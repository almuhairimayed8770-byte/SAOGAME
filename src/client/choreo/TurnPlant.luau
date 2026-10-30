--!strict
--[[
	TurnPlant: a standing body's feet hold the ground while its root turns (D-416; section 10, no
	sliding foot; Studio item 323(d)). The lock turns a standing root at combat.luau
	aim.lockTurnRate (720 degrees a second: half a turn in 0.25 s), and a held facing or the engine
	turns it too; on its own the root's yaw swings the hips, and both planted feet with them, round
	the root's axis (a 180 degree lock turn moved the feet 1.28 and 2.09 studs, a planted foot 0.31
	a frame). So while the body stands its hips keep the yaw they stood at: the Root joint takes
	back what the root turned (the lag), and the Waist turns the upper body on toward the root's
	facing by up to choreo.luau locomotion.turnPlant.twistDegrees (the head and torso lead).

	The hips come round only between a turn clip's first two Footsteps. The first is the pivot
	foot's: the clip has set it with the inner corner of its sole on the root's axis. The other foot
	is off the ground until the second, when it plants where the stance has it. In between the
	hips turn about the root's own axis, so the pivot foot turns about the corner the turn holds
	still and the other foot is in the air: neither slides. They come round on turnPlant.easing over
	that clip time and turn at most turnPlant.stepDegrees in a 60 Hz frame (a pop is 20). A lag the
	turn did not take (a turn short of locomotion.turnInPlaceDegrees) stays while the body stands.
	When the body moves off, leaves the ground, or another full-body clip takes it, the lag lets go
	evenly over turnPlant.plantSeconds, done by every attack's first strike key
	(tools/validators/choreo.luau): the hit is drawn on the clip's own pose.

		local plant = TurnPlant.new()
		TurnPlant.step(plant, dt, turned, holds, turnClip, clockBefore, clockAfter)
		animator:setProcedural("turnPlant", TurnPlant.offsets(plant))
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)
local Types = require(Shared.types)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Easing = require(Shared.util.Easing)

local Data = ChoreoData.locomotion.turnPlant

-- A lag smaller than this (degrees) is none.
local NONE = 1e-6

export type Plant = {
	lag: number, -- degrees the hips stand off the root's yaw (+ = to its left)
	letGo: number, -- degrees a second the lag is letting go at (0 while it holds)
	offsets: ClipSampler.Offsets, -- the channel's offsets, reused every step
}

local TurnPlant = {}

--- A plant with no lag.
function TurnPlant.new(): Plant
	return {
		lag = 0,
		letGo = 0,
		offsets = {
			Root = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
			Waist = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } },
		},
	}
end

local windows: { [string]: { number } } = {}

--- The clip time a turn clip brings the hips round between: its first two Footsteps (the pivot
--- foot's plant, then the other foot's). Nil for a clip with fewer than two.
function TurnPlant.window(clip: Types.ClipDef): (number?, number?)
	local cached = windows[clip.id]
	if cached == nil then
		local times: { number } = {}
		for _, event in clip.events or {} do
			if event.kind == "Footstep" then
				table.insert(times, event.time)
			end
		end
		table.sort(times)
		local found: { number } = if #times >= 2 and times[2] > times[1] then { times[1], times[2] } else {}
		windows[clip.id] = found
		cached = found
	end
	local window = cached :: { number }
	return window[1], window[2]
end

--- One step of `dt` seconds. `turned`: the degrees the root turned since the last step (+ = left).
--- `holds`: the body stands with its feet down and no other full-body clip has it. `clip`, `from`
--- and `to`: the turn clip playing and its clock before and after this step (nil when none).
function TurnPlant.step(
	plant: Plant,
	dt: number,
	turned: number,
	holds: boolean,
	clip: Types.ClipDef?,
	from: number,
	to: number
)
	local lag = plant.lag
	if holds then
		plant.letGo = 0
		-- The hips stay where they stood.
		lag -= turned
		if clip ~= nil and to > from then
			local open, close = TurnPlant.window(clip)
			if open ~= nil and close ~= nil and to > open and from < close then
				local span = close - open
				local before = Easing.evaluate(Data.easing, math.clamp((from - open) / span, 0, 1))
				local after = Easing.evaluate(Data.easing, math.clamp((to - open) / span, 0, 1))
				-- The share of the lag the curve still keeps, then this step's turn of the hips,
				-- capped per 60 Hz frame of clip time.
				local keep = if after >= 1 then 0 else (1 - after) / math.max(1 - before, NONE)
				local cap = Data.stepDegrees * (to - from) * 60
				lag += math.clamp(lag * keep - lag, -cap, cap)
			end
		end
	elseif lag ~= 0 then
		if plant.letGo <= 0 then
			plant.letGo = math.abs(lag) / Data.plantSeconds
		end
		local step = plant.letGo * dt
		lag = if math.abs(lag) <= step then 0 else lag - math.sign(lag) * step
	end
	if math.abs(lag) < NONE then
		lag = 0
		plant.letGo = 0
	end
	plant.lag = lag
end

--- The channel's offsets for the plant's lag (the Root takes it back, the Waist turns the upper
--- body on by up to twistDegrees of it), or nil when there is none.
function TurnPlant.offsets(plant: Plant): ClipSampler.Offsets?
	local lag = plant.lag
	if lag == 0 then
		return nil
	end
	local offsets = plant.offsets
	offsets.Root.rot[2] = lag
	offsets.Waist.rot[2] = -math.clamp(lag, -Data.twistDegrees, Data.twistDegrees)
	return offsets
end

return TurnPlant
