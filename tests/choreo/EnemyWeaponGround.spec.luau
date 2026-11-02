--!strict
--[[
	An enemy's weapon stays on top of the field and never pops (section 10: "Break is a kneel with
	the weapon dropping"; section 21 gate line 4: no popping limb in any clip; D-542). Every
	audited enemy clip whose rig carries a weapon (dev.luau review.audit.rigs[rig].weapon) is played
	the way the game plays it (ClipAudit.plans) through the real Mixer on RigBuilder's rig, at every
	review.audit.sampleHz, and per drawn frame:
	- Sink: once the clip's blend in is done, no corner of a weapon part goes deeper below the field
	  than review.audit.footSinkStuds (the feet's own bar: a dropped weapon lies on the ground or
	  stays gripped and planted, never sunk). What the clip blends in over is the hand-over: the
	  stagger starts on the chop's bite.
	- Turn: while the clip is drawn, no weapon part turns more than review.audit.popDegrees in one
	  60 Hz frame in the root's frame (ClipAudit's pop list holds the body only, so a weapon that
	  flips under the floor in one frame was never judged). The Lab's cut in is not judged.
	Attacks are left out: a strike may bite the ground on purpose (enemy/Kobold/Overhead: "the axe
	bites the ground", then "is stuck low; two tugs free it"), and ClipAudit judges an attack's
	weapon by its tip. The Kobold's Break used to sink its axe 1.75 under the field from 0.40 to
	2.37 s, flipping it 67 degrees on the frames in and out.
]]

local Dev = Harness.load("src/shared/data/dev")
local ChoreoData = Harness.load("src/shared/data/choreo")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local RigBuilder = Harness.load("src/server/world/RigBuilder")

local Audit = Dev.review.audit

local function lowest(solved: any, part: string, size: Vector3): number
	local cf = solved[part]
	local half = size * 0.5
	local low = math.huge
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				low = math.min(low, (cf * Vector3.new(x * half.X, y * half.Y, z * half.Z)).Y)
			end
		end
	end
	return low
end

local function turn(a: CFrame, b: CFrame): number
	local _, angle = a:ToObjectSpace(b):ToAxisAngle()
	return math.deg(math.abs(angle))
end

-- The audited enemy clips, attacks aside, on a rig that carries a weapon.
local cases: { string } = {}
for _, id in Audit.clips do
	local clip = ClipLibrary.get(id)
	local rigConfig = Audit.rigs[clip.rig]
	local armed = rigConfig ~= nil and rigConfig.weapon ~= nil and #rigConfig.weapon > 0
	if string.sub(id, 1, 6) == "enemy/" and armed and not clip.attack then
		table.insert(cases, id)
	end
end

local bodies: { [string]: any } = {}
local function bodyOf(rig: string): any
	if bodies[rig] == nil then
		bodies[rig] = ClipAudit.standingBody(RigBuilder.build(rig), rig)
	end
	return bodies[rig]
end

-- The worst a clip's weapon does over every plan and sample rate, with where.
type Worst = { value: number, plan: string, clipTime: number }
local function measure(clip: any): { [string]: Worst }
	local body = bodyOf(clip.rig)
	local blendIn = clip.blendIn or ChoreoData.blendIn
	local sink: Worst = { value = 0, plan = "", clipTime = 0 }
	local fastest: Worst = { value = 0, plan = "", clipTime = 0 }
	for _, plan in ClipAudit.plans(clip, ClipLibrary.get) do
		for _, hz in Audit.sampleHz do
			local previous: { [string]: CFrame } = {}
			for _, frame in ClipAudit.trace(body, plan, hz) do
				local clipTime = frame.clipTime
				for _, part in body.weaponParts do
					if clipTime == nil then
						previous[part] = nil
						continue
					end
					local depth = body.fieldTop - lowest(frame.solved, part, body.sizes[part])
					if clipTime >= blendIn - 1e-6 and depth > sink.value then
						sink = { value = depth, plan = ("%s %d Hz"):format(plan.label, hz), clipTime = clipTime }
					end
					local here = frame.root:ToObjectSpace(frame.solved[part])
					local before = previous[part]
					if hz == 60 and before ~= nil then
						local degrees = turn(before, here)
						if degrees > fastest.value then
							fastest = { value = degrees, plan = plan.label, clipTime = clipTime }
						end
					end
					previous[part] = here
				end
			end
		end
	end
	return { Sink = sink, Turn = fastest }
