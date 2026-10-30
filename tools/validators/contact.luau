--!strict
--[[
	Validates the contact numbers in src/shared/data/combat.luau `contact` that the hold for the
	server's word (D-312) and the swing's keep-out (D-314, D-315) run on, and the enemy blockers in
	src/shared/data/rigs.luau they keep out of:
	- contact.wordHoldSeconds is at least the Kill hold (hitStopFrames.Kill frames of
	  hitStopFrameSeconds), so a kill's word that comes inside it upgrades the hold in place and
	  never starts a second freeze (D-313);
	- contact.standOff.keepOut.maxStuds is at least standOff.maxStuds (it caps the Art's step and
	  the keep-out together, so it never cuts the step alone short) and within rootMotionSlack, so
	  the anti-cheat's mid-swing allowance covers the step, the keep-out and an Art's own root motion;
	- keepOut.bodyFace and keepOut.heldFace are RigBuilder's BLOCKER_NAME and HELD_BLOCKER_NAME, the
	  faces RigBuilder.addBlocker builds;
	- keepOut.parts names PlayerR15 parts (its root or a joint's part), keepOut.sampleSeconds and
	  maxTurnDegrees are above 0, and rounds and maxPieces are whole numbers of at least 1;
	- what the body shows of it (item 285): keepOut.maxSpeedStudsPerSecond is above 0 and within
	  maxSpeedStudsPerSecond (the sprint cap), leadSeconds is at least sampleSeconds and covers a
	  whole stand-off step (standOff.maxStuds) at that speed, and speedPieces is a whole number of
	  at least 1;
	- the reach (D-424): keepOut.limbs names PlayerR15 parts, each once and none of keepOut.parts (a
	  hand or an arm the strike's key keeps out of the target's body, apart from what the keep-out
	  keeps out of its blocker), and keepOut.bladeDepthStuds is 0 or more (a key that holds the
	  blade off the body would cost the hit) and within the sweep's promise (hitSphereRadius less
	  half of sweepMaxTipStep), the depth a cut still reads as touching at, and
	  keepOut.stepPerDepth (the studs of step a stud of depth is worth) is a finite 1 or more;
	- every rig's `blocker` and `rush` (D-437: the poses a rush is judged against walls in) pose
	  clips of its own rig (enemy/<Rig>/...) that exist, at least one, every sampleSeconds above 0;
	- the walk shell (item 236, D-430): a blocker's heldSlices is a whole number of at least 1, and
	  a rig that holds parts (trailParts) and has a blocker names it (the shell meets what it holds
	  as that many boxes); every rig's `shell` names parts of its own rig, each once and, on
	  PlayerR15, none of keepOut.parts (the engine already stops those at the faces), boxes them
	  over at least one `sheathed` and one `drawn` clip of its own rig that exists, posed every
	  sampleSeconds above 0 and padded padStuds, a finite 0 or more; contact.walkShell.halvings is
	  a whole number of at least 1.
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

	-- D-312, D-313: the word's hold covers the Kill hold.
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

	-- D-314: one budget for the step and the keep-out, inside the anti-cheat's slack.
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

	-- D-315: the faces the keep-out stays out of are the ones RigBuilder builds.
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
	-- Item 285: how fast the body shows the keep-out, and how far ahead it starts.
	check(
		isNumber(keepOut.maxSpeedStudsPerSecond)
			and keepOut.maxSpeedStudsPerSecond > 0
			and keepOut.maxSpeedStudsPerSecond <= combat.maxSpeedStudsPerSecond + 1e-9,
		("standOff.keepOut.maxSpeedStudsPerSecond (%s) must be above 0 and within maxSpeedStudsPerSecond (%s): the keep-out never outruns a sprint"):format(
			tostring(keepOut.maxSpeedStudsPerSecond),
			tostring(combat.maxSpeedStudsPerSecond)
		)
	)
	check(
		isNumber(keepOut.leadSeconds)
			and isNumber(keepOut.sampleSeconds)
			and keepOut.leadSeconds >= keepOut.sampleSeconds - 1e-9,
		("standOff.keepOut.leadSeconds (%s) must be at least sampleSeconds: the lead reads samples ahead"):format(
			tostring(keepOut.leadSeconds)
		)
	)
	check(
		isNumber(keepOut.leadSeconds)
			and isNumber(keepOut.maxSpeedStudsPerSecond)
			and isNumber(standOff.maxStuds)
			and keepOut.leadSeconds * keepOut.maxSpeedStudsPerSecond >= standOff.maxStuds - 1e-9,
		("standOff.keepOut.leadSeconds (%s) at maxSpeedStudsPerSecond must cover standOff.maxStuds (%s): a whole step starts early enough to be taken at that speed"):format(
			tostring(keepOut.leadSeconds),
			tostring(standOff.maxStuds)
		)
	)
	check(isWhole(keepOut.speedPieces, 1), "standOff.keepOut.speedPieces must be a whole number of at least 1")

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

	-- D-424: the reach's hands and arms, and how deep the blade may stand at a strike's key.
	local colliding: { [string]: boolean } = {}
	if typeof(keepOut.parts) == "table" then
		for _, name in keepOut.parts do
			colliding[name] = true
		end
	end
	if typeof(keepOut.limbs) ~= "table" or #keepOut.limbs == 0 then
		check(false, "standOff.keepOut.limbs must name the hands and arms the reach keeps out")
	else
		local seen: { [string]: boolean } = {}
		for index, name in keepOut.limbs do
			local label = ("standOff.keepOut.limbs[%d] '%s'"):format(index, tostring(name))
			if typeof(name) ~= "string" or bodyParts[name] ~= true then
				check(false, label .. " is not a PlayerR15 part")
			elseif colliding[name] then
				check(false, label .. " is one of keepOut.parts: the keep-out already holds it out of the blocker")
			elseif seen[name] then
				check(false, label .. " is named twice")
			end
			if typeof(name) == "string" then
				seen[name] = true
			end
		end
	end
	local promise = combat.hitSphereRadius - combat.sweepMaxTipStep * 0.5
	check(
		isNumber(keepOut.bladeDepthStuds) and keepOut.bladeDepthStuds >= 0,
		("standOff.keepOut.bladeDepthStuds (%s) must be 0 or more: a key that holds the blade off the body costs the hit"):format(
			tostring(keepOut.bladeDepthStuds)
		)
	)
	check(
		isNumber(keepOut.bladeDepthStuds) and keepOut.bladeDepthStuds <= promise + 1e-6,
		("standOff.keepOut.bladeDepthStuds (%s) must be within the sweep's promise (%.3f: hitSphereRadius less half of sweepMaxTipStep)"):format(
			tostring(keepOut.bladeDepthStuds),
			promise
		)
	)
	check(
		isNumber(keepOut.stepPerDepth) and keepOut.stepPerDepth >= 1 and keepOut.stepPerDepth < math.huge,
		("standOff.keepOut.stepPerDepth (%s) must be 1 or more: a depth moves no farther than the body, so a step that clears a key is at least as long as the depth it takes off"):format(
			tostring(keepOut.stepPerDepth)
		)
	)

	-- D-315: each rig's blocker is posed over its own rig's clips.
	local rigNames: { string } = {}
	for name in rigs do
		if typeof(name) == "string" then
			table.insert(rigNames, name)
		end
	end
	table.sort(rigNames)
	-- D-437: so is the set of poses its rush is judged against walls in (`rush`).
	for _, name in rigNames do
		for _, field in { "blocker", "rush" } do
			local blocker = rigs[name][field]
			if blocker == nil then
				continue
			end
			local where = ("rigs.%s.%s"):format(name, field)
			if typeof(blocker) ~= "table" then
				check(false, where .. " must be a table of clips and sampleSeconds")
				continue
			end
			check(
				isNumber(blocker.sampleSeconds) and blocker.sampleSeconds > 0,
				where .. ".sampleSeconds must be above 0"
			)
			if typeof(blocker.clips) ~= "table" or #blocker.clips == 0 then
				check(
					false,
					where
						.. (
							if field == "rush"
								then ".clips must list the clips the rig rushes in"
								else ".clips must list the loops the rig stands in"
						)
				)
				continue
			end
			for index, id in blocker.clips do
				local label = ("%s.clips[%d] '%s'"):format(where, index, tostring(id))
				if
					typeof(id) ~= "string"
					or string.sub(id, 1, #("enemy/" .. name .. "/")) ~= "enemy/" .. name .. "/"
				then
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
	end

	-- Item 236 (D-430): what the walk shell meets of a held part, the shell itself, and its cut.
	for _, name in rigNames do
		local rig = rigs[name]
		local blocker = rig.blocker
		if typeof(blocker) == "table" then
			local where = ("rigs.%s.blocker.heldSlices"):format(name)
			if blocker.heldSlices ~= nil then
				check(isWhole(blocker.heldSlices, 1), where .. " must be a whole number of at least 1")
			elseif typeof(rig.trailParts) == "table" and #rig.trailParts > 0 then
				check(false, where .. " must be set: the rig holds parts (trailParts) the walk shell meets as boxes")
			end
		end
		local shell = rig.shell
		if shell == nil then
			continue
		end
		local where = ("rigs.%s.shell"):format(name)
		if typeof(shell) ~= "table" then
			check(false, where .. " must be a table of parts, sheathed, drawn, sampleSeconds and padStuds")
			continue
		end
		local ownParts: { [string]: boolean } = {}
		ownParts[rig.rootPart] = true
		for _, joint in rig.joints or {} do
			ownParts[joint.part0] = true
			ownParts[joint.part1] = true
		end
		if typeof(shell.parts) ~= "table" or #shell.parts == 0 then
			check(false, where .. ".parts must name the parts the shell boxes")
		else
			local seen: { [string]: boolean } = {}
			for index, partName in shell.parts do
				local label = ("%s.parts[%d] '%s'"):format(where, index, tostring(partName))
				if typeof(partName) ~= "string" or ownParts[partName] ~= true then
					check(false, ("%s is not a %s part"):format(label, name))
				elseif name == "PlayerR15" and colliding[partName] then
					check(false, label .. " is one of keepOut.parts: the engine already stops it at the faces")
				elseif seen[partName] then
					check(false, label .. " is named twice")
				end
				if typeof(partName) == "string" then
					seen[partName] = true
				end
			end
		end
		for _, field in { "sheathed", "drawn" } do
			local clips = shell[field]
			if typeof(clips) ~= "table" or #clips == 0 then
				check(false, ("%s.%s must list the clips the %s stance stands in"):format(where, field, field))
				continue
			end
			for index, id in clips do
				local label = ("%s.%s[%d] '%s'"):format(where, field, index, tostring(id))
				local ok, clip = pcall(ctx.load, "src/shared/clips/" .. tostring(id))
				if typeof(id) ~= "string" or not ok or typeof(clip) ~= "table" then
					check(false, label .. " is not a clip file")
					continue
				end
				check(clip.rig == name, ("%s plays on rig '%s', not %s"):format(label, tostring(clip.rig), name))
			end
		end
		check(isNumber(shell.sampleSeconds) and shell.sampleSeconds > 0, where .. ".sampleSeconds must be above 0")
		check(
			isNumber(shell.padStuds) and shell.padStuds >= 0 and shell.padStuds < math.huge,
			where .. ".padStuds must be a finite 0 or more"
		)
	end
	local walkShell = contact.walkShell
	check(
		typeof(walkShell) == "table" and isWhole(walkShell.halvings, 1),
		"walkShell.halvings must be a whole number of at least 1"
	)

	return problems
end
