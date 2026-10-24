--!strict
--[[
	No player clip drives the sword into the ground or through the body (section 2: combat is
	physical; section 10: the post-motion must look like a person caught in a stance, and a blade
	sunk in the field or a hilt in the head reads as a broken game, not a stance). Every clip of the
	Playground loadout weapon's category (src/shared/clips/player/OneHandedSword: the Arts and the
	basic chain, locomotion, guard, parry, dodges, flinches, death) is posed at dev.luau
	groundClearance.sampleHz and at every key time on the hit matrix's player (HitMatrix.standing:
	the engine's blank-avatar R15 scaled by rigs.luau PlayerR15.scale, jointed with
	AnimationConstraints, holding the loadout sword, feet on the Playground field), the root carried
	by the clip's root motion. The sword is where ReviewMarkers.mountAt puts it (docs/DECISIONS.md
	D-050): in the hand, or on its sheath across the back (weaponModels.luau sheaths), where the
	clip's Weapon key no longer moves it.

	The field: the blade's tip and guard end (TrailEnd / TrailStart) sink below the field's top face
	by at most groundClearance.bladeMargin, and no corner of either hand goes below it; it names
	every clip and time range with its lowest point. Base and FullBody clips are posed alone, an
	UpperBody or Additive clip over every Base clip of the set it plays over, as the Mixer layers
	them: a clip that puts the sword away (a WeaponSheathe) over the sheathed set, Draw over the
	drawn set, the other UpperBody clips and the Additive one-shots over the drawn set (the drawn
	sprint with its pose on top), and the Additive ones over the sheathed set too, the sword on the
	back.

	The handoff: at every WeaponDraw and WeaponSheathe the sword changes hands where the hand is
	(groundClearance.handoff), the blade clear of the head and torso. The slide
	(groundClearance.sheathSlide): from a WeaponDraw until the blade is clear of the scabbard, and
	back from a WeaponSheathe to where the blade meets it, no long edge of the blade comes out
	through the scabbard's walls past the bound for that moment: posed alone, with each flinch
	landing along the slide, and with Breathe from points over its cycle.

	Off the body (groundClearance.offBody): the scabbard lies on the back within offBody.backGap of
	it; the sword on the back (blade, guard, grip) and the scabbard keep offBody.margin from every
	body part but the one the sheath hangs on, and stay above the field; the sword in the hand
	(blade and guard) keeps offBody.heldMargin from every body part but the hand on the hilt and its
	forearm. With the sword on the back: the sheathed set (the Base clips marked `sheathed`), every
	FullBody clip that is not an attack (turns, jumps, landings, the skid, dodges, Stagger,
	GuardBreak: they play sheathed too), every Additive one-shot (the flinches, DeathFreeze) over the
	sheathed set, Draw before its WeaponDraw over every Base clip (the walk set follows the drawn
	state at once) and Sheathe from its WeaponSheathe on over the sheathed set. With the sword in the
	hand: the drawn set (the drawn sprint pose on its sprint), the attacks, the UpperBody clips
	(Guard, GuardHit, Parry) and the Additive one-shots over the drawn set, Draw after its WeaponDraw
	and Sheathe before its WeaponSheathe. A clip laid over a looping Base clip starts at points spread
	over the base's cycle so every base frame plays under it, a one-shot at most
	offBody.startSpacing apart. A hilt in the head or a hand through the scabbard reads as a broken
	model, not a stance. Not posed yet: a flinch over a FullBody one-shot or over Draw off the body,
	and the sheathed set with the sword still in the hand (it plays while Sheathe waits out
	choreo.luau sheatheDelay). TurnClearance.spec.luau poses the turn lean through drawn turns.

	This is its own spec rather than a section of HitMatrix.spec.luau: it is a property of the clip
	data (like clips.spec.luau), it reuses only the matrix's rig and field, and it runs without the
	matrix's server swings.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local CFrame = roblox.CFrame

local Dev = Harness.load("src/shared/data/dev")
local Playground = Harness.load("src/shared/data/playground")
local Weapons = Harness.load("src/shared/data/weapons")
local ChoreoData = Harness.load("src/shared/data/choreo")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers")
local WeaponModels = Harness.load("src/shared/data/weaponModels")

local Config = Dev.groundClearance
local OffBody = Config.offBody
local root = Harness.repoRoot()
local category = Weapons.byId(Playground.loadout.weapon).category
local clipsDirectory = "src/shared/clips/player/" .. category

-- The margin a body part keeps from the sword and the scabbard: its group's in OffBody.margin.
local function marginOf(partName: string): number
	if partName == "Head" then
		return OffBody.margin.head
	elseif partName:find("Arm") or partName:find("Hand") then
		return OffBody.margin.arms
	elseif partName:find("Leg") or partName:find("Foot") then
		return OffBody.margin.legs
	end
	return OffBody.margin.torso
end

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
	backPart: any, -- the sheath's part on the back
	scabbardC0: any, -- the scabbard's place on it (its weld's C0)
	handChain: any, -- the rig's joints read once (Pose.chain), the sword in the hand
	backChain: any, -- the same with the Weapon joint on the back mount
	fieldHand: any, -- the hand chain cut to the joints that place the sword and the hands
	fieldBack: any, -- the same for the back chain
	slideHand: any, -- the hand chain cut to the joints that place the sword and the sheath's part
	pieces: { Piece }, -- the sword's boxes and the scabbard
	bodyParts: { any }, -- every body part the sword and scabbard must stay off
	margins: { number }, -- by body part: the margin it keeps from them (marginOf)
	radii: { number }, -- by body part: its bounding sphere's radius
}

-- The links of `chain` that place `parts` and the parts they hang from, in the chain's order, so
-- a solve through them places just those parts, the same as the whole chain does.
local function toward(chain: any, parts: { string }): any
	local byPart = {}
	for _, link in chain.links do
		byPart[link.part1] = link
	end
	local needed: { [string]: boolean } = {}
	for _, name in parts do
		local part = name
		while byPart[part] ~= nil and not needed[part] do
			needed[part] = true
			part = byPart[part].part0
		end
	end
	local links = {}
	for _, link in chain.links do
		if needed[link.part1] then
			table.insert(links, link)
		end
	end
	return { rootName = chain.rootName, links = links }
end

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
		local margins, radii = {}, {}
		for index, part in bodyParts do
			margins[index] = marginOf(part.Name)
			radii[index] = part.Size.Magnitude / 2
		end
		-- The field test needs only the blade and the hands placed.
		local fieldParts = { blade.Name, "RightHand", "LeftHand" }
		-- The joints are read once: the back chain swaps the Weapon joint onto the sheath mount,
		-- where Choreo pins it, so a solve on the back never reads the rig either.
		local handChain = Pose.chain(avatar.model)
		local backLinks = {}
		for index, link in handChain.links do
			if link.name == weapon.Name and link.part1 == weapon.Part1.Name then
				link = table.clone(link)
				link.part0 = row.part
				link.c0 = ClipSampler.toCFrame(row.mount)
			end
			backLinks[index] = link
		end
		standing = {
			avatar = avatar,
			fieldTop = field.CFrame.Position.Y + halfHeight(field.CFrame, field.Size),
			trailStart = trailStart,
			trailEnd = trailEnd,
			hands = { avatar.model:FindFirstChild("RightHand"), avatar.model:FindFirstChild("LeftHand") },
			weapon = weapon,
			backPart = backPart,
			scabbardC0 = scabbardWeld.C0,
			handChain = handChain,
			backChain = { rootName = handChain.rootName, links = backLinks },
			fieldHand = toward(handChain, fieldParts),
			slideHand = toward(handChain, { blade.Name, row.part }),
			fieldBack = toward({ rootName = handChain.rootName, links = backLinks }, fieldParts),
			pieces = pieces,
			bodyParts = bodyParts,
			margins = margins,
			radii = radii,
		}
	end
	return standing :: Body
end

-- Solves the body with the sword at `mount`; on the back the clip's Weapon key no longer moves
-- it (Choreo pins the joint there).
local function solveAt(current: Body, rootCFrame: any, offsets: any, mount: string): any
	if mount == "Back" then
		offsets = table.clone(offsets)
		offsets.Weapon = nil
		return Pose.solve(current.avatar.model, rootCFrame, offsets, current.backChain)
	end
	return Pose.solve(current.avatar.model, rootCFrame, offsets, current.handChain)
