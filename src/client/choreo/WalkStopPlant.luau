--!strict
--[[
	WalkStopPlant: an enemy that stops plants its feet and steps them into its idle (D-623;
	section 10, no sliding foot; Studio item 511(k)). The server stops an enemy's root within a
	frame or two (the Humanoid brakes), while the client's walk went on: it kept its clock at the
	walk's slowest rate and crossfaded into the idle over locomotion.weightBlendRate (0.125 s) with
	the root standing, so each planted foot swung about its hip from the walk's stance to the idle's
	stand and the swinging foot was drawn down onto the field on the way: the kobold slid 0.12 to
	0.24 a 60 Hz row, the boar 0.38 with its turn plant let go at once. In the anime a monster that
	stops plants and stands.

	So when the root stands, the walk's clock stops where the body stopped and every leg is drawn
	in the root's own space. Each leg holds the place it stood in (its sole stays on its field
	point) until its group's step; a step lifts the leg off that place and sets it down where the
	idle stands it, on a SineInOut over stepSeconds with the sole kept liftStuds clear of the
	straight path between where it rose and where it lands at the step's middle. Groups step one
	at a time (a trot's diagonal pairs, a biped's feet): first every group but the one standing
	lowest (the swinging foot lands first), the lowest last, so the body always stands on a group.
	A group whose feet already stand within settleStuds of the idle's spots glides there with the
	first step instead. The walk's share of the body (torso, head, arms, tail) falls evenly to 0
	over the steps, so the idle owns the whole rig the moment the last foot is down.

		local plan = WalkStopPlant.plan(character, rigId, config)
		local state = WalkStopPlant.new(plan)
		WalkStopPlant.begin(state, shownLastFrame, idlePose)
		local walkWeight = WalkStopPlant.walkWeight(state, dt)
		local offsets = WalkStopPlant.step(state, dt, basePose, idlePose)
		animator:setProcedural("walkStopPlant", offsets, 1)
		if WalkStopPlant.done(state) then WalkStopPlant.cancel(state) end
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rigs = require(Shared.data.rigs)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Pose = require(Shared.choreo.Pose)
local Easing = require(Shared.util.Easing)

local NOISE = 1e-9 -- unit: seconds, float noise in a sum of frame times

export type Config = {
	groups: { { string } }, -- the rig's foot parts, by the group each steps with, each hung from its own hip
	stepSeconds: number, -- one group's step
	liftStuds: number, -- how far the sole clears its straight path at the step's middle
	settleStuds: number, -- a group whose soles all stand this near the idle's spots glides instead
}

type Leg = {
	part: string,
	joint: string, -- the hip joint that hangs the leg
	group: number,
	path: { Pose.Link }, -- the joints from the root part down to the leg, the hip last
	corners: { Vector3 }, -- the sole's four corners in the leg's own space
	sole: Vector3, -- the sole's centre in the leg's own space
}

export type Plan = {
	legs: { Leg },
	groups: number,
	height: number, -- the root part's centre over the field when it stands (studs)
	config: Config,
}

export type State = {
	plan: Plan,
	active: boolean,
	clock: number, -- seconds since the stop began
	total: number, -- seconds the steps take
	held: { CFrame }, -- per leg: where it stood when the stop began, in the root's space
	starts: { number }, -- per group: the stop's clock its step starts at
	glides: { boolean }, -- per group: it glides to the idle's spots (no lift)
	offsets: ClipSampler.Offsets,
}

local WalkStopPlant = {}

local REST: ClipSampler.Offset = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }

--- Reads a rig's legs once: the joints that hang each foot from the root and its sole's corners.
--- `character` is the rig (its joints and part sizes), `rigId` its rigs.luau id. Nil when it names
--- no foot it has.
function WalkStopPlant.plan(character: Model, rigId: string, config: Config): Plan?
	local root = character.PrimaryPart
	if root == nil then
		return nil
	end
	local chain = Pose.chain(character)
	local byPart: { [string]: Pose.Link } = {}
	for _, link in chain.links do
		byPart[link.part1] = link
	end
	local legs: { Leg } = {}
	for group, feet in config.groups do
		for _, name in feet do
			local part = character:FindFirstChild(name)
			local hip = byPart[name]
			if part == nil or not part:IsA("BasePart") or hip == nil then
				continue
			end
			local path: { Pose.Link } = { hip }
			local above = byPart[hip.part0]
			while above ~= nil do
				table.insert(path, 1, above)
				above = byPart[above.part0]
			end
			if path[1].part0 ~= chain.rootName then
				continue
			end
			local half = (part :: BasePart).Size / 2
			local corners: { Vector3 } = {}
			for _, x in { -1, 1 } do
				for _, z in { -1, 1 } do
					table.insert(corners, Vector3.new(x * half.X, -half.Y, z * half.Z))
				end
			end
			table.insert(legs, {
				part = name,
				joint = hip.name,
				group = group,
				path = path,
				corners = corners,
				sole = Vector3.new(0, -half.Y, 0),
			})
		end
	end
	if #legs == 0 then
		return nil
	end
	local rig = Rigs[rigId]
	local height = if rig ~= nil then rig.hipHeight + root.Size.Y / 2 else root.Size.Y / 2
	return { legs = legs, groups = #config.groups, height = height, config = config }
end

--- A stop plant standing by (no stop under way).
function WalkStopPlant.new(plan: Plan): State
	local offsets: ClipSampler.Offsets = {}
	for _, leg in plan.legs do
		offsets[leg.joint] = { pos = { 0, 0, 0 }, rot = { 0, 0, 0 } }
	end
	return {
		plan = plan,
		active = false,
		clock = 0,
		total = 0,
		held = {},
		starts = {},
		glides = {},
		offsets = offsets,
	}
end

-- The frame of the leg's parent part (`upTo` links of its path) or of the leg itself, in the
-- root's space, under `pose`.
local function frameOf(leg: Leg, pose: ClipSampler.Offsets, upTo: number): CFrame
	local frame = CFrame.identity
	for index = 1, upTo do
		local link = leg.path[index]
		frame = frame * link.c0 * ClipSampler.toCFrame(pose[link.name] or REST) * link.c1Inverse
	end
	return frame
end

local function legFrame(leg: Leg, pose: ClipSampler.Offsets): CFrame
	return frameOf(leg, pose, #leg.path)
end

-- The lowest of the sole's corners over the field, the leg at `frame` (root space).
local function lowest(plan: Plan, leg: Leg, frame: CFrame): number
	local low = math.huge
	for _, corner in leg.corners do
		low = math.min(low, (frame * corner).Y)
	end
	return plan.height + low
end

--- Starts a stop: `shown` is the pose the rig showed on the last frame (every joint from the root
--- to the feet), `idle` the idle's pose now. Each leg holds where `shown` stood it; the groups'
--- steps are set in order (every group but the lowest, the highest first, then the lowest).
function WalkStopPlant.begin(state: State, shown: ClipSampler.Offsets, idle: ClipSampler.Offsets)
	local plan = state.plan
	local config = plan.config
	local height: { number } = {}
	local settled: { boolean } = {}
	for group = 1, plan.groups do
		height[group] = -math.huge
		settled[group] = true
	end
	for index, leg in plan.legs do
		local held = legFrame(leg, shown)
		state.held[index] = held
		height[leg.group] = math.max(height[leg.group], lowest(plan, leg, held))
		local away = (held * leg.sole) - (legFrame(leg, idle) * leg.sole)
		if away.Magnitude > config.settleStuds then
			settled[leg.group] = false
		end
	end
	local steppers: { number } = {}
	for group = 1, plan.groups do
		state.glides[group] = settled[group]
		state.starts[group] = 0
		if not settled[group] and height[group] > -math.huge then
			table.insert(steppers, group)
		end
	end
	-- The highest group first and the lowest (the one the body stands on) last.
	table.sort(steppers, function(a: number, b: number): boolean
		if height[a] ~= height[b] then
			return height[a] > height[b]
		end
		return a < b
	end)
	for slot, group in steppers do
		state.starts[group] = (slot - 1) * config.stepSeconds
	end
	state.total = math.max(#steppers, 1) * config.stepSeconds
	state.clock = 0
	state.active = true
end

--- Ends a stop: its last foot is down, the walk goes on, or a full-body clip takes the body.
function WalkStopPlant.cancel(state: State)
	state.active = false
end

--- The walk's share of the body once the next step of `dt` is drawn: 1 as the stop begins, 0 when
--- its last foot is down. 0 when no stop is under way.
function WalkStopPlant.walkWeight(state: State, dt: number): number
	if not state.active then
		return 0
	end
	return 1 - math.clamp((state.clock + math.max(dt, 0)) / state.total, 0, 1)
end

--- True once the stop's last foot is down (its clock has run its steps).
function WalkStopPlant.done(state: State): boolean
	return state.clock >= state.total - NOISE
end

--- One step of `dt` seconds. `base`: the pose the rig's base layer composes on this step, every
--- joint from the root down; `idle`: the idle's pose on this step. Returns each hip's offset over
--- `base` that draws its leg where the stop has it (a leg whose step is done stands where the idle
--- stands it), or nil when no stop is under way.
function WalkStopPlant.step(
	state: State,
	dt: number,
	base: ClipSampler.Offsets,
	idle: ClipSampler.Offsets
): ClipSampler.Offsets?
	if not state.active then
		return nil
	end
	state.clock += math.max(dt, 0)
	local plan = state.plan
	local config = plan.config
	for index, leg in plan.legs do
		local held = state.held[index]
		local lands = legFrame(leg, idle)
		local progress = (state.clock - state.starts[leg.group]) / config.stepSeconds
		local frame: CFrame
		if progress <= 0 then
			frame = held
		elseif progress >= 1 - NOISE then
			frame = lands
		else
			local eased = Easing.SineInOut(progress)
			frame = held:Lerp(lands, eased)
			if not state.glides[leg.group] then
				-- On or over the straight path between the heights it rose from and lands at, and
				-- liftStuds * sin(pi * progress) over the lower of them: a foot already up comes
				-- down onto its spot, and every foot lands from straight above.
				local from, to = lowest(plan, leg, held), lowest(plan, leg, lands)
				local path = math.max(
					from + (to - from) * eased,
					math.min(from, to) + config.liftStuds * math.sin(math.pi * progress)
				)
				local lift = math.max(0, path - lowest(plan, leg, frame))
				frame = CFrame.new(0, lift, 0) * frame
			end
		end
		-- The hip's transform that hangs the leg there from its parent as the base draws it.
		local hip = leg.path[#leg.path]
		local parent = frameOf(leg, base, #leg.path - 1)
		local transform = hip.c0:Inverse() * parent:Inverse() * frame * hip.c1Inverse:Inverse()
		local rx, ry, rz = transform:ToEulerAnglesXYZ()
		local under = base[leg.joint] or REST
		local offset = state.offsets[leg.joint]
		local at = transform.Position
		offset.pos[1], offset.pos[2], offset.pos[3] = at.X - under.pos[1], at.Y - under.pos[2], at.Z - under.pos[3]
		offset.rot[1] = math.deg(rx) - under.rot[1]
		offset.rot[2] = math.deg(ry) - under.rot[2]
		offset.rot[3] = math.deg(rz) - under.rot[3]
	end
	return state.offsets
end

return WalkStopPlant
