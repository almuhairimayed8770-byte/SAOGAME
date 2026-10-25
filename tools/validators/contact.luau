--!strict
--[[
	Validates the contact numbers in src/shared/data/combat.luau `contact` that the hold for the
	server's word (D-CH1) and the swing's keep-out (D-CH3, D-CH4) run on, and the enemy blockers in
	src/shared/data/rigs.luau they keep out of:
	- contact.wordHoldSeconds is at least the Kill hold (hitStopFrames.Kill frames of
	  hitStopFrameSeconds), so a kill's word that comes inside it upgrades the hold in place and
	  never starts a second freeze (D-CH2);
	- contact.standOff.keepOut.maxStuds is at least standOff.maxStuds (it caps the Art's step and
	  the keep-out together, so it never cuts the step alone short) and within rootMotionSlack, so
	  the anti-cheat's mid-swing allowance covers the step, the keep-out and an Art's own root motion;
	- keepOut.bodyFace and keepOut.heldFace are RigBuilder's BLOCKER_NAME and HELD_BLOCKER_NAME, the
	  faces RigBuilder.addBlocker builds;
	- keepOut.parts names PlayerR15 parts (its root or a joint's part), keepOut.sampleSeconds and
	  maxTurnDegrees are above 0, and rounds and maxPieces are whole numbers of at least 1;
	- every rig's `blocker` poses clips of its own rig (enemy/<Rig>/...) that exist, every
	  sampleSeconds above 0.
]]

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value
end

local function isWhole(value: any, least: number): boolean
	return isNumber(value) and value >= least and value % 1 == 0
end

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "contact: " .. message)
		end
	end

	local combat = ctx.load("src/shared/data/combat")
	local rigs = ctx.load("src/shared/data/rigs")
	local RigBuilder = ctx.load("src/server/world/RigBuilder")

	local contact = combat.contact
	if typeof(contact) ~= "table" then
		check(false, "combat.contact is missing")
		return problems
	end

	-- D-CH1, D-CH2: the word's hold covers the Kill hold.
	local killHold = combat.hitStopFrames.Kill * combat.hitStopFrameSeconds
	check(
		isNumber(contact.wordHoldSeconds) and contact.wordHoldSeconds >= killHold - 1e-9,
		("wordHoldSeconds (%s) must be at least the Kill hold (%.4f s): a kill's word inside it upgrades the hold in place"):format(
			tostring(contact.wordHoldSeconds),
			killHold
		)
	)

	local standOff = contact.standOff
	local keepOut = if typeof(standOff) == "table" then standOff.keepOut else nil
	if typeof(keepOut) ~= "table" then
		check(false, "standOff.keepOut is missing")
		return problems
	end

	-- D-CH3: one budget for the step and the keep-out, inside the anti-cheat's slack.
	check(
		isNumber(keepOut.maxStuds) and keepOut.maxStuds >= standOff.maxStuds - 1e-9,
		("standOff.keepOut.maxStuds (%s) must be at least standOff.maxStuds (%s): it caps the step and the keep-out together"):format(
			tostring(keepOut.maxStuds),
			tostring(standOff.maxStuds)
		)
	)
	check(
		isNumber(keepOut.maxStuds) and keepOut.maxStuds <= combat.rootMotionSlack + 1e-9,
		("standOff.keepOut.maxStuds (%s) must be within rootMotionSlack (%s): the anti-cheat's mid-swing allowance covers it"):format(
			tostring(keepOut.maxStuds),
			tostring(combat.rootMotionSlack)
		)
	)

	-- D-CH4: the faces the keep-out stays out of are the ones RigBuilder builds.
	check(
		keepOut.bodyFace == RigBuilder.BLOCKER_NAME,
		("standOff.keepOut.bodyFace '%s' must be RigBuilder's BLOCKER_NAME '%s'"):format(
			tostring(keepOut.bodyFace),
			tostring(RigBuilder.BLOCKER_NAME)
		)
	)
	check(
		keepOut.heldFace == RigBuilder.HELD_BLOCKER_NAME,
		("standOff.keepOut.heldFace '%s' must be RigBuilder's HELD_BLOCKER_NAME '%s'"):format(
			tostring(keepOut.heldFace),
			tostring(RigBuilder.HELD_BLOCKER_NAME)
		)
	)

	-- The plan's own numbers.
	check(
		isNumber(keepOut.sampleSeconds) and keepOut.sampleSeconds > 0,
		"standOff.keepOut.sampleSeconds must be above 0"
	)
	check(
		isNumber(keepOut.maxTurnDegrees) and keepOut.maxTurnDegrees > 0,
		"standOff.keepOut.maxTurnDegrees must be above 0"
	)
	check(isWhole(keepOut.rounds, 1), "standOff.keepOut.rounds must be a whole number of at least 1")
	check(isWhole(keepOut.maxPieces, 1), "standOff.keepOut.maxPieces must be a whole number of at least 1")
	check(
		isNumber(keepOut.depthEpsilon) and keepOut.depthEpsilon >= 0,
		"standOff.keepOut.depthEpsilon must be 0 or more"
	)

	local player = rigs.PlayerR15
	local bodyParts: { [string]: boolean } = {}
	if typeof(player) == "table" then
		bodyParts[player.rootPart] = true
		for _, joint in player.joints do
			bodyParts[joint.part0] = true
			bodyParts[joint.part1] = true
		end
	end
	if typeof(keepOut.parts) ~= "table" or #keepOut.parts == 0 then
		check(false, "standOff.keepOut.parts must name the body's colliding parts")
	else
		for index, name in keepOut.parts do
			check(
				typeof(name) == "string" and bodyParts[name] == true,
				("standOff.keepOut.parts[%d] '%s' is not a PlayerR15 part"):format(index, tostring(name))
			)
		end
	end

	-- D-CH4: each rig's blocker is posed over its own rig's clips.
	local rigNames: { string } = {}
	for name in rigs do
		if typeof(name) == "string" then
			table.insert(rigNames, name)
		end
	end
	table.sort(rigNames)
	for _, name in rigNames do
		local blocker = rigs[name].blocker
		if blocker == nil then
			continue
		end
		local where = ("rigs.%s.blocker"):format(name)
		if typeof(blocker) ~= "table" then
			check(false, where .. " must be a table of clips and sampleSeconds")
			continue
		end
		check(isNumber(blocker.sampleSeconds) and blocker.sampleSeconds > 0, where .. ".sampleSeconds must be above 0")
		if typeof(blocker.clips) ~= "table" then
			check(false, where .. ".clips must list the loops the rig stands in")
			continue
		end
		for index, id in blocker.clips do
			local label = ("%s.clips[%d] '%s'"):format(where, index, tostring(id))
			if typeof(id) ~= "string" or string.sub(id, 1, #("enemy/" .. name .. "/")) ~= "enemy/" .. name .. "/" then
				check(false, ("%s must be one of the rig's own clips (enemy/%s/...)"):format(label, name))
				continue
			end
			local ok, clip = pcall(ctx.load, "src/shared/clips/" .. id)
			if not ok or typeof(clip) ~= "table" then
				check(false, label .. " is not a clip file")
				continue
			end
			check(clip.rig == name, ("%s plays on rig '%s', not %s"):format(label, tostring(clip.rig), name))
		end
	end

	return problems
end