end

-- The same, placing only the sword and the hands (the field test's parts).
local function solveField(current: Body, rootCFrame: any, offsets: any, mount: string): any
	if mount == "Back" then
		offsets = table.clone(offsets)
		offsets.Weapon = nil
		return Pose.solve(current.avatar.model, rootCFrame, offsets, current.fieldBack)
	end
	return Pose.solve(current.avatar.model, rootCFrame, offsets, current.fieldHand)
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

-- The joint offsets a clip shows at `time`: alone, or laid over `base` the way the Mixer layers it
-- (the base at `baseTime`, the same clock time when not given).
local function offsetsAt(clip: any, base: any?, time: number, baseTime: number?): any
	local own = ClipSampler.sample(clip, time)
	if base == nil then
		return own
	end
	local under = ClipSampler.sample(base, baseTime or time) -- the base loops: the sampler wraps it
	if clip.layer == "Additive" then
		return ClipSampler.add(under, own, 1)
	end
	for name, offset in own do
		under[name] = offset
	end
	return under
end

-- The root at a clip time, carried by the clip's root motion from its first frame.
local function rootAt(current: Body, clip: any, time: number): any
	local start = ClipSampler.rootMotionAt(clip, 0)
	local now = ClipSampler.rootMotionAt(clip, time)
	return current.avatar.base * CFrame.new(now[1] - start[1], now[2] - start[2], now[3] - start[3])
end

local function isFreeze(clip: any): boolean
	return clip.id:sub(-#ChoreoData.freezeClipSuffix) == ChoreoData.freezeClipSuffix
end

-- The clip's frames, laid over `base` from `start` in its cycle when given (a freeze clip holds
-- the base where it started), with `extra` added on top; `back` puts the sword on its back mount
-- for every frame (an Additive clip over the sheathed set), otherwise it is where mountAt says.
local function measure(clip: any, base: any?, start: number?, back: boolean?, extra: any?): { Sample }
	local current = body()
	local blade = current.trailEnd.Parent.Name
	local guardPart = current.trailStart.Parent.Name
	local samples: { Sample } = {}
	local frozen = isFreeze(clip)
	for _, time in sampleTimes(clip) do
		local baseTime = if start == nil then nil elseif frozen then start else start + time
		local offsets = offsetsAt(clip, base, time, baseTime)
		if extra ~= nil then
			offsets = ClipSampler.add(offsets, extra, 1)
		end
		local solved = solveField(
			current,
			rootAt(current, clip, time),
			offsets,
			if back == true then "Back" else ReviewMarkers.mountAt(clip, time)
		)
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

-- A box as 15 plain numbers: its center (1-3), its three axes, the rotation's columns (4-6, 7-9,
-- 10-12), and half its size (13-15).
type Box = { number }

local function boxOf(frame: any, size: any): Box
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = frame:GetComponents()
	return { x, y, z, r00, r10, r20, r01, r11, r21, r02, r12, r22, size.X / 2, size.Y / 2, size.Z / 2 }
end

-- Scratch for boxSeparation: the rotation between the boxes, its absolute values, and the
-- center offset in the first box's axes. Reused so the check allocates nothing per pair.
local rotation = table.create(9, 0)
local absolute = table.create(9, 0)
local offsetIn = table.create(3, 0)

-- How far apart two boxes are along the axis that separates them best (the separating axis
-- test over the 15 axes): positive is a gap, negative how deep they overlap along the shallowest
-- axis. Stops early, with a lower bound of the gap, once an axis shows them `enough` apart: the
-- off-body checks ask it a few hundred thousand times and only care about near pairs.
local function boxSeparation(a: Box, b: Box, enough: number?): number
	local limit = enough or math.huge
	for i = 1, 3 do
		local ax, ay, az = a[3 * i + 1], a[3 * i + 2], a[3 * i + 3]
		for j = 1, 3 do
			local dot = ax * b[3 * j + 1] + ay * b[3 * j + 2] + az * b[3 * j + 3]
			rotation[3 * (i - 1) + j] = dot
			absolute[3 * (i - 1) + j] = math.abs(dot)
		end
	end
	local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	for i = 1, 3 do
		offsetIn[i] = dx * a[3 * i + 1] + dy * a[3 * i + 2] + dz * a[3 * i + 3]
	end
	local ha1, ha2, ha3 = a[13], a[14], a[15]
	local hb1, hb2, hb3 = b[13], b[14], b[15]
	local best = -math.huge
	-- The first box's axes.
	for i = 1, 3 do
		local row = 3 * (i - 1)
		local gap = math.abs(offsetIn[i])
			- a[12 + i]
			- (hb1 * absolute[row + 1] + hb2 * absolute[row + 2] + hb3 * absolute[row + 3])
		if gap > best then
			best = gap
			if best >= limit then
				return best
			end
		end
	end
	-- The second box's axes.
	for j = 1, 3 do
		local distance =
			math.abs(offsetIn[1] * rotation[j] + offsetIn[2] * rotation[3 + j] + offsetIn[3] * rotation[6 + j])
		local gap = distance - b[12 + j] - (ha1 * absolute[j] + ha2 * absolute[3 + j] + ha3 * absolute[6 + j])
		if gap > best then
			best = gap
			if best >= limit then
				return best
			end
		end
	end
	-- Their edges crossed.
	for i = 1, 3 do
		local i1, i2 = i % 3 + 1, (i + 1) % 3 + 1
		for j = 1, 3 do
			local r = rotation[3 * (i - 1) + j]
			local length = math.sqrt(math.max(0, 1 - r * r))
			if length > 1e-6 then
				local j1, j2 = j % 3 + 1, (j + 1) % 3 + 1
				local distance =
					math.abs(offsetIn[i2] * rotation[3 * (i1 - 1) + j] - offsetIn[i1] * rotation[3 * (i2 - 1) + j])
				local reachA = a[12 + i1] * absolute[3 * (i2 - 1) + j] + a[12 + i2] * absolute[3 * (i1 - 1) + j]
				local reachB = b[12 + j1] * absolute[3 * (i - 1) + j2] + b[12 + j2] * absolute[3 * (i - 1) + j1]
				local gap = (distance - reachA - reachB) / length
				if gap > best then
					best = gap
					if best >= limit then
						return best
					end
				end
			end
		end
	end
	return best
end

-- Off the body. One pose to check: its joint offsets and root, whether the sword is on the back,
-- and whether the right hand is on the hilt (the grip and guard may meet that hand and forearm).
type Frame = {
	label: string, -- the clip, or the clip over its base
	at: string, -- when, for the report: the clip time, and the base's start under it
	offsets: any,
	rootCFrame: any,
	back: boolean,
	onHilt: boolean,
}

type Closest = { gap: number, label: string, at: string, margin: number }

-- The closest each sword piece came to each body part (or how far below the field it went), by
-- label, in the order first seen; how many frames were posed and under which labels.
type Tally = { order: { string }, closest: { [string]: Closest }, frames: number, seen: { [string]: boolean } }

local HILT_HAND: { [string]: boolean } = { RightHand = true, RightLowerArm = true }

local function newTally(): Tally
	return { order = {}, closest = {}, frames = 0, seen = {} }
end

local function note(tally: Tally, key: string, gap: number, frame: Frame, margin: number)
	local entry = tally.closest[key]
	if entry == nil then
		table.insert(tally.order, key)
		tally.closest[key] = { gap = gap, label = frame.label, at = frame.at, margin = margin }
	elseif gap < entry.gap then
		entry.gap, entry.label, entry.at = gap, frame.label, frame.at
	end
end

