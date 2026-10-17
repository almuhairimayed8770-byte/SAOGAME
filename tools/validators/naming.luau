--!strict
--[[
	Naming validator (section 3, D-014): no name from the source franchise may appear anywhere in
	the repository. Scans every text file under the repo (src, tests, tools, docs, places,
	.github, the root files and any other directory) except .git, build output, package folders,
	docs/GAME_SPEC.md and the blocklist itself, lowercases each file, and reports file:line for
	every hit. Entries marked `whole` match only as a whole word.

	Files are discovered only through ctx.listFiles("") so a test can plant a hit in a string.
]]

local blocklist = require("../naming/blocklist")

type Entry = { term: string, whole: boolean }

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local SKIP_DIRECTORIES = {
	[".git"] = true,
	["build"] = true,
	["Packages"] = true,
	["ServerPackages"] = true,
	["DevPackages"] = true,
	[".lune"] = true,
	["node_modules"] = true,
}

local SKIP_FILES = {
	["docs/GAME_SPEC.md"] = true,
	["tools/naming/blocklist.luau"] = true,
}

local BINARY_EXTENSIONS = {
	rbxl = true,
	rbxlx = true,
	rbxm = true,
	rbxmx = true,
	png = true,
	jpg = true,
	jpeg = true,
	gif = true,
	webp = true,
	mp4 = true,
	mp3 = true,
	ogg = true,
	wav = true,
	ttf = true,
	otf = true,
	woff = true,
	woff2 = true,
	zip = true,
	lock = true,
}

local function escapePattern(text: string): string
	return (text:gsub("%W", "%%%0"))
end

-- A compiled matcher per entry: a plain substring or a frontier-bounded pattern.
local function compile(entry: Entry): (string) -> number?
	if entry.whole then
		local pattern = "%f[%w_]" .. escapePattern(entry.term) .. "%f[^%w_]"
		return function(text: string): number?
			return (string.find(text, pattern))
		end
	end
	local term = entry.term
	return function(text: string): number?
		return (string.find(text, term, 1, true))
	end
end

local matchers: { { entry: Entry, find: (string) -> number? } } = {}
for _, entry in blocklist :: { Entry } do
	table.insert(matchers, { entry = entry, find = compile(entry) })
end

local function shouldScan(path: string): boolean
	if SKIP_FILES[path] then
		return false
	end
	local first = path:match("^([^/]+)/")
	if first and SKIP_DIRECTORIES[first] then
		return false
	end
	local extension = path:match("%.([%w]+)$")
	if extension and BINARY_EXTENSIONS[extension:lower()] then
		return false
	end
	return true
end

return function(ctx: Context): { string }
	local problems = {}
	local files = ctx.listFiles("")
	for _, path in files do
		if not shouldScan(path) then
			continue
		end
		local ok, content = pcall(ctx.readFile, path)
		if not ok then
			continue
		end
		if content:find("\0", 1, true) then
			continue -- binary
		end
		local lowered = content:lower()
		for _, matcher in matchers do
			if matcher.find(lowered) == nil then
				continue -- the cheap whole-file check first; most files never hit
			end
			-- Report every line that hits, not only the first.
			local lineIndex = 0
			for line in (lowered .. "\n"):gmatch("(.-)\n") do
				lineIndex += 1
				if matcher.find(line) then
					table.insert(
						problems,
						("%s:%d: blocklisted term '%s'%s"):format(
							path,
							lineIndex,
							matcher.entry.term,
							if matcher.entry.whole then " (whole word)" else ""
						)
					)
				end
			end
		end
	end
	table.sort(problems)
	return problems
end
