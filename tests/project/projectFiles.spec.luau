--!strict
--[[
	The Rojo project files carry two settings that used to be Studio hand steps:
	- an empty LocalScript named "Animate" in StarterPlayer.StarterCharacterScripts, so the engine never
	  inserts its default character animation script (it writes Motor6D.Transform and would fight Choreo);
	- HttpService.HttpEnabled = true in the dev places only (the PoseEditor plugin posts to the local pose
	  server), never in default.project.json, which is the shipped game.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local root = Harness.repoRoot()

local GAME_PROJECT = "default.project.json"
local DEV_PLACE_PROJECTS = { "places/Playground.project.json", "places/ClipLab.project.json" }
-- Choreo.luau destroys a script by this name if one still reaches a character.
local ANIMATE_SCRIPT = "Animate"

local function readProject(path: string): any
	return serde.decode("json", fs.readFile(root .. "/" .. path))
end

-- Every project file Rojo builds into a place: the game plus everything in places/.
local function allProjects(): { string }
	local paths = { GAME_PROJECT }
	for _, entry in fs.readDir(root .. "/places") do
		if entry:match("%.project%.json$") then
			table.insert(paths, "places/" .. entry)
		end
	end
	table.sort(paths)
	return paths
end

local function httpEnabled(project: any): any
	local service = project.tree.HttpService
	if service == nil or service["$properties"] == nil then
		return nil
	end
	return service["$properties"].HttpEnabled
end

describe("project files", function()
	it("finds the game and both dev places", function()
		local projects = allProjects()
		expect(projects).toContain(GAME_PROJECT)
		for _, path in DEV_PLACE_PROJECTS do
			expect(projects).toContain(path)
		end
	end)

	it("ships an empty Animate LocalScript in StarterCharacterScripts in every place", function()
		for _, path in allProjects() do
			local starterPlayer = readProject(path).tree.StarterPlayer
			expect(starterPlayer).toBeTruthy()
			local characterScripts = starterPlayer.StarterCharacterScripts
			expect(characterScripts).toBeTruthy()
			local animate = characterScripts[ANIMATE_SCRIPT]
			expect(animate).toBeTruthy()
			expect(animate["$className"]).toBe("LocalScript")
			-- Empty: no source file, no Source property, no children.
			expect(animate["$path"]).toBeNil()
			local properties = animate["$properties"]
			if properties ~= nil then
				expect(properties.Source == nil or properties.Source == "").toBe(true)
			end
			for key in animate do
				expect(key:sub(1, 1)).toBe("$")
			end
		end
	end)

	it("allows HTTP requests in the dev places", function()
		for _, path in DEV_PLACE_PROJECTS do
			expect(httpEnabled(readProject(path))).toBe(true)
		end
	end)

	it("leaves HttpEnabled out of the shipped game", function()
		expect(httpEnabled(readProject(GAME_PROJECT))).toBeNil()
	end)
end)