end

-- The bars: studs under the field, degrees in one 60 Hz frame.
local BARS: { [string]: number } = { Sink = Audit.footSinkStuds, Turn = Audit.popDegrees }

-- What the enemy clips do not meet yet, by clip and kind: the most each is past its bar (rounded
-- up to the hundredth), measured when this spec came in (D-542). A pending clip fails a kind it
-- does not list, a listed kind further past its bar, and a listed kind it no longer has (take it
-- off). The fix stage takes entries off; an entry never grows.
local PENDING: { [string]: { [string]: number } } = {
	-- The additive flinches' four keys (0, 0.05, 0.16, 0.3): FlinchBack pitches the body 12 deg
	-- forward and the axe head 8 down on the hit, 0.389 under the field at 0.05 s; both swing the
	-- axe back 21.9 and 22.2 deg in the frame after it.
	["enemy/Kobold/FlinchBack"] = { Sink = 0.29, Turn = 1.9 },
	["enemy/Kobold/FlinchFront"] = { Turn = 2.17 },
	-- The knock-back throws the axe up and wide in four frames (13.5 deg a frame of its own on top
	-- of the arm's swing): 22.6 deg in the frame the blend in ends.
	["enemy/Kobold/Stagger"] = { Turn = 2.6 },
}

describe("EnemyWeaponGround: an enemy's weapon lies on the field, never under it (D-542)", function()
	it("finds the enemy clips with a weapon", function()
		local ids = {}
		for _, id in cases do
			ids[id] = true
		end
		expect(ids["enemy/Kobold/Break"]).toBe(true)
		expect(ids["enemy/Kobold/Walk"]).toBe(true)
		expect(ids["enemy/Kobold/Overhead"]).toBe(nil)
	end)

	for _, id in cases do
		it(("%s keeps its weapon over the field and turning under popDegrees"):format(id), function()
			local worst = measure(ClipLibrary.get(id))
			local pending = PENDING[id] or {}
			local problems = {}
			for kind, bar in BARS do
				local found = worst[kind]
				local excess = found.value - bar
				local allowed = pending[kind]
				if excess > 0 and (allowed == nil or excess > allowed + 1e-9) then
					table.insert(
						problems,
						("%s %.3f (bar %.2f, pending %s) at %.3f s, %s"):format(
							kind,
							found.value,
							bar,
							if allowed == nil then "none" else ("+%.2f"):format(allowed),
							found.clipTime,
							found.plan
						)
					)
				elseif excess <= 0 and allowed ~= nil then
					table.insert(problems, ("%s %.3f meets its bar now: take it off PENDING"):format(kind, found.value))
				end
			end
			if #problems > 0 then
				error(id .. ": " .. table.concat(problems, "; "))
			end
		end)
	end

	it("catches a weapon keyed under the field and a weapon flip", function()
		-- The real Break with its axe tipped back to -100 under the field from 0.40 s (the clip
		-- before D-542) must fail both bars.
		local clip = ClipLibrary.get("enemy/Kobold/Break")
		local broken = table.clone(clip)
		broken.keys = {}
		for _, key in clip.keys do
			local copy = table.clone(key)
			copy.joints = table.clone(key.joints)
			if key.time >= 0.4 and key.time <= 2.37 then
				copy.joints.Weapon = { rot = { -100, 0, 0 } }
			end
			table.insert(broken.keys, copy)
		end
		local worst = measure(broken)
		expect(worst.Sink.value > Audit.footSinkStuds).toBe(true)
		expect(worst.Turn.value > Audit.popDegrees).toBe(true)
	end)
end)
