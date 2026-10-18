--!strict
-- WeaponBuilder under Lune's Instance: the three-part stand-in, its FX instances, equip's Motor6D
-- and the scabbard on the back mount.
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")
local Palette = Harness.load("src/shared/data/palette")
local Fx = Harness.load("src/shared/data/fx")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local RigBuilder = Harness.load("src/server/world/RigBuilder")

local SWORD = Weapons.byId("TrialistSword")

local function near(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < 1e-4
end

local function countClass(model: any, className: string): number
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA(className) then
			count += 1
		end
	end
	return count
end

-- A stand-in for the engine-built R15 character: a root and a right hand.
local function character(): any
	local model = Instance.new("Model")
	model.Name = "Tester"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = model
	model.PrimaryPart = root
	local hand = Instance.new("Part")
	hand.Name = "RightHand"
	hand.Size = Vector3.new(1, 0.4, 1)
	hand.CFrame = CFrame.new(1.5, 1.2, 0)
	hand.Parent = model
	-- One joint from the root to the hand so Pose.solve can reach the Weapon motor.
	local wrist = Instance.new("Motor6D")
	wrist.Name = "RightWrist"
	wrist.Part0 = root
	wrist.Part1 = hand
	wrist.C0 = root.CFrame:Inverse() * hand.CFrame
	wrist.C1 = CFrame.identity
	wrist.Parent = hand
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	return model, hand, root
end

describe("WeaponBuilder.build", function()
	local model = WeaponBuilder.build(SWORD)
	local blade = model:FindFirstChild("Weapon")
	local geometry = WeaponModels.get("OneHandedSword")

	it("is a Model named Weapon with a blade named Weapon as PrimaryPart, a guard and a grip", function()
		expect(model.Name).toBe("Weapon")
		expect(blade).toBeTruthy()
		expect(blade:IsA("BasePart")).toBe(true)
		expect(model.PrimaryPart).toBe(blade)
		expect(countClass(model, "BasePart")).toBe(WeaponModels.partsPerWeapon)
		expect(model:FindFirstChild("Guard")).toBeTruthy()
		expect(model:FindFirstChild("Grip")).toBeTruthy()
		expect(countClass(model, "WeldConstraint")).toBe(2)
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("WeldConstraint") then
				expect(descendant.Part0).toBe(blade)
				expect(descendant.Part1).toBe(descendant.Parent)
			end
		end
	end)

	it("sizes the blade along +Y from the category table and places the guard and grip below it", function()
		expect(near(blade.Size, Vector3.new(geometry.blade.width, geometry.blade.length, geometry.blade.thickness))).toBe(
			true
		)
		local guard = model:FindFirstChild("Guard")
		local grip = model:FindFirstChild("Grip")
		local bladeY = blade.CFrame.Position.Y
		expect(guard.CFrame.Position.Y).toBeCloseTo(
			bladeY - geometry.blade.length / 2 - geometry.guard.height / 2,
			1e-4
		)
		expect(grip.CFrame.Position.Y).toBeCloseTo(
			bladeY - geometry.blade.length / 2 - geometry.guard.height - geometry.grip.length / 2,
			1e-4
		)
		expect(grip.CFrame.Position.Y).toBeLessThan(guard.CFrame.Position.Y)
	end)

	it("every part is a flat SmoothPlastic placeholder that neither collides nor weighs", function()
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				expect(descendant.Material).toBe(Enum.Material.SmoothPlastic)
				expect(descendant.CanCollide).toBe(false)
				expect(descendant.Massless).toBe(true)
				expect(descendant.Anchored).toBe(false)
			end
		end
		local steel = Palette.rgb("PlaceholderSteel")
		local wood = Palette.rgb("PlaceholderWood")
		expect(blade.Color.R).toBeCloseTo(steel[1], 1e-3)
		expect(model:FindFirstChild("Grip").Color.R).toBeCloseTo(wood[1], 1e-3)
	end)

	it("carries TrailStart at the guard and TrailEnd at the tip", function()
		local start = blade:FindFirstChild("TrailStart")
		local finish = blade:FindFirstChild("TrailEnd")
		expect(start:IsA("Attachment")).toBe(true)
		expect(finish:IsA("Attachment")).toBe(true)
		expect(near(start.CFrame.Position, Vector3.new(0, -geometry.blade.length / 2, 0))).toBe(true)
		expect(near(finish.CFrame.Position, Vector3.new(0, geometry.blade.length / 2, 0))).toBe(true)
	end)

	it("pre-creates a disabled Trail from fx.luau in the weapon's color and a disabled activation light", function()
		local trail = blade:FindFirstChildOfClass("Trail")
		expect(trail).toBeTruthy()
		expect(trail.Enabled).toBe(false)
		expect(trail.Lifetime).toBeCloseTo(Fx.trail.lifetime, 1e-5)
		expect(trail.LightEmission).toBeCloseTo(Fx.trail.lightEmission, 1e-5)
		expect(trail.MinLength).toBeCloseTo(Fx.trail.minLength, 1e-5)
		expect(trail.Attachment0).toBe(blade:FindFirstChild("TrailStart"))
		expect(trail.Attachment1).toBe(blade:FindFirstChild("TrailEnd"))
		expect(#trail.WidthScale.Keypoints).toBe(#Fx.trail.widthKeys)
		local rgb = Palette.rgb(SWORD.trailColor)
		expect(trail.Color.Keypoints[1].Value.R).toBeCloseTo(rgb[1], 1e-3)
		local light = blade:FindFirstChildOfClass("PointLight")
		expect(light).toBeTruthy()
		expect(light.Enabled).toBe(false)
		expect(light.Range).toBeCloseTo(Fx.activationLight.range, 1e-5)
		expect(light.Brightness).toBeCloseTo(Fx.activationLight.brightness, 1e-5)
	end)

	it("writes the trail attributes fx.luau names and tags the model Placeholder", function()
		expect(blade:GetAttribute(Fx.trail.widthAttribute)).toBe(SWORD.trailWidth)
		expect(blade:GetAttribute(Fx.trail.colorAttribute)).toBe(SWORD.trailColor)
		expect(model:GetAttribute("WeaponId")).toBe("TrialistSword")
		expect(model:GetAttribute("WeaponCategory")).toBe("OneHandedSword")
		expect(model:HasTag("Placeholder")).toBe(true)
	end)

	it("builds every starter weapon", function()
		for _, category in Weapons.rarityOrder do
			expect(category).toBeTruthy()
		end
		for category, id in Weapons.starters do
			local weapon = WeaponBuilder.build(Weapons.byId(id))
			expect(weapon.PrimaryPart.Name).toBe("Weapon")
			expect(weapon:GetAttribute("WeaponCategory")).toBe(category)
			expect(countClass(weapon, "BasePart")).toBe(3)
		end
		expect(WeaponBuilder.build(Weapons.byId("TrialistBuckler")).PrimaryPart.Shape).toBe(Enum.PartType.Cylinder)
	end)
end)

describe("WeaponBuilder.equip", function()
	it(
		"hangs the blade from the RightHand on a Motor6D named Weapon with C0 from rigs.luau and C1 at the grip",
		function()
			local model, hand = character()
			local weapon = WeaponBuilder.equip(model, SWORD)
			expect(weapon.Parent).toBe(model)
			local blade = weapon.PrimaryPart
			local motor = blade:FindFirstChild("Weapon")
			expect(motor).toBeTruthy()
			expect(motor:IsA("Motor6D")).toBe(true)
			expect(motor.Part0).toBe(hand)
			expect(motor.Part1).toBe(blade)
			local joint = WeaponBuilder.gripJoint()
			expect(joint.part0).toBe("RightHand")
			expect(near(motor.C0.Position, Vector3.new(joint.c0.pos[1], joint.c0.pos[2], joint.c0.pos[3]))).toBe(true)
			local rx = motor.C0:ToEulerAnglesXYZ()
			expect(math.deg(rx)).toBeCloseTo(joint.c0.rot[1], 1e-3)
			expect(motor.C1.Position.Y).toBeCloseTo(-WeaponModels.holdOffset("OneHandedSword"), 1e-4)
			expect(model:GetAttribute("WeaponId")).toBe("TrialistSword")
			expect(hand:FindFirstChild("WeaponGrip")).toBeTruthy()
		end
	)

	it("the blade points forward out of the hand with the grip in the fist", function()
		local model, hand = character()
		local weapon = WeaponBuilder.equip(model, SWORD)
		local blade = weapon.PrimaryPart
		-- Where the joint holds it: Part1 = Part0 * C0 * C1^-1 (Pose's rule); the parts start there too.
		local solved = Pose.solve(model, model.PrimaryPart.CFrame, {})
		expect(solved.Weapon).toBeTruthy()
		expect((blade.CFrame.Position - solved.Weapon.Position).Magnitude).toBeLessThan(1e-3)
		-- The hand's -Z is forward; the blade's +Y (its length) points that way.
		expect(blade.CFrame.UpVector.Z).toBeCloseTo(-1, 1e-5)
		local jointPoint = hand.CFrame * blade:FindFirstChild("Weapon").C0
		-- The grip's center sits at the joint; the tip is one blade length ahead of the guard.
		local grip = weapon:FindFirstChild("Grip")
		expect((grip.CFrame.Position - jointPoint.Position).Magnitude).toBeLessThan(1e-3)
		local tip = blade.CFrame * blade:FindFirstChild("TrailEnd").CFrame
		expect(tip.Position.Z).toBeLessThan(grip.CFrame.Position.Z - 3)
	end)

	it("re-equipping replaces the weapon and unequip clears it", function()
		local model, hand = character()
		local first = WeaponBuilder.equip(model, SWORD)
		local second = WeaponBuilder.equip(model, Weapons.byId("TrialistKatana"))
		expect(first.Parent).toBeNil()
		expect(second.Parent).toBe(model)
		expect(WeaponBuilder.equipped(model)).toBe(second)
		expect(model:GetAttribute("WeaponId")).toBe("TrialistKatana")
		local motorCount = 0
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("Motor6D") and descendant.Name == "Weapon" then
				motorCount += 1
			end
		end
		expect(motorCount).toBe(1)
		WeaponBuilder.unequip(model)
		expect(WeaponBuilder.equipped(model)).toBeNil()
		expect(model:GetAttribute("WeaponId")).toBeNil()
		expect(hand:FindFirstChild("Weapon")).toBeNil()
	end)

	it("refuses a character without a RightHand", function()
		local model = Instance.new("Model")
		expect(function()
			WeaponBuilder.equip(model, SWORD)
		end).toThrow("RightHand")
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The sheath: a scabbard welded to the back
-- ------------------------------------------------------------------------------------------

-- A stand-in with a body to carry the scabbard: a root, an UpperTorso and a right hand, jointed
-- root -> UpperTorso -> RightHand so Pose.solve reaches the weapon from either part.
local function characterWithTorso(): any
	local model = Instance.new("Model")
	model.Name = "Tester"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = model
	model.PrimaryPart = root
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 1.6, 1)
	torso.CFrame = CFrame.new(0, 4.2, 0)
	torso.Parent = model
	local hand = Instance.new("Part")
	hand.Name = "RightHand"
	hand.Size = Vector3.new(1, 0.4, 1)
	hand.CFrame = CFrame.new(1.5, 2.6, 0)
	hand.Parent = model
	local function joint(name: string, part0: any, part1: any)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = part0.CFrame:Inverse() * part1.CFrame
		motor.C1 = CFrame.identity
		motor.Parent = part1
	end
	joint("Waist", root, torso)
	joint("RightWrist", torso, hand)
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	return model, torso, hand
end

local function sheathsOf(model: any): { any }
	local list = {}
	for _, child in model:GetChildren() do
		if child.Name == "Sheath" then
			table.insert(list, child)
		end
	end
	return list
end

local function sameFrame(a: CFrame, b: CFrame): boolean
	return near(a.Position, b.Position)
		and near(a.RightVector, b.RightVector)
		and near(a.UpVector, b.UpVector)
		and near(a.LookVector, b.LookVector)
end

local function jointNames(model: any): { string }
	local names = {}
	for _, entry in Joints.collect(model) do
		table.insert(names, entry.name)
	end
	table.sort(names)
	return names
end

describe("WeaponBuilder sheath", function()
	local row = WeaponModels.sheath("OneHandedSword")
	local geometry = WeaponModels.get("OneHandedSword")

	it("the one-handed sword has a back mount on the UpperTorso", function()
		expect(row).toBeTruthy()
		expect(row.part).toBe("UpperTorso")
		expect(WeaponModels.sheath("Rapier")).toBeNil()
	end)

	it("equip welds one placeholder scabbard to the UpperTorso at the back mount", function()
		local model, torso = characterWithTorso()
		WeaponBuilder.equip(model, SWORD)
		local sheaths = sheathsOf(model)
		expect(#sheaths).toBe(1)
		local sheath = sheaths[1]
		expect(sheath:IsA("Model")).toBe(true)
		expect(WeaponBuilder.sheathOf(model)).toBe(sheath)
		expect(sheath:HasTag(WeaponModels.tag)).toBe(true)
		expect(countClass(sheath, "BasePart")).toBe(1)
		local scabbard = sheath:FindFirstChild("Scabbard")
		expect(scabbard).toBeTruthy()
		expect(scabbard:IsA("BasePart")).toBe(true)
		expect(sheath.PrimaryPart).toBe(scabbard)

		-- A Weld (not a Motor6D, not a WeldConstraint): no reader of joints ever sees it.
		local weld = scabbard:FindFirstChild("ScabbardWeld")
		expect(weld).toBeTruthy()
		expect(weld.ClassName).toBe("Weld")
		expect(countClass(sheath, "Motor6D")).toBe(0)
		expect(countClass(sheath, "WeldConstraint")).toBe(0)
		expect(weld.Part0).toBe(torso)
		expect(weld.Part1).toBe(scabbard)
		local along = WeaponModels.holdOffset("OneHandedSword") + row.scabbard.clearance / 2
		local c0 = RigBuilder.frameOf(row.mount) * CFrame.new(0, along, 0)
		expect(sameFrame(weld.C0, c0)).toBe(true)
		expect(sameFrame(WeaponBuilder.scabbardC0("OneHandedSword"), c0)).toBe(true)
		expect(sameFrame(weld.C1, CFrame.identity)).toBe(true)
		-- It starts where the weld holds it: nothing flashes at the origin.
		expect(sameFrame(scabbard.CFrame, torso.CFrame * c0)).toBe(true)

		-- The blade's width and thickness plus a wall on each side, and the clearance past the tip.
		local wall, clearance = row.scabbard.wall, row.scabbard.clearance
		expect(
			near(
				scabbard.Size,
				Vector3.new(
					geometry.blade.width + 2 * wall,
					geometry.blade.length + clearance,
					geometry.blade.thickness + 2 * wall
				)
			)
		).toBe(true)

		-- Never collides, touches or answers a spatial query (D-042); weighs nothing.
		expect(scabbard.CanCollide).toBe(false)
		expect(scabbard.CanQuery).toBe(false)
		expect(scabbard.CanTouch).toBe(false)
		expect(scabbard.Massless).toBe(true)
		expect(scabbard.Anchored).toBe(false)
		expect(scabbard.Material).toBe(Enum.Material.SmoothPlastic)
		local wood = Palette.rgb(row.scabbard.color)
		expect(scabbard.Color.R).toBeCloseTo(wood[1], 1e-3)
		expect(scabbard.Color.G).toBeCloseTo(wood[2], 1e-3)
		expect(scabbard.Color.B).toBeCloseTo(wood[3], 1e-3)

		-- No attachment, and no name that FX or the hit sweep find by search.
		expect(countClass(sheath, "Attachment")).toBe(0)
		for _, name in { "Weapon", "TrailStart", "TrailEnd", "WeaponGrip" } do
			expect(sheath:FindFirstChild(name, true)).toBeNil()
		end
	end)

	it("the sword on the back mount lies inside the scabbard, its guard at the mouth", function()
		local model, torso = characterWithTorso()
		local weapon = WeaponBuilder.equip(model, SWORD)
		local scabbard = WeaponBuilder.sheathOf(model):FindFirstChild("Scabbard")
		local weld = scabbard:FindFirstChild("ScabbardWeld")
		local scabbardFrame = weld.Part0.CFrame * weld.C0 * weld.C1:Inverse()

		-- What a client does when it sheathes: the Weapon joint on the torso at the back mount.
		local motor = weapon.PrimaryPart:FindFirstChild("Weapon")
		motor.Part0 = torso
		motor.C0 = RigBuilder.frameOf(row.mount)
		local blade = Pose.solve(model, model.PrimaryPart.CFrame, {}).Weapon
		expect(blade).toBeTruthy()

		-- Axes parallel: the blade's +Y (to the tip) runs along the scabbard's +Y.
		expect(blade.UpVector:Dot(scabbardFrame.UpVector)).toBeCloseTo(1, 1e-5)
		expect(blade.RightVector:Dot(scabbardFrame.RightVector)).toBeCloseTo(1, 1e-5)
		-- The blade's center sits half the clearance short of the scabbard's center.
		local clearance = row.scabbard.clearance
		local expected = scabbardFrame.Position - scabbardFrame.UpVector * (clearance / 2)
		expect((blade.Position - expected).Magnitude).toBeLessThan(1e-4)
		-- The guard end is at the mouth and the tip is inside the far end.
		local half = scabbard.Size / 2
		local length = geometry.blade.length
		local guardEnd = scabbardFrame:PointToObjectSpace((blade * CFrame.new(0, -length / 2, 0)).Position)
		local tip = scabbardFrame:PointToObjectSpace((blade * CFrame.new(0, length / 2, 0)).Position)
		expect(guardEnd.Y).toBeCloseTo(-half.Y, 1e-4)
		expect(tip.Y).toBeLessThan(half.Y)
		expect(tip.Y).toBeCloseTo(half.Y - clearance, 1e-4)
		for _, point in { guardEnd, tip } do
			expect(math.abs(point.X)).toBeLessThan(1e-4)
			expect(math.abs(point.Z)).toBeLessThan(1e-4)
		end
		expect(geometry.blade.width / 2).toBeLessThan(half.X)
		expect(geometry.blade.thickness / 2).toBeLessThan(half.Z)
	end)

	it("reads as a back sheath: the grip high on the right behind the back, the tip low on the left", function()
		local model, torso = characterWithTorso()
		local weapon = WeaponBuilder.equip(model, SWORD)
		local motor = weapon.PrimaryPart:FindFirstChild("Weapon")
		motor.Part0 = torso
		motor.C0 = RigBuilder.frameOf(row.mount)
		local blade = Pose.solve(model, model.PrimaryPart.CFrame, {}).Weapon
		local grip = torso.CFrame:PointToObjectSpace((torso.CFrame * motor.C0).Position)
		local tip = torso.CFrame:PointToObjectSpace((blade * CFrame.new(0, geometry.blade.length / 2, 0)).Position)
		-- Parts face -Z, so +Z is behind the body.
		expect(grip.Y).toBeGreaterThan(0)
		expect(grip.X).toBeGreaterThan(0)
		expect(grip.Z).toBeGreaterThan(torso.Size.Z / 2)
		expect(tip.Y).toBeLessThan(0)
		expect(tip.X).toBeLessThan(0)
		expect(tip.Z).toBeGreaterThan(torso.Size.Z / 2)
		-- Flat against the back: the blade's length runs across the back, not away from it.
		expect(math.abs(blade.UpVector:Dot(torso.CFrame.LookVector))).toBeLessThan(1e-5)
	end)

	it("leaves the server's weapon in the hand: three parts, Part0 RightHand, one new joint", function()
		local model, _, hand = characterWithTorso()
		local before = jointNames(model)
		local weapon = WeaponBuilder.equip(model, SWORD)
		expect(countClass(weapon, "BasePart")).toBe(WeaponModels.partsPerWeapon)
		local motor = weapon.PrimaryPart:FindFirstChild("Weapon")
		expect(motor.Part0).toBe(hand)
		local expected = table.clone(before)
		table.insert(expected, "Weapon")
		table.sort(expected)
		expect(jointNames(model)).toEqual(expected)
	end)

	it("re-equip keeps one sheath, a weapon without a row takes it away, unequip removes it", function()
		local model = characterWithTorso()
		WeaponBuilder.equip(model, SWORD)
		WeaponBuilder.equip(model, SWORD)
		expect(#sheathsOf(model)).toBe(1)
		WeaponBuilder.equip(model, Weapons.byId("TrialistKatana"))
		expect(#sheathsOf(model)).toBe(0) -- a category without a row keeps its weapon in the hand
		WeaponBuilder.equip(model, SWORD)
		expect(#sheathsOf(model)).toBe(1)
		WeaponBuilder.unequip(model)
		expect(#sheathsOf(model)).toBe(0)
		expect(WeaponBuilder.sheathOf(model)).toBeNil()
	end)

	it("a stand-in without the row's part gets no sheath and no error", function()
		local model = character()
		expect(function()
			WeaponBuilder.equip(model, SWORD)
		end).never.toThrow()
		expect(#sheathsOf(model)).toBe(0)
		expect(WeaponBuilder.equipped(model)).toBeTruthy()
	end)
end)
