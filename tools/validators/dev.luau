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
	and at most the enemy's own, a `releaseAfter` only on one let go, inside the take, under a
	prompt beat at that moment), takes the Lock camera only when it locks on or else a
	capture.cameras view, has a cameraSide of 1 or -1, prompt beats from 0 in order inside the take,
	and a perform list (CF). Each press, an entry or a chain step, is an input.luau action or
	capture.perform.moveAction (the stick: a name no input action has), held a positive time; a
	Move holds a stick {right, forward} of length (0, 1] and only a Move has a stick or a sprint;
	`enemy` names a staged enemy by index; an Art press is held past the start pose and activation
	and short of the cancel time. Each entry is timed by exactly one of `at` (letting go inside
	the take; timed Moves never overlap), `onClip` (a reaction: an attack clip, with a
	HitWindowOpen, of the staged enemy it names, which the shot lets go; led by 0 or more and under
	combat.parryWindow for a Guard, at most the wind-up after the clip's first event for any other
	press; `repeats` and `lock` booleans; an optional `to` above 0 and inside the take, past which
	nothing of it goes down (D-CI3); a `chain` of steps each a `delay` of 0 or more after the
	one before, timed by nothing else, a `cycle` of Art actions starting with its own, `within`
	only on a Move step) and `every` (a standing rule: BasicAttack with a positive `within`, or
	LockOn, inside 0 <= from < to <= the take). A timed attack lands where its prompts say: an Art launches on its release, so
	a prompt beat comes up at its press (hold) and one at its release (let go), and it is held at
	least capture.artGlowSeconds past the start pose so the lit stance reads; a basic swings on its
	press, which a beat marks. A released Charger says what its first charge does to a player standing on the
	spot (`charge`, from inside the charge band): Meets (the line's reach covers the root) or Passes
	(the line ends short of the body); no other entry has one. The staged views name a known anchor
	and reference, degrees in [0, 180], a positive distance, a height of 0 or more and a focusBias in
	[0, 1]. The hotkeys are distinct,
	off input.luau's keyboard bindings, never a function key, autoPerform and releaseStage among
	them, and no walk cancel key; auto-perform starts off. The stage: a plain remote name, positive
	request rate, away distance (past camera.luau lock.range) and hold wait (under
	stageTimeoutSeconds); a ledge at least LEDGE_MIN_DROP_STUDS tall, its stand inset on its top,
	standHeightTolerance under its height, palette colours and real materials; every stand spot
	awayStuds inside the field's edge, the area's off the ledge and the open shot's on it; the ledge
	and its ramp off every spawn's scatter; no staged enemy on the ledge; the ring's disc thinner
	than standHeightTolerance, palette-coloured, a real material, transparency in [0, 1).

	The capture's walk into the stand ring (D-244: the staging never moves the player):
	- capture.stage's ring numbers are positive, and the ring is wider than the auto-walk's rest
	  target (capture.walk.restStuds), so a body at rest on the spot stands inside it;
	  walk.restDegrees is under a right angle and walk.secondWalks a whole number of 0 or more;
	- walk.sprintAction is an input.luau action whose speed (combat.luau
	  maxSpeedStudsPerSecond) is past choreo.luau locomotion.skidSpeedThreshold, so the walk's stop
	  is the Skid's and carries nothing (D-059);
	- walk.lookaheadStuds is shorter than the last leg (stage.approachStuds), and the let-go below
	  the Skid's threshold (walk.carrySeconds at locomotion runSpeed) is on it too;
	  walk.carrySeconds is under locomotion.stopStepsSeconds, the two-step stop's longest carry;
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
		for _, key in
			{
				"timeoutSeconds",
				"waypointStuds",
				"lookaheadStuds",
				"carrySeconds",
				"restSpeed",
				"restStuds",
				"restDegrees",
			}
		do
			if not isNumber(walk[key]) or walk[key] <= 0 then
				problem(("capture.walk.%s must be a positive number"):format(key))
			end
		end
		if not isNumber(walk.secondWalks) or walk.secondWalks < 0 or walk.secondWalks % 1 ~= 0 then
			problem("capture.walk.secondWalks must be a whole number of 0 or more")
		end
		local ledge = stage.ledge
		local ramp = if typeof(ledge) == "table" and typeof(ledge.ramp) == "table" then ledge.ramp.size else nil
		if typeof(ramp) ~= "table" or #ramp ~= 3 then
			problem("capture.stage.ledge.ramp.size must be { width, height, length }")
		end
		if #problems == walkProblems then
			local choreo = ctx.load("src/shared/data/choreo")
			local logic = ctx.load("src/server/dev/DevStageLogic")
			local input = ctx.load("src/shared/data/input")
			local locomotion = choreo.locomotion
			if walk.restStuds >= stage.standRadius then
				problem(
					("capture.walk.restStuds (%g) must be under capture.stage.standRadius (%g): a body at rest on the spot stands in the ring"):format(
						walk.restStuds,
						stage.standRadius
					)
				)
			end
			if walk.restDegrees >= 90 then
				problem(("capture.walk.restDegrees (%g) must be under 90"):format(walk.restDegrees))
			end
			if typeof(walk.sprintAction) ~= "string" or table.find(input.actions, walk.sprintAction) == nil then
				problem(
					("capture.walk.sprintAction (%s) must be an input.luau action"):format(tostring(walk.sprintAction))
				)
			elseif combat.maxSpeedStudsPerSecond <= locomotion.skidSpeedThreshold then
				problem(
					("capture.walk.sprintAction: the sprint (combat maxSpeedStudsPerSecond %g) must be past choreo locomotion.skidSpeedThreshold (%g), so the walk's stop carries nothing"):format(
						combat.maxSpeedStudsPerSecond,
						locomotion.skidSpeedThreshold
					)
				)
			end
			if walk.lookaheadStuds >= stage.approachStuds then
				problem(
					("capture.walk.lookaheadStuds (%g) must be under capture.stage.approachStuds (%g): the walk follows the last leg's line"):format(
						walk.lookaheadStuds,
						stage.approachStuds
					)
				)
			end
			if walk.carrySeconds >= locomotion.stopStepsSeconds then
				problem(
					("capture.walk.carrySeconds (%g) must be under choreo locomotion.stopStepsSeconds (%g), the two-step stop's longest carry"):format(
						walk.carrySeconds,
						locomotion.stopStepsSeconds
					)
				)
			elseif walk.carrySeconds * locomotion.runSpeed >= stage.approachStuds then
				problem(
					("capture.walk.carrySeconds (%g) lets go %.2f studs short of the spot at run speed, off the last leg (capture.stage.approachStuds %g)"):format(
						walk.carrySeconds,
						walk.carrySeconds * locomotion.runSpeed,
						stage.approachStuds
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
		local ai = ctx.load("src/shared/data/ai")
		local rigs = ctx.load("src/shared/data/rigs")
		local cameras = if typeof(capture.cameras) == "table" then capture.cameras else {}
		local artHoldMin = combat.startPoseTime + combat.activationHold
		local artHoldMax = input.art.cancelTime
		-- A timed Art's lit stance on camera: from the end of its start pose to its release.
		local artGlow: number? = nil
		if not isNumber(capture.artGlowSeconds) or capture.artGlowSeconds <= 0 then
			problem("capture.artGlowSeconds must be a positive number of seconds")
		elseif combat.startPoseTime + capture.artGlowSeconds >= artHoldMax then
			problem(
				("capture.artGlowSeconds (%g) past the start pose (%g s) must end short of the cancel time (%g s)"):format(
					capture.artGlowSeconds,
					combat.startPoseTime,
					artHoldMax
				)
			)
		else
			artGlow = capture.artGlowSeconds
		end
		-- The player's body radius for a hit (HitSweep.bodyRadius: half the root's wider flat side),
		-- the root as the hit matrix builds it, scaled by PlayerR15's proportions.
		local rootSize = dev.hitMatrix.avatar.parts.HumanoidRootPart
		local proportions = rigs.PlayerR15.scale
		local playerRadius = math.max(rootSize[1] * proportions.bodyWidth, rootSize[3] * proportions.bodyDepth) / 2
		local function rushOf(def: any): any
			if def.archetype ~= "Charger" then
				return nil
			end
			for _, attack in def.attacks do
				if attack.arc == 0 or attack.groundShape == "Line" then
					return attack
				end
			end
			return nil
		end

		-- Auto-perform's vocabulary (CF): a press of capture.perform.moveAction holds the stick, not
		-- a key, so it is never an input.luau action itself.
		local moveAction: string? = nil
		if
			typeof(capture.perform) ~= "table"
			or typeof(capture.perform.moveAction) ~= "string"
			or capture.perform.moveAction == ""
			or table.find(input.actions, capture.perform.moveAction) ~= nil
		then
			problem(
				"capture.perform.moveAction must be a name that is not an input.luau action: a press of it holds the stick"
			)
		else
			moveAction = capture.perform.moveAction
		end
		local function isArt(action: string): boolean
			return action == "Art" or action:match("^ArtSlot") ~= nil
		end
		-- What every press of a perform list is, an entry or a chain step: a real action held a
		-- positive time; a Move holds a stick {right, forward} of length (0, 1], and only a Move has
		-- a stick or a sprint; `enemy` names a staged enemy by its index; an Art is held past the
		-- start pose and activation and short of the cancel time. False when the press is no press.
		local function checkPress(pressLabel: string, press: any, staged: { any }): boolean
			if
				typeof(press.action) ~= "string"
				or (table.find(input.actions, press.action) == nil and press.action ~= moveAction)
			then
				problem(
					("%s.action '%s' is not an input.luau action nor capture.perform.moveAction"):format(
						pressLabel,
						tostring(press.action)
					)
				)
				return false
			end
			if not isNumber(press.hold) or press.hold <= 0 then
				problem(pressLabel .. ".hold must be a positive number of seconds")
				return false
			end
			local move = press.action == moveAction
			if move then
				local stick = press.stick
				local whole = typeof(stick) == "table" and #stick == 2 and isNumber(stick[1]) and isNumber(stick[2])
				local length = if whole then math.sqrt(stick[1] * stick[1] + stick[2] * stick[2]) else 0
				if length <= 0 or length > 1 + 1e-9 then
					problem(pressLabel .. ".stick must be {right, forward} with a length above 0 and at most 1")
				end
			elseif press.stick ~= nil then
				problem(pressLabel .. ".stick is only for a capture.perform.moveAction press")
			end
			if press.sprint ~= nil then
				if typeof(press.sprint) ~= "boolean" then
					problem(pressLabel .. ".sprint must be true or false")
				elseif not move then
					problem(pressLabel .. ".sprint is only for a capture.perform.moveAction press")
				end
			end
			if press.enemy ~= nil and (not isWhole(press.enemy) or press.enemy < 1 or press.enemy > #staged) then
				problem(("%s.enemy must name one of the shot's staged enemies (1 to %d)"):format(pressLabel, #staged))
			end
			if isArt(press.action) and (press.hold <= artHoldMin or press.hold >= artHoldMax) then
				problem(
					("%s: an Art press is held past the start pose and activation (%g s) and short of the cancel time (%g s); got %g s"):format(
						pressLabel,
						artHoldMin,
						artHoldMax,
						press.hold
					)
				)
			end
			return true
		end
		-- A reaction (`onClip`): the clip this client draws for one of the shot's staged enemies
		-- (`enemy`, the first by default), an attack of that enemy, which the shot lets go; the
		-- press `lead` ahead of the clip's hit window: a guard inside the parry window, any other
		-- press after the clip's first event (the client hears the clip from it on). It may
		-- repeat on each play, lock the enemy on hearing it, and chain presses after it.
		local function checkReaction(pressLabel: string, press: any, staged: { any }, seconds: number?)
			local ok, clip = pcall(ctx.load, CLIPS .. tostring(press.onClip))
			local window: number? = nil
			local first: number? = nil
			if ok and typeof(clip) == "table" and typeof(clip.events) == "table" then
				for _, event in clip.events do
					if typeof(event) ~= "table" or not isNumber(event.time) then
						continue
					end
					first = math.min(first or event.time, event.time)
					if event.kind == "HitWindowOpen" and window == nil then
						window = event.time
					end
				end
			end
			if window == nil then
				problem(
					("%s.onClip '%s' must name a clip with a HitWindowOpen event"):format(
						pressLabel,
						tostring(press.onClip)
					)
				)
			end
			local index = if isWhole(press.enemy) then press.enemy else 1
			local entry = staged[index]
			local def = if typeof(entry) == "table" then enemies.byId(entry.enemy) else nil
			if def ~= nil then
				local names = {}
				local found = false
				for _, attack in def.attacks do
					local id = ("enemy/%s/%s"):format(tostring(def.skin), tostring(attack.clip))
					table.insert(names, id)
					found = found or id == press.onClip
				end
				if not found then
					problem(
						("%s.onClip '%s' must be an attack clip of the enemy it reacts to (stage.enemies[%d]: %s)"):format(
							pressLabel,
							tostring(press.onClip),
							index,
							table.concat(names, ", ")
						)
					)
				end
				if entry.held == true then
					problem(
						("%s reacts to an enemy the shot holds (stage.enemies[%d]): a held enemy never attacks"):format(
							pressLabel,
							index
						)
					)
				end
			end
			if not isNumber(press.lead) then
				problem(pressLabel .. ".lead must say how far ahead of the hit window the press comes")
			elseif press.action == "Guard" then
				if press.lead < 0 or press.lead >= combat.parryWindow then
					problem(
						("%s.lead (%g) must be 0 or more and under combat.parryWindow (%g)"):format(
							pressLabel,
							press.lead,
							combat.parryWindow
						)
					)
				end
			else
				local most = if window ~= nil and first ~= nil then window - first else math.huge
				if press.lead < 0 or press.lead > most + 1e-9 then
					problem(
						("%s.lead (%g) must be 0 or more and at most the clip's wind-up after its first event (%g s): the press comes after this client hears the clip"):format(
							pressLabel,
							press.lead,
							most
						)
					)
				end
			end
			for _, key in { "repeats", "lock" } do
				if press[key] ~= nil and typeof(press[key]) ~= "boolean" then
					problem(("%s.%s must be true or false"):format(pressLabel, key))
				end
			end
			-- `to` (D-CI3): nothing of the reaction, its chain included, goes down past it, so what
			-- it launches lands before the take's cut.
			if
				press.to ~= nil
				and (not isNumber(press.to) or press.to <= 0 or (seconds ~= nil and press.to > seconds))
			then
				problem(
					("%s.to (%s) must be above 0 and at most the take (%s s): nothing of the reaction goes down past it"):format(
						pressLabel,
						tostring(press.to),
						tostring(seconds)
					)
				)
			end
			if press.chain == nil then
				return
			end
			if typeof(press.chain) ~= "table" or #press.chain == 0 then
				problem(pressLabel .. ".chain must list at least one step")
				return
			end
			-- Each step a press `delay` after the step before it lets go; a Move step lets go at
			-- `within` studs of the lock's target or at its hold; an Art step may cycle Arts, one per
			-- play of the reaction.
			for stepIndex, step in press.chain do
				local stepLabel = ("%s.chain[%d]"):format(pressLabel, stepIndex)
				if typeof(step) ~= "table" then
					problem(stepLabel .. " must be a table")
					continue
				end
				if not checkPress(stepLabel, step, staged) then
					continue
				end
				if not isNumber(step.delay) or step.delay < 0 then
					problem(stepLabel .. ".delay must be 0 or more seconds after the step before it")
				end
				for _, key in { "at", "onClip", "every", "lead", "repeats", "lock", "chain", "from", "to" } do
					if step[key] ~= nil then
						problem(("%s.%s: a chain step is timed by its delay alone"):format(stepLabel, key))
					end
				end
				if step.cycle ~= nil then
					local cycle = step.cycle
					if typeof(cycle) ~= "table" or #cycle == 0 or cycle[1] ~= step.action then
						problem(stepLabel .. ".cycle must start with the step's own action")
					end
					if typeof(cycle) == "table" then
						for _, action in cycle do
							if
								typeof(action) ~= "string"
								or table.find(input.actions, action) == nil
								or not isArt(action)
							then
								problem(
									stepLabel .. ".cycle must list Art actions (input.luau Art and ArtSlot actions)"
								)
								break
							end
						end
					end
				end
				if step.within ~= nil then
					if step.action ~= moveAction then
						problem(stepLabel .. ".within is only for a standing BasicAttack or a Move chain step")
					elseif not isNumber(step.within) or step.within <= 0 then
						problem(stepLabel .. ".within must be a positive number of studs")
					end
				end
			end
		end
		-- A standing rule (`every`): a basic on the lock's target in reach (`within`) or the lock
		-- (when it is off), every so often from `from` (0) to `to` (the take's end), never while a
		-- reaction waits or its chain runs.
		local function checkStanding(pressLabel: string, press: any, seconds: number?)
			if press.action ~= "BasicAttack" and press.action ~= "LockOn" then
				problem(pressLabel .. ": a standing rule (`every`) presses only BasicAttack or LockOn")
			end
			if not isNumber(press.every) or press.every <= 0 then
				problem(pressLabel .. ".every must be a positive number of seconds")
			end
			local from = if press.from == nil then 0 else press.from
			local to = if press.to == nil then seconds else press.to
			if
				not isNumber(from)
				or (to ~= nil and not isNumber(to))
				or from < 0
				or (to ~= nil and from >= to)
				or (to ~= nil and seconds ~= nil and to > seconds)
			then
				problem(
					("%s must run 0 <= from < to <= the take (%s s); got from %s, to %s"):format(
						pressLabel,
						tostring(seconds),
						tostring(press.from),
						tostring(press.to)
					)
				)
			end
			if press.action == "BasicAttack" then
				if press.within == nil then
					problem(pressLabel .. ": a standing BasicAttack presses only in reach: `within`, in studs")
				elseif not isNumber(press.within) or press.within <= 0 then
					problem(pressLabel .. ".within must be a positive number of studs")
				end
			elseif press.within ~= nil then
				problem(pressLabel .. ".within is only for a standing BasicAttack or a Move chain step")
			end
		end

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
					-- Let go partway through the take (CF): when, inside the take, under the prompt beat
					-- that says so.
					if entry.releaseAfter ~= nil then
						if entry.held ~= false then
							problem(entryLabel .. ".releaseAfter is only for an enemy the shot lets go (held = false)")
						elseif
							not isNumber(entry.releaseAfter)
							or entry.releaseAfter < 0
							or (seconds ~= nil and entry.releaseAfter >= seconds)
						then
							problem(
								("%s.releaseAfter (%s) must be 0 or more and inside the take (%s s)"):format(
									entryLabel,
									tostring(entry.releaseAfter),
									tostring(seconds)
								)
							)
						else
							local beat = false
							if typeof(shot.prompts) == "table" then
								for _, prompt in shot.prompts do
									beat = beat
										or (
											typeof(prompt) == "table"
											and isNumber(prompt.at)
											and math.abs(prompt.at - entry.releaseAfter) < 1e-6
										)
								end
							end
							if not beat then
								problem(
									("%s.releaseAfter (%g s) needs a prompt beat at that moment, saying it is let go"):format(
										entryLabel,
										entry.releaseAfter
									)
								)
							end
						end
					end
					-- A released Charger's first charge, against a player standing on the spot (CS7).
					local rush = rushOf(def)
					if rush == nil or entry.held ~= false then
						if entry.charge ~= nil then
							problem(entryLabel .. ".charge is only for a released Charger")
						end
					elseif entry.charge ~= "Meets" and entry.charge ~= "Passes" then
						problem(
							entryLabel
								.. ".charge must say what the first charge does to the player on the spot: Meets or Passes"
						)
					elseif isNumber(entry.distance) then
						local tuning = ai.tuningFor("Charger")
						if entry.distance < tuning.minChargeDistance or entry.distance > tuning.maxChargeDistance then
							problem(
								("%s.distance (%g) must be inside the charge band [%g, %g]: it crouches from where it stands as the take starts"):format(
									entryLabel,
									entry.distance,
									tuning.minChargeDistance,
									tuning.maxChargeDistance
								)
							)
						elseif entry.charge == "Meets" and entry.distance > rush.reach then
							problem(
								("%s: a charge that Meets needs the line (reach %g) to reach the player's root; distance %g"):format(
									entryLabel,
									rush.reach,
									entry.distance
								)
							)
						elseif entry.charge == "Passes" and entry.distance - playerRadius <= rush.reach then
							problem(
								("%s: a charge that Passes needs the line (reach %g) to end short of the player's body (radius %.2f); distance %g"):format(
									entryLabel,
									rush.reach,
									playerRadius,
									entry.distance
								)
							)
						end
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
			-- Auto-perform (CF): real actions, each timed by exactly one of a moment (`at`), a clip
			-- this client draws (`onClip`, a reaction) and a standing rule (`every`).
			local perform = shot.perform
			if typeof(perform) ~= "table" then
				problem(label .. ".perform must be a list (empty for none)")
				continue
			end
			local staged = if shotStage ~= nil and typeof(shotStage.enemies) == "table" then shotStage.enemies else {}
			local moves: { { index: number, at: number, hold: number } } = {}
			for pressIndex, press in perform do
				local pressLabel = ("%s.perform[%d]"):format(label, pressIndex)
				if typeof(press) ~= "table" then
					problem(pressLabel .. " must be a table")
					continue
				end
				if not checkPress(pressLabel, press, staged) then
					continue
				end
				local timings = (if press.at ~= nil then 1 else 0)
					+ (if press.onClip ~= nil then 1 else 0)
					+ (if press.every ~= nil then 1 else 0)
				if timings ~= 1 then
					problem(
						pressLabel
							.. " must be timed by exactly one of `at` and `onClip`, or by `every` (a standing rule)"
					)
				elseif press.at ~= nil then
					if not isNumber(press.at) or press.at < 0 then
						problem(pressLabel .. ".at must be 0 or more")
					else
						if seconds ~= nil and press.at + press.hold >= seconds then
							problem(("%s must let go inside the take (%g s)"):format(pressLabel, seconds))
						end
						if press.action == moveAction then
							table.insert(moves, { index = pressIndex, at = press.at, hold = press.hold })
						end
					end
				elseif press.onClip ~= nil then
					checkReaction(pressLabel, press, staged, seconds)
				else
					checkStanding(pressLabel, press, seconds)
				end
				-- Each timing's own fields only.
				if press.onClip == nil then
					for _, key in { "repeats", "lock", "chain" } do
						if press[key] ~= nil then
							problem(("%s.%s is only for a clip-timed press"):format(pressLabel, key))
						end
					end
				end
				if press.every == nil then
					if press.from ~= nil or (press.to ~= nil and press.onClip == nil) then
						problem(
							pressLabel
								.. ".from and .to are only for a standing rule (`every`); a reaction (`onClip`) may end at a `to`"
						)
					end
					if press.within ~= nil then
						problem(pressLabel .. ".within is only for a standing BasicAttack or a Move chain step")
					end
				end
				local art = isArt(press.action)
				-- A timed attack lands where its prompts say (CS5): an Art launches on its release, so
				-- a beat tells the player to press and hold at `at` and one to let go at `at + hold`,
				-- the lit stance between long enough to read; a basic swings on its press.
				if isNumber(press.at) and (art or press.action == "BasicAttack") then
					local function beatAt(at: number): boolean
						if typeof(prompts) ~= "table" then
							return false
						end
						for _, beat in prompts do
							if typeof(beat) == "table" and isNumber(beat.at) and math.abs(beat.at - at) < 1e-6 then
								return true
							end
						end
						return false
					end
					if not art then
						if not beatAt(press.at) then
							problem(
								("%s: a basic needs a prompt beat at its press (%g s), where it swings"):format(
									pressLabel,
									press.at
								)
							)
						end
					else
						if not beatAt(press.at) then
							problem(
								("%s: a timed Art needs a prompt beat at its press (%g s), telling the player to hold the key"):format(
									pressLabel,
									press.at
								)
							)
						end
						if not beatAt(press.at + press.hold) then
							problem(
								("%s: a timed Art needs a prompt beat at its release (%g s), where it launches"):format(
									pressLabel,
									press.at + press.hold
								)
							)
						end
						if artGlow ~= nil and press.hold - combat.startPoseTime < artGlow - 1e-6 then
							problem(
								("%s: a timed Art holds its glow at least capture.artGlowSeconds (%g s) on camera, past the start pose (%g s); got %g s"):format(
									pressLabel,
									artGlow,
									combat.startPoseTime,
									press.hold - combat.startPoseTime
								)
							)
						end
					end
				end
			end
			-- Timed Move presses never overlap: one stick at a time.
			table.sort(moves, function(a, b): boolean
				return a.at < b.at
			end)
			for order = 2, #moves do
				local before, this = moves[order - 1], moves[order]
				if this.at < before.at + before.hold - 1e-6 then
					problem(
						("%s.perform[%d] overlaps the Move before it (perform[%d], held to %g s): one stick at a time"):format(
							label,
							this.index,
							before.index,
							before.at + before.hold
						)
					)
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
