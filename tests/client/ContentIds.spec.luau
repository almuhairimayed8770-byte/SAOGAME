--!strict
--[[
	No placeholder asset id reaches an engine property, and the sky's Clouds sits where the engine
	takes it. The 2026-10-23 Play test logged four "Failed to load sound rbxassetid://0" lines (the
	SoundId of MusicDirector's Stem_* Sounds: writing an id is enough for the engine to fetch it)
	and "Cloud instance must exist under Terrain node" (a Clouds under Lighting).

	The audio modules load here with a recording Instance.new: every content property they write
	(SoundId, Texture, Image...) is kept, and no write may be a placeholder id. The Playground
	builder makes the sky's Clouds under workspace.Terrain from lighting.luau.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Sfx = Harness.load("src/shared/data/sfx")
local LightingData = Harness.load("src/shared/data/lighting")
local PlaygroundBuilder = Harness.load("src/server/world/PlaygroundBuilder")

local CONTENT_PROPERTIES = {
	SoundId = true,
	Texture = true,
	TextureId = true,
	TextureID = true,
	Image = true,
	AnimationId = true,
	MeshId = true,
}
local RECORDED_MODULES = { "src/client/audio/MusicDirector", "src/client/audio/SfxPool" }

type Write = { className: string, name: string, key: string, value: string }
type Recorder = {
	writes: { Write },
	created: { any },
	load: (sourcePath: string) -> any,
}

-- A stand-in for one engine Instance: reads and method calls go to a real Lune Instance, and a
-- write to a content property is recorded. Parent and Instance-valued writes are not forwarded
-- (a Lune Instance cannot be parented to the harness's virtual services).
local function recordedInstance(recorder: Recorder, className: string): any
	local real = roblox.Instance.new(className)
	local standIn = setmetatable({}, {
		__index = function(_self: any, key: string): any
			local value = (real :: any)[key]
			if typeof(value) == "function" then
				return function(_caller: any, ...: any): any
					return value(real, ...)
				end
			end
			return value
		end,
		__newindex = function(_self: any, key: string, value: any)
			if CONTENT_PROPERTIES[key] then
				table.insert(recorder.writes, { className = className, name = real.Name, key = key, value = value })
			end
			if key == "Parent" or typeof(value) == "table" then
				return
			end
			(real :: any)[key] = value
		end,
	})
	table.insert(recorder.created, standIn)
	return standIn
end

-- Fresh copies of MusicDirector and SfxPool (their module state starts over) whose Instance.new
-- records; every other module is the harness's shared copy.
local function newRecorder(): Recorder
	local recorder: Recorder = { writes = {}, created = {}, load = nil :: any }
	local cache: { [any]: any } = {}
	local recordedRequire: (target: any) -> any
	local function loadRecorded(node: any, sourcePath: string): any
		if cache[node] == nil then
			local env = Harness.environment()
			env.Instance = {
				new = function(className: string): any
					return recordedInstance(recorder, className)
				end,
			}
			env.script = node
			env.require = recordedRequire
			local path = Harness.repoRoot() .. "/" .. sourcePath .. ".luau"
			cache[node] = luau.load(fs.readFile(path), { debugName = path, environment = env :: any })()
		end
		return cache[node]
	end
	recordedRequire = function(target: any): any
		for _, sourcePath in RECORDED_MODULES do
			if Harness.node(sourcePath) == target then
				return loadRecorded(target, sourcePath)
			end
		end
		return Harness.loadModule(target)
	end
	recorder.load = function(sourcePath: string): any
		return recordedRequire(Harness.node(sourcePath))
	end
	return recorder
end

local function isPlaceholderId(value: string): boolean
	return value == Sfx.placeholderId or string.match(value, "^rbxassetid://0+$") ~= nil
end

local function placeholderWrites(recorder: Recorder): { string }
	local found = {}
	for _, write in recorder.writes do
		if isPlaceholderId(tostring(write.value)) then
			table.insert(found, ("%s %s.%s = %s"):format(write.className, write.name, write.key, tostring(write.value)))
		end
	end
	table.sort(found)
	return found
end

local function lastWrite(recorder: Recorder, name: string, key: string): string?
	local value: string? = nil
	for _, write in recorder.writes do
		if write.name == name and write.key == key then
			value = write.value
		end
	end
	return value
end

local function createdNamed(recorder: Recorder, name: string): number
	local count = 0
	for _, standIn in recorder.created do
		if standIn.Name == name then
			count += 1
		end
	end
	return count
end

-- Runs `body` with sfx.music.stemIds changed, then puts the data back.
local function withStemIds(ids: { [string]: string }, body: () -> ())
	local saved = table.clone(Sfx.music.stemIds)
	for name, id in ids do
		Sfx.music.stemIds[name] = id
	end
	local ok, err = pcall(body)
	table.clear(Sfx.music.stemIds)
	for name, id in saved do
		Sfx.music.stemIds[name] = id
	end
	if not ok then
		error(err, 0)
	end
end

local REAL_STEM = "rbxassetid://1234567890"

describe("MusicDirector writes no placeholder id", function()
	it("keeps every stem id in sfx.luau music.stemIds, one per stem", function()
		local names = {}
		for name in Sfx.music.stemIds do
			table.insert(names, name)
		end
		table.sort(names)
		local stems = table.clone(Sfx.music.stems)
		table.sort(stems)
		expect(names).toEqual(stems)
	end)

	it("makes no stem Sound at start while every stem id is a placeholder", function()
		local recorder = newRecorder()
		local MusicDirector = recorder.load("src/client/audio/MusicDirector")
		MusicDirector.start()
		MusicDirector.setState("Combat")
		MusicDirector.update()
		MusicDirector.stop()
		expect(placeholderWrites(recorder)).toEqual({})
		for _, name in Sfx.music.stems do
			expect(createdNamed(recorder, "Stem_" .. name)).toBe(0)
		end
	end)

	it("applies the data's stem ids at start: a real id gets its Sound, a placeholder none", function()
		withStemIds({ combat = REAL_STEM }, function()
			local recorder = newRecorder()
			local MusicDirector = recorder.load("src/client/audio/MusicDirector")
			MusicDirector.start()
			MusicDirector.stop()
			expect(createdNamed(recorder, "Stem_combat")).toBe(1)
			expect(lastWrite(recorder, "Stem_combat", "SoundId")).toBe(REAL_STEM)
			expect(createdNamed(recorder, "Stem_ambient")).toBe(0)
			expect(placeholderWrites(recorder)).toEqual({})
		end)
	end)

	it("clears a stem's SoundId to no asset when setStems puts a placeholder back", function()
		local recorder = newRecorder()
		local MusicDirector = recorder.load("src/client/audio/MusicDirector")
		MusicDirector.setStems({ explore = REAL_STEM })
		expect(lastWrite(recorder, "Stem_explore", "SoundId")).toBe(REAL_STEM)
		MusicDirector.setStems({ explore = Sfx.placeholderId })
		MusicDirector.stop()
		expect(lastWrite(recorder, "Stem_explore", "SoundId")).toBe("")
		expect(createdNamed(recorder, "Stem_explore")).toBe(1)
		expect(placeholderWrites(recorder)).toEqual({})
	end)
end)

describe("SfxPool writes no placeholder id", function()
	it("gives a placeholder loop bed a Sound with no asset", function()
		local recorder = newRecorder()
		local SfxPool = recorder.load("src/client/audio/SfxPool")
		local beds = 0
		for name, entry in Sfx.families.ambience.entries do
			if entry.placeholder then
				beds += 1
				SfxPool.loop("ambience." .. name, 1)
				SfxPool.loop("ambience." .. name, 0)
				expect(lastWrite(recorder, "ambience." .. name, "SoundId")).toBe("")
			end
		end
		expect(beds).toBeGreaterThan(0)
		expect(placeholderWrites(recorder)).toEqual({})
	end)

	it("still gives a real loop bed its own id", function()
		local recorder = newRecorder()
		local SfxPool = recorder.load("src/client/audio/SfxPool")
		local entry = Sfx.get("ambience", "Plains")
		expect(Sfx.isReal(entry)).toBe(true)
		SfxPool.loop("ambience.Plains", 0)
		expect(lastWrite(recorder, "ambience.Plains", "SoundId")).toBe(entry.id)
	end)
end)

describe("the sky's Clouds", function()
	-- A workspace with its Terrain, and a Lighting that still holds the Clouds an older build put there.
	local function place(): (any, any, any)
		local workspace = Instance.new("Folder")
		workspace.Name = "Workspace"
		local terrain = Instance.new("Terrain")
		terrain.Parent = workspace
		local lighting = Instance.new("Folder")
		lighting.Name = "Lighting"
		local stray = Instance.new("Clouds")
		stray.Parent = lighting
		return workspace, terrain, lighting
	end

	it("builds one Clouds under workspace.Terrain with lighting.luau's cover and density", function()
		local workspace, terrain = place()
		local clouds = PlaygroundBuilder.buildSkyClouds(workspace)
		expect(clouds).never.toBeNil()
		expect(clouds.ClassName).toBe("Clouds")
		expect(clouds.Parent).toBe(terrain)
		expect(clouds.Cover).toBeCloseTo(LightingData.clouds.cover, 1e-6)
		expect(clouds.Density).toBeCloseTo(LightingData.clouds.density, 1e-6)
		-- Building again keeps the one Clouds.
		expect(PlaygroundBuilder.buildSkyClouds(workspace)).toBe(clouds)
		local count = 0
		for _, child in terrain:GetChildren() do
			if child:IsA("Clouds") then
				count += 1
			end
		end
		expect(count).toBe(1)
	end)

	it("takes a Clouds left under Lighting away (the engine refuses it there)", function()
		local workspace, _, lighting = place()
		PlaygroundBuilder.buildSkyClouds(workspace, lighting)
		expect(lighting:FindFirstChildOfClass("Clouds")).toBeNil()
	end)

	it("builds no Clouds where there is no Terrain, and the Playground build reports it", function()
		local container = Instance.new("Folder")
		expect(PlaygroundBuilder.buildSkyClouds(container)).toBeNil()
		local workspace, terrain = place()
		local result = PlaygroundBuilder.build(workspace, Random.new(5))
		expect(result.skyClouds).toBe(terrain:FindFirstChildOfClass("Clouds"))
		expect(PlaygroundBuilder.build(container, Random.new(5)).skyClouds).toBeNil()
	end)
end)
