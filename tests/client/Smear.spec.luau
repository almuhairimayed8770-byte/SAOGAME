--!strict
-- Smear in Lune: the weapon part stretched along the clip's axis and put back, the size it had
-- before the stretch kept per part (Smear.restSize, which the impact-frame figure draws), and a
-- reset that puts it back and forgets it.
local Smear = Harness.load("src/client/fx/Smear")
local fx = Harness.load("src/shared/data/fx")

local REST = Vector3.new(0.3, 4, 0.15)

-- A rig with a torso and a Weapon part (the part the smear stretches) under a holder model.
local function rig(): (Model, BasePart, BasePart)
	local model = Instance.new("Model")
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Parent = model
	local holder = Instance.new("Model")
	holder.Name = "Sword"
	holder.Parent = model
	local weapon = Instance.new("Part")
	weapon.Name = "Weapon"
	weapon.Size = REST
	weapon.Parent = holder
	return model, weapon, torso
end

local function near(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude < 1e-4
end

describe("Smear", function()
	it("stretches the weapon along the clip's axis for the snap and puts it back", function()
		local model, weapon = rig()
		Smear.apply(model, true, "Y")
		expect(Smear.isActive(model)).toBe(true)
		expect(near(weapon.Size, Vector3.new(REST.X, REST.Y * fx.smear.scale, REST.Z))).toBe(true)
		Smear.apply(model, false)
		expect(Smear.isActive(model)).toBe(false)
		expect(near(weapon.Size, REST)).toBe(true)
		-- No axis (or a bad one) uses the data's default.
		Smear.apply(model, true, "W")
		local expected = Vector3.new(
			REST.X * (if fx.smear.defaultAxis == "X" then fx.smear.scale else 1),
			REST.Y * (if fx.smear.defaultAxis == "Y" then fx.smear.scale else 1),
			REST.Z * (if fx.smear.defaultAxis == "Z" then fx.smear.scale else 1)
		)
		expect(near(weapon.Size, expected)).toBe(true)
		Smear.reset(model)
		expect(near(weapon.Size, REST)).toBe(true)
	end)

	it("restSize is the size before the stretch while it shows, and nil for a part it never touched", function()
		local model, weapon, torso = rig()
		expect(Smear.restSize(weapon)).toBeNil()
		Smear.apply(model, true, "Y")
		expect(weapon.Size.Y > REST.Y).toBe(true)
		expect(near(Smear.restSize(weapon) :: Vector3, REST)).toBe(true)
		-- A second SmearOn on a stretched sword (two snaps in a row) does not stretch the stretch.
		Smear.apply(model, true, "Z")
		expect(near(Smear.restSize(weapon) :: Vector3, REST)).toBe(true)
		expect(near(weapon.Size, Vector3.new(REST.X, REST.Y, REST.Z * fx.smear.scale))).toBe(true)
		-- The torso is not the smear's: the figure draws it at its own size.
		expect(Smear.restSize(torso)).toBeNil()
		Smear.apply(model, false)
		expect(near(Smear.restSize(weapon) :: Vector3, REST)).toBe(true)
		-- Reset forgets the part: nothing is stored for it any more.
		Smear.reset(model)
		expect(Smear.restSize(weapon)).toBeNil()
	end)
end)
