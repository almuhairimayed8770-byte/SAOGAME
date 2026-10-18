--!strict
-- Joints under Lune's Instance: both joint kinds read the same way. Lune knows AnimationConstraint
-- and Attachment, but leaves the constraint's read-only C0 / C1 / Part0 / Part1 aliases unset, so
-- these tests also prove the helper reads the attachments themselves.
local Joints = Harness.load("src/shared/choreo/Joints")

-- Instance properties hold CFrames as 32-bit floats, so a frame read back differs by about 1e-6.
local function near(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-4
		and (a.RightVector - b.RightVector).Magnitude < 1e-4
		and (a.UpVector - b.UpVector).Magnitude < 1e-4
end

local function part(name: string, parent: Instance?): any
	local created = Instance.new("Part")
	created.Name = name
	created.Parent = parent
	return created
end

local function attachment(name: string, parent: Instance?, frame: CFrame): any
	local created = Instance.new("Attachment")
	created.Name = name
	created.CFrame = frame
	created.Parent = parent
	return created
end

-- An AnimationConstraint between two rig attachments, parented to Part1 like the engine's R15.
local function constraint(name: string, part0: any, part1: any, c0: CFrame, c1: CFrame): any
	local joint = Instance.new("AnimationConstraint")
	joint.Name = name
	joint.Attachment0 = attachment(name .. "RigAttachment", part0, c0)
	joint.Attachment1 = attachment(name .. "RigAttachment", part1, c1)
	joint.Parent = part1
	return joint
end

local function motor(name: string, part0: any, part1: any, c0: CFrame, c1: CFrame): any
	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = c0
	joint.C1 = c1
	joint.Parent = part1
	return joint
end

describe("Joints.isJoint / asJoint", function()
	it("accepts a Motor6D and an AnimationConstraint and nothing else", function()
		local motor6D = Instance.new("Motor6D")
		local animation = Instance.new("AnimationConstraint")
		expect(Joints.isJoint(motor6D)).toBe(true)
		expect(Joints.isJoint(animation)).toBe(true)
		expect(Joints.asJoint(motor6D)).toBe(motor6D)
		expect(Joints.asJoint(animation)).toBe(animation)
		for _, className in { "BallSocketConstraint", "Weld", "WeldConstraint", "Attachment", "Part", "Model" } do
			local other = Instance.new(className)
			expect(Joints.isJoint(other)).toBe(false)
			expect(Joints.asJoint(other)).toBeNil()
		end
	end)

	it("lists the two classes in report order", function()
		expect(Joints.CLASSES).toEqual({ "Motor6D", "AnimationConstraint" })
	end)
end)

describe("Joints.parts / frames / resolve", function()
	it("reads a Motor6D's own Part0, Part1, C0 and C1", function()
		local a, b = part("UpperTorso"), part("RightUpperArm")
		local c0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, 0, math.rad(10))
		local c1 = CFrame.new(-0.5, 0.4, 0)
		local joint = motor("RightShoulder", a, b, c0, c1)
		local part0, part1 = Joints.parts(joint)
		expect(part0).toBe(a)
		expect(part1).toBe(b)
		local frame0, frame1 = Joints.frames(joint)
		expect(near(frame0, c0)).toBe(true)
		expect(near(frame1, c1)).toBe(true)
		local resolved = Joints.resolve(joint)
		expect(resolved.name).toBe("RightShoulder")
		expect(resolved.joint).toBe(joint)
	end)

	it("reads an AnimationConstraint through Attachment0 / Attachment1, not the read-only aliases", function()
		local root, lower = part("HumanoidRootPart"), part("LowerTorso")
		local c0 = CFrame.new(0, -1, 0)
		local c1 = CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(5), 0, 0)
		local joint = constraint("Root", root, lower, c0, c1)
		-- Lune leaves the aliases unset: Part0 reads nil and C0 cannot be read at all.
		expect((joint :: any).Part0).toBeNil()
		expect(function()
			return (joint :: any).C0
		end).toThrow()
		local part0, part1 = Joints.parts(joint)
		expect(part0).toBe(root)
		expect(part1).toBe(lower)
		local frame0, frame1 = Joints.frames(joint)
		expect(near(frame0, c0)).toBe(true)
		expect(near(frame1, c1)).toBe(true)
		local resolved = Joints.resolve(joint)
		expect(resolved.part0).toBe(root)
		expect(resolved.part1).toBe(lower)
		expect(near(resolved.c1, c1)).toBe(true)
	end)

	it("composes an attachment nested in another attachment up to its part", function()
		local torso, arm = part("UpperTorso"), part("RightUpperArm")
		local outer = attachment("RightShoulderRigAttachment", torso, CFrame.new(1, 0.5, 0))
		local inner = attachment("JointRotation", outer, CFrame.Angles(0, 0, math.rad(30)))
		local joint = Instance.new("AnimationConstraint")
		joint.Attachment0 = inner
		joint.Attachment1 = attachment("RightShoulderRigAttachment", arm, CFrame.new(-0.5, 0.4, 0))
		local part0 = Joints.parts(joint)
		expect(part0).toBe(torso)
		local frame0 = Joints.frames(joint)
		expect(near(frame0, CFrame.new(1, 0.5, 0) * CFrame.Angles(0, 0, math.rad(30)))).toBe(true)
	end)

	it("leaves a joint unresolved while a part or an attachment is missing", function()
		local loose = Instance.new("AnimationConstraint")
		local part0, part1 = Joints.parts(loose)
		expect(part0).toBeNil()
		expect(part1).toBeNil()
		local frame0, frame1 = Joints.frames(loose)
		expect(near(frame0, CFrame.identity)).toBe(true)
		expect(near(frame1, CFrame.identity)).toBe(true)
		expect(Joints.resolve(loose)).toBeNil()

		-- An attachment under something that is not a part has no part to ride on.
		local half = Instance.new("AnimationConstraint")
		half.Attachment0 = attachment("Floating", Instance.new("Folder"), CFrame.identity)
		half.Attachment1 = attachment("RootRigAttachment", part("LowerTorso"), CFrame.identity)
		expect(Joints.resolve(half)).toBeNil()

		local motor6D = Instance.new("Motor6D")
		motor6D.Part1 = part("RightHand")
		expect(Joints.resolve(motor6D)).toBeNil()
	end)
