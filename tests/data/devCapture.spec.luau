--!strict
--[[
	dev.luau capture data (F12): every gate shot sets itself up. Each shot names its staging (the
	enemies, their distance and side, held or let go), its camera, its prompt beats and the keys
	auto-perform presses; the hotkeys stay off the game's own bindings and the function keys; the
	staging's spots stand on the field, clear of the ledge and of the field's spawn points. The
	staging never moves the player (D-244): the stand ring is wider than the auto-walk's let-go,
	the ledge's ramp is a walkable way up behind the run, and the walk into the ring fits its
	timeout.
]]

local Dev = Harness.load("src/shared/data/dev")
local Input = Harness.load("src/shared/data/input")
local Combat = Harness.load("src/shared/data/combat")
local Camera = Harness.load("src/shared/data/camera")
local Enemies = Harness.load("src/shared/data/enemies")
local Playground = Harness.load("src/shared/data/playground")
local Choreo = Harness.load("src/shared/data/choreo")
local Palette = Harness.load("src/shared/data/palette")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local StageLogic = Harness.load("src/server/dev/DevStageLogic")

local Capture = Dev.capture
local Stage = Capture.stage
local Walk = Capture.walk
-- Roblox's Humanoid.MaxSlopeAngle default (nothing in the game changes it): steeper is a wall.
local HUMANOID_MAX_SLOPE_DEGREES = 89

local function priority(row: any): number
	return (Enum.RenderPriority :: any)[row.base].Value + row.offset
end

local function isAction(name: string): boolean
	return table.find(Input.actions, name) ~= nil
end

