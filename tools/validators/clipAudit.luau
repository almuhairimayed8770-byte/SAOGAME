--!strict
--[[
	Validates the clip audit's numbers and part groups (src/shared/data/dev.luau review.audit,
	read by src/client/dev/ClipAudit.luau, tools/animation-review.luau and
	tests/choreo/ClipAudit.spec.luau). Each rule keeps the audit measuring what its comment says:
	- sampleHz: whole multiples of 60 (one 60 Hz frame is a whole number of samples), holding 60
	  (the game's frame) and 60 / the ClipLab's slowest speed (dev.luau clipLab.speeds: every frame
	  of the slowest review pass);
	- popDegrees inside (0, 180) and reportDegrees inside (0, popDegrees];
	- overlapStuds, weaponStuds, footSinkStuds and returnStuds above 0; footSlideStuds above 0 and
	  no looser than the gaits' own bar (choreo.luau locomotion.stride.slideBar); footDriftStuds at
	  least footSlideStuds (a plant drifts at least as far as it slides in one frame);
	- anticipation: maxCosine in [-1, 0) (a pull against the cut), minTravel above 0, maxSpeedShare
	  and maxHiddenShare in (0, 1) (under the snap's speed; seen for some of the beat);
	- recoveryFaceShare in [0, 1);
	- cancel.snapFrames a whole number in [2, 4] (a cancel's hand-over is a snap, section 10 beat 2);
	- afterFreezeTipSpeed in (0, 20] studs a second (the tip's step on the first frame after a
	  hit-stop, tests/choreo/PostFreezeStep.spec.luau; a tenth of a snap's peak at most);
	- leadSeconds at least the longest clip blend in (what plays under a clip is settled when it
	  starts), settleSeconds and loopOverSeconds above 0, maxTraceSeconds above the longest trace
	  (lead, chain, the longest clip and a loop's overrun, the longest blend-out, the settle),
	  segmentSamples a whole number of 1 or more;
	- idlePhases 0 or more, runPhases shares in [0, 1), chainSeconds inside combat.luau's chain
	  (at least basicHitDuration: the swing's beat; under basicChainWindow; the mashed chain, one
	  BasicAttackRequest refill after the swing, is the audit's other chain plan);
	- kinds: exactly the nine kinds ClipAudit.findings reports, once each;
	- rigs: each a rigs.luau rig; every body, pair, foot, weaponFree, visible, head and tip part one
	  of its parts (the weapon's pieces the rig's or weaponModels.luau guardPart / gripPart); the
	  tip an attachment name or a part with a three-number offset; visible shares above 0; every
	  clip it names (idle, breathing, drawnIdle, drawnRun, walk, chain, over, rush, airborne,
	  slideFree) a clip file of that rig, the chain and over clips non-looping on their keys' side;
	  a rush names an enemies.luau Charger and one of its attacks; views a list of "Behind" and
	  "Front", at least one and each once; each
	  cancels entry a clip and the clip it cuts (both clip files of that rig) and a gap at least 0
	  and inside the cut clip;
	- clips: each a clip file, listed once, of a rig the audit has.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local CLIPS = "src/shared/clips/"
local GAME_HZ = 60
local HALF_TURN_DEGREES = 180
local KINDS = { "Pop", "Overlap", "Weapon", "Slide", "Drift", "Sink", "Anticipation", "Return", "Recovery" }
local VIEWS = { "Behind", "Front" }
-- Studs a second: a tenth of a one-handed snap's peak (about 190 studs a second at 60 Hz).
local MAX_AFTER_FREEZE_TIP_SPEED = 20
-- Section 10 beat 2: a snap is 2 to 4 frames.
local SNAP_FRAMES_LOW, SNAP_FRAMES_HIGH = 2, 4

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isWhole(value: any): boolean
	return isNumber(value) and value % 1 == 0
end

return function(ctx: Context): { string }
	local problems: { string } = {}
	local function problem(text: string)
		table.insert(problems, "review.audit." .. text)
	end

	local Dev = ctx.load("src/shared/data/dev")
	local Choreo = ctx.load("src/shared/data/choreo")
	local Combat = ctx.load("src/shared/data/combat")
	local Rigs = ctx.load("src/shared/data/rigs")
	local WeaponModels = ctx.load("src/shared/data/weaponModels")
	local Enemies = ctx.load("src/shared/data/enemies")
	local audit = Dev.review and Dev.review.audit
	if typeof(audit) ~= "table" then
		return { "review.audit is missing" }
	end

	local function positive(key: string, value: any)
		if not (isNumber(value) and value > 0) then
			problem(("%s must be a number above 0 (got %s)"):format(key, tostring(value)))
		end
	end
	local function inRange(key: string, value: any, low: number, high: number, closedLow: boolean, closedHigh: boolean)
		local ok = isNumber(value)
			and (if closedLow then value >= low else value > low)
			and (if closedHigh then value <= high else value < high)
		if not ok then
			problem(
				("%s must be in %s%s, %s%s (got %s)"):format(
					key,
					if closedLow then "[" else "(",
					tostring(low),
					tostring(high),
					if closedHigh then "]" else ")",
					tostring(value)
				)
			)
		end
	end

	-- Sample rates.
	local slowest = math.huge
	for _, speed in Dev.clipLab.speeds do
		slowest = math.min(slowest, speed)
	end
	local reviewHz = GAME_HZ / slowest
	local rates: { [number]: boolean } = {}
	if typeof(audit.sampleHz) ~= "table" or #audit.sampleHz == 0 then
		problem("sampleHz must list the sample rates")
	else
		for index, hz in audit.sampleHz do
			if not (isWhole(hz) and hz >= GAME_HZ and hz % GAME_HZ == 0) then
				problem(("sampleHz[%d] must be a whole multiple of %d (got %s)"):format(index, GAME_HZ, tostring(hz)))
			else
				rates[hz] = true
			end
		end
		if not rates[GAME_HZ] then
			problem(("sampleHz must hold %d (the game's frame)"):format(GAME_HZ))
		end
		if not rates[reviewHz] then
			problem(("sampleHz must hold %g (every frame of the ClipLab's %gx pass)"):format(reviewHz, slowest))
		end
	end

	-- Thresholds.
	inRange("popDegrees", audit.popDegrees, 0, HALF_TURN_DEGREES, false, false)
	if isNumber(audit.popDegrees) then
		inRange("reportDegrees", audit.reportDegrees, 0, audit.popDegrees, false, true)
	end
	positive("overlapStuds", audit.overlapStuds)
	positive("weaponStuds", audit.weaponStuds)
	positive("footSinkStuds", audit.footSinkStuds)
	positive("returnStuds", audit.returnStuds)
	local slideBar = Choreo.locomotion.stride.slideBar
	inRange("footSlideStuds", audit.footSlideStuds, 0, slideBar, false, true)
	if
		isNumber(audit.footSlideStuds)
		and not (isNumber(audit.footDriftStuds) and audit.footDriftStuds >= audit.footSlideStuds)
	then
		problem(
			("footDriftStuds must be at least footSlideStuds %s (got %s)"):format(
				tostring(audit.footSlideStuds),
				tostring(audit.footDriftStuds)
			)
		)
	end
	local anticipation = audit.anticipation
	if typeof(anticipation) ~= "table" then
		problem("anticipation is missing")
	else
		inRange("anticipation.maxCosine", anticipation.maxCosine, -1, 0, true, false)
		positive("anticipation.minTravel", anticipation.minTravel)
		inRange("anticipation.maxSpeedShare", anticipation.maxSpeedShare, 0, 1, false, false)
		inRange("anticipation.maxHiddenShare", anticipation.maxHiddenShare, 0, 1, false, false)
	end
	inRange("recoveryFaceShare", audit.recoveryFaceShare, 0, 1, true, false)
	-- The tip's step out of a freeze: above 0, and under what one held frame's settle would take
	-- at the slowest snap (a bar the snap's own speed could pass is no bar).
	inRange("afterFreezeTipSpeed", audit.afterFreezeTipSpeed, 0, MAX_AFTER_FREEZE_TIP_SPEED, false, true)
	-- A cancel's hand-over is a snap: 2 to 4 whole 60 Hz frames (section 10 beat 2).
	local cancel = audit.cancel
	local snapFrames = if typeof(cancel) == "table" then cancel.snapFrames else nil
	if not (isWhole(snapFrames) and snapFrames >= SNAP_FRAMES_LOW and snapFrames <= SNAP_FRAMES_HIGH) then
		problem(
			("cancel.snapFrames must be a whole number of frames in [%d, %d] (got %s)"):format(
				SNAP_FRAMES_LOW,
				SNAP_FRAMES_HIGH,
				tostring(snapFrames)
			)
		)
	end

	-- The trace.
	local longestBlendIn, longestBlendOut, longestClip = 0, 0, 0
	for _, file in ctx.listFiles("src/shared/clips", "%.luau$") do
		local clip = ctx.load((file:gsub("%.luau$", "")))
		longestBlendIn = math.max(longestBlendIn, clip.blendIn or Choreo.blendIn or 0)
		longestBlendOut = math.max(longestBlendOut, clip.blendOut or Choreo.blendOut or 0)
		longestClip = math.max(longestClip, clip.duration or 0)
	end
	if not (isNumber(audit.leadSeconds) and audit.leadSeconds >= longestBlendIn and audit.leadSeconds > 0) then
		problem(
			("leadSeconds must be above 0 and at least the longest clip blendIn %g (got %s)"):format(
				longestBlendIn,
				tostring(audit.leadSeconds)
			)
		)
	end
	positive("settleSeconds", audit.settleSeconds)
	positive("loopOverSeconds", audit.loopOverSeconds)
	if
		isNumber(audit.leadSeconds)
		and isNumber(audit.chainSeconds)
		and isNumber(audit.settleSeconds)
		and isNumber(audit.loopOverSeconds)
	then
		local longest = audit.leadSeconds
			+ audit.chainSeconds
			+ longestClip
			+ audit.loopOverSeconds
			+ longestBlendOut
			+ audit.settleSeconds
		if not (isNumber(audit.maxTraceSeconds) and audit.maxTraceSeconds > longest) then
			problem(
				("maxTraceSeconds must be above the longest trace %g s (got %s)"):format(
					longest,
					tostring(audit.maxTraceSeconds)
				)
			)
		end
	end
	if not (isWhole(audit.segmentSamples) and audit.segmentSamples >= 1) then
		problem(("segmentSamples must be a whole number of 1 or more (got %s)"):format(tostring(audit.segmentSamples)))
	end
	for index, phase in audit.idlePhases or {} do
		inRange(("idlePhases[%d]"):format(index), phase, 0, math.huge, true, false)
	end
	if #(audit.idlePhases or {}) == 0 then
		problem("idlePhases must list at least one phase")
	end
	for index, share in audit.runPhases or {} do
		inRange(("runPhases[%d]"):format(index), share, 0, 1, true, false)
	end
	inRange("chainSeconds", audit.chainSeconds, Combat.basicHitDuration, Combat.basicChainWindow, true, false)

	-- Kinds.
	local listed: { [string]: number } = {}
	for _, kind in audit.kinds or {} do
		listed[kind] = (listed[kind] or 0) + 1
	end
	for _, kind in KINDS do
		if listed[kind] ~= 1 then
			problem(("kinds must list %s once (listed %d times)"):format(kind, listed[kind] or 0))
		end
	end
	for kind in listed do
		if not table.find(KINDS, kind) then
			problem(("kinds lists %s, which ClipAudit never reports"):format(kind))
		end
	end

	-- Rigs.
	local function clipOf(id: any, rigId: string, key: string): any
		if typeof(id) ~= "string" then
			problem(("rigs.%s.%s must be a clip id (got %s)"):format(rigId, key, tostring(id)))
			return nil
		end
		local ok, clip = pcall(ctx.load, CLIPS .. id)
		if not ok or typeof(clip) ~= "table" then
			problem(("rigs.%s.%s names %s, which has no clip file"):format(rigId, key, id))
			return nil
		end
		if clip.rig ~= rigId then
			problem(("rigs.%s.%s names %s, a %s clip"):format(rigId, key, id, tostring(clip.rig)))
		end
		return clip
	end
	for rigId, config in audit.rigs or {} do
		local rig = Rigs[rigId]
		if typeof(rig) ~= "table" then
			problem(("rigs.%s is not a rigs.luau rig"):format(tostring(rigId)))
			continue
		end
		local parts: { [string]: boolean } = {}
		for _, joint in rig.joints do
			parts[joint.part0] = true
			parts[joint.part1] = true
		end
		local function part(name: any, key: string)
			if typeof(name) ~= "string" or not parts[name] then
				problem(("rigs.%s.%s names %s, not a %s part"):format(rigId, key, tostring(name), rigId))
			end
		end
		if typeof(config.body) ~= "table" or #config.body == 0 then
			problem(("rigs.%s.body must list the visible parts"):format(rigId))
		end
		local body: { [string]: boolean } = {}
		for index, name in config.body or {} do
			part(name, ("body[%d]"):format(index))
			if name == rig.rootPart then
				problem(("rigs.%s.body lists %s, which is not drawn"):format(rigId, name))
			end
			body[name] = true
		end
		local function bodyPart(name: any, key: string)
			part(name, key)
			if typeof(name) == "string" and parts[name] and not body[name] then
				problem(("rigs.%s.%s names %s, which body does not list"):format(rigId, key, name))
			end
		end
		for index, group in config.pairs or {} do
			if typeof(group.a) ~= "table" or #group.a == 0 or typeof(group.b) ~= "table" or #group.b == 0 then
				problem(("rigs.%s.pairs[%d] must hold two part lists a and b"):format(rigId, index))
				continue
			end
			for slot, name in group.a do
				bodyPart(name, ("pairs[%d].a[%d]"):format(index, slot))
			end
			for slot, name in group.b do
				bodyPart(name, ("pairs[%d].b[%d]"):format(index, slot))
			end
		end
		if typeof(config.feet) ~= "table" or #config.feet == 0 then
			problem(("rigs.%s.feet must list the parts that stand on the field"):format(rigId))
		end
		for index, name in config.feet or {} do
			bodyPart(name, ("feet[%d]"):format(index))
		end
		local weaponNames = table.clone(parts)
		weaponNames[WeaponModels.guardPart] = true
		weaponNames[WeaponModels.gripPart] = true
		for index, name in config.weapon or {} do
			if typeof(name) ~= "string" or not weaponNames[name] then
				problem(("rigs.%s.weapon[%d] names %s, not a weapon piece"):format(rigId, index, tostring(name)))
			end
		end
		if config.weaponFree ~= nil and config.weapon == nil then
			problem(("rigs.%s.weaponFree needs a weapon"):format(rigId))
		end
		for index, name in config.weaponFree or {} do
			bodyPart(name, ("weaponFree[%d]"):format(index))
		end
		for name, share in config.visible or {} do
			bodyPart(name, "visible")
			local ok = typeof(share) == "table" and #share == 3
			for _, value in if ok then share else {} do
				ok = ok and isNumber(value) and value > 0
			end
			if not ok then
				problem(("rigs.%s.visible.%s must be three shares above 0"):format(rigId, tostring(name)))
			end
		end
		if config.head ~= nil then
			bodyPart(config.head, "head")
		end
		local tip = config.tip
		if tip ~= nil then
			if tip.attachment ~= nil then
				if typeof(tip.attachment) ~= "string" or tip.attachment == "" then
					problem(("rigs.%s.tip.attachment must be an attachment name"):format(rigId))
				end
			else
				bodyPart(tip.part, "tip.part")
				local ok = typeof(tip.offset) == "table" and #tip.offset == 3
				for _, value in if ok then tip.offset else {} do
					ok = ok and isNumber(value)
				end
				if not ok then
					problem(("rigs.%s.tip.offset must be three numbers"):format(rigId))
				end
			end
		end
		-- The views the tells are judged from (D-414): one at least, each Behind or Front, once.
		if typeof(config.views) ~= "table" or #config.views == 0 then
			problem(("rigs.%s.views must list the views the gameplay camera sees it from"):format(rigId))
		else
			local seenViews: { [string]: boolean } = {}
			for index, view in config.views do
				if not table.find(VIEWS, view) then
					problem(("rigs.%s.views[%d] must be Behind or Front (got %s)"):format(rigId, index, tostring(view)))
				elseif seenViews[view] then
					problem(("rigs.%s.views lists %s twice"):format(rigId, view))
				end
				seenViews[view] = true
			end
		end
		for _, key in { "idle", "breathing", "drawnIdle", "drawnRun", "walk" } do
			local id = config[key]
			if id ~= nil then
				local clip = clipOf(id, rigId, key)
				if clip ~= nil and not clip.loop then
					problem(("rigs.%s.%s names %s, which does not loop"):format(rigId, key, id))
				end
			end
		end
		for _, key in { "chain", "over" } do
			for id, before in config[key] or {} do
				local clip = clipOf(id, rigId, key)
				clipOf(before, rigId, ("%s[%s]"):format(key, tostring(id)))
				if clip ~= nil and clip.loop then
					problem(("rigs.%s.%s names %s, which loops"):format(rigId, key, tostring(id)))
				end
			end
		end
		for index, cancelPlan in config.cancels or {} do
			local key = ("cancels[%d]"):format(index)
			if typeof(cancelPlan) ~= "table" then
				problem(("rigs.%s.%s must be a table of clip, over and gap"):format(rigId, key))
				continue
			end
			clipOf(cancelPlan.clip, rigId, key .. ".clip")
			local over = clipOf(cancelPlan.over, rigId, key .. ".over")
			local gap = cancelPlan.gap
			local length = if over ~= nil then over.duration else nil
			if not (isNumber(gap) and gap >= 0 and (length == nil or gap < length)) then
				problem(
					("rigs.%s.%s.gap must be at least 0 and inside %s (%s s; got %s)"):format(
						rigId,
						key,
						tostring(cancelPlan.over),
						tostring(length),
						tostring(gap)
					)
				)
			end
		end
		for _, key in { "airborne", "slideFree" } do
			for index, id in config[key] or {} do
				clipOf(id, rigId, ("%s[%d]"):format(key, index))
			end
		end
		for id, rush in config.rush or {} do
			clipOf(id, rigId, "rush")
			local enemy = if typeof(rush) == "table" and typeof(rush.enemy) == "string"
				then Enemies.byId(rush.enemy)
				else nil
			if enemy == nil or enemy.archetype ~= "Charger" then
				problem(
					("rigs.%s.rush[%s] must name an enemies.luau Charger (got %s)"):format(
						rigId,
						tostring(id),
						tostring(if typeof(rush) == "table" then rush.enemy else rush)
					)
				)
				continue
			end
			local found = false
			for _, attack in enemy.attacks do
				found = found or attack.id == rush.attack
			end
			if not found then
				problem(
					("rigs.%s.rush[%s] names %s, not an attack of %s"):format(
						rigId,
						tostring(id),
						tostring(rush.attack),
						rush.enemy
					)
				)
			end
		end
	end
	-- The audited clips.
	local seen: { [string]: boolean } = {}
	if typeof(audit.clips) ~= "table" or #audit.clips == 0 then
		problem("clips must list the clips the audit plays")
	end
	for index, id in audit.clips or {} do
		if seen[id] then
			problem(("clips[%d] lists %s twice"):format(index, tostring(id)))
		end
		seen[id] = true
		local ok, clip = pcall(ctx.load, CLIPS .. tostring(id))
		if not ok or typeof(clip) ~= "table" then
			problem(("clips[%d] names %s, which has no clip file"):format(index, tostring(id)))
		elseif (audit.rigs or {})[clip.rig] == nil then
			problem(
				("clips[%d] names %s, a %s clip the audit has no rig for"):format(
					index,
					tostring(id),
					tostring(clip.rig)
				)
			)
		end
	end
	return problems
end
