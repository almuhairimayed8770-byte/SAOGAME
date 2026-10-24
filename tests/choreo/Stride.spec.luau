--!strict
--[[
	Stride: a planted foot holds the ground (section 10 Locomotion: the blend space and the
	two-step stop). Everything is measured on the hit matrix's player (HitMatrix.standing, the
	engine's blank-avatar R15 on the Playground field) at locomotion.stride.measureHz, legs only.
	A foot is in contact while its lowest corner is within stride.contact of the field's top. Each
	Footstep belongs to the contact of its foot that holds it, or else the first one after it.
	From the Footstep on, the contact is the plant: its slide is the farthest the contact corner
	gets from where it was at the Footstep. Before the Footstep, and in a contact that holds no
	Footstep, the foot is still swinging (a toe or heel scraping the field): that is drag, the
	farthest the corner gets from its touchdown.

	1. data/choreo.luau stride.groundSpeed is re-measured from every gait clip: the regression
	   slope of the planted corner's travel over each plant, the root standing still; and
	   stride.touchdown, where each clip has each foot at its Footstep (an Idle at its start).
	2. The stride data is self-consistent (rates, floors, bars, the stop's numbers).
	3. The clean clips (CLEAN: every walk) plant and swing under slideBar at that speed, and every
	   gait clip plants and swings within transientBar: a swing meets the field only at its plant.
	4. Paced: the real Locomotion and Choreo animator on a Lune rig whose root moves at a set
	   speed, the mixer's offsets posing the body every frame. A clip paced to its own ground
	   speed slides at any pace as it does at rate 1, so a steady case may slide, and drag, no
	   more than the worst clip it shows does at its own ground speed, plus slideBar: a lone clip
	   at any pace, Guard at walkSpeed, the four diagonals at walk speeds. Moving straight back
	   every plant and swing stays under slideBar. A change of gait (the set crossfade, a start
	   from standing, the two-step stop wherever in the stride the stick lets go, and its
	   hand-over to Idle) holds its plants within transientBar. Every case also checks one
	   Footstep per plant (D-051).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function fakeSignal()
	local signal = {}
	function signal:Connect()
		return { Disconnect = function() end }
	end
	return signal
end
Harness.stubService("RunService", {
	RenderStepped = fakeSignal(),
	Heartbeat = fakeSignal(),
	PreSimulation = fakeSignal(),
	-- Choreo's rig step (bound just before the camera's): the spec steps the rigs itself.
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
Choreo.configure({
	now = function()
		return 0
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local LocomotionState = Harness.load("src/client/choreo/LocomotionState")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")

local Config = ChoreoData.locomotion
-- Read through `any` so a build without the stride table fails each test, not the whole file.
local Stride: any = (Config :: any).stride

local root = Harness.repoRoot()
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end
local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")

local FEET = { "LeftFoot", "RightFoot" }
local LEG_PARTS = {
	LowerTorso = true,
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
}

-- Gait clips that plant and swing under slideBar on their own: every walk. Run and Sprint still
-- carry a little authored slide (a stance foot that speeds up and slows down, a toe that touches
-- before its Footstep), never more than transientBar; pacing adds no more than slideBar to it.
local CLEAN = {
	"WalkForward",
	"WalkBack",
	"WalkLeft",
	"WalkRight",
	"WalkForwardDrawn",
	"WalkBackDrawn",
	"WalkLeftDrawn",
	"WalkRightDrawn",
}

type Body = {
	model: any,
	base: any, -- the root's CFrame standing on the field
	fieldTop: number,
	chain: any, -- legs only: the feet are all this measures
	corners: { [string]: { any } }, -- each foot's eight corners in its own frame
	footLength: number,
	forward: any,
	right: any,
}

local cachedBody: Body? = nil
local function body(): Body
	if cachedBody == nil then
		local avatar, field = HitMatrix.standing(Harness)
		local half = field.Size * 0.5
		local frame = field.CFrame
		local fieldTop = frame.Position.Y
			+ math.abs(frame.RightVector.Y) * half.X
			+ math.abs(frame.UpVector.Y) * half.Y
			+ math.abs(frame.LookVector.Y) * half.Z
		local full = Pose.chain(avatar.model)
		local links = {}
		for _, link in full.links do
			if LEG_PARTS[link.part1] then
				table.insert(links, link)
			end
		end
		local corners = {}
		local footLength = 0
		for _, foot in FEET do
			local size = avatar.model:FindFirstChild(foot).Size
			footLength = math.max(footLength, size.Z)
			local half = size * 0.5
			local list = {}
			for _, x in { -1, 1 } do
				for _, y in { -1, 1 } do
					for _, z in { -1, 1 } do
						table.insert(list, Vector3.new(x * half.X, y * half.Y, z * half.Z))
					end
				end
			end
			corners[foot] = list
		end
		cachedBody = {
			model = avatar.model,
			base = avatar.base,
			fieldTop = fieldTop,
			chain = { rootName = full.rootName, links = links },
			corners = corners,
			footLength = footLength,
			forward = avatar.base.LookVector,
			right = avatar.base.RightVector,
		}
	end
	return cachedBody :: Body
end

-- A solved foot's eight corners in world space, the lowest one's index and its height above the
-- field.
local function footCorners(solved: any, foot: string): ({ any }, number, number)
	local shape = body()
	local frame = solved[foot]
	local points = {}
	local low, lowIndex = math.huge, 1
	for index, corner in shape.corners[foot] do
		local point = frame:PointToWorldSpace(corner)
		points[index] = point
		if point.Y < low then
			low, lowIndex = point.Y, index
		end
	end
	return points, lowIndex, low - shape.fieldTop
end

-- ------------------------------------------------------------------ one clip at rate 1

type Sample = { height: number, move: any } -- move: the contact corner's horizontal step, root still
-- A contact in one clip cycle (sample indices wrap): `plant` samples from touchdown to the
-- Footstep (nil for a contact that holds no Footstep).
type Stance = { foot: string, first: number, count: number, plant: number? }

local function gaitClip(name: string): any
	return ClipLibrary.get(Config.clipPrefix .. Config.clips[name])
end

-- The axis a gait clip's root travels along (its planted foot moves the other way).
local function travelAxis(name: string): any
	local shape = body()
	local plain = name:gsub("Drawn$", "")
	if plain == "WalkBack" then
		return -shape.forward
	elseif plain == "WalkLeft" then
		return -shape.right
	elseif plain == "WalkRight" then
		return shape.right
	end
	return shape.forward
end

-- One cycle of a clip at measureHz with the root standing still: per foot and sample, the lowest
-- corner's height and how far that corner moved since the sample before.
local function profile(clip: any): { [string]: { Sample } }
	local shape = body()
	local count = math.floor(clip.duration * Stride.measureHz + 0.5)
	local samples: { [string]: { Sample } } = { LeftFoot = {}, RightFoot = {} }
	local previous: { [string]: { any } } = {}
	for index = -1, count - 1 do -- a lap of one sample first, so the first one has a previous
		local t = (index % count) / Stride.measureHz
		local solved = Pose.solve(shape.model, shape.base, ClipSampler.sample(clip, t), shape.chain)
		for _, foot in FEET do
			local points, lowIndex, height = footCorners(solved, foot)
			if index >= 0 then
				local step = points[lowIndex] - previous[foot][lowIndex]
				table.insert(samples[foot], { height = height, move = Vector3.new(step.X, 0, step.Z) })
			end
			previous[foot] = points
		end
	end
	return samples
end

-- Every contact of a clip cycle: the one that holds each Footstep (or the first after it), with
-- the samples from its touchdown to that Footstep, and every contact that holds none.
local function clipStances(clip: any, samples: { [string]: { Sample } }): { Stance }
	local stances: { Stance } = {}
	local stepped: { [string]: { [number]: boolean } } = { LeftFoot = {}, RightFoot = {} }
	for _, event in clip.events do
		if event.kind ~= "Footstep" then
			continue
		end
		local foot = event.data.foot .. "Foot"
		local list = samples[foot]
		local count = #list
		local planted = function(index: number): boolean
			return list[(index - 1) % count + 1].height <= Stride.contact
		end
		local at = math.floor(event.time * Stride.measureHz + 0.5) % count + 1
		local first = at
		if planted(at) then
			while planted(first - 1) and at - first < count do
				first -= 1
			end
		else
			while not planted(first) and first - at < count do
				first += 1
			end
		end
		local length = 0
		while planted(first + length) and length < count do
			length += 1
		end
		if length > 0 then
			local start = (first - 1) % count + 1
			table.insert(stances, { foot = foot, first = start, count = length, plant = math.max(0, at - first) })
			stepped[foot][start] = true
		end
	end
	for _, foot in FEET do
		local list = samples[foot]
		local count = #list
		local planted = function(index: number): boolean
			return list[(index - 1) % count + 1].height <= Stride.contact
		end
		for index = 1, count do
			if planted(index) and not planted(index - 1) and not stepped[foot][index] then
				local length = 0
				while planted(index + length) and length < count do
					length += 1
				end
				table.insert(stances, { foot = foot, first = index, count = length, plant = nil })
			end
		end
	end
	return stances
end

-- The contact corner's travel from touchdown, sample by sample (index 1 at touchdown).
local function stanceTrack(samples: { [string]: { Sample } }, stance: Stance): { any }
	local list = samples[stance.foot]
	local count = #list
	local track = { Vector3.zero }
	local sum = Vector3.zero
	for step = 1, stance.count - 1 do
		sum += list[(stance.first + step - 1) % count + 1].move
		table.insert(track, sum)
	end
	return track
end

-- Ground speed: the regression slope of the planted corner's backward travel against time,
-- pooled over the plants (from each Footstep to lift-off, each with its own intercept).
local function measuredGroundSpeed(name: string): number
	local clip = gaitClip(name)
	local samples = profile(clip)
	local axis = travelAxis(name)
	local dt = 1 / Stride.measureHz
	local num, den = 0, 0
	for _, stance in clipStances(clip, samples) do
		local from = stance.plant
		if from == nil then
			continue
		end
		local track = stanceTrack(samples, stance)
		local meanT, meanA, n = 0, 0, 0
		for step = from + 1, #track do
			meanT += (step - 1) * dt
			meanA += track[step]:Dot(axis)
			n += 1
		end
		if n < 2 then
			continue
		end
		meanT /= n
		meanA /= n
		for step = from + 1, #track do
			local t = (step - 1) * dt - meanT
			num += t * (track[step]:Dot(axis) - meanA)
			den += t * t
		end
	end
	return if den > 0 then -num / den else 0
end

type Own = { plant: number, drag: number }

-- A clip's own slide with the root moving at its data ground speed: its worst plant and its worst
-- drag (before a Footstep, or in a contact without one).
local owns: { [string]: Own } = {}
local function own(name: string): Own
	local cached = owns[name]
	if cached ~= nil then
		return cached
	end
	local clip = gaitClip(name)
	local samples = profile(clip)
	local carry = travelAxis(name) * (Stride.groundSpeed[name] / Stride.measureHz)
	local result: Own = { plant = 0, drag = 0 }
	for _, stance in clipStances(clip, samples) do
		local from = stance.plant
		local track = stanceTrack(samples, stance)
		local base: any = nil
		for step, point in track do
			local ground = point + carry * (step - 1)
			if from ~= nil and step - 1 >= from then
				if base == nil then
					base = ground
				end
				result.plant = math.max(result.plant, (ground - base).Magnitude)
			else
				result.drag = math.max(result.drag, ground.Magnitude)
			end
		end
	end
	owns[name] = result
	return result
end

local GAIT_NAMES = {}
for _, set in { "", "Drawn" } do
	for _, gait in { "WalkForward", "WalkBack", "WalkLeft", "WalkRight", "Run", "Sprint" } do
		table.insert(GAIT_NAMES, gait .. set)
	end
end

-- Where a clip has each foot (studs from the root: forward, right): a gait clip at that foot's
-- Footstep, an Idle at its start. The foot part's centre, root standing still.
local function measuredTouchdown(name: string): { [string]: { number } }
	local shape = body()
	local clip = ClipLibrary.get(Config.clipPrefix .. Config.clips[name])
	local spots: { [string]: { number } } = {}
	for _, foot in FEET do
		local at = 0
		for _, event in clip.events do
			if event.kind == "Footstep" and event.data.foot .. "Foot" == foot then
				at = event.time
				break
			end
		end
		local solved = Pose.solve(shape.model, shape.base, ClipSampler.sample(clip, at), shape.chain)
		local offset = solved[foot].Position - shape.base.Position
		spots[foot] = { offset:Dot(shape.forward), offset:Dot(shape.right) }
	end
	return { left = spots.LeftFoot, right = spots.RightFoot }
end

-- ------------------------------------------------------------------ paced on a Lune rig

local function buildRig(): any
	local model = Instance.new("Model")
	model.Name = "PlayerR15"
	model:SetAttribute("Rig", "PlayerR15")
	local parts = {}
	local function part(name: string): any
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Position = Vector3.zero
		created.Parent = model
		parts[name] = created
		return created
	end
	for _, joint in Rigs.PlayerR15.joints do
		part(joint.part0)
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Parent = part(joint.part1)
	end
	model.PrimaryPart = parts.HumanoidRootPart
	return model
end

type Case = {
	direction: any, -- unit move in the body's frame (the body faces forward)
	-- The root's speed this frame; it may read the rig's Locomotion (the two-step stop does).
	speed: (t: number, dt: number, locomotion: any) -> number,
	drawn: (t: number) -> boolean,
	moving: ((t: number) -> boolean)?, -- the stick is held (default: speed > 0)
	sprinting: boolean?,
	duration: number,
	measureFrom: number,
	measureTo: number?,
	start: ((animator: any) -> ())?,
	-- A body held off its stick (D-144): the root's velocity (world, studs a second) moves it in
	-- place of direction x speed, with the stick (default `direction`) held while `moving`. The
	-- velocity reaches Locomotion in the state, or with `readRoot` on the root part (the local
	-- controller gives none).
	velocity: ((t: number) -> any)?,
	stick: any?,
	readRoot: boolean?,
}

type TrackSample = { t: number, net: any }

type Contact = {
	foot: string,
	start: number,
	finish: number,
	net: any,
	track: { TrackSample },
	steps: { number },
}

type Result = {
	slide: number, -- the worst plant's slide from its Footstep
	drag: number, -- the worst slide before a Footstep or in a contact without one
	plants: number,
	doubled: number, -- contacts that hold two Footsteps of their foot
	steps: { number }, -- every Footstep's time
	shown: { [string]: number }, -- the most each gait clip showed while measuring
	contacts: { Contact },
}

local function simulate(case: Case): Result
	local shape = body()
	local model = buildRig()
	local animator: any = Choreo.get(model)
	local locomotion = Locomotion.new(animator, model, { footIK = false }) :: any
	local footsteps: { { foot: string, t: number } } = {}
	local now = 0
	local connection = animator.events:Connect(function(_clipId: string, event: any)
		if event.kind == "Footstep" then
			table.insert(footsteps, { foot = event.data.foot .. "Foot", t = now })
		end
	end)
	if case.start ~= nil then
		case.start(animator)
	end
	local dt = 1 / Stride.measureHz
	local position = Vector3.zero
	local open: { [string]: Contact? } = {}
	local previous: { [string]: { any } } = {}
	local contacts: { Contact } = {}
	local shown: { [string]: number } = {}
	local measureTo = case.measureTo or case.duration
	for frame = 1, math.floor(case.duration * Stride.measureHz + 0.5) do
		local t = frame * dt
		now = t
		local speed = case.speed(t, dt, locomotion)
		local velocity = if case.velocity ~= nil then case.velocity(t) else case.direction * speed
		position += velocity * dt
		model.PrimaryPart.CFrame = CFrame.new(position)
		local held = if case.moving ~= nil then case.moving(t) else speed > 0
		local state: any = {
			moveDir = if held then case.stick or case.direction else Vector3.zero,
			speed = speed,
			sprinting = case.sprinting == true,
			grounded = true,
			drawn = case.drawn(t),
			turning = 0,
			verticalVelocity = 0,
		}
		if case.velocity ~= nil then
			if case.readRoot then
				model.PrimaryPart.AssemblyLinearVelocity = velocity
			else
				state.velocity = velocity
			end
		end
		locomotion:update(dt, state)
		animator:step(dt)
		if t >= case.measureFrom and t <= measureTo then
			for _, name in GAIT_NAMES do
				local handle = locomotion.handles[name]
				shown[name] = math.max(shown[name] or 0, handle.weight * handle.fade)
			end
		end
		local rootFrame = CFrame.new(shape.base.Position + position)
		local solved = Pose.solve(shape.model, rootFrame, animator.mixer:lastOffsets(), shape.chain)
		for _, foot in FEET do
			local points, lowIndex, height = footCorners(solved, foot)
			local contact = open[foot]
			if height <= Stride.contact then
				if contact == nil then
					open[foot] = {
						foot = foot,
						start = t,
						finish = t,
						net = Vector3.zero,
						track = { { t = t, net = Vector3.zero } },
						steps = {},
					}
				elseif previous[foot] ~= nil then
					-- The corner that is lowest now, against where that same corner was last frame.
					local moved = points[lowIndex] - previous[foot][lowIndex]
					contact.net += Vector3.new(moved.X, 0, moved.Z)
					contact.finish = t
					table.insert(contact.track, { t = t, net = contact.net })
				end
			elseif contact ~= nil then
				table.insert(contacts, contact)
				open[foot] = nil
			end
			previous[foot] = points
		end
	end
	for _, contact in open do
		table.insert(contacts, contact :: Contact)
	end
	connection:Disconnect()
	locomotion:destroy()
	Choreo.release(model)
	-- Each Footstep belongs to the first contact of its foot that has not ended by then.
	table.sort(contacts, function(a: Contact, b: Contact): boolean
		return a.start < b.start
	end)
	local stepTimes = {}
	for _, step in footsteps do
		table.insert(stepTimes, step.t)
		for _, contact in contacts do
			if contact.foot == step.foot and contact.finish >= step.t then
				table.insert(contact.steps, step.t)
				break
			end
		end
	end
	local result: Result = {
		slide = 0,
		drag = 0,
		plants = 0,
		doubled = 0,
		steps = stepTimes,
		shown = shown,
		contacts = contacts,
	}
	for _, contact in contacts do
		-- A contact counts by when its plant starts (its touchdown when it has no Footstep).
		local plantFrom = if #contact.steps > 0 then math.max(contact.start, contact.steps[1]) else math.huge
		local counted = if #contact.steps > 0 then plantFrom else contact.start
		if counted < case.measureFrom or counted > measureTo then
			continue
		end
		local base: any = nil
		for _, sample in contact.track do
			if sample.t >= plantFrom - 1e-9 then
				base = base or sample.net
				result.slide = math.max(result.slide, (sample.net - base).Magnitude)
			else
				result.drag = math.max(result.drag, sample.net.Magnitude)
			end
		end
		if #contact.steps > 0 then
			result.plants += 1
			if #contact.steps > 1 then
				result.doubled += 1
			end
		end
	end
	return result
end

-- The most any contact moves from `from` to `to` (the feet once the root has stopped).
local function stillSlide(result: Result, from: number, to: number): number
	local worst = 0
	for _, contact in result.contacts do
		local base: any = nil
		for _, sample in contact.track do
			if sample.t >= from and sample.t <= to then
				base = base or sample.net
				worst = math.max(worst, (sample.net - base).Magnitude)
			end
		end
	end
	return worst
end

-- The worst own plant and drag of the gait clips a case showed.
local function owned(result: Result): (number, number)
	local plant, drag = 0, 0
	for name, weight in result.shown do
		if weight > 0.05 then
			plant = math.max(plant, own(name).plant)
			drag = math.max(drag, own(name).drag)
		end
	end
	return plant, drag
end

-- A steady move, measured from 1.5 s (the weights have settled) for at least 4 studs of travel.
local function steady(direction: any, speed: number, drawn: boolean, sprinting: boolean?): Case
	return {
		direction = direction,
		speed = function(): number
			return speed
		end,
		drawn = function(): boolean
			return drawn
		end,
		sprinting = sprinting,
		duration = 1.5 + math.max(1.5, 4 / speed),
		measureFrom = 1.5,
	}
end

local function forward(): any
	return body().forward
end

-- Notes what is wrong with a case's plants: none, one sliding past `plantLimit`, a swing
-- dragging past `dragLimit` (nil: not checked), a doubled Footstep.
local function checkPlants(problems: { string }, label: string, result: Result, plantLimit: number, dragLimit: number?)
	if result.plants == 0 then
		table.insert(problems, label .. ": no plant")
	elseif result.slide > plantLimit then
		table.insert(problems, ("%s: slid %.3f, limit %.3f"):format(label, result.slide, plantLimit))
	end
	if dragLimit ~= nil and result.drag > dragLimit then
		table.insert(problems, ("%s: dragged %.3f, limit %.3f"):format(label, result.drag, dragLimit))
	end
	if result.doubled > 0 then
		table.insert(problems, ("%s: %d plants with two Footsteps"):format(label, result.doubled))
	end
end

-- A steady case: no more than its clips' own slide and drag, plus slideBar.
local function checkBounded(problems: { string }, label: string, result: Result)
	local plant, drag = owned(result)
	checkPlants(problems, label, result, plant + Stride.slideBar, drag + Stride.slideBar)
end

-- A change of gait: its plants within transientBar (or its clips' own slide plus slideBar, if
-- more), its swing within its clips' own drag plus slideBar (`withDrag` false: not checked).
local function checkTransient(problems: { string }, label: string, result: Result, withDrag: boolean?)
	local plant, drag = owned(result)
	checkPlants(
		problems,
		label,
		result,
		math.max(Stride.transientBar, plant + Stride.slideBar),
		if withDrag == false then nil else drag + Stride.slideBar
	)
end

local function drawnLabel(drawn: boolean): string
	return if drawn then "drawn" else "sheathed"
end

local function always(value: boolean): (t: number) -> boolean
	return function(): boolean
		return value
	end
end

-- ------------------------------------------------------------------ specs

describe("gait clips on the posed body", function()
	it("each gait clip's measured ground speed matches data/choreo.luau stride.groundSpeed", function()
		local problems = {}
		for _, name in GAIT_NAMES do
			local measured = measuredGroundSpeed(name)
			if math.abs(measured - Stride.groundSpeed[name]) > Stride.groundSpeedTolerance then
				table.insert(problems, ("%s measures %.3f, data %.3f"):format(name, measured, Stride.groundSpeed[name]))
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("each clip's feet are where data/choreo.luau stride.touchdown has them", function()
		local problems = {}
		local names = table.clone(GAIT_NAMES)
		table.insert(names, "Idle")
		table.insert(names, "IdleDrawn")
		for _, name in names do
			local measured = measuredTouchdown(name)
			local row = Stride.touchdown[name]
			for _, side in { "left", "right" } do
				local spot, data = measured[side], if row ~= nil then row[side] else nil
				if
					data == nil
					or math.abs(spot[1] - data[1]) > Stride.touchdownTolerance
					or math.abs(spot[2] - data[2]) > Stride.touchdownTolerance
				then
					table.insert(problems, ("%s %s measures { %.3f, %.3f }"):format(name, side, spot[1], spot[2]))
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("the stride data holds together", function()
		local problems = {}
		local function need(ok: boolean, what: string)
			if not ok then
				table.insert(problems, what)
			end
		end
		need(Stride.rateFloor > 0 and Stride.rateFloor < 1, "0 < rateFloor < 1")
		need(Stride.rateCeiling > 1, "rateCeiling > 1")
		need(Stride.minGroundSpeed > 0, "minGroundSpeed > 0")
		need(Config.stopStepsSeconds > 0, "stopStepsSeconds > 0")
		need(Config.stopMinCycles >= 0 and Config.stopMinCycles < 0.5, "0 <= stopMinCycles < half a cycle")
		-- The bar stays under one 60 Hz frame of travel at a walk, so a plant reads as planted.
		need(
			Stride.slideBar <= Config.walkSpeed * ChoreoData.frameSeconds,
			"slideBar under a frame of travel at walkSpeed"
		)
		need(Stride.transientBar >= Stride.slideBar, "transientBar >= slideBar")
		-- A change of gait may pivot the foot, never skate it: under a third of the foot's length.
		need(Stride.transientBar <= body().footLength / 3, "transientBar under a third of the foot's length")
		-- A ground speed off by the tolerance adds at most half the bar over the longest plant.
		local longest, fastestWalk = 0, 0
		for _, name in GAIT_NAMES do
			longest = math.max(longest, gaitClip(name).duration)
			if not name:find("Run") and not name:find("Sprint") then
				fastestWalk = math.max(fastestWalk, Stride.groundSpeed[name])
			end
		end
		need(
			Stride.groundSpeedTolerance * longest <= Stride.slideBar / 2,
			"groundSpeedTolerance x a cycle <= slideBar / 2"
		)
		-- The stop slows down no further than where every walk still shows alone (Idle takes
		-- weight below rateFloor x the walk's ground speed), and stays a slow-down.
		need(Config.stopEndSpeed > Stride.rateFloor * fastestWalk, "stopEndSpeed above the walks' Idle band")
		need(Config.stopEndSpeed < Config.walkSpeed, "stopEndSpeed < walkSpeed")
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("the clean clips plant and swing under slideBar at their ground speed", function()
		local problems = {}
		for _, name in CLEAN do
			local result = own(name)
			if result.plant > Stride.slideBar or result.drag > Stride.slideBar then
				table.insert(problems, ("%s slides %.3f, drags %.3f"):format(name, result.plant, result.drag))
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("every gait clip plants and swings within transientBar at its ground speed", function()
		-- Pacing keeps a clip's own slide at any speed and time scale (D-127), so a swing that
		-- scrapes the field before its Footstep shows at every step: a slowed capture and the
		-- lock-on forward walk read it as a skate.
		local problems = {}
		for _, name in GAIT_NAMES do
			local result = own(name)
			if result.plant > Stride.transientBar or result.drag > Stride.transientBar then
				table.insert(problems, ("%s slides %.3f, drags %.3f"):format(name, result.plant, result.drag))
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)
end)

describe("paced to the root's speed (Locomotion and the animator at measureHz)", function()
	it("moving straight back, both sets, from a slow walk to walkSpeed: every plant under slideBar", function()
		local problems = {}
		for _, drawn in { false, true } do
			for _, speed in { 1, 3, 5, Config.walkSpeed } do
				local label = ("back %s at %.1f"):format(drawnLabel(drawn), speed)
				local result = simulate(steady(-forward(), speed, drawn))
				checkPlants(problems, label, result, Stride.slideBar, Stride.slideBar)
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("a gait clip shown alone plants as at its own ground speed at any pace in its range", function()
		local shape = body()
		local cases = {
			{ name = "WalkForward", direction = shape.forward, speeds = { 1, 2, 3 } },
			{ name = "WalkRight", direction = shape.right, speeds = { 1, 2, 3, 4 } },
			{ name = "WalkLeft", direction = -shape.right, speeds = { 2, Config.walkSpeed } },
			{ name = "WalkForwardDrawn", direction = shape.forward, speeds = { 1, 3 } },
			{ name = "WalkRightDrawn", direction = shape.right, speeds = { 1, Config.walkSpeed } },
			{ name = "WalkLeftDrawn", direction = -shape.right, speeds = { 3, 6 } },
			{ name = "Run", direction = shape.forward, speeds = { Stride.groundSpeed.Run, Config.runSpeed + 2 } },
			{ name = "RunDrawn", direction = shape.forward, speeds = { Stride.groundSpeed.RunDrawn, Config.runSpeed } },
			{ name = "Sprint", direction = shape.forward, speeds = { Config.sprintSpeed, 26 }, sprinting = true },
			{ name = "SprintDrawn", direction = shape.forward, speeds = { Config.sprintSpeed, 26 }, sprinting = true },
		}
		local problems = {}
		for _, row in cases do
			local drawn = row.name:match("Drawn$") ~= nil
			for _, speed in row.speeds do
				local label = ("%s at %.2f"):format(row.name, speed)
				local result = simulate(steady(row.direction, speed, drawn, row.sprinting))
				if (result.shown[row.name] or 0) < 0.99 then
					table.insert(problems, ("%s: not alone (%.2f)"):format(label, result.shown[row.name] or 0))
				end
				local mine = own(row.name)
				checkPlants(problems, label, result, mine.plant + Stride.slideBar, mine.drag + Stride.slideBar)
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("Guard at walkSpeed: the drawn walk under the Guard clip", function()
		local result = simulate({
			direction = forward(),
			speed = function(): number
				return Config.walkSpeed
			end,
			drawn = always(true),
			duration = 4,
			measureFrom = 1.5,
			start = function(animator: any)
				animator:play(Config.clipPrefix .. "Guard")
			end,
		})
		local problems = {}
		checkBounded(problems, "Guard at walkSpeed", result)
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("the four diagonals, both sets, at walk speeds: the planted foot follows the move", function()
		local shape = body()
		local problems = {}
		for _, drawn in { false, true } do
			for degrees = 45, 315, 90 do
				local radians = math.rad(degrees)
				local f, r = math.cos(radians), math.sin(radians)
				local direction = (shape.forward * f + shape.right * r).Unit
				-- Up to the speed at which the walk blend shows alone at its natural cadence.
				local weights = LocomotionState.walkWeights(f, r, drawn)
				local along = LocomotionState.walkGait(weights, f, r, drawn)
				for _, speed in { along * 0.6, along } do
					local label = ("diagonal %d %s at %.2f"):format(degrees, drawnLabel(drawn), speed)
					-- The plants only: a blend's swing scrapes where its clips' do (each clip's
					-- drag is held above), a little more where two dips overlap.
					local result = simulate(steady(direction, speed, drawn))
					checkPlants(problems, label, result, owned(result) + Stride.slideBar, nil)
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("a lock-on strafe at walkSpeed, square and a little off, both sets: plants as the forward walk's", function()
		-- The facing held to a lock (D-112: turning 0, a slow yaw) while the stick strafes at the
		-- walk speed the lock holds the body to. The lock turn lags a moving target, so the move
		-- is a few degrees off square as often as on it.
		local shape = body()
		local problems = {}
		for _, drawn in { false, true } do
			local walk = simulate(steady(shape.forward, Config.walkSpeed, drawn))
			for _, degrees in { 88, 90, 92, 268, 270, 272 } do
				local radians = math.rad(degrees)
				local direction = (shape.forward * math.cos(radians) + shape.right * math.sin(radians)).Unit
				local label = ("strafe %d %s at %.1f"):format(degrees, drawnLabel(drawn), Config.walkSpeed)
				local result = simulate(steady(direction, Config.walkSpeed, drawn))
				local _, drag = owned(result)
				checkPlants(problems, label, result, walk.slide, drag + Stride.slideBar)
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("a lock-on forward walk at walkSpeed, square and a little off, both sets: within transientBar", function()
		-- The lock holds the body to walkSpeed with the facing on the target (D-112), so the
		-- forward walk blends with Run by cadence, and a stick a few degrees off the facing adds a
		-- side walk's share (D-129). Every plant and swing holds the ground.
		local shape = body()
		local problems = {}
		for _, drawn in { false, true } do
			for _, degrees in { 0, 3, 8, 352, 357 } do
				local radians = math.rad(degrees)
				local direction = (shape.forward * math.cos(radians) + shape.right * math.sin(radians)).Unit
				local label = ("forward %d %s at %.1f"):format(degrees, drawnLabel(drawn), Config.walkSpeed)
				local result = simulate(steady(direction, Config.walkSpeed, drawn))
				checkPlants(problems, label, result, Stride.transientBar, Stride.transientBar)
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("the set crossfade mid-walk and mid-run, either way, wherever in the stride it lands", function()
		local problems = {}
		for _, speed in { Config.walkSpeed, Config.runSpeed } do
			for _, toDrawn in { true, false } do
				for step = 0, 5 do
					local switch = 1.5 + step * 0.1
					local result = simulate({
						direction = forward(),
						speed = function(): number
							return speed
						end,
						drawn = function(t: number): boolean
							return if t >= switch then toDrawn else not toDrawn
						end,
						duration = switch + 0.8,
						measureFrom = switch - 0.05,
					})
					local label = ("at %d to %s at %.1f s"):format(speed, drawnLabel(toDrawn), switch)
					checkTransient(problems, label, result)
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("a start from standing, both sets, to walk, run and sprint speed: the first plants hold", function()
		local problems = {}
		for _, drawn in { false, true } do
			for _, target in { Config.walkSpeed, Config.runSpeed, Config.sprintSpeed } do
				-- Standing for different times puts the start anywhere in the old cycle.
				for _, still in { 1, 1.37, 1.71 } do
					local result = simulate({
						direction = forward(),
						speed = function(t: number): number
							return if t < still then 0 else target
						end,
						moving = function(t: number): boolean
							return t >= still
						end,
						drawn = always(drawn),
						sprinting = target > Config.runSpeed,
						duration = still + 1.2,
						measureFrom = still,
						measureTo = still + 0.8,
					})
					local label = ("start %s to %d after %.2f s"):format(drawnLabel(drawn), target, still)
					-- The root is at full speed from the first frame: the Idle feet drag while the
					-- gait blends in, so only the plants are held to the bar here.
					checkTransient(problems, label, result, false)
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("the two-step stop from a walk (Guard) and from a run, wherever in the stride the stick lets go", function()
		local carryConfig = {
			seconds = Config.stopStepsSeconds,
			minCycles = Config.stopMinCycles,
			endSpeed = Config.stopEndSpeed,
			minSpeed = Config.idleSpeedThreshold,
			maxSpeed = Config.skidSpeedThreshold,
		}
		local speeds = { walk = Config.walkSpeed, run = Config.runSpeed, sprint = Config.sprintSpeed }
		local problems = {}
		local rows = {
			{ state = "Guard", drawn = true },
			{ state = "Idle", drawn = false },
			{ state = "Idle", drawn = true },
		}
		for _, row in rows do
			local humanoidSpeed = ActionLogic.speedFor(row.state, false, speeds)
			for step = 0, 11 do
				local release = 1.5 + step * 0.05
				local carry = ActionLogic.newStopCarry()
				local gait = { phase = 0, leftStep = 0, leftAfter = 0, rightStep = 0.5, rightAfter = 0 }
				local speed = humanoidSpeed
				local stick = forward()
				local carried = 0
				local stoppedAt: number? = nil
				local result = simulate({
					direction = stick,
					-- The controller's step: the stick, then the carry from the gait.
					speed = function(t: number, dt: number, locomotion: any): number
						local held = t < release
						if not held then
							locomotion:stopGait(gait)
						end
						carried = ActionLogic.stopCarryStep(
							carry,
							if held then stick.X else 0,
							if held then stick.Z else 0,
							speed,
							humanoidSpeed,
							true,
							row.state,
							dt,
							carryConfig,
							if held then nil else gait
						)
						if not held and carried == 0 and stoppedAt == nil then
							stoppedAt = t
						end
						speed = if held then humanoidSpeed else carried
						return speed
					end,
					-- The controller moves the Humanoid along the carry, so the stick reads it.
					moving = function(t: number): boolean
						return t < release or carried > 0
					end,
					drawn = always(row.drawn),
					duration = release + Config.stopStepsSeconds + 0.5,
					measureFrom = release - 0.5,
					start = if row.state == "Guard"
						then function(animator: any)
							animator:play(Config.clipPrefix .. "Guard")
						end
						else nil,
				})
				local label = ("stop %s %s at %.2f s"):format(row.state, drawnLabel(row.drawn), release)
				checkTransient(problems, label, result)
				-- It ends at the settle point, not at the cap, after the next Footstep.
				local stopped = stoppedAt or math.huge
				if stopped - release >= Config.stopStepsSeconds - 1e-9 then
					table.insert(problems, ("%s: ran to the cap"):format(label))
				end
				local after = 0
				for _, t in result.steps do
					if t > release and t <= stopped then
						after += 1
					end
				end
				if after < 1 then
					table.insert(problems, ("%s: no Footstep before the stop"):format(label))
				end
				-- The hand-over to Idle: the feet barely move once the root is still.
				local still = stillSlide(result, stopped, stopped + 0.5)
				if still > Stride.transientBar then
					table.insert(problems, ("%s: settled %.3f, limit %.3f"):format(label, still, Stride.transientBar))
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)
end)

describe("held off the stick (D-144): the posed body against a wall", function()
	-- Walks ahead at walkSpeed for a second into a wall, the stick held on. The root's velocity
	-- after the contact: `after(t, jostle)`, jostle being a seeded draw for each 60 Hz frame (the
	-- engine's), a unit direction and a 0 .. 1 size.
	local CONTACT = 1
	local function intoWall(drawn: boolean, readRoot: boolean, after: (t: number, jostle: any) -> any): Case
		local random = Random.new(11)
		local draws = {}
		local function jostle(t: number): any
			local frame = math.floor(t * 60)
			local draw = draws[frame]
			if draw == nil then
				local angle = random:NextNumber() * math.pi * 2
				draw = { direction = Vector3.new(math.cos(angle), 0, math.sin(angle)), size = random:NextNumber() }
				draws[frame] = draw
			end
			return draw
		end
		local function velocity(t: number): any
			if t < CONTACT then
				return forward() * Config.walkSpeed
			end
			return after(t, jostle(t))
		end
		return {
			direction = forward(),
			speed = function(t: number): number
				local v = velocity(t)
				return Vector3.new(v.X, 0, v.Z).Magnitude
			end,
			velocity = velocity,
			moving = always(true),
			drawn = always(drawn),
			readRoot = readRoot,
			duration = CONTACT + 3,
			measureFrom = CONTACT + 1,
		}
	end

	it("jostled about nothing, the body stands on planted feet", function()
		local problems = {}
		for _, drawn in { false, true } do
			for _, readRoot in { false, true } do
				local label = ("%s, velocity %s"):format(drawnLabel(drawn), if readRoot then "on the root" else "given")
				local case = intoWall(drawn, readRoot, function(_t: number, jostle: any): any
					return jostle.direction * (0.5 * jostle.size)
				end)
				local result = simulate(case)
				for name, weight in result.shown do
					if weight > 0 then
						table.insert(problems, ("%s: %s shows %.3f"):format(label, name, weight))
					end
				end
				local still = stillSlide(result, case.measureFrom, case.duration)
				if still > Stride.slideBar then
					table.insert(problems, ("%s: a foot slid %.3f, limit %.3f"):format(label, still, Stride.slideBar))
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("slid along its flank, the feet step the slide's way", function()
		local shape = body()
		local problems = {}
		for _, drawn in { false, true } do
			-- Square to the side, and a diagonal (back and right) whose swing is checked no more than
			-- the open-ground diagonals' are (a blend's swing scrapes where its clips' do).
			for _, row in
				{
					{ slide = shape.right * 3.2, swing = true },
					{ slide = (shape.right * 0.6 - shape.forward * 0.8) * 3, swing = false },
					{ slide = -shape.right * 2, swing = true },
				}
			do
				local slide = row.slide
				for _, readRoot in { false, true } do
					local label = ("%s, slide (%.1f, %.1f), velocity %s"):format(
						drawnLabel(drawn),
						slide.X,
						slide.Z,
						if readRoot then "on the root" else "given"
					)
					local case = intoWall(drawn, readRoot, function(): any
						return slide
					end)
					local result = simulate(case)
					local ahead = (result.shown[LocomotionState.clipFor("WalkForward", drawn)] or 0)
						+ (result.shown[LocomotionState.clipFor("Run", drawn)] or 0)
					if ahead > 0 then
						table.insert(problems, ("%s: steps ahead (%.3f)"):format(label, ahead))
					end
					if row.swing then
						checkBounded(problems, label, result)
					else
						checkPlants(problems, label, result, owned(result) + Stride.slideBar, nil)
					end
				end
			end
		end
		expect(table.concat(problems, "; ")).toBe("")
	end)
end)
