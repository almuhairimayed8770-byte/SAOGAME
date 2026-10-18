--!strict
-- Pose over both joint kinds. The player character under the Avatar Joint Upgrade carries its 15
-- R15 joints as AnimationConstraints between rig attachments (no Motor6D at all) plus the Weapon
-- Motor6D WeaponBuilder adds; enemies carry Motor6Ds. The same R15 is built both ways here (Lune
-- knows AnimationConstraint and Attachment, so no fake is needed) and must solve to the same part
-- CFrames, and the server's blade path through the AnimationConstraint rig must match.
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local HitSweep = Harness.load("src/server/combat/HitSweep")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local Weapons = Harness.load("src/shared/data/weapons")
local Rigs = Harness.load("src/shared/data/rigs")
local Horizontal = Harness.load("src/shared/clips/player/OneHandedSword/Horizontal")
local SharpNail = Harness.load("src/shared/clips/player/OneHandedSword/SharpNail")

local SWORD = Weapons.byId("TrialistSword")
local ROOT = CFrame.new(4, 3, -2) * CFrame.Angles(0, math.rad(35), 0)
-- Instance properties hold CFrames as 32-bit floats; both rigs read the same stored values, so
-- they agree far tighter than this, but a hand-computed expectation differs by about 1e-6.
local EPSILON = 1e-4

-- Engine-style R15 joint frames: the Part0-side and Part1-side rig attachments (the classic R15
-- values for the root and the arms). One pair is turned so orientation has to compose correctly.
local FRAMES: { [string]: { CFrame } } = {
	Root = { CFrame.new(0, -1, 0), CFrame.new(0, -0.2, 0) },
	Waist = { CFrame.new(0, 0.2, 0), CFrame.new(0, -0.8, 0) },
	Neck = { CFrame.new(0, 0.8, 0), CFrame.new(0, -0.5, 0) },
	LeftShoulder = { CFrame.new(-1, 0.563, 0), CFrame.new(0.5, 0.394, 0) },
	LeftElbow = { CFrame.new(0, -0.334, 0), CFrame.new(0, 0.259, 0) },
	LeftWrist = { CFrame.new(0, -0.501, 0), CFrame.new(0, 0.125, 0) },
	RightShoulder = {
		CFrame.new(1, 0.563, 0) * CFrame.Angles(0, 0, math.rad(12)),
		CFrame.new(-0.5, 0.394, 0) * CFrame.Angles(0, math.rad(-7), 0),
	},
	RightElbow = { CFrame.new(0, -0.334, 0), CFrame.new(0, 0.259, 0) },
	RightWrist = { CFrame.new(0, -0.501, 0), CFrame.new(0, 0.125, 0) },
	LeftHip = { CFrame.new(-0.5, -0.2, 0), CFrame.new(0, 0.42, 0) },
	LeftKnee = { CFrame.new(0, -0.42, 0), CFrame.new(0, 0.29, 0) },
	LeftAnkle = { CFrame.new(0, -0.55, 0), CFrame.new(0, 0.1, 0) },
	RightHip = { CFrame.new(0.5, -0.2, 0), CFrame.new(0, 0.42, 0) },
	RightKnee = { CFrame.new(0, -0.42, 0), CFrame.new(0, 0.29, 0) },
	RightAnkle = { CFrame.new(0, -0.55, 0), CFrame.new(0, 0.1, 0) },
}

type Kind = "Motor6D" | "AnimationConstraint"

-- The R15 joint list from rigs.luau without the Weapon joint (WeaponBuilder adds that one).
local function r15Joints(): { any }
	local list = {}
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name ~= "Weapon" then
			table.insert(list, joint)
		end
	end
	return list
end

-- Builds the R15 character with its joints of one kind, the way the engine lays them out (each
-- joint parented to its Part1), and equips the Trialist Sword through WeaponBuilder.
local function buildCharacter(kind: Kind): any
	local model = Instance.new("Model")
	model.Name = kind .. "Character"
	local parts = {}
	local function part(name: string): any
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Size = Vector3.one
		created.CFrame = ROOT
		created.Parent = model
		parts[name] = created
		return created
	end
	local root = part("HumanoidRootPart")
	model.PrimaryPart = root
	for _, spec in r15Joints() do
		local part0, part1 = part(spec.part0), part(spec.part1)
		local frames = FRAMES[spec.name]
		assert(frames ~= nil, "no fixture frames for " .. spec.name)
		if kind == "Motor6D" then
			local motor = Instance.new("Motor6D")
			motor.Name = spec.name
			motor.Part0 = part0
			motor.Part1 = part1
			motor.C0 = frames[1]
			motor.C1 = frames[2]
			motor.Parent = part1
		else
			local attachment0 = Instance.new("Attachment")
			attachment0.Name = spec.name .. "RigAttachment"
			attachment0.CFrame = frames[1]
			attachment0.Parent = part0
			local attachment1 = Instance.new("Attachment")
			attachment1.Name = spec.name .. "RigAttachment"
			attachment1.CFrame = frames[2]
			attachment1.Parent = part1
			local joint = Instance.new("AnimationConstraint")
			joint.Name = spec.name
			joint.Attachment0 = attachment0
			joint.Attachment1 = attachment1
			joint.Parent = part1
			-- The upgrade also adds a ball socket on the same attachments (none on Root); it is not a joint.
			if spec.name ~= "Root" then
				local socket = Instance.new("BallSocketConstraint")
				socket.Name = spec.name .. "BallSocket"
				socket.Attachment0 = attachment0
				socket.Attachment1 = attachment1
				socket.Parent = part1
			end
		end
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	WeaponBuilder.equip(model, SWORD)
	return model
