--!strict
--[[
	dev.luau capture data (F12): every gate shot sets itself up. Each shot names its staging (the
	enemies, their distance and side, held or let go), its camera, its prompt beats and the keys
	auto-perform presses; the hotkeys stay off the game's own bindings and the function keys; the
	staging's spots stand on the field, clear of the ledge and of the field's spawn points. The
	staging never moves the player (D-244): the stand ring is wider than the auto-walk's rest
	target, the walk sprints (its stop the Skid's, no carry) and follows the last leg's line, the
	ledge's ramp is a walkable way up behind the run, and the walk into the ring fits its timeout.
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

	it(
		"a released Charger's charge meets or passes the player on the spot, and the prompts say which (D-300)",
		function()
			local AI = Harness.load("src/shared/data/ai")
			local tuning = AI.tuningFor("Charger")
			local any = false
			for _, shot in Capture.shots do
				for _, entry in shot.stage.enemies do
					local def = Enemies.byId(entry.enemy) :: any
					if def.archetype ~= "Charger" or entry.held then
						expect(entry.charge).toBe(nil)
						continue
					end
					any = true
					local reach = def.attacks[1].reach
					expect(entry.distance).toBeGreaterThanOrEqual(tuning.minChargeDistance)
					expect(entry.distance).toBeLessThanOrEqual(tuning.maxChargeDistance)
					local said = false
					for _, beat in shot.prompts do
						said = said
							or beat.text:find(if entry.charge == "Meets" then "into you" else "past you", 1, true)
								~= nil
					end
					expect(said).toBe(true)
					if entry.charge == "Meets" then
						expect(entry.distance).toBeLessThanOrEqual(reach)
					else
						expect(entry.charge).toBe("Passes")
						expect(entry.distance - 1).toBeGreaterThan(reach) -- past the line's end by a body
					end
				end
			end
			expect(any).toBe(true)
		end
	)

	it("the open shot's runs name the key that crosses the Open view (D or A), never W or S (D-301)", function()
		local Cameras = Capture.cameras
		local checked = 0
		for _, shot in Capture.shots do
			if shot.camera ~= "Open" then
				continue
			end
			-- The Open view looks along -X from the player's +X (World, 90): D runs -Z, screen right.
			expect(Cameras.Open.reference).toBe("World")
			expect(Cameras.Open.degrees).toBe(90)
			for _, beat in shot.prompts do
				local text = beat.text:lower()
				local moves = text:find("walk", 1, true) ~= nil
					or text:find("run", 1, true) ~= nil
					or text:find("sprint", 1, true) ~= nil
				if moves then
					checked += 1
					local named = beat.text:find("(D)", 1, true) ~= nil
						or beat.text:find("(A)", 1, true) ~= nil
						or beat.text:find("Shift+D", 1, true) ~= nil
						or beat.text:find("Shift+A", 1, true) ~= nil
					expect(named).toBe(true)
					expect(beat.text:find("(W)", 1, true) == nil and beat.text:find("(S)", 1, true) == nil).toBe(true)
				end
			end
		end
		expect(checked).toBeGreaterThan(0)
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

	-- D-298: an Art launches on its release, a basic on its press. The prompts mark both moments.
	it("a timed attack's prompts mark when to press, hold and let go, and the glow holds on camera (D-298)", function()
		local function beatAt(shot: any, at: number): any
			for _, beat in shot.prompts do
				if math.abs(beat.at - at) < 1e-6 then
					return beat
				end
			end
			return nil
		end
		local checked = 0
		for _, shot in Capture.shots do
			for _, entry in shot.perform do
				local art = entry.action == "Art" or entry.action:match("^ArtSlot") ~= nil
				if entry.at == nil or (not art and entry.action ~= "BasicAttack") then
					continue
				end
				checked += 1
				local press = beatAt(shot, entry.at)
				expect(press ~= nil).toBe(true)
				if art then
					local release = beatAt(shot, entry.at + entry.hold)
					expect(release ~= nil).toBe(true)
					expect(press.text:lower():find("hold", 1, true)).never.toBeNil()
					expect(release.text:lower():find("let go", 1, true)).never.toBeNil()
					-- The first line names both moments.
					local first = shot.prompts[1].text
					expect(first:find(("%.1f s"):format(entry.at), 1, true)).never.toBeNil()
					expect(first:find(("%.1f s"):format(entry.at + entry.hold), 1, true)).never.toBeNil()
					-- Lit from the end of the start pose to the release, for long enough to read.
					expect(entry.hold - Combat.startPoseTime).toBeGreaterThan(Capture.artGlowSeconds - 1e-6)
				else
					expect(press.text:lower():find("now", 1, true)).never.toBeNil()
					expect(shot.prompts[1].text:find(("%.1f s"):format(entry.at), 1, true)).never.toBeNil()
				end
			end
		end
		expect(checked).toBe(5)
		-- The glow fits between the start pose and the cancel.
		expect(Combat.startPoseTime + Capture.artGlowSeconds).toBeLessThan(Input.art.cancelTime)
	end)

	it(
		"auto-perform presses real input actions or the stick, each timed by a moment, a clip or a standing rule (CF)",
		function()
			local moveAction = Capture.perform.moveAction
			-- the stick is no key: never an input action
			expect(typeof(moveAction)).toBe("string")
			expect(isAction(moveAction)).toBe(false)
			local function pressOk(entry: any)
				expect(isAction(entry.action) or entry.action == moveAction).toBe(true)
				expect(entry.hold).toBeGreaterThan(0)
				if entry.action == moveAction then
					local length = math.sqrt(entry.stick[1] ^ 2 + entry.stick[2] ^ 2)
					expect(length).toBeGreaterThan(0)
					expect(length).toBeLessThanOrEqual(1)
				else
					expect(entry.stick).toBeNil()
					expect(entry.sprint).toBeNil()
				end
			end
			for _, shot in Capture.shots do
				for _, entry in shot.perform do
					pressOk(entry)
					-- Exactly one of a moment, a clip and a standing rule.
					local timings = (if entry.at ~= nil then 1 else 0)
						+ (if entry.onClip ~= nil then 1 else 0)
						+ (if entry.every ~= nil then 1 else 0)
					expect(timings).toBe(1)
					if entry.at ~= nil then
						expect(entry.at).toBeGreaterThanOrEqual(0)
						expect(entry.at + entry.hold).toBeLessThan(shot.seconds)
					elseif entry.every ~= nil then
						expect(entry.every).toBeGreaterThan(0)
						expect(entry.action == "BasicAttack" or entry.action == "LockOn").toBe(true)
						local from, to = entry.from or 0, entry.to or shot.seconds
						expect(from).toBeGreaterThanOrEqual(0)
						expect(from).toBeLessThan(to)
						expect(to).toBeLessThanOrEqual(shot.seconds)
					end
					for _, step in entry.chain or {} do
						expect(entry.onClip ~= nil).toBe(true)
						pressOk(step)
						expect(step.delay).toBeGreaterThanOrEqual(0)
						expect(step.at == nil and step.onClip == nil and step.every == nil).toBe(true)
					end
				end
			end
		end
	)

	it("a reaction names an attack clip of a staged enemy let go, and leads its hit window (CF)", function()
		local any = false
		for _, shot in Capture.shots do
			for _, entry in shot.perform do
				if entry.onClip == nil then
					continue
				end
				any = true
				local clip = ClipLibrary.get(entry.onClip)
				expect(clip ~= nil).toBe(true)
				local window: number? = nil
				local first = math.huge
				for _, event in (clip :: any).events do
					first = math.min(first, event.time)
					if event.kind == "HitWindowOpen" and window == nil then
						window = event.time
					end
				end
				expect(window ~= nil).toBe(true)
				-- the clip is an attack of the enemy it reacts to, which the shot lets go
				local staged = shot.stage.enemies[entry.enemy or 1]
				expect(staged.held).toBe(false)
				local def = Enemies.byId(staged.enemy) :: any
				local attack = false
				for _, row in def.attacks do
					attack = attack or entry.onClip == ("enemy/%s/%s"):format(def.skin, row.clip)
				end
				expect(attack).toBe(true)
				expect(entry.lead ~= nil).toBe(true)
				expect(entry.lead :: number).toBeGreaterThanOrEqual(0)
				if entry.action == "Guard" then
					-- the guard lands inside the parry window
					expect(entry.lead :: number).toBeLessThan(Combat.parryWindow)
				else
					-- any other press comes after the client hears the clip
					expect(entry.lead :: number).toBeLessThanOrEqual((window :: number) - first)
				end
			end
		end
		expect(any).toBe(true)
	end)

	it(
		"the fight reacts: a parry on each overhead then the next Art, a dodge on the charge then the lock and a sprint at the skid (CF)",
		function()
			local shot = nil
			for _, candidate in Capture.shots do
				if candidate.id == "fight-boar-kobold" then
					shot = candidate
				end
			end
			assert(shot ~= nil, "no fight shot")
			local kobold, boar = nil, nil
			for index, entry in shot.stage.enemies do
				if entry.enemy == "KoboldAxeman" then
					kobold = index
				elseif entry.enemy == "FrenzyBoar" then
					boar = index
				end
			end
			assert(kobold ~= nil and boar ~= nil, "the fight stages a kobold and a boar")
			local guard, dodge, basics, relock = nil, nil, nil, nil
			for _, entry in shot.perform do
				local action: string = entry.action
				if action == "Guard" and entry.onClip == "enemy/Kobold/Overhead" then
					guard = entry
				elseif action == "Dodge" and entry.onClip == "enemy/Boar/Charge" then
					dodge = entry
				elseif action == "BasicAttack" and entry.every ~= nil then
					basics = entry
				elseif action == "LockOn" and entry.every ~= nil then
					relock = entry
				end
			end
			assert(guard ~= nil and dodge ~= nil and basics ~= nil and relock ~= nil, "the fight's four rules")
			-- each overhead: the guard, the lock on the kobold, then one Art of all four in turn
			expect(guard.enemy or 1).toBe(kobold)
			expect(guard.repeats).toBe(true)
			expect(guard.lock).toBe(true)
			local cycle = guard.chain[1].cycle
			for _, action in { "Art", "ArtSlot2", "ArtSlot3", "ArtSlot4" } do
				expect(table.find(cycle, action) ~= nil).toBe(true)
			end
			-- the charge: the dodge, the lock on the boar, a sprint at it that lets go in a basic's reach
			expect(dodge.enemy).toBe(boar)
			local lockStep, runStep = dodge.chain[1], dodge.chain[2]
			expect(lockStep.action).toBe("LockOn")
			expect(lockStep.enemy).toBe(boar)
			expect(runStep.action).toBe(Capture.perform.moveAction)
			expect(runStep.sprint).toBe(true)
			expect(runStep.stick[2]).toBeGreaterThan(0) -- at the lock's target
			expect(runStep.within).toBeLessThan(basics.within)
			-- the lock back on the kobold once the boar is gone
			expect(relock.enemy or 1).toBe(kobold)
			-- the boar comes in after the kobold's first parries, at a beat that says it is let go
			local release = shot.stage.enemies[boar].releaseAfter
			expect(release ~= nil).toBe(true)
			expect(release).toBeGreaterThan(0)
		end
	)

	it(
		"the locomotion pass: a sheathed walk, run and sprint, the draw, the same drawn, a turn in place, a sprint to the skid (CF)",
		function()
			local shot = nil
			for _, candidate in Capture.shots do
				if candidate.id == "locomotion" then
					shot = candidate
				end
			end
			assert(shot ~= nil, "no locomotion shot")
			local moveAction = Capture.perform.moveAction
			local moves, locks = {}, {}
			for _, entry in shot.perform do
				if entry.action == moveAction then
					table.insert(moves, entry)
				elseif entry.action == "LockOn" then
					table.insert(locks, entry)
				end
			end
			local function length(entry: any): number
				return math.sqrt(entry.stick[1] ^ 2 + entry.stick[2] ^ 2)
			end
			local function kinds(from: number, to: number): { string }
				local list = {}
				for _, entry in moves do
					if entry.at >= from and entry.at < to then
						table.insert(
							list,
							if entry.sprint then "sprint" elseif length(entry) < 0.75 then "walk" else "run"
						)
					end
				end
				return list
			end
			-- two lock pairs: the draw (F, F again) and the turn in place
			expect(#locks).toBe(4)
			expect(kinds(0, locks[1].at)).toEqual({ "walk", "run", "sprint" })
			expect(kinds(locks[2].at, locks[3].at)).toEqual({ "walk", "run", "sprint" })
			expect(kinds(locks[4].at, shot.seconds)).toEqual({ "sprint" })
			-- the turn in place: no stick held from before its lock to after its let-go
			for _, entry in moves do
				local ends = entry.at + entry.hold
				expect(ends <= locks[3].at or entry.at >= locks[4].at).toBe(true)
			end
			-- the stick lets go before the take ends: the skid plays on camera
			local last = moves[#moves]
			expect(last.at + last.hold).toBeLessThan(shot.seconds - 0.5)
			-- the runs cross the Open view: sideways on its frame, never at or away from the lens
			for _, entry in moves do
				expect(entry.stick[2]).toBe(0)
			end
		end
	)

	it("an enemy let go partway through the take is let go under the beat that says so (CF)", function()
		local checked = 0
		for _, shot in Capture.shots do
			for _, entry in shot.stage.enemies do
				if entry.releaseAfter == nil then
					continue
				end
				checked += 1
				expect(entry.held).toBe(false)
				expect(entry.releaseAfter).toBeGreaterThanOrEqual(0)
				expect(entry.releaseAfter).toBeLessThan(shot.seconds)
				local said = false
				for _, beat in shot.prompts do
					said = said
						or (math.abs(beat.at - entry.releaseAfter) < 1e-6 and beat.text:find("let go", 1, true) ~= nil)
				end
				expect(said).toBe(true)
			end
		end
		expect(checked).toBeGreaterThan(0)
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
	it("the ring is wider than the auto-walk's rest target, and tells the ledge's top from the field", function()
		expect(Walk.restStuds).toBeGreaterThan(0)
		expect(Stage.standRadius).toBeGreaterThan(Walk.restStuds)
		expect(Walk.restDegrees).toBeGreaterThan(0)
		expect(Walk.restDegrees).toBeLessThan(90)
		expect(Walk.secondWalks).toBeGreaterThanOrEqual(0)
		expect(Walk.secondWalks % 1).toBe(0)
		expect(Walk.waypointStuds).toBeGreaterThan(0)
		expect(Stage.standHeightTolerance).toBeGreaterThan(0)
		expect(Stage.standHeightTolerance).toBeLessThan(Stage.ledge.size[2])
		-- At rest: below the slowest the two-step stop carries the body, so the stop has ended.
		expect(Walk.restSpeed).toBeGreaterThan(0)
		expect(Walk.restSpeed).toBeLessThan(Choreo.locomotion.stopEndSpeed)
		expect(Stage.routeMarginStuds).toBeGreaterThan(0)
	end)

	it(
		"the walk sprints, so its stop is the Skid's with no carry; below it the let-go stays on the last leg",
		function()
			expect(table.find(Input.actions, Walk.sprintAction) ~= nil).toBe(true)
			expect(Input.keyboard[Walk.sprintAction] ~= nil).toBe(true)
			-- The sprint is past the two-step stop's top speed (D-059): the Skid stops it, no carry.
			expect(Combat.maxSpeedStudsPerSecond).toBeGreaterThan(Choreo.locomotion.skidSpeedThreshold)
			expect(Walk.lookaheadStuds).toBeGreaterThan(0)
			expect(Walk.lookaheadStuds).toBeLessThan(Stage.approachStuds)
			expect(Walk.carrySeconds).toBeGreaterThan(0)
			expect(Walk.carrySeconds).toBeLessThan(Choreo.locomotion.stopStepsSeconds)
			expect(Walk.carrySeconds * Choreo.locomotion.runSpeed).toBeLessThan(Stage.approachStuds)
		end
	)

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

-- A color's relative luminance (sRGB, 0 to 1).
local function luminance(color: Color3): number
	local function linear(channel: number): number
		return if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
end

describe("dev.luau capture render-frame tick (D-336)", function()
	it("is a small square in two palette colors that differ in hue, not brightness", function()
		local tick = Capture.frameTick
		expect(typeof(tick)).toBe("table")
		expect(tick.size >= 4 and tick.size <= 32 and tick.size % 1 == 0).toBe(true)
		expect(tick.margin >= 0 and tick.margin % 1 == 0).toBe(true)
		expect(#tick.tokens).toBe(2)
		expect(tick.tokens[1] ~= tick.tokens[2]).toBe(true)
		local a = Palette.color3(tick.tokens[1])
		local b = Palette.color3(tick.tokens[2])
		-- A swap a recording can tell apart frame from frame...
		expect((Vector3.new(a.R, a.G, a.B) - Vector3.new(b.R, b.G, b.B)).Magnitude).toBeGreaterThan(0.3)
		-- ...that never flashes: the two are as bright as each other, within the data's step.
		expect(tick.maxLuminanceStep > 0 and tick.maxLuminanceStep <= 0.1).toBe(true)
		expect(math.abs(luminance(a) - luminance(b)) <= tick.maxLuminanceStep).toBe(true)
	end)
end)
