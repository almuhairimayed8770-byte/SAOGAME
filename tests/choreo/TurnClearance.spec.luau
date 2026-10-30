--!strict
--[[
	Drawn turns keep the scabbard off the body (the off-body rule, dev.luau groundClearance.offBody,
	through Locomotion's blend and its lean, which GroundClearance poses clip by clip). The real
	Locomotion and Choreo animator run on a Lune rig whose root moves at a set speed and yaws toward
	a stick swung straight back (offBody.turns): the drawn blend passes through the back and side
	walks, and the lean into the turn rolls the waist. Every frame at groundClearance.sampleHz the
	mixer's offsets pose the hit matrix's player (HitMatrix.standing), and the scabbard keeps
	offBody.margin from every body part but the one the sheath hangs on. Breathe is stopped: the
	margins already hold its reach, as in GroundClearance.

	A drawn left reversal shows the drawn left walk at full weight with the lean near its cap; the
	scabbard went up to 0.19 studs into the left foot until locomotion.lean.upright held the torso
	up. The sheathed set is not posed here: its walk-to-run blend brings the scabbard within the arms
	margin of the left forearm going straight, a matter for the clips.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame

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
	-- Choreo's rig step (bound before every reader of a pose, D-211): the spec steps the rigs itself.
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
local Dev = Harness.load("src/shared/data/dev")
local Rigs = Harness.load("src/shared/data/rigs")
local Pose = Harness.load("src/shared/choreo/Pose")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")
local Playground = Harness.load("src/shared/data/playground")

local Clearance = Dev.groundClearance
local OffBody = Clearance.offBody
local Turns = OffBody.turns
local category = Weapons.byId(Playground.loadout.weapon).category

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

-- The margin a body part keeps: its group's in offBody.margin (as GroundClearance groups them).
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

-- A box as 15 numbers: its center, its three axes and half its size (GroundClearance's layout).
type Box = { number }

local function boxOf(frame: any, size: any): Box
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = frame:GetComponents()
	return { x, y, z, r00, r10, r20, r01, r11, r21, r02, r12, r22, size.X / 2, size.Y / 2, size.Z / 2 }
end

local rotation = table.create(9, 0)
local absolute = table.create(9, 0)
local offsetIn = table.create(3, 0)

-- How far apart two boxes are along the axis that separates them best (the 15-axis separating
-- test): positive is a gap, negative how deep they overlap along the shallowest axis.
local function boxSeparation(a: Box, b: Box): number
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
	local hb1, hb2, hb3 = b[13], b[14], b[15]
	local ha1, ha2, ha3 = a[13], a[14], a[15]
	local best = -math.huge
	for i = 1, 3 do
		local row = 3 * (i - 1)
		local reach = hb1 * absolute[row + 1] + hb2 * absolute[row + 2] + hb3 * absolute[row + 3]
		best = math.max(best, math.abs(offsetIn[i]) - a[12 + i] - reach)
	end
	for j = 1, 3 do
		local distance =
			math.abs(offsetIn[1] * rotation[j] + offsetIn[2] * rotation[3 + j] + offsetIn[3] * rotation[6 + j])
		best =
			math.max(best, distance - b[12 + j] - (ha1 * absolute[j] + ha2 * absolute[3 + j] + ha3 * absolute[6 + j]))
	end
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
				best = math.max(best, (distance - reachA - reachB) / length)
			end
		end
	end
	return best
end

-- A box that rides the sheath, and where a solved pose puts it.
type Piece = { name: string, size: any, frameOf: (solved: any) -> any }

type Body = {
	avatar: any,
	chain: any, -- the rig's joints, the sword in the hand
	scabbard: Piece,
	parts: { any }, -- the body parts the scabbard keeps off
	margins: { number },
}

local cachedBody: Body? = nil
local function body(): Body
	if cachedBody == nil then
		local avatar = HitMatrix.standing(Harness)
		local row = WeaponModels.sheath(category)
		assert(row ~= nil, "weaponModels.luau has no sheath for " .. category)
		local function partNamed(name: string): any
			for _, item in avatar.model:GetDescendants() do
				if item:IsA("BasePart") and item.Name == name then
					return item
				end
			end
			error("the matrix's avatar has no " .. name)
		end
		local scabbardPart = partNamed(WeaponModels.scabbardPart)
		local weld = scabbardPart:FindFirstChild(WeaponModels.scabbardWeld)
		local scabbard: Piece = {
			name = scabbardPart.Name,
			size = scabbardPart.Size,
			frameOf = function(solved: any): any
				return solved[row.part] * weld.C0
			end,
		}
		local parts = {}
		for _, part in avatar.model:GetChildren() do
			if part:IsA("BasePart") and part ~= avatar.model.PrimaryPart and part.Name ~= row.part then
				table.insert(parts, part)
			end
		end
		table.sort(parts, function(a: any, b: any): boolean
			return a.Name < b.Name
		end)
		local margins = {}
		for index, part in parts do
			margins[index] = marginOf(part.Name)
		end
		cachedBody = {
			avatar = avatar,
			chain = Pose.chain(avatar.model),
			scabbard = scabbard,
			parts = parts,
			margins = margins,
		}
	end
	return cachedBody :: Body
end

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

-- The closest the scabbard came to any body part, short of that part's margin.
type Worst = { slack: number, gap: number, part: string, margin: number, at: number }

-- One drawn reversal: straight ahead for `settle`, then the stick points back and the root yaws
-- toward it (to the left when `side` is 1) at `yawRate` until it faces it, then on for `after`.
local function reversal(side: number, speed: number, yawRate: number): Worst
	local shape = body()
	local model = buildRig()
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, { footIK = false })
	-- Breathe adds to every pose on its own clock; the margins already hold its reach.
	for _, handle in animator.mixer:handles() do
		if handle.clip.id:find("Breathe", 1, true) ~= nil then
			animator:stop(handle, 0)
		end
	end
	local dt = 1 / Clearance.sampleHz
	local turnSeconds = 180 / yawRate
	local frames = math.floor((Turns.settle + turnSeconds + Turns.after) * Clearance.sampleHz + 0.5)
	local worst: Worst = { slack = math.huge, gap = 0, part = "", margin = 0, at = 0 }
	local yaw = 0
	for frame = 1, frames do
		local t = frame * dt
		local turning = t > Turns.settle
		if turning then
			yaw = math.min(180, yaw + yawRate * dt)
		end
		model.PrimaryPart.CFrame = CFrame.Angles(0, math.rad(yaw * side), 0)
		locomotion:update(dt, {
			moveDir = if turning then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1),
			speed = speed,
			sprinting = false,
			grounded = true,
			drawn = true,
			turning = 0,
			verticalVelocity = 0,
		})
		animator:step(dt)
		if turning then
			-- The scabbard and the parts all ride the body, so the gaps do not depend on the root.
			local solved = Pose.solve(shape.avatar.model, shape.avatar.base, animator.mixer:lastOffsets(), shape.chain)
			local scabbardBox = boxOf(shape.scabbard.frameOf(solved), shape.scabbard.size)
			for index, part in shape.parts do
				local margin = shape.margins[index]
				local gap = boxSeparation(scabbardBox, boxOf(solved[part.Name], part.Size))
				if gap - margin < worst.slack then
					worst =
						{ slack = gap - margin, gap = gap, part = part.Name, margin = margin, at = t - Turns.settle }
				end
			end
		end
	end
	locomotion:destroy()
	Choreo.release(model)
	return worst
end

describe("drawn turns keep the scabbard off the body", function()
	it("drawn reversals to either side at every speed and yaw rate in offBody.turns", function()
		local problems: { string } = {}
		local closest = math.huge
		local cases = 0
		for _, side in { 1, -1 } do
			for _, speed in Turns.speeds do
				for _, yawRate in Turns.yawRates do
					local worst = reversal(side, speed, yawRate)
					cases += 1
					closest = math.min(closest, worst.gap)
					if worst.slack < 0 then
						table.insert(
							problems,
							("%s turn at %g studs/s, %g deg/s: the scabbard %.3f studs from the %s at +%.3f s (keep %.3f)"):format(
								if side > 0 then "left" else "right",
								speed,
								yawRate,
								worst.gap,
								worst.part,
								worst.at,
								worst.margin
							)
						)
					end
				end
			end
		end
		expect(cases).toBe(2 * #Turns.speeds * #Turns.yawRates)
		print(("  %d drawn turns, the scabbard at least %.3f studs from the body"):format(cases, closest))
		if #problems > 0 then
			print(("  %d come too near:\n    %s"):format(#problems, table.concat(problems, "\n    ")))
		end
		expect(#problems).toBe(0)
	end)
end)
