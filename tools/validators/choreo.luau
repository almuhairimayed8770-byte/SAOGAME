--!strict
--[[
	Validates data/choreo.luau's render-stall jump (stall.jumpSeconds, D-132). A step longer than
	jumpSeconds is a jump: the clip clocks take the gap, the root takes none of it, and the events
	it crossed only close what they close.

	- jumpSeconds is a positive, finite number.
	- A rig the quality tier steps on Heartbeat (distantHz, farHz) steps every 1 / rate, and
	  Heartbeat keeps running while the display sleeps: only a Heartbeat hitch as long as a whole
	  step on top of one may count as a jump, so jumpSeconds is at least 2 / rate for every rate of
	  every tier. Low's 4 Hz far rate wants 0.5 s.
	- A gap the camera snaps through (camera.luau stall.settleSeconds) is a stall for the clips too,
	  so jumpSeconds is at most settleSeconds.

	And the sheath's moving cap: sheath.movingTipShare is in (0, 1], the share of drawTipSpeed and
	sheatheTipSpeed a Draw or Sheathe over a moving body is held to (tests/choreo/SheathTip.spec.luau
	sweeps the cycle at it), so the cap moving is never above the cap standing.

	And the guard raised sheathed (SheathState, D-420): every sheath.drawFirstClips name is one of
	sheath.drawCutClips and a clip under locomotion.clipPrefix; sheath.overPriority is above each of
	those clips' priority and priority.Sheath (the Draw lays over the guard) and below
	priority.Basic (the attacks still draw-cut over it); sheath.handOverTime falls after the Draw's
	WeaponDraw and before its end (the guard takes the arm with the sword in the hand); and
	sheath.handOverBlend is a positive number of seconds. sheath.skidBrakeSeconds (D-579) is above
	0 and at most the Skid clip's duration. sheath.stopBrakeClips (D-611) maps sheathed
	locomotion.clips names to steps over the walk above 0, and sheath.stopBrakeRate is above 0 and
	under locomotion.weightBlendRate times the smallest of them (a run let go at once brakes).

	And the cancel hand-over (D-408): handOver.seconds is above 0 and at most dev.luau
	review.audit.cancel.snapFrames 60 Hz frames (a cancel is a snap, section 10 beat 2),
	handOver.easing a util/Easing curve other than Linear and Hold, and every handOver.snapClips
	name (a clip that comes up as the snap with nothing to cut, the guard, D-527) a clip under
	locomotion.clipPrefix that is not an attack.

	And the gait hand-off (D-404): locomotion.handOff.seconds is above 0; every joint it lists is
	a PlayerR15 joint (rigs.luau) with a factor in (0, 3]; and for every attack clip under
	locomotion.clipPrefix the longest hand-off blend (its blendIn or seconds, the longer, times the
	largest factor) ends by its first strike key (the first strike snap key in its first damage
	window, ContactPredictor.strikeKey): the hit is drawn on that key's pose, the clip's own.

	And the dodge's hand-off (D-528): every locomotion.dodgeHandOff.clips name is a clip under
	locomotion.clipPrefix that is not an attack; every joint it lists is a PlayerR15 joint whose
	seconds are above 0 and at most combat.luau dodgeDuration; and dodgeHandOff.resumePhase (the
	point of the stride a dodge that played to its end hands the legs back at, D-609) is a gait
	phase in [0, 1); every dodgeHandOff.takesFrom name (D-613) is a locomotion.clips one-shot
	that is not an attack or a dodge. The Skid's drop (D-612): locomotion.stopSpeedDrop is above 0 and
	stopDropSeconds above 0 and at most 0.1 s.

	And an enemy rig's gait paced by its root's own travel (D-575): enemy.gait.travelSeconds is a
	positive number of seconds, at most 1 / locomotion.weightBlendRate; each enemy.gait.startPhase
	(D-599) names a rig with a walk clip and is a phase from 0 up to 1. Each enemy.gait.turnPlant
	(D-619) names a rig with a walk clip; its feet are distinct parts of that rig, each hung from
	its own joint; its share is above 0 and at most 1; its maxRollDegrees above 0 and at most 20 (the
	roll's lift is drawn for a small roll); its maxShiftStuds above 0 and at most the narrowest
	foot's half depth (the leg slides along the body inside its own hip). Each enemy.gait.stopPlant
	(D-623) names a rig with a walk clip; its groups are two or more non-empty lists of distinct
	parts of that rig, each hung from its own joint and named once (the body always stands on a
	group while another steps); its stepSeconds is at least 1 / locomotion.weightBlendRate (a step
	no quicker than the gait's own crossfade) and its groups' steps together take at most the walk
	clip's duration (a stop steps no slower than its walk); its liftStuds is above
	locomotion.stride.contact (the step clears the contact band: a foot that rose less would read as
	sliding) and at most half the shortest foot part's height (a step, not a hop); its settleStuds
	is 0 or more, and a glide over that far within stepSeconds (SineInOut, its fastest pi / 2 times
	the mean) slides a foot at most stride.contact a 60 Hz frame. enemy.gait.stopBrakeShare is above
	0 and below 1 (a root that moved its whole pace on a row walks on). Each enemy.gait.attackPlant
	(D-632) keeps the stop plant's rules but the walk's cycle; instead its groups' steps, after the
	deepest network catch-up (catchUpMaxJump), are done by the first HitWindowOpen of each attack
	clip in its walk's folder (the clip has the legs for its strike). enemy.gait.attackBrakeShare is
	0 to 1 (standing to carrying on) and enemy.gait.attackBrakeSeconds a positive number of seconds.
	enemy.gait.attackWaitSeconds (D-652) is a positive number of seconds, at most (1 - 1 /
	enemy.beat.maxRate) of the first HitWindowOpen of each of those attack clips: a clip that waited
	that long for its walking body to brake can still even the beat by its mark.
	enemy.gait.evenRoot (D-664): drawBody is a boolean; rateSeconds a positive number of seconds,
	at most two of the gait's crossfades (2 / locomotion.weightBlendRate: the drawn root's pace is
	never a mean over longer than the gait takes to answer a change of pace twice); followSeconds positive and lagSeconds 0 or more, each at most rateSeconds;
	maxLagStuds positive and at most enemy.rush.teleportStuds (further off is a placement);
	maxLagDegrees above 0 and at most 90; settleStuds 0 up to locomotion.stride.contact (the snap
	onto the root is inside the contact band); settleDegrees 0 or more, below maxLagDegrees;
	sinkStuds (D-682) 0 up to locomotion.stride.contact (a body held that far over its root still
	stands its feet in the contact band). Each
	enemy.gait.standTurn (D-665) keeps the stop plant's rules but the walk's cycle, and its
	twistStuds is above its settleStuds (a turning stance steps only past its twist);
	enemy.gait.standTurnDegrees is a positive number of degrees, at least evenRoot.settleDegrees (a
	drawn root snapping onto its root reads as no turn).

	And the breath's give under a strike (D-685): breathYield.joints names distinct joints of
	every rig with a breathing clip (rigs.<rig>.breathing), among them every joint that clip keys on
	the chain from the rig's root part to its weapon (rigs.luau, the weaponModels.luau motorName
	motor up through each joint's Part0): a breath left on one moves the blade under every strike.
	breathYield.outEasing and inEasing are util/Easing curves other than Linear and Hold. outSeconds is
	a positive number of seconds, at most every attack's Anticipation beat under
	locomotion.clipPrefix (the breath leaves inside the wind-up).
]]

local TIERS = { "High", "Medium", "Low" }
-- The longest window the even root (D-664) reads its root's pace over, in the gait's crossfades.
local EVEN_RATE_MOST_CROSSFADES = 2
-- The longest a gait hand-off may stretch a joint's blend, in times its base.
local MAX_HAND_OFF_FACTOR = 3
local RATES = { "distantHz", "farHz" }
-- The turn plant's turn clips (locomotion.clips keys), its most twist, the turn it must bring
-- round (a target straight behind) and the samples its curve's slope is read at.
local TURN_CLIPS = { "TurnLeft", "TurnRight", "TurnLeftDrawn", "TurnRightDrawn", "TurnLeftDraw", "TurnRightDraw" }
local MAX_TURN_TWIST = 90
local HALF_TURN = 180
local SLOPE_SAMPLES = 1000

-- The longest locomotion.landOnMoveBlend (seconds): by then the stride sets its next foot down
-- under a Fall pose still showing.
local LAND_ON_MOVE_BLEND_MOST = 0.25

local function positive(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0 and value < math.huge
end

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "choreo: " .. message)
		end
	end

	local choreo = ctx.load("src/shared/data/choreo")
	local camera = ctx.load("src/shared/data/camera")

	-- Every player attack under locomotion.clipPrefix with the time of its first strike key (the
	-- first strike snap key in its first damage window, ContactPredictor.strikeKey): where its hit
	-- is drawn, on the clip's own pose.
	local strikeCache: { { id: string, key: number, blendIn: number? } }? = nil
	local function strikeKeys(): { { id: string, key: number, blendIn: number? } }
		if strikeCache ~= nil then
			return strikeCache
		end
		local found: { { id: string, key: number, blendIn: number? } } = {}
		local ClipSampler = ctx.load("src/shared/choreo/ClipSampler")
		local combat = ctx.load("src/shared/data/combat")
		local keyEpsilon = if typeof(combat.contact) == "table" then combat.contact.keyEpsilon or 0 else 0
		local prefix = if typeof(choreo.locomotion) == "table" then choreo.locomotion.clipPrefix else nil
		for _, file in ctx.listFiles("src/shared/clips/" .. tostring(prefix), "%.luau$") do
			local clip = ctx.load((file:gsub("%.luau$", "")))
			if typeof(clip) == "table" and clip.attack == true then
				local open, close = nil, nil
				for _, event in clip.events or {} do
					if event.kind == "HitWindowOpen" and open == nil then
						open = event.time
					elseif event.kind == "HitWindowClose" and close == nil then
						close = event.time
					end
				end
				if open ~= nil and close ~= nil then
					local key = open
					for index = 2, #clip.keys do
						local time = clip.keys[index].time
						if
							time > open + keyEpsilon
							and time <= close + keyEpsilon
							and ClipSampler.isStrikeSnap(clip, index)
						then
							key = time
							break
						end
					end
					table.insert(found, { id = tostring(clip.id or file), key = key, blendIn = clip.blendIn })
				end
			end
		end
		strikeCache = found
		return found
	end

	local sheath = choreo.sheath
	local share = if typeof(sheath) == "table" then sheath.movingTipShare else nil
	check(
		positive(share) and share <= 1,
		("sheath.movingTipShare (%s) must be in (0, 1]: the share of the tip cap a Draw or Sheathe over a moving body keeps"):format(
			tostring(share)
		)
	)

	if typeof(sheath) == "table" then
		local cuts: { [string]: boolean } = {}
		if typeof(sheath.drawCutClips) == "table" then
			for _, name in sheath.drawCutClips do
				cuts[name] = true
			end
		end
		local prefix = if typeof(choreo.locomotion) == "table" then choreo.locomotion.clipPrefix else nil
		local priority = if typeof(choreo.priority) == "table" then choreo.priority else {}
		local over = sheath.overPriority
		local overOk = positive(over)
		check(
			overOk and over > (priority.Sheath or math.huge) and over < (priority.Basic or -math.huge),
			("sheath.overPriority (%s) must be above priority.Sheath (%s) and below priority.Basic (%s): the Draw plays over a guard, the attacks over the Draw"):format(
				tostring(over),
				tostring(priority.Sheath),
				tostring(priority.Basic)
			)
		)
		if typeof(sheath.drawFirstClips) ~= "table" then
			check(false, "sheath.drawFirstClips must list the guard clips the Draw plays over")
		else
			for _, name in sheath.drawFirstClips do
				check(
					cuts[name] == true,
					("sheath.drawFirstClips '%s' must be one of sheath.drawCutClips"):format(tostring(name))
				)
				local ok, clip = pcall(ctx.load, "src/shared/clips/" .. tostring(prefix) .. tostring(name))
				if not ok or typeof(clip) ~= "table" then
					check(
						false,
						("sheath.drawFirstClips '%s' is not a clip under %s"):format(tostring(name), tostring(prefix))
					)
				else
					check(
						overOk and typeof(clip.priority) == "number" and over > clip.priority,
						("sheath.overPriority (%s) must be above %s's priority (%s): the Draw lays over it"):format(
							tostring(over),
							tostring(name),
							tostring(clip.priority)
						)
					)
				end
			end
		end
		local drawName = if typeof(sheath.clips) == "table" then sheath.clips.draw else nil
		local okDraw, draw = pcall(ctx.load, "src/shared/clips/" .. tostring(prefix) .. tostring(drawName))
		local grab: number? = nil
		if okDraw and typeof(draw) == "table" then
			for _, event in draw.events or {} do
				if event.kind == "WeaponDraw" then
					grab = event.time
				end
			end
		end
		local handOver = sheath.handOverTime
		check(
			grab ~= nil and positive(handOver) and handOver > (grab :: number) and handOver < draw.duration,
			("sheath.handOverTime (%s) must be after the Draw's WeaponDraw (%s s) and before its end (%s s): the guard takes the arm with the sword in the hand"):format(
				tostring(handOver),
				tostring(grab),
				tostring(if okDraw and typeof(draw) == "table" then draw.duration else nil)
			)
		)
		check(
			positive(sheath.handOverBlend),
			("sheath.handOverBlend (%s) must be a positive number of seconds"):format(tostring(sheath.handOverBlend))
		)
		-- D-579: the Skid's brake, a part of the Skid's own clock.
		local skidName = if typeof(choreo.locomotion) == "table" and typeof(choreo.locomotion.clips) == "table"
			then choreo.locomotion.clips.Skid
			else nil
		local okSkid, skid = pcall(ctx.load, "src/shared/clips/" .. tostring(prefix) .. tostring(skidName))
		local brake = sheath.skidBrakeSeconds
		check(
			okSkid and typeof(skid) == "table" and positive(brake) and brake <= skid.duration,
			("sheath.skidBrakeSeconds (%s) must be above 0 and at most the Skid clip's duration (%s s): a sheath clip stands through the Skid's brake"):format(
				tostring(brake),
				tostring(if okSkid and typeof(skid) == "table" then skid.duration else nil)
			)
		)
		-- D-611: the stop brake reads sheathed gait clips by their step over the walk, and its
		-- rate is one a run let go at once (weightBlendRate times the smallest step) passes.
		local brakeClips = sheath.stopBrakeClips
		local gaitClips = if typeof(choreo.locomotion) == "table" then choreo.locomotion.clips else nil
		local smallest = math.huge
		if typeof(brakeClips) ~= "table" or next(brakeClips) == nil then
			check(false, "sheath.stopBrakeClips must map at least one gait clip to its step over the walk")
		else
			for name, steps in brakeClips do
				check(
					typeof(name) == "string"
						and typeof(gaitClips) == "table"
						and gaitClips[name] ~= nil
						and name:sub(-5) ~= "Drawn",
					("sheath.stopBrakeClips '%s' must be a sheathed clip of locomotion.clips (its drawn twin is read with it)"):format(
						tostring(name)
					)
				)
				check(
					positive(steps),
					("sheath.stopBrakeClips.%s (%s) must be a step over the walk above 0"):format(
						tostring(name),
						tostring(steps)
					)
				)
				if positive(steps) then
					smallest = math.min(smallest, steps)
				end
			end
		end
		local blendRate = if typeof(choreo.locomotion) == "table" then choreo.locomotion.weightBlendRate else nil
		local stopRate = sheath.stopBrakeRate
		check(
			positive(stopRate) and positive(blendRate) and stopRate < blendRate * smallest,
			("sheath.stopBrakeRate (%s) must be above 0 and under locomotion.weightBlendRate times the smallest stopBrakeClips step (%s): a run let go at once brakes"):format(
				tostring(stopRate),
				tostring(if positive(blendRate) then blendRate * smallest else nil)
			)
		)
	end

	-- The cancel hand-over (D-408): a snap of at most review.audit.cancel.snapFrames frames, eased
	-- by a util/Easing curve that is not Linear (no linear tween on a limb) nor Hold.
	local dev = ctx.load("src/shared/data/dev")
	local audit = if typeof(dev.review) == "table" then dev.review.audit else nil
	local snapFrames = if typeof(audit) == "table" and typeof(audit.cancel) == "table"
		then audit.cancel.snapFrames
		else nil
	local handOver = choreo.handOver
	if typeof(handOver) ~= "table" then
		check(false, "handOver is missing (the cancel's snap: seconds and easing)")
	else
		check(
			positive(handOver.seconds) and positive(snapFrames) and handOver.seconds <= snapFrames / 60 + 1e-9,
			("handOver.seconds (%s) must be above 0 and at most review.audit.cancel.snapFrames / 60 (%s): a cancel is a snap"):format(
				tostring(handOver.seconds),
				tostring(if positive(snapFrames) then snapFrames / 60 else snapFrames)
			)
		)
		local Easing = ctx.load("src/shared/util/Easing")
		local curve = handOver.easing
		check(
			typeof(curve) == "string" and curve ~= "Linear" and curve ~= "Hold" and (pcall(Easing.get, curve)),
			("handOver.easing '%s' must be a util/Easing curve other than Linear and Hold"):format(tostring(curve))
		)
		-- The clips that always come up as the snap (D-527): each a clip under
		-- locomotion.clipPrefix and not an attack (an attack's hit is drawn on its own pose, and
		-- its hand-off from the gait is locomotion.handOff's).
		local snapPrefix = if typeof(choreo.locomotion) == "table" then choreo.locomotion.clipPrefix else nil
		if typeof(handOver.snapClips) ~= "table" then
			check(false, "handOver.snapClips must list the clips that come up as the snap with nothing to cut")
		else
			for _, name in handOver.snapClips do
				local ok, clip = pcall(ctx.load, "src/shared/clips/" .. tostring(snapPrefix) .. tostring(name))
				if not ok or typeof(clip) ~= "table" then
					check(
						false,
						("handOver.snapClips '%s' is not a clip under %s"):format(tostring(name), tostring(snapPrefix))
					)
				else
					check(
						clip.attack ~= true,
						("handOver.snapClips '%s' is an attack: its hand-off is locomotion.handOff's"):format(
							tostring(name)
						)
					)
				end
			end
		end
	end

	-- The gait hand-off (D-404): every listed joint a PlayerR15 joint with a factor in (0, 3], and
	-- every attack's longest hand-off blend done by its first strike key, the pose its hit is drawn
	-- at (ContactPredictor.strikeKey: the first strike snap key in the first damage window).
	local handOff = if typeof(choreo.locomotion) == "table" then choreo.locomotion.handOff else nil
	if typeof(handOff) ~= "table" or typeof(handOff.joints) ~= "table" then
		check(false, "locomotion.handOff is missing (seconds and the joints' factors)")
	else
		check(
			positive(handOff.seconds),
			("locomotion.handOff.seconds (%s) must be a positive number of seconds"):format(tostring(handOff.seconds))
		)
		local Rigs = ctx.load("src/shared/data/rigs")
		local jointNames: { [string]: boolean } = {}
		for _, joint in Rigs.PlayerR15.joints do
			jointNames[joint.name] = true
		end
		local longest = 0
		for name, factor in handOff.joints do
			check(
				jointNames[name] == true,
				("locomotion.handOff.joints names %s, not a PlayerR15 joint"):format(tostring(name))
			)
			check(
				positive(factor) and factor <= MAX_HAND_OFF_FACTOR,
				("locomotion.handOff.joints.%s (%s) must be in (0, %d]"):format(
					tostring(name),
					tostring(factor),
					MAX_HAND_OFF_FACTOR
				)
			)
			if positive(factor) then
				longest = math.max(longest, factor)
			end
		end
		if positive(handOff.seconds) then
			for _, attack in strikeKeys() do
				local blend = math.max(attack.blendIn or choreo.blendIn, handOff.seconds) * longest
				check(
					blend <= attack.key + 1e-9,
					("locomotion.handOff leaves %s blending %.3f s, past its first strike key at %.3f s: the hit is drawn on the clip's own pose"):format(
						attack.id,
						blend,
						attack.key
					)
				)
			end
		end
	end

	-- The dodge's hand-off (D-528): each clip a dodge under locomotion.clipPrefix (not an attack),
	-- each joint a PlayerR15 joint, and each blend above 0 and done by the dodge's move end
	-- (combat.luau dodgeDuration): the body reads as the dodge while it moves.
	local dodgeHandOff = if typeof(choreo.locomotion) == "table" then choreo.locomotion.dodgeHandOff else nil
	if
		typeof(dodgeHandOff) ~= "table"
		or typeof(dodgeHandOff.clips) ~= "table"
		or typeof(dodgeHandOff.joints) ~= "table"
	then
		check(false, "locomotion.dodgeHandOff is missing (the dodge clips and the joints' seconds)")
	else
		local prefix = choreo.locomotion.clipPrefix
		for _, name in dodgeHandOff.clips do
			local ok, clip = pcall(ctx.load, "src/shared/clips/" .. tostring(prefix) .. tostring(name))
			if not ok or typeof(clip) ~= "table" then
				check(
					false,
					("locomotion.dodgeHandOff.clips '%s' is not a clip under %s"):format(
						tostring(name),
						tostring(prefix)
					)
				)
			else
				check(
					clip.attack ~= true,
					("locomotion.dodgeHandOff.clips '%s' is an attack: its hand-off is locomotion.handOff's"):format(
						tostring(name)
					)
				)
			end
		end
		local Rigs = ctx.load("src/shared/data/rigs")
		local jointNames: { [string]: boolean } = {}
		for _, joint in Rigs.PlayerR15.joints do
			jointNames[joint.name] = true
		end
		local dodgeSeconds = ctx.load("src/shared/data/combat").dodgeDuration
		for name, seconds in dodgeHandOff.joints do
			check(
				jointNames[name] == true,
				("locomotion.dodgeHandOff.joints names %s, not a PlayerR15 joint"):format(tostring(name))
			)
			check(
				positive(seconds) and positive(dodgeSeconds) and seconds <= dodgeSeconds + 1e-9,
				("locomotion.dodgeHandOff.joints.%s (%s) must be above 0 and at most combat.luau dodgeDuration (%s): the body reads as the dodge while it moves"):format(
					tostring(name),
					tostring(seconds),
					tostring(dodgeSeconds)
				)
			)
		end
		-- D-613: the one-shots a dodge takes the body from as from a stance: locomotion.clips
		-- names whose clips are not attacks or dodges (an action keeps the cancel's snap).
		local takesFrom = dodgeHandOff.takesFrom
		local gaitClips = choreo.locomotion.clips
		if typeof(takesFrom) ~= "table" then
			check(false, "locomotion.dodgeHandOff.takesFrom must list the one-shots a dodge takes the body from")
		else
			local dodgeNames: { [string]: boolean } = {}
			for _, name in dodgeHandOff.clips do
				dodgeNames[name] = true
			end
			for _, name in takesFrom do
				local okName = typeof(name) == "string"
					and typeof(gaitClips) == "table"
					and gaitClips[name] ~= nil
					and not dodgeNames[name]
				local ok, clip = pcall(ctx.load, "src/shared/clips/" .. tostring(prefix) .. tostring(name))
				check(
					okName and ok and typeof(clip) == "table" and clip.attack ~= true,
					("locomotion.dodgeHandOff.takesFrom '%s' must be a locomotion.clips one-shot under %s that is not an attack or a dodge"):format(
						tostring(name),
						tostring(prefix)
					)
				)
			end
		end
		-- D-609: the point of the stride the gait picks up at after a dodge, a phase of the cycle.
		local resume = dodgeHandOff.resumePhase
		check(
			typeof(resume) == "number" and resume == resume and resume >= 0 and resume < 1,
			("locomotion.dodgeHandOff.resumePhase (%s) must be a gait phase in [0, 1): the point of the stride a dodge hands the legs back at"):format(
				tostring(resume)
			)
		)
	end

	-- D-612: the Skid's drop, read as a fall rate: a positive speed over a window of at most
	-- 0.1 s (a stop, not an eased slow-down).
	do
		local locomotion = if typeof(choreo.locomotion) == "table" then choreo.locomotion else {}
		check(
			positive(locomotion.stopSpeedDrop),
			("locomotion.stopSpeedDrop (%s) must be a speed above 0"):format(tostring(locomotion.stopSpeedDrop))
		)
		local window = locomotion.stopDropSeconds
		check(
			positive(window) and window <= 0.1,
			("locomotion.stopDropSeconds (%s) must be above 0 and at most 0.1 s: the Skid's drop is a stop's"):format(
				tostring(window)
			)
		)
	end

	-- The turn plant (D-416): the hips come round between a turn clip's first two Footsteps, the
	-- pivot foot's and then the other's, at most stepDegrees a 60 Hz frame (a pop is the most),
	-- and are round leadSeconds before the second (D-641, 0 or more); the window left is long
	-- enough for half a turn at that cap on the curve's steepest stretch; a
	-- lag the body leaves standing lets go by every attack's first strike key; the Waist's lead
	-- stays a twist; and a second turn never cuts a turn clip's own steps.
	local loco = if typeof(choreo.locomotion) == "table" then choreo.locomotion else {}
	local plant = loco.turnPlant
	if typeof(plant) ~= "table" then
		check(false, "locomotion.turnPlant is missing (stepDegrees, plantSeconds, twistDegrees, easing, leadSeconds)")
	else
		local pop = if typeof(audit) == "table" then audit.popDegrees else nil
		local step = plant.stepDegrees
		check(
			positive(step) and positive(pop) and step <= pop,
			("locomotion.turnPlant.stepDegrees (%s) must be above 0 and at most review.audit.popDegrees (%s): the hips never pop round"):format(
				tostring(step),
				tostring(pop)
			)
		)
		local twist = plant.twistDegrees
		check(
			typeof(twist) == "number" and twist >= 0 and twist <= MAX_TURN_TWIST,
			("locomotion.turnPlant.twistDegrees (%s) must be in [0, %d]: the upper body leads the hips by a twist"):format(
				tostring(twist),
				MAX_TURN_TWIST
			)
		)
		local Easing = ctx.load("src/shared/util/Easing")
		local curve = plant.easing
		local eased = typeof(curve) == "string" and curve ~= "Linear" and curve ~= "Hold" and (pcall(Easing.get, curve))
		check(
			eased,
			("locomotion.turnPlant.easing '%s' must be a util/Easing curve other than Linear and Hold"):format(
				tostring(curve)
			)
		)
		local hold = plant.plantSeconds
		if not positive(hold) then
			check(
				false,
				("locomotion.turnPlant.plantSeconds (%s) must be a positive number of seconds"):format(tostring(hold))
			)
		else
			for _, attack in strikeKeys() do
				check(
					hold <= attack.key + 1e-9,
					("locomotion.turnPlant.plantSeconds (%.3f s) lets go past %s's first strike key at %.3f s: the hit is drawn on the clip's own pose"):format(
						hold,
						attack.id,
						attack.key
					)
				)
			end
		end
		-- The curve's steepest slope over its span, sampled.
		local slope = 0
		if eased then
			local last = Easing.evaluate(curve, 0)
			for index = 1, SLOPE_SAMPLES do
				local value = Easing.evaluate(curve, index / SLOPE_SAMPLES)
				slope = math.max(slope, math.abs(value - last) * SLOPE_SAMPLES)
				last = value
			end
		end
		-- D-641: the hips are round leadSeconds before the second Footstep: 0 or more seconds,
		-- and the window left (checked per clip below) still brings half a turn round.
		local lead = plant.leadSeconds
		local leadOk = typeof(lead) == "number" and lead == lead and lead >= 0 and lead < math.huge
		check(
			leadOk,
			("locomotion.turnPlant.leadSeconds (%s) must be 0 or more seconds: the hips are round before the second Footstep"):format(
				tostring(lead)
			)
		)
		local clips = if typeof(loco.clips) == "table" then loco.clips else {}
		local prefix = tostring(loco.clipPrefix)
		for _, name in TURN_CLIPS do
			local pivot = if name:sub(1, 8) == "TurnLeft" then "Left" else "Right"
			local other = if pivot == "Left" then "Right" else "Left"
			local clipName = clips[name]
			local ok, clip = pcall(ctx.load, "src/shared/clips/" .. prefix .. tostring(clipName))
			if typeof(clipName) ~= "string" or not ok or typeof(clip) ~= "table" then
				check(
					false,
					("locomotion.clips.%s (%s) must name a clip under %s"):format(name, tostring(clipName), prefix)
				)
				continue
			end
			local steps = {}
			for _, event in clip.events or {} do
				if event.kind == "Footstep" then
					table.insert(steps, event)
				end
			end
			table.sort(steps, function(a: any, b: any): boolean
				return a.time < b.time
			end)
			local first, second = steps[1], steps[2]
			local footOf = function(event: any): any
				return if typeof(event.data) == "table" then event.data.foot else nil
			end
			if first == nil or second == nil or footOf(first) ~= pivot or footOf(second) ~= other then
				check(
					false,
					("%s must step the pivot foot (%s) and then the other (%s) first: its two Footsteps hold the turn plant's window"):format(
						name,
						pivot,
						other
					)
				)
				continue
			end
			local span = second.time - first.time - (if leadOk then lead else 0)
			local need = if positive(step) and eased then HALF_TURN * slope / (step * 60) else 0
			check(
				span >= need - 1e-9,
				("%s's window from its first Footstep to leadSeconds before its second (%.3f s) is under %.3f s: half a turn on %s at stepDegrees would not come round"):format(
					name,
					span,
					need,
					tostring(curve)
				)
			)
			check(
				typeof(clip.duration) == "number"
					and typeof(loco.turnClipDuration) == "number"
					and loco.turnClipDuration >= clip.duration - 1e-9,
				("locomotion.turnClipDuration (%s) must be at least %s's duration (%s): a second turn never cuts a turn's own steps"):format(
					tostring(loco.turnClipDuration),
					name,
					tostring(clip.duration)
				)
			)
		end
	end

	-- A landing on the move (D-521): the Fall lets go of the legs over landOnMoveBlend, no faster
	-- than a one-shot cuts in and no slower than LAND_ON_MOVE_BLEND_MOST.
	local landBlend = loco.landOnMoveBlend
	check(
		positive(landBlend)
			and typeof(choreo.oneShotBlendIn) == "number"
			and landBlend >= choreo.oneShotBlendIn
			and landBlend <= LAND_ON_MOVE_BLEND_MOST,
		("locomotion.landOnMoveBlend (%s) must be in [oneShotBlendIn %s, %s] seconds"):format(
			tostring(landBlend),
			tostring(choreo.oneShotBlendIn),
			tostring(LAND_ON_MOVE_BLEND_MOST)
		)
	)

	local stall = choreo.stall
	if typeof(stall) ~= "table" then
		check(false, "stall is missing (jumpSeconds: the longest step that is not a render-stall jump)")
		return problems
	end
	local jump = stall.jumpSeconds
	if not positive(jump) then
		check(false, "stall.jumpSeconds must be a positive number of seconds")
		return problems
	end

	for _, tier in TIERS do
		local row = choreo.quality[tier]
		if typeof(row) == "table" then
			for _, rate in RATES do
				local hz = row[rate]
				if positive(hz) then
					check(
						jump >= 2 / hz,
						("stall.jumpSeconds %.2f is under 2 / quality.%s.%s (%.2f): a rig stepped on Heartbeat at that rate would jump on a hitch shorter than its own step"):format(
							jump,
							tier,
							rate,
							2 / hz
						)
					)
				end
			end
		end
	end

	-- An enemy rig's gait paced by its root's travel (D-575) answers a change of pace no later
	-- than its own crossfade: travelSeconds is positive and at most 1 / locomotion.weightBlendRate.
	local gait = if typeof(choreo.enemy) == "table" then choreo.enemy.gait else nil
	local travel = if typeof(gait) == "table" then gait.travelSeconds else nil
	check(positive(travel), "enemy.gait.travelSeconds must be a positive number of seconds")
	local blendRate = if typeof(choreo.locomotion) == "table" then choreo.locomotion.weightBlendRate else nil
	if positive(travel) and positive(blendRate) then
		check(
			travel <= 1 / blendRate,
			("enemy.gait.travelSeconds %.3f is over 1 / locomotion.weightBlendRate (%.3f s): the gait would answer a change of pace later than its crossfade"):format(
				travel,
				1 / blendRate
			)
		)
	end

	-- An enemy rig's walk start (D-599): each start phase names a rig with a walk and is a point
	-- of its cycle, 0 up to (not at) 1.
	local starts = if typeof(gait) == "table" then gait.startPhase else nil
	check(typeof(starts) == "table", "enemy.gait.startPhase must be a table of rig ids to phases")
	if typeof(starts) == "table" then
		for rigId, phase in starts do
			local rigClips = if typeof(choreo.rigs) == "table" then choreo.rigs[rigId] else nil
			check(
				typeof(rigClips) == "table" and typeof(rigClips.walk) == "string",
				("enemy.gait.startPhase.%s names no rig with a walk clip (choreo rigs)"):format(tostring(rigId))
			)
			check(
				typeof(phase) == "number" and phase >= 0 and phase < 1,
				("enemy.gait.startPhase.%s must be a phase of the walk's cycle, 0 up to 1"):format(tostring(rigId))
			)
		end
	end

	-- An enemy rig's walking-turn plant (D-619): each names a rig with a walk; its feet are that
	-- rig's parts hung from their own joints; a share of the sweep up to all of it; a small roll and a
	-- slide inside the hip.
	local plants = if typeof(gait) == "table" then gait.turnPlant else nil
	check(typeof(plants) == "table", "enemy.gait.turnPlant must be a table of rig ids to plants")
	if typeof(plants) == "table" then
		local Rigs = ctx.load("src/shared/data/rigs")
		for rigId, plant in plants do
			local where = ("enemy.gait.turnPlant.%s"):format(tostring(rigId))
			local rigClips = if typeof(choreo.rigs) == "table" then choreo.rigs[rigId] else nil
			local rig = Rigs[rigId]
			check(
				typeof(rigClips) == "table" and typeof(rigClips.walk) == "string" and typeof(rig) == "table",
				("%s names no rig with a walk clip (choreo rigs)"):format(where)
			)
			if typeof(plant) ~= "table" then
				check(false, ("%s must be a table (feet, share, maxRollDegrees, maxShiftStuds)"):format(where))
				continue
			end
			local hung: { [string]: boolean } = {}
			if typeof(rig) == "table" and typeof(rig.joints) == "table" then
				for _, joint in rig.joints do
					hung[joint.part1] = true
				end
			end
			local narrowest = math.huge
			check(
				typeof(plant.feet) == "table" and #plant.feet > 0,
				("%s.feet must list the rig's foot parts"):format(where)
			)
			if typeof(plant.feet) == "table" then
				local seen: { [string]: boolean } = {}
				for _, foot in plant.feet do
					local part = if typeof(rig) == "table" and typeof(rig.parts) == "table"
						then rig.parts[foot]
						else nil
					check(
						typeof(foot) == "string" and part ~= nil and hung[foot] == true and not seen[foot],
						("%s.feet: %s must be a part of the rig hung from its own joint, named once"):format(
							where,
							tostring(foot)
						)
					)
					if typeof(foot) == "string" then
						seen[foot] = true
					end
					if part ~= nil and typeof(part.size) == "table" and typeof(part.size[3]) == "number" then
						narrowest = math.min(narrowest, part.size[3] / 2)
					end
				end
			end
			local share = plant.share
			check(
				typeof(share) == "number" and share > 0 and share <= 1,
				("%s.share %s must be above 0 and at most 1"):format(where, tostring(share))
			)
			local roll = plant.maxRollDegrees
			check(
				typeof(roll) == "number" and roll > 0 and roll <= 20,
				("%s.maxRollDegrees %s must be above 0 and at most 20"):format(where, tostring(roll))
			)
			local shift = plant.maxShiftStuds
			check(
				typeof(shift) == "number" and shift > 0 and shift <= narrowest,
				("%s.maxShiftStuds %s must be above 0 and at most the narrowest foot's half depth (%s)"):format(
					where,
					tostring(shift),
					tostring(narrowest)
				)
			)
		end
	end

	-- An enemy rig's stop plant (D-623) or attack plant (D-632): it names a rig with a walk; two
	-- or more groups of that rig's feet hung from their own joints, each foot named once; steps no
	-- quicker than the gait's crossfade; a lift that clears the contact band and is no hop; a glide
	-- no faster than stride.contact a 60 Hz frame. Returns the rig's walk clip id (nil when it names
	-- none), its groups' count and its stepSeconds when that is a positive number.
	local Rigs = ctx.load("src/shared/data/rigs")
	local locomotion = if typeof(choreo.locomotion) == "table" then choreo.locomotion else {}
	local stride = if typeof(locomotion.stride) == "table" then locomotion.stride else {}
	local contact = stride.contact
	local function checkPlant(where: string, rigId: any, plant: any): (string?, number, number?)
		local rigClips = if typeof(choreo.rigs) == "table" then choreo.rigs[rigId] else nil
		local rig = Rigs[rigId]
		local walkId = if typeof(rigClips) == "table" then rigClips.walk else nil
		check(
			typeof(walkId) == "string" and typeof(rig) == "table",
			("%s names no rig with a walk clip (choreo rigs)"):format(where)
		)
		if typeof(plant) ~= "table" then
			check(false, ("%s must be a table (groups, stepSeconds, liftStuds, settleStuds)"):format(where))
			return nil, 0, nil
		end
		local hung: { [string]: boolean } = {}
		if typeof(rig) == "table" and typeof(rig.joints) == "table" then
			for _, joint in rig.joints do
				hung[joint.part1] = true
			end
		end
		local shortest = math.huge
		local groups = plant.groups
		check(
			typeof(groups) == "table" and #groups >= 2,
			("%s.groups must list two or more groups of the rig's foot parts"):format(where)
		)
		local seen: { [string]: boolean } = {}
		if typeof(groups) == "table" then
			for index, group in groups do
				check(
					typeof(group) == "table" and #group > 0,
					("%s.groups[%s] must list one or more foot parts"):format(where, tostring(index))
				)
				if typeof(group) ~= "table" then
					continue
				end
				for _, foot in group do
					local part = if typeof(rig) == "table" and typeof(rig.parts) == "table"
						then rig.parts[foot]
						else nil
					check(
						typeof(foot) == "string" and part ~= nil and hung[foot] == true and not seen[foot],
						("%s.groups: %s must be a part of the rig hung from its own joint, named once"):format(
							where,
							tostring(foot)
						)
					)
					if typeof(foot) == "string" then
						seen[foot] = true
					end
					if part ~= nil and typeof(part.size) == "table" and typeof(part.size[2]) == "number" then
						shortest = math.min(shortest, part.size[2])
					end
				end
			end
		end
		local step = plant.stepSeconds
		local blendRate = locomotion.weightBlendRate
		check(
			positive(step) and positive(blendRate) and step >= 1 / blendRate - 1e-9,
			("%s.stepSeconds %s must be at least 1 / locomotion.weightBlendRate (%s s): a step no quicker than the gait's crossfade"):format(
				where,
				tostring(step),
				if positive(blendRate) then ("%.3f"):format(1 / blendRate) else "?"
			)
		)
		local lift = plant.liftStuds
		check(
			typeof(lift) == "number"
				and positive(contact)
				and lift > contact
				and shortest < math.huge
				and lift <= shortest / 2,
			("%s.liftStuds %s must be above locomotion.stride.contact (%s) and at most half the shortest foot's height (%s)"):format(
				where,
				tostring(lift),
				tostring(contact),
				if shortest < math.huge then tostring(shortest / 2) else "?"
			)
		)
		local settleStuds = plant.settleStuds
		check(
			typeof(settleStuds) == "number" and settleStuds >= 0,
			("%s.settleStuds %s must be 0 or more"):format(where, tostring(settleStuds))
		)
		if typeof(settleStuds) == "number" and settleStuds >= 0 and positive(step) and positive(contact) then
			local fastest = settleStuds * math.pi / (2 * step) / 60
			check(
				fastest <= contact + 1e-9,
				("%s.settleStuds %s glides a foot %.3f a 60 Hz frame over stepSeconds (max stride.contact %s)"):format(
					where,
					tostring(settleStuds),
					fastest,
					tostring(contact)
				)
			)
		end
		return if typeof(walkId) == "string" then walkId else nil,
			if typeof(groups) == "table" then #groups else 0,
			if positive(step) then step else nil
	end

	-- The stop plant's steps together take no longer than the walk's cycle (a stop steps no slower
	-- than its walk).
	local stops = if typeof(gait) == "table" then gait.stopPlant else nil
	check(typeof(stops) == "table", "enemy.gait.stopPlant must be a table of rig ids to stop plants")
	if typeof(stops) == "table" then
		for rigId, stop in stops do
			local where = ("enemy.gait.stopPlant.%s"):format(tostring(rigId))
			local walkId, count, step = checkPlant(where, rigId, stop)
			if step ~= nil and count > 0 and walkId ~= nil then
				local ok, walk = pcall(ctx.load, "src/shared/clips/" .. walkId)
				local cycle = if ok and typeof(walk) == "table" then walk.duration else nil
				check(
					positive(cycle) and count * step <= cycle + 1e-9,
					("%s: its %d steps of %s s must take at most the walk's cycle (%s s): a stop steps no slower than its walk"):format(
						where,
						count,
						tostring(step),
						tostring(cycle)
					)
				)
			end
		end
	end

	-- The attack plant's steps are done, after the deepest network catch-up (catchUpMaxJump), before
	-- the first HitWindowOpen of each attack clip in the rig's walk's folder: the clip has the legs
	-- for its strike.
	local attackPlants = if typeof(gait) == "table" then gait.attackPlant else nil
	check(typeof(attackPlants) == "table", "enemy.gait.attackPlant must be a table of rig ids to attack plants")
	-- An attack clip waits at most attackWaitSeconds for its walking body to brake (D-652): a
	-- positive number of seconds that the beat, run at enemy.beat.maxRate, can still even by each
	-- attack clip's first HitWindowOpen with no catch-up.
	local wait = if typeof(gait) == "table" then gait.attackWaitSeconds else nil
	check(
		positive(wait),
		("enemy.gait.attackWaitSeconds %s must be a positive number of seconds"):format(tostring(wait))
	)
	local beat = if typeof(choreo.enemy) == "table" then choreo.enemy.beat else nil
	local maxRate = if typeof(beat) == "table" then beat.maxRate else nil
	local evens = if typeof(maxRate) == "number" and maxRate > 1 then 1 - 1 / maxRate else nil
	if typeof(attackPlants) == "table" then
		local catchUp = choreo.catchUpMaxJump
		for rigId, attackPlant in attackPlants do
			local where = ("enemy.gait.attackPlant.%s"):format(tostring(rigId))
			local walkId, count, step = checkPlant(where, rigId, attackPlant)
			local folder = if walkId ~= nil then walkId:match("^(.+)/[^/]+$") else nil
			if step == nil or count <= 0 or folder == nil or not positive(catchUp) then
				continue
			end
			for _, file in ctx.listFiles("src/shared/clips/" .. folder, "%.luau$") do
				local ok, clip = pcall(ctx.load, (file:gsub("%.luau$", "")))
				if not ok or typeof(clip) ~= "table" or clip.attack ~= true then
					continue
				end
				local open: number? = nil
				for _, event in clip.events or {} do
					if event.kind == "HitWindowOpen" and (open == nil or event.time < open) then
						open = event.time
					end
				end
				if open ~= nil and positive(wait) and evens ~= nil then
					check(
						wait <= evens * open + 1e-9,
						("enemy.gait.attackWaitSeconds %s is more than %s's beat can even by its first HitWindowOpen (%s s at maxRate %s: at most %s s)"):format(
							tostring(wait),
							tostring(clip.id or file),
							tostring(open),
							tostring(maxRate),
							tostring(math.floor(evens * open * 1e4 + 0.5) / 1e4)
						)
					)
				end
				if open ~= nil then
					check(
						catchUp + count * step <= open + 1e-9,
						("%s: its %d steps of %s s after a %s s catch-up must be done by %s's first HitWindowOpen (%s s)"):format(
							where,
							count,
							tostring(step),
							tostring(catchUp),
							tostring(clip.id or file),
							tostring(open)
						)
					)
				end
			end
		end
	end
	local brake = if typeof(gait) == "table" then gait.stopBrakeShare else nil
	check(
		typeof(brake) == "number" and brake > 0 and brake < 1,
		("enemy.gait.stopBrakeShare %s must be above 0 and below 1"):format(tostring(brake))
	)
	-- The attack plant's first row carries the root on by a share from standing (0) to carrying on
	-- (1); a braking root's speed falls with a positive time constant.
	local attackBrake = if typeof(gait) == "table" then gait.attackBrakeShare else nil
	check(
		typeof(attackBrake) == "number" and attackBrake >= 0 and attackBrake <= 1,
		("enemy.gait.attackBrakeShare %s must be 0 to 1"):format(tostring(attackBrake))
	)
	local attackBrakeSeconds = if typeof(gait) == "table" then gait.attackBrakeSeconds else nil
	check(
		positive(attackBrakeSeconds),
		("enemy.gait.attackBrakeSeconds %s must be a positive number of seconds"):format(tostring(attackBrakeSeconds))
	)

	-- The root an enemy's body is drawn on (D-664): a window that answers a change of pace no
	-- later than the gait's crossfade, a pull and a lag inside it, a lag never as far as a
	-- placement, and a snap onto the root inside the contact band.
	local even = if typeof(gait) == "table" then gait.evenRoot else nil
	check(
		typeof(even) == "table",
		"enemy.gait.evenRoot must be a table (drawBody, rateSeconds, followSeconds, lagSeconds, maxLagStuds, maxLagDegrees, settleStuds, settleDegrees, sinkStuds)"
	)
	local settleDegrees: number? = nil
	if typeof(even) == "table" then
		check(
			typeof(even.drawBody) == "boolean",
			("enemy.gait.evenRoot.drawBody %s must be true or false"):format(tostring(even.drawBody))
		)
		local rate = even.rateSeconds
		local blendRate = locomotion.weightBlendRate
		check(
			positive(rate) and positive(blendRate) and rate <= EVEN_RATE_MOST_CROSSFADES / blendRate + 1e-9,
			("enemy.gait.evenRoot.rateSeconds %s must be a positive number of seconds, at most two of the gait's crossfades (%s s): the drawn root's pace is a mean over no longer"):format(
				tostring(rate),
				if positive(blendRate) then ("%.3f"):format(EVEN_RATE_MOST_CROSSFADES / blendRate) else "?"
			)
		)
		local follow = even.followSeconds
		check(
			positive(follow) and (not positive(rate) or follow <= rate + 1e-9),
			("enemy.gait.evenRoot.followSeconds %s must be a positive number of seconds, at most rateSeconds"):format(
				tostring(follow)
			)
		)
		local lag = even.lagSeconds
		check(
			typeof(lag) == "number" and lag >= 0 and (not positive(rate) or lag <= rate + 1e-9),
			("enemy.gait.evenRoot.lagSeconds %s must be 0 or more seconds, at most rateSeconds"):format(tostring(lag))
		)
		local rush = if typeof(choreo.enemy) == "table" then choreo.enemy.rush else nil
		local teleport = if typeof(rush) == "table" then rush.teleportStuds else nil
		local most = even.maxLagStuds
		check(
			positive(most) and positive(teleport) and most <= teleport,
			("enemy.gait.evenRoot.maxLagStuds %s must be a positive number of studs, at most enemy.rush.teleportStuds (%s): further off is a placement"):format(
				tostring(most),
				tostring(teleport)
			)
		)
		local mostDegrees = even.maxLagDegrees
		check(
			positive(mostDegrees) and mostDegrees <= 90,
			("enemy.gait.evenRoot.maxLagDegrees %s must be above 0 and at most 90"):format(tostring(mostDegrees))
		)
		local settleStuds = even.settleStuds
		check(
			typeof(settleStuds) == "number" and settleStuds >= 0 and positive(contact) and settleStuds <= contact,
			("enemy.gait.evenRoot.settleStuds %s must be 0 up to locomotion.stride.contact (%s): the snap onto the root is inside the contact band"):format(
				tostring(settleStuds),
				tostring(contact)
			)
		)
		local snap = even.settleDegrees
		local snapOk = typeof(snap) == "number" and snap >= 0 and positive(mostDegrees) and snap < mostDegrees
		check(
			snapOk,
			("enemy.gait.evenRoot.settleDegrees %s must be 0 or more, below maxLagDegrees"):format(tostring(snap))
		)
		settleDegrees = if snapOk then snap else nil
		-- The height held over a settling root (D-682): a body held that far over it still stands
		-- its feet in the contact band.
		local sink = even.sinkStuds
		check(
			typeof(sink) == "number" and sink >= 0 and positive(contact) and sink <= contact,
			("enemy.gait.evenRoot.sinkStuds %s must be 0 up to locomotion.stride.contact (%s): a body held that far over its root still stands its feet in the contact band"):format(
				tostring(sink),
				tostring(contact)
			)
		)
	end

	-- The stand turn (D-665) keeps the stop plant's rules but the walk's cycle; a turning stance
	-- steps only past its twist, and a drawn root snapping onto its root reads as no turn.
	local stands = if typeof(gait) == "table" then gait.standTurn else nil
	check(typeof(stands) == "table", "enemy.gait.standTurn must be a table of rig ids to stand turns")
	if typeof(stands) == "table" then
		for rigId, stand in stands do
			local where = ("enemy.gait.standTurn.%s"):format(tostring(rigId))
			checkPlant(where, rigId, stand)
			local twist = if typeof(stand) == "table" then stand.twistStuds else nil
			local standSettle = if typeof(stand) == "table" then stand.settleStuds else nil
			check(
				positive(twist) and typeof(standSettle) == "number" and twist > standSettle,
				("%s.twistStuds %s must be above its settleStuds (%s): a turning stance steps only past its twist"):format(
					where,
					tostring(twist),
					tostring(standSettle)
				)
			)
		end
	end
	local standDegrees = if typeof(gait) == "table" then gait.standTurnDegrees else nil
	check(
		positive(standDegrees) and (settleDegrees == nil or standDegrees >= settleDegrees - 1e-9),
		("enemy.gait.standTurnDegrees %s must be a positive number of degrees, at least evenRoot.settleDegrees (%s): a drawn root snapping onto its root reads as no turn"):format(
			tostring(standDegrees),
			tostring(settleDegrees)
		)
	)

	-- The breath's give under a strike (D-685): distinct joints of every breathing rig, among them
	-- every joint its breathing clip keys from the root to the weapon, eased by a curve.
	local breathYield = choreo.breathYield
	if typeof(breathYield) ~= "table" or typeof(breathYield.joints) ~= "table" then
		check(false, "breathYield is missing (the joints that give way under a strike and the easing)")
	else
		local listed: { [string]: boolean } = {}
		for _, name in breathYield.joints do
			check(
				typeof(name) == "string" and listed[name] == nil,
				("breathYield.joints names %s twice or not as a joint name"):format(tostring(name))
			)
			if typeof(name) == "string" then
				listed[name] = true
			end
		end
		local Easing = ctx.load("src/shared/util/Easing")
		for _, field in { "outEasing", "inEasing" } do
			local curve = breathYield[field]
			check(
				typeof(curve) == "string" and curve ~= "Linear" and curve ~= "Hold" and (pcall(Easing.get, curve)),
				("breathYield.%s '%s' must be a util/Easing curve other than Linear and Hold"):format(
					field,
					tostring(curve)
				)
			)
		end
		local out = breathYield.outSeconds
		check(positive(out), ("breathYield.outSeconds (%s) must be a positive number of seconds"):format(tostring(out)))
		local prefix = if typeof(choreo.locomotion) == "table" then choreo.locomotion.clipPrefix else nil
		if positive(out) and typeof(prefix) == "string" then
			for _, file in ctx.listFiles("src/shared/clips/" .. prefix, "%.luau$") do
				local clip = ctx.load((file:gsub("%.luau$", "")))
				local beats = if typeof(clip) == "table" and clip.attack == true then clip.beats else nil
				local anticipation = if typeof(beats) == "table" then beats.Anticipation else nil
				if typeof(anticipation) == "table" then
					local span = anticipation.finish - anticipation.start
					check(
						out <= span + 1e-9,
						("breathYield.outSeconds %.4f is longer than %s's Anticipation beat (%.4f): the breath leaves inside the wind-up"):format(
							out,
							tostring(clip.id),
							span
						)
					)
				end
			end
		end
		local Rigs = ctx.load("src/shared/data/rigs")
		local motorName = ctx.load("src/shared/data/weaponModels").motorName
		for rigId, rigClips in (if typeof(choreo.rigs) == "table" then choreo.rigs else {}) :: { [string]: any } do
			local rig = Rigs[rigId]
			if typeof(rigClips) ~= "table" or typeof(rigClips.breathing) ~= "string" or typeof(rig) ~= "table" then
				continue
			end
			local names: { [string]: boolean } = {}
			local byChild: { [string]: any } = {}
			local weapon: any = nil
			for _, joint in rig.joints do
				names[joint.name] = true
				byChild[joint.part1] = joint
				if joint.name == motorName then
					weapon = joint
				end
			end
			for name in listed do
				check(names[name] == true, ("breathYield.joints names %s, not a %s joint"):format(name, rigId))
			end
			-- The sword's chain: the weapon motor and each joint above it to the root part.
			local chain: { [string]: boolean } = {}
			local joint = weapon
			while joint ~= nil and chain[joint.name] == nil do
				chain[joint.name] = true
				joint = byChild[joint.part0]
			end
			local ok, clip = pcall(ctx.load, "src/shared/clips/" .. rigClips.breathing)
			if not ok or typeof(clip) ~= "table" or typeof(clip.keys) ~= "table" then
				continue
			end
			local keyed: { [string]: boolean } = {}
			for _, key in clip.keys do
				for name in key.joints or {} do
					keyed[name] = true
				end
			end
			for name in keyed do
				check(
					chain[name] ~= true or listed[name] == true,
					("breathYield.joints leaves out %s, which %s keys on the sword's chain: the breath would move the blade under every strike"):format(
						name,
						rigClips.breathing
					)
				)
			end
		end
	end

	local settle = if typeof(camera.stall) == "table" then camera.stall.settleSeconds else nil
	if positive(settle) then
		check(
			jump <= settle,
			("stall.jumpSeconds %.2f is over camera.stall.settleSeconds (%.2f): a gap the camera snaps through would replay the clips"):format(
				jump,
				settle
			)
		)
	end

	return problems
end