end

local function near(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < EPSILON
		and (a.RightVector - b.RightVector).Magnitude < EPSILON
		and (a.UpVector - b.UpVector).Magnitude < EPSILON
end

-- Every part name both solves reached, after checking the two reached the same set.
local function sameSolve(a: { [string]: CFrame }, b: { [string]: CFrame }): (boolean, string?)
	for name, frame in a do
		local other = b[name]
		if other == nil then
			return false, name .. " is solved on one rig only"
		end
		if not near(frame, other) then
			return false, name .. " differs"
		end
	end
	for name in b do
		if a[name] == nil then
			return false, name .. " is solved on one rig only"
		end
	end
	return true, nil
end

local function count(map: { [string]: any }): number
	local total = 0
	for _ in map do
		total += 1
	end
	return total
end

-- Every clip time inside a clip's hit windows, sampled the way the server sweeps them.
local function windowTimes(clip: any): { number }
	local times = {}
	for _, window in ClipSampler.hitWindows(clip) do
		for _, time in HitSweep.samplePath(clip, window) do
			table.insert(times, time)
		end
	end
	return times
end

describe("Pose.solve over AnimationConstraint joints", function()
	local motorRig = buildCharacter("Motor6D")
	local constraintRig = buildCharacter("AnimationConstraint")

	it("the AnimationConstraint rig really has no R15 Motor6D: only WeaponBuilder's Weapon joint", function()
		local motors, constraints = {}, 0
		for _, descendant in constraintRig:GetDescendants() do
			if descendant:IsA("Motor6D") then
				table.insert(motors, descendant.Name)
			elseif descendant:IsA("AnimationConstraint") then
				constraints += 1
			end
		end
		expect(motors).toEqual({ "Weapon" })
		expect(constraints).toBe(15)
	end)

	it("solves every part, down to the hand and the blade, from the root", function()
		local solved = Pose.solve(constraintRig, ROOT, {})
		-- The root, 15 R15 parts and the blade.
		expect(count(solved)).toBe(17)
		expect(solved.RightHand).never.toBeNil()
		expect(solved.Weapon).never.toBeNil()
	end)

	it("hangs Part1 from the Part1-side attachment: the rest pose matches the joint rule by hand", function()
		local solved = Pose.solve(constraintRig, ROOT, {})
		local root = FRAMES.Root
		local lowerTorso = ROOT * root[1] * root[2]:Inverse()
		expect(near(solved.LowerTorso, lowerTorso)).toBe(true)
		local waist = FRAMES.Waist
		local shoulder = FRAMES.RightShoulder
		local upperArm = lowerTorso * waist[1] * waist[2]:Inverse() * shoulder[1] * shoulder[2]:Inverse()
		expect(near(solved.RightUpperArm, upperArm)).toBe(true)
	end)

	it("puts each joint's offset between its two attachments: Part0 * C0 * Transform * C1:Inverse()", function()
		local offsets = {
			Root = { pos = { 0, 0.3, 0 }, rot = { 0, 25, 0 } },
			Waist = { pos = { 0, 0, 0 }, rot = { 10, -30, 5 } },
			RightShoulder = { pos = { 0, 0, 0 }, rot = { 70, 0, -20 } },
		}
		local solved = Pose.solve(constraintRig, ROOT, offsets)
		local root, waist, shoulder = FRAMES.Root, FRAMES.Waist, FRAMES.RightShoulder
		local lowerTorso = ROOT * root[1] * ClipSampler.toCFrame(offsets.Root) * root[2]:Inverse()
		local upperTorso = lowerTorso * waist[1] * ClipSampler.toCFrame(offsets.Waist) * waist[2]:Inverse()
		local upperArm = upperTorso * shoulder[1] * ClipSampler.toCFrame(offsets.RightShoulder) * shoulder[2]:Inverse()
		expect(near(solved.LowerTorso, lowerTorso)).toBe(true)
		expect(near(solved.UpperTorso, upperTorso)).toBe(true)
		expect(near(solved.RightUpperArm, upperArm)).toBe(true)
	end)

	it("gives the same part CFrames as the Motor6D rig at rest", function()
		local same, problem = sameSolve(Pose.solve(motorRig, ROOT, {}), Pose.solve(constraintRig, ROOT, {}))
		expect(problem).toBeNil()
		expect(same).toBe(true)
	end)

	it("gives the same part CFrames as the Motor6D rig under the Horizontal and Sharp Nail offsets", function()
		local compared = 0
		for _, clip in { Horizontal, SharpNail } do
			for _, time in windowTimes(clip) do
				local offsets = ClipSampler.sample(clip, time)
				local same, problem =
					sameSolve(Pose.solve(motorRig, ROOT, offsets), Pose.solve(constraintRig, ROOT, offsets))
				if not same then
					error(("%s at %.3f: %s"):format(clip.id, time, tostring(problem)))
				end
				compared += 1
			end
		end
		expect(compared).toBeGreaterThan(20)
	end)

	it("skips joints it cannot use: off the root's tree, a second on a solved part, half attached", function()
		local cluttered = buildCharacter("AnimationConstraint")
		local function loosePart(name: string): any
			local created = Instance.new("Part")
			created.Name = name
			created.Parent = cluttered
			return created
		end
		local function attach(parent: any, frame: CFrame): any
			local created = Instance.new("Attachment")
			created.CFrame = frame
			created.Parent = parent
			return created
		end
		-- A constraint between two parts no joint path from the root reaches.
		local looseA, looseB = loosePart("LooseA"), loosePart("LooseB")
		local off = Instance.new("AnimationConstraint")
		off.Name = "Loose"
		off.Attachment0 = attach(looseA, CFrame.identity)
		off.Attachment1 = attach(looseB, CFrame.new(0, 1, 0))
		off.Parent = looseB
		-- A second RightShoulder on the engine's attachments (a stale copy left by a rebuild): one
		-- of the two solves the arm, the other can never resolve.
		local upperTorso = cluttered:FindFirstChild("UpperTorso")
		local upperArm = cluttered:FindFirstChild("RightUpperArm")
		local original = upperArm:FindFirstChild("RightShoulder")
		local duplicate = Instance.new("AnimationConstraint")
		duplicate.Name = "RightShoulder"
		duplicate.Attachment0 = original.Attachment0
		duplicate.Attachment1 = original.Attachment1
		duplicate.Parent = upperArm
		-- A constraint whose second attachment never arrived.
		local half = Instance.new("AnimationConstraint")
		half.Name = "Half"
		half.Attachment0 = attach(upperTorso, CFrame.identity)
		half.Parent = upperTorso

		local offsets = ClipSampler.sample(Horizontal, 0.4)
		local solved = Pose.solve(cluttered, ROOT, offsets)
		expect(solved.LooseA).toBeNil()
		expect(solved.LooseB).toBeNil()
		local same, problem = sameSolve(Pose.solve(constraintRig, ROOT, offsets), solved)
		expect(problem).toBeNil()
		expect(same).toBe(true)
	end)

	it("offsets move the AnimationConstraint rig: the blade is not at its rest pose mid-cut", function()
		local rest = Pose.solve(constraintRig, ROOT, {})
		local cut = Pose.solve(constraintRig, ROOT, ClipSampler.sample(Horizontal, 0.4))
		expect((cut.Weapon.Position - rest.Weapon.Position).Magnitude).toBeGreaterThan(0.5)
	end)
end)

describe("HitSweep.bladePath on an AnimationConstraint rig", function()
	local motorRig = buildCharacter("Motor6D")
	local constraintRig = buildCharacter("AnimationConstraint")

	it("finds the blade and matches the Motor6D rig sample for sample", function()
		for _, clip in { Horizontal, SharpNail } do
			local times = windowTimes(clip)
			local motorStart, motorEnd = HitSweep.trailAttachments(motorRig)
			local constraintStart, constraintEnd = HitSweep.trailAttachments(constraintRig)
			expect(constraintStart).never.toBeNil()
			expect(constraintEnd).never.toBeNil()
			local expected = HitSweep.bladePath(motorRig, ROOT, clip, times, motorStart, motorEnd)
			local path = HitSweep.bladePath(constraintRig, ROOT, clip, times, constraintStart, constraintEnd)
			expect(path).never.toBeNil()
			expect(#path).toBe(#times)
			expect(#path).toBeGreaterThan(0)
			for index, sample in path do
				local reference = expected[index]
				expect(sample.time).toBe(reference.time)
				expect((sample.start - reference.start).Magnitude).toBeLessThan(EPSILON)
				expect((sample.finish - reference.finish).Magnitude).toBeLessThan(EPSILON)
			end
		end
	end)

	it("sweeps the tip across the Horizontal window instead of holding it still", function()
		local times = windowTimes(Horizontal)
		local trailStart, trailEnd = HitSweep.trailAttachments(constraintRig)
		local path = HitSweep.bladePath(constraintRig, ROOT, Horizontal, times, trailStart, trailEnd)
		expect((path[#path].finish - path[1].finish).Magnitude).toBeGreaterThan(1)
	end)
end)
