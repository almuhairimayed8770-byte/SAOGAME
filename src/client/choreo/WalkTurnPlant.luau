--!strict
--[[
	WalkTurnPlant: an enemy's planted feet hold the field while its body turns as it walks
	(D-619; section 10, no sliding foot; Studio item 511). The server turns an enemy's root about
	its own axis (the boar wheels at 110 degrees a second), and the walk's planted feet, set out from
	that axis, swing round it with the root: the boar's hooves stand 1.0 to 2.3
	studs out, so a wheeling boar's planted hoof slid 0.013 to 0.030 a 144 Hz row on the turn alone
	(0.03 to 0.067 a 60 Hz row), on top of the walk's own slide. The player's TurnPlant (D-416)
	holds a standing body's feet by turning its hips back against the root's turn; a walking body
	cannot take a whole turn back (it has a foot down all the time), so each leg takes back its own
	share of it while that foot is down.

	Each foot's stance is read once off the rig's walk clip: where the clip stands its sole on the
	field (a corner within stride.contact with the root at its standing height), and where the sole
	is. While a foot is down its hip sets the sole back against the sweep the root's turn over the
	row gives its spot (the turn times the sole's distance from the root's axis): `share` of it, so
	the turn shows that much less on the planted sole. While a foot is up it is set out into the
	turn for its next stance: half the stance's take-back ahead, arriving as it lands, so the stance
	takes it through the walk's own pose and on by as much. The hip rolls the leg sideways (with
	the leg drawn up by what the roll sinks the sole's low edge) and slides it along the body; a
	roll is at most maxRollDegrees and a slide maxShiftStuds, and a turn too tight for the stance
	takes back the same lesser share all through it, never a leg thrown out of the body. The hips
	do not turn the legs about the vertical as well: that holds the sole's heading but turns the
	leg's roll over its sole off the body's travel, and a boar wheeling at 110 degrees a second slid
	more on it (0.035 a 60 Hz row against 0.029, 0.047 a 144 Hz row against 0.032).

		local plan = WalkTurnPlant.plan(character, walkClip, config)
		local state = WalkTurnPlant.new(plan)
		local offsets = WalkTurnPlant.step(state, dt, turned, walkTime, walkRate)
		animator:setProcedural("walkTurnPlant", offsets, walkWeight)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)
local Rigs = require(Shared.data.rigs)
local Types = require(Shared.types)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Pose = require(Shared.choreo.Pose)

local Stride = ChoreoData.locomotion.stride

local SAMPLES = 120 -- unit: samples a plan reads of the walk's cycle
local NOISE = 1e-9 -- unit: float noise in a phase or a sweep

export type Config = {
	feet: { string }, -- the rig's foot parts, each hung from its own hip joint
	share: number, -- the share of a planted foot's sweep its hip takes back (0 .. 1]
	maxRollDegrees: number, -- the most a hip rolls its leg sideways
	maxShiftStuds: number, -- the most a hip slides its leg along the body
}

type Foot = {
	part: string,
	joint: string, -- the hip joint that hangs the foot
	axis: CFrame, -- the hip joint's C0 rotation (its frame in its Part0, the body)
	length: number, -- from the hip down to the sole
	halfWidth: number, -- the sole's half width (a roll sinks its low edge by this times the sine)
	down: { boolean }, -- per sample: the clip stands the sole on the field
	at: { Vector3 }, -- per sample: the sole's centre in the root's space
	-- Per sample: the take-back of the stance the sample is in or the next one (clip seconds times
	-- studs: the sweep per radian a second of turn, summed over the stance's samples), and the clip
	-- time to that stance's start (0 in it).
	stanceSweep: { Vector3 },
	untilStance: { number },
	-- Per down sample: what is left of its stance's take-back from that sample on.
	sweepLeft: { Vector3 },
}

export type Plan = {
	duration: number,
	feet: { Foot },
	config: Config,
}

export type State = {
	plan: Plan,
	-- Per foot: the hip's take-back, its sole's flat move in the root's space (studs, x across and
	-- z along).
	shift: { Vector3 },
	offsets: ClipSampler.Offsets,
}

local WalkTurnPlant = {}

-- The sweep a turn of one radian gives a point `at` the root's space: y x at, flat.
local function sweepOf(at: Vector3): Vector3
	return Vector3.new(at.Z, 0, -at.X)
end

local function sampleAt(plan: Plan, time: number): number
	local duration = plan.duration
	local phase = (time % duration) / duration
	return math.clamp(math.floor(phase * SAMPLES + NOISE), 0, SAMPLES - 1) + 1
end

--- Reads a rig's walk once: each foot's stance on the field and where the sole is.
--- `character` is the rig (its joints and part sizes); `clip` its walk.
function WalkTurnPlant.plan(character: Model, clip: Types.ClipDef, config: Config): Plan?
	local root = character.PrimaryPart
	if root == nil then
		return nil
	end
	local rig = Rigs[clip.rig]
	local height = if rig ~= nil then rig.hipHeight + root.Size.Y / 2 else root.Size.Y / 2
	local base = CFrame.new(0, height, 0)
	local chain = Pose.chain(character)
	local hips: { [string]: Pose.Link } = {}
	for _, link in chain.links do
		hips[link.part1] = link
	end
	local feet: { Foot } = {}
	local sizes: { [string]: Vector3 } = {}
	for _, name in config.feet do
		local part = character:FindFirstChild(name)
		local link = hips[name]
		if part == nil or not part:IsA("BasePart") or link == nil then
			continue
		end
		local size = (part :: BasePart).Size
		sizes[name] = size
		table.insert(feet, {
			part = name,
			joint = link.name,
			axis = link.c0.Rotation,
			length = link.c1Inverse:Inverse().Position.Magnitude + size.Y / 2,
			halfWidth = size.X / 2,
			down = {},
			at = {},
			stanceSweep = {},
			untilStance = {},
			sweepLeft = {},
		})
	end
	if #feet == 0 then
		return nil
	end
	local duration = clip.duration
	for index = 1, SAMPLES do
		local time = (index - 0.5) / SAMPLES * duration
		local solved = Pose.solve(character, base, ClipSampler.sample(clip, time), chain)
		for _, foot in feet do
			local frame = solved[foot.part]
			local size = sizes[foot.part]
			local lowest = math.huge
			for _, x in { -0.5, 0.5 } do
				for _, z in { -0.5, 0.5 } do
					lowest = math.min(lowest, (frame * Vector3.new(x * size.X, -0.5 * size.Y, z * size.Z)).Y)
				end
			end
			foot.down[index] = lowest <= Stride.contact
			foot.at[index] = base:PointToObjectSpace(frame * Vector3.new(0, -0.5 * size.Y, 0))
		end
	end
	local step = duration / SAMPLES
	for _, foot in feet do
		-- Each stance's whole take-back, then every sample's own stance (in it) or next one.
		local first: number? = nil
		for index = 1, SAMPLES do
			local before = if index == 1 then SAMPLES else index - 1
			if foot.down[index] and not foot.down[before] then
				first = index
				break
			end
		end
		if first == nil then
			-- Down all cycle or never: no stance to set out for.
			for index = 1, SAMPLES do
				foot.stanceSweep[index] = Vector3.zero
				foot.untilStance[index] = 0
				foot.sweepLeft[index] = Vector3.zero
			end
			continue
		end
		local sweeps: { [number]: Vector3 } = {}
		local startOf: { number } = {}
		local current = first :: number
		for offset = 0, SAMPLES - 1 do
			local index = ((first :: number) - 1 + offset) % SAMPLES + 1
			local before = if index == 1 then SAMPLES else index - 1
			if foot.down[index] and not foot.down[before] then
				current = index
				sweeps[current] = Vector3.zero
			end
			if foot.down[index] then
				sweeps[current] += sweepOf(foot.at[index]) * step
			end
			startOf[index] = current
		end
		-- What is left of each stance from each of its samples on (walked back from its end).
		local sweepLeft = Vector3.zero
		for offset = SAMPLES - 1, 0, -1 do
			local index = ((first :: number) - 1 + offset) % SAMPLES + 1
			sweepLeft = if foot.down[index] then sweepLeft + sweepOf(foot.at[index]) * step else Vector3.zero
			foot.sweepLeft[index] = sweepLeft
		end
		for index = 1, SAMPLES do
			local stance = index
			local ahead = 0
			while not foot.down[stance] and ahead < SAMPLES do
				stance = stance % SAMPLES + 1
				ahead += 1
			end
			foot.stanceSweep[index] = sweeps[startOf[stance]] or Vector3.zero
			foot.untilStance[index] = ahead * step
		end
	end
	return { duration = duration, feet = feet, config = config }
end

--- A plant with every leg on the walk's own pose.
function WalkTurnPlant.new(plan: Plan): State
	local shift: { Vector3 } = {}
	local offsets: ClipSampler.Offsets = {}
	for index, foot in plan.feet do
		shift[index] = Vector3.zero
		offsets[foot.joint] = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }
	end
	return { plan = plan, shift = shift, offsets = offsets }
