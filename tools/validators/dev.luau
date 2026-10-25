--!strict
--[[
	Validates the Studio dev hooks in src/shared/data/dev.luau (D-114): `aim`, the client helper
	that drives the real request path from a Studio MCP execute_luau call
	(src/client/dev/DevAim.client.luau), and `trace`, the server helper that reads
	CombatService.traceSink (src/server/dev/DevCombat.server.luau).

	Every wait the helpers make is tied to the game numbers it waits on, so a retuned combat table
	cannot quietly turn a helper's report into a wrong one:
	- aim.faceToleranceDegrees stays under combat.luau aim.snapDegrees (the swing's own snap finishes
	  the turn) and under deg(acos(1 - facingTolerance)), the farthest facing the server accepts;
	- aim.faceTimeoutSeconds lets the lock turn (aim.lockTurnRate) and the dev turn
	  (aim.faceDegreesPerSecond) come round from straight behind;
	- aim.replicationSettleSeconds covers combat.lagAllowance, so the server sees a dev turn and the
	  client's yaw history no longer holds the old facing;
	- aim.artHoldSeconds is past the start pose and activation hold and short of the cancel time;
	- aim.swingGapSeconds is no faster than BasicAttackRequest's refill, outlasts the server's basic
	  swing (basicHitDuration) and the latest basic hit window plus the lag allowance (so a swing's
	  hit is in before the next goes), and stays inside basicChainWindow (the chain carries on);
	- aim.runTimeoutSeconds and trace.runTimeoutSeconds outlast the longest loadout Art;
	- aim.maxSwings covers one whole basic chain; trace.keepEvents holds every window of the
	  longest swing command.

	The capture's timeScale.steps are each above 0 and at most 1, and timeScale.default is one of
	them: the capture slows the local body with them (CharacterController.setCaptureTimeScale), so
	a step past 1x would move it faster than the anti-cheat's sprint cap.

	The capture's shots (F12, tests/data/devCapture.spec.luau): every shot stages at least one
	enemy the game has (a positive distance, a side within a half turn, held a boolean, hp above 0
	and at most the enemy's own), takes the Lock camera only when it locks on or else a
	capture.cameras view, has a cameraSide of 1 or -1, prompt beats from 0 in order inside the take,
	and a perform list of input.luau actions each held a positive time and timed by exactly one of
	`at` (letting go inside the take) and `onClip` (a clip with a HitWindowOpen, led by 0 or more and
	under combat.parryWindow); an Art press is held past the start pose and activation and short of
	the cancel time. The staged views name a known anchor and reference, degrees in [0, 180], a
	positive distance, a height of 0 or more and a focusBias in [0, 1]. The hotkeys are distinct,
	off input.luau's keyboard bindings, never a function key, autoPerform and releaseStage among
	them, and no walk cancel key; auto-perform starts off. The stage: a plain remote name, positive
	request rate, away distance (past camera.luau lock.range) and hold wait (under
	stageTimeoutSeconds); a ledge at least LEDGE_MIN_DROP_STUDS tall, its stand inset on its top,
	standHeightTolerance under its height, palette colours and real materials; every stand spot
	awayStuds inside the field's edge, the area's off the ledge and the open shot's on it; the ledge
	and its ramp off every spawn's scatter; no staged enemy on the ledge; the ring's disc thinner
	than standHeightTolerance, palette-coloured, a real material, transparency in [0, 1).

	The capture's walk into the stand ring (D-244: the staging never moves the player):
	- capture.stage's ring numbers are positive, and the ring is wider than the auto-walk's let-go
	  (capture.walk.arriveStuds), so the let-go lands inside it;
	- capture.walk.restSpeed is under choreo.luau locomotion.stopEndSpeed (the two-step stop has
	  ended when the body is that slow);
	- the ledge's ramp is as tall as the ledge, no wider, and no steeper than a Humanoid walks
	  (MaxSlopeAngle, left at its default), behind the open shot's start;
	- the open shot's approach stands on the ramp, and walk.timeoutSeconds covers the route from
	  the stage area up to the open shot's spot at locomotion walkSpeed;
	- walk.renderOrder runs after the control script's input step and before the character
	  controller's step (choreo.luau renderOrder.character), and walk.cancelKeys are real KeyCodes.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local roblox = require("@lune/roblox")

local HALF_TURN_DEGREES = 180
-- Roblox's Humanoid.MaxSlopeAngle default; nothing in the game changes it.
local HUMANOID_MAX_SLOPE_DEGREES = 89
local MAX_DECIMALS = 6
local CLIPS = "src/shared/clips/"
-- The ledge's drop: at least this tall, so the fall off it lands with weight (choreo landing).
local LEDGE_MIN_DROP_STUDS = 4
-- What a staged view frames from (CameraController.setStage).
local STAGE_ANCHORS = { "Player", "Target", "Middle" }
local STAGE_REFERENCES = { "Line", "Facing", "World" }

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isWhole(value: any): boolean
	return isNumber(value) and value % 1 == 0
end

local function isName(value: any): boolean
	return typeof(value) == "string" and value:match("^%a%w*$") ~= nil
end

local function isMaterial(name: any): boolean
	local ok, material = pcall(function(): any
		return (roblox.Enum.Material :: any)[name]
	end)
	return ok and material ~= nil
end

return function(ctx: Context): { string }
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, "dev: " .. message)
	end

	local dev = ctx.load("src/shared/data/dev")
	local combat = ctx.load("src/shared/data/combat")
	local world = ctx.load("src/shared/data/world")
	local arts = ctx.load("src/shared/data/arts")
	local weapons = ctx.load("src/shared/data/weapons")
	local playground = ctx.load("src/shared/data/playground")
	local sampler = ctx.load("src/shared/choreo/ClipSampler")

	-- The capture's slow-motion steps (D-111).
	local timeScale = dev.timeScale
	if typeof(timeScale) ~= "table" or typeof(timeScale.steps) ~= "table" or #timeScale.steps == 0 then
		problem("timeScale.steps must be a list of at least one scale")
	else
		for index, step in timeScale.steps do
			if not isNumber(step) or step <= 0 or step > 1 then
				problem(
					("timeScale.steps[%d] must be a number above 0 and at most 1 (got %s): the capture slows the local body with it, and past 1x it would outrun the anti-cheat's cap"):format(
						index,
						tostring(step)
					)
				)
			end
		end
		if table.find(timeScale.steps, timeScale.default) == nil then
			problem(("timeScale.default (%s) must be one of timeScale.steps"):format(tostring(timeScale.default)))
		end
	end

	-- The capture's walk into the stand ring (D-244).
	local capture = dev.capture
	local stage = if typeof(capture) == "table" then capture.stage else nil
	local walk = if typeof(capture) == "table" then capture.walk else nil
	if typeof(stage) ~= "table" or typeof(walk) ~= "table" then
		problem("capture.stage and capture.walk must be tables")
	else
		local walkProblems = #problems
		for _, key in { "standRadius", "standHeightTolerance", "approachStuds", "routeMarginStuds" } do
			if not isNumber(stage[key]) or stage[key] <= 0 then
				problem(("capture.stage.%s must be a positive number"):format(key))
			end
		end
		for _, key in { "timeoutSeconds", "waypointStuds", "arriveStuds", "restSpeed" } do
			if not isNumber(walk[key]) or walk[key] <= 0 then
				problem(("capture.walk.%s must be a positive number"):format(key))
			end
		end
		local ledge = stage.ledge
		local ramp = if typeof(ledge) == "table" and typeof(ledge.ramp) == "table" then ledge.ramp.size else nil
		if typeof(ramp) ~= "table" or #ramp ~= 3 then
			problem("capture.stage.ledge.ramp.size must be { width, height, length }")
		end
		if #problems == walkProblems then
			local choreo = ctx.load("src/shared/data/choreo")
			local logic = ctx.load("src/server/dev/DevStageLogic")
			if walk.arriveStuds >= stage.standRadius then
				problem(
					("capture.walk.arriveStuds (%g) must be under capture.stage.standRadius (%g): the auto-walk lets go inside the ring"):format(
						walk.arriveStuds,
						stage.standRadius
					)
				)
			end
			if walk.restSpeed >= choreo.locomotion.stopEndSpeed then
				problem(
					("capture.walk.restSpeed (%g) must be under choreo locomotion.stopEndSpeed (%g): at rest means the two-step stop has ended"):format(
						walk.restSpeed,
						choreo.locomotion.stopEndSpeed
					)
				)
			end
			if ramp[2] ~= ledge.size[2] then
				problem(
					("capture.stage.ledge.ramp rises %g studs; it must rise the ledge's height (%g)"):format(
						ramp[2],
						ledge.size[2]
					)
				)
			end
			if ramp[1] <= 0 or ramp[1] > ledge.size[1] or ramp[3] <= 0 then
				problem("capture.stage.ledge.ramp must be no wider than the ledge, with a positive width and length")
			elseif math.deg(math.atan2(ramp[2], ramp[3])) >= HUMANOID_MAX_SLOPE_DEGREES then
				problem(
					("capture.stage.ledge.ramp is steeper than a Humanoid walks (%g degrees)"):format(
						HUMANOID_MAX_SLOPE_DEGREES
					)
				)
			else
				local x, _, z, facing = logic.standSpot(true, stage.area, ledge)
				local lx, lz = logic.look(facing)
				local _, _, rampZ = logic.rampFrame(ledge)
				if (rampZ - z) * lz >= 0 then
					problem("capture.stage.ledge.ramp must stand behind the open shot's start, off its run")
				end
				if not logic.onRamp(ledge, x - lx * stage.approachStuds, z - lz * stage.approachStuds) then
					problem("capture.stage.approachStuds must put the open shot's approach on the ledge's ramp")
				end
				local fromX, fromZ = stage.area.position[1], stage.area.position[3]
				local length = 0
				for _, point in logic.route(true, stage, true, fromX, fromZ) do
					length += math.sqrt((point[1] - fromX) ^ 2 + (point[2] - fromZ) ^ 2)
					fromX, fromZ = point[1], point[2]
				end
				local seconds = length / choreo.locomotion.walkSpeed
				if walk.timeoutSeconds <= seconds then
					problem(
						("capture.walk.timeoutSeconds (%g) must cover the walk from the stage area up to the open shot (%.2f s at walk speed)"):format(
							walk.timeoutSeconds,
							seconds
						)
					)
				end
			end
			local function priority(row: any): number?
				local item = if typeof(row) == "table" then (roblox.Enum.RenderPriority :: any)[row.base] else nil
				return if item ~= nil and isNumber(row.offset) then item.Value + row.offset else nil
			end
			local walkAt, characterAt = priority(walk.renderOrder), priority(choreo.renderOrder.character)
			if
				walkAt == nil
				or characterAt == nil
				or walkAt <= roblox.Enum.RenderPriority.Input.Value
				or walkAt >= characterAt
			then
				problem(
					"capture.walk.renderOrder must run after the Input render step and before choreo renderOrder.character"
				)
			end
			if typeof(walk.cancelKeys) ~= "table" or #walk.cancelKeys == 0 then
				problem("capture.walk.cancelKeys must list the movement keys")
			else
				for _, name in walk.cancelKeys do
					local ok, code = pcall(function(): any
						return (roblox.Enum.KeyCode :: any)[name]
					end)
					if not ok or code == nil then
						problem(("capture.walk.cancelKeys: %s is not an Enum.KeyCode"):format(tostring(name)))
					end
				end
			end
		end
	end

	-- The capture's shots (F12): every shot stages itself (tests/data/devCapture.spec.luau).
	if typeof(capture) == "table" then
		local input = ctx.load("src/shared/data/input")
		local camera = ctx.load("src/shared/data/camera")
		local enemies = ctx.load("src/shared/data/enemies")
		local palette = ctx.load("src/shared/data/palette")
		local logic = ctx.load("src/server/dev/DevStageLogic")
		local cameras = if typeof(capture.cameras) == "table" then capture.cameras else {}
		local artHoldMin = combat.startPoseTime + combat.activationHold
		local artHoldMax = input.art.cancelTime

		-- The staged views.
		for name, view in cameras do
			local label = ("capture.cameras.%s"):format(tostring(name))
			if name == "Lock" then
				problem(label .. ": Lock is the lock-on's own camera, not a staged view")
			end
			if typeof(view) ~= "table" then
				problem(label .. " must be a table")
				continue
			end
			if table.find(STAGE_ANCHORS, view.anchor) == nil then
				problem(("%s.anchor must be one of %s"):format(label, table.concat(STAGE_ANCHORS, ", ")))
			end
			if table.find(STAGE_REFERENCES, view.reference) == nil then
				problem(("%s.reference must be one of %s"):format(label, table.concat(STAGE_REFERENCES, ", ")))
			end
			if not isNumber(view.degrees) or view.degrees < 0 or view.degrees > HALF_TURN_DEGREES then
				problem(("%s.degrees must be in [0, %d]"):format(label, HALF_TURN_DEGREES))
			end
			if not isNumber(view.distance) or view.distance <= 0 then
				problem(label .. ".distance must be positive")
			end
			if not isNumber(view.height) or view.height < 0 then
				problem(label .. ".height must be 0 or more")
			end
			if not isNumber(view.focusBias) or view.focusBias < 0 or view.focusBias > 1 then
				problem(label .. ".focusBias must be in [0, 1]")
			end
		end

		-- The shots.
		local shots = capture.shots
		if typeof(shots) ~= "table" or #shots == 0 then
			problem("capture.shots must list at least one shot")
			shots = {}
		end
		for index, shot in shots do
			local label = ("capture.shots[%d]"):format(index)
			if typeof(shot) ~= "table" then
				problem(label .. " must be a table")
				continue
			end
			if typeof(shot.id) == "string" then
				label = ("capture.shots[%d] (%s)"):format(index, shot.id)
			end
			local seconds = if isNumber(shot.seconds) and shot.seconds > 0 then shot.seconds else nil
			if seconds == nil then
				problem(label .. ".seconds must be a positive take length")
			end
			local shotStage = shot.stage
			if
				typeof(shotStage) ~= "table"
				or typeof(shotStage.open) ~= "boolean"
				or typeof(shotStage.lock) ~= "boolean"
			then
				problem(label .. ".stage must be a table with boolean open and lock")
				shotStage = nil
			elseif typeof(shotStage.enemies) ~= "table" or #shotStage.enemies == 0 then
				problem(label .. ".stage.enemies must stage at least one enemy")
			else
				for enemyIndex, entry in shotStage.enemies do
					local entryLabel = ("%s.stage.enemies[%d]"):format(label, enemyIndex)
					local def = if typeof(entry) == "table" then enemies.byId(entry.enemy) else nil
					if def == nil then
						problem(
							("%s names '%s', which is not an enemy the game has"):format(
								entryLabel,
								tostring(if typeof(entry) == "table" then entry.enemy else entry)
							)
						)
						continue
					end
					if not isNumber(entry.distance) or entry.distance <= 0 then
						problem(entryLabel .. ".distance must be positive")
					end
					if not isNumber(entry.side) or math.abs(entry.side) > HALF_TURN_DEGREES then
						problem(
							("%s.side must be in [-%d, %d] degrees"):format(
								entryLabel,
								HALF_TURN_DEGREES,
								HALF_TURN_DEGREES
							)
						)
					end
					if typeof(entry.held) ~= "boolean" then
						problem(entryLabel .. ".held must be a boolean")
					end
					if entry.hp ~= nil and (not isNumber(entry.hp) or entry.hp <= 0 or entry.hp > def.hp) then
						problem(
							("%s.hp must be above 0 and at most the enemy's own (%s)"):format(
								entryLabel,
								tostring(def.hp)
							)
						)
					end
				end
			end
			if shot.camera == "Lock" then
				if shotStage ~= nil and shotStage.lock ~= true then
					problem(label .. " takes the Lock camera on a shot that does not lock on (stage.lock)")
				end
			elseif typeof(shot.camera) ~= "string" or typeof(cameras[shot.camera]) ~= "table" then
				problem(("%s.camera '%s' must be Lock or a capture.cameras view"):format(label, tostring(shot.camera)))
			end
			if shot.cameraSide ~= 1 and shot.cameraSide ~= -1 then
				problem(label .. ".cameraSide must be 1 or -1")
			end
			-- Prompt beats: from 0, in order, all inside the take.
			local prompts = shot.prompts
			if typeof(prompts) ~= "table" or #prompts == 0 then
				problem(label .. ".prompts must list at least one beat")
			else
				for beatIndex, beat in prompts do
					local beatLabel = ("%s.prompts[%d]"):format(label, beatIndex)
					if typeof(beat) ~= "table" or typeof(beat.text) ~= "string" or beat.text == "" then
						problem(beatLabel .. " must have a text")
						continue
					end
					if not isNumber(beat.at) then
						problem(beatLabel .. ".at must be a number of seconds")
						continue
					end
					if beatIndex == 1 and beat.at ~= 0 then
						problem(beatLabel .. ".at must be 0: the first prompt shows as the take starts")
					end
					local previous = prompts[beatIndex - 1]
					if
						beatIndex > 1
						and typeof(previous) == "table"
						and isNumber(previous.at)
						and beat.at <= previous.at
					then
						problem(beatLabel .. ".at must come after the prompt before it")
					end
					if seconds ~= nil and beat.at >= seconds then
						problem(("%s.at must show inside the take (%g s)"):format(beatLabel, seconds))
					end
				end
			end
			-- Auto-perform: real actions, each timed by exactly one of a moment and a clip.
			local perform = shot.perform
			if typeof(perform) ~= "table" then
				problem(label .. ".perform must be a list (empty for none)")
				continue
			end
			for pressIndex, press in perform do
				local pressLabel = ("%s.perform[%d]"):format(label, pressIndex)
				if typeof(press) ~= "table" then
					problem(pressLabel .. " must be a table")
					continue
				end
				if typeof(press.action) ~= "string" or table.find(input.actions, press.action) == nil then
					problem(("%s.action '%s' is not an input.luau action"):format(pressLabel, tostring(press.action)))
					continue
				end
				if not isNumber(press.hold) or press.hold <= 0 then
					problem(pressLabel .. ".hold must be a positive number of seconds")
					continue
				end
				if (press.at ~= nil) == (press.onClip ~= nil) then
					problem(pressLabel .. " must be timed by exactly one of `at` and `onClip`")
				elseif press.at ~= nil then
					if not isNumber(press.at) or press.at < 0 then
						problem(pressLabel .. ".at must be 0 or more")
					elseif seconds ~= nil and press.at + press.hold >= seconds then
						problem(("%s must let go inside the take (%g s)"):format(pressLabel, seconds))
					end
				else
					local ok, clip = pcall(ctx.load, CLIPS .. tostring(press.onClip))
					local window = false
					if ok and typeof(clip) == "table" and typeof(clip.events) == "table" then
						for _, event in clip.events do
							if typeof(event) == "table" and event.kind == "HitWindowOpen" then
								window = true
							end
						end
					end
					if not window then
						problem(
							("%s.onClip '%s' must name a clip with a HitWindowOpen event"):format(
								pressLabel,
								tostring(press.onClip)
							)
						)
					end
					if not isNumber(press.lead) then
						problem(pressLabel .. ".lead must say how far ahead of the hit window the press comes")
					elseif press.lead < 0 or press.lead >= combat.parryWindow then
						problem(
							("%s.lead (%g) must be 0 or more and under combat.parryWindow (%g)"):format(
								pressLabel,
								press.lead,
								combat.parryWindow
							)
						)
					end
				end
				if press.action == "Art" or press.action:match("^ArtSlot") ~= nil then
					if press.hold <= artHoldMin or press.hold >= artHoldMax then
						problem(
							("%s: an Art press is held past the start pose and activation (%g s) and short of the cancel time (%g s); got %g s"):format(
								pressLabel,
								artHoldMin,
								artHoldMax,
								press.hold
							)
						)
					end
				end
			end
		end

		-- The hotkeys: distinct, off the game's own keyboard bindings, never a function key.
		local hotkeys = capture.hotkeys
		if typeof(hotkeys) ~= "table" then
			problem("capture.hotkeys must be a table")
		else
			local bound: { [string]: boolean } = {}
			for _, keys in input.keyboard do
				for _, key in keys do
					bound[key] = true
				end
			end
			local seen: { [string]: string } = {}
			local names = {}
			for name in hotkeys do
				table.insert(names, tostring(name))
			end
			table.sort(names)
			for _, name in names do
				local key = hotkeys[name]
				if typeof(key) ~= "string" then
					problem(("capture.hotkeys.%s must be a key name"):format(name))
					continue
				end
				if seen[key] ~= nil then
					problem(("capture.hotkeys.%s and capture.hotkeys.%s are both %s"):format(seen[key], name, key))
				end
				seen[key] = name
				if bound[key] then
					problem(("capture.hotkeys.%s (%s) is one of the game's own keyboard bindings"):format(name, key))
				end
				if key:match("^F%d+$") ~= nil then
					problem(("capture.hotkeys.%s (%s) must not be a function key"):format(name, key))
				end
			end
			for _, name in { "autoPerform", "releaseStage" } do
				if hotkeys[name] == nil then
					problem(("capture.hotkeys.%s is missing"):format(name))
				end
			end
			if typeof(walk) == "table" and typeof(walk.cancelKeys) == "table" then
				for _, key in walk.cancelKeys do
					if seen[key] ~= nil then
						problem(
							("capture.walk.cancelKeys: %s is the capture hotkey %s"):format(tostring(key), seen[key])
						)
					end
				end
			end
		end
		if typeof(capture.perform) ~= "table" or capture.perform.defaultOn ~= false then
			problem("capture.perform.defaultOn must be false: auto-perform starts off")
		end

		-- The staging's own numbers.
		if typeof(stage) == "table" then
			if typeof(stage.remoteName) ~= "string" or not isName(stage.remoteName) then
				problem("capture.stage.remoteName must be a plain instance name")
			end
			for _, key in { "requestsPerSecond", "awayStuds", "holdWaitSeconds" } do
				if not isNumber(stage[key]) or stage[key] <= 0 then
					problem(("capture.stage.%s must be a positive number"):format(key))
				end
			end
			if isNumber(stage.awayStuds) and stage.awayStuds <= camera.lock.range then
				problem(
					("capture.stage.awayStuds (%g) must be past camera.luau lock.range (%g): a moved field enemy is never locked"):format(
						stage.awayStuds,
						camera.lock.range
					)
				)
			end
			if
				not isNumber(capture.stageTimeoutSeconds)
				or (isNumber(stage.holdWaitSeconds) and stage.holdWaitSeconds >= capture.stageTimeoutSeconds)
			then
				problem(
					"capture.stage.holdWaitSeconds must be under capture.stageTimeoutSeconds: the client waits out the server's hold wait"
				)
			end
			local ledge = stage.ledge
			local area = stage.area
			local ledgeOk = typeof(ledge) == "table"
				and typeof(ledge.size) == "table"
				and #ledge.size == 3
				and typeof(ledge.position) == "table"
				and #ledge.position == 3
				and isNumber(ledge.standInset)
			if not ledgeOk then
				problem("capture.stage.ledge must have a size, a position and a standInset")
			else
				if ledge.size[2] < LEDGE_MIN_DROP_STUDS then
					problem(
						("capture.stage.ledge drops %g studs; at least %d for a landing with weight"):format(
							ledge.size[2],
							LEDGE_MIN_DROP_STUDS
						)
					)
				end
				if ledge.standInset <= 0 or ledge.standInset >= ledge.size[3] then
					problem("capture.stage.ledge.standInset must be inside the ledge's top (0 < inset < size Z)")
				end
				if isNumber(stage.standHeightTolerance) and stage.standHeightTolerance >= ledge.size[2] then
					problem(
						"capture.stage.standHeightTolerance must be under the ledge's height (it tells the top from the field)"
					)
				end
				for _, part in { { "ledge", ledge }, { "ledge.ramp", ledge.ramp } } do
					local row: any = part[2]
					if typeof(row) ~= "table" then
						continue
					end
					if palette.tokens[row.colorToken] == nil then
						problem(
							("capture.stage.%s.colorToken '%s' is not a palette token"):format(
								part[1],
								tostring(row.colorToken)
							)
						)
					end
					if not isMaterial(row.material) then
						problem(
							("capture.stage.%s.material '%s' is not an Enum.Material"):format(
								part[1],
								tostring(row.material)
							)
						)
					end
				end
			end
			local areaOk = typeof(area) == "table"
				and typeof(area.position) == "table"
				and #area.position == 3
				and isNumber(area.facing)
			if not areaOk then
				problem("capture.stage.area must have a position and a facing")
			end
			local rampOk = ledgeOk
				and typeof(ledge.ramp) == "table"
				and typeof(ledge.ramp.size) == "table"
				and #ledge.ramp.size == 3
			if rampOk and areaOk and isNumber(stage.awayStuds) then
				-- Every spot on the field, the area's off the ledge and the open shot's on it.
				local inner = playground.fieldRadius - stage.awayStuds
				for _, open in { false, true } do
					local x, _, z = logic.standSpot(open, area, ledge)
					if math.sqrt(x * x + z * z) >= inner then
						problem(
							("capture.stage.%s spot must stand %g studs inside the field's edge (awayStuds)"):format(
								if open then "ledge" else "area",
								stage.awayStuds
							)
						)
					end
					if logic.onLedge(ledge, x, z) ~= open then
						problem(
							if open
								then "capture.stage.ledge: the open shot's spot must stand on the ledge"
								else "capture.stage.area must stand off the ledge"
						)
					end
				end
				-- The ledge and its ramp off the field's spawn points.
				local reach = math.max(ledge.size[1], ledge.size[3]) / 2 + playground.spawnScatterRadius
				local rx, _, rz = logic.rampFrame(ledge)
				local rampReach = math.max(ledge.ramp.size[1], ledge.ramp.size[3]) / 2 + playground.spawnScatterRadius
				for spawnIndex, spawn in playground.spawns do
					local dx, dz = spawn.position[1] - ledge.position[1], spawn.position[3] - ledge.position[3]
					if math.sqrt(dx * dx + dz * dz) <= reach then
						problem(("capture.stage.ledge stands on playground spawn %d's scatter"):format(spawnIndex))
					end
					dx, dz = spawn.position[1] - rx, spawn.position[3] - rz
					if math.sqrt(dx * dx + dz * dz) <= rampReach then
						problem(("capture.stage.ledge.ramp stands on playground spawn %d's scatter"):format(spawnIndex))
					end
				end
				-- No staged enemy on the ledge.
				for index, shot in shots do
					if
						typeof(shot) ~= "table"
						or typeof(shot.stage) ~= "table"
						or typeof(shot.stage.enemies) ~= "table"
					then
						continue
					end
					local x, _, z, facing = logic.standSpot(shot.stage.open == true, area, ledge)
					for enemyIndex, entry in shot.stage.enemies do
						if typeof(entry) ~= "table" or not isNumber(entry.side) or not isNumber(entry.distance) then
							continue
						end
						local ex, ez = logic.around(x, z, facing, entry.side, entry.distance)
						if logic.onLedge(ledge, ex, ez) then
							problem(
								("capture.shots[%d].stage.enemies[%d] stands on the ledge"):format(index, enemyIndex)
							)
						end
					end
				end
			end
			-- The ring's disc: thin, palette-coloured, a real material, see-through but shown.
			local ring = if typeof(walk) == "table" then walk.ring else nil
			if typeof(ring) ~= "table" then
				problem("capture.walk.ring must be a table")
			else
				if
					not isNumber(ring.thickness)
					or ring.thickness <= 0
					or (isNumber(stage.standHeightTolerance) and ring.thickness >= stage.standHeightTolerance)
				then
					problem("capture.walk.ring.thickness must be positive and under capture.stage.standHeightTolerance")
				end
				if palette.tokens[ring.colorToken] == nil then
					problem(
						("capture.walk.ring.colorToken '%s' is not a palette token"):format(tostring(ring.colorToken))
					)
				end
				if not isMaterial(ring.material) then
					problem(("capture.walk.ring.material '%s' is not an Enum.Material"):format(tostring(ring.material)))
				end
				if not isNumber(ring.transparency) or ring.transparency < 0 or ring.transparency >= 1 then
					problem("capture.walk.ring.transparency must be in [0, 1)")
				end
			end
		end
	end

	local aim = dev.aim
	local trace = dev.trace
	if typeof(aim) ~= "table" then
		problem("aim table is missing")
		return problems
	end
	if typeof(trace) ~= "table" then
		problem("trace table is missing")
		return problems
	end

	local numeric = {
		"faceToleranceDegrees",
		"faceTimeoutSeconds",
		"faceDegreesPerSecond",
		"replicationSettleSeconds",
		"artHoldSeconds",
		"swingGapSeconds",
		"runTimeoutSeconds",
		"actionSettleSeconds",
	}
	for _, key in numeric do
		if not isNumber(aim[key]) or aim[key] <= 0 then
			problem(("aim.%s must be a positive number"):format(key))
		end
	end
	if not isNumber(trace.runTimeoutSeconds) or trace.runTimeoutSeconds <= 0 then
		problem("trace.runTimeoutSeconds must be a positive number")
	end
	if #problems > 0 then
		return problems
	end

	-- Names
	if not isName(aim.bindableName) then
		problem("aim.bindableName must be a plain instance name")
	end
	if not isName(trace.bindableName) then
		problem("trace.bindableName must be a plain instance name")
	end
	if aim.bindableName == trace.bindableName then
		problem("aim.bindableName and trace.bindableName must differ")
	end
	if typeof(trace.printPrefix) ~= "string" or trace.printPrefix == "" then
		problem("trace.printPrefix must be a non-empty string")
	end
	local function checkDecimals(name: string, decimals: any)
		if not isWhole(decimals) or decimals < 0 or decimals > MAX_DECIMALS then
			problem(("%s.decimals must be a whole number from 0 to %d"):format(name, MAX_DECIMALS))
		end
	end
	checkDecimals("aim", aim.decimals)
	checkDecimals("trace", trace.decimals)

	-- Facing
	local acceptance = math.deg(math.acos(1 - combat.facingTolerance))
	if aim.faceToleranceDegrees >= acceptance then
		problem(
			("aim.faceToleranceDegrees (%g) must be under the server's facing acceptance (%.2f degrees)"):format(
				aim.faceToleranceDegrees,
				acceptance
			)
		)
	end
	local combatAim = combat.aim
	if typeof(combatAim) == "table" then
		if isNumber(combatAim.snapDegrees) and aim.faceToleranceDegrees >= combatAim.snapDegrees then
			problem(
				("aim.faceToleranceDegrees (%g) must be under combat.aim.snapDegrees (%g): the swing's snap finishes the turn"):format(
					aim.faceToleranceDegrees,
					combatAim.snapDegrees
				)
			)
		end
		if isNumber(combatAim.lockTurnRate) and combatAim.lockTurnRate > 0 then
			local needed = HALF_TURN_DEGREES / combatAim.lockTurnRate
			if aim.faceTimeoutSeconds < needed then
				problem(
					("aim.faceTimeoutSeconds (%g) is shorter than the lock turn from straight behind (%.3f s)"):format(
						aim.faceTimeoutSeconds,
						needed
					)
				)
			end
		end
	end
	local devTurn = HALF_TURN_DEGREES / aim.faceDegreesPerSecond
	if aim.faceTimeoutSeconds < devTurn then
		problem(
			("aim.faceTimeoutSeconds (%g) is shorter than the dev turn from straight behind (%.3f s)"):format(
				aim.faceTimeoutSeconds,
				devTurn
			)
		)
	end
	if aim.replicationSettleSeconds < combat.lagAllowance then
		problem(
			("aim.replicationSettleSeconds (%g) must cover combat.lagAllowance (%g)"):format(
				aim.replicationSettleSeconds,
				combat.lagAllowance
			)
		)
	end
	if aim.actionSettleSeconds < combat.lagAllowance then
		problem(
			("aim.actionSettleSeconds (%g) must cover combat.lagAllowance (%g)"):format(
				aim.actionSettleSeconds,
				combat.lagAllowance
			)
		)
	end

	-- The Art hold
	local stance = combat.startPoseTime + combat.activationHold
	if aim.artHoldSeconds <= stance then
		problem(
			("aim.artHoldSeconds (%g) must pass the start pose and activation hold (%g)"):format(
				aim.artHoldSeconds,
				stance
			)
		)
	end
	if aim.artHoldSeconds >= combat.activationCancelTime then
		problem(
			("aim.artHoldSeconds (%g) must be short of combat.activationCancelTime (%g)"):format(
				aim.artHoldSeconds,
				combat.activationCancelTime
			)
		)
	end

	-- The loadout's attacks: the basic chain of its weapon and its quick-slot Arts.
	local loadout = playground.loadout
	local category = weapons.category(loadout.weapon)
	local latestBasicClose = 0
	local mostWindows = 0
	if category == nil then
		problem(("playground loadout weapon %s has no category"):format(tostring(loadout.weapon)))
	else
		for index = 1, combat.basicChainLength do
			local path = ("%splayer/%s/Basic%d"):format(CLIPS, category, index)
			local ok, clip = pcall(ctx.load, path)
			if not ok then
				problem(("no basic clip at %s"):format(path))
				continue
			end
			local windows = sampler.hitWindows(clip)
			mostWindows = math.max(mostWindows, #windows)
			for _, window in windows do
				latestBasicClose = math.max(latestBasicClose, window.close)
			end
		end
	end
	local longestArt = 0
	for _, artId in loadout.artSlots do
		local art = arts.byId(artId)
		if art == nil then
			continue -- the playground validator reports it
		end
		longestArt = math.max(longestArt, art.total + art.postMotion)
		mostWindows = math.max(mostWindows, art.hits)
	end

	-- Swing spacing
	local rate = world.anticheat.remoteRates.BasicAttackRequest.perSecond
	if aim.swingGapSeconds < 1 / rate then
		problem(
			("aim.swingGapSeconds (%g) is faster than BasicAttackRequest's refill (%g a second)"):format(
				aim.swingGapSeconds,
				rate
			)
		)
	end
	if aim.swingGapSeconds < combat.basicHitDuration then
		problem(
			("aim.swingGapSeconds (%g) must outlast the server's basic swing (basicHitDuration %g)"):format(
				aim.swingGapSeconds,
				combat.basicHitDuration
			)
		)
	end
	local seen = latestBasicClose + combat.lagAllowance
	if aim.swingGapSeconds < seen then
		problem(
			("aim.swingGapSeconds (%g) must outlast the latest basic hit window plus the lag allowance (%g)"):format(
				aim.swingGapSeconds,
				seen
			)
		)
	end
	if aim.swingGapSeconds > combat.basicChainWindow then
		problem(
			("aim.swingGapSeconds (%g) must stay inside combat.basicChainWindow (%g) so the chain carries on"):format(
				aim.swingGapSeconds,
				combat.basicChainWindow
			)
		)
	end

	-- Run timeouts
	local artRun = longestArt + aim.artHoldSeconds + combat.lagAllowance
	if aim.runTimeoutSeconds < artRun then
		problem(
			("aim.runTimeoutSeconds (%g) must outlast the longest loadout Art from the press (%g)"):format(
				aim.runTimeoutSeconds,
				artRun
			)
		)
	end
	local serverRun = longestArt + combat.lagAllowance
	if trace.runTimeoutSeconds < serverRun then
		problem(
			("trace.runTimeoutSeconds (%g) must outlast the longest loadout Art (%g)"):format(
				trace.runTimeoutSeconds,
				serverRun
			)
		)
	end

	-- Counts
	if not isWhole(aim.maxSwings) or aim.maxSwings < combat.basicChainLength then
		problem(
			("aim.maxSwings must be a whole number of at least combat.basicChainLength (%d)"):format(
				combat.basicChainLength
			)
		)
	elseif not isWhole(trace.keepEvents) or trace.keepEvents < aim.maxSwings * mostWindows then
		problem(
			("trace.keepEvents must be a whole number of at least aim.maxSwings x the most windows a loadout attack has (%d)"):format(
				aim.maxSwings * mostWindows
			)
		)
	end

	return problems
end
