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
	the Mixer layers them.

	It fails when the blade's tip or guard end (TrailEnd / TrailStart) sinks below the field's top
	face by more than groundClearance.bladeMargin, or a corner of either hand goes below that face,
	and names every clip and time range with its lowest point.

	This is its own spec rather than a section of HitMatrix.spec.luau: it is a property of the clip
	data (like clips.spec.luau), it reuses only the matrix's rig and field, and it runs in about eight
	seconds without the matrix's server swings.
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

type Body = {
	avatar: any,
	fieldTop: number,
	trailStart: any,
	trailEnd: any,
	hands: { any },
}

local standing: Body? = nil
local function body(): Body
	if standing == nil then
		local avatar, field = HitMatrix.standing(Harness)
		local trailStart = avatar.model:FindFirstChild("TrailStart", true)
		local trailEnd = avatar.model:FindFirstChild("TrailEnd", true)
		assert(trailStart ~= nil and trailEnd ~= nil, "the matrix's sword has no TrailStart / TrailEnd")
		standing = {
			avatar = avatar,
			fieldTop = field.CFrame.Position.Y + halfHeight(field.CFrame, field.Size),
			trailStart = trailStart,
			trailEnd = trailEnd,
			hands = { avatar.model:FindFirstChild("RightHand"), avatar.model:FindFirstChild("LeftHand") },
		}
	end
	return standing :: Body
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
		local solved = Pose.solve(avatar.model, rootCFrame, offsetsAt(clip, base, time))
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

local function baseFor(clip: any): any?
	if clip.layer == "UpperBody" or clip.layer == "Additive" then
		return layeredBase()
	end
	return nil
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
		local attacks = 0
		for _, entry in clips do
			layers[entry.clip.layer] = (layers[entry.clip.layer] or 0) + 1
			if entry.clip.attack then
				attacks += 1
			end
			expect(#sampleTimes(entry.clip)).toBeGreaterThanOrEqual(math.floor(entry.clip.duration * Config.sampleHz))
		end
		expect(#clips).toBe(#Harness.listFiles(clipsDirectory, "%.luau$"))
		expect(attacks).toBeGreaterThan(0)
		for _, layer in { "Base", "UpperBody", "FullBody", "Additive" } do
			expect(layers[layer] or 0).toBeGreaterThan(0)
		end
		expect(layeredBase().layer).toBe("Base")
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
	end)
end)

describe("ground clearance: every player clip", function()
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
