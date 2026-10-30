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
	sheath.handOverBlend is a positive number of seconds.

	And the cancel hand-over (D-408): handOver.seconds is above 0 and at most dev.luau
	review.audit.cancel.snapFrames 60 Hz frames (a cancel is a snap, section 10 beat 2), and
	handOver.easing a util/Easing curve other than Linear and Hold.

	And the gait hand-off (D-404): locomotion.handOff.seconds is above 0; every joint it lists is
	a PlayerR15 joint (rigs.luau) with a factor in (0, 3]; and for every attack clip under
	locomotion.clipPrefix the longest hand-off blend (its blendIn or seconds, the longer, times the
	largest factor) ends by its first strike key (the first strike snap key in its first damage
	window, ContactPredictor.strikeKey): the hit is drawn on that key's pose, the clip's own.
]]

local TIERS = { "High", "Medium", "Low" }
-- The longest a gait hand-off may stretch a joint's blend, in times its base.
local MAX_HAND_OFF_FACTOR = 3
local RATES = { "distantHz", "farHz" }
-- The turn plant's turn clips (locomotion.clips keys), its most twist, the turn it must bring
-- round (a target straight behind) and the samples its curve's slope is read at.
local TURN_CLIPS = { "TurnLeft", "TurnRight", "TurnLeftDrawn", "TurnRightDrawn" }
local MAX_TURN_TWIST = 90
local HALF_TURN = 180
local SLOPE_SAMPLES = 1000

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

	-- The turn plant (D-416): the hips come round between a turn clip's first two Footsteps, the
	-- pivot foot's and then the other's, at most stepDegrees a 60 Hz frame (a pop is the most);
	-- the window is long enough for half a turn at that cap on the curve's steepest stretch; a
	-- lag the body leaves standing lets go by every attack's first strike key; the Waist's lead
	-- stays a twist; and a second turn never cuts a turn clip's own steps.
	local loco = if typeof(choreo.locomotion) == "table" then choreo.locomotion else {}
	local plant = loco.turnPlant
	if typeof(plant) ~= "table" then
		check(false, "locomotion.turnPlant is missing (stepDegrees, plantSeconds, twistDegrees, easing)")
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
			local span = second.time - first.time
			local need = if positive(step) and eased then HALF_TURN * slope / (step * 60) else 0
			check(
				span >= need - 1e-9,
				("%s's window between its first two Footsteps (%.3f s) is under %.3f s: half a turn on %s at stepDegrees would not come round"):format(
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
