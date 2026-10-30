--!strict
--[[
	A lock-on's draw on a turn in place (323(b), shot 10 on the owner's PC: the skid at 4.83 s,
	then TurnLeft and the draw at 5.05 s, and a second Draw clip at 5.85 s). The lock-on asks for
	the sword (the predicted draw) on the frame the lock turns the standing body; the Draw starts
	that frame, the turn in place comes once the body has turned turnInPlaceDegrees (about 4
	frames later at the lock's 720 degrees a second), covers the sword arm before the Draw's grab,
	and the Draw is cut and plays again once every turn clip is over. One Draw plays, never cut
	before its grab.

	Runs the real Choreo animator, Locomotion and SheathState on a sword rig the server's
	WeaponBuilder hung (tests/choreo/Locomotion.spec.luau's harness), the root turned on the lock's
	rate the way the character controller turns it.
]]
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
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")

local FRAME = 1 / 60
local Config = ChoreoData.locomotion
local Sheath = ChoreoData.sheath
local DRAW = Config.clipPrefix .. Sheath.clips.draw
local SWORD = Weapons.byId("TrialistSword")

local function eventTime(clipId: string, kind: string): number
	for _, event in ClipLibrary.get(clipId).events do
		if event.kind == kind then
			return event.time
		end
	end
	error(clipId .. " has no " .. kind)
end

local function trackerOf(state)
	return function()
		return state
	end
end

local world = Instance.new("Folder")
world.Name = "World"

-- A player rig whose sword the server's WeaponBuilder hung on the right hand (with its scabbard),
-- in a world folder. `armed` false leaves the sword off.
local function buildSwordRig(armed: boolean?)
	local model = Instance.new("Model")
	model.Name = "Player"
	model:SetAttribute("Rig", "PlayerR15")
	local parts = {}
	local function part(name)
		local existing = parts[name]
		if existing then
			return existing
		end
		local created = Instance.new("Part")
		created.Name = name
		created.Size = Vector3.new(1, 1, 1)
		created.CFrame = CFrame.new(0, 3, 0)
		created.Position = Vector3.new(0, 3, 0)
		created.Parent = model
		parts[name] = created
		return created
	end
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name == WeaponModels.motorName then
			continue
		end
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Part0 = part(joint.part0)
		motor.Part1 = part(joint.part1)
		motor.C0 = RigBuilder.frameOf(joint.c0)
		motor.Parent = motor.Part1
	end
	model.PrimaryPart = parts.HumanoidRootPart
	if armed ~= false then
		WeaponBuilder.equip(model, SWORD)
	end
	model.Parent = world
	return model
end

local function swordMotor(model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name == WeaponModels.motorName then
			return descendant
		end
	end
	return nil
end

local function steps(animator, seconds: number)
	for _ = 1, math.ceil(seconds / FRAME - 1e-9) do
		animator:step(FRAME)
	end
end

local function still()
	return { moveDir = Vector3.zero, speed = 0, sprinting = false, grounded = true, turning = 0 }
end

local AIM_TURN_RATE = Harness.load("src/shared/data/combat").aim.lockTurnRate

-- A standing, sheathed body the lock turns `degrees` to the left at the lock's turn rate, the
-- sword wanted drawn from the lock's frame (the lock-on's predicted draw). Returns each Draw
-- handle in the order it started, with the clip time it stopped at (nil while it never stopped).
local function lockTurnDraw(degrees: number, seconds: number): ({ { start: number, stoppedAt: number? } }, string)
	local model = buildSwordRig()
	model:SetAttribute("Drawn", false)
	local animator = Choreo.get(model)
	local state = still()
	state.drawn = false
	local driver = Locomotion.attach(animator, model, { footIK = false, tracker = trackerOf(state) })
	steps(animator, 0.5)
	local root = model.PrimaryPart :: any
	local draws: { { start: number, stoppedAt: number?, handle: any } } = {}
	local left = degrees
	local t = 0
	state.drawn = true
	while t < seconds do
		t += FRAME
		local step = math.min(left, AIM_TURN_RATE * FRAME)
		left -= step
		root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(step), 0)
		animator:step(FRAME)
		for _, handle in animator.mixer:handles() do
			if handle.clipId == DRAW then
				local known = false
				for _, entry in draws do
					if entry.handle == handle then
						known = true
						if handle.stopping and entry.stoppedAt == nil then
							entry.stoppedAt = handle.time
						end
					end
				end
				if not known then
					table.insert(draws, { start = t, stoppedAt = nil, handle = handle })
				end
			end
		end
	end
	local motor = swordMotor(model)
	local place = if motor.Part0 == model:FindFirstChild("RightHand") then "Hand" else "Back"
	driver:destroy()
	Choreo.release(model)
	local out = {}
	for _, entry in draws do
		table.insert(out, { start = entry.start, stoppedAt = entry.stoppedAt })
	end
	return out, place
end

describe("Locomotion: a lock-on's draw on a turn in place (323(b))", function()
	it("plays one Draw that is never cut before its grab, however far the lock turns the body", function()
		local grab = eventTime(DRAW, "WeaponDraw")
		local results = {}
		for _, degrees in { 60, 135 } do
			local draws, place = lockTurnDraw(degrees, 2)
			table.insert(results, { draws = draws, place = place })
			local line = {}
			for _, entry in draws do
				table.insert(
					line,
					("start %.2f%s"):format(
						entry.start,
						if entry.stoppedAt ~= nil then (" stop at clip %.2f"):format(entry.stoppedAt) else ""
					)
				)
			end
			print(
				("323(b) %d deg: %d Draw clip(s): %s; sword %s"):format(
					degrees,
					#draws,
					table.concat(line, ", "),
					place
				)
			)
		end
		for _, result in results do
			local draws, place = result.draws, result.place
			expect(#draws).toBe(1)
			for _, entry in draws do
				expect(entry.stoppedAt == nil or (entry.stoppedAt :: number) >= grab).toBe(true)
			end
			expect(place).toBe("Hand")
		end
	end)
end)
