--!strict
--[[
	A dodge from the run while a Draw or Sheathe plays (D-580, Studio item 478(a)). The owner's
	PC on 209875b dodged from the run at 16 with the sword drawn through DevAim's draw, whose Draw
	clip was still on: the right arm turned 20.1 to 31.63 degrees on 1 to 4 rows after the press
	(the press row itself 25.73 on the forearm). On the base the dodge took the arm over its own
	0.18 s blend (D-528) while the sheath clip went on swinging under it, or, a Draw that had not
	taken the sword yet or a Sheathe that had not put it away, stopped over sheath.stopBlend with
	its clock running: the right forearm up to 88 degrees a row (the Draw) and 264 (the Sheathe).

	Now a dodge that starts while a Draw or Sheathe is under way leaves that clip the arm and the
	sword's joint, and the clip stands (its clock and any fade in) until the dodge is gone; then it
	plays on and moves the sword on its own event.

	The game's own path, as DodgeTakeOver.spec.luau runs it: real Choreo and Locomotion (foot IK on
	a flat field), SheathState and WeaponMount, on the hit matrix's player. Each case runs the stick
	forward at dev.luau groundClearance.dodgeSheath.speed, flips the Drawn target so the clip has
	played each of `clipTimes` seconds at the press (a Sheathe starts sheath.sheatheDelay after the
	target goes false), plays DodgeForward as CharacterController plays it (handOver, nothing to
	cut; the unlocked run's dodge) with the root moved at the dodge's speed for combat.luau
	dodgeDuration, and runs `after` seconds more. Each part's turn per review.fps row, read in the
	root part's frame, stays within review.audit.popDegrees while the dodge holds the body (from
	the press until it lets go), and the sword ends where the target wants it.
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

local clock = 0
local Choreo = Harness.load("src/client/choreo/Choreo")
Choreo.configure({
	now = function()
		return clock
	end,
	cameraPosition = function()
		return Vector3.zero
	end,
})
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local WeaponModels = Harness.load("src/shared/data/weaponModels")

local Cases = Dev.groundClearance.dodgeSheath
local Audit = Dev.review.audit
local HZ = Dev.review.fps
local PREFIX = ChoreoData.locomotion.clipPrefix
local DODGE = PREFIX .. "DodgeForward"
local DODGE_SPEED = Combat.dodgeDistance / Combat.dodgeDuration

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

local PARTS = {
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
	"Head",
	"UpperTorso",
	"LowerTorso",
}

local function angleBetween(a: CFrame, b: CFrame): number
	local _, radians = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	return math.deg(math.abs(radians))
end

type Result = {
	degrees: number, -- the largest part turn a row while the dodge holds the body
	part: string,
	row: number, -- rows after the press
	place: string?, -- the Weapon motor's Part0 at the end
}

-- `drawing`: a Draw plays (the target flips to drawn), else a Sheathe. `clipTime`: how long the
-- clip has played at the press. `lead`: seconds past `settle` the press comes.
local function run(drawing: boolean, clipTime: number, lead: number): Result
	local avatar, field = HitMatrix.standing(Harness)
	local model = avatar.model
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", not drawing)
	local motor: any = nil
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and item.Name == WeaponModels.motorName then
			motor = item
		end
	end
	assert(motor ~= nil, "the matrix's sword has no Weapon motor")
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
	local dt = 1 / HZ
	local chain = Pose.chain(model)
	local pressFrame = math.floor((Cases.settle + lead) * HZ + 0.5)
	-- The target flips this long before the press: a Sheathe starts sheatheDelay after it.
	local flipBefore = clipTime + if drawing then 0 else ChoreoData.sheath.sheatheDelay
	local offset = Vector3.zero
	local last: any = nil
	local handle: any = nil
	local result: Result = { degrees = 0, part = "", row = 0, place = nil }
	for frame = 1, pressFrame + math.floor(Cases.after * HZ + 0.5) do
		clock += dt
		local since = (frame - pressFrame) * dt
		if handle == nil and frame >= pressFrame then
			handle = animator:play(DODGE, { handOver = true })
		end
		local dodging = handle ~= nil and since < Combat.dodgeDuration - 1e-9
		local flipped = since >= -flipBefore - 1e-9
		local velocity = if dodging then Vector3.new(0, 0, -DODGE_SPEED) else Vector3.new(0, 0, -Cases.speed)
		offset += velocity * dt
		local rootFrame = avatar.base * CFrame.new(offset)
		primary.CFrame = rootFrame
		primary.Position = rootFrame.Position
		locomotion:update(dt, {
			moveDir = Vector3.new(0, 0, -1),
			speed = velocity.Magnitude,
			sprinting = false,
			grounded = true,
			drawn = if flipped then drawing else not drawing,
			turning = 0,
			verticalVelocity = 0,
			velocity = velocity,
		})
		animator:step(dt)
		local solved = Pose.solve(model, avatar.base, animator.mixer:lastOffsets(), chain)
		-- The dodge holds the body from the press until it lets go (its blend out under the gait).
		if handle ~= nil and last ~= nil and not handle.stopping and not handle.done then
			for _, part in PARTS do
				local degrees = angleBetween(last[part], solved[part])
				if degrees > result.degrees then
					result.degrees, result.part, result.row = degrees, part, frame - pressFrame + 1
				end
			end
		end
		last = solved
	end
	result.place = if motor.Part0 ~= nil then motor.Part0.Name else nil
	locomotion:destroy()
	Choreo.release(model)
	return result
end

local function check(drawing: boolean)
	local name = if drawing then "Draw" else "Sheathe"
	local problems: { string } = {}
	local worst, worstCase = 0, ""
	local cases = 0
	for _, lead in Cases.leads do
		for _, clipTime in Cases.clipTimes do
			local result = run(drawing, clipTime, lead)
			cases += 1
			local case = ("%s %.2f s in, the press %.2f s into the run"):format(name, clipTime, Cases.settle + lead)
			if result.degrees > worst then
				worst, worstCase = result.degrees, ("%s: the %s on row +%d"):format(case, result.part, result.row)
			end
			if result.degrees > Audit.popDegrees then
				table.insert(
					problems,
					("%s: the %s turns %.1f degrees on row +%d (popDegrees %d)"):format(
						case,
						result.part,
						result.degrees,
						result.row,
						Audit.popDegrees
					)
				)
			end
			local inHand = result.place == "RightHand"
			if inHand ~= drawing then
				table.insert(
					problems,
					("%s: the sword ends on %s, not %s"):format(
						case,
						tostring(result.place),
						if drawing then "the hand" else "the back"
					)
				)
			end
		end
	end
	expect(cases).toBe(#Cases.leads * #Cases.clipTimes)
	print(("  a dodge over the %s: %d cases, at most %.1f degrees a row (%s)"):format(name, cases, worst, worstCase))
	if #problems > 0 then
		error(("%d %s case(s) fail:\n%s"):format(#problems, name, table.concat(problems, "\n")))
	end
end

describe("A dodge from the run over a Draw or Sheathe (D-580, 478(a))", function()
	it(
		"Draw: no part turns over popDegrees a row while the dodge holds the body; the sword ends in the hand",
		function()
			check(true)
		end
	)
	it(
		"Sheathe: no part turns over popDegrees a row while the dodge holds the body; the sword ends on the back",
		function()
			check(false)
		end
	)
end)
