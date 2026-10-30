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

	The ClipLab's light (dev place only): key, fill and rim lights each a position, a positive range
	and brightness and a palette color, the key and the fill on the side of the rigs the lab camera
	starts on (clipLab.camera.startYaw) and the rim behind them, so the faces the camera sees are
	lit and a dark outfit's edge reads against the backdrop; the backdrop a part name and a palette
	color; the lab's ambient colors and diffuse scale in [0, 1] and its exposure in [-3, 3].

	The capture's timeScale.steps are each above 0 and at most 1, and timeScale.default is one of
	them: the capture slows the local body with them (CharacterController.setCaptureTimeScale), so
	a step past 1x would move it faster than the anti-cheat's sprint cap.

	The capture's shots (F12, tests/data/devCapture.spec.luau): every shot stages at least one
	enemy the game has (a positive distance, a side within a half turn, held a boolean, hp above 0
	and at most the enemy's own, a `releaseAfter` only on one let go, inside the take, under a
	prompt beat at that moment, an `attacks` limit only on one let go, a whole number of 1 or
	more: FK2), takes the Lock camera only when it locks on or else a
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
	nothing of it goes down (D-320); a `chain` of steps each a `delay` of 0 or more after the
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
	them, and no walk cancel key; auto-perform starts off. No dev key (capture.hotkeys,
	clipLab.hotkeys, capture.walk.cancelKeys) is one Studio keeps for its own shortcuts
	(STUDIO_SHORTCUT_KEYS): pressed in Play it never reaches the game. The stage: a plain remote
	name, positive request rate, away distance (past camera.luau lock.range) and hold wait (under
	stageTimeoutSeconds); a ledge at least LEDGE_MIN_DROP_STUDS tall, its stand inset on its top,
	standHeightTolerance under its height, palette colours and real materials; every stand spot
	awayStuds inside the field's edge, the area's off the ledge (its ring routeMarginStuds clear of
	the ledge and its ramp: a body where they go walks there first) and the open shot's on it; the
	ledge and its ramp off every spawn's scatter; no staged enemy on the ledge; the ring's disc thinner
	than standHeightTolerance, palette-coloured, a real material, transparency in [0, 1).

	The capture's render-frame tick (D-336): capture.frameTick.size is a whole number of pixels
	from 1 to MAX_TICK_PIXELS and its margin a whole number of 0 or more; its tokens are two
	different palette tokens whose relative luminance differs by at most maxLuminanceStep (above 0,
	at most MAX_TICK_LUMINANCE_STEP), so the square it swaps every rendered frame never flashes.

	The capture's walk into the stand ring (D-244: the staging never moves the player):
	- capture.stage's ring numbers are positive, and the ring is wider than the auto-walk's rest
	  target (capture.walk.restStuds), so a body at rest on the spot stands inside it;
	  walk.restDegrees is under a right angle and walk.secondWalks a whole number of 0 or more;
	- the turn on the spot (step 14): walk.faceDegreesPerSecond is positive and
	  walk.faceSettleSeconds 0 or more, and a half turn at that rate plus the stand after it fit
	  inside walk.timeoutSeconds;
	- walk.sprintAction is an input.luau action whose speed (combat.luau
	  maxSpeedStudsPerSecond) is past choreo.luau locomotion.skidSpeedThreshold, so the walk's stop
	  is the Skid's and carries nothing (D-059);
	- walk.lookaheadStuds is shorter than the last leg (stage.approachStuds), and the let-go below
	  the Skid's threshold (walk.carrySeconds at locomotion runSpeed) is on it too;
	  walk.carrySeconds is under locomotion.stopStepsSeconds, the two-step stop's longest carry;
	- capture.walk.restSpeed is at most choreo.luau locomotion.idleSpeedThreshold (at rest is where
	  the Locomotion stands the body) and under locomotion.stopEndSpeed (the two-step stop has
	  ended when the body is that slow);
	- the ledge's ramp is as tall as the ledge, no wider, and no steeper than a Humanoid walks
	  (MaxSlopeAngle, left at its default), behind the open shot's start;
	- the open shot's approach stands on the ramp, and walk.timeoutSeconds covers the route from
	  the stage area up to the open shot's spot at locomotion walkSpeed;
	- walk.renderOrder runs after the control script's input step and before the character
	  controller's step (choreo.luau renderOrder.character), and walk.cancelKeys are real KeyCodes;
	- the corrections (CW): walk.askSettleSeconds x (secondWalks + 2) fits walk.timeoutSeconds;
	  walk.correctWithinStuds covers the ring and stays on the last leg (stage.standRadius to
	  approachStuds); walk.correctBackStuds is past waypointStuds and on the last leg;
	  walk.correctSpeed is at most locomotion runSpeed (a walk, never the sprint);
	  walk.creepEndSpeed is under locomotion idleSpeedThreshold (the two-step stop carries
	  nothing) and creepEndSpeed x creepSeconds is under restStuds;
	- the blocked rule (316(b)): walk.blockedSeconds and blockedStuds are positive,
	  blockedSeconds is under timeoutSeconds and over the correction's creep across its last
	  blockedStuds, and blockedStuds is under restStuds.

	DevCombat's Studio test hooks (`hooks`, D-333):
	- hooks.arriveStuds is positive and under ai.luau leash.homeRadius, so a walked body stands at
	  home where it stops and its leash never walks it back;
	- hooks.walkTimeoutSeconds gives the slowest walking enemy WALK_DETOUR times its straight walk of
	  hooks.maxWalkStuds;
	- hooks.chargeTimeoutSeconds outlasts every Charger rush (every def, Elite too): its wind-up with
	  ai.hitStop.maxPausePerAttack of hit-stop in it, then the longer of its strike beat and its run
	  (reach plus the Charger's overshoot at ai.rushSpeed);
	- hooks.folderName is a plain instance name no other part of the place uses (the Playground
	  model, its kill volume, the stage's ledge and ramp); hooks.maxParts is whole, 1 to
	  MAX_DEV_PARTS; 0 < minPartStuds < maxPartStuds <= the engine's 2048; hooks.maxAfterSeconds is
	  positive and at most chargeTimeoutSeconds (a late part lands while a charge still waits);
	  hooks.maxNameLength is whole, 1 to 100 (the engine's name cap); the parts' colour is a palette
	  token and their material a real Enum.Material; hooks.maxPackSize ("pack", item 315) is whole,
	  from 2 to the members the widest spawn scatter (playground spawnScatterRadius widened by
	  spawnSpacing) holds spawnSpacing.minStuds apart;
	- the Studio frame cap (303): frameCap.attribute is a plain name no other dev attribute uses;
	  frameCap.least and most are whole frames a second, 1 <= least < most <= 240, with the 30 the
	  Studio item asks for inside; frameCap.priority runs after every renderOrder row of choreo,
	  camera and fx and after capture.walk.renderOrder, so the cap holds a whole drawn frame;
	- "place" on a wind-up (302(b)): hooks.maxPlaceAfterSeconds reaches past every enemy attack's
	  wind-up with ai.hitStop.maxPausePerAttack of hit-stop in it and its strike, and is under
	  hooks.windUpWaitSeconds, which outlasts every enemy attack's whole beat (wind-up, pauses,
	  strike and recovery), so an enemy attacking on a loop starts its next wind-up inside the wait.
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
-- Keys Studio keeps for its own shortcuts while "Respect Studio shortcuts when game has focus" is
-- on: pressed in Play they never reach the game (measured in Studio on Windows). Enum.KeyCode names.
local STUDIO_SHORTCUT_KEYS = { "I", "O", "Home", "End", "PageUp", "PageDown", "F1", "F2", "F11", "F12" }
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

-- DevCombat's Studio test hooks (D-333): dev.luau `hooks`.
-- A walk gets this many times its straight walk at the slowest walking enemy's pace before it ends:
-- room for a path round an obstacle and a slide along another body.
local WALK_DETOUR = 2
-- The most parts the dev folder may hold, and the engine's own cap on a part's side (studs).
local MAX_DEV_PARTS = 256
local ENGINE_MAX_PART_STUDS = 2048
-- The engine's cap on an Instance.Name.
local MAX_INSTANCE_NAME = 100
-- The render-frame tick (D-336): a small square, its two colors as bright as each other.
local MAX_TICK_PIXELS = 32
local MAX_TICK_LUMINANCE_STEP = 0.1
-- The Studio frame cap (303): the rate the Studio item asks for, and the most a cap may hold to
-- (Studio's own highest option).
local FRAME_CAP_ASKED = 30
local FRAME_CAP_MOST = 240

local function checkHooks(ctx: Context, dev: any, problem: (message: string) -> ())
	local hooks = dev.hooks
	if typeof(hooks) ~= "table" then
		problem("hooks table is missing (DevCombat's enemy, walk, charge and part numbers)")
		return
	end
	local ai = ctx.load("src/shared/data/ai")
	local enemies = ctx.load("src/shared/data/enemies")
	local palette = ctx.load("src/shared/data/palette")
	local world = ctx.load("src/shared/data/world")
	local playground = ctx.load("src/shared/data/playground")

	-- "walk": arrived inside the home radius, so the leash never walks the body back.
	local homeRadius = ai.leash.homeRadius
	if not isNumber(hooks.arriveStuds) or hooks.arriveStuds <= 0 or hooks.arriveStuds >= homeRadius then
		problem(
			("hooks.arriveStuds (%s) must be positive and under ai.luau leash.homeRadius (%g)"):format(
				tostring(hooks.arriveStuds),
				homeRadius
			)
		)
	end
	if not isNumber(hooks.maxWalkStuds) or hooks.maxWalkStuds <= 0 then
		problem("hooks.maxWalkStuds must be a positive number of studs")
	else
		local slowest = math.huge
		for _, def in enemies.list() do
			if isNumber(def.moveSpeed) and def.moveSpeed > 0 then
				slowest = math.min(slowest, def.moveSpeed)
			end
		end
		local needed = WALK_DETOUR * hooks.maxWalkStuds / slowest
		if not isNumber(hooks.walkTimeoutSeconds) or hooks.walkTimeoutSeconds < needed then
			problem(
				("hooks.walkTimeoutSeconds (%s) must give the slowest walking enemy (%g studs a second) twice its longest walk (%g s)"):format(
					tostring(hooks.walkTimeoutSeconds),
					slowest,
					needed
				)
			)
		end
	end

	-- "charge": over once the rush is: its wind-up (paused by hits at most maxPausePerAttack), then
	-- the longer of its strike beat and its run (reach and overshoot at its rush speed).
	local longest = 0
	local overshoot = ai.archetypes.Charger.overshoot
	for _, base in enemies.list() do
		for _, def in { enemies.scaled(base), enemies.variant(enemies.scaled(base), "Elite") } do
			if def.archetype ~= "Charger" then
				continue
			end
			for _, attack in def.attacks do
				if attack.arc == 0 or attack.groundShape == "Line" then
					local run = (attack.reach + overshoot) / ai.rushSpeed(attack)
					longest =
						math.max(longest, attack.windUp + ai.hitStop.maxPausePerAttack + math.max(attack.strike, run))
				end
			end
		end
	end
	if not isNumber(hooks.chargeTimeoutSeconds) or hooks.chargeTimeoutSeconds <= longest then
		problem(
			("hooks.chargeTimeoutSeconds (%s) must outlast every Charger rush's wind-up, pauses and run (%.3f s)"):format(
				tostring(hooks.chargeTimeoutSeconds),
				longest
			)
		)
	end

	-- "part" and "clearparts".
	if not isName(hooks.folderName) then
		problem("hooks.folderName must be a plain instance name")
	else
		local taken = { world.playground.modelName, world.playground.killVolumeName }
		local stage = if typeof(dev.capture) == "table" then dev.capture.stage else nil
		local ledge = if typeof(stage) == "table" then stage.ledge else nil
		if typeof(ledge) == "table" then
			table.insert(taken, ledge.name)
			if typeof(ledge.ramp) == "table" then
				table.insert(taken, ledge.ramp.name)
			end
		end
		if table.find(taken, hooks.folderName) ~= nil then
			problem(("hooks.folderName '%s' is already a name in the place"):format(hooks.folderName))
		end
	end
	if not isWhole(hooks.maxParts) or hooks.maxParts < 1 or hooks.maxParts > MAX_DEV_PARTS then
		problem(("hooks.maxParts must be a whole number from 1 to %d"):format(MAX_DEV_PARTS))
	end
	local least, most = hooks.minPartStuds, hooks.maxPartStuds
	if not isNumber(least) or not isNumber(most) or least <= 0 or least >= most or most > ENGINE_MAX_PART_STUDS then
		problem(("hooks.minPartStuds and maxPartStuds must satisfy 0 < min < max <= %d"):format(ENGINE_MAX_PART_STUDS))
	end
	if
		not isNumber(hooks.maxAfterSeconds)
		or hooks.maxAfterSeconds <= 0
		or (isNumber(hooks.chargeTimeoutSeconds) and hooks.maxAfterSeconds > hooks.chargeTimeoutSeconds)
	then
		problem(
			("hooks.maxAfterSeconds (%s) must be positive and at most hooks.chargeTimeoutSeconds (%s): a late part lands while a charge still waits"):format(
				tostring(hooks.maxAfterSeconds),
				tostring(hooks.chargeTimeoutSeconds)
			)
		)
	end
	if not isWhole(hooks.maxNameLength) or hooks.maxNameLength < 1 or hooks.maxNameLength > MAX_INSTANCE_NAME then
		problem(("hooks.maxNameLength must be a whole number from 1 to %d"):format(MAX_INSTANCE_NAME))
	end
	-- "place" on a wind-up: `after` may reach anywhere in any wind-up and its strike, and the wait
	-- for one outlasts every attack's whole beat.
	local reachWindUp, wholeBeat = 0, 0
	for _, base in enemies.list() do
		for _, def in { enemies.scaled(base), enemies.variant(enemies.scaled(base), "Elite") } do
			for _, attack in def.attacks do
				local paused = attack.windUp + ai.hitStop.maxPausePerAttack
				reachWindUp = math.max(reachWindUp, paused + attack.strike)
				wholeBeat = math.max(wholeBeat, paused + attack.strike + attack.recovery)
			end
		end
	end
	local placeAfter, windUpWait = hooks.maxPlaceAfterSeconds, hooks.windUpWaitSeconds
	if not isNumber(placeAfter) or placeAfter < reachWindUp then
		problem(
			("hooks.maxPlaceAfterSeconds (%s) must reach past every enemy wind-up, its pauses and its strike (%.3f s)"):format(
				tostring(placeAfter),
				reachWindUp
			)
		)
	end
	if not isNumber(windUpWait) or windUpWait <= wholeBeat then
		problem(
			("hooks.windUpWaitSeconds (%s) must outlast every enemy attack's wind-up, pauses, strike and recovery (%.3f s)"):format(
				tostring(windUpWait),
				wholeBeat
			)
		)
	elseif isNumber(placeAfter) and placeAfter >= windUpWait then
		problem(
			("hooks.maxPlaceAfterSeconds (%s) must be under hooks.windUpWaitSeconds (%s)"):format(
				tostring(placeAfter),
				tostring(windUpWait)
			)
		)
	end
	if palette.tokens[hooks.partColorToken] == nil then
		problem(("hooks.partColorToken '%s' is not a palette token"):format(tostring(hooks.partColorToken)))
	end
	if not isMaterial(hooks.partMaterial) then
		problem(("hooks.partMaterial '%s' is not an Enum.Material"):format(tostring(hooks.partMaterial)))
	end
	-- Item 315: as many pack members as the widest scatter disc holds clear of each other (its area
	-- over each member's minStuds circle), and at least a pair.
	local spacing = playground.spawnSpacing
	local widest = playground.spawnScatterRadius + spacing.widenStuds * spacing.widenings
	local room = math.floor((widest / (spacing.minStuds / 2)) ^ 2)
	if not isWhole(hooks.maxPackSize) or hooks.maxPackSize < 2 or hooks.maxPackSize > room then
		problem(
			("hooks.maxPackSize (%s) must be a whole number from 2 to %d: the members the widest spawn scatter holds clear of each other"):format(
				tostring(hooks.maxPackSize),
				room
			)
		)
	end
end

-- The Studio frame cap (303): a Workspace attribute of its own, a range that holds the 30 frames a
-- second the Studio item asks for, and a render step after every step of the frame.
local function checkFrameCap(ctx: Context, dev: any, problem: (message: string) -> ())
	local cap = dev.frameCap
	if typeof(cap) ~= "table" then
		problem("frameCap is missing (the Studio frame-rate cap, DevFrameCap.client.luau)")
		return
	end
	local attributes = if typeof(dev.attributes) == "table" then dev.attributes else {}
	local taken = false
	for _, name in attributes do
		taken = taken or name == cap.attribute
	end
	if not isName(cap.attribute) or taken then
		problem("frameCap.attribute must be a plain attribute name no other dev attribute uses")
	end
	if
		not isWhole(cap.least)
		or not isWhole(cap.most)
		or cap.least < 1
		or cap.least >= cap.most
		or cap.most > FRAME_CAP_MOST
		or cap.least > FRAME_CAP_ASKED
		or cap.most < FRAME_CAP_ASKED
	then
		problem(
			("frameCap.least and most must be whole frames a second, 1 <= least < most <= %d, with %d inside (Studio item 303)"):format(
				FRAME_CAP_MOST,
				FRAME_CAP_ASKED
			)
		)
	end
	local function priority(row: any): number?
		if typeof(row) ~= "table" or typeof(row.base) ~= "string" or not isWhole(row.offset) then
			return nil
		end
		-- Lune's Enum throws on a name it does not have.
		local ok, item = pcall(function(): any
			return (roblox.Enum.RenderPriority :: any)[row.base]
		end)
		return if ok and item ~= nil then item.Value + row.offset else nil
	end
	local at = priority(cap.priority)
	if at == nil then
		problem("frameCap.priority must be { base = an Enum.RenderPriority name, offset = a whole number }")
		return
	end
	local rows: { { label: string, row: any } } = {}
	for _, source in { "choreo", "camera", "fx" } do
		local data = ctx.load("src/shared/data/" .. source)
		if typeof(data.renderOrder) == "table" then
			for name, row in data.renderOrder do
				table.insert(rows, { label = ("%s renderOrder.%s"):format(source, tostring(name)), row = row })
			end
		end
	end
	local walk = if typeof(dev.capture) == "table" then dev.capture.walk else nil
	if typeof(walk) == "table" then
		table.insert(rows, { label = "capture.walk.renderOrder", row = walk.renderOrder })
	end
	for _, entry in rows do
		local other = priority(entry.row)
		if other ~= nil and at <= other then
			problem(
				("frameCap.priority (%d) must run after %s (%d): the cap holds a whole frame"):format(
					at,
					entry.label,
					other
				)
			)
		end
	end
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

	-- The ClipLab's light (dev place only): every light a position, a positive range and brightness
	-- and a palette color; the key and the fill on the camera's side of the rigs (the camera starts
	-- at clipLab.camera.startYaw, on the rigs' -Z side at yaw 0), the rim on the far side; the
	-- backdrop a part name and a palette color; the lab's ambient colors in [0, 1], its diffuse scale
	-- in [0, 1] and its exposure inside the engine's [-3, 3].
	local lab = dev.clipLab
	if typeof(lab) ~= "table" or typeof(lab.camera) ~= "table" or not isNumber(lab.camera.startYaw) then
		problem("clipLab.camera.startYaw must be a number")
	else
		local palette = ctx.load("src/shared/data/palette")
		local yaw = math.rad(lab.camera.startYaw)
		local towardCamera = { math.sin(yaw), -math.cos(yaw) }
		for name, side in { keyLight = 1, fillLight = 1, rimLight = -1 } do
			local light = lab[name]
			local position = if typeof(light) == "table" then light.position else nil
			if
				typeof(position) ~= "table"
				or #position ~= 3
				or not (isNumber(position[1]) and isNumber(position[2]) and isNumber(position[3]))
			then
				problem(("clipLab.%s.position must be three numbers"):format(name))
				continue
			end
			if
				not isNumber(light.range)
				or light.range <= 0
				or not isNumber(light.brightness)
				or light.brightness <= 0
			then
				problem(("clipLab.%s needs a positive range and brightness"):format(name))
			end
			if typeof(light.color) ~= "string" or palette.tokens[light.color] == nil then
				problem(("clipLab.%s.color '%s' is not a palette token"):format(name, tostring(light.color)))
			end
			local facing = position[1] * towardCamera[1] + position[3] * towardCamera[2]
			if facing * side <= 0 then
				problem(
					("clipLab.%s must stand %s the rigs as the camera sees them (the key and the fill light the faces it looks at, the rim the edge against the backdrop)"):format(
						name,
						if side > 0 then "in front of" else "behind"
					)
				)
			end
		end
		local backdrop = lab.backdrop
		if typeof(backdrop) ~= "table" or not isName(backdrop.part) then
			problem("clipLab.backdrop.part must name the place's backdrop part")
		elseif typeof(backdrop.color) ~= "string" or palette.tokens[backdrop.color] == nil then
			problem(("clipLab.backdrop.color '%s' is not a palette token"):format(tostring(backdrop.color)))
		end
		local lighting = lab.lighting
		if typeof(lighting) ~= "table" then
			problem("clipLab.lighting must be a table")
		else
			for _, key in { "ambient", "outdoorAmbient" } do
				local rgb = lighting[key]
				local ok = typeof(rgb) == "table" and #rgb == 3
				if ok then
					for _, channel in rgb do
						if not isNumber(channel) or channel < 0 or channel > 1 then
							ok = false
						end
					end
				end
				if not ok then
					problem(("clipLab.lighting.%s must be three numbers in [0, 1]"):format(key))
				end
			end
			local diffuse = lighting.environmentDiffuseScale
			if not isNumber(diffuse) or diffuse < 0 or diffuse > 1 then
				problem("clipLab.lighting.environmentDiffuseScale must be a number in [0, 1]")
			end
			local exposure = lighting.exposureCompensation
			if not isNumber(exposure) or exposure < -3 or exposure > 3 then
				problem("clipLab.lighting.exposureCompensation must be a number in [-3, 3]")
			end
		end
		-- The hotkeys bind above the default character scripts (LabKeys, D-413).
		local okPriority, priority = pcall(function()
			return (roblox.Enum.ContextActionPriority :: any)[lab.actionPriority]
		end)
		if not okPriority or priority == nil or typeof(lab.actionPriority) ~= "string" then
			problem(("clipLab.actionPriority '%s' is not a ContextActionPriority"):format(tostring(lab.actionPriority)))
		elseif priority.Value <= roblox.Enum.ContextActionPriority.Medium.Value then
			problem(
				("clipLab.actionPriority '%s' must be above Medium: the character scripts bind the arrows and Space at the default priority"):format(
					lab.actionPriority
				)
			)
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
				"askSettleSeconds",
				"correctWithinStuds",
				"correctBackStuds",
				"correctSpeed",
				"creepSeconds",
				"creepEndSpeed",
				"faceDegreesPerSecond",
				"blockedSeconds",
				"blockedStuds",
			}
		do
			if not isNumber(walk[key]) or walk[key] <= 0 then
				problem(("capture.walk.%s must be a positive number"):format(key))
			end
		end
		if not isNumber(walk.secondWalks) or walk.secondWalks < 0 or walk.secondWalks % 1 ~= 0 then
			problem("capture.walk.secondWalks must be a whole number of 0 or more")
		end
		if not isNumber(walk.faceSettleSeconds) or walk.faceSettleSeconds < 0 then
			problem("capture.walk.faceSettleSeconds must be a number of 0 or more")
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
			-- The turn on the spot (step 14): a half turn and the stand after it, inside the walk's time.
			local faceSeconds = 180 / walk.faceDegreesPerSecond + walk.faceSettleSeconds
			if faceSeconds >= walk.timeoutSeconds then
				problem(
					("capture.walk: a half turn on the spot at faceDegreesPerSecond (%g) and faceSettleSeconds (%g) take %.2f s, not under timeoutSeconds (%g)"):format(
						walk.faceDegreesPerSecond,
						walk.faceSettleSeconds,
						faceSeconds,
						walk.timeoutSeconds
					)
				)
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
			if walk.restSpeed > locomotion.idleSpeedThreshold then
				problem(
					("capture.walk.restSpeed (%g) must be at most choreo locomotion.idleSpeedThreshold (%g): at rest means the Locomotion stands the body, so the walk never asks while it still walks in place"):format(
						walk.restSpeed,
						locomotion.idleSpeedThreshold
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
			-- The corrections (CW): every rest of a staging waits askSettleSeconds, a walk asked for
			-- beside the spot starts at the rest check, and a correction walks, never sprints.
			if walk.askSettleSeconds * (walk.secondWalks + 2) >= walk.timeoutSeconds then
				problem(
					("capture.walk.askSettleSeconds (%g) x (secondWalks + 2) must be under timeoutSeconds (%g): the walk's rests and its ask fit the timeout"):format(
						walk.askSettleSeconds,
						walk.timeoutSeconds
					)
				)
			end
			if walk.correctWithinStuds < stage.standRadius or walk.correctWithinStuds > stage.approachStuds then
				problem(
					("capture.walk.correctWithinStuds (%g) must be from capture.stage.standRadius (%g) to approachStuds (%g): a body at rest in the ring is never sent round the route"):format(
						walk.correctWithinStuds,
						stage.standRadius,
						stage.approachStuds
					)
				)
			end
			if walk.correctBackStuds <= walk.waypointStuds or walk.correctBackStuds > stage.approachStuds then
				problem(
					("capture.walk.correctBackStuds (%g) must be over waypointStuds (%g) and at most capture.stage.approachStuds (%g): the correction walks back along the last leg"):format(
						walk.correctBackStuds,
						walk.waypointStuds,
						stage.approachStuds
					)
				)
			end
			if walk.correctSpeed > locomotion.runSpeed then
				problem(
					("capture.walk.correctSpeed (%g) must be at most choreo locomotion.runSpeed (%g): a correction walks on a stick pushed at most all the way, never at the sprint"):format(
						walk.correctSpeed,
						locomotion.runSpeed
					)
				)
			end
			if walk.creepEndSpeed >= locomotion.idleSpeedThreshold then
				problem(
					("capture.walk.creepEndSpeed (%g) must be under choreo locomotion.idleSpeedThreshold (%g): the correction lets go too slow for the two-step stop to carry"):format(
						walk.creepEndSpeed,
						locomotion.idleSpeedThreshold
					)
				)
			end
			-- The blocked rule (316(b)): it judges a walk well inside the timeout, never a body the
			-- walk still moves. The correction's creep (ahead / creepSeconds studs a second, let go
			-- at creepEndSpeed) is the slowest push: its last blockedStuds take
			-- creepSeconds x ln((blockedStuds + end) / end), end = creepEndSpeed x creepSeconds.
			if walk.blockedSeconds >= walk.timeoutSeconds then
				problem(
					("capture.walk.blockedSeconds (%g) must be under timeoutSeconds (%g): a blocked walk lets go before the walk times out"):format(
						walk.blockedSeconds,
						walk.timeoutSeconds
					)
				)
			end
			if walk.blockedStuds >= walk.restStuds then
				problem(
					("capture.walk.blockedStuds (%g) must be under restStuds (%g): a body the walk moves less than that is held, not walking"):format(
						walk.blockedStuds,
						walk.restStuds
					)
				)
			end
			local creepEnd = walk.creepEndSpeed * walk.creepSeconds
			local creepLast = walk.creepSeconds * math.log((walk.blockedStuds + creepEnd) / creepEnd)
			if creepLast >= walk.blockedSeconds then
				problem(
					("capture.walk.blockedSeconds (%g) must be over the correction's creep over its last blockedStuds (%.3f s): the creep is never read as blocked"):format(
						walk.blockedSeconds,
						creepLast
					)
				)
			end
			if walk.creepEndSpeed * walk.creepSeconds >= walk.restStuds then
				problem(
					("capture.walk.creepEndSpeed x creepSeconds (%.3f) must be under restStuds (%g): the correction lets go on the spot"):format(
						walk.creepEndSpeed * walk.creepSeconds,
						walk.restStuds
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
			-- `to` (D-320): nothing of the reaction, its chain included, goes down past it, so what
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
				for _, key in { "at", "onClip", "every", "lead", "repeats", "lock", "chain", "from" } do
					if step[key] ~= nil then
						problem(("%s.%s: a chain step is timed by its delay alone"):format(stepLabel, key))
					end
				end
				-- A step's own `to` (EF): nothing of the step goes down past it, like its reaction's.
				if
					step.to ~= nil
					and (not isNumber(step.to) or step.to <= 0 or (seconds ~= nil and step.to > seconds))
				then
					problem(
						("%s.to (%s) must be above 0 and at most the take (%s s): nothing of the step goes down past it"):format(
							stepLabel,
							tostring(step.to),
							tostring(seconds)
						)
					)
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
					-- The attacks it may begin before it is held at its next free tick (FK2,
					-- EnemyService.limitAttacks): a whole number of one or more, on a let-go enemy only.
					if entry.attacks ~= nil then
						if entry.held ~= false then
							problem(entryLabel .. ".attacks is only for an enemy the shot lets go (held = false)")
						elseif not isWhole(entry.attacks) or entry.attacks < 1 then
							problem(
								("%s.attacks (%s) must be a whole number of 1 or more"):format(
									entryLabel,
									tostring(entry.attacks)
								)
							)
						end
					end
					-- A released Charger's first charge, against a player standing on the spot (D-300).
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
				-- A timed attack lands where its prompts say (D-298): an Art launches on its release, so
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

		-- No dev key is one Studio keeps for its own shortcuts: it would never reach the game.
		local devKeys: { { where: string, key: any } } = {}
		local clipLabKeys = if typeof(dev.clipLab) == "table" then dev.clipLab.hotkeys else nil
		local lists = {
			{ prefix = "capture.hotkeys", keys = hotkeys },
			{ prefix = "clipLab.hotkeys", keys = clipLabKeys },
		}
		for _, list in lists do
			if typeof(list.keys) == "table" then
				local names = {}
				for name in list.keys do
					table.insert(names, tostring(name))
				end
				table.sort(names)
				for _, name in names do
					table.insert(devKeys, { where = ("%s.%s"):format(list.prefix, name), key = list.keys[name] })
				end
			end
		end
		if typeof(walk) == "table" and typeof(walk.cancelKeys) == "table" then
			for index, key in walk.cancelKeys do
				table.insert(devKeys, { where = ("capture.walk.cancelKeys[%d]"):format(index), key = key })
			end
		end
		for _, entry in devKeys do
			if table.find(STUDIO_SHORTCUT_KEYS, entry.key) ~= nil then
				problem(
					("%s (%s) is a key Studio keeps for its own shortcuts (Respect Studio shortcuts when game has focus): it never reaches the game"):format(
						entry.where,
						tostring(entry.key)
					)
				)
			end
		end
		if typeof(capture.perform) ~= "table" or capture.perform.defaultOn ~= false then
			problem("capture.perform.defaultOn must be false: auto-perform starts off")
		end
		-- The guard's lead read off the staging replies (EF) is capped at a positive time.
		if
			typeof(capture.perform) == "table"
			and (not isNumber(capture.perform.wayUpMax) or capture.perform.wayUpMax <= 0)
		then
			problem("capture.perform.wayUpMax must be a positive number of seconds: the way up a guard leads by")
		end

		-- The staging's own numbers.
		if typeof(stage) == "table" then
			if typeof(stage.remoteName) ~= "string" or not isName(stage.remoteName) then
				problem("capture.stage.remoteName must be a plain instance name")
			end
			for _, key in
				{
					"requestsPerSecond",
					"awayStuds",
					"holdWaitSeconds",
					"settleNearStuds",
					"settleStuds",
					"settleSeconds",
					"settleTimeoutSeconds",
				}
			do
				if not isNumber(stage[key]) or stage[key] <= 0 then
					problem(("capture.stage.%s must be a positive number"):format(key))
				end
			end
			-- The settled read (D-447): its still window fits its timeout, it covers the whole ring,
			-- and the hold wait and the settle together stay under the client's wait.
			if
				isNumber(stage.settleSeconds)
				and isNumber(stage.settleTimeoutSeconds)
				and stage.settleSeconds >= stage.settleTimeoutSeconds
			then
				problem("capture.stage.settleSeconds must be under settleTimeoutSeconds: a still root is seen")
			end
			if
				isNumber(stage.settleNearStuds)
				and isNumber(stage.standRadius)
				and stage.settleNearStuds < stage.standRadius
			then
				problem(
					"capture.stage.settleNearStuds must be at least standRadius: a root in the ring is read settled"
				)
			end
			if
				isNumber(stage.holdWaitSeconds)
				and isNumber(stage.settleTimeoutSeconds)
				and isNumber(capture.stageTimeoutSeconds)
				and stage.holdWaitSeconds + stage.settleTimeoutSeconds >= capture.stageTimeoutSeconds
			then
				problem(
					"capture.stage.holdWaitSeconds + settleTimeoutSeconds must be under capture.stageTimeoutSeconds: the client waits out both"
				)
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
				-- The area's ring stands routeMarginStuds clear of the ledge and its ramp: a body in it
				-- never stands where they go, and a body where they go is walked there to stand clear
				-- before they are built (DevStage).
				if isNumber(stage.standRadius) and isNumber(stage.routeMarginStuds) then
					local ax, _, az = logic.standSpot(false, area, ledge)
					local clearance = stage.standRadius + stage.routeMarginStuds
					for _, box in logic.partBoxes(ledge) do
						local dx = math.max(box.min[1] - ax, 0, ax - box.max[1])
						local dz = math.max(box.min[3] - az, 0, az - box.max[3])
						if math.sqrt(dx * dx + dz * dz) < clearance then
							problem(
								("capture.stage.area's ring must stand routeMarginStuds (%g) clear of %s: a body where the ledge and its ramp go walks there to stand clear"):format(
									stage.routeMarginStuds,
									tostring(box.name)
								)
							)
						end
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

	-- The render-frame tick (D-336): a small square whose two colors swap every rendered frame.
	local tick = if typeof(capture) == "table" then capture.frameTick else nil
	if typeof(tick) ~= "table" then
		problem("capture.frameTick must be a table")
	else
		if not isWhole(tick.size) or tick.size < 1 or tick.size > MAX_TICK_PIXELS then
			problem(("capture.frameTick.size must be a whole number of pixels from 1 to %d"):format(MAX_TICK_PIXELS))
		end
		if not isWhole(tick.margin) or tick.margin < 0 then
			problem("capture.frameTick.margin must be a whole number of pixels, 0 or more")
		end
		local step = tick.maxLuminanceStep
		if not isNumber(step) or step <= 0 or step > MAX_TICK_LUMINANCE_STEP then
			problem(
				("capture.frameTick.maxLuminanceStep must be above 0 and at most %g"):format(MAX_TICK_LUMINANCE_STEP)
			)
		end
		local palette = ctx.load("src/shared/data/palette")
		local tokens = tick.tokens
		if
			typeof(tokens) ~= "table"
			or #tokens ~= 2
			or tokens[1] == tokens[2]
			or palette.tokens[tokens[1]] == nil
			or palette.tokens[tokens[2]] == nil
		then
			problem("capture.frameTick.tokens must be two different palette tokens")
		elseif isNumber(step) then
			-- Relative luminance (sRGB): the swap is a change of hue, never a flash.
			local function luminance(token: string): number
				local rgb = palette.rgb(token)
				local total = 0
				for index, weight in { 0.2126, 0.7152, 0.0722 } do
					local channel = rgb[index]
					local linear = if channel <= 0.04045 then channel / 12.92 else ((channel + 0.055) / 1.055) ^ 2.4
					total += weight * linear
				end
				return total
			end
			local gap = math.abs(luminance(tokens[1]) - luminance(tokens[2]))
			if gap > step then
				problem(
					("capture.frameTick.tokens differ in brightness by %.3f, over maxLuminanceStep %g: the square would flash"):format(
						gap,
						step
					)
				)
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

	checkHooks(ctx, dev, problem)
	checkFrameCap(ctx, dev, problem)
	return problems
end
