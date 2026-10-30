--!strict
--[[
	The body review of every audited clip (section 10 "Review loop"; section 21 gate line 4: "No
	T-pose, A-pose, frozen rig, popping limb or sliding foot appears in any clip"). Every clip
	dev.luau review.audit.clips lists is played the way the game plays it (ClipAudit.plans: cut in
	as the ClipLab shows it, blended in over the stance at two points of its cycle, out of the drawn
	run, chained after the basic before it on its beat and mashed, out of the guard), through the real Mixer on the real
	rigs (the hit matrix's player, RigBuilder's boar and kobold) at every review.audit.sampleHz, and
	measured per frame by ClipAudit: no limb turns past popDegrees in a frame outside a strike's
	snap, no body part sinks into another nor the weapon into the body past their bounds, no planted
	foot slides or drifts nor sinks below the field, the first strike's anticipation pulls against
	the cut, travels, stays slower than the snap and is seen from the gameplay camera, the blend
	back to the stance is a settle, and the Recovery does not hold the blade across the face.

	PENDING (below) is the one list of what the clips do not meet yet, by clip, kind and plan, with
	how far past its bound each is: a pending clip must fail exactly that (a new kind, a kind in
	another plan or further past its bound fails, and so does a listed one it no longer has: take
	it off the list). The fix stage empties it; the bounds never move to make a clip pass (they are
	data, dev.luau review.audit, with validator rules).

	The second half checks the rules catch what they are for: a real clean clip made to pop, push
	an arm into the torso, turn the blade into the arm, slide and sink its feet, a real attack made
	to hide its anticipation, pending clips given a fault they did not have or a worse one; the
	strike, return and Recovery rules on reports; and the bounds against every problem the owner's
	PC review saw (none may be loosened past what the eye already caught).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Dev = Harness.load("src/shared/data/dev")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")

local Audit = Dev.review.audit
local root = Harness.repoRoot()

-- What each audited clip does not meet yet: by clip, kind (review.audit.kinds) and plan (the
-- ClipAudit.plans label), the most its findings of that kind in that plan are past their bound
-- (the finding's excess, rounded up to the hundredth: degrees past popDegrees, studs past a stud
-- bound, a share or a cosine past an anticipation bound). Measured on the pass after cebade4; the
-- player attacks' entries shrunk with the gait hand-off and the cancel hand-over (D-404, D-408), and
-- the flinches' and DeathFreeze's Sink over the drawn idle went with its sole (D-417), and the
-- Kobold walk's Sink with its root at the idle's height (D-418; its Drift shrank with it). A
-- clip fails a kind it does not list, a kind in a plan it does not list it for, a listed kind and
-- plan past that excess, and a listed kind and plan it no longer has (take it off). The fix stage
-- takes entries off; an entry never grows.
local PENDING: { [string]: { [string]: { [string]: number } } } = {
	["player/OneHandedSword/Basic1"] = {
		Overlap = { ["Run@0.5"] = 0.03 },
	},
	["player/OneHandedSword/Basic2"] = {
		Pop = { ["Run@0.5"] = 0.24 },
		Overlap = { ["Run@0.5"] = 0.03 },
		Anticipation = { ["Run@0.5"] = 0.17, ["Mash after Basic1"] = 0.31 },
	},
	["player/OneHandedSword/Basic3"] = {
		Overlap = { ["Run@0.5"] = 0.03 },
	},
	["player/OneHandedSword/Horizontal"] = {
		Overlap = { ["Run@0.5"] = 0.03 },
	},
	["player/OneHandedSword/Vertical"] = {
		Overlap = { ["Run@0.5"] = 0.03 },
	},
	["player/OneHandedSword/SharpNail"] = {
		Overlap = { ["Run@0.5"] = 0.03 },
	},
	["player/OneHandedSword/RisingArc"] = {
		Overlap = { ["Run@0.5"] = 0.04 },
	},
	["enemy/Boar/Walk"] = {
		Slide = { ["Lab"] = 0.29 },
		Drift = { ["Lab"] = 4.88 },
	},
	["enemy/Boar/Break"] = {
		Pop = { ["Lab"] = 20.06, ["Stand@0"] = 34.22, ["Stand@6"] = 35.31 },
		Slide = { ["Lab"] = 1.23, ["Stand@0"] = 0.22, ["Stand@6"] = 0.22 },
		Drift = { ["Lab"] = 1.94, ["Stand@0"] = 1.94, ["Stand@6"] = 1.84 },
		Sink = { ["Lab"] = 0.23, ["Stand@0"] = 0.23, ["Stand@6"] = 0.24 },
	},
	["enemy/Boar/Stagger"] = {
		Pop = { ["Lab"] = 17.44, ["Stand@0"] = 38.22, ["Stand@6"] = 42.27 },
		Slide = { ["Lab"] = 0.37, ["Stand@0"] = 0.37, ["Stand@6"] = 0.37 },
		Drift = { ["Lab"] = 0.81, ["Stand@0"] = 0.81, ["Stand@6"] = 0.81 },
		Sink = { ["Lab"] = 0.51, ["Stand@0"] = 0.51, ["Stand@6"] = 0.51 },
	},
	["enemy/Kobold/Walk"] = {
		Slide = { ["Lab"] = 0.22 },
		Drift = { ["Lab"] = 2.61 },
	},
	["enemy/Kobold/Break"] = {
		Pop = { ["Lab"] = 21.24, ["Stand@0"] = 35.13, ["Stand@6"] = 35.27 },
		Slide = { ["Lab"] = 0.39, ["Stand@0"] = 0.22, ["Stand@6"] = 0.22 },
		Drift = { ["Lab"] = 1.48, ["Stand@0"] = 1.48, ["Stand@6"] = 1.4 },
		Sink = { ["Lab"] = 1.11, ["Stand@0"] = 1.11, ["Stand@6"] = 1.11 },
	},
}

-- tools/ modules are plain Lune scripts: load one with only Lune's own libraries to require.
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target) :: any
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local bodies: { [string]: any } = {}
local function bodyOf(rig: string): any
	local found = bodies[rig]
	if found == nil then
		if rig == "PlayerR15" then
			local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
			local avatar, field = HitMatrix.standing(Harness)
			found = ClipAudit.body(avatar.model, rig, avatar.base, ClipAudit.topOf(field.CFrame, field.Size))
		else
			found = ClipAudit.standingBody(RigBuilder.build(rig), rig)
		end
		bodies[rig] = found
	end
	return found
end

local function findingsOf(clip: any): { any }
	local _, findings = ClipAudit.audit(bodyOf(clip.rig), clip, ClipLibrary.get)
	return findings
end

local function listed(findings: { any }, keep: (string) -> boolean): string
	local lines = {}
	for _, finding in ClipAudit.worst(findings) do
		if keep(finding.kind) then
			table.insert(lines, "  " .. finding.text)
		end
	end
	return table.concat(lines, "\n")
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, element in value do
		copy[key] = deepCopy(element)
	end
	return copy
end

-- What a clip's findings break of its PENDING entry (see PENDING): one line for the worst finding
-- of each kind, subject and plan that is not pending or is past its pending excess, and one for
-- each pending kind and plan the clip no longer has.
local function unmet(id: string, findings: { any }): { string }
	local pending = PENDING[id] or {}
	local seen: { [string]: boolean } = {}
	local worst: { [string]: any } = {}
	for _, finding in findings do
		local plans = pending[finding.kind]
		local most = if plans ~= nil then plans[finding.plan] else nil
		seen[finding.kind .. "|" .. finding.plan] = true
		if most == nil or finding.excess > most + 1e-9 then
			local key = finding.kind .. "|" .. finding.what .. "|" .. finding.plan
			if worst[key] == nil or finding.excess > worst[key].excess then
				worst[key] = finding
			end
		end
	end
	local problems: { string } = {}
	for _, finding in worst do
		local most = (pending[finding.kind] or {})[finding.plan]
		table.insert(
			problems,
			if most == nil
				then ("%s fails %s (not pending in %s)"):format(id, finding.text, finding.plan)
				else ("%s fails %s (pending up to %.2f past the bound)"):format(id, finding.text, most)
		)
	end
	for kind, plans in pending do
		for plan in plans do
			if not seen[kind .. "|" .. plan] then
				table.insert(problems, ("%s now passes %s in %s: take it off PENDING"):format(id, kind, plan))
			end
		end
	end
	table.sort(problems)
	return problems
end

describe("ClipAudit: every audited clip", function()
	it("the pending list names audited clips, audit kinds and the clips' own plans only", function()
		local audited: { [string]: boolean } = {}
		for _, id in Audit.clips do
			audited[id] = true
		end
		for id, kinds in PENDING do
			expect(audited[id]).toBe(true)
			local labels: { [string]: boolean } = {}
			for _, plan in ClipAudit.plans(ClipLibrary.get(id), ClipLibrary.get) do
				labels[plan.label] = true
			end
			for kind, plans in kinds do
				expect(table.find(Audit.kinds, kind) ~= nil).toBe(true)
				for plan, most in plans do
					expect(labels[plan]).toBe(true)
					expect(most > 0).toBe(true)
				end
			end
		end
	end)

	for _, id in Audit.clips do
		it(id .. " passes the body review (or fails exactly what is pending, no worse)", function()
			local problems = unmet(id, findingsOf(ClipLibrary.get(id)))
			if #problems > 0 then
				error(table.concat(problems, "\n"))
			end
		end)
	end
end)

describe("ClipAudit: the rules catch what they are for", function()
	local fall = ClipLibrary.get("player/OneHandedSword/Fall")
	local boarIdle = ClipLibrary.get("enemy/Boar/Idle")

	-- The same clip with every key's `joint` set to `key` (the whole clip held in that pose).
	local function everyKey(clip: any, joint: string, key: any): any
		local copy = deepCopy(clip)
		for _, entry in copy.keys do
			entry.joints[joint] = deepCopy(key)
		end
		return copy
	end

	-- The same clip with a held copy of the first key at `at` and, one frame later, that pose with
	-- `change` applied: a change the eye sees in one frame.
	local function oneFrameChange(clip: any, at: number, change: (any) -> ()): any
		local copy = deepCopy(clip)
		assert(copy.keys[2].time > at + 2 / 60, "the first key segment is too short for the change")
		local held = deepCopy(copy.keys[1])
		held.time = at
		held.easing = "Linear"
		local changed = deepCopy(held)
		changed.time = at + 1 / 60
		change(changed.joints)
		table.insert(copy.keys, 2, changed)
		table.insert(copy.keys, 2, held)
		return copy
	end

	local function kinds(clip: any): { string }
		return ClipAudit.kindsOf(findingsOf(clip))
	end

	it("the clean clips the checks below start from are clean", function()
		expect(kinds(fall)).toEqual({})
		expect(kinds(boarIdle)).toEqual({})
	end)

	it("a head that turns 60 degrees in one frame pops", function()
		local clip = oneFrameChange(boarIdle, 0.5, function(joints: any)
			joints.Neck = { rot = { 60, 0, 0 } }
		end)
		expect(table.find(kinds(clip), "Pop") ~= nil).toBe(true)
	end)

	it("an arm rolled into the torso overlaps it", function()
		local clip = everyKey(fall, "RightShoulder", { rot = { 0, 0, -70 } })
		local findings = findingsOf(clip)
		expect(table.find(ClipAudit.kindsOf(findings), "Overlap") ~= nil).toBe(true)
		expect(listed(findings, function(kind: string): boolean
			return kind == "Overlap"
		end):find("RightLowerArm into UpperTorso", 1, true) ~= nil).toBe(true)
	end)

	it("a blade turned back into the arm is the weapon in the body", function()
		local clip = everyKey(fall, "RightWrist", { rot = { 180, 0, 0 } })
		expect(table.find(kinds(clip), "Weapon") ~= nil).toBe(true)
	end)

	it("a body shifted half a stud in one frame over planted feet slides them", function()
		local clip = oneFrameChange(boarIdle, 0.5, function(joints: any)
			joints.Root = { pos = { 0.5, 0, 0 }, rot = { 0, 0, 0 } }
		end)
		local found = kinds(clip)
		expect(table.find(found, "Slide") ~= nil).toBe(true)
		expect(table.find(found, "Drift") ~= nil).toBe(true)
	end)

	it("a body lowered into the field sinks its feet", function()
		local clip = everyKey(boarIdle, "Root", { pos = { 0, -0.4, 0 }, rot = { 0, 0, 0 } })
		expect(table.find(kinds(clip), "Sink") ~= nil).toBe(true)
	end)

	it("a basic is chained mashed (one BasicAttackRequest refill after the swing before it) and on its beat", function()
		-- CharacterController.basicAttack starts the next basic as soon as the request refills.
		local World = Harness.load("src/shared/data/world")
		local refill = 1 / World.anticheat.remoteRates.BasicAttackRequest.perSecond
		for id, before in Audit.rigs.PlayerR15.chain do
			local starts = {}
			for _, plan in ClipAudit.plans(ClipLibrary.get(id), ClipLibrary.get) do
				local beforeAt, measuredAt = nil, nil
				for _, play in plan.plays do
					if play.clip.id == before then
						beforeAt = play.at
					elseif play.measured then
						measuredAt = play.at
					end
				end
				if beforeAt ~= nil and measuredAt ~= nil then
					table.insert(starts, measuredAt - beforeAt)
				end
			end
			table.sort(starts)
			expect(#starts).toBe(2)
			expect(math.abs(starts[1] - refill) < 1e-9).toBe(true)
			expect(math.abs(starts[2] - Audit.chainSeconds) < 1e-9).toBe(true)
		end
	end)

	-- A held copy of the pose the clip has at `at` and, one frame later, that pose with `change`
	-- applied; the clip goes on from there to its next key (a fault cut into a real clip anywhere).
	local function oneFrameChangeAt(clip: any, at: number, change: (any) -> ()): any
		local copy = deepCopy(clip)
		local joints = {}
		for name, value in ClipSampler.sample(clip, at) do
			if name ~= ClipSampler.ROOT_KEY then
				joints[name] = deepCopy(value)
			end
		end
		local index = 1
		for i, key in copy.keys do
			if key.time <= at + 1e-9 then
				index = i
			end
		end
		local changed = { time = at + 1 / 60, easing = "Linear", joints = deepCopy(joints) }
		change(changed.joints)
		table.insert(copy.keys, index + 1, { time = at + 2 / 60, easing = "Linear", joints = deepCopy(joints) })
		table.insert(copy.keys, index + 1, changed)
		table.insert(copy.keys, index + 1, { time = at, easing = "SineInOut", joints = deepCopy(joints) })
		ClipSampler.invalidate(copy)
		return copy
	end

	it("a clip on the pending list still fails a fault it did not have: a pop cut into Basic1", function()
		-- Basic1 pops only in the run hand-over (its Run plans); this pop is in the Recovery.
		local id = "player/OneHandedSword/Basic1"
		local clip = oneFrameChangeAt(ClipLibrary.get(id), 0.3, function(joints: any)
			local neck = joints.Neck or { rot = { 0, 0, 0 } }
			local rot = neck.rot or { 0, 0, 0 }
			joints.Neck = { pos = neck.pos, rot = { rot[1], rot[2] + 60, rot[3] } }
		end)
		expect(#unmet(id, findingsOf(clip)) > 0).toBe(true)
	end)

	it("a clip on the pending list still fails a pending fault that grew: the boar's walk slid further", function()
		local id = "enemy/Boar/Walk"
		local clip = oneFrameChangeAt(ClipLibrary.get(id), 0.3, function(joints: any)
			local rootKey = joints.Root or { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }
			local pos = rootKey.pos or { 0, 0, 0 }
			joints.Root = { pos = { pos[1] + 0.5, pos[2], pos[3] }, rot = rootKey.rot }
		end)
		expect(#unmet(id, findingsOf(clip)) > 0).toBe(true)
	end)

	-- The same attack with every key inside its first Anticipation beat (after its first key) set
	-- to `joints`: the wind-up held in that pose.
	local function anticipationHeld(clip: any, joints: any): any
		local copy = deepCopy(clip)
		local beat = copy.beats.Anticipation
		for _, key in copy.keys do
			if key.time > 0 and key.time >= beat.start - 1e-9 and key.time <= beat.finish + 1e-9 then
				for name, value in joints do
					key.joints[name] = deepCopy(value)
				end
			end
		end
		return copy
	end
	local function hasFinding(findings: { any }, kind: string, what: string, plan: string): boolean
		for _, finding in findings do
			if finding.kind == kind and finding.what == what and finding.plan == plan then
				return true
			end
		end
		return false
	end

	it("a wind-up held behind the head is hidden from the gameplay camera and does not travel", function()
		local clip = anticipationHeld(ClipLibrary.get("player/OneHandedSword/Horizontal"), {
			RightShoulder = { rot = { 170, 0, 20 } },
			RightElbow = { rot = { 120, 0, 0 } },
			RightWrist = { rot = { 0, 0, 0 } },
			Weapon = { rot = { 0, 0, 0 } },
		})
		local findings = findingsOf(clip)
		expect(hasFinding(findings, "Anticipation", "strike 1 hidden", "Lab")).toBe(true)
		expect(hasFinding(findings, "Anticipation", "strike 1 travel", "Lab")).toBe(true)
	end)

	it("a wind-up held low in front of the body runs along the cut", function()
		local clip = anticipationHeld(ClipLibrary.get("player/OneHandedSword/Basic1"), {
			RightShoulder = { rot = { 40, 0, -30 } },
			RightElbow = { rot = { 60, 0, 0 } },
			RightWrist = { rot = { 0, 0, 0 } },
			Weapon = { rot = { -90, 0, 0 } },
		})
		expect(hasFinding(findingsOf(clip), "Anticipation", "strike 1 direction", "Lab")).toBe(true)
	end)

	it("a wind-up that jerks the blade as fast as the snap is too fast", function()
		local clip = oneFrameChangeAt(ClipLibrary.get("player/OneHandedSword/Horizontal"), 0.29, function(joints: any)
			local shoulder = joints.RightShoulder or { rot = { 0, 0, 0 } }
			local rot = shoulder.rot or { 0, 0, 0 }
			joints.RightShoulder = { pos = shoulder.pos, rot = { rot[1] + 90, rot[2], rot[3] } }
		end)
		expect(hasFinding(findingsOf(clip), "Anticipation", "strike 1 speed", "Lab")).toBe(true)
	end)

	it("a Recovery held with the blade across the face hides it", function()
		local copy = deepCopy(ClipLibrary.get("player/OneHandedSword/Horizontal"))
		for _, key in copy.keys do
			if key.time >= copy.beats.Recovery.start - 1e-9 then
				key.joints.RightShoulder = { rot = { 90, 0, -45 } }
				key.joints.RightElbow = { rot = { 45, 0, 0 } }
				key.joints.RightWrist = { rot = { 0, 0, 0 } }
				key.joints.Weapon = { rot = { 90, 0, 0 } }
			end
		end
		expect(hasFinding(findingsOf(copy), "Recovery", "blade across the face", "Lab")).toBe(true)
	end)

	it("a clip that ends far from the stance and blends back in a frame or two snaps back", function()
		local copy = deepCopy(ClipLibrary.get("player/OneHandedSword/DodgeBack"))
		copy.blendOut = 0.02
		local last = copy.keys[#copy.keys]
		last.joints.RightShoulder = { rot = { 0, 0, 90 } }
		last.joints.LeftShoulder = { rot = { 0, 0, -90 } }
		local snapsBack = false
		for _, finding in findingsOf(copy) do
			if finding.kind == "Return" and finding.what ~= "tip" and finding.plan == "Stand@0" then
				snapsBack = true
			end
		end
		expect(snapsBack).toBe(true)
	end)

	it("an overlap only the blend back has is the clip's; one the stance it settles into has is not", function()
		local clip = ClipLibrary.get("player/OneHandedSword/DodgeBack")
		local body = bodyOf(clip.rig)
		local plan = nil
		for _, candidate in ClipAudit.plans(clip, ClipLibrary.get) do
			if candidate.label == "Stand@0" then
				plan = candidate
			end
		end
		assert(plan ~= nil, "DodgeBack has no Stand@0 plan")
		local hz = Audit.sampleHz[1]
		local function overlapsArm(intoSettle: boolean): boolean
			local frames = ClipAudit.trace(body, plan, hz)
			local pushed = 0
			for _, frame in frames do
				-- The forearm pushed into the chest while the clip blends out (and, with
				-- intoSettle, in the stance it settles into as well).
				if (frame.ended and frame.clipTime ~= nil) or (intoSettle and frame.clipTime == nil) then
					frame.solved.RightLowerArm = frame.solved.UpperTorso
					pushed += 1
				end
			end
			assert(pushed > 0, "the trace has no blend-out")
			for _, overlap in ClipAudit.measure(body, clip, plan, frames, hz).overlaps do
				local pair = { overlap.a, overlap.b }
				if table.find(pair, "RightLowerArm") and table.find(pair, "UpperTorso") then
					return true
				end
			end
			return false
		end
		expect(overlapsArm(false)).toBe(true)
		expect(overlapsArm(true)).toBe(false)
	end)

	-- The rules on a report: a strike's anticipation, the return and the Recovery.
	local horizontal = ClipLibrary.get("player/OneHandedSword/Horizontal")
	local function report(fill: (any) -> ()): any
		local base = {
			clipId = horizontal.id,
			label = "Lab",
			hz = 60,
			pops = {},
			overlaps = {},
			weapon = {},
			slides = {},
			drifts = {},
			jumps = {},
			sink = {},
			strikes = {},
		}
		fill(base)
		return base
	end
	local function strike(index: number, values: any): any
		local entry = {
			index = index,
			snap = { start = 0.35, finish = 0.4 },
			anticipation = { start = 0.25, finish = 0.35 },
			cosine = -0.9,
			firstCosine = -0.9,
			travel = 3,
			anticipationPeak = 0.5,
			snapPeak = 5,
			snapPeakAt = 0.36,
			hidden = 0,
		}
		for key, value in values do
			entry[key] = value
		end
		return entry
	end
	local function whats(found: { any }): { string }
		local list = {}
		for _, finding in found do
			table.insert(list, finding.kind .. " " .. finding.what)
		end
		table.sort(list)
		return list
	end

	it("a first strike's anticipation fails hidden, along the cut, short or as fast as the snap", function()
		local good = report(function(r: any)
			r.strikes = { strike(1, {}) }
		end)
		expect(ClipAudit.findings(horizontal, good)).toEqual({})
		local bad = report(function(r: any)
			r.strikes = {
				strike(1, {
					hidden = Audit.anticipation.maxHiddenShare + 0.1,
					cosine = Audit.anticipation.maxCosine + 0.1,
					travel = Audit.anticipation.minTravel / 2,
					anticipationPeak = 5 * (Audit.anticipation.maxSpeedShare + 0.1),
				}),
			}
		end)
		expect(whats(ClipAudit.findings(horizontal, bad))).toEqual({
			"Anticipation strike 1 direction",
			"Anticipation strike 1 hidden",
			"Anticipation strike 1 speed",
			"Anticipation strike 1 travel",
		})
	end)

	it("a later strike's lead-in is reported, not judged (one anticipation an attack)", function()
		local later = report(function(r: any)
			r.strikes = { strike(1, {}), strike(2, { hidden = 1, cosine = 1, travel = 0 }) }
		end)
		expect(ClipAudit.findings(horizontal, later)).toEqual({})
	end)

	it("the return and the Recovery fail past their bounds", function()
		local bad = report(function(r: any)
			r.returnTip = Audit.returnStuds + 1
			r.returnPeak = { part = "RightHand", degrees = Audit.popDegrees + 5, time = 1 }
			r.recoveryFaceShare = Audit.recoveryFaceShare + 0.1
		end)
		expect(whats(ClipAudit.findings(horizontal, bad))).toEqual({
			"Recovery blade across the face",
			"Return RightHand",
			"Return tip",
		})
		local good = report(function(r: any)
			r.returnTip = Audit.returnStuds - 0.1
			r.returnPeak = { part = "RightHand", degrees = Audit.popDegrees - 1, time = 1 }
			r.recoveryFaceShare = Audit.recoveryFaceShare
		end)
		expect(ClipAudit.findings(horizontal, good)).toEqual({})
	end)

	-- What the owner's PC review of cebade4 saw as a problem (its per-clip-frame logs at 0.25x;
	-- where it named a problem without a number, the audit's own measure of that clip on
	-- cebade4): the bounds must fail every one of them, so none may be loosened past what the eye
	-- already caught.
	it("the bounds fail every problem the owner's PC review saw", function()
		local seen = report(function(r: any)
			-- Horizontal's right upper arm 26 degrees in one frame at f2.
			r.pops = { { part = "RightUpperArm", degrees = 26, time = 2 / 60, clipTime = 2 / 60 } }
			-- Basic1's right upper arm 0.15 into the head.
			r.overlaps = { { a = "RightUpperArm", b = "Head", depth = 0.15, from = 0.15, to = 0.2, at = 0.17 } }
			-- the boar's back legs sliding 0.13 a frame through the rush.
			r.slides = { { foot = "BackLeftLeg", studs = 0.13, time = 1, clipTime = 1 } }
			r.strikes = {
				strike(1, {
					cosine = -0.37, -- Horizontal's weak pull
					travel = 0.92, -- RisingArc's weak pull (the audit on cebade4)
					anticipationPeak = 0.52 * 5, -- Basic3's, read as part of the swing (the audit on cebade4)
					hidden = 1, -- Horizontal's tip hidden through the whole beat
				}),
			}
			r.returnTip = 2.7 -- Basic1's blade 2.7 studs from where it started
			r.recoveryFaceShare = 0.97 -- RisingArc across the face (the audit on cebade4)
		end)
		expect(whats(ClipAudit.findings(horizontal, seen))).toEqual({
			"Anticipation strike 1 direction",
			"Anticipation strike 1 hidden",
			"Anticipation strike 1 speed",
			"Anticipation strike 1 travel",
			"Overlap RightUpperArm into Head",
			"Pop RightUpperArm",
			"Recovery blade across the face",
			"Return tip",
			"Slide BackLeftLeg",
		})
	end)
end)
