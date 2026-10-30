--!strict
--[[
	Pose server (section 10: the PoseEditor "writes the data table back to the file").

		lune run tools/pose-server.luau [--port N]

	A tiny HTTP server on data/dev.luau poseServer.host:port that the PoseEditor plugin talks to
	from Studio (HttpService; "Allow HTTP Requests" must be on, see docs/STUDIO_TASKS.md):

		GET  /health         -> { ok, port, clipsDirectory }
		GET  /clips          -> { ids = { "player/OneHandedSword/Horizontal", ... } }
		GET  /clips/<id>     -> the clip module's source (text/plain)
		POST /clips/<id>     -> body: Luau source of the clip module. The server checks the id
		                        (2..4 alphanumeric segments, no dots), parses the body with
		                        Serialize.parse (no code runs) and requires clip.id == <id>, writes
		                        src/shared/clips/<id>.luau, runs stylua on it, runs the data
		                        validators in a child Lune and answers
		                        { ok, id, path, bytes, stylua, problems = { ... } } where problems
		                        are the validator lines that mention the clip.

	Anything else is 404. Bodies above poseServer.maxBodyBytes are refused (413). The server only
	ever writes under src/shared/clips/ and only files whose id passed Dev.isClipId.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local Harness = require("../tests/_harness/Harness")

local root = Harness.repoRoot()
local Dev = Harness.load("src/shared/data/dev")
local Server = Dev.poseServer

-- Serialize has no requires: load it as a plain chunk.
local Serialize = luau.load(fs.readFile(root .. "/tools/PoseEditor/src/Serialize.luau"), {
	debugName = "Serialize",
})()

local port: number = Server.port
for index, arg in process.args do
	if arg == "--port" and process.args[index + 1] ~= nil then
		port = tonumber(process.args[index + 1]) or port
	end
end

local clipsDirectory: string = Dev.review.clipsDirectory
local CLIPS_ROUTE: string = Server.clipsRoute

type Response = { status: number, headers: { [string]: string }?, body: string? }

local function json(status: number, value: any): Response
	return {
		status = status,
		headers = { ["content-type"] = "application/json" },
		body = serde.encode("json", value),
	}
end

local function text(status: number, body: string): Response
	return { status = status, headers = { ["content-type"] = "text/plain; charset=utf-8" }, body = body }
end

local function log(line: string)
	stdio.write(("[pose-server] %s\n"):format(line))
end

local function clipPath(id: string): string
	return ("%s/%s/%s.luau"):format(root, clipsDirectory, id)
end

local function listClipIds(): { string }
	local ids = {}
	for _, file in Harness.listFiles(clipsDirectory, "%.luau$") do
		local id = file:match("^" .. clipsDirectory:gsub("%p", "%%%0") .. "/(.-)%.luau$")
		if id ~= nil then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local function ensureDirectory(path: string)
	local parent = path:match("^(.*)/[^/]+$")
	if parent ~= nil and not fs.isDir(parent) then
		ensureDirectory(parent)
		fs.writeDir(parent)
	end
end

-- Runs a program from the repo root; returns ok, combined output. Lune 0.8 calls this
-- process.spawn, Lune 0.9+ process.exec.
local exec: any = (process :: any).exec or (process :: any).spawn

local function run(program: string, args: { string }): (boolean, string)
	if exec == nil then
		return false, "this Lune has no process.exec / process.spawn"
	end
	local ok, result = pcall(exec, program, args, { cwd = root })
	if not ok then
		return false, ("%s is not installed (%s)"):format(program, tostring(result))
	end
	local spawned = result :: any
	return spawned.ok == true, (spawned.stdout or "") .. (spawned.stderr or "")
end

-- The validator lines that mention the clip id (or its file path).
local function validatorProblems(id: string): ({ string }, boolean)
	local ok, output = run("lune", { "run", "tools/validate.luau" })
	local problems = {}
	local path = ("%s/%s.luau"):format(clipsDirectory, id)
	for line in output:gmatch("[^\n]+") do
		local problem = line:match("^%s*%-%s*(.+)$")
		if problem ~= nil and (problem:find(id, 1, true) or problem:find(path, 1, true)) then
			table.insert(problems, problem)
		end
	end
	return problems, ok
end

local function handleGet(path: string): Response
	if path == Server.healthRoute then
		return json(200, { ok = true, port = port, clipsDirectory = clipsDirectory })
	end
	if path == CLIPS_ROUTE then
		return json(200, { ids = listClipIds() })
	end
	local id = path:match("^" .. CLIPS_ROUTE:gsub("%p", "%%%0") .. "/(.+)$")
	if id ~= nil then
		if not Dev.isClipId(id) then
			return json(400, { ok = false, error = "bad clip id" })
		end
		local file = clipPath(id)
		if not fs.isFile(file) then
			return json(404, { ok = false, error = "no such clip" })
		end
		return text(200, fs.readFile(file))
	end
	return json(404, { ok = false, error = "not found" })
end

local function handlePost(path: string, body: string): Response
	local id = path:match("^" .. CLIPS_ROUTE:gsub("%p", "%%%0") .. "/(.+)$")
	if id == nil then
		return json(404, { ok = false, error = "not found" })
	end
	if not Dev.isClipId(id) then
		return json(400, { ok = false, error = "bad clip id (2..4 alphanumeric segments, no dots)" })
	end
	if #body > Server.maxBodyBytes then
		return json(413, { ok = false, error = ("body over %d bytes"):format(Server.maxBodyBytes) })
	end
	if #body == 0 then
		return json(400, { ok = false, error = "empty body" })
	end
	local parsed, clip = pcall(Serialize.parse, body)
	if not parsed then
		return json(422, { ok = false, error = ("not a clip module: %s"):format(tostring(clip)) })
	end
	if clip.id ~= id then
		return json(
			422,
			{ ok = false, error = ("clip.id %s does not match the route %s"):format(tostring(clip.id), id) }
		)
	end
	local shape = Serialize.shapeProblems(clip)
	if #shape > 0 then
		return json(422, { ok = false, error = "clip shape", problems = shape })
	end

	local file = clipPath(id)
	ensureDirectory(file)
	fs.writeFile(file, body)
	log(("wrote %s (%d bytes)"):format(file, #body))

	local styluaOk, styluaOutput = run("stylua", { file })
	local styluaNote = if styluaOk then "ok" else "failed: " .. styluaOutput:gsub("%s+$", "")
	local problems, validatorsOk = validatorProblems(id)
	local relative = ("%s/%s.luau"):format(clipsDirectory, id)
	log(
		("%s: stylua %s, %d problem(s), validators %s"):format(
			id,
			styluaNote,
			#problems,
			if validatorsOk then "green" else "red"
		)
	)
	return json(200, {
		ok = styluaOk and #problems == 0,
		id = id,
		path = relative,
		bytes = #body,
		stylua = styluaNote,
		problems = problems,
		validatorsGreen = validatorsOk,
	})
end

local function handle(request: any): Response
	local path: string = tostring(request.path)
	local method: string = tostring(request.method):upper()
	local ok, response = pcall(function(): Response
		if method == "GET" then
			return handleGet(path)
		elseif method == "POST" then
			return handlePost(path, tostring(request.body or ""))
		end
		return json(405, { ok = false, error = "method not allowed" })
	end)
	if not ok then
		log(("error on %s %s: %s"):format(method, path, tostring(response)))
		return json(500, { ok = false, error = tostring(response) })
	end
	return response :: Response
end

local started, result = pcall(function()
	return net.serve(port, { address = "http://" .. Server.host, handleRequest = handle } :: any)
end)
if not started then
	-- Older Lune: no address option; bind the default address.
	started, result = pcall(net.serve, port, handle :: any)
end
if not started then
	stdio.ewrite(("[pose-server] could not listen on %s:%d: %s\n"):format(Server.host, port, tostring(result)))
	process.exit(1)
end
log(
	("listening on http://%s:%d  (%d clips under %s; Ctrl+C to stop)"):format(
		Server.host,
		port,
		#listClipIds(),
		clipsDirectory
	)
)
