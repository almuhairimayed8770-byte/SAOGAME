--!strict
--[[
	The soles stand on the floor the Humanoid holds the root over (D-506), whatever the avatar.

	The engine holds the root's bottom the Humanoid's own HipHeight over the floor; the legs hang
	where the avatar's own parts and joints put them. On 7d112ef Locomotion measured the ground
	against the rig table's hipHeight (rigs.luau PlayerR15 2.0) instead: on the owner-sized body
	(HitMatrix.standing: the owner's torso, arm, hand and foot sizes) its flat field read 0.54 high,
	and the foot IK lifted both standing feet 0.30 to 0.66 off it. A Humanoid whose HipHeight is
	short of the legs (or past them) sank (or floated) every sole by the difference, walking too,
	where the IK has faded. Now the IK measures the ground against the floor the Humanoid stands
	on, and the body is raised or lowered over its root by the gap between the legs' bind-pose
	hang and that floor (within footIK.maxAdjust).

	Real Choreo and Locomotion (foot IK on, a raycast onto the field) on the hit matrix's player,
	with its Humanoid's HipHeight off the legs' hang by each of dev.luau
	groundClearance.standHeight.hipErrors (the root stands that much lower or higher), standing
	and walking at each of `speeds`, drawn. After `settle` seconds, every frame for `seconds`
	more: standing, the lowest sole corner stays within locomotion.stride.contact of the field
	(STUDIO_TASKS 368(b): no foot sinks); walking, the lowest sole each frame (the planted foot)
	does the same (368(a): a planted corner within 0.02 of the floor).

	A landing (367(a)) on the same body, standing, sheathed and drawn, at each of
	standHeight.landing.stepHz: no leg part turns more than review.audit.popDegrees in a 60 Hz
	frame. On 7d112ef the IK's bend came in at full weight on the touch-down frame, a 0.54 stud
	lift no floor asked for: the shin turned 34 to 41 degrees in that frame at 60 Hz.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

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
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")

local Stand = Dev.groundClearance.standHeight
local CONTACT = ChoreoData.locomotion.stride.contact

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

local FEET = { "LeftFoot", "RightFoot" }

-- The lowest sole corner of both feet over the field's top, every frame after the settle.
local function run(hipError: number, speed: number): { number }
	local avatar, field = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", true)
	local top = ClipAudit.topOf(field.CFrame, field.Size)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid ~= nil, "the hit matrix's player has a Humanoid")
	local primary = model.PrimaryPart
	-- The legs reach the field from avatar.rootHeight; the Humanoid holds the root hipError lower.
	humanoid.HipHeight = avatar.rootHeight - primary.Size.Y / 2 - hipError
	local base = avatar.base * CFrame.new(0, -hipError, 0)
	primary.CFrame = base
	primary.Position = base.Position
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, {
		raycast = function(origin: Vector3, direction: Vector3): Vector3?
			if origin.Y >= top and origin.Y + direction.Y <= top then
				return Vector3.new(origin.X, top, origin.Z)
			end
			return nil
		end,
	})
	local dt = 1 / Stand.stepHz
	local lows: { number } = {}
	local travelled = 0
	local chain = Pose.chain(model)
	for frame = 1, math.floor((Stand.settle + Stand.seconds) * Stand.stepHz + 0.5) do
		travelled += speed * dt
		local rootFrame = base * CFrame.new(0, 0, -travelled)
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = if speed > 0 then Vector3.new(0, 0, -1) else Vector3.zero,
			speed = speed,
			sprinting = false,
			grounded = true,
			drawn = true,
			turning = 0,
			verticalVelocity = 0,
			velocity = Vector3.new(0, 0, -speed),
		})
		animator:step(dt)
		if frame * dt > Stand.settle then
			local solved = Pose.solve(model, rootFrame, animator.mixer:lastOffsets(), chain)
			local low = math.huge
			for _, name in FEET do
				local frameOf = solved[name]
				local size = (model:FindFirstChild(name) :: any).Size
				for _, sx in { -0.5, 0.5 } do
					for _, sz in { -0.5, 0.5 } do
						local corner = frameOf * CFrame.new(sx * size.X, -0.5 * size.Y, sz * size.Z)
						low = math.min(low, corner.Position.Y - top)
					end
				end
			end
			table.insert(lows, low)
		end
	end
	locomotion:destroy()
	Choreo.release(model)
	return lows
end

local function angleBetween(a: CFrame, b: CFrame): number
	local _, radians = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	return math.deg(math.abs(radians))
end

