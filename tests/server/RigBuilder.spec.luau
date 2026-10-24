--!strict
-- RigBuilder under Lune's Instance: part counts, joints, the rest pose through Pose.solve, attachments.
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Pose = Harness.load("src/shared/choreo/Pose")
local Rigs = Harness.load("src/shared/data/rigs")
local Palette = Harness.load("src/shared/data/palette")
local Fx = Harness.load("src/shared/data/fx")

local function countClass(model: any, className: string): number
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA(className) then
			count += 1
		end
	end
	return count
end

local function near(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < 1e-4
end

local function motors(model: any): { [string]: any }
	local map = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			map[descendant.Name] = descendant
		end
	end
	return map
end

describe("RigBuilder.build (Boar)", function()
	local boar = RigBuilder.build("Boar", "Frenzy Boar")

	it("builds 11 parts and 10 Motor6Ds whose Part0 / Part1 all resolve", function()
		expect(boar.Name).toBe("Frenzy Boar")
		expect(countClass(boar, "BasePart")).toBe(11)
		expect(countClass(boar, "Motor6D")).toBe(10)
		local partCount, jointCount = RigBuilder.counts("Boar")
		expect(partCount).toBe(11)
		expect(jointCount).toBe(10)
		for name, motor in motors(boar) do
			expect(motor.Part0).toBeTruthy()
			expect(motor.Part1).toBeTruthy()
			expect(motor.Part0.Parent).toBe(boar)
			expect(motor.Part1.Parent).toBe(boar)
			expect(motor.Parent).toBe(motor.Part1)
			expect(name).toBe(motor.Name)
		end
		for _, joint in Rigs.Boar.joints do
			expect(motors(boar)[joint.name]).toBeTruthy()
		end
	end)

	it(
		"the root is the PrimaryPart, the only colliding part and the assembly root; every part is a flat SmoothPlastic placeholder",
		function()
			local root = boar.PrimaryPart
			expect(root).toBeTruthy()
			expect(root.Name).toBe("HumanoidRootPart")
			expect(root.CanCollide).toBe(true)
			-- The Humanoid moves the assembly root: the root keeps its mass and outranks every limb.
			expect(root.Massless).toBe(false)
			for _, descendant in boar:GetDescendants() do
				if descendant:IsA("BasePart") then
					expect(descendant.Anchored).toBe(false)
					expect(descendant.Material).toBe(Enum.Material.SmoothPlastic)
					if descendant ~= root then
						expect(descendant.CanCollide).toBe(false)
						expect(descendant.Massless).toBe(true)
						expect(descendant.RootPriority).toBeLessThan(root.RootPriority)
					end
					local spec = Rigs.Boar.parts[descendant.Name]
					expect(spec).toBeTruthy()
					expect(near(descendant.Size, Vector3.new(spec.size[1], spec.size[2], spec.size[3]))).toBe(true)
					local rgb = Palette.rgb(spec.color)
					expect(descendant.Color.R).toBeCloseTo(rgb[1], 1e-3)
					expect(descendant.Color.G).toBeCloseTo(rgb[2], 1e-3)
					expect(descendant.Color.B).toBeCloseTo(rgb[3], 1e-3)
				end
			end
		end
	)

	it("gives the model a Humanoid set up for MoveTo only", function()
		local humanoid = boar:FindFirstChildOfClass("Humanoid")
		expect(humanoid).toBeTruthy()
		expect(humanoid.HipHeight).toBeCloseTo(Rigs.Boar.hipHeight, 1e-5)
		expect(humanoid.RequiresNeck).toBe(false)
		expect(humanoid.AutoRotate).toBe(false)
		expect(humanoid.NameDisplayDistance).toBe(0)
		expect(humanoid.HealthDisplayDistance).toBe(0)
		expect(humanoid.BreakJointsOnDeath).toBe(false)
		expect(humanoid.WalkSpeed).toBe(Rigs.Boar.walkSpeed)
	end)

	it("C0 is the rest pose in studs and degrees; C1 comes from c1 or is identity", function()
		local map = motors(boar)
		local neck = map.Neck
		expect(near(neck.C0.Position, Vector3.new(0, 0.4, -2.2))).toBe(true)
		expect(near(neck.C1.Position, Vector3.new(0, 0, 1.1))).toBe(true)
		expect(near(map.Root.C1.Position, Vector3.zero)).toBe(true)
		expect(near(map.Root.C1.LookVector, -Vector3.zAxis)).toBe(true)
		local tusk = map.TuskLeft
		local x, y, z = tusk.C0:ToEulerAnglesXYZ()
		expect(math.deg(x)).toBeCloseTo(20, 1e-3)
		expect(y).toBeCloseTo(0, 1e-9)
		expect(z).toBeCloseTo(0, 1e-9)
	end)

	it("the rest pose puts the head in front of the torso and the legs below it", function()
		local solved = Pose.solve(boar, CFrame.identity, {})
		local torso = solved.Torso.Position
		local head = solved.Head.Position
		expect(head.Z).toBeLessThan(torso.Z - 2) -- -Z is forward
		expect(head.Y).toBeGreaterThan(torso.Y)
		for _, leg in { "FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg" } do
			expect(solved[leg].Position.Y).toBeLessThan(torso.Y - 1)
		end
		expect(solved.FrontLeftLeg.Position.Z).toBeLessThan(solved.BackLeftLeg.Position.Z)
		expect(solved.FrontLeftLeg.Position.X).toBeLessThan(solved.FrontRightLeg.Position.X)
		expect(solved.Tail.Position.Z).toBeGreaterThan(torso.Z)
		expect(solved.Snout.Position.Z).toBeLessThan(head.Z)
		-- The parts were placed at the solved pose before the engine ever sees them.
		expect(near(boar:FindFirstChild("Head").CFrame.Position, head)).toBe(true)
		expect(near(boar:FindFirstChild("HumanoidRootPart").CFrame.Position, Vector3.zero)).toBe(true)
	end)

	it("carries the Placeholder tag and the Rig attribute, and no weapon attachments", function()
		expect(boar:HasTag("Placeholder")).toBe(true)
		expect(boar:GetAttribute("Rig")).toBe("Boar")
		expect(boar:FindFirstChild("WeaponGrip", true)).toBeNil()
		expect(boar:FindFirstChild("TrailStart", true)).toBeNil()
	end)

	it("two builds are identical in shape", function()
		local again = RigBuilder.build("Boar")
		expect(again.Name).toBe("Boar")
		expect(countClass(again, "BasePart")).toBe(11)
		expect(near(again:FindFirstChild("Head").CFrame.Position, boar:FindFirstChild("Head").CFrame.Position)).toBe(
			true
		)
	end)
end)

describe("RigBuilder.build (Kobold)", function()
	local kobold = RigBuilder.build("Kobold", "Kobold Axeman")

	it("builds 8 parts and 7 joints with the axe on the right arm", function()
		expect(countClass(kobold, "BasePart")).toBe(8)
		expect(countClass(kobold, "Motor6D")).toBe(7)
		-- The Kobold's Torso is bigger than its root: only the root's mass and priority keep it the assembly root.
		local root = kobold.PrimaryPart
		local torso = kobold:FindFirstChild("Torso")
		expect(torso.Size.X * torso.Size.Y * torso.Size.Z).toBeGreaterThan(root.Size.X * root.Size.Y * root.Size.Z)
		expect(root.Massless).toBe(false)
		expect(torso.Massless).toBe(true)
		expect(root.RootPriority).toBeGreaterThan(torso.RootPriority)
		local weapon = motors(kobold).Weapon
		expect(weapon.Part0.Name).toBe("RightArm")
		expect(weapon.Part1.Name).toBe("Weapon")
		expect(near(weapon.C1.Position, Vector3.new(0, -1.4, 0))).toBe(true)
	end)

	it("places WeaponGrip at the Weapon joint on the grip part and TrailStart / TrailEnd along the axe", function()
		local grip = kobold:FindFirstChild("RightArm"):FindFirstChild("WeaponGrip")
		expect(grip).toBeTruthy()
		expect(grip:IsA("Attachment")).toBe(true)
		expect(near(grip.CFrame.Position, Vector3.new(0, -1.0, 0))).toBe(true)
		local axe = kobold:FindFirstChild("Weapon")
		local start = axe:FindFirstChild("TrailStart")
		local finish = axe:FindFirstChild("TrailEnd")
		expect(start).toBeTruthy()
		expect(finish).toBeTruthy()
		-- The axe's long axis is Y (3.6 studs); fx.luau's placeholder fractions place the ends.
		expect(start.CFrame.Position.Y).toBeCloseTo(3.6 * Fx.trail.placeholderStart, 1e-4)
		expect(finish.CFrame.Position.Y).toBeCloseTo(3.6 * Fx.trail.placeholderEnd, 1e-4)
		expect(finish.CFrame.Position.Y).toBeGreaterThan(start.CFrame.Position.Y)
	end)

	it("the rest pose puts the head above the torso and the axe forward of the right arm", function()
		local solved = Pose.solve(kobold, CFrame.identity, {})
		expect(solved.Head.Position.Y).toBeGreaterThan(solved.Torso.Position.Y + 1)
		expect(solved.LeftLeg.Position.Y).toBeLessThan(solved.Torso.Position.Y - 1)
		expect(solved.RightArm.Position.X).toBeGreaterThan(solved.LeftArm.Position.X)
		-- The Weapon joint rotates -90 about X, so the axe's +Y (its length) points -Z.
		local axeUp = solved.Weapon.LookVector
		expect(solved.Weapon.UpVector.Z).toBeCloseTo(-1, 1e-5)
		expect(axeUp.Y).toBeCloseTo(-1, 1e-5)
		expect(solved.Weapon.Position.Z).toBeLessThan(solved.RightArm.Position.Z)
	end)
end)

describe("RigBuilder helpers", function()
	it("refuses rigs it does not know and the engine-built player", function()
		expect(function()
			RigBuilder.build("Dragon")
		end).toThrow("no rig")
		expect(function()
			RigBuilder.build("PlayerR15")
		end).toThrow("engine-built")
	end)

	it("lists the placeholder rigs", function()
		expect(RigBuilder.placeholderRigIds()).toEqual({ "Boar", "Kobold" })
	end)

	it("never lets the engine label a rig: one name per enemy, the nameplate's", function()
		-- Under the default Viewer the viewing player's distances apply, so the rig's own zero
		-- distances hid nothing and every enemy showed the engine's name over its nameplate.
		for _, id in RigBuilder.placeholderRigIds() do
			local model = RigBuilder.build(id)
			local humanoids = 0
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("Humanoid") then
					humanoids += 1
					expect(descendant.DisplayDistanceType).toBe(Enum.HumanoidDisplayDistanceType.None)
					expect(descendant.NameDisplayDistance).toBe(0)
					expect(descendant.HealthDisplayDistance).toBe(0)
				end
			end
			expect(humanoids).toBe(1)
			model:Destroy()
		end
	end)

	it("frameOf converts studs and degrees; longAxis prefers Y on ties", function()
		local frame = RigBuilder.frameOf({ pos = { 1, 2, 3 }, rot = { 0, 90, 0 } })
		expect(near(frame.Position, Vector3.new(1, 2, 3))).toBe(true)
		expect(frame.LookVector.X).toBeCloseTo(-1, 1e-5)
		local axis, extent = RigBuilder.longAxis(Vector3.new(2, 2, 1))
		expect(near(axis, Vector3.yAxis)).toBe(true)
		expect(extent).toBe(2)
		axis, extent = RigBuilder.longAxis(Vector3.new(1, 1, 5))
		expect(near(axis, Vector3.zAxis)).toBe(true)
		expect(extent).toBe(5)
		axis = RigBuilder.longAxis(Vector3.new(4, 1, 1))
		expect(near(axis, Vector3.xAxis)).toBe(true)
	end)
end)
