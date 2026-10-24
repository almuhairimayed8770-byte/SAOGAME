--!strict
--[[
	The Rojo project files carry two settings that used to be Studio hand steps:
	- an empty LocalScript named "Animate" in StarterPlayer.StarterCharacterScripts, so the engine never
	  inserts its default character animation script (it writes Motor6D.Transform and would fight Choreo);
	- HttpService.HttpEnabled = true in the dev places only (the PoseEditor plugin posts to the local pose
	  server), never in default.project.json, which is the shipped game.

	And no place file holds a Clouds: the engine takes one only under Workspace.Terrain ("Cloud
	instance must exist under Terrain node", 2026-10-23 Play test), so the server builds the sky's
	Clouds there at start from lighting.luau (PlaygroundBuilder.buildSkyClouds). What a place's
	Lighting holds is the sky, the atmosphere and the post effects.

	Nothing overhead casts a shadow (D-186): the Playground's Ceiling is a 900-stud disc 350 studs up,
	and with CastShadow on it put the whole field in its shadow (Studio, 2026-10-24). Any part a place
	hangs that high is sky dressing, not something the sun should be blocked by.
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

-- The classes a place's Lighting may hold: the engine draws these only as Lighting's children.
local LIGHTING_CHILDREN = {
	Sky = true,
	Atmosphere = true,
	BloomEffect = true,
	ColorCorrectionEffect = true,
	SunRaysEffect = true,
	DepthOfFieldEffect = true,
	BlurEffect = true,
}

-- Every instance node of a project tree as (path, className), "$" keys skipped.
local function eachNode(node: any, path: string, visit: (path: string, className: string, node: any) -> ())
	for key, child in node do
		if typeof(key) == "string" and key:sub(1, 1) ~= "$" and typeof(child) == "table" then
			local childPath = path .. "." .. key
			visit(childPath, child["$className"] or key, child)
			eachNode(child, childPath, visit)
		end
	end
end

-- Parts hung at least this high are overhead dressing (the Playground's Ceiling sits at 350).
local OVERHEAD_STUDS = 100
local PART_CLASSES = { Part = true, MeshPart = true, WedgePart = true, CornerWedgePart = true, TrussPart = true }

-- A part node's center height from its CFrame or Position property, or nil.
local function heightOf(node: any): number?
	local properties = node["$properties"]
	if properties == nil then
		return nil
	end
	local cframe = properties.CFrame
	if typeof(cframe) == "table" and typeof(cframe.CFrame) == "table" and typeof(cframe.CFrame.position) == "table" then
		return cframe.CFrame.position[2]
	end
	local position = properties.Position
	if typeof(position) == "table" then
		return position[2]
	end
	return nil
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

	it("puts no Clouds in any place (the server builds the sky's under workspace.Terrain)", function()
		local found = {}
		for _, path in allProjects() do
			eachNode(readProject(path).tree, "game", function(nodePath: string, className: string)
				if className == "Clouds" then
					table.insert(found, path .. ": " .. nodePath)
				end
			end)
		end
		expect(found).toEqual({})
	end)

	it("keeps only the sky, the atmosphere and the post effects under a place's Lighting", function()
		local strays = {}
		for _, path in allProjects() do
			local lighting = readProject(path).tree.Lighting
			if lighting == nil then
				continue
			end
			for key, child in lighting do
				if key:sub(1, 1) ~= "$" and typeof(child) == "table" then
					local className = child["$className"] or key
					if not LIGHTING_CHILDREN[className] then
						table.insert(strays, ("%s: Lighting.%s (%s)"):format(path, key, className))
					end
				end
			end
		end
		expect(strays).toEqual({})
		-- The Playground still carries its sky and post effects.
		local playground = readProject("places/Playground.project.json").tree.Lighting
		for _, name in { "Sky", "Atmosphere", "Bloom", "ColorCorrection", "SunRays" } do
			expect(playground[name]).toBeTruthy()
		end
	end)

	it(
		"hangs nothing overhead that casts a shadow: the Playground's Ceiling leaves the field in the sun (D-186)",
		function()
			local ceiling = readProject("places/Playground.project.json").tree.Workspace.Playground.Ceiling
			expect(ceiling).toBeTruthy()
			expect(ceiling["$properties"].CastShadow).toBe(false)
			local shading = {}
			for _, path in allProjects() do
				eachNode(readProject(path).tree, "game", function(nodePath: string, className: string, node: any)
					if not PART_CLASSES[className] then
						return
					end
					local height = heightOf(node)
					if height ~= nil and height >= OVERHEAD_STUDS and node["$properties"].CastShadow ~= false then
						table.insert(shading, ("%s: %s at y %s"):format(path, nodePath, tostring(height)))
					end
				end)
			end
			expect(shading).toEqual({})
		end
	)

	it("never turns the engine's name or health bar back on from StarterPlayer (D-178)", function()
		-- The server unlabels every character (CharacterReady.unlabel) and every rig (RigBuilder);
		-- a place that set a viewer distance or a StarterHumanoid label would draw the engine's
		-- name and health bar beside the nameplate on any Humanoid that missed it.
		local labels = {}
		for _, path in allProjects() do
			local starterPlayer = readProject(path).tree.StarterPlayer
			local properties = if starterPlayer ~= nil then starterPlayer["$properties"] else nil
			if properties ~= nil then
				for _, name in { "NameDisplayDistance", "HealthDisplayDistance" } do
					local value = properties[name]
					if value ~= nil and value ~= 0 then
						table.insert(labels, ("%s: StarterPlayer.%s = %s"):format(path, name, tostring(value)))
					end
				end
			end
			local humanoid = if starterPlayer ~= nil then starterPlayer.StarterHumanoid else nil
			if humanoid ~= nil then
				local displayType = humanoid["$properties"] and humanoid["$properties"].DisplayDistanceType
				if displayType ~= "None" then
					table.insert(
						labels,
						("%s: StarterHumanoid.DisplayDistanceType = %s"):format(path, tostring(displayType))
					)
				end
			end
		end
		expect(labels).toEqual({})
	end)
end)
