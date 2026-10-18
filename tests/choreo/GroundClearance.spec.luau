--!strict
--[[
	No player clip drives the sword into the ground (section 2: combat is physical; section 10: the
	post-motion must look like a person caught in a stance, and a blade sunk in the field reads as a
	broken game, not a stance). Every clip of the Playground loadout weapon's category
	(src/shared/clips/player/OneHandedSword: the Arts and the basic chain, locomotion, guard, parry,
	dodges, flinches, death) is posed at dev.luau groundClearance.sampleHz and at every key time on
	the hit matrix's player (HitMatrix.standing: the engine's blank-avatar R15 scaled by rigs.luau
	PlayerR15.scale, jointed with AnimationConstraints, holding the loadout sword, feet on the
	Playground field), the root carried by the clip's root motion. Base and FullBody clips are posed
	alone; UpperBody and Additive clips over groundClearance.layeredOver at the same clock time, as
	the Mixer layers them, and a clip that puts the sword away (a WeaponSheathe) over
	groundClearance.layeredOverSheathed.

	The sword is where ReviewMarkers.mountAt puts it (docs/DECISIONS.md D-050): in the hand, or on
	its sheath across the back (weaponModels.luau sheaths), where the clip's Weapon key no longer
	moves it. It fails when the blade's tip or guard end (TrailEnd / TrailStart) sinks below the
	field's top face by more than groundClearance.bladeMargin, or a corner of either hand goes below
	that face, and names every clip and time range with its lowest point. At every WeaponDraw and
	WeaponSheathe the sword must change hands where the hand is (groundClearance.handoff), with the
	blade clear of the head and torso. For groundClearance.sheathSlide seconds after a WeaponDraw
	and before a WeaponSheathe the blade runs along its sheath, and no edge or face of it may come
	out through the scabbard's walls. Through the sheathed set (the Base clips marked `sheathed`:
	the idle, the walks, Run and Sprint) the sword's blade, guard and grip on the back and the
	scabbard must stay out of every body part but the one the sheath hangs on
	(groundClearance.backOverlap): a head tipped back into the hilt or an arm swung through the
	scabbard fails.

	This is its own spec rather than a section of HitMatrix.spec.luau: it is a property of the clip
	data (like clips.spec.luau), it reuses only the matrix's rig and field, and it runs in about
	fourteen seconds without the matrix's server swings.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local CFrame = roblox.CFrame

local Dev = Harness.load("src/shared/data/dev")
local Playground = Harness.load("src/shared/data/playground")
local Weapons = Harness.load("src/shared/data/weapons")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers")
local WeaponModels = Harness.load("src/shared/data/weaponModels")

local Config = Dev.groundClearance
local root = Harness.repoRoot()
local category = Weapons.byId(Playground.loadout.weapon).category
local clipsDirectory = "src/shared/clips/player/" .. category

-- tools/ modules are plain Lune scripts: load one with only Lune's own libraries to require.
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

-- Half the vertical extent of a box's world-axis bounds.
local function halfHeight(cframe: any, size: any): number
	local half = size * 0.5
	return math.abs(cframe.RightVector.Y) * half.X
		+ math.abs(cframe.UpVector.Y) * half.Y
		+ math.abs(cframe.LookVector.Y) * half.Z
end

-- A box that rides the sword or the sheath, and where a solved pose puts it.
type Piece = { name: string, size: any, frameOf: (solved: any) -> any }

type Body = {
	avatar: any,
	fieldTop: number,
	trailStart: any,
	trailEnd: any,
	hands: { any },
	weapon: any, -- the sword's Weapon Motor6D
	handPart: any, -- its Part0 and C0 in the hand
	handC0: any,
	backPart: any, -- the sheath's part and C0 on the back
	backC0: any,
	pieces: { Piece }, -- the sword's boxes and the scabbard
	bodyParts: { any }, -- every body part the sheathed sword must stay out of
}