end)

describe("Joints over a model", function()
	-- A model with a Motor6D "Weapon", an AnimationConstraint "Waist", a second "Waist" (a Motor6D),
	-- an unresolved AnimationConstraint "Neck" and a BallSocketConstraint that is not a joint.
	local function mixedModel(): (any, { [string]: any })
		local model = Instance.new("Model")
		local lower = part("LowerTorso", model)
		local upper = part("UpperTorso", model)
		local hand = part("RightHand", model)
		local blade = part("Weapon", model)
		local made = {}
		made.waist = constraint("Waist", lower, upper, CFrame.new(0, 0.2, 0), CFrame.new(0, -0.8, 0))
		made.weapon = motor("Weapon", hand, blade, CFrame.new(0, -0.3, 0), CFrame.identity)
		made.waistMotor = motor("Waist", lower, upper, CFrame.identity, CFrame.identity)
		local neck = Instance.new("AnimationConstraint")
		neck.Name = "Neck"
		neck.Parent = upper
		made.neck = neck
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = "WaistBallSocket"
		socket.Parent = upper
		return model, made
	end

	it("list finds every joint of either kind and skips other constraints", function()
		local model = mixedModel()
		local listed = Joints.list(model)
		expect(#listed).toBe(4)
		for _, joint in listed do
			expect(Joints.isJoint(joint)).toBe(true)
		end
	end)

	it("collect resolves only the joints whose parts are set", function()
		local model = mixedModel()
		local names = {}
		for _, entry in Joints.collect(model) do
			table.insert(names, entry.name)
		end
		table.sort(names)
		expect(names).toEqual({ "Waist", "Waist", "Weapon" })
	end)

	it("byName groups duplicates; map keeps the first joint of each name", function()
		local model, made = mixedModel()
		local grouped = Joints.byName(model)
		expect(#grouped.Waist).toBe(2)
		expect(#grouped.Weapon).toBe(1)
		expect(#grouped.Neck).toBe(1)
		expect(grouped.WaistBallSocket).toBeNil()
		local named = Joints.map(model)
		expect(named.Waist).toBe(grouped.Waist[1])
		expect(named.Weapon).toBe(made.weapon)
		expect(named.Neck).toBe(made.neck)
	end)

	it("setTransform writes Transform on both kinds", function()
		local _, made = mixedModel()
		local turn = CFrame.Angles(0, math.rad(20), 0)
		Joints.setTransform(made.waist, turn)
		Joints.setTransform(made.weapon, turn)
		expect(near(made.waist.Transform, turn)).toBe(true)
		expect(near(made.weapon.Transform, turn)).toBe(true)
	end)
end)