end

--- Lets every leg go back to the walk's own pose at once (the walk is not shown).
function WalkTurnPlant.reset(state: State)
	for index in state.shift do
		state.shift[index] = Vector3.zero
	end
end

-- The share of what is left of a stance's take-back (on one axis) that keeps it within the leg's
-- reach: the rest of the stance takes back `sweep` (at this turn and walk rate) from `from`, ending
-- at from - share * sweep, at most `reach` either side. Read afresh every step (the turn and the
-- walk's rate change under a stance), a turn too tight for the leg takes back the same lesser share
-- all through the stance (the planted sole keeps an even part of the turn on every row) rather than
-- all of it until the leg runs out and none after.
local function shareWithin(share: number, sweep: number, from: number, reach: number): number
	local size = math.abs(sweep)
	if size <= NOISE then
		return share
	end
	local room = reach + (if sweep > 0 then from else -from)
	return math.clamp(room / size, 0, share)
end

-- Half the share of a whole stance's take-back `sweep` a swing sets its foot out by: the stance then
-- takes it from that side of the walk's own pose to as far the other, within `reach` either side.
local function halfWithin(share: number, sweep: number, reach: number): number
	local size = math.abs(sweep)
	if size <= NOISE then
		return share / 2
	end
	return math.min(share, 2 * reach / size) / 2
end

--- One step of `dt` seconds. `turned`: the radians the root turns over the row this step draws
--- (+ = to its left, about +Y). `time`: the walk's clock after this step; `rate`: its speed. Returns
--- the channel's offsets (each foot's hip), or nil when no leg is off the walk's pose.
function WalkTurnPlant.step(state: State, dt: number, turned: number, time: number, rate: number): ClipSampler.Offsets?
	local plan = state.plan
	local config = plan.config
	local share = config.share
	local index = sampleAt(plan, time)
	local clipRate = math.max(rate, 1e-6)
	local perClip = (if dt > 0 then turned / dt else 0) / clipRate -- radians of turn a clip second
	local alongReach = config.maxShiftStuds
	local any = false
	for footIndex, foot in plan.feet do
		local shift = state.shift[footIndex]
		local acrossReach = foot.length * math.sin(math.rad(config.maxRollDegrees))
		if foot.down[index] then
			-- Down: back against this row's sweep of the sole's spot, the share of it the rest of the
			-- stance can take back.
			local sweep = foot.sweepLeft[index] * perClip
			local back = sweepOf(foot.at[index]) * turned
			shift -= Vector3.new(
				back.X * shareWithin(share, sweep.X, shift.X, acrossReach),
				0,
				back.Z * shareWithin(share, sweep.Z, shift.Z, alongReach)
			)
		else
			-- Up: out into the turn for the next stance, half its take-back ahead (of the share the
			-- leg can take back from there), arriving as it lands.
			local sweep = foot.stanceSweep[index] * perClip
			local target = Vector3.new(
				sweep.X * halfWithin(share, sweep.X, acrossReach),
				0,
				sweep.Z * halfWithin(share, sweep.Z, alongReach)
			)
			local left = foot.untilStance[index]
			local reach = if left > 0 then math.min(1, dt * clipRate / left) else 1
			shift += (target - shift) * reach
		end
		shift =
			Vector3.new(math.clamp(shift.X, -acrossReach, acrossReach), 0, math.clamp(shift.Z, -alongReach, alongReach))
		state.shift[footIndex] = shift
		-- Into the hip's own frame (its C0), as a roll across and a slide along.
		local here = foot.axis:VectorToObjectSpace(shift)
		local roll = math.asin(math.clamp(here.X / foot.length, -1, 1))
		local offset = state.offsets[foot.joint]
		offset.rot[3] = math.deg(roll)
		offset.pos[3] = here.Z
		-- The roll lifts the sole's centre and sinks its low edge: draw the leg up by what is left.
		offset.pos[2] = foot.halfWidth * math.abs(math.sin(roll)) - foot.length * (1 - math.cos(roll))
		any = any or shift.Magnitude > 1e-6
	end
	return if any then state.offsets else nil
end

return WalkTurnPlant
