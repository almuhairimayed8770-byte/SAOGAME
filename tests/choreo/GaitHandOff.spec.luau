--!strict
--[[
	An attack that cuts a moving gait takes the body over its hand-off (D-404, GaitHandOff and
	choreo.luau locomotion.handOff): the legs, the root and the arms come into the attack's first
	pose over their own blends, longer than the clip's own blendIn, so no stride or arm swing is
	crossed into the attack in a frame. The server counts the swing from the clip's pose alone
	(HitSweep) and the hit is drawn on the strike's key (ContactPredictor.strikeKey, the
	contact-to-key rule): on that frame the blade the eye sees must be the clip's, so no joint's
	hand-off blend runs past the first strike key. tools/validators/choreo.luau holds the data to it.

	The basics' window opens at 0.1 s and their key is at 0.15 s: the sword arm's 0.15 s hand-off
	(0.1 x 1.5) ends on the key, the tip 0 studs from the clip's own on it (0.06 to 0.88 studs off
	on the snap's first frames, where no hit is drawn); a factor of 2 would leave it 0.05 s late.

	- Every hand-off blend of every player attack ends by its first strike key.
	- The hand-off still lengthens the legs' and arms' blends past the clip's own for an attack
	  whose window opens later (an Art), and gives no joint a blend shorter than a frame.
	- Locomotion gives an attack started over a running gait those blends (Mixer.handOff).
]]

local ChoreoData = Harness.load("src/shared/data/choreo")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local GaitHandOff = Harness.load("src/client/choreo/GaitHandOff")

-- Locomotion steps through the real Choreo animator; the spec steps the rigs itself.
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
local Rigs = Harness.load("src/shared/data/rigs")

-- A bare rig: a part per body part and a Motor6D per rigs.luau joint.
local function buildRig(rigId: string): Model
	local model = Instance.new("Model")
	model.Name = rigId
	model:SetAttribute("Rig", rigId)
	local parts: { [string]: Part } = {}
	local function part(name: string): Part
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
	for _, joint in Rigs[rigId].joints do
		part(joint.part0)
		local child = part(joint.part1)
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Parent = child
	end
	model.PrimaryPart = parts.HumanoidRootPart
	return model
end

local P = "player/OneHandedSword/"
local ATTACKS = { "Basic1", "Basic2", "Basic3", "Horizontal", "Vertical", "SharpNail", "RisingArc" }

local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")

-- The first damage window's strike key: where its hit is drawn.
local function firstKey(clip: any): number
	local open, close = nil, nil
	for _, event in clip.events or {} do
		if event.kind == "HitWindowOpen" and open == nil then
			open = event.time
		elseif event.kind == "HitWindowClose" and close == nil then
			close = event.time
		end
	end
	expect(open).never.toBeNil()
	expect(close).never.toBeNil()
	return ContactPredictor.strikeKey(clip, { open = open :: number, close = close :: number })
end

describe("GaitHandOff: an attack out of a moving gait", function()
	it("ends every joint's hand-off by the first strike key, where the hit is drawn", function()
		local late: { string } = {}
		for _, name in ATTACKS do
			local clip = ClipLibrary.get(P .. name)
			expect(clip).never.toBeNil()
			expect(GaitHandOff.applies(clip)).toBe(true)
			local key = firstKey(clip)
			for joint, seconds in GaitHandOff.blends(clip) do
				if seconds > key + 1e-9 then
					table.insert(late, ("%s %s %.3f s past its key at %.3f s"):format(name, joint, seconds, key))
				end
			end
		end
		table.sort(late)
		expect(late).toEqual({})
	end)

	it("still lengthens the legs and arms past an Art's own blend in", function()
		local clip = ClipLibrary.get(P .. "Horizontal")
		local blends = GaitHandOff.blends(clip)
		local own = clip.blendIn or ChoreoData.blendIn
		for _, joint in { "Root", "LeftKnee", "RightKnee", "LeftShoulder", "RightShoulder", "RightWrist" } do
			expect(blends[joint]).never.toBeNil()
			expect(blends[joint] > own).toBe(true)
		end
		for _, name in ATTACKS do
			for _, seconds in GaitHandOff.blends(ClipLibrary.get(P .. name)) do
				expect(seconds >= 1 / 60).toBe(true)
			end
		end
	end)

	it("is what Locomotion hands an attack started over a running gait", function()
		local FRAME = 1 / 60
		local model = buildRig("PlayerR15")
		local animator = Choreo.get(model)
		local locomotion = Locomotion.new(animator, model, { footIK = false }) :: any
		local state: any =
			{ moveDir = Vector3.new(0, 0, -1), speed = 16, sprinting = false, grounded = true, turning = 0 }
		for _ = 1, 60 do
			locomotion:update(FRAME, state)
			animator:step(FRAME)
		end
		expect(locomotion.gaitShown > 0.5).toBe(true)
		local clip = ClipLibrary.get(P .. "Basic1")
		local handle = animator:play(P .. "Basic1") :: any
		locomotion:update(FRAME, state)
		animator:step(FRAME)
		expect(handle.jointBlendIn).never.toBeNil()
		local want = GaitHandOff.blends(clip)
		local got = 0
		for joint, seconds in handle.jointBlendIn :: any do
			got += 1
			expect(math.abs(seconds - want[joint]) < 1e-9).toBe(true)
		end
		expect(got > 0).toBe(true)
		locomotion:destroy()
		Choreo.release(model)
	end)
end)
