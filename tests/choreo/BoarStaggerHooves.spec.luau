--!strict
--[[
	The boar's parry stagger, hoof by hoof, as ClipLab plays it (AO 470 on 209875b; D-540, D-573).
	The clip's header authors three beats: the rear (0.00-0.20, the front hooves pawing about a stud
	up), the crash (the front hooves flat where they stood by 0.40, its one footstep at 0.42) and the
	sway (0.44-0.74, "sways onto its left legs (the right feet lift and come straight back down)").
	470(c) asked the back hooves to stay within 0.02 of the field over the whole clip, from D-540's
	"back hooves -0.012 throughout"; that read the back left hoof and the rear and crash, never the
	sway, where the back right lifts with the front right (the PC: 0.0965 at 0.58, back by 0.73; here
	0.0966 at 0.5833). This pins the clip as its header writes it, so the Studio line reads the same.

	Played through the real ClipAudit Lab plan (the clip cut in over the boar's idle, as ClipLab plays
	it) on the real rig at 60 and 144 Hz. Each row reads each hoof's lowest corner over the field
	inside the clip (0 to 1.0 s; the blend out into the idle after the clip's end is not this clip).
	A hoof is planted while its lowest corner is within stride.contact of the field.
]]
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local ChoreoData = Harness.load("src/shared/data/choreo")

local CONTACT = ChoreoData.locomotion.stride.contact
local CLIP = "enemy/Boar/Stagger"

type Row = { t: number, low: { [string]: number } }

local function rows(hz: number): { Row }
	local clip = ClipLibrary.get(CLIP)
	local body = ClipAudit.standingBody(RigBuilder.build("Boar"), "Boar")
	local lab = nil
	for _, plan in ClipAudit.plans(clip, ClipLibrary.get) do
		if plan.label == "Lab" then
			lab = plan
		end
	end
	assert(lab ~= nil, "ClipAudit has no Lab plan for " .. CLIP)
	local out: { Row } = {}
	for _, frame in ClipAudit.trace(body, lab, hz) do
		local t = frame.clipTime
		if t == nil or t >= clip.duration then
			continue
		end
		local low: { [string]: number } = {}
		for _, foot in body.feet do
			local least = math.huge
			for _, corner in body.corners[foot] do
				least = math.min(least, (frame.solved[foot] * corner).Y)
			end
			low[foot] = least - body.fieldTop
		end
		table.insert(out, { t = t, low = low })
	end
	return out
end

-- The lowest and highest a hoof reads over the rows with clip time in [from, to].
local function span(list: { Row }, foot: string, from: number, to: number): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, row in list do
		if row.t >= from - 1e-9 and row.t <= to + 1e-9 then
			lo = math.min(lo, row.low[foot])
			hi = math.max(hi, row.low[foot])
		end
	end
	return lo, hi
end

local function planted(list: { Row }, foot: string, from: number, to: number, label: string)
	local lo, hi = span(list, foot, from, to)
	if lo < -CONTACT or hi > CONTACT or hi - lo > CONTACT then
		error(
			("%s %s: %.4f to %.4f over %.2f-%.2f s (planted: within %.2f and moving at most %.2f)"):format(
				label,
				foot,
				lo,
				hi,
				from,
				to,
				CONTACT,
				CONTACT
			)
		)
	end
end

describe("BoarStaggerHooves: the parry stagger's hooves as its header writes them (AO 470, D-573)", function()
	for _, hz in { 60, 144 } do
		local label = ("%d Hz"):format(hz)
		local list = rows(hz)

		it(("rears with the front hooves about a stud up at 0.10-0.20 s (%s)"):format(label), function()
			for _, foot in { "FrontLeftLeg", "FrontRightLeg" } do
				local lo, hi = span(list, foot, 0.1, 0.2)
				expect(lo).toBeGreaterThanOrEqual(0.95)
				expect(hi).toBeLessThanOrEqual(1.1)
			end
		end)

		it(("crashes onto both front hooves by 0.40 s with one footstep at 0.42 (%s)"):format(label), function()
			for _, foot in { "FrontLeftLeg", "FrontRightLeg" } do
				local _, hi = span(list, foot, 0.4, 0.44)
				expect(hi).toBeLessThanOrEqual(CONTACT)
			end
			local steps = {}
			for _, event in ClipLibrary.get(CLIP).events do
				if event.kind == "Footstep" then
					table.insert(steps, event.time)
				end
			end
			expect(#steps).toBe(1)
			expect(math.abs(steps[1] - 0.42)).toBeLessThanOrEqual(1 / 60)
		end)

		it(
			("keeps the back left hoof planted over the whole clip and the back right through the crash (%s)"):format(
				label
			),
			function()
				planted(list, "BackLeftLeg", 0, 1, label)
				planted(list, "BackRightLeg", 0, 0.44, label)
			end
		)

		it(
			("sways onto its left legs at 0.44-0.74 s: the right hooves lift together and come back down (%s)"):format(
				label
			),
			function()
				-- The left hooves hold the field from the crash to the end.
				planted(list, "FrontLeftLeg", 0.42, 1, label)
				planted(list, "BackLeftLeg", 0.42, 1, label)
				-- The right hooves rise together to about 0.1 (0.0966 at 0.5833) and are back by 0.74.
				local peak, peakAt = -math.huge, 0
				for _, row in list do
					if row.t >= 0.44 and row.t <= 0.74 then
						expect(math.abs(row.low.FrontRightLeg - row.low.BackRightLeg)).toBeLessThanOrEqual(CONTACT)
						if row.low.BackRightLeg > peak then
							peak, peakAt = row.low.BackRightLeg, row.t
						end
					end
				end
				expect(peak).toBeGreaterThanOrEqual(0.08)
				expect(peak).toBeLessThanOrEqual(0.11)
				expect(peakAt).toBeGreaterThanOrEqual(0.55)
				expect(peakAt).toBeLessThanOrEqual(0.62)
				planted(list, "FrontRightLeg", 0.74, 1, label)
				planted(list, "BackRightLeg", 0.74, 1, label)
			end
		)
	end
end)