-- Poses one frame and notes every piece that comes nearer a body part than its margin or goes
-- below the field: the scabbard always; the sword's pieces while it is on the back; in the hand,
-- its blade and guard against offBody.heldMargin (the grip is in the fist, and the field test
-- owns the blade's height).
local function check(tally: Tally, frame: Frame)
	local current = body()
	local solved = solveAt(current, frame.rootCFrame, frame.offsets, if frame.back then "Back" else "Hand")
	tally.frames += 1
	tally.seen[frame.label] = true
	local boxes: { [number]: Box } = {}
	for _, piece in current.pieces do
		local inHand = not frame.back and piece.name ~= WeaponModels.scabbardPart
		if inHand and piece.name == WeaponModels.gripPart then
			continue
		end
		local pieceFrame = piece.frameOf(solved)
		if not inHand then
			local low = pieceFrame.Position.Y - halfHeight(pieceFrame, piece.size) - current.fieldTop
			if low < 0 then
				note(tally, ("%s|%s|field"):format(frame.label, piece.name), low, frame, 0)
			end
		end
		local box = boxOf(pieceFrame, piece.size)
		-- The hand on the hilt and its forearm may meet what they hold.
		local held = inHand
			or frame.onHilt and (piece.name == WeaponModels.gripPart or piece.name == WeaponModels.guardPart)
		local pieceRadius = piece.size.Magnitude / 2
		for index, part in current.bodyParts do
			if held and HILT_HAND[part.Name] then
				continue
			end
			local margin = if inHand then OffBody.heldMargin else current.margins[index]
			local other = boxes[index]
			if other == nil then
				other = boxOf(solved[part.Name], part.Size)
				boxes[index] = other
			end
			-- Boxes whose bounding spheres are a margin apart cannot come nearer than it.
			local reach = pieceRadius + current.radii[index] + margin
			local dx, dy, dz = other[1] - box[1], other[2] - box[2], other[3] - box[3]
			if dx * dx + dy * dy + dz * dz > reach * reach then
				continue
			end
			local gap = boxSeparation(box, other, margin)
			if gap < margin then
				note(tally, ("%s|%s|%s"):format(frame.label, piece.name, part.Name), gap, frame, margin)
			end
		end
	end
end

-- One line per label, piece and body part that came too near (or went below the field).
local function tallyLines(tally: Tally): { string }
	local lines = {}
	for _, key in tally.order do
		local entry = tally.closest[key]
		local piece, part = key:match("|([^|]+)|([^|]+)$")
		assert(piece ~= nil and part ~= nil, "bad tally key " .. key)
		local line
		if part == "field" then
			line = ("%s: the %s %.3f studs below the field at %s"):format(entry.label, piece, -entry.gap, entry.at)
		elseif entry.gap < 0 then
			line = ("%s: the %s in the %s, %.3f studs deep at %s"):format(
				entry.label,
				piece,
				part,
				-entry.gap,
				entry.at
			)
		else
			line = ("%s: the %s %.3f studs from the %s at %s (keep %.3f)"):format(
				entry.label,
				piece,
				entry.gap,
				part,
				entry.at,
				entry.margin
			)
		end
		table.insert(lines, line)
	end
	return lines
end

local function always(_: number): boolean
	return true
end

local function never(_: number): boolean
	return false
end

-- Every frame of a clip alone, its root carried by its root motion. `back(time)` says where the
-- sword is; `keep(time)` picks the frames to check.
local function checkAlone(
	tally: Tally,
	name: string,
	clip: any,
	back: (number) -> boolean,
	keep: ((number) -> boolean)?,
	extra: any?
)
	local current = body()
	for _, time in sampleTimes(clip) do
		if keep ~= nil and not keep(time) then
			continue
		end
		local offsets = ClipSampler.sample(clip, time)
		if extra ~= nil then
			offsets = ClipSampler.add(offsets, extra, 1)
		end
		check(tally, {
			label = name,
			at = ("%.3f s"):format(time),
			offsets = offsets,
			rootCFrame = rootAt(current, clip, time),
			back = back(time),
			onHilt = false,
		})
	end
end

-- Where a clip laid over a looping base starts in the base's cycle: evenly spread, enough that
-- every base frame plays under some frame of the clip. A one-shot (it peaks once) also starts at
-- least OffBody.starts times and at most OffBody.startSpacing seconds apart, up to
-- OffBody.maxStarts, so a pose that meets the body over a short stretch of the base's cycle is
-- never stepped over.
local function startsOver(clip: any, base: any): { number }
	local count = math.max(1, math.ceil(base.duration / clip.duration - 1e-9))
	if clip.loop ~= true then
		local spaced = math.min(math.ceil(base.duration / OffBody.startSpacing - 1e-9), OffBody.maxStarts)
		count = math.max(count, OffBody.starts, spaced)
	end
	local list = {}
	for index = 0, count - 1 do
		table.insert(list, base.duration * index / count)
	end
	return list
end

-- Every frame of `clip` over `base` from each start, layered as the Mixer layers them (a freeze
-- clip stops the base's clock at its start). `keep`, `back` and `onHilt` read the clip's time.
local function checkOver(
	tally: Tally,
	name: string,
	clip: any,
	baseName: string,
	base: any,
	keep: (number) -> boolean,
	back: (number) -> boolean,
	onHilt: (number) -> boolean
)
	local current = body()
	local label = ("%s over %s"):format(name, baseName)
	local frozen = isFreeze(clip)
	for _, start in startsOver(clip, base) do
		for _, time in sampleTimes(clip) do
			if not keep(time) then
				continue
			end
			local baseTime = if frozen then start else start + time
			check(tally, {
				label = label,
				at = ("%.3f s, %s from %.3f s"):format(time, baseName, start),
				offsets = offsetsAt(clip, base, time, baseTime),
				rootCFrame = current.avatar.base,
				back = back(time),
				onHilt = onHilt(time),
			})
		end
	end
end

-- The player clips in the roles the off-body checks pose them in.
type Roles = {
	sheathedSet: { Entry }, -- Base clips marked sheathed
	drawnSet: { Entry }, -- the other Base clips
	oneShots: { Entry }, -- FullBody clips that are not attacks: they play sheathed or drawn
	attacks: { Entry },
	upper: { Entry }, -- UpperBody clips that do not move the sword (Guard, GuardHit, Parry)
	additive: { Entry }, -- Additive one-shots (the always-on loop is the margin's job)
	draws: { Entry }, -- clips with a WeaponDraw
	sheathes: { Entry }, -- clips with a WeaponSheathe
}

local function roles(): Roles
	local found: Roles = {
		sheathedSet = {},
		drawnSet = {},
		oneShots = {},
		attacks = {},
		upper = {},
		additive = {},
		draws = {},
		sheathes = {},
	}
	for _, entry in playerClips() do
		local clip = entry.clip
		if eventTime(clip, "WeaponDraw") ~= nil then
			table.insert(found.draws, entry)
		elseif eventTime(clip, "WeaponSheathe") ~= nil then
			table.insert(found.sheathes, entry)
		elseif clip.attack == true then
			table.insert(found.attacks, entry)
		elseif clip.layer == "Base" then
			table.insert(if clip.sheathed == true then found.sheathedSet else found.drawnSet, entry)
		elseif clip.layer == "FullBody" then
			table.insert(found.oneShots, entry)
		elseif clip.layer == "UpperBody" then
			table.insert(found.upper, entry)
		elseif clip.layer == "Additive" and clip.loop ~= true then
			table.insert(found.additive, entry)
		end
	end
	return found
end

-- The off-body problems of one clip alone, the sword where ReviewMarkers.mountAt puts it.
local function bodyProblems(name: string, clip: any): { string }
	local tally = newTally()
	checkAlone(tally, name, clip, function(time: number): boolean
		return ReviewMarkers.mountAt(clip, time) == "Back"
	end)
	return tallyLines(tally)
end

-- Everything the sword on the back shows: the sheathed set, the one-shots, the Additive one-shots
-- over the sheathed set, Draw before its grab over every Base clip and Sheathe after it is home.
local function sheathedTally(found: Roles): Tally
	local tally = newTally()
	for _, entry in found.sheathedSet do
		checkAlone(tally, entry.name, entry.clip, always)
	end
	for _, entry in found.oneShots do
		checkAlone(tally, entry.name, entry.clip, always)
	end
	for _, entry in found.additive do
		for _, base in found.sheathedSet do
			checkOver(tally, entry.name, entry.clip, base.name, base.clip, always, always, never)
		end
	end
	for _, entry in found.draws do
		local grab = eventTime(entry.clip, "WeaponDraw") :: number
		local function before(time: number): boolean
			return time < grab - 1e-9
		end
		local function reaching(time: number): boolean
			return time >= grab - OffBody.onHilt - 1e-9
		end
		for _, set in { found.sheathedSet, found.drawnSet } do
			for _, base in set do
				checkOver(tally, entry.name, entry.clip, base.name, base.clip, before, always, reaching)
			end
		end
	end
	for _, entry in found.sheathes do
		local home = eventTime(entry.clip, "WeaponSheathe") :: number
		local function after(time: number): boolean
			return time >= home - 1e-9
		end
		local function letting(time: number): boolean
			return time <= home + OffBody.onHilt + 1e-9
		end
		for _, base in found.sheathedSet do
			checkOver(tally, entry.name, entry.clip, base.name, base.clip, after, always, letting)
		end
	end
	return tally
end

-- The drawn sprint pose (Locomotion's drawnSprint channel) as offsets at its weight.
local function drawnSprintPose(): any
	local offsets = {}
	for name, key in ChoreoData.locomotion.drawnSprintPose do
		offsets[name] = { pos = key.pos or { 0, 0, 0 }, rot = key.rot or { 0, 0, 0 } }
	end
	return ClipSampler.add({}, offsets, ChoreoData.additiveWeights.drawnSprint)
end

-- Everything the scabbard shows with the sword in the hand (the sheathed tally already covers
-- the FullBody one-shots, which pose the scabbard the same either way).
local function drawnTally(found: Roles): Tally
	local tally = newTally()
	for _, entry in found.drawnSet do
		checkAlone(tally, entry.name, entry.clip, never)
		if entry.name == ChoreoData.locomotion.clips.SprintDrawn then
			checkAlone(tally, entry.name .. " with the drawn sprint pose", entry.clip, never, nil, drawnSprintPose())
		end
	end
	for _, entry in found.attacks do
		checkAlone(tally, entry.name, entry.clip, never)
	end
	for _, set in { found.upper, found.additive } do
		for _, entry in set do
			for _, base in found.drawnSet do
				checkOver(tally, entry.name, entry.clip, base.name, base.clip, always, never, never)
			end
		end
	end
	for _, entry in found.draws do
		local grab = eventTime(entry.clip, "WeaponDraw") :: number
		local function after(time: number): boolean
			return time >= grab - 1e-9
		end
		for _, set in { found.sheathedSet, found.drawnSet } do
			for _, base in set do
				checkOver(tally, entry.name, entry.clip, base.name, base.clip, after, never, never)
			end
		end
	end
	for _, entry in found.sheathes do
		local home = eventTime(entry.clip, "WeaponSheathe") :: number
		local function before(time: number): boolean
			return time < home - 1e-9
		end
		for _, base in found.sheathedSet do
			checkOver(tally, entry.name, entry.clip, base.name, base.clip, before, never, never)
		end
	end
	return tally
end

-- A base a layered clip plays over in the field test: what is added on top of the two, and
-- whether the sword is on its back mount the whole time (otherwise mountAt says where it is).
type Over = { name: string, clip: any, extra: any?, back: boolean }

-- The bases the field test lays a clip over, nil for a Base or FullBody clip (posed alone). A
-- clip that puts the sword away plays over the sheathed set (D-050). Draw plays over the drawn
-- set: the walk set follows the drawn state at once and has crossed over before the grab
-- (locomotion.weightBlendRate). The other UpperBody clips and the Additive one-shots play over the
-- drawn set, the drawn sprint with its pose on top; the Additive ones over the sheathed set too,
-- the sword on the back.
local function fieldBases(clip: any, found: Roles): { Over }?
	if clip.layer ~= "UpperBody" and clip.layer ~= "Additive" then
		return nil
	end
	local list: { Over } = {}
	local function add(set: { Entry }, back: boolean)
		for _, base in set do
			table.insert(list, { name = base.name, clip = base.clip, back = back })
		end
	end
	if eventTime(clip, "WeaponSheathe") ~= nil then
		add(found.sheathedSet, false)
	elseif eventTime(clip, "WeaponDraw") ~= nil then
		add(found.drawnSet, false)
	else
		add(found.drawnSet, false)
		local sprint = ChoreoData.locomotion.clips.SprintDrawn
		for _, base in found.drawnSet do
			if base.name == sprint then
				table.insert(list, {
					name = sprint .. " with the drawn sprint pose",
					clip = base.clip,
					extra = drawnSprintPose(),
					back = false,
				})
			end
		end
		if clip.layer == "Additive" then
			add(found.sheathedSet, true)
		end
	end
	return list
end

-- How far the lowest sample comes past the field check's limits (negative: it fails).
local function lowestOf(samples: { Sample }): number
	local low = math.huge
	for _, sample in samples do
		low = math.min(low, sample.tip + Config.bladeMargin, sample.guard + Config.bladeMargin, sample.hand)
	end
	return low
end

-- The field problems of one clip: alone, or over every base it plays over from each start in
-- the base's cycle, reporting the start that goes deepest.
local function fieldProblems(name: string, clip: any, found: Roles): { string }
	local bases = fieldBases(clip, found)
	if bases == nil then
		return problems(name, measure(clip))
	end
	local lines = {}
	for _, over in bases do
		local worst, worstStart, worstSamples = math.huge, 0, nil
		for _, start in startsOver(clip, over.clip) do
			local samples = measure(clip, over.clip, start, over.back, over.extra)
			local low = lowestOf(samples)
			if low < worst then
				worst, worstStart, worstSamples = low, start, samples
			end
		end
		if worst < 0 and worstSamples ~= nil then
			local label = ("%s over %s from %.3f s"):format(name, over.name, worstStart)
			for _, line in problems(label, worstSamples) do
				table.insert(lines, line)
			end
		end
	end
	return lines
end

-- How far the scabbard stands off the sheath part's back face (+Z) along the length of it that
-- lies over that face: the largest and smallest gap, its face nearest the back station by
-- station. Nil when no part of it lies over the face.
local SCABBARD_STATIONS = 64

local function backGap(torsoSize: any, scabbardC0: any, scabbardSize: any): (number?, number?)
	local half = scabbardSize * 0.5
	local torso = torsoSize * 0.5
	-- The scabbard's reach toward the back across its width and thickness.
	local near = half.X * math.abs(scabbardC0.RightVector.Z) + half.Z * math.abs(scabbardC0.LookVector.Z)
	local most, least = nil, nil
	for station = 0, SCABBARD_STATIONS do
		local along = -half.Y + scabbardSize.Y * station / SCABBARD_STATIONS
		local point = scabbardC0 * roblox.Vector3.new(0, along, 0)
		if math.abs(point.X) <= torso.X and math.abs(point.Y) <= torso.Y then
			local gap = point.Z - near - torso.Z
			most = if most == nil then gap else math.max(most, gap)
			least = if least == nil then gap else math.min(least, gap)
		end
	end
	return most, least
end

-- The back-gap problems of a scabbard placed at `scabbardC0` on the sheath part.
local function backGapProblems(torsoSize: any, scabbardC0: any, scabbardSize: any): { string }
	local most, least = backGap(torsoSize, scabbardC0, scabbardSize)
	if most == nil or least == nil then
		return { "the scabbard does not lie over the back" }
	end
	local lines = {}
	if most > OffBody.backGap then
		table.insert(
			lines,
			("the scabbard stands %.3f studs off the back (at most %.2f)"):format(most, OffBody.backGap)
		)
	end
	if least < 0 then
		table.insert(lines, ("the scabbard goes %.3f studs into the back"):format(-least))
	end
	return lines
end

local Slide = Config.sheathSlide

-- Narrows [lo, hi] to the part of a line p + t * dp where |p + t * dp| <= limit.
local function narrow(lo: number, hi: number, p: number, dp: number, limit: number): (number, number)
	if math.abs(dp) < 1e-12 then
		if math.abs(p) > limit then
			return 1, 0
		end
		return lo, hi
	end
	local first, second = (-limit - p) / dp, (limit - p) / dp
	if first > second then
		first, second = second, first
	end
	return math.max(lo, first), math.min(hi, second)
end

-- How far the blade comes out through the scabbard's walls (negative: the room left). Each of the
-- blade's four long edges is cut to the part of it within the scabbard's length; an edge counts
-- when some of that part is inside the walls (the rest has left the sheath, or never reached
-- it), and its farthest point out is at an end of that part (the distance out of a box's
-- cross-section is convex along a line). Nil when no edge counts.
local function edgePoke(bladeFrame: any, bladeSize: any, sheathFrame: any, sheathSize: any): number?
	local half, sheath = bladeSize * 0.5, sheathSize * 0.5
	local worst: number? = nil
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local a = sheathFrame:PointToObjectSpace(
			bladeFrame * roblox.Vector3.new(corner[1] * half.X, -half.Y, corner[2] * half.Z)
		)
		local b = sheathFrame:PointToObjectSpace(
			bladeFrame * roblox.Vector3.new(corner[1] * half.X, half.Y, corner[2] * half.Z)
		)
		local d = b - a
		local lo, hi = narrow(0, 1, a.Y, d.Y, sheath.Y)
		if lo > hi then
			continue
		end
		local insideLo, insideHi = narrow(lo, hi, a.X, d.X, sheath.X)
		insideLo, insideHi = narrow(insideLo, insideHi, a.Z, d.Z, sheath.Z)
		if insideLo > insideHi then
			continue
		end
		for _, t in { lo, hi } do
			local point = a + d * t
			local out = math.max(math.abs(point.X) - sheath.X, math.abs(point.Z) - sheath.Z)
			if worst == nil or out > worst then
				worst = out
			end
		end
	end
	return worst
end

-- One pose of the slide: the clip time, how long from the event, and the edge poke.
type SlideSample = { time: number, away: number, out: number }

-- The slide around one WeaponDraw or WeaponSheathe, the sword in the hand: from the event outward
-- (on after a WeaponDraw, back before a WeaponSheathe) at sheathSlide.sampleHz until the blade's
-- box is clear of the scabbard's. `extra(time)` adds a layer on top (Breathe, a flinch).
local function slideSpan(
	clip: any,
	base: any?,
	kind: string,
	event: number,
	extra: ((number) -> any?)?
): { SlideSample }
	local current = body()
	local blade, scabbard = current.pieces[1], current.pieces[#current.pieces]
	local step = 1 / Slide.sampleHz
	local direction = if kind == "WeaponDraw" then 1 else -1
	local samples: { SlideSample } = {}
	local index = 0
	while true do
		local time = event + direction * index * step
		if time < -1e-9 or time > clip.duration + 1e-9 then
			break
		end
		local offsets = offsetsAt(clip, base, time)
		local added = if extra ~= nil then extra(time) else nil
		if added ~= nil then
			offsets = ClipSampler.add(offsets, added, 1)
		end
		local solved = Pose.solve(current.avatar.model, current.avatar.base, offsets, current.slideHand)
		local bladeFrame, sheathFrame = blade.frameOf(solved), scabbard.frameOf(solved)
		if boxSeparation(boxOf(bladeFrame, blade.size), boxOf(sheathFrame, scabbard.size)) > 0 then
			break
		end
		local out = edgePoke(bladeFrame, blade.size, sheathFrame, scabbard.size)
		if out ~= nil then
			table.insert(samples, { time = time, away = index * step, out = out })
		end
		index += 1
	end
	return samples
end

-- The worst of some slides: in the slide (within sheathSlide.seconds of the event) and as the
-- blade swings out over the mouth after it, each with when and under which case.
type SlideWorst = {
	inside: number,
	insideAt: number,
	insideCase: string,
	after: number,
	afterAt: number,
	afterCase: string,
}

local function newWorst(): SlideWorst
	return { inside = -math.huge, insideAt = 0, insideCase = "", after = -math.huge, afterAt = 0, afterCase = "" }
end

local function addSlide(worst: SlideWorst, samples: { SlideSample }, case: string)
	for _, sample in samples do
		if sample.away <= Slide.seconds + 1e-9 then
			if sample.out > worst.inside then
				worst.inside, worst.insideAt, worst.insideCase = sample.out, sample.time, case
			end
		elseif sample.out > worst.after then
			worst.after, worst.afterAt, worst.afterCase = sample.out, sample.time, case
		end
	end
end

local function slideLines(name: string, kind: string, worst: SlideWorst, bound: number): { string }
	local lines = {}
	if worst.inside > bound then
		table.insert(
			lines,
			("%s %s%s: the blade comes %.3f studs out through the scabbard's wall at %.4f s, in the slide (allowed %.3f)"):format(
				name,
				kind,
				worst.insideCase,
				worst.inside,
				worst.insideAt,
				bound
			)
		)
	end
	if worst.after > Slide.swingOut then
		table.insert(
			lines,
			("%s %s%s: the blade comes %.3f studs out through the scabbard's wall at %.4f s, swinging out over the mouth (allowed %.3f)"):format(
				name,
				kind,
				worst.afterCase,
				worst.after,
				worst.afterAt,
				Slide.swingOut
			)
		)
	end
	return lines
end

-- The slide problems of a clip: per WeaponDraw or WeaponSheathe, the slide alone, with each of
-- `overlays` (the Additive one-shots) landing every sheathSlide.leadStep seconds, from ending at
-- the event to starting once the blade is clear, and with `breathe` (Breathe) from
-- sheathSlide.breathPhases points of its cycle.
local function slideProblems(name: string, clip: any, breathe: any?, overlays: { Entry }?): { string }
	local base = baseFor(clip)
	local lines = {}
	for _, kind in { "WeaponDraw", "WeaponSheathe" } do
		local event = eventTime(clip, kind)
		if event == nil then
			continue
		end
		local worst = newWorst()
		local plain = slideSpan(clip, base, kind, event)
		addSlide(worst, plain, "")
		local reach = if #plain > 0 then plain[#plain].away else 0
		local direction = if kind == "WeaponDraw" then 1 else -1
		for _, overlay in overlays or {} do
			local layer = overlay.clip
			for lead = math.floor(-layer.duration / Slide.leadStep), math.ceil(reach / Slide.leadStep) + 1 do
				-- Where the overlay's clock starts, in the clip's: `lead` steps along the slide.
				local landing = if direction > 0
					then event + lead * Slide.leadStep
					else event - lead * Slide.leadStep - layer.duration
				addSlide(
					worst,
					slideSpan(clip, base, kind, event, function(time: number): any?
						local at = time - landing
						if at < 0 or at > layer.duration then
							return nil
						end
						return ClipSampler.sample(layer, at)
					end),
					(" with %s from %.3f s"):format(overlay.name, landing)
				)
			end
		end
		for _, line in slideLines(name, kind, worst, Slide.poke) do
			table.insert(lines, line)
		end
		if breathe ~= nil then
			local breathing = newWorst()
			for phase = 0, Slide.breathPhases - 1 do
				local from = breathe.duration * phase / Slide.breathPhases
				addSlide(
					breathing,
					slideSpan(clip, base, kind, event, function(time: number): any?
						return ClipSampler.sample(breathe, from + time)
					end),
					(" with Breathe from %.3f s"):format(from)
				)
			end
			for _, line in slideLines(name, kind, breathing, Slide.breathe) do
				table.insert(lines, line)
			end
		end
	end
	return lines
end

-- A one-key probe clip of the loadout weapon's category.
local function probe(name: string, layer: string, joints: any): any
	return {
		id = "player/" .. category .. "/" .. name,
		rig = "PlayerR15",
		duration = 0.1,
		loop = false,
		layer = layer,
		priority = if layer == "Base" then 0 else 5,
		keys = { { time = 0, easing = "Hold", joints = joints } },
		events = {},
	}
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

	it("solves from the joints read once as the rig itself solves, the sword in the hand or on the back", function()
		local current = body()
		local offsets = ClipSampler.sample(layeredBase(), 0.5)
		local model = current.avatar.model
		local fromRig = Pose.solve(model, current.avatar.base, offsets)
		local fromChain = solveAt(current, current.avatar.base, offsets, "Hand")
		for name, frame in fromRig do
			expect((fromChain[name].Position - frame.Position).Magnitude).toBeLessThan(1e-9)
		end
		-- Moving the motor onto the mount and solving from the rig puts the sword where the
		-- back chain does (to the rounding of a C0 written on an instance).
		local row = WeaponModels.sheath(category)
		local motor = current.weapon
		local part0, c0 = motor.Part0, motor.C0
		motor.Part0, motor.C0 = current.backPart, ClipSampler.toCFrame(row.mount)
		local stowedOffsets = table.clone(offsets)
		stowedOffsets.Weapon = nil
		local fromMovedRig = Pose.solve(model, current.avatar.base, stowedOffsets)
		motor.Part0, motor.C0 = part0, c0
		local stowed = solveAt(current, current.avatar.base, offsets, "Back")
		local blade = WeaponModels.bladePart
		expect((stowed[blade].Position - fromMovedRig[blade].Position).Magnitude).toBeLessThan(1e-4)
		expect((stowed[blade].Position - fromChain[blade].Position).Magnitude).toBeGreaterThan(1)
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

	it("sorts every clip into the role the off-body checks pose it in", function()
		local found = roles()
		local sorted = 0
		for _, set in found :: any do
			sorted += #set
		end
		-- Every clip but the always-on Additive loop.
		local loops = 0
		for _, entry in playerClips() do
			if entry.clip.layer == "Additive" and entry.clip.loop == true then
				loops += 1
			end
		end
		expect(sorted + loops).toBe(#playerClips())
		for name, set in found :: any do
			expect({ name = name, count = #set }).never.toEqual({ name = name, count = 0 })
		end
		local names = {}
		for _, entry in found.oneShots do
			table.insert(names, entry.name)
		end
		for _, name in
			{
				"Jump",
				"Fall",
				"Land",
				"Skid",
				"TurnLeft",
				"TurnRight",
				"DodgeForward",
				"DodgeBack",
				"DodgeLeft",
				"DodgeRight",
				"Stagger",
				"GuardBreak",
			}
		do
			expect(table.find(names, name)).never.toBeNil()
		end
		local overlays = {}
		for _, entry in found.additive do
			table.insert(overlays, entry.name)
		end
		for _, name in { "FlinchLeft", "FlinchRight", "FlinchFront", "FlinchBack", "DeathFreeze" } do
			expect(table.find(overlays, name)).never.toBeNil()
		end
		-- A clip over a base starts often enough that every base frame plays under it, and a
		-- one-shot at most startSpacing apart (up to maxStarts).
		for _, set in { found.sheathedSet, found.drawnSet } do
			for _, base in set do
				for _, entry in found.additive do
					local starts = startsOver(entry.clip, base.clip)
					expect(#starts).toBeGreaterThanOrEqual(OffBody.starts)
					expect(#starts * entry.clip.duration).toBeGreaterThanOrEqual(base.clip.duration - 1e-9)
					local spacing = base.clip.duration / #starts
					expect(spacing <= OffBody.startSpacing + 1e-9 or #starts >= OffBody.maxStarts).toBe(true)
				end
			end
		end
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
		-- The hand on the hilt but the blade turned 40 degrees about the grip: the turn alone pops.
		local draw = Harness.load(clipsDirectory .. "/Draw")
		local grabAt = eventTime(draw, "WeaponDraw") :: number
		local turned = ClipSampler.sample(draw, grabAt)
		local weapon = turned.Weapon
		turned.Weapon = { pos = weapon.pos, rot = { weapon.rot[1] + 40, weapon.rot[2], weapon.rot[3] } }
		local twist = probe("TwistProbe", "UpperBody", turned)
		twist.sheathed = true
		twist.events = { { time = 0.05, kind = "WeaponDraw" } }
		local result = handoff(twist, baseFor(twist), 0.05)
		expect(result.distance).toBeLessThan(0.01)
		expect(result.degrees).toBeGreaterThan(Config.handoff.maxDegrees)
		expect(table.concat(handoffProblems("TwistProbe", twist), "\n")).toContain(
			"TwistProbe WeaponDraw at 0.050 s: the grip moves"
		)
		for _, name in { "Draw", "Sheathe" } do
			local clip = Harness.load(clipsDirectory .. "/" .. name)
			expect(handoffProblems(name, clip)).toEqual({})
		end
	end)

	it(
		"flags a clip that tips the head into the hilt, swings a hand through the scabbard or hangs the drawn guard in a leg",
		function()
			local headBack = probe("BackProbe", "Base", { Neck = { rot = { 25, 0, 0 } } })
			headBack.sheathed = true
			local flagged = table.concat(bodyProblems("HeadBack", headBack), "\n")
			expect(flagged).toContain("HeadBack: the " .. WeaponModels.gripPart .. " in the Head")
			local armBack = table.clone(headBack)
			armBack.keys = { { time = 0, easing = "Hold", joints = { LeftShoulder = { rot = { -30, 0, 0 } } } } }
			expect(table.concat(bodyProblems("ArmBack", armBack), "\n")).toContain(
				"ArmBack: the " .. WeaponModels.scabbardPart .. " in the LeftHand"
			)
			-- With the sword out the hilt is in the hand: the scabbard keeps its margin, and the blade
			-- and guard stay out of the body (offBody.heldMargin).
			local drawnArm = table.clone(armBack)
			drawnArm.sheathed = nil
			expect(table.concat(bodyProblems("DrawnArm", drawnArm), "\n")).toContain(
				"DrawnArm: the " .. WeaponModels.scabbardPart .. " in the LeftHand"
			)
			local carry = ClipSampler.sample(layeredBase(), 0)
			carry.Neck = { pos = { 0, 0, 0 }, rot = { 25, 0, 0 } }
			expect(bodyProblems("DrawnHead", probe("DrawnHead", "Base", carry))).toEqual({})
			-- The arm at rest with the sword out hangs the guard in the thigh.
			expect(table.concat(bodyProblems("Hanging", probe("Hanging", "Base", {})), "\n")).toContain(
				"Hanging: the " .. WeaponModels.guardPart .. " in the RightUpperLeg"
			)
			local rest = table.clone(headBack)
			rest.keys = { { time = 0, easing = "Hold", joints = {} } }
			expect(bodyProblems("Rest", rest)).toEqual({})
		end
	)

	it("flags a pose that comes nearer a body part than its margin without touching it", function()
		-- One joint turned until the nearest sheathed piece is half the group's margin from a body
		-- part of that group: the head tipped back to the hilt, the left arm swung back to the
		-- scabbard, the left leg swung back to its tip.
		local cases = {
			{ joint = "Neck", sign = 1, part = "Head", margin = OffBody.margin.head, from = 0, to = 30 },
			{ joint = "LeftShoulder", sign = -1, part = "Left", margin = OffBody.margin.arms, from = 0, to = 10 },
			{ joint = "LeftHip", sign = -1, part = "LeftUpperLeg", margin = OffBody.margin.legs, from = 20, to = 70 },
		}
		for _, case in cases do
			local function pose(degrees: number): any
				local clip = probe("MarginProbe", "Base", { [case.joint] = { rot = { case.sign * degrees, 0, 0 } } })
				clip.sheathed = true
				return clip
			end
			local function gapAt(degrees: number): number
				local tally = newTally()
				checkAlone(tally, "MarginProbe", pose(degrees), always)
				local gap = math.huge
				for _, key in tally.order do
					local part = key:match("|([^|]+)$")
					if part ~= nil and part:sub(1, #case.part) == case.part then
						gap = math.min(gap, tally.closest[key].gap)
					end
				end
				return gap
			end
			local low, high = case.from, case.to
			expect(gapAt(low)).toBe(math.huge) -- the margin kept
			expect(gapAt(high)).toBeLessThan(0)
			for _ = 1, 30 do
				local middle = (low + high) / 2
				local gap = gapAt(middle)
				if gap == math.huge or gap > case.margin / 2 then
					low = middle
				else
					high = middle
				end
			end
			local gap = gapAt(high)
			expect(gap).toBeGreaterThan(0)
			expect(gap).toBeLessThan(case.margin)
			local lines = table.concat(bodyProblems("Near", pose(high)), "\n")
			expect(lines).toContain("studs from the " .. case.part)
			expect(lines).toContain(("(keep %.3f)"):format(case.margin))
		end
	end)

	it(
		"flags a one-shot over the sheathed set, a draw's hand in the hilt before the grab, and a scabbard in the field",
		function()
			local idle = Harness.load(clipsDirectory .. "/" .. Config.layeredOverSheathed)
			-- An Additive flinch that throws the head back, over the idle: the sword is on the back.
			local tally = newTally()
			checkOver(
				tally,
				"Snap",
				probe("Snap", "Additive", { Neck = { rot = { 25, 0, 0 } } }),
				"Idle",
				idle,
				always,
				always,
				never
			)
			expect(table.concat(tallyLines(tally), "\n")).toContain(
				"Snap over Idle: the " .. WeaponModels.gripPart .. " in the Head"
			)
			-- An UpperBody clip overrides the joints it keys.
			local reach = Harness.load(clipsDirectory .. "/Draw")
			local grab = eventTime(reach, "WeaponDraw") :: number
			local grabPose = ClipSampler.sample(reach, grab)
			local held = probe("Held", "UpperBody", grabPose)
			local onHilt = newTally()
			checkOver(onHilt, "Held", held, "Idle", idle, always, always, always)
			expect(tallyLines(onHilt)).toEqual({})
			-- Held there with no draw coming, the hand is in the grip.
			local away = newTally()
			checkOver(away, "Held", held, "Idle", idle, always, always, never)
			expect(table.concat(tallyLines(away), "\n")).toContain(
				"Held over Idle: the " .. WeaponModels.gripPart .. " in the RightHand"
			)
			-- The body sunk into the field takes the scabbard with it.
			local sunk = newTally()
			checkAlone(sunk, "Sunk", probe("Sunk", "FullBody", { Root = { pos = { 0, -4, 0 } } }), never)
			expect(table.concat(tallyLines(sunk), "\n")).toContain("Sunk: the " .. WeaponModels.scabbardPart)
			expect(table.concat(tallyLines(sunk), "\n")).toContain("below the field")
		end
	)

	it("flags a scabbard that stands off the back or goes into it, and passes the mount", function()
		local current = body()
		local torso = current.backPart.Size
		local scabbard = current.pieces[#current.pieces].size
		expect(backGapProblems(torso, current.scabbardC0, scabbard)).toEqual({})
		local most, least = backGap(torso, current.scabbardC0, scabbard)
		expect(most).never.toBeNil()
		expect(least :: number).toBeGreaterThanOrEqual(0)
		local out = backGapProblems(torso, CFrame.new(0, 0, 0.3) * current.scabbardC0, scabbard)
		expect(table.concat(out, "\n")).toContain("studs off the back")
		local into =
			backGapProblems(torso, CFrame.new(0, 0, -((least :: number) + 0.05)) * current.scabbardC0, scabbard)
		expect(table.concat(into, "\n")).toContain("studs into the back")
		-- Tipped away from the back at its lower end, the end stands off it.
		local tipped = backGapProblems(torso, current.scabbardC0 * CFrame.Angles(math.rad(-15), 0, 0), scabbard)
		expect(#tipped).toBeGreaterThan(0)
		expect(backGapProblems(torso, CFrame.new(0, 0, 5) * current.scabbardC0, scabbard)).toEqual({
			"the scabbard stands "
				.. ("%.3f"):format((most :: number) + 5)
				.. " studs off the back (at most "
				.. ("%.2f"):format(OffBody.backGap)
				.. ")",
		})
	end)

	it("flags a layered clip that sinks the blade only over a moving base", function()
		local found = roles()
		-- Draw settling into the drawn idle's own carry (its Weapon key, 4 degrees past it at the
		-- overshoot): the idle holds the point up, a sprint's lean under it puts it in the field.
		local draw = Harness.load(clipsDirectory .. "/Draw")
		local carry = ClipSampler.sample(layeredBase(), 0).Weapon.rot
		local settle = draw.keys[#draw.keys].time
		local low = table.clone(draw)
		low.keys = {}
		for _, key in draw.keys do
			local joints = table.clone(key.joints)
			if key.time >= 0.5 - 1e-9 and joints.Weapon ~= nil then
				local past = if key.time < settle - 1e-9 then 4 else 0
				joints.Weapon = { rot = { carry[1] - past, carry[2], carry[3] } }
			end
			table.insert(low.keys, { time = key.time, easing = key.easing, joints = joints })
		end
		local idleOnly = table.clone(found)
		idleOnly.drawnSet = {}
		for _, entry in found.drawnSet do
			if entry.name == Config.layeredOver then
				table.insert(idleOnly.drawnSet, entry)
			end
		end
		expect(#idleOnly.drawnSet).toBe(1)
		expect(fieldProblems("LowDraw", low, idleOnly)).toEqual({})
		expect(table.concat(fieldProblems("LowDraw", low, found), "\n")).toContain(
			"LowDraw over " .. ChoreoData.locomotion.clips.SprintDrawn .. " from"
		)
	end)

	it("keeps the Rising Arc's re-cock where its torso, sword hand and blade stood", function()
		-- The re-cock twists the waist less than its first form (the waist turned 20 degrees, the
		-- hips at rest) so the hips clear the scabbard; Root and the hips take up the rest, so the
		-- torso, the sword hand and the blade's tip stand where they did.
		local arc = Harness.load(clipsDirectory .. "/RisingArc")
		local first = table.clone(arc)
		first.keys = {}
		local recock = 0
		for _, key in arc.keys do
			local joints = table.clone(key.joints)
			if math.abs(key.time - 0.56) < 1e-9 then
				recock = key.time
				joints.Root = { pos = { 0.04, -0.02, -0.1 }, rot = { 0, -8, -2 } }
				joints.Waist = { rot = { 14, -20, -6 } }
			end
			if math.abs(key.time - 0.56) < 1e-9 or math.abs(key.time - 0.61) < 1e-9 then
				joints.LeftHip, joints.RightHip = nil, nil
			end
			table.insert(first.keys, { time = key.time, easing = key.easing, joints = joints, root = key.root })
		end
		expect(recock).toBe(0.56)
		local current = body()
		local now = solveAt(current, rootAt(current, arc, recock), ClipSampler.sample(arc, recock), "Hand")
		local was = solveAt(current, rootAt(current, first, recock), ClipSampler.sample(first, recock), "Hand")
		for _, name in { "UpperTorso", "RightHand" } do
			expect((now[name].Position - was[name].Position).Magnitude).toBeLessThan(0.02)
		end
		expect(degreesBetween(now.UpperTorso.LookVector, was.UpperTorso.LookVector)).toBeLessThan(1)
		local blade = current.trailEnd.Parent.Name
		local tip = (now[blade] * current.trailEnd.CFrame).Position
		local tipWas = (was[blade] * current.trailEnd.CFrame).Position
		expect((tip - tipWas).Magnitude).toBeLessThan(0.02)
	end)

	it("measures how far a blade edge comes out through the scabbard's wall, at the mouth as in the middle", function()
		local current = body()
		local blade, scabbard = current.pieces[1], current.pieces[#current.pieces]
		local home = CFrame.new()
		local room = math.min(scabbard.size.X - blade.size.X, scabbard.size.Z - blade.size.Z) / 2
		-- Centred, every edge has the room left; beside the scabbard no edge is inside its walls.
		expect(edgePoke(CFrame.new(), blade.size, home, scabbard.size)).toBeCloseTo(-room, 1e-9)
		expect(edgePoke(CFrame.new(scabbard.size.X + blade.size.X, 0, 0), blade.size, home, scabbard.size)).toBeNil()
		-- Turned about a point near the closed end, the part at the mouth comes out first. The
		-- edges walked in fine steps give the same answer.
		local half, sheath = blade.size * 0.5, scabbard.size * 0.5
		local pivot = roblox.Vector3.new(0, sheath.Y - 0.2, 0)
		for _, degrees in { 0.5, 2, 6 } do
			local frame = CFrame.new(pivot) * CFrame.Angles(0, 0, math.rad(degrees)) * CFrame.new(-pivot)
			local walked: number? = nil
			for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
				local counts, out = false, -math.huge
				for step = 0, 4000 do
					local along = -half.Y + blade.size.Y * step / 4000
					local point = frame * roblox.Vector3.new(corner[1] * half.X, along, corner[2] * half.Z)
					if math.abs(point.Y) <= sheath.Y then
						out = math.max(out, math.abs(point.X) - sheath.X, math.abs(point.Z) - sheath.Z)
						counts = counts or (math.abs(point.X) <= sheath.X and math.abs(point.Z) <= sheath.Z)
					end
				end
				if counts then
					walked = if walked == nil then out else math.max(walked, out)
				end
			end
			local exact = edgePoke(frame, blade.size, home, scabbard.size)
			expect(exact).never.toBeNil()
			expect(walked).never.toBeNil()
			expect(math.abs((exact :: number) - (walked :: number))).toBeLessThan(2e-3)
			if degrees >= 2 then
				expect(exact :: number).toBeGreaterThan(0)
			end
		end
	end)

	it(
		"flags a draw that turns the blade out through the scabbard's wall or a flinch that moves the sword arm in the pull",
		function()
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
			expect(#flagged).toBeGreaterThanOrEqual(1)
			expect(flagged[1]).toContain("SlideProbe WeaponDraw: the blade comes")
			expect(flagged[1]).toContain("in the slide")
			-- Held at the grab, the blade stays home in its sheath.
			local still = table.clone(sideways)
			still.keys = { { time = 0, easing = "Hold", joints = grab } }
			expect(slideProblems("Still", still)).toEqual({})
			-- The slide runs on until the blade is clear: Draw's ends past sheathSlide.seconds, its
			-- last edges coming out over the mouth.
			local span = slideSpan(draw, baseFor(draw), "WeaponDraw", grabAt)
			expect(span[#span].away).toBeGreaterThan(Slide.seconds)
			local swing = -math.huge
			for _, sample in span do
				if sample.away > Slide.seconds then
					swing = math.max(swing, sample.out)
				end
			end
			expect(swing).toBeGreaterThan(0)
			expect(swing).toBeLessThanOrEqual(Slide.swingOut)
			-- A flinch that keys the sword arm, landing in the pull, cuts out through the wall.
			local armFlinch = probe("ArmFlinch", "Additive", { RightShoulder = { rot = { 8, 0, 6 } } })
			local lines =
				table.concat(slideProblems("Draw", draw, nil, { { name = "ArmFlinch", clip = armFlinch } }), "\n")
			expect(lines).toContain("Draw WeaponDraw with ArmFlinch from")
			for _, name in { "Draw", "Sheathe" } do
				expect(slideProblems(name, Harness.load(clipsDirectory .. "/" .. name))).toEqual({})
			end
		end
	)
end)

-- The labels a tally should have posed (each clip alone, or "<clip> over <base>") that it did not.
local function uncovered(tally: Tally, alone: { { Entry } }, over: { { Entry } }, bases: { { Entry } }): { string }
	local missing = {}
	for _, set in alone do
		for _, entry in set do
			if not tally.seen[entry.name] then
				table.insert(missing, entry.name)
			end
		end
	end
	for _, set in over do
		for _, entry in set do
			for _, baseSet in bases do
				for _, base in baseSet do
					local label = ("%s over %s"):format(entry.name, base.name)
					if not tally.seen[label] then
						table.insert(missing, label)
					end
				end
			end
		end
	end
	return missing
end

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

	it("swings the blade into the sheath without a jump: Sheathe's tip under sheath.sheatheTipSpeed", function()
		local current = body()
		local clip = Harness.load(clipsDirectory .. "/" .. ChoreoData.sheath.clips.sheathe)
		local base = baseFor(clip)
		local blade = current.trailEnd.Parent.Name
		local step = 1 / Config.sampleHz
		local previous: any = nil
		local worst, worstAt = 0, 0
		for index = 0, math.floor(clip.duration * Config.sampleHz + 1e-6) do
			local time = index * step
			local solved =
				solveAt(current, current.avatar.base, offsetsAt(clip, base, time), ReviewMarkers.mountAt(clip, time))
			local tip = (solved[blade] * current.trailEnd.CFrame).Position
			if previous ~= nil and (tip - previous).Magnitude / step > worst then
				worst, worstAt = (tip - previous).Magnitude / step, time
			end
			previous = tip
		end
		expect(worst).toBeGreaterThan(0)
		if worst > ChoreoData.sheath.sheatheTipSpeed then
			error(
				("Sheathe moves the blade's tip %.1f studs a second at %.4f s (limit %.0f)"):format(
					worst,
					worstAt,
					ChoreoData.sheath.sheatheTipSpeed
				)
			)
		end
	end)

	it("slides the blade along its sheath, inside the scabbard's walls, as it comes out and goes home", function()
		local found = roles()
		local breathe = Harness.load("src/shared/clips/" .. ChoreoData.rigs.PlayerR15.breathing)
		-- The flinches land on a draw (a hit taken while sheathed plays both). DeathFreeze is
		-- left out: it holds the pose the body died in for the half second before it shatters.
		local overlays = {}
		for _, entry in found.additive do
			if not isFreeze(entry.clip) then
				table.insert(overlays, entry)
			end
		end
		expect(#overlays).toBeGreaterThan(0)
		local lines = {}
		local checked = 0
		for _, entry in playerClips() do
			if eventTime(entry.clip, "WeaponDraw") or eventTime(entry.clip, "WeaponSheathe") then
				checked += 1
				for _, line in slideProblems(entry.name, entry.clip, breathe, overlays) do
					table.insert(lines, line)
				end
			end
		end
		expect(checked).toBeGreaterThanOrEqual(2)
		if #lines > 0 then
			error(("%d draw(s) or sheathe(s) cut through the scabbard:\n%s"):format(#lines, table.concat(lines, "\n")))
		end
	end)

	it("hangs the scabbard on the back, flat to it within the back gap", function()
		local current = body()
		local lines = backGapProblems(current.backPart.Size, current.scabbardC0, current.pieces[#current.pieces].size)
		if #lines > 0 then
			error(table.concat(lines, "\n"))
		end
	end)

	it(
		"keeps the sword on its back and the scabbard off the body through the sheathed set and its one-shots",
		function()
			local found = roles()
			for _, entry in found.sheathedSet do
				-- The whole clip plays with the sword on the back.
				expect(ReviewMarkers.mountAt(entry.clip, 0)).toBe("Back")
				expect(ReviewMarkers.mountAt(entry.clip, entry.clip.duration)).toBe("Back")
			end
			local tally = sheathedTally(found)
			expect(tally.frames).toBeGreaterThan(0)
			local missing = uncovered(
				tally,
				{ found.sheathedSet, found.oneShots },
				{ found.additive, found.sheathes },
				{ found.sheathedSet }
			)
			for _, label in uncovered(tally, {}, { found.draws }, { found.sheathedSet, found.drawnSet }) do
				table.insert(missing, label)
			end
			expect(missing).toEqual({})
			local lines = tallyLines(tally)
			if #lines > 0 then
				error(
					("%d sword piece(s) come too near the body with the sword on the back (margins: head %.3f, arms %.3f, legs %.3f, torso %.3f studs):\n%s"):format(
						#lines,
						OffBody.margin.head,
						OffBody.margin.arms,
						OffBody.margin.legs,
						OffBody.margin.torso,
						table.concat(lines, "\n")
					)
				)
			end
		end
	)

	it("keeps the scabbard off the body with the sword drawn", function()
		local found = roles()
		local tally = drawnTally(found)
		expect(tally.frames).toBeGreaterThan(0)
		local missing = uncovered(
			tally,
			{ found.drawnSet, found.attacks },
			{ found.upper, found.additive },
			{ found.drawnSet }
		)
		for _, label in uncovered(tally, {}, { found.draws }, { found.sheathedSet, found.drawnSet }) do
			table.insert(missing, label)
		end
		for _, label in uncovered(tally, {}, { found.sheathes }, { found.sheathedSet }) do
			table.insert(missing, label)
		end
		if not tally.seen[ChoreoData.locomotion.clips.SprintDrawn .. " with the drawn sprint pose"] then
			table.insert(missing, "the drawn sprint pose")
		end
		expect(missing).toEqual({})
		local lines = tallyLines(tally)
		if #lines > 0 then
			error(
				("%d scabbard contact(s) with the sword drawn (margins: head %.3f, arms %.3f, legs %.3f, torso %.3f studs):\n%s"):format(
					#lines,
					OffBody.margin.head,
					OffBody.margin.arms,
					OffBody.margin.legs,
					OffBody.margin.torso,
					table.concat(lines, "\n")
				)
			)
		end
	end)

	it("keeps the blade's tip and guard above the field and both hands off it, over every base", function()
		local found = roles()
		local lines = {}
		for _, entry in playerClips() do
			for _, line in fieldProblems(entry.name, entry.clip, found) do
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
