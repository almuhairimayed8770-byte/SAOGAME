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

	A stop begun on the root its last row was drawn on (begin's `root`, D-664) holds each leg's
	place on the field instead, read on the root each row is drawn on: a drawn root still coming to
	a stand carries the body over planted feet.

		local plan = WalkStopPlant.plan(character, rigId, config)
		local state = WalkStopPlant.new(plan)
		WalkStopPlant.begin(state, shownLastFrame, idlePose)
		local walkWeight = WalkStopPlant.walkWeight(state, dt)
		local offsets = WalkStopPlant.step(state, dt, basePose, idlePose)
		animator:setProcedural("walkStopPlant", offsets, 1)
		if WalkStopPlant.done(state) then WalkStopPlant.cancel(state) end

	The same machinery plants the feet under an attack (D-632; Studio item 511(c)). An attack clip
	is authored from the idle's stand and blends in over a few frames: over a walk (or a stand the
	clip moves a foot from) that blend swept each planted foot across the field from where it stood
	to where the clip has it, 0.25 to 0.51 a 60 Hz row and down to -0.08. In the anime a monster
	about to charge plants, digs in and lowers; its feet never skate. So when the clip comes in,
	each leg holds the field point it stood on (not the root's: the root may still be braking under
	it), and a leg that stood further than settleStuds from where the clip's first pose has it (at
	the clock the network catch-up started it on) digs in: one group at a time (every group but the
	lowest first), over stepSeconds of the clip's clock (its beat paces the dig-in, a hit-stop holds
	it), its sole liftStuds clear of the straight path at the step's middle, onto where the clip has
	the foot then. A leg that stood there already
	follows the clip from the start, gliding off what it stood away. Every leg hangs from its hip as
	the layers drew the body that step: it turns about the corner of its sole it stands on so the hip
	holds it (the body moves over a planted foot as the clip's own solve does), and is never drawn
	lower than that corner stood. The plant writes the hips over the composed pose
	(Mixer.setPoseHook), so the blend, the clip's beat and the body's own motion are what the step
	really drew. The field point is read on the root the row is drawn on: RigDriver carries the root
	it read on by its last row's move, braking (enemy.gait.attackBrakeShare, attackBrakeSeconds).

		WalkStopPlant.beginUnder(state, shownLastFrame, clipFirstPose, rootLastFrame)
		mixer:setPoseHook("attackPlant", function(pose)
			WalkStopPlant.stepUnder(state, clipAdvance, pose, clipPoseNow, rootThisRow)
		end)
		if WalkStopPlant.done(state) and not mixer:blendingIn(handle) then -- take the hook off

	And through a turn on the spot (D-665; Studio item 558): a boar turning with its idle showing
	swept its planted hooves round the root's axis, 0.057 a 60 Hz row and 0.114 under the PC's
	uneven yaw. In the anime a beast turning on the spot shuffles round on planted feet. So each
	leg holds its place on the field, hung from its hip, and the group standing furthest from the
	idle's spots steps there (one group at a time, as a stop's step) once the hip's twist passes a
	limit; once the root stands, the legs step home. A walk taking the rig has each group step onto
	where the walk has it, the one the walk has down first.

		WalkStopPlant.beginStand(state, shownLastFrame, rootLastFrame)
		local offsets = WalkStopPlant.stepStand(state, dt, basePose, idlePose, rootThisRow, limit, walking)
		if WalkStopPlant.standHome(state) (standing) or WalkStopPlant.standDone(state) (walking) then ... end
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Rigs = require(Shared.data.rigs)
local ClipSampler = require(Shared.choreo.ClipSampler)
local Pose = require(Shared.choreo.Pose)
local Easing = require(Shared.util.Easing)

