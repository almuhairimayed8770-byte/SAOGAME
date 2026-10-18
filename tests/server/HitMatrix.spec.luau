--!strict
--[[
	The Phase 0 gate's "the server registered every hit" (section 20), as a test: every hit of every
	Phase 0 player attack (the Playground loadout's Arts and the basic chain), swung through the
	server's own CombatService and HitSweep at the boar facing, the boar side-on and the kobold at
	every real-fight placement in dev.luau hitMatrix, registers at every frame phase, and lands on
	its strike: by the first server frame at or after its snap ends (section 10: the Hold freezes
	the contact pose), never first in the settle or the recovery.
	tools/hitmatrix/HitMatrix.luau runs the swings; `lune run tools/hit-matrix.luau` prints the same
	matrix with the sample that registered each hit, or how far the blade passed when one did not.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Instance = roblox.Instance

local Dev = Harness.load("src/shared/data/dev")
local Combat = Harness.load("src/shared/data/combat")
local Playground = Harness.load("src/shared/data/playground")

local root = Harness.repoRoot()

-- tools/ modules are plain Lune scripts: load one with only Lune's own libraries to require.
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")

-- One run of the real-fight matrix, shared by the cases below (it swings every hit at every
-- placement and phase, so it runs once).
local report
local function matrix(): any
	if report == nil then
		report = HitMatrix.run(Harness, { realOnly = true, skipAttribution = true })
	end
	return report
end

local function isReal(setup: any, distance: number): boolean
	return distance >= setup.realFight.min - 1e-9 and distance <= setup.realFight.max + 1e-9
end

describe("HitMatrix fake engine", function()
	local function box(name: string, position: any, size: any): any
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = CFrame.new(position)
		return part
	end

	it("never casts into a part the sphere starts inside, and the bounds query still sees it", function()
		local inside = box("Inside", Vector3.new(0, 0, 0), Vector3.new(2, 2, 2))
		local world = HitMatrix.world({ inside })
		expect(world.cast(Vector3.new(0, 0, 0), 1, Vector3.new(0, 0, -10), {})).toBeNil()
		-- Touching at the start is inside too: 1.5 from the face with a 1.5 radius.
		expect(world.cast(Vector3.new(0, 0, -2.5), 1.5, Vector3.new(0, 0, -10), {})).toBeNil()
		local found = world.overlap(Vector3.new(0, 0, 0), 1, {})
		expect(#found).toBe(1)
		expect(found[1]).toBe(inside)
	end)

	it("returns the first part along the cast, where the sphere first touches it", function()
		local near = box("Near", Vector3.new(0, 0, -5), Vector3.new(2, 2, 2))
		local far = box("Far", Vector3.new(0, 0, -9), Vector3.new(2, 2, 2))
		local world = HitMatrix.world({ far, near })
		local hit = world.cast(Vector3.new(0, 0, 0), 1, Vector3.new(0, 0, -20), {})
		expect(hit).never.toBeNil()
		expect(hit.Instance).toBe(near)
		-- The near face is at z = -4: a sphere of radius 1 touches it after 3 studs.
		expect(hit.Distance).toBeCloseTo(3, 1e-6)
		expect(hit.Position.Z).toBeCloseTo(-4, 1e-6)
		-- A cast that passes beside the part by more than the radius misses it.
		expect(world.cast(Vector3.new(2.5, 0, 0), 1, Vector3.new(0, 0, -20), {})).toBeNil()
	end)

	it("skips excluded and unqueryable parts", function()
		local mine = Instance.new("Model")
		local own = box("Own", Vector3.new(0, 0, -5), Vector3.new(2, 2, 2))
		own.Parent = mine
		local ghost = box("Ghost", Vector3.new(0, 0, -9), Vector3.new(2, 2, 2))
		ghost.CanCollide = false
		ghost.CanQuery = false
		local world = HitMatrix.world({ own, ghost })
		expect(world.cast(Vector3.new(0, 0, 0), 1, Vector3.new(0, 0, -20), { mine })).toBeNil()
		expect(#world.overlap(Vector3.new(0, 0, -9), 1, {})).toBe(0)
		expect(#world.overlap(Vector3.new(0, 0, -5), 1, { mine })).toBe(0)
	end)
end)

describe("HitMatrix placements", function()
	it("writes each setup's real-fight range as the rigs derive it", function()
		local problems = HitMatrix.rangeProblems(matrix())
		if #problems > 0 then
			error(table.concat(problems, "\n"))
		end
	end)

	it("swings at both ends of every real-fight range and never inside the enemy's body", function()
		local current = matrix()
		for _, setup in Dev.hitMatrix.setups do
			local derived = current.derived[setup.id]
			expect(table.find(setup.distances, setup.realFight.min)).never.toBeNil()
			expect(table.find(setup.distances, setup.realFight.max)).never.toBeNil()
			for index, distance in setup.distances do
				expect(distance).toBeGreaterThanOrEqual(derived.contact)
				if index > 1 then
					expect(distance).toBeGreaterThan(setup.distances[index - 1])
				end
			end
		end
	end)
end)

describe("HitMatrix: the server registers every hit", function()
	it("swings every hit of every Phase 0 attack at every real-fight placement and frame phase", function()
		local current = matrix()
		-- The loadout's Arts in slot order, then the basic chain.
		expect(#current.attacks).toBe(#Playground.loadout.artSlots + Combat.basicChainLength)
		local expected = 0
		for _, setup in Dev.hitMatrix.setups do
			local real = 0
			for _, distance in setup.distances do
				if isReal(setup, distance) then
					real += 1
				end
			end
			for _, attack in current.attacks do
				expect(#attack.windows).toBeGreaterThan(0)
				-- Every window is judged against its own strike's snap.
				expect(#attack.snaps).toBe(#attack.windows)
				expected += real * #attack.windows
			end
		end
		expect(#current.cells).toBe(expected)
		for _, cell in current.cells do
			expect(#cell.phases).toBe(#Dev.hitMatrix.framePhases)
		end
	end)

	it("registers every real-fight swing at every frame phase", function()
		local misses = HitMatrix.misses(matrix())
		if #misses > 0 then
			error(
				("%d real-fight swing(s) the server did not register (lune run tools/hit-matrix.luau shows the matrix):\n%s"):format(
					#misses,
					table.concat(misses, "\n")
				)
			)
		end
	end)

	it("lands every real-fight hit on its strike, by the first server frame after the snap ends", function()
		local current = matrix()
		local late = HitMatrix.lateHits(current)
		if #late > 0 then
			error(
				("%d real-fight hit(s) landed after their strike (lune run tools/hit-matrix.luau shows the matrix):\n%s"):format(
					#late,
					table.concat(late, "\n")
				)
			)
		end
		-- Every registered phase carries the frame it landed on, so lateness was judged, not skipped.
		for _, cell in current.cells do
			for _, result in cell.phases do
				if result.hit then
					expect(result.landed).never.toBeNil()
				end
			end
		end
	end)
end)
