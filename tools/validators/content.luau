--!strict
--[[
	Content validator: no placeholder asset id reaches an engine property, every asset id lives in
	src/shared/data, each asset a data field hands to a property is of the kind that property
	takes, and the place projects put each instance where the engine accepts it. (The 2026-10-23
	Play test logged "Failed to load sound rbxassetid://0" for Sounds whose SoundId held id 0,
	and "Cloud instance must exist under Terrain node" for a Clouds under Lighting.)

	Source rules, over every .luau under src/ outside src/shared/data, comments stripped:
	- `placeholderId` and the literal rbxassetid://0 appear only in a comparison (== or ~=):
	  writing id 0 into a SoundId, Texture or Image already makes the engine fetch it and fail.
	- No rbxassetid://<digits> literal: asset ids live in src/shared/data.
	- A write to a content property (SoundId, Texture, TextureId, Image, MeshId, AnimationId, the
	  Sky's textures...) assigns "" or a value checked against placeholders on that line or the
	  GUARD_LINES lines before it (`isPlaceholder(`, a `.placeholder` field, `isReal(`,
	  `isReady(`). A write whose check sits in its caller is listed in GUARDED_ELSEWHERE with
	  the reason.
	- `Assets.url(` comes with an `Assets.isReady(` check on that line or the GUARD_LINES lines
	  before it (Assets.url returns rbxassetid://0 for a placeholder).

	Project rules, over default.project.json and places/*.project.json:
	- A Clouds is a direct child of Workspace.Terrain, with lighting.luau's clouds cover and
	  density; a Sky, an Atmosphere or a post effect is a direct child of Lighting.
	- No project node sets a content property (ids live in src/shared/data).

	Asset kinds: every field in a src/shared/data table named like `textureAsset(s)`,
	`meshAsset(s)`, `soundAsset(s)`, `fontAsset(s)` or `animationAsset(s)` (any prefix, any
	case) names assets.luau entries of that kind; a Texture property fed a Mesh or a Decal id
	logs "Asset type does not match requested type".
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local GUARD_LINES = 3
local SOURCE_DIRECTORY = "src"
local DATA_PREFIX = "src/shared/data/"
local ASSETS_MODULE = "src/shared/data/assets.luau"
local PLACEHOLDER_TOKENS = { "placeholderId", "rbxassetid://0" }

-- Engine properties that take an asset id.
local CONTENT_PROPERTIES = {
	"SoundId",
	"Texture",
	"TextureId",
	"TextureID",
	"Image",
	"AnimationId",
	"MeshId",
	"SkyboxBk",
	"SkyboxDn",
	"SkyboxFt",
	"SkyboxLf",
	"SkyboxRt",
	"SkyboxUp",
	"SunTextureId",
	"MoonTextureId",
	"ColorMap",
	"NormalMap",
	"MetalnessMap",
	"RoughnessMap",
	"ShirtTemplate",
	"PantsTemplate",
	"Graphic",
}

-- What makes a content write safe: a check against placeholders near it.
local GUARD_PATTERNS = { "isPlaceholder%(", "%.placeholder%f[^%w_]", "isReal%(", "isReady%(" }

-- Content writes whose placeholder check lives in the caller: file -> property -> why.
local GUARDED_ELSEWHERE: { [string]: { [string]: string } } = {
	["src/client/choreo/Choreo.luau"] = {
		AnimationId = "Choreo.play hands playRbx only clip ids that start with rbxassetid://, and the clips "
			.. "validator resolves every clip id in data to a clip file",
	},
}

-- Instance classes the engine accepts only under one parent (the path from the DataModel).
local REQUIRED_PARENT: { [string]: string } = {
	Clouds = "Workspace.Terrain",
	Sky = "Lighting",
	Atmosphere = "Lighting",
	BloomEffect = "Lighting",
	ColorCorrectionEffect = "Lighting",
	SunRaysEffect = "Lighting",
	DepthOfFieldEffect = "Lighting",
	BlurEffect = "Lighting",
}

-- Data field name endings (lower case, singular) and the asset kind they name.
local KIND_FIELDS = {
	{ suffix = "textureasset", kind = "Texture" },
	{ suffix = "meshasset", kind = "Mesh" },
	{ suffix = "soundasset", kind = "Sound" },
	{ suffix = "fontasset", kind = "Font" },
	{ suffix = "animationasset", kind = "Animation" },
}

-- The code of each line: block comments and line comments removed (strings kept).
local function codeLines(source: string): { string }
	local lines = {}
	local inBlock = false
	for line in (source .. "\n"):gmatch("(.-)\n") do
		local code = line
		if inBlock then
			local close = code:find("]]", 1, true)
			if close == nil then
				table.insert(lines, "")
				continue
			end
			code = code:sub(close + 2)
			inBlock = false
		end
		local open = code:find("--[[", 1, true)
		if open ~= nil then
			local close = code:find("]]", open + 4, true)
			if close == nil then
				inBlock = true
				code = code:sub(1, open - 1)
			else
				code = code:sub(1, open - 1) .. code:sub(close + 2)
			end
		end
		local comment = code:find("--", 1, true)
		if comment ~= nil then
			code = code:sub(1, comment - 1)
		end
		table.insert(lines, code)
	end
	return lines
end

local function escape(text: string): string
	return (text:gsub("%p", "%%%0"))
end

-- True when every use of `token` on the line is one side of an == or ~= comparison.
local function onlyCompared(line: string, token: string): boolean
	local escaped = escape(token)
	local uses = select(2, line:gsub(escaped, ""))
	local compared = select(2, line:gsub("[=~]=%s*[%w_%.]*" .. escaped, ""))
		+ select(2, line:gsub(escaped .. "[%w_]*%s*[=~]=", ""))
	return compared >= uses
end

local function guarded(lines: { string }, index: number, patterns: { string }): boolean
	for back = math.max(1, index - GUARD_LINES), index do
		for _, pattern in patterns do
			if lines[back]:find(pattern) ~= nil then
				return true
			end
		end
	end
	return false
end

-- The content property a line writes and the text it assigns, or nil.
local function contentWrite(line: string): (string?, string?)
	for _, property in CONTENT_PROPERTIES do
		local value = line:match("%." .. property .. "%s*=%s*([^=].*)$")
		if value ~= nil then
			return property, value
		end
	end
	return nil, nil
end

local function isEmptyString(value: string): boolean
	return value:match('^""') ~= nil or value:match("^''") ~= nil
end

local function checkSource(ctx: Context, problem: (string, ...any) -> ())
	for _, file in ctx.listFiles(SOURCE_DIRECTORY, "%.luau$") do
		if file:sub(1, #DATA_PREFIX) == DATA_PREFIX then
			continue
		end
		local lines = codeLines(ctx.readFile(file))
		local elsewhere = GUARDED_ELSEWHERE[file] or {}
		for index, line in lines do
			local where = ("%s:%d"):format(file, index)
			for _, token in PLACEHOLDER_TOKENS do
				if line:find(token, 1, true) and not onlyCompared(line, token) then
					problem(
						"%s: a placeholder id is only ever compared, never written: %s",
						where,
						(line:gsub("^%s+", ""))
					)
				end
			end
			if line:find("rbxassetid://%d") then
				problem("%s: an asset id literal belongs in src/shared/data", where)
			end
			if line:find("Assets.url(", 1, true) and not guarded(lines, index, { "Assets%.isReady%(" }) then
				problem("%s: Assets.url without an Assets.isReady check (a placeholder's url is rbxassetid://0)", where)
			end
			local property, value = contentWrite(line)
			if
				property ~= nil
				and value ~= nil
				and not isEmptyString(value)
				and elsewhere[property] == nil
				and not guarded(lines, index, GUARD_PATTERNS)
			then
				problem(
					'%s: %s gets a value nothing checked against placeholders (write "" for a placeholder)',
					where,
					property
				)
			end
		end
	end
end

local function walkProject(
	node: any,
	path: string,
	visit: (className: string, path: string, parent: string, node: any) -> ()
)
	for key, child in node do
		if typeof(key) == "string" and key:sub(1, 1) ~= "$" and typeof(child) == "table" then
			local childPath = path .. "." .. key
			visit(child["$className"] or key, childPath, path, child)
			walkProject(child, childPath, visit)
		end
	end
end

local function checkProjects(ctx: Context, problem: (string, ...any) -> ())
	local serde = require("@lune/serde") :: any
	local Lighting = ctx.load("src/shared/data/lighting")
	local projects = { "default.project.json" }
	for _, file in ctx.listFiles("places", "%.project%.json$") do
		table.insert(projects, file)
	end
	for _, projectPath in projects do
		local project = serde.decode("json", ctx.readFile(projectPath))
		walkProject(project.tree, "game", function(className: string, path: string, parent: string, node: any)
			local want = REQUIRED_PARENT[className]
			if want ~= nil and parent ~= "game." .. want then
				problem("%s: %s (%s) must be a direct child of %s", projectPath, path, className, want)
			end
			local properties = node["$properties"]
			if typeof(properties) ~= "table" then
				return
			end
			for _, property in CONTENT_PROPERTIES do
				if properties[property] ~= nil then
					problem("%s: %s sets %s; asset ids live in src/shared/data", projectPath, path, property)
				end
			end
			if className == "Clouds" then
				for key, field in { Cover = "cover", Density = "density" } do
					if properties[key] ~= Lighting.clouds[field] then
						problem(
							"%s: %s.%s is %s, lighting.luau clouds.%s is %s",
							projectPath,
							path,
							key,
							tostring(properties[key]),
							field,
							tostring(Lighting.clouds[field])
						)
					end
				end
			end
		end)
	end
end

-- The asset kind a data field names, from its name (`textureAssets` -> "Texture"), or nil.
local function kindOfField(key: string): string?
	local name = (key:lower():gsub("s$", ""))
	for _, field in KIND_FIELDS do
		if name:sub(-#field.suffix) == field.suffix then
			return field.kind
		end
	end
	return nil
end

local function checkKinds(ctx: Context, problem: (string, ...any) -> ())
	local Assets = ctx.load("src/shared/data/assets")
	local function checkName(label: string, kind: string, name: any)
		local def = if typeof(name) == "string" then Assets.registry[name] else nil
		if def == nil then
			problem("%s: '%s' is not in assets.luau", label, tostring(name))
		elseif def.kind ~= kind then
			problem("%s: '%s' is a %s; this field feeds a %s property", label, name, tostring(def.kind), kind)
		end
	end
	local visited: { [any]: boolean } = {}
	local function walk(value: any, label: string)
		if typeof(value) ~= "table" or visited[value] then
			return
		end
		visited[value] = true
		local keys = {}
		for key in value do
			table.insert(keys, key)
		end
		table.sort(keys, function(a: any, b: any): boolean
			return tostring(a) < tostring(b)
		end)
		for _, key in keys do
			local child = value[key]
			local childLabel = label .. "." .. tostring(key)
			local kind = if typeof(key) == "string" then kindOfField(key) else nil
			if kind == nil then
				walk(child, childLabel)
			elseif typeof(child) == "table" then
				for inner, name in child do
					checkName(childLabel .. "." .. tostring(inner), kind, name)
				end
			else
				checkName(childLabel, kind, child)
			end
		end
	end
	for _, file in ctx.listFiles("src/shared/data", "%.luau$") do
		if file == ASSETS_MODULE then
			continue
		end
		local name = file:match("^src/shared/data/(.+)%.luau$") :: string
		walk(ctx.load("src/shared/data/" .. name), name)
	end
end

return function(ctx: Context): { string }
	local problems = {}
	local function problem(format: string, ...: any)
		table.insert(problems, string.format(format, ...))
	end
	checkSource(ctx, problem)
	checkProjects(ctx, problem)
	checkKinds(ctx, problem)
	return problems
end