local NOISE = 1e-9 -- unit: seconds, float noise in a sum of frame times
local SPACE_NOISE = 1e-9 -- unit: studs, float noise in a turn's axis or a corner's height

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
	attach: Vector3, -- where the hip hangs the leg, in the leg's own space
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
	-- Under an attack (beginUnder, D-632): per leg, where it stood on the field as the clip came
	-- in, and, for a leg that stood where the clip's first pose has it (within settleStuds), its
	-- offset from there (it follows the clip, gliding the offset off over stepSeconds).
	field: { CFrame },
	follows: { [number]: CFrame },
	-- A stop begun on the root its last row was drawn on (D-664): each leg holds `field`, its
	-- place on the field, not its place in the root's space, while that root comes to a stand.
	onField: boolean,
	-- A stand turn (beginStand, D-665): the group stepping (0: none), per leg where its step left
	-- the field, whether every leg stood on the idle's spot (within settleStuds) last step, and per
	-- group whether it has stepped onto the pose that took the rig (it is that pose's from then).
	stepping: number,
	from: { CFrame },
	home: boolean,
	released: { boolean },
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
				attach = hip.c1Inverse:Inverse().Position,
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
		field = {},
		follows = {},
		onField = false,
		stepping = 0,
		from = {},
		home = true,
		released = {},
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

-- A point turned about an axis through the origin (Rodrigues), for a leg turned about a corner.
local function turnAbout(pivot: Vector3, from: Vector3, to: Vector3): CFrame
	local axis = from:Cross(to)
	if axis.Magnitude <= SPACE_NOISE then
		return CFrame.identity
	end
	local angle = math.atan2(axis.Magnitude, from:Dot(to))
	return CFrame.new(pivot) * CFrame.fromAxisAngle(axis.Unit, angle) * CFrame.new(-pivot)
end

-- The leg at `frame` (root space) hung from its hip at `socket` (root space): turned about the
-- corner of its sole it stands on so the point its hip holds lies on the line from that corner to
-- the socket, as a rigid leg follows a body moving over its planted foot (the gap left along that
-- line is the joint's). The corner it stands on is the one no other comes lower than once it is
-- turned; where every turn sinks another, the leg is raised by the least sink.
local function hang(leg: Leg, frame: CFrame, socket: Vector3): CFrame
	local attach = frame * leg.attach
	local best = frame
	local bestSink = -math.huge
	for _, corner in leg.corners do
		local pivot = frame * corner
		local turned = turnAbout(pivot, attach - pivot, socket - pivot) * frame
		local low = math.huge
		for _, other in leg.corners do
			low = math.min(low, (turned * other).Y)
		end
		local sink = low - pivot.Y
		if sink > bestSink + SPACE_NOISE then
			best, bestSink = turned, sink
		end
	end
	if bestSink < 0 then
		best = CFrame.new(0, -bestSink, 0) * best
	end
	return best
end

--- Starts a stop: `shown` is the pose the rig showed on the last frame (every joint from the root
--- to the feet), `idle` the idle's pose now. Each leg holds where `shown` stood it; the groups'
--- steps are set in order (every group but the lowest, the highest first, then the lowest).
--- `root`, when given, is the root's CFrame the last frame was drawn on: each leg then holds its
--- place on the field (step reads it on the root each row is drawn on), so a drawn root still
--- coming to a stand carries the body over planted feet (D-664).
function WalkStopPlant.begin(state: State, shown: ClipSampler.Offsets, idle: ClipSampler.Offsets, root: CFrame?)
	local plan = state.plan
	local config = plan.config
	local height: { number } = {}
	local settled: { boolean } = {}
	for group = 1, plan.groups do
		height[group] = -math.huge
		settled[group] = true
	end
	state.onField = root ~= nil
	for index, leg in plan.legs do
		local held = legFrame(leg, shown)
		state.held[index] = held
		if root ~= nil then
			state.field[index] = root * held
		end
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
--- stands it), or nil when no stop is under way. A stop begun on a root (begin's `root`) reads its
--- held legs on `root`, the root's CFrame this step is drawn on, each hung from its hip as `base`
--- draws the body.
function WalkStopPlant.step(
	state: State,
	dt: number,
	base: ClipSampler.Offsets,
	idle: ClipSampler.Offsets,
	root: CFrame?
): ClipSampler.Offsets?
	if not state.active then
		return nil
	end
	state.clock += math.max(dt, 0)
	local plan = state.plan
	local config = plan.config
	local unroot = if state.onField and root ~= nil then root:Inverse() else nil
	for index, leg in plan.legs do
		local held = if unroot ~= nil then unroot * state.field[index] else state.held[index]
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
		if unroot ~= nil and progress < 1 - NOISE then
			frame = hang(leg, frame, parent * hip.c0.Position)
		end
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

-- Groups that step, highest first and the lowest last (the swinging foot lands, the body stands on
-- a group while another steps), each stepSeconds after the one before, from the stop's clock 0.
local function schedule(state: State, height: { number }, steps: { boolean })
	local plan = state.plan
	local steppers: { number } = {}
	for group = 1, plan.groups do
		state.starts[group] = 0
		if steps[group] and height[group] > -math.huge then
			table.insert(steppers, group)
		end
	end
	table.sort(steppers, function(a: number, b: number): boolean
		if height[a] ~= height[b] then
			return height[a] > height[b]
		end
		return a < b
	end)
	for slot, group in steppers do
		state.starts[group] = (slot - 1) * plan.config.stepSeconds
	end
	state.total = math.max(#steppers, 1) * plan.config.stepSeconds
end

--- Starts the plant under an attack clip (D-632): `shown` is the pose the rig showed on the last
--- frame, `root` the root part's CFrame it was drawn on, `first` the clip's first pose (where it
--- has the feet as it starts). Each leg holds the field point it stood on; a leg further than
--- settleStuds from the clip's first pose digs in, group by group (every group but the lowest
--- first); one that stood there follows the clip.
function WalkStopPlant.beginUnder(state: State, shown: ClipSampler.Offsets, first: ClipSampler.Offsets, root: CFrame)
	local plan = state.plan
	local height: { number } = {}
	local steps: { boolean } = {}
	for group = 1, plan.groups do
		height[group] = -math.huge
		steps[group] = false
	end
	table.clear(state.follows)
	for index, leg in plan.legs do
		local stood = legFrame(leg, shown)
		state.field[index] = root * stood
		local start = legFrame(leg, first)
		if ((stood * leg.sole) - (start * leg.sole)).Magnitude <= plan.config.settleStuds then
			state.follows[index] = start:Inverse() * stood
		else
			steps[leg.group] = true
			height[leg.group] = math.max(height[leg.group], lowest(plan, leg, stood))
		end
	end
	schedule(state, height, steps)
	state.clock = 0
	state.active = true
end

--- One step of `dt` seconds of the clip's clock under the attack (D-632). `pose`: the pose the
--- layers composed this step (Mixer.setPoseHook's), whose hips it sets; `clip`: the clip's own pose
--- now; `root`: the root part's CFrame this step is drawn on. A leg holds its field point until its group's step,
--- steps (lifted) onto where the clip has it, and then is the clip's; a leg that stood where the
--- clip starts is the clip's, less what it stood away gliding off. Each hangs from its hip as
--- `pose` draws the body. Nothing when no plant is under way.
function WalkStopPlant.stepUnder(
	state: State,
	dt: number,
	pose: ClipSampler.Offsets,
	clip: ClipSampler.Offsets,
	root: CFrame
)
	if not state.active then
		return
	end
	state.clock += math.max(dt, 0)
	local plan = state.plan
	local config = plan.config
	local unroot = root:Inverse()
	for index, leg in plan.legs do
		local lands = legFrame(leg, clip)
		local frame: CFrame
		local follow = state.follows[index]
		if follow ~= nil then
			local left = 1 - Easing.SineInOut(math.clamp(state.clock / config.stepSeconds, 0, 1))
			frame = lands * CFrame.new():Lerp(follow, left)
		else
			local held = unroot * state.field[index]
			local progress = (state.clock - state.starts[leg.group]) / config.stepSeconds
			if progress <= 0 then
				frame = held
			elseif progress >= 1 - NOISE then
				frame = lands
			else
				local eased = Easing.SineInOut(progress)
				frame = held:Lerp(lands, eased)
				local from, to = lowest(plan, leg, held), lowest(plan, leg, lands)
				local path = math.max(
					from + (to - from) * eased,
					math.min(from, to) + config.liftStuds * math.sin(math.pi * progress)
				)
				frame = CFrame.new(0, math.max(0, path - lowest(plan, leg, frame)), 0) * frame
			end
		end
		local hip = leg.path[#leg.path]
		local parent = frameOf(leg, pose, #leg.path - 1)
		frame = hang(leg, frame, parent * hip.c0.Position)
		local transform = hip.c0:Inverse() * parent:Inverse() * frame * hip.c1Inverse:Inverse()
		local rx, ry, rz = transform:ToEulerAnglesXYZ()
		local at = transform.Position
		pose[leg.joint] = { pos = { at.X, at.Y, at.Z }, rot = { math.deg(rx), math.deg(ry), math.deg(rz) } }
	end
end

--- Starts a stand turn (D-665): the root turns on the spot with the idle showing. `shown` is
--- the pose the rig showed on the last frame, `root` the root's CFrame it was drawn on: every leg
--- holds its place on the field.
function WalkStopPlant.beginStand(state: State, shown: ClipSampler.Offsets, root: CFrame)
	for index, leg in state.plan.legs do
		state.field[index] = root * legFrame(leg, shown)
	end
	state.stepping = 0
	state.clock = 0
	state.home = false
	table.clear(state.released)
	state.active = true
end

--- One step of a stand turn of `dt` seconds. `base`: the pose the layers compose this step, whose
--- hips it sets; `idle`: the idle's pose now; `root`: the root's CFrame this step is drawn on. Each
--- leg holds its field point, hung from its hip; while no group steps, the group standing furthest
--- from where the idle has it steps there (lifted, as a stop's step) once that is past `limit` (the
--- hip's twist while the root turns, settleStuds once it stands). `release`: a walk took the rig, so
--- the groups step onto where `base` has them instead, the one `base` stands lowest first, each
--- following `base` once down (standDone then). Returns each hip's offset over `base`, or nil when
--- no stand turn is under way.
function WalkStopPlant.stepStand(
	state: State,
	dt: number,
	base: ClipSampler.Offsets,
	idle: ClipSampler.Offsets,
	root: CFrame,
	limit: number,
	release: boolean
): ClipSampler.Offsets?
	if not state.active then
		return nil
	end
	local plan = state.plan
	local config = plan.config
	local unroot = root:Inverse()
	local target = if release then base else idle
	if state.stepping ~= 0 then
		state.clock += math.max(dt, 0)
		if state.clock >= config.stepSeconds - NOISE then
			-- Down where it stepped to: on the idle's spot it holds the field there; on the pose
			-- that took the rig it is that pose's.
			for index, leg in plan.legs do
				if leg.group == state.stepping then
					state.field[index] = root * legFrame(leg, target)
				end
			end
			if release then
				state.released[state.stepping] = true
			end
			state.stepping = 0
		end
	end
	local worst, worstGroup = 0, 0
	local lowestOn, lowestGroup = -math.huge, 0
	for index, leg in plan.legs do
		if state.released[leg.group] then
			continue
		end
		local off = ((unroot * state.field[index]) * leg.sole - legFrame(leg, idle) * leg.sole).Magnitude
		if off > worst then
			worst, worstGroup = off, leg.group
		end
		local down = -lowest(plan, leg, legFrame(leg, base))
		if down > lowestOn then
			lowestOn, lowestGroup = down, leg.group
		end
	end
	state.home = state.stepping == 0 and worst <= config.settleStuds
	local stepper = if release
		then lowestGroup
		else (if worst > math.max(limit, config.settleStuds) then worstGroup else 0)
	if state.stepping == 0 and stepper ~= 0 then
		state.stepping = stepper
		state.clock = 0
		for index, leg in plan.legs do
			if leg.group == stepper then
				state.from[index] = state.field[index]
			end
		end
	end
	for index, leg in plan.legs do
		local frame = unroot * state.field[index]
		local stepping = leg.group == state.stepping
		local released = state.released[leg.group] == true
		if released then
			frame = legFrame(leg, base)
		elseif stepping then
			local held = unroot * state.from[index]
			local lands = legFrame(leg, target)
			local progress = math.clamp(state.clock / config.stepSeconds, 0, 1)
			local eased = Easing.SineInOut(progress)
			frame = held:Lerp(lands, eased)
			local from, to = lowest(plan, leg, held), lowest(plan, leg, lands)
			local path = math.max(
				from + (to - from) * eased,
				math.min(from, to) + config.liftStuds * math.sin(math.pi * progress)
			)
			frame = CFrame.new(0, math.max(0, path - lowest(plan, leg, frame)), 0) * frame
		end
		local hip = leg.path[#leg.path]
		local parent = frameOf(leg, base, #leg.path - 1)
		if not stepping and not released then
			frame = hang(leg, frame, parent * hip.c0.Position)
		end
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

--- True once a released stand turn's every group has stepped onto the pose that took the rig.
function WalkStopPlant.standDone(state: State): boolean
	for group = 1, state.plan.groups do
		if not state.released[group] then
			return false
		end
	end
	return true
end

--- True when a stand turn's legs all stood on the idle's spots (within settleStuds) with none
--- stepping on its last step.
function WalkStopPlant.standHome(state: State): boolean
	return state.home
end

return WalkStopPlant
