--!strict
--[[
	Harness: loads game modules from src/ under Lune through a virtual DataModel.

	Usage in a spec or validator:
		local Easing = Harness.load("src/shared/util/Easing")
		local combat = Harness.load("src/shared/data/combat")
		Harness.stubService("RunService", { IsServer = function() return true end })

	Modules see `script`, `game`, `workspace`, the Roblox datatypes, `Random`, `task` and `tick`,
	so unchanged game code runs here. Anything that needs the engine itself (rendering, physics,
	real remotes) is covered by run-in-roblox smoke scripts instead; Net's send and receive paths run
	under Lune against recording fake remotes (tests/net/Net.spec.luau).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local VirtualTree = require("./VirtualTree")
local RandomShim = require("./RandomShim")

local Harness = {}

local repoRoot: string = nil :: any
local game: any = nil
local workspaceNode: any = nil
local moduleCache: { [any]: any } = {}
local loading: { [any]: boolean } = {}
local baseEnv: { [string]: any } = nil :: any
local logs: { string } = {}

local SOURCE_ROOTS = {
	{ prefix = "src/shared", service = "ReplicatedStorage", folder = "Shared" },
	{ prefix = "src/server", service = "ServerScriptService", folder = "Server" },
	{ prefix = "src/client", service = "StarterPlayer", folder = "StarterPlayerScripts", sub = "Client" },
}

local function findRepoRoot(): string
	local candidates = { ".", "..", "../..", "../../.." }
	for _, candidate in candidates do
		if fs.isFile(candidate .. "/default.project.json") and fs.isDir(candidate .. "/src") then
			return candidate
		end
	end
	error("Harness: could not find the repository root (run from the repo root or a subdirectory)")
end

local function buildGame()
	game = VirtualTree.newNode("game", "DataModel", nil)
	local replicated = VirtualTree.adopt(game, VirtualTree.newNode("ReplicatedStorage", "ReplicatedStorage", nil))
	VirtualTree.adopt(replicated, VirtualTree.fromDirectory(repoRoot .. "/src/shared", "Shared"))
	local serverScripts =
		VirtualTree.adopt(game, VirtualTree.newNode("ServerScriptService", "ServerScriptService", nil))
	VirtualTree.adopt(serverScripts, VirtualTree.fromDirectory(repoRoot .. "/src/server", "Server"))
	local starterPlayer = VirtualTree.adopt(game, VirtualTree.newNode("StarterPlayer", "StarterPlayer", nil))
	local starterScripts =
		VirtualTree.adopt(starterPlayer, VirtualTree.newNode("StarterPlayerScripts", "StarterPlayerScripts", nil))
	VirtualTree.adopt(starterScripts, VirtualTree.fromDirectory(repoRoot .. "/src/client", "Client"))
	workspaceNode = VirtualTree.adopt(game, VirtualTree.newNode("Workspace", "Workspace", nil))
	for _, serviceName in { "Players", "RunService", "Lighting", "ReplicatedFirst", "ServerStorage", "SoundService" } do
		VirtualTree.adopt(game, VirtualTree.newNode(serviceName, serviceName, nil))
	end
end

local function wrappedTypeof(value: any): string
	if VirtualTree.isNode(value) then
		return "Instance"
	end
	if typeof(value) == "table" and getmetatable(value) == RandomShim then
		return "Random"
	end
	return typeof(value)
end

local function buildBaseEnv()
	baseEnv = {
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		BrickColor = roblox.BrickColor,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		-- The engine refuses NumberRange.new(min, max) with min > max ("invalid range"); Lune swaps
		-- the ends without a word, so every spec gets the engine's rule.
		NumberRange = {
			new = function(first: number, last: number?): any
				if last == nil then
					return roblox.NumberRange.new(first)
				end
				if first > last then
					error(("NumberRange.new(%s, %s): invalid range"):format(tostring(first), tostring(last)), 2)
				end
				return roblox.NumberRange.new(first, last)
			end,
		},
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		Rect = roblox.Rect,
		Ray = roblox.Ray,
		Font = roblox.Font,
		Enum = roblox.Enum,
		Instance = roblox.Instance,
		Random = RandomShim,
		task = task,
		tick = os.clock,
		typeof = wrappedTypeof,
		game = game,
		workspace = workspaceNode,
		warn = function(...: any)
			local parts = {}
			for _, value in { ... } do
				table.insert(parts, tostring(value))
			end
			table.insert(logs, "[warn] " .. table.concat(parts, " "))
		end,
	}
end

local function ensureBuilt()
	if game ~= nil then
		return
	end
	repoRoot = findRepoRoot()
	buildGame()
	buildBaseEnv()
end

local harnessRequire: (target: any) -> any

--- Loads (and caches) a ModuleScript node, running it in the harness environment.
function Harness.loadModule(node: any): any
	ensureBuilt()
	if not VirtualTree.isNode(node) then
		error("Harness.loadModule expects a virtual Instance, got " .. typeof(node), 2)
	end
	if rawget(node, "ClassName") ~= "ModuleScript" then
		error(("Harness: %s is a %s, not a ModuleScript"):format(node:GetFullName(), rawget(node, "ClassName")), 2)
	end
	local cached = moduleCache[node]
	if cached ~= nil then
		return cached
	end
	if loading[node] then
		error("Harness: cyclic require of " .. node:GetFullName(), 2)
	end
	local path = VirtualTree.sourcePath(node) :: string
	local source = fs.readFile(path)
	-- Lune copies the environment table when injecting globals, so a metatable fallback is lost;
	-- build a flat table per module instead.
	local env = Harness.environment()
	env.script = node
	env.require = harnessRequire
	local chunk = luau.load(source, { debugName = path, environment = env :: any })
	loading[node] = true
	local ok, result = pcall(chunk)
	loading[node] = nil
	if not ok then
		error(("Harness: error loading %s: %s"):format(path, tostring(result)), 2)
	end
	if result == nil then
		error(("Harness: %s did not return a value"):format(path), 2)
	end
	moduleCache[node] = result
	return result
end

harnessRequire = function(target: any): any
	if typeof(target) == "string" then
		if target:sub(1, 6) == "@lune/" then
			return require(target) :: any
		end
		error(
			("Harness: string require '%s' is not supported in game code (use Instance paths, D-002)"):format(target),
			2
		)
	end
	return Harness.loadModule(target)
end

--- Resolves a source path like "src/shared/util/Easing" to its virtual node.
function Harness.node(sourcePath: string): any
	ensureBuilt()
	local cleaned = sourcePath:gsub("%.luau$", ""):gsub("^%./", "")
	for _, root in SOURCE_ROOTS do
		if cleaned:sub(1, #root.prefix) == root.prefix then
			local node = game:GetService(root.service)[root.folder]
			if root.sub then
				node = node[root.sub]
			end
			local rest = cleaned:sub(#root.prefix + 2)
			if rest ~= "" then
				for segment in rest:gmatch("[^/]+") do
					node = node:FindFirstChild(segment)
					if node == nil then
						error(("Harness: no module at '%s' (missing '%s')"):format(sourcePath, segment), 2)
					end
				end
			end
			return node
		end
	end
	error(("Harness: path '%s' is not under src/shared, src/server or src/client"):format(sourcePath), 2)
end

--- Loads a module by source path, e.g. Harness.load("src/shared/data/combat").
function Harness.load(sourcePath: string): any
	return Harness.loadModule(Harness.node(sourcePath))
end

--- A fresh copy of the base environment (datatypes, game, Random, task...) for custom chunks.
function Harness.environment(): { [string]: any }
	ensureBuilt()
	return table.clone(baseEnv)
end

--- Returns the virtual DataModel.
function Harness.game(): any
	ensureBuilt()
	return game
end

--- Registers (or replaces) a service stub; fields on `stub` become members of the service node.
function Harness.stubService(name: string, stub: { [string]: any }): any
	ensureBuilt()
	local existing = game:FindFirstChild(name)
	local node = existing or VirtualTree.adopt(game, VirtualTree.newNode(name, name, nil))
	for key, value in stub do
		node[key] = value
	end
	return node
end

--- Clears the module cache so the next load re-runs module bodies (fresh state).
function Harness.reset()
	table.clear(moduleCache)
	table.clear(loading)
	table.clear(logs)
end

--- Warnings captured from modules (the harness replaces `warn`).
function Harness.warnings(): { string }
	return table.clone(logs)
end

--- Repository root as a relative path from the current working directory.
function Harness.repoRoot(): string
	ensureBuilt()
	return repoRoot
end

--- Lists every source file under a repo-relative directory (recursive), as repo-relative paths.
function Harness.listFiles(relativeDirectory: string, pattern: string?): { string }
	ensureBuilt()
	local results = {}
	local function walk(directory: string, relative: string)
		for _, entry in fs.readDir(directory) do
			local full = directory .. "/" .. entry
			local rel = if relative == "" then entry else relative .. "/" .. entry
			if fs.isDir(full) then
				walk(full, rel)
			elseif pattern == nil or entry:match(pattern) then
				table.insert(results, rel)
			end
		end
	end
	walk(repoRoot .. "/" .. relativeDirectory, relativeDirectory)
	table.sort(results)
	return results
end

--- Reads a repo-relative file.
function Harness.readFile(relativePath: string): string
	ensureBuilt()
	return fs.readFile(repoRoot .. "/" .. relativePath)
end

return Harness
