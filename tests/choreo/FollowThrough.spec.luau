--!strict
--[[
	The follow-through (GAME_SPEC section 10 beat 5, D-484): a cut goes through the target and
	out past it. After the freeze the blade of seven player attacks stayed inside the kobold for up
	to 26 frames (the first basic 0.48 deep 12 frames past the exit, Horizontal 0.44 for 26, Sharp
	Nail's third thrust 0.46 for 23), and the hand of Horizontal stood in its torso for 58: in
	Studio the sword read as stuck in the body, not as a cut through it.

	Every Art the weapon has a clip for and every basic swing is played the way the audit stands it
	(ClipAudit.plans, Stand at each review.audit.idlePhases phase: through the real Mixer over the
	drawn idle and the breathing, on the hit matrix's player), with the stand-off and keep-out the
	game carries it with (ContactPredictor.standOff with keepOut and the step, as FreezeStill's
	reach does), at the kobold where a fight with it stands (3.5 and 4.8, FreezeStill's reach
	placements), and read every 60 Hz frame against the kobold's hurtboxes:

	- Exit: within review.audit.followThrough.exitFrames frames after a strike's authored hold,
	  the blade is no deeper in the body than that strike's own snap, key and hold took it (it
	  carries on through, it does not sink in);
	- Late: from then until the next strike's snap (or through the blend-out and the settle after
	  the last), the blade is at most followThrough.touchStuds in the body;
	- Approach: before the first snap the blade is at most touchStuds in the body;
	- Limb: outside the cuts (snap to the end of the hold), no hand or arm (keepOut.limbs) is more
	  than touchStuds deeper in a body part than it stood at the start.

	PENDING (below) is what a clip does not meet yet, by clip and rule, with how far past its bound
	it is (rounded up to the hundredth of a stud): a pending clip must fail exactly that (a new
	rule or a worse excess fails, and so does a listed rule it no longer has: take it off). The
	bounds are data (dev.luau review.audit.followThrough, with a validator rule) and never move to
	make a clip pass.

	The second half checks the rules catch what they are for: a real swing with its follow-through
	held at the key, its anticipation pushed into the body and its hand pushed into the torso
	after the cut; and the measure sees each cut it judges reach the body at the staging.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Arts = Harness.load("src/shared/data/arts")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local AimLogic = Harness.load("src/client/controllers/AimLogic")

local Audit = Dev.review.audit
local STAND_OFF = Combat.contact.standOff
local KEEP_OUT = STAND_OFF.keepOut
local HOLD_FALLBACK = Combat.startPoseTime + Combat.activationHold
-- The rule counts 60 Hz frames (section 10's frames).
local FRAME_HZ = 60
-- Where a fight with the kobold stands (FreezeStill's reach, D-424): 3.5 as the capture's Art
-- shots stage it, 4.8 where the Brute starts its overhead.
local PLACEMENTS = { 3.5, 4.8 }
local STAGED = 3.5
-- Points along the blade (guard to tip) its depth is read at.
local BLADE_POINTS = 64
local EPSILON = 1e-6
local RULES = { "Exit", "Late", "Approach", "Limb" }

-- What each swing does not meet yet: by clip name and rule, the most it is past its bound (studs,
-- rounded up to the hundredth). Before the re-key (48a846f, the Stand plans, both placements) all
-- seven swings failed, past their bounds by: Basic1 Late 0.379; Basic2 Approach 0.209;
-- Basic3 Exit 0.209 and Late 0.340; Horizontal Exit 0.174, Late 0.342 and Limb 0.264; Vertical
-- Exit 0.176 and Late 0.329; SharpNail Exit 0.258 and Late 0.361; RisingArc Exit 0.149 and Late
-- 0.148. Left after it, with the kobold's rest pose on the field (rigs.luau hipHeight 2.4, D-483;
-- it stood 0.2 into it when these were first measured, D-493):
-- - Basic2 Approach: the wind-up runs into the cock at 0.1 (the hit window's open key, the
--   strike's own start), which is taken past the kobold's near side when it stands 3.5 off (0.153
--   deep at 0.083), and its middle key brushes the near leg at 4.8 (0.170 deep at 0.067); a cock
--   clear of it moves the hit path (D-492). With the kobold on the field that middle key dipped
--   the blade 0.341 into the leg (0.25 past), so it rolls the sword wrist 3.5 degrees less (D-493).
-- RisingArc's Exit (0.002 past its own cut at 60 Hz) went with the kobold on the field.
-- An entry never grows.
local PENDING: { [string]: { [string]: number } } = {
	Basic2 = { Approach = 0.08 },
}

local root = Harness.repoRoot()

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

local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
local avatar, field = HitMatrix.standing(Harness)
local body = ClipAudit.body(avatar.model, "PlayerR15", avatar.base, ClipAudit.topOf(field.CFrame, field.Size))
local trailStart = avatar.model:FindFirstChild("TrailStart", true) :: any
local trailEnd = avatar.model:FindFirstChild("TrailEnd", true) :: any

type Swing = { name: string, clip: any, art: any?, from: number }

-- Every Art the weapon has a clip for, from its hold pose, and the basic swings.
local SWINGS: { Swing } = {}
for _, art in Arts.list("OneHandedSword") do
	local name = art.clip:match("[^/]+$")
	if fs.isFile(root .. "/src/shared/clips/player/OneHandedSword/" .. name .. ".luau") then
		local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
		table.insert(
			SWINGS,
			{ name = name, clip = clip, art = art, from = ActionLogic.holdClipTime(clip, HOLD_FALLBACK) }
		)
	end
end
for index = 1, Combat.basicChainLength do
	local name = "Basic" .. index
	table.insert(
		SWINGS,
		{ name = name, clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name), art = nil, from = 0 }
	)
end

local function setupOf(id: string): any
	for _, setup in Dev.hitMatrix.setups do
		if setup.id == id then
			return setup
		end
	end
	error("no hit matrix setup " .. id)
end

-- The kobold in its rest pose `distance` ahead where the hit matrix stands it, with its blocker
-- (the stand-off reads it), and its hurtboxes.
local function place(distance: number): (any, { any })
	local setup = setupOf("Kobold")
	local def = Enemies.byId(setup.enemy)
	local model = RigBuilder.build(def.skin)
	local height =
		PlaygroundLayout.rootHeight(Rigs[def.skin].hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local bearing = math.rad(setup.bearing or 0)
	local frame = avatar.base
		* CFrame.new(math.sin(bearing) * distance, height - avatar.rootHeight, -math.cos(bearing) * distance)
		* CFrame.Angles(0, math.pi - bearing + math.rad(setup.yaw), 0)
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	assert(RigBuilder.addBlocker(model) ~= nil, "no blocker for the kobold")
	local hurt = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and BladeContact.hurtbox(part) then
			table.insert(hurt, part)
		end
	end
	assert(#hurt > 0, "the kobold has no hurtboxes")
	return model, hurt
end

-- How deep a point stands inside a box (its least distance to a face), 0 or less outside.
local function pointDepth(point: Vector3, frame: CFrame, size: Vector3): number
	local at = frame:PointToObjectSpace(point)
	return math.min(size.X / 2 - math.abs(at.X), size.Y / 2 - math.abs(at.Y), size.Z / 2 - math.abs(at.Z))
end

type Strike = { key: number, snap: number, holdEnd: number }

-- Each strike: its key (the hit-stop's), where its snap starts and where its authored hold ends.
local function strikesOf(clip: any): { Strike }
	local list: { Strike } = {}
	for _, window in ClipSampler.hitWindows(clip) do
		local key = ContactPredictor.strikeKey(clip, window)
		local snap, holdEnd = window.open, key
		for index = 2, #clip.keys do
			if math.abs(clip.keys[index].time - key) < EPSILON then
				if ClipSampler.isStrikeSnap(clip, index) then
					snap = clip.keys[index - 1].time
				end
				local after = clip.keys[index + 1]
				if after ~= nil and after.easing == "Hold" then
					holdEnd = after.time
				end
			end
		end
		table.insert(list, { key = key, snap = math.min(snap, key), holdEnd = holdEnd })
	end
	return list
end

type Row = {
	clipTime: number?, -- nil once the clip is gone
	blade: number, -- the blade's deepest point in any hurtbox
	where: string,
	limbs: { [string]: number }, -- "<limb> in <part>": how deep
}

local function planLabel(phase: number): string
	return ("Stand@%g"):format(phase)
end

-- The swing's frames from its start pose on, as the audit's Stand plan `label` plays it, carried
-- by the stand-off at the kobold `distance` ahead.
local function trace(swing: Swing, distance: number, label: string): { Row }
	local model, hurt = place(distance)
	local plan = ContactPredictor.standOff(
		avatar.model,
		swing.clip,
		swing.from,
		avatar.base,
		model,
		nil,
		{ keepOut = true, step = swing.art ~= nil }
	)
	local auditPlan = nil
	for _, each in ClipAudit.plans(swing.clip, ClipLibrary.get) do
		if each.label == label then
			auditPlan = each
		end
	end
	assert(auditPlan ~= nil, "the audit has no plan " .. label)
	local rows: { Row } = {}
	local started = false
	for _, frame in ClipAudit.trace(body, auditPlan, FRAME_HZ) do
		local clipTime = frame.clipTime
		if clipTime ~= nil then
			started = true
		end
		if not started or (clipTime ~= nil and clipTime < swing.from - 1e-9) then
			continue
		end
		local t = if clipTime ~= nil then clipTime else swing.clip.duration
		local shift = Vector3.zero
		if plan ~= nil then
			local back = AimLogic.standOffAt(plan.distance, plan.from, plan.to, t, STAND_OFF.easing)
			if plan.keep ~= nil then
				back += plan.keep(t)
			end
			shift = plan.away * back
			if plan.side ~= nil and plan.keepSide ~= nil then
				shift += plan.side * plan.keepSide(t)
			end
		end
		local a = (frame.solved[trailStart.Parent.Name] * trailStart.CFrame).Position + shift
		local b = (frame.solved[trailEnd.Parent.Name] * trailEnd.CFrame).Position + shift
		local blade, where = -math.huge, ""
		for _, part in hurt do
			for k = 0, BLADE_POINTS do
				local each = pointDepth(a:Lerp(b, k / BLADE_POINTS), part.CFrame, part.Size)
				if each > blade then
					blade, where = each, part.Name
				end
			end
		end
		local limbs: { [string]: number } = {}
		for _, name in KEEP_OUT.limbs do
			local limb = avatar.model:FindFirstChild(name) :: any
			local cf = frame.solved[name]
			if limb ~= nil and cf ~= nil then
				for _, part in hurt do
					limbs[name .. " in " .. part.Name] =
						ClipAudit.overlapDepth(cf + shift, limb.Size, part.CFrame, part.Size)
				end
			end
		end
		table.insert(rows, {
			clipTime = if frame.ended then nil else clipTime,
			blade = blade,
			where = where,
			limbs = limbs,
		})
	end
	model:Destroy()
	return rows
end

type Finding = { excess: number, text: string }

-- The rules on one trace: the worst finding of each rule it breaks, and how deep each strike's cut
-- went (its snap, key and hold).
local function judge(swing: Swing, rows: { Row }, where: string): ({ [string]: Finding }, { number })
	local strikes = strikesOf(swing.clip)
	local exitSeconds = Audit.followThrough.exitFrames / FRAME_HZ
	local touch = Audit.followThrough.touchStuds
	local cut: { number } = {}
	for index, strike in strikes do
		local deepest = -math.huge
		for _, row in rows do
			local t = row.clipTime
			if t ~= nil and t >= strike.snap - EPSILON and t <= strike.holdEnd + EPSILON then
				deepest = math.max(deepest, row.blade)
			end
		end
		cut[index] = deepest
	end
	local found: { [string]: Finding } = {}
	local function note(rule: string, excess: number, text: string)
		if excess > 0 and (found[rule] == nil or excess > found[rule].excess) then
			found[rule] = { excess = excess, text = ("%s %s at %s: %s"):format(swing.name, rule, where, text) }
		end
	end
	local start = rows[1]
	for _, row in rows do
		local t = row.clipTime
		local stretch = 0
		for index, strike in strikes do
			if t == nil or t >= strike.snap - EPSILON then
				stretch = index
			end
		end
		local inCut = t ~= nil and stretch > 0 and t <= strikes[stretch].holdEnd + EPSILON
		local at = if t ~= nil then ("%.3f"):format(t) else "the blend-out"
		if stretch == 0 then
			note(
				"Approach",
				row.blade - touch,
				("the blade %.3f in the %s at %s before the first snap (touch %.2f)"):format(
					row.blade,
					row.where,
					at,
					touch
				)
			)
		elseif not inCut then
			local strike = strikes[stretch]
			local since = if t ~= nil then t - strike.holdEnd else math.huge
			if since <= exitSeconds + EPSILON then
				-- a strike that never reached the body may still brush it
				local allowed = math.max(cut[stretch], touch)
				note(
					"Exit",
					row.blade - allowed,
					("strike %d's blade %.3f in the %s at %s, deeper than its cut %.3f"):format(
						stretch,
						row.blade,
						row.where,
						at,
						allowed
					)
				)
			else
				note(
					"Late",
					row.blade - touch,
					("strike %d's blade still %.3f in the %s at %s, %d frames past its hold (touch %.2f)"):format(
						stretch,
						row.blade,
						row.where,
						at,
						Audit.followThrough.exitFrames,
						touch
					)
				)
			end
		end
		if not inCut then
			for name, each in row.limbs do
				local started = math.max(start.limbs[name] or 0, 0)
				note(
					"Limb",
					each - started - touch,
					("%s %.3f deep at %s (%.3f at the start, touch %.2f)"):format(name, each, at, started, touch)
				)
			end
		end
	end
	return found, cut
end

-- The worst finding of each rule over every placement and Stand plan.
local function findingsOf(swing: Swing): { [string]: Finding }
	local worst: { [string]: Finding } = {}
	for _, distance in PLACEMENTS do
		for _, phase in Audit.idlePhases do
			local label = planLabel(phase)
			local found = judge(swing, trace(swing, distance, label), ("%.1f %s"):format(distance, label))
			for rule, finding in found do
				if worst[rule] == nil or finding.excess > worst[rule].excess then
					worst[rule] = finding
				end
			end
		end
	end
	return worst
end

local function roundUp(value: number): number
	return math.ceil(value * 100 - 1e-6) / 100
end

-- What `found` breaks against what `pending` lists: lines for a rule it is not listed for, one past
-- its listed excess, and a listed rule it no longer breaks.
local function against(found: { [string]: Finding }, pending: { [string]: number }): { string }
	local lines = {}
	for _, rule in RULES do
		local finding = found[rule]
		local listed = pending[rule]
		if finding ~= nil and listed == nil then
			table.insert(lines, ("  %s (%.3f past its bound)"):format(finding.text, finding.excess))
		elseif finding ~= nil and listed ~= nil and roundUp(finding.excess) > listed + 1e-9 then
			table.insert(
				lines,
				("  %s (%.2f past its bound, pending lists %.2f)"):format(finding.text, roundUp(finding.excess), listed)
			)
		elseif finding == nil and listed ~= nil then
			table.insert(lines, ("  %s no longer breaks %s: take it off PENDING"):format("the swing", rule))
		end
	end
	return lines
end

describe("a cut goes through the body and out past it (section 10 beat 5, D-484)", function()
	it("names only swings it plays and rules it has in PENDING", function()
		local names: { [string]: boolean } = {}
		for _, swing in SWINGS do
			names[swing.name] = true
		end
		local rules: { [string]: boolean } = {}
		for _, rule in RULES do
			rules[rule] = true
		end
		for name, listed in PENDING do
			expect(names[name]).toBe(true)
			for rule, excess in listed do
				expect(rules[rule]).toBe(true)
				expect(excess > 0).toBe(true)
			end
		end
	end)

	for _, swing in SWINGS do
		it(
			("%s: the blade leaves the kobold within %d frames of each hold, and no hand or arm stays in it"):format(
				swing.name,
				Audit.followThrough.exitFrames
			),
			function()
				local lines = against(findingsOf(swing), PENDING[swing.name] or {})
				if #lines > 0 then
					error(("%s:\n%s"):format(swing.name, table.concat(lines, "\n")))
				end
			end
		)
	end
end)

describe("the follow-through rules catch what they are for", function()
	local function find(name: string): Swing
		for _, swing in SWINGS do
			if swing.name == name then
				return swing
			end
		end
		error("no swing " .. name)
	end
	-- `swing` with every key in (from, to] posed as the key at `pose` (the same joints and root).
	local function posedAs(swing: Swing, pose: number, from: number, to: number): Swing
		local clip = table.clone(swing.clip)
		clip.keys = table.clone(swing.clip.keys)
		local source = nil
		for _, key in clip.keys do
			if math.abs(key.time - pose) < EPSILON then
				source = key
			end
		end
		assert(source ~= nil, "no key at " .. pose)
		for index, key in clip.keys do
			if key.time > from + EPSILON and key.time <= to + EPSILON then
				local copy = table.clone(key)
				copy.joints = source.joints
				clip.keys[index] = copy
			end
		end
		return { name = swing.name, clip = clip, art = swing.art, from = swing.from }
	end
	local function staged(swing: Swing): { [string]: Finding }
		return (judge(swing, trace(swing, STAGED, planLabel(Audit.idlePhases[1])), "the staging"))
	end

	it("sees each swing's cut reach the body at the staging (the rule is not vacuous)", function()
		local lines = {}
		for _, swing in SWINGS do
			local _, cut = judge(swing, trace(swing, STAGED, planLabel(Audit.idlePhases[1])), "the staging")
			local deepest = -math.huge
			for _, each in cut do
				deepest = math.max(deepest, each)
			end
			if not (deepest > 0) then
				table.insert(lines, ("  %s: deepest %.3f"):format(swing.name, deepest))
			end
		end
		if #lines > 0 then
			error("swings whose cuts never reach the kobold at the staging:\n" .. table.concat(lines, "\n"))
		end
	end)

	-- Basic3's: with the kobold on the field (D-483) Basic1's held cut is 0.283 deep, 0.18 past
	-- touch, under this check's 0.2; Basic3's is 0.433 (D-493).
	it("fails a follow-through held at the key (the blade left in the body)", function()
		local swing = find("Basic3")
		local strike = strikesOf(swing.clip)[1]
		local held = posedAs(swing, strike.key, strike.holdEnd, swing.clip.duration)
		local found = staged(held)
		expect(found.Late ~= nil).toBe(true)
		expect((found.Late :: Finding).excess > 0.2).toBe(true)
	end)

	it("fails an anticipation that starts in the body", function()
		local swing = find("Vertical")
		local strike = strikesOf(swing.clip)[1]
		local pushed = posedAs(swing, strike.key, -1, strike.snap - EPSILON)
		local found = staged(pushed)
		expect(found.Approach ~= nil).toBe(true)
	end)

	it("fails a hand pushed into the body after the cut", function()
		local swing = find("Basic1")
		local strike = strikesOf(swing.clip)[1]
		-- the key's pose again past the exit, carried four studs nearer the kobold. The keep-out
		-- holds the hands and arms out as well as the torsos and head (D-501), up to
		-- keepOut.maxStuds at its speed cap, so a two-stud push is taken back whole (no Limb
		-- finding) and three leaves 0.24; four is past what it can take back (Limb 1.02).
		local held = posedAs(swing, strike.key, strike.holdEnd, swing.clip.duration)
		local clip = table.clone(held.clip)
		local keys = table.clone(clip.keys)
		for index, key in keys do
			if key.time > strike.holdEnd + EPSILON then
				local copy = table.clone(key)
				local joints = table.clone(copy.joints)
				local rootJoint = table.clone(joints.Root)
				local pos = rootJoint.pos or { 0, 0, 0 }
				rootJoint.pos = { pos[1], pos[2], pos[3] - 4 }
				joints.Root = rootJoint
				copy.joints = joints
				keys[index] = copy
			end
		end
		clip.keys = keys
		local found = staged({ name = held.name, clip = clip, art = held.art, from = held.from })
		expect(found.Limb ~= nil).toBe(true)
		expect((found.Limb :: Finding).excess > 0.5).toBe(true)
	end)
end)
