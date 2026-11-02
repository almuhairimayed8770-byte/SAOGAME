--!strict
--[[
	EnemyWalkStride: an enemy's walk keeps its planted feet on the field at the rig's walkSpeed
	(section 21 gate line 4: "No T-pose, A-pose, frozen rig, popping limb or sliding foot appears in
	any clip"; D-482). RigDriver plays enemy/Boar/Walk and enemy/Kobold/Walk at speed / walkSpeed
	under a body the server carries, so one cycle of the walk has to cover rigs.luau walkSpeed x its
	duration with every planted foot still.

	Each walk is traced through ClipAudit's Lab plan (the real Mixer, the rig RigBuilder builds,
	the root carried at walkSpeed) with the walk alone in it, at each review.audit sampleHz, one
	whole cycle and on past its wrap, and measured by ClipAudit with review.audit's own bounds (no
	planted foot slides past footSlideStuds in a frame nor drifts past footDriftStuds over its plant
	nor sinks past footSinkStuds; no part turns past popDegrees in a frame). The Lab plan proper
	cuts the walk in over the rig's fallback idle, which takes choreo.luau fallbackBlend to fade out
	under it while the root already moves at walkSpeed: those first frames are part idle, and
	ClipAudit.spec keeps that cut-in pending. The old walks slid all through their cycle (the boar's
	planted feet 5.13 studs over a plant, the kobold's 2.86).
]]

local Choreo = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local RigBuilder = Harness.load("src/server/world/RigBuilder")

local Audit = Dev.review.audit
local FEET_AND_POPS = { Slide = true, Drift = true, Sink = true, Pop = true }

-- The feet and pop findings of one trace of `clip` alone through the Lab plan at `hz`, and the
-- clip time the trace covers.
local function cycleFindings(clip: any, hz: number): ({ string }, number)
	local body = ClipAudit.standingBody(RigBuilder.build(clip.rig), clip.rig)
	local lab = ClipAudit.plans(clip, ClipLibrary.get)[1]
	expect(lab.label).toBe("Lab")
	expect(lab.travel ~= nil).toBe(true)
	local plan = table.clone(lab)
	plan.plays = {}
	for _, play in lab.plays do
		if play.fallback ~= true then
			table.insert(plan.plays, play)
		end
	end
	expect(#plan.plays).toBe(1)
	local frames = ClipAudit.trace(body, plan, hz)
	local first: number?, last: number? = nil, nil
	for _, frame in frames do
		if frame.clipTime ~= nil then
			first = first or frame.time
			last = frame.time
		end
	end
	local covered = if first ~= nil and last ~= nil then last - first else 0
	local found = {}
	for _, finding in ClipAudit.findings(clip, ClipAudit.measure(body, clip, plan, frames, hz)) do
		if FEET_AND_POPS[finding.kind] then
			table.insert(found, finding.text)
		end
	end
	return found, covered
end

describe("EnemyWalkStride: an enemy's walk keeps its planted feet on the field (D-482)", function()
	for _, rig in { "Boar", "Kobold" } do
		local id = Choreo.rigs[rig].walk
		for _, hz in Audit.sampleHz do
			it(("%s holds its feet through a whole cycle at %d Hz"):format(id, hz), function()
				local clip = ClipLibrary.get(id)
				local found, covered = cycleFindings(clip, hz)
				-- a whole cycle was measured
				expect(covered >= clip.duration).toBe(true)
				expect(table.concat(found, "\n")).toBe("")
			end)
		end
	end
end)

-- The boar's walk is one key a 60 fps frame split into four on the straight line between its two
-- keys (D-576), so a planted hoof moves near evenly inside a frame and a 144 Hz row never catches
-- it stopping and going. The first frame's first quarter had kept the single ease's pace (the
-- planted hips 1.11 degrees against the stance's 1.9), and the hooves dragged on by it at every
-- front-left and back-right touchdown: 0.042 a 144 Hz row walking straight, 0.049 wheeling at 90
-- degrees with the turn plant (D-620; now 0.021 and 0.029).
describe("EnemyWalkStride: the boar's walk quarters every frame on its straight line (D-576, D-620)", function()
	it("every key between two 60 fps keys stands on the line between them", function()
		local clip = ClipLibrary.get(Choreo.rigs.Boar.walk)
		local frame = 1 / 60
		local framed: { number } = {}
		for index, key in clip.keys do
			local whole = key.time / frame
			if math.abs(whole - math.floor(whole + 0.5)) < 0.01 then
				table.insert(framed, index)
			end
		end
		expect(#framed >= 2).toBe(true)
		local worst, worstAt = 0, ""
		for step = 1, #framed - 1 do
			local from, to = clip.keys[framed[step]], clip.keys[framed[step + 1]]
			local count = framed[step + 1] - framed[step]
			for between = framed[step] + 1, framed[step + 1] - 1 do
				local key = clip.keys[between]
				local share = (between - framed[step]) / count
				for joint, value in key.joints do
					local a, b = from.joints[joint], to.joints[joint]
					for _, field in { "pos", "rot" } do
						local here = (value :: any)[field] or { 0, 0, 0 }
						local first = (a :: any)[field] or { 0, 0, 0 }
						local last = (b :: any)[field] or { 0, 0, 0 }
						for axis = 1, 3 do
							local line = first[axis] + (last[axis] - first[axis]) * share
							local off = math.abs(here[axis] - line)
							if off > worst then
								worst, worstAt = off, ("%s %s[%d] at %.4f s"):format(joint, field, axis, key.time)
							end
						end
					end
				end
			end
		end
		print(("enemy/Boar/Walk: farthest quarter key off its frame's line %.4f (%s)"):format(worst, worstAt))
		-- The keys are written to the hundredth of a degree and the thousandth of a stud.
		expect(worst <= 0.006).toBe(true)
	end)
end)