-- A landing (Studio item 367(a): Land popped 31 to 48 degrees in a frame): standing, the body
-- falls for landing.fallSeconds at landing.fallSpeed and lands; the most any leg part turns in
-- one frame from the touch-down on, scaled to a 60 Hz frame.
local LEGS = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local function land(
	drawn: boolean,
	hz: number,
	moving: { speed: number, fallSeconds: number, grounded: boolean }?
): (number, string)
	local avatar, field = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", drawn)
	local top = ClipAudit.topOf(field.CFrame, field.Size)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: any
	local primary = model.PrimaryPart
	humanoid.HipHeight = avatar.rootHeight - primary.Size.Y / 2
	primary.CFrame = avatar.base
	primary.Position = avatar.base.Position
	local animator: any = Choreo.get(model)
	local locomotion: any = Locomotion.new(animator, model, {
		raycast = function(origin: Vector3, direction: Vector3): Vector3?
			if origin.Y >= top and origin.Y + direction.Y <= top then
				return Vector3.new(origin.X, top, origin.Z)
			end
			return nil
		end,
	})
	local landing = Stand.landing
	local dt = 1 / hz
	local chain = Pose.chain(model)
	local last: any = nil
	local worst, worstPart = 0, ""
	local landAt = Stand.settle + (if moving ~= nil then moving.fallSeconds else landing.fallSeconds)
	local speed = if moving ~= nil then moving.speed else 0
	local window = if moving ~= nil then landing.moveWindow else landing.after
	for frame = 1, math.floor((landAt + window) * hz + 0.5) do
		local t = frame * dt
		-- `grounded`: the same stride with no fall, for the stride's own most.
		local airborne = t > Stand.settle and t < landAt and not (moving ~= nil and moving.grounded)
		-- Locomotion reads the fall's height on the frame grounded turns true.
		local touchDown = not airborne and t >= landAt and t < landAt + dt
		locomotion:update(dt, {
			moveDir = if speed > 0 then Vector3.new(0, 0, -1) else Vector3.zero,
			speed = speed,
			sprinting = speed > ChoreoData.locomotion.runSpeed,
			grounded = not airborne,
			drawn = drawn,
			turning = 0,
			verticalVelocity = if airborne then -landing.fallSpeed else 0,
			fallHeight = if airborne or touchDown then landing.fallHeight else nil,
			velocity = Vector3.new(0, if airborne then -landing.fallSpeed else 0, -speed),
		})
		animator:step(dt)
		local solved = Pose.solve(model, avatar.base, animator.mixer:lastOffsets(), chain)
		if last ~= nil and t >= landAt - 1e-9 then
			for _, name in LEGS do
				local step = angleBetween(last[name], solved[name]) * hz / 60
				if step > worst then
					worst, worstPart = step, name
				end
			end
		end
		last = solved
	end
	locomotion:destroy()
	Choreo.release(model)
	return worst, worstPart
end

describe("StandHeight", function()
	it("a landing brings the legs in without a pop: the foot IK finds the floor where the legs already are", function()
		local report = {}
		for _, drawn in { false, true } do
			for _, hz in Stand.landing.stepHz do
				local worst, part = land(drawn, hz)
				table.insert(
					report,
					("%s %d Hz: %.1f (%s)"):format(if drawn then "drawn" else "sheathed", hz, worst, part)
				)
				if worst > Dev.review.audit.popDegrees then
					error(
						("a %s landing at %d Hz turns the %s %.1f degrees in a 60 Hz frame (review.audit.popDegrees %d)"):format(
							if drawn then "drawn" else "sheathed",
							hz,
							part,
							worst,
							Dev.review.audit.popDegrees
						)
					)
				end
			end
		end
		print("StandHeight landing: " .. table.concat(report, "; "))
	end)

	it("a landing on the move hands the legs to the stride without a pop (D-521)", function()
		-- Studio 417(c) on 0582a04: landings turned a leg part 25.3 and 27.2 degrees a frame. On the
		-- move Land has no weight, and the Fall let go of the legs over oneShotBlendIn (0.05 s): a
		-- run's touch-down frame turned a foot 24 to 35 degrees against the stride's own 23.
		local landing = Stand.landing
		local report = {}
		local problems = {}
		for _, drawn in { false, true } do
			for _, speed in landing.moveSpeeds do
				for _, fallSeconds in landing.moveFallSeconds do
					local worst, part = land(drawn, 60, { speed = speed, fallSeconds = fallSeconds, grounded = false })
					local own = land(drawn, 60, { speed = speed, fallSeconds = fallSeconds, grounded = true })
					local bar = math.max(Dev.review.audit.popDegrees, own) + landing.moveSlack
					local label = ("%s at %d after a %.2f s fall"):format(
						if drawn then "drawn" else "sheathed",
						speed,
						fallSeconds
					)
					table.insert(report, ("%s: %.1f (%s; the stride's own %.1f)"):format(label, worst, part, own))
					if worst > bar then
						table.insert(
							problems,
							("%s: the %s turns %.1f degrees in a 60 Hz frame after the touch-down (the stride's own most %.1f, bar %.1f)"):format(
								label,
								part,
								worst,
								own,
								bar
							)
						)
					end
				end
			end
		end
		print("StandHeight landing on the move:\n  " .. table.concat(report, "\n  "))
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("the planted soles stand on the floor the Humanoid holds the root over, drawn, standing and walking", function()
		local cases = 0
		local report = {}
		for _, hipError in Stand.hipErrors do
			for _, speed in Stand.speeds do
				local lows = run(hipError, speed)
				cases += 1
				local worst = 0
				for _, low in lows do
					if math.abs(low) > math.abs(worst) then
						worst = low
					end
				end
				table.insert(
					report,
					("HipHeight %+.2f off the legs, speed %d: lowest sole %+.3f at worst"):format(
						if hipError == 0 then 0 else -hipError,
						speed,
						worst
					)
				)
				if math.abs(worst) > CONTACT then
					error(
						("HipHeight %+.2f off the legs, speed %d: the planted sole stands %+.3f from the field (locomotion.stride.contact %.2f): it %s"):format(
							-hipError,
							speed,
							worst,
							CONTACT,
							if worst < 0 then "sinks" else "floats"
						)
					)
				end
			end
		end
		print("StandHeight:\n  " .. table.concat(report, "\n  "))
		expect(cases).toBe(#Stand.hipErrors * #Stand.speeds)
	end)
end)