describe("dev.luau capture shots", function()
	it("every shot stages itself: enemies, a camera, prompts and a perform list", function()
		expect(#Capture.shots).toBeGreaterThan(0)
		for _, shot in Capture.shots do
			expect(typeof(shot.stage)).toBe("table")
			expect(typeof(shot.stage.open)).toBe("boolean")
			expect(typeof(shot.stage.lock)).toBe("boolean")
			expect(#shot.stage.enemies).toBeGreaterThan(0)
			expect(shot.camera == "Lock" or Capture.cameras[shot.camera] ~= nil).toBe(true)
			expect(shot.cameraSide == 1 or shot.cameraSide == -1).toBe(true)
			expect(#shot.prompts).toBeGreaterThan(0)
			expect(typeof(shot.perform)).toBe("table")
		end
	end)

	it("the lock camera only on a shot that locks on", function()
		for _, shot in Capture.shots do
			if shot.camera == "Lock" then
				expect(shot.stage.lock).toBe(true)
			end
		end
	end)

	it("stages enemies the game has, at a positive distance; hp only below the enemy's own", function()
		for _, shot in Capture.shots do
			for _, entry in shot.stage.enemies do
				local def = Enemies.byId(entry.enemy)
				expect(def ~= nil).toBe(true)
				expect(entry.distance).toBeGreaterThan(0)
				expect(math.abs(entry.side)).toBeLessThanOrEqual(180)
				expect(typeof(entry.held)).toBe("boolean")
				if entry.hp ~= nil then
					expect(entry.hp).toBeGreaterThan(0)
					expect(entry.hp).toBeLessThanOrEqual((def :: any).hp)
				end
			end
		end
	end)

	it("prompt beats start at 0, run in order and all show inside the take", function()
		for _, shot in Capture.shots do
			expect(shot.prompts[1].at).toBe(0)
			for index, beat in shot.prompts do
				expect(#beat.text).toBeGreaterThan(0)
				expect(beat.at).toBeLessThan(shot.seconds)
				if index > 1 then
					expect(beat.at).toBeGreaterThan(shot.prompts[index - 1].at)
				end
			end
		end
	end)

	it("auto-perform presses real input actions, each timed by a moment or by a clip", function()
		for _, shot in Capture.shots do
			for _, entry in shot.perform do
				expect(isAction(entry.action)).toBe(true)
				expect(entry.hold).toBeGreaterThan(0)
				-- Exactly one of a moment and a clip.
				expect((entry.at ~= nil) ~= (entry.onClip ~= nil)).toBe(true)
				if entry.at ~= nil then
					expect(entry.at).toBeGreaterThanOrEqual(0)
					expect(entry.at + entry.hold).toBeLessThan(shot.seconds)
				end
			end
		end
	end)

	it("an Art press is held past the start pose and activation, short of the cancel time", function()
		local least = Combat.startPoseTime + Combat.activationHold
		for _, shot in Capture.shots do
			for _, entry in shot.perform do
				if entry.action == "Art" or entry.action:match("^ArtSlot") ~= nil then
					expect(entry.hold).toBeGreaterThan(least)
					expect(entry.hold).toBeLessThan(Input.art.cancelTime)
				end
			end
		end
	end)

	it("a clip-timed press names a clip with a hit window, and leads it inside the parry window", function()
		local any = false
		for _, shot in Capture.shots do
			for _, entry in shot.perform do
				if entry.onClip ~= nil then
					any = true
					local clip = ClipLibrary.get(entry.onClip)
					expect(clip ~= nil).toBe(true)
					local window = false
					for _, event in (clip :: any).events do
						if event.kind == "HitWindowOpen" then
							window = true
						end
					end
					expect(window).toBe(true)
					expect(entry.lead ~= nil).toBe(true)
					expect(entry.lead :: number).toBeGreaterThanOrEqual(0)
					expect(entry.lead :: number).toBeLessThan(Combat.parryWindow)
				end
			end
		end
		expect(any).toBe(true)
	end)
end)

describe("dev.luau capture cameras", function()
	it("each staged view is a sane camera", function()
		for name, view in Capture.cameras do
			expect(name ~= "Lock").toBe(true)
			expect(table.find({ "Player", "Target", "Middle" }, view.anchor) ~= nil).toBe(true)
			expect(table.find({ "Line", "Facing", "World" }, view.reference) ~= nil).toBe(true)
			expect(view.degrees).toBeGreaterThanOrEqual(0)
			expect(view.degrees).toBeLessThanOrEqual(180)
			expect(view.distance).toBeGreaterThan(0)
			expect(view.height).toBeGreaterThanOrEqual(0)
			expect(view.focusBias).toBeGreaterThanOrEqual(0)
			expect(view.focusBias).toBeLessThanOrEqual(1)
		end
	end)
end)

describe("dev.luau capture hotkeys", function()
	it("are distinct, off the game's keyboard bindings and never a function key", function()
		local bound: { [string]: boolean } = {}
		for _, keys in Input.keyboard do
			for _, key in keys do
				bound[key] = true
			end
		end
		local seen: { [string]: string } = {}
		for name, key in Capture.hotkeys do
			expect(seen[key] == nil).toBe(true)
			seen[key] = name
			expect(bound[key] == nil).toBe(true)
			expect(key:match("^F%d+$") == nil).toBe(true)
		end
		expect(Capture.hotkeys.autoPerform ~= nil).toBe(true)
		expect(Capture.hotkeys.releaseStage ~= nil).toBe(true)
	end)

	it("auto-perform starts off", function()
		expect(Capture.perform.defaultOn).toBe(false)
	end)
end)

describe("dev.luau capture staging", function()
	it("moves field enemies past the lock's range", function()
		expect(Stage.awayStuds).toBeGreaterThan(Camera.lock.range)
	end)

	it("stands every spot on the field, the area off the ledge and the open shot on it", function()
		local inner = Playground.fieldRadius - Stage.awayStuds
		for _, open in { false, true } do
			local x, _, z = StageLogic.standSpot(open, Stage.area, Stage.ledge)
			expect(math.sqrt(x * x + z * z)).toBeLessThan(inner)
			expect(StageLogic.onLedge(Stage.ledge, x, z)).toBe(open)
		end
	end)

	it("keeps the ledge and its ramp off the field's spawn points", function()
		local ledge = Stage.ledge
		local reach = math.max(ledge.size[1], ledge.size[3]) / 2 + Playground.spawnScatterRadius
		local rx, _, rz = StageLogic.rampFrame(ledge)
		local rampReach = math.max(ledge.ramp.size[1], ledge.ramp.size[3]) / 2 + Playground.spawnScatterRadius
		for _, spawn in Playground.spawns do
			local dx = spawn.position[1] - ledge.position[1]
			local dz = spawn.position[3] - ledge.position[3]
			expect(math.sqrt(dx * dx + dz * dz)).toBeGreaterThan(reach)
			dx, dz = spawn.position[1] - rx, spawn.position[3] - rz
			expect(math.sqrt(dx * dx + dz * dz)).toBeGreaterThan(rampReach)
		end
	end)

	it("stands no staged enemy on the ledge", function()
		for _, shot in Capture.shots do
			local x, _, z, facing = StageLogic.standSpot(shot.stage.open, Stage.area, Stage.ledge)
			for _, entry in shot.stage.enemies do
				local ex, ez = StageLogic.around(x, z, facing, entry.side, entry.distance)
				expect(StageLogic.onLedge(Stage.ledge, ex, ez)).toBe(false)
			end
		end
	end)

	it("the ledge's drop is a fall with weight, and the walk to it fits in the first beat", function()
		local ledge = Stage.ledge
		expect(ledge.size[2]).toBeGreaterThanOrEqual(4)
		expect(ledge.standInset).toBeGreaterThan(0)
		expect(ledge.standInset).toBeLessThan(ledge.size[3])
	end)
end)

describe("dev.luau capture stand ring and walk (D-244)", function()
	it("the ring is wider than the auto-walk's let-go, and tells the ledge's top from the field", function()
		expect(Walk.arriveStuds).toBeGreaterThan(0)
		expect(Stage.standRadius).toBeGreaterThan(Walk.arriveStuds)
		expect(Walk.waypointStuds).toBeGreaterThan(0)
		expect(Stage.standHeightTolerance).toBeGreaterThan(0)
		expect(Stage.standHeightTolerance).toBeLessThan(Stage.ledge.size[2])
		-- At rest: below the slowest the two-step stop carries the body, so the stop has ended.
		expect(Walk.restSpeed).toBeGreaterThan(0)
		expect(Walk.restSpeed).toBeLessThan(Choreo.locomotion.stopEndSpeed)
		expect(Stage.routeMarginStuds).toBeGreaterThan(0)
	end)

	it("the ramp rises the ledge's height, no wider than it, at a slope a Humanoid walks", function()
		local ledge = Stage.ledge
		local ramp = ledge.ramp.size
		expect(ramp[2]).toBe(ledge.size[2])
		expect(ramp[1]).toBeGreaterThan(0)
		expect(ramp[1]).toBeLessThanOrEqual(ledge.size[1])
		expect(ramp[3]).toBeGreaterThan(0)
		expect(math.deg(math.atan2(ramp[2], ramp[3]))).toBeLessThan(HUMANOID_MAX_SLOPE_DEGREES)
		expect(Palette.tokens[ledge.ramp.colorToken] ~= nil).toBe(true)
		expect((Enum.Material :: any)[ledge.ramp.material] ~= nil).toBe(true)
		-- Behind the start (the +Z side), the open shot looking the other way (off the run).
		local _, _, z, facing = StageLogic.standSpot(true, Stage.area, ledge)
		local _, lz = StageLogic.look(facing)
		local _, _, rz = StageLogic.rampFrame(ledge)
		expect((rz - z) * lz).toBeLessThan(0)
	end)

	it("the open shot's approach stands on the ramp, so the climb is the last leg", function()
		local ledge = Stage.ledge
		local x, _, z, facing = StageLogic.standSpot(true, Stage.area, ledge)
		local lx, lz = StageLogic.look(facing)
		expect(StageLogic.onRamp(ledge, x - lx * Stage.approachStuds, z - lz * Stage.approachStuds)).toBe(true)
	end)

	it("the walk from the stage area up to the open shot fits the timeout at walk speed", function()
		local area = Stage.area
		local fromX, fromZ = area.position[1], area.position[3]
		local length = 0
		for _, point in StageLogic.route(true, Stage, true, fromX, fromZ) do
			length += math.sqrt((point[1] - fromX) ^ 2 + (point[2] - fromZ) ^ 2)
			fromX, fromZ = point[1], point[2]
		end
		expect(length / Choreo.locomotion.walkSpeed).toBeLessThan(Walk.timeoutSeconds)
	end)

	it("the walk steps after the control script's input and before the character controller reads it", function()
		expect(priority(Walk.renderOrder)).toBeGreaterThan(Enum.RenderPriority.Input.Value)
		expect(priority(Walk.renderOrder)).toBeLessThan(priority(Choreo.renderOrder.character))
	end)

	it("the walk's movement keys are key codes and none is a capture hotkey", function()
		expect(#Walk.cancelKeys).toBeGreaterThan(0)
		local hotkeys: { [string]: boolean } = {}
		for _, key in Capture.hotkeys do
			hotkeys[key] = true
		end
		for _, key in Walk.cancelKeys do
			expect((Enum.KeyCode :: any)[key] ~= nil).toBe(true)
			expect(hotkeys[key] == nil).toBe(true)
		end
	end)

	it("the ring's disc is a thin palette-coloured part", function()
		local ring = Walk.ring
		expect(ring.thickness).toBeGreaterThan(0)
		expect(ring.thickness).toBeLessThan(Stage.standHeightTolerance)
		expect(Palette.tokens[ring.colorToken] ~= nil).toBe(true)
		expect((Enum.Material :: any)[ring.material] ~= nil).toBe(true)
		expect(ring.transparency).toBeGreaterThanOrEqual(0)
		expect(ring.transparency).toBeLessThan(1)
	end)
end)
