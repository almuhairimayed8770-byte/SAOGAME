--!strict
--[[
	The boar's idle keeps its hooves out of the field (D-601). Its weight shift at 2.0 s rolled the
	body 2 degrees with the front left leg reaching 4 degrees forward, which put that hoof's lowest
	corner 0.067 into the field (the back left 0.057) from 2.0 to 2.6 s. It showed wherever the idle
	takes weight: under the Charge's crouch when the boar charges from that pose (ClipAudit's Stand@6
	plan) and in ClipLab's blend out of the Stagger into the idle at its 2 s mark.

	Its breath kept them on the field too (D-622): riding the Root joint alone it lifted the body
	0.05 with every leg, the front hooves 0.068 off the field at 1.0 s and 0.058 at 3.2 s; the hips
	take the rise back now, so the chest rises on its legs.

	Played through the real ClipAudit plans on the real rig at 60 and 144 Hz. A hoof reads its lowest
	corner over the field; it is on the field while that is within stride.contact.
]]
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local ChoreoData = Harness.load("src/shared/data/choreo")

local CONTACT = ChoreoData.locomotion.stride.contact
local IDLE = "enemy/Boar/Idle"
-- The boar's clips the game plays over its idle (its walk is a loop of its own, measured elsewhere).
local OVER_IDLE = {
	"enemy/Boar/Charge",
	"enemy/Boar/Stagger",
	"enemy/Boar/FlinchFront",
	"enemy/Boar/FlinchBack",
	"enemy/Boar/FlinchLeft",
	"enemy/Boar/FlinchRight",
	"enemy/Boar/Break",
}

type Row = { t: number, clipTime: number?, ended: boolean, low: { [string]: number } }

local function trace(id: string, label: string, hz: number): { Row }
	local clip = ClipLibrary.get(id)
	local body = ClipAudit.standingBody(RigBuilder.build("Boar"), "Boar")
	local out: { Row } = {}
	for _, plan in ClipAudit.plans(clip, ClipLibrary.get) do
		if plan.label ~= label then
			continue
		end
		for _, frame in ClipAudit.trace(body, plan, hz) do
			local low: { [string]: number } = {}
			for _, foot in body.feet do
				local least = math.huge
				for _, corner in body.corners[foot] do
					least = math.min(least, (frame.solved[foot] * corner).Y)
				end
				low[foot] = least - body.fieldTop
			end
			table.insert(out, { t = frame.time, clipTime = frame.clipTime, ended = frame.ended, low = low })
		end
	end
	return out
end

local function labels(id: string): { string }
	local out = {}
	for _, plan in ClipAudit.plans(ClipLibrary.get(id), ClipLibrary.get) do
		table.insert(out, plan.label)
	end
	return out
end

-- The deepest hoof over the rows `keep` takes, with where it was.
local function deepest(list: { Row }, keep: (Row) -> boolean): (number, string, number)
	local lo, foot, at = math.huge, "", 0
	for _, row in list do
		if keep(row) then
			for name, low in row.low do
				if low < lo then
					lo, foot, at = low, name, row.t
				end
			end
		end
	end
	return lo, foot, at
end

describe("BoarIdleHooves: the boar's idle keeps its hooves out of the field (D-601)", function()
	for _, hz in { 60, 144 } do
		local label = ("%d Hz"):format(hz)

		it(("no hoof sinks past stride.contact over the idle's loop (%s)"):format(label), function()
			local list = trace(IDLE, "Lab", hz)
			expect(#list).toBeGreaterThan(0)
			local lo, foot, at = deepest(list, function(row)
				return row.clipTime ~= nil
			end)
			if lo < -CONTACT then
				error(("%s %s: %.4f at %.3f s, below -%.2f"):format(label, foot, lo, at, CONTACT))
			end
		end)

		it(("every hoof stays on the field through the breath and the whole loop (%s)"):format(label), function()
			local high, highFoot, highAt = -math.huge, "", 0
			for _, row in trace(IDLE, "Lab", hz) do
				if row.clipTime == nil then
					continue
				end
				for foot, low in row.low do
					if low > high then
						high, highFoot, highAt = low, foot, row.t
					end
				end
			end
			print(("%s: highest hoof %s %.4f at %.3f s"):format(label, highFoot, high, highAt))
			if high > CONTACT then
				error(
					("%s %s: %.4f at %.3f s, off the field by more than %.2f"):format(
						label,
						highFoot,
						high,
						highAt,
						CONTACT
					)
				)
			end
		end)

		it(("every hoof holds the field through the weight shift, 2.0-2.6 s (%s)"):format(label), function()
			for _, row in trace(IDLE, "Lab", hz) do
				local t = row.clipTime
				if t == nil or t < 2 - 1e-9 or t > 2.6 + 1e-9 then
					continue
				end
				for foot, low in row.low do
					if math.abs(low) > CONTACT then
						error(
							("%s %s: %.4f at %.3f s, off the field by more than %.2f"):format(
								label,
								foot,
								low,
								t,
								CONTACT
							)
						)
					end
				end
			end
		end)

		it(
			("no hoof sinks past stride.contact while the idle holds weight around a clip (%s)"):format(label),
			function()
				for _, id in OVER_IDLE do
					for _, name in labels(id) do
						local list = trace(id, name, hz)
						-- Before the clip plays the idle stands alone; once it ends it blends back into the idle.
						local lo, foot, at = deepest(list, function(row)
							return row.clipTime == nil or row.ended
						end)
						if lo < -CONTACT then
							error(
								("%s %s %s %s: %.4f at %.3f s, below -%.2f"):format(
									id,
									name,
									label,
									foot,
									lo,
									at,
									CONTACT
								)
							)
						end
					end
				end
			end
		)
	end
end)