local standing: Body? = nil
local function body(): Body
	if standing == nil then
		local avatar, field = HitMatrix.standing(Harness)
		local trailStart = avatar.model:FindFirstChild("TrailStart", true)
		local trailEnd = avatar.model:FindFirstChild("TrailEnd", true)
		assert(trailStart ~= nil and trailEnd ~= nil, "the matrix's sword has no TrailStart / TrailEnd")
		local weapon = nil
		for _, item in avatar.model:GetDescendants() do
			if item:IsA("Motor6D") and item.Name == "Weapon" then
				weapon = item
			end
		end
		assert(weapon ~= nil, "the matrix's sword has no Weapon Motor6D")
		local row = WeaponModels.sheath(category)
		assert(row ~= nil, "weaponModels.luau has no sheath for " .. category)
		local backPart = avatar.model:FindFirstChild(row.part)
		assert(backPart ~= nil, "the matrix's avatar has no " .. row.part)
		-- The guard and grip ride the blade on welds; the scabbard rides the sheath's part.
		local blade = trailEnd.Parent
		local pieces: { Piece } = {}
		-- (The Weapon Motor6D shares the blade's name, so the search keeps to parts.)
		local function partNamed(name: string): any
			for _, item in avatar.model:GetDescendants() do
				if item:IsA("BasePart") and item.Name == name then
					return item
				end
			end
			return nil
		end
		for _, name in { WeaponModels.bladePart, WeaponModels.guardPart, WeaponModels.gripPart } do
			local part = partNamed(name)
			assert(part ~= nil, "the matrix's sword has no " .. name)
			local offset = blade.CFrame:ToObjectSpace(part.CFrame)
			table.insert(pieces, {
				name = name,
				size = part.Size,
				frameOf = function(solved: any): any
					return solved[blade.Name] * offset
				end,
			})
		end
		local scabbard = partNamed(WeaponModels.scabbardPart)
		assert(scabbard ~= nil, "the matrix's avatar has no " .. WeaponModels.scabbardPart)
		local scabbardWeld = scabbard:FindFirstChild(WeaponModels.scabbardWeld)
		assert(scabbardWeld ~= nil, "the matrix's scabbard has no " .. WeaponModels.scabbardWeld)
		table.insert(pieces, {
			name = scabbard.Name,
			size = scabbard.Size,
			frameOf = function(solved: any): any
				return solved[row.part] * scabbardWeld.C0
			end,
		})
		-- The body parts are the avatar's own children; the sword and sheath sit in their models.
		local bodyParts = {}
		for _, part in avatar.model:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= avatar.model.PrimaryPart.Name and part.Name ~= row.part then
				table.insert(bodyParts, part)
			end
		end
		table.sort(bodyParts, function(a, b)
			return a.Name < b.Name
		end)
		standing = {
			avatar = avatar,
			fieldTop = field.CFrame.Position.Y + halfHeight(field.CFrame, field.Size),
			trailStart = trailStart,
			trailEnd = trailEnd,
			hands = { avatar.model:FindFirstChild("RightHand"), avatar.model:FindFirstChild("LeftHand") },
			weapon = weapon,
			handPart = weapon.Part0,
			handC0 = weapon.C0,
			backPart = backPart,
			backC0 = ClipSampler.toCFrame(row.mount),
			pieces = pieces,
			bodyParts = bodyParts,
		}
	end
	return standing :: Body
end

-- Joints the sword to the hand or to its sheath on the back. Pose.solve reads the joints on each
-- call (no chain passed), so the next solve follows the move.
local function setMount(current: Body, mount: string)
	if mount == "Back" then
		current.weapon.Part0 = current.backPart
		current.weapon.C0 = current.backC0
	else
		current.weapon.Part0 = current.handPart
		current.weapon.C0 = current.handC0
	end
end

-- Solves the body with the sword at `mount`; on the back the clip's Weapon key no longer moves
-- it (Choreo pins the joint there).
local function solveAt(current: Body, rootCFrame: any, offsets: any, mount: string): any
	setMount(current, mount)
	if mount == "Back" then
		offsets = table.clone(offsets)
		offsets.Weapon = nil
	end
	local solved = Pose.solve(current.avatar.model, rootCFrame, offsets)
	setMount(current, "Hand")
	return solved
end

-- Heights above the field's top face at one clip time (negative: below it).
type Sample = { time: number, tip: number, guard: number, hand: number, handName: string }

local function sampleTimes(clip: any): { number }
	local times = {}
	local count = math.floor(clip.duration * Config.sampleHz + 1e-6)
	for index = 0, count do
		table.insert(times, index / Config.sampleHz)
	end
	table.insert(times, clip.duration)
	for _, key in clip.keys do
		table.insert(times, key.time)
	end
	table.sort(times)
	local unique = {}
	for _, time in times do
		if #unique == 0 or time - unique[#unique] > 1e-9 then
			table.insert(unique, time)
		end
	end
	return unique
end

-- The joint offsets a clip shows at `time`: alone, or laid over `base` the way the Mixer layers it.
local function offsetsAt(clip: any, base: any?, time: number): any
	local own = ClipSampler.sample(clip, time)
	if base == nil then
		return own
	end
	local under = ClipSampler.sample(base, time) -- the base loops: the sampler wraps it
	if clip.layer == "Additive" then
		return ClipSampler.add(under, own, 1)
	end
	for name, offset in own do
		under[name] = offset
	end
	return under
end

-- The sheathed set's poses, kept by clip and time: the field check and the back check pose the
-- same frames, so the second reads them instead of solving them again.
local sheathedPoses: { [any]: { [number]: any } } = setmetatable({}, { __mode = "k" }) :: any

-- Solves `clip` (over `base`) at `time` with the sword where ReviewMarkers.mountAt puts it.
local function poseAt(current: Body, clip: any, base: any?, time: number, rootCFrame: any): any
	if clip.sheathed ~= true or base ~= nil then
		return solveAt(current, rootCFrame, offsetsAt(clip, base, time), ReviewMarkers.mountAt(clip, time))
	end
	local kept = sheathedPoses[clip]
	if kept == nil then
		kept = {}
		sheathedPoses[clip] = kept
	end
	local solved = kept[time]
	if solved == nil then
		solved = solveAt(current, rootCFrame, offsetsAt(clip, nil, time), ReviewMarkers.mountAt(clip, time))
		kept[time] = solved
	end
	return solved
end

local function measure(clip: any, base: any?): { Sample }
	local current = body()
	local avatar = current.avatar
	local blade = current.trailEnd.Parent.Name
	local guardPart = current.trailStart.Parent.Name
	local start = ClipSampler.rootMotionAt(clip, 0)
	local samples: { Sample } = {}
	for _, time in sampleTimes(clip) do
		local now = ClipSampler.rootMotionAt(clip, time)
		local rootCFrame = avatar.base * CFrame.new(now[1] - start[1], now[2] - start[2], now[3] - start[3])
		local solved = poseAt(current, clip, base, time, rootCFrame)
		local tip = (solved[blade] * current.trailEnd.CFrame).Position.Y - current.fieldTop
		local guard = (solved[guardPart] * current.trailStart.CFrame).Position.Y - current.fieldTop
		local hand, handName = math.huge, ""
		for _, part in current.hands do
			local frame = solved[part.Name]
			local lowest = frame.Position.Y - halfHeight(frame, part.Size) - current.fieldTop
			if lowest < hand then
				hand, handName = lowest, part.Name
			end
		end
		table.insert(samples, { time = time, tip = tip, guard = guard, hand = hand, handName = handName })
	end
	return samples
end

local function fails(sample: Sample): boolean
	return sample.tip < -Config.bladeMargin or sample.guard < -Config.bladeMargin or sample.hand < 0
end

-- One line per run of consecutive failing samples: the time range and its lowest point.
local function problems(name: string, samples: { Sample }): { string }
	local lines = {}
	local index = 1
	while index <= #samples do
		if not fails(samples[index]) then
			index += 1
			continue
		end
		local first = index
		while index + 1 <= #samples and fails(samples[index + 1]) do
			index += 1
		end
		local lowest, lowestAt, which = math.huge, 0, ""
		local hand, handAt, handName = math.huge, 0, ""
		for at = first, index do
			local sample = samples[at]
			if sample.tip < lowest then
				lowest, lowestAt, which = sample.tip, sample.time, "tip"
			end
			if sample.guard < lowest then
				lowest, lowestAt, which = sample.guard, sample.time, "guard"
			end
			if sample.hand < hand then
				hand, handAt, handName = sample.hand, sample.time, sample.handName
			end
		end
		local line = ("%s %.3f-%.3f s: lowest blade point the %s, %.3f %s the field at %.3f s"):format(
			name,
			samples[first].time,
			samples[index].time,
			which,
			math.abs(lowest),
			if lowest < 0 then "below" else "above",
			lowestAt
		)
		if hand < 0 then
			line ..= ("; the %s %.3f below it at %.3f s"):format(handName, -hand, handAt)
		end
		table.insert(lines, line)
		index += 1
	end
	return lines
end

type Entry = { name: string, clip: any }

local function playerClips(): { Entry }
	local list: { Entry } = {}
	for _, file in Harness.listFiles(clipsDirectory, "%.luau$") do
		local name = file:match("([^/]+)%.luau$")
		assert(name ~= nil, "unexpected clip path " .. file)
		table.insert(list, { name = name, clip = Harness.load((file:gsub("%.luau$", ""))) })
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

local function layeredBase(): any
	return Harness.load(clipsDirectory .. "/" .. Config.layeredOver)
end

local function eventTime(clip: any, kind: string): number?
	for _, event in clip.events do
		if event.kind == kind then
			return event.time
		end
	end
	return nil
end

-- A clip that puts the sword away plays over the sheathed set; every other layered clip (Draw
-- included) over the drawn stance.
local function baseFor(clip: any): any?
	if clip.layer == "UpperBody" or clip.layer == "Additive" then
		if eventTime(clip, "WeaponSheathe") ~= nil then
			return Harness.load(clipsDirectory .. "/" .. Config.layeredOverSheathed)
		end
		return layeredBase()
	end
	return nil
end

-- How far a segment comes to a box: the distance outside it, negative when it passes inside.
local function segmentToBox(a: any, b: any, frame: any, size: any): number
	local half = size * 0.5
	local best = math.huge
	local steps = 40
	for index = 0, steps do
		local here = frame:PointToObjectSpace(a:Lerp(b, index / steps))
		local dx = math.max(math.abs(here.X) - half.X, 0)
		local dy = math.max(math.abs(here.Y) - half.Y, 0)
		local dz = math.max(math.abs(here.Z) - half.Z, 0)
		local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
		if distance == 0 then
			distance = -math.min(half.X - math.abs(here.X), half.Y - math.abs(here.Y), half.Z - math.abs(here.Z))
		end
		best = math.min(best, distance)
	end
	return best
end

-- The angle between two directions, steady near zero (acos loses a tenth of a degree there).
local function degreesBetween(u: any, v: any): number
	return math.deg(math.atan2(u:Cross(v).Magnitude, u:Dot(v)))
end

type Handoff = { time: number, distance: number, degrees: number, clear: number, part: string }

-- The sword at a WeaponDraw or WeaponSheathe: posed once in the hand (the clip's Weapon key) and
-- once on the back mount. The grip and the blade should not jump between the two, and the blade
-- should be clear of the head and torso.
local function handoff(clip: any, base: any?, time: number): Handoff
	local current = body()
	local offsets = offsetsAt(clip, base, time)
	local held = solveAt(current, current.avatar.base, offsets, "Hand")
	local stowed = solveAt(current, current.avatar.base, offsets, "Back")
	local weaponPart = current.weapon.Part1.Name
	local grip = held[weaponPart] * current.weapon.C1
	local home = stowed[weaponPart] * current.weapon.C1
	local blade = current.trailEnd.Parent.Name
	local guardPart = current.trailStart.Parent.Name
	local clear, closest = math.huge, ""
	for _, solved in { held, stowed } do
		local tip = (solved[blade] * current.trailEnd.CFrame).Position
		local guard = (solved[guardPart] * current.trailStart.CFrame).Position
		for _, name in { "Head", "UpperTorso", "LowerTorso" } do
			local part = current.avatar.model:FindFirstChild(name)
			local distance = segmentToBox(guard, tip, solved[name], part.Size)
			if distance < clear then
				clear, closest = distance, name
			end
		end
	end
	return {
		time = time,
		distance = (grip.Position - home.Position).Magnitude,
		degrees = degreesBetween(grip.UpVector, home.UpVector),
		clear = clear,
		part = closest,
	}
end

-- The handoff problems of one clip: one line per WeaponDraw or WeaponSheathe that pops.
local function handoffProblems(name: string, clip: any): { string }
	local lines = {}
	for _, kind in { "WeaponDraw", "WeaponSheathe" } do
		local time = eventTime(clip, kind)
		if time == nil then
			continue
		end
		local result = handoff(clip, baseFor(clip), time)
		if result.distance > Config.handoff.maxDistance or result.degrees > Config.handoff.maxDegrees then
			table.insert(
				lines,
				("%s %s at %.3f s: the grip moves %.3f studs (limit %.2f) and the blade turns %.1f degrees (limit %.0f) when the sword changes hands"):format(
					name,
					kind,
					time,
					result.distance,
					Config.handoff.maxDistance,
					result.degrees,
					Config.handoff.maxDegrees
				)
			)
		end
		if result.clear <= 0 then
			table.insert(
				lines,
				("%s %s at %.3f s: the blade passes %.3f inside the %s"):format(
					name,
					kind,
					time,
					-result.clear,
					result.part
				)
			)
		end
	end
	return lines
end

-- A box as plain numbers: its center, its three axes (the rotation's columns) and half its size.
type Box = { center: { number }, axes: { { number } }, half: { number } }

local function boxOf(frame: any, size: any): Box
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = frame:GetComponents()
	return {
		center = { x, y, z },
		axes = { { r00, r10, r20 }, { r01, r11, r21 }, { r02, r12, r22 } },
		half = { size.X / 2, size.Y / 2, size.Z / 2 },
	}
end

-- How far apart two boxes are along the axis that separates them best (the separating axis
-- test over the 15 axes): positive is a gap, negative how deep they overlap along the shallowest
-- axis. Plain numbers, no vectors: the sheathed set asks it a few hundred thousand times.
local function boxSeparation(a: Box, b: Box): number
	local rotation = {}
	local absolute = {}
	for i = 1, 3 do
		rotation[i], absolute[i] = {}, {}
		local ai = a.axes[i]
		for j = 1, 3 do
			local bj = b.axes[j]
			local dot = ai[1] * bj[1] + ai[2] * bj[2] + ai[3] * bj[3]
			rotation[i][j] = dot
			absolute[i][j] = math.abs(dot)
		end
	end
	local dx = b.center[1] - a.center[1]
	local dy = b.center[2] - a.center[2]
	local dz = b.center[3] - a.center[3]
	local t = {}
	for i = 1, 3 do
		local ai = a.axes[i]
		t[i] = dx * ai[1] + dy * ai[2] + dz * ai[3]
	end
	local ha, hb = a.half, b.half
	local best = -math.huge
	for i = 1, 3 do
		local gap = math.abs(t[i]) - ha[i] - (hb[1] * absolute[i][1] + hb[2] * absolute[i][2] + hb[3] * absolute[i][3])
		best = math.max(best, gap)
	end
	for j = 1, 3 do
		local distance = math.abs(t[1] * rotation[1][j] + t[2] * rotation[2][j] + t[3] * rotation[3][j])
		local gap = distance - hb[j] - (ha[1] * absolute[1][j] + ha[2] * absolute[2][j] + ha[3] * absolute[3][j])
		best = math.max(best, gap)
	end
	for i = 1, 3 do
		local i1, i2 = i % 3 + 1, (i + 1) % 3 + 1
		for j = 1, 3 do
			local length = math.sqrt(math.max(0, 1 - rotation[i][j] * rotation[i][j]))
			if length > 1e-6 then
				local j1, j2 = j % 3 + 1, (j + 1) % 3 + 1
				local distance = math.abs(t[i2] * rotation[i1][j] - t[i1] * rotation[i2][j])
				local reachA = ha[i1] * absolute[i2][j] + ha[i2] * absolute[i1][j]
				local reachB = hb[j1] * absolute[i][j2] + hb[j2] * absolute[i][j1]
				best = math.max(best, (distance - reachA - reachB) / length)
			end
		end
	end
	return best
end

-- The back problems of a clip: one line per sword piece and body part that overlap by more than
-- backOverlap while the sword is on the back, with the deepest overlap and its time.
local function backProblems(name: string, clip: any): { string }
	local current = body()
	local start = ClipSampler.rootMotionAt(clip, 0)
	local deepest: { [string]: { depth: number, time: number } } = {}
	local order: { string } = {}
	for _, time in sampleTimes(clip) do
		if ReviewMarkers.mountAt(clip, time) ~= "Back" then
			continue
		end
		local now = ClipSampler.rootMotionAt(clip, time)
		local rootCFrame = current.avatar.base * CFrame.new(now[1] - start[1], now[2] - start[2], now[3] - start[3])
		local solved = poseAt(current, clip, nil, time, rootCFrame)
		local parts: { Box } = {}
		for index, part in current.bodyParts do
			parts[index] = boxOf(solved[part.Name], part.Size)
		end
		for _, piece in current.pieces do
			local box = boxOf(piece.frameOf(solved), piece.size)
			for index, part in current.bodyParts do
				local other = parts[index]
				-- Boxes whose bounding spheres are apart cannot meet.
				local reach = (piece.size.Magnitude + part.Size.Magnitude) / 2
				local dx = other.center[1] - box.center[1]
				local dy = other.center[2] - box.center[2]
				local dz = other.center[3] - box.center[3]
				if dx * dx + dy * dy + dz * dz > reach * reach then
					continue
				end
				local gap = boxSeparation(box, other)
				if gap < -Config.backOverlap then
					local key = ("the %s in the %s"):format(piece.name, part.Name)
					local entry = deepest[key]
					if entry == nil then
						table.insert(order, key)
					end
					if entry == nil or -gap > entry.depth then
						deepest[key] = { depth = -gap, time = time }
					end
				end
			end
		end
	end
	local lines = {}
	for _, key in order do
		local entry = deepest[key]
		table.insert(lines, ("%s: %s, %.3f studs deep at %.3f s"):format(name, key, entry.depth, entry.time))
	end
	return lines
end

-- Points along the blade where its edges and faces are checked against the scabbard's walls.
local SLIDE_STATIONS = 16

-- How far the blade comes out through the scabbard's walls at `time` (negative: the room left),
-- over the part of it that is within the scabbard's length; nil when no part of it is.
local function slidePoke(current: Body, clip: any, base: any?, time: number): number?
	local solved = solveAt(current, current.avatar.base, offsetsAt(clip, base, time), "Hand")
	local blade, scabbard = current.pieces[1], current.pieces[#current.pieces]
	local bladeFrame, sheathFrame = blade.frameOf(solved), scabbard.frameOf(solved)
	local half, sheath = blade.size * 0.5, scabbard.size * 0.5
	local worst: number? = nil
	for station = 0, SLIDE_STATIONS do
		local along = -half.Y + blade.size.Y * station / SLIDE_STATIONS
		for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			local point = bladeFrame * roblox.Vector3.new(corner[1] * half.X, along, corner[2] * half.Z)
			local inSheath = sheathFrame:PointToObjectSpace(point)
			if math.abs(inSheath.Y) <= sheath.Y then
				local out = math.max(math.abs(inSheath.X) - sheath.X, math.abs(inSheath.Z) - sheath.Z)
				if worst == nil or out > worst then
					worst = out
				end
			end
		end
	end
	return worst
end

-- The slide problems of a clip: one line per WeaponDraw or WeaponSheathe whose blade comes out
-- through the scabbard's walls while it runs along the sheath (groundClearance.sheathSlide).
local function slideProblems(name: string, clip: any): { string }
	local current = body()
	local base = baseFor(clip)
	local lines = {}
	for _, kind in { "WeaponDraw", "WeaponSheathe" } do
		local event = eventTime(clip, kind)
		if event == nil then
			continue
		end
		local from = if kind == "WeaponDraw" then event else event - Config.sheathSlide.seconds
		local to = if kind == "WeaponDraw" then event + Config.sheathSlide.seconds else event
		local worst, worstAt = -math.huge, 0
		for _, time in sampleTimes(clip) do
			if time < from - 1e-9 or time > to + 1e-9 or ReviewMarkers.mountAt(clip, time) ~= "Hand" then
				continue
			end
			local out = slidePoke(current, clip, base, time)
			if out ~= nil and out > worst then
				worst, worstAt = out, time
			end
		end
		if worst > Config.sheathSlide.poke then
			table.insert(
				lines,
				("%s %s: the blade comes %.3f studs out through the scabbard's wall at %.3f s"):format(
					name,
					kind,
					worst,
					worstAt
				)
			)
		end
	end
	return lines
end

describe("ground clearance: the rig and the check", function()
	it("stands the hit matrix's player with its feet on the field's top face", function()
		local current = body()
		local solved = Pose.solve(current.avatar.model, current.avatar.base, {})
		local lowest = math.huge
		for _, part in current.avatar.model:GetChildren() do
			if part:IsA("BasePart") and solved[part.Name] ~= nil and part.Name ~= "HumanoidRootPart" then
				lowest = math.min(lowest, solved[part.Name].Position.Y - halfHeight(solved[part.Name], part.Size))
			end
		end
		expect(lowest).toBeCloseTo(current.fieldTop, 1e-6)
	end)

	it("poses every clip of the loadout weapon, on every layer, layered clips over a Base clip", function()
		local clips = playerClips()
		local layers: { [string]: number } = {}
		local attacks, sheathed, draws, sheathes = 0, 0, 0, 0
		for _, entry in clips do
			layers[entry.clip.layer] = (layers[entry.clip.layer] or 0) + 1
			if entry.clip.attack then
				attacks += 1
			end
			if entry.clip.sheathed == true then
				sheathed += 1
			end
			if eventTime(entry.clip, "WeaponDraw") ~= nil then
				draws += 1
			end
			if eventTime(entry.clip, "WeaponSheathe") ~= nil then
				sheathes += 1
			end
			expect(#sampleTimes(entry.clip)).toBeGreaterThanOrEqual(math.floor(entry.clip.duration * Config.sampleHz))
		end
		expect(#clips).toBe(#Harness.listFiles(clipsDirectory, "%.luau$"))
		expect(attacks).toBeGreaterThan(0)
		expect(sheathed).toBeGreaterThan(0)
		expect(draws).toBeGreaterThan(0)
		expect(sheathes).toBeGreaterThan(0)
		for _, layer in { "Base", "UpperBody", "FullBody", "Additive" } do
			expect(layers[layer] or 0).toBeGreaterThan(0)
		end
		expect(layeredBase().layer).toBe("Base")
		local underSheathe = Harness.load(clipsDirectory .. "/" .. Config.layeredOverSheathed)
		expect(underSheathe.layer).toBe("Base")
		expect(underSheathe.sheathed).toBe(true)
		expect(layeredBase().sheathed).never.toBe(true)
	end)

	it("flags a sword hung point-down from the hand, and passes the rest pose", function()
		local hanging = {
			id = "player/" .. category .. "/GroundProbe",
			rig = "PlayerR15",
			duration = 0.1,
			loop = false,
			layer = "FullBody",
			keys = { { time = 0, easing = "Hold", joints = { Weapon = { rot = { -80, 0, 0 } } } } },
			events = {},
		}
		local flagged = problems("GroundProbe", measure(hanging))
		expect(#flagged).toBe(1)
		expect(flagged[1]).toContain("tip")
		local rest = table.clone(hanging)
		rest.keys = { { time = 0, easing = "Hold", joints = { Weapon = { rot = { 0, 0, 0 } } } } }
		expect(#problems("Rest", measure(rest))).toBe(0)
		-- On the back the hand's Weapon key no longer moves the sword: the same key passes.
		local stowed = table.clone(hanging)
		stowed.sheathed = true
		expect(#problems("Stowed", measure(stowed))).toBe(0)
		-- A WeaponSheathe puts it on the back from that time: the hanging blade is flagged before only.
		local putAway = table.clone(hanging)
		putAway.duration = 0.2
		putAway.events = { { time = 0.1, kind = "WeaponSheathe" } }
		local lines = problems("PutAway", measure(putAway))
		expect(#lines).toBe(1)
		expect(lines[1]).toContain("PutAway 0.000-0.096 s")
	end)

	it("flags a draw whose hand is at the side when it takes the sword, and passes Draw and Sheathe", function()
		local atTheSide = {
			id = "player/" .. category .. "/HandoffProbe",
			rig = "PlayerR15",
			duration = 0.4,
			loop = false,
			sheathed = true,
			layer = "UpperBody",
			priority = 8,
			keys = {
				{ time = 0, easing = "SineInOut", joints = { RightShoulder = { rot = { 3, 0, 4 } } } },
				{
					time = 0.2,
					easing = "SineInOut",
					joints = { RightShoulder = { rot = { 3, 0, 4 } }, Weapon = { rot = { 0, 0, 0 } } },
				},
			},
			events = { { time = 0.2, kind = "WeaponDraw" } },
		}
		local flagged = handoffProblems("HandoffProbe", atTheSide)
		expect(#flagged).toBe(1)
		expect(flagged[1]).toContain("HandoffProbe WeaponDraw at 0.200 s: the grip moves")
		for _, name in { "Draw", "Sheathe" } do
			local clip = Harness.load(clipsDirectory .. "/" .. name)
			expect(handoffProblems(name, clip)).toEqual({})
		end
	end)

	it("flags a sheathed clip that tips the head into the hilt or swings a hand through the scabbard", function()
		local headBack = {
			id = "player/" .. category .. "/BackProbe",
			rig = "PlayerR15",
			duration = 0.1,
			loop = false,
			sheathed = true,
			layer = "Base",
			priority = 0,
			keys = { { time = 0, easing = "Hold", joints = { Neck = { rot = { 25, 0, 0 } } } } },
			events = {},
		}
		local flagged = table.concat(backProblems("HeadBack", headBack), "\n")
		expect(flagged).toContain("HeadBack: the " .. WeaponModels.gripPart .. " in the Head")
		local armBack = table.clone(headBack)
		armBack.keys = { { time = 0, easing = "Hold", joints = { LeftShoulder = { rot = { -30, 0, 0 } } } } }
		expect(table.concat(backProblems("ArmBack", armBack), "\n")).toContain(
			"ArmBack: the " .. WeaponModels.scabbardPart .. " in the LeftHand"
		)
		local rest = table.clone(headBack)
		rest.keys = { { time = 0, easing = "Hold", joints = {} } }
		expect(backProblems("Rest", rest)).toEqual({})
	end)

	it("flags a draw that turns the blade out through the scabbard's wall, and passes Draw and Sheathe", function()
		-- The real Draw's grab, then the shoulder rolls out to the side instead of pulling.
		local draw = Harness.load(clipsDirectory .. "/Draw")
		local grabAt = eventTime(draw, "WeaponDraw")
		assert(grabAt ~= nil, "Draw has no WeaponDraw")
		local grab = ClipSampler.sample(draw, grabAt)
		local rolled = table.clone(grab)
		local shoulder = grab.RightShoulder.rot
		rolled.RightShoulder = { rot = { shoulder[1], shoulder[2], shoulder[3] + 20 } }
		local sideways = {
			id = "player/" .. category .. "/SlideProbe",
			rig = "PlayerR15",
			duration = 0.2,
			loop = false,
			sheathed = true,
			layer = "UpperBody",
			priority = 8,
			keys = {
				{ time = 0, easing = "Hold", joints = grab },
				{ time = 0.1, easing = "Hold", joints = grab },
				{ time = 0.2, easing = "QuadOut", joints = rolled },
			},
			events = { { time = 0.1, kind = "WeaponDraw" } },
		}
		local flagged = slideProblems("SlideProbe", sideways)
		expect(#flagged).toBe(1)
		expect(flagged[1]).toContain("SlideProbe WeaponDraw: the blade comes")
		-- Held at the grab, the blade stays home in its sheath.
		local still = table.clone(sideways)
		still.keys = { { time = 0, easing = "Hold", joints = grab } }
		expect(slideProblems("Still", still)).toEqual({})
		for _, name in { "Draw", "Sheathe" } do
			expect(slideProblems(name, Harness.load(clipsDirectory .. "/" .. name))).toEqual({})
		end
	end)
end)

describe("ground clearance: every player clip", function()
	it("the sword changes hands where the hand is, clear of the head and torso", function()
		local lines = {}
		local checked = 0
		for _, entry in playerClips() do
			for _, line in handoffProblems(entry.name, entry.clip) do
				table.insert(lines, line)
			end
			if eventTime(entry.clip, "WeaponDraw") or eventTime(entry.clip, "WeaponSheathe") then
				checked += 1
			end
		end
		expect(checked).toBeGreaterThanOrEqual(2)
		if #lines > 0 then
			error(("%d sword handoff(s) pop:\n%s"):format(#lines, table.concat(lines, "\n")))
		end
	end)

	it("slides the blade along its sheath, inside the scabbard's walls, as it comes out and goes home", function()
		local lines = {}
		local checked = 0
		for _, entry in playerClips() do
			if eventTime(entry.clip, "WeaponDraw") or eventTime(entry.clip, "WeaponSheathe") then
				checked += 1
				for _, line in slideProblems(entry.name, entry.clip) do
					table.insert(lines, line)
				end
			end
		end
		expect(checked).toBeGreaterThanOrEqual(2)
		if #lines > 0 then
			error(
				("%d draw(s) or sheathe(s) cut through the scabbard (allowed %.3f studs):\n%s"):format(
					#lines,
					Config.sheathSlide.poke,
					table.concat(lines, "\n")
				)
			)
		end
	end)

	it("keeps the sword on its back and the scabbard off the body through the sheathed set", function()
		local lines = {}
		local checked = 0
		for _, entry in playerClips() do
			if entry.clip.sheathed == true and entry.clip.layer == "Base" then
				checked += 1
				-- The whole clip plays with the sword on the back, so every frame is checked.
				expect(ReviewMarkers.mountAt(entry.clip, 0)).toBe("Back")
				expect(ReviewMarkers.mountAt(entry.clip, entry.clip.duration)).toBe("Back")
				for _, line in backProblems(entry.name, entry.clip) do
					table.insert(lines, line)
				end
			end
		end
		expect(checked).toBeGreaterThan(0)
		if #lines > 0 then
			error(
				("%d sword piece(s) pass inside the body in the sheathed set (overlap allowed %.2f studs):\n%s"):format(
					#lines,
					Config.backOverlap,
					table.concat(lines, "\n")
				)
			)
		end
	end)

	it("keeps the blade's tip and guard above the field and both hands off it", function()
		local lines = {}
		for _, entry in playerClips() do
			for _, line in problems(entry.name, measure(entry.clip, baseFor(entry.clip))) do
				table.insert(lines, line)
			end
		end
		if #lines > 0 then
			error(
				("%d clip range(s) drive the sword into the ground (margin %.2f studs):\n%s"):format(
					#lines,
					Config.bladeMargin,
					table.concat(lines, "\n")
				)
			)
		end
	end)
end)
