--!strict
--[[
	A ribbon names the rig it draws (D-362; Studio items 295(b) and 302(a)).

	The PC counted the trail ribbon's Beams on 10 to 12 frames around every flinch of a struck
	stance and on frames +3 to +13 after a doomed Art press, and read them as the player's. Through
	the real path the player's stance never lights its trail: a Sharp Nail or Vertical stance let go
	with struckStanceBlendOut fades through its TrailOn (0.33, 0.35) and Replication.routeClipEvent
	starts nothing on a clip taken away (0 setActive(true) calls; tests/client/Replication.spec's
	"a clip taken away starts nothing"). The kobold whose axe staggers the player lights its own
	ribbon on its Overhead's TrailOn (1.3 s to TrailOff 1.52 s): 13 frames at 60 fps, 16 with a
	6-frame hold. Every ribbon's Beams sit in one workspace folder (fx.trail.ribbon.folderName) on a
	host part named TrailRibbon whatever rig draws it, so a per-frame log cannot tell them apart.

	Each ribbon's host carries the rig it draws now in its fx.trail.ribbon.ownerAttribute attribute
	(the rig model's full name), set when a rig takes the ribbon from the pool, so a logger counts
	the player's own.
]]
local Trails = Harness.load("src/client/fx/Trails")
local Engine = Harness.load("src/client/fx/Engine")
local fx = Harness.load("src/shared/data/fx")

local FRAME = 1 / 60
local TOKEN = fx.trail.defaultToken
local RIBBON = fx.trail.ribbon
local SHOULDER_C0 = CFrame.new(1.5, 0.5, 0)
local ROOT_AT = CFrame.new(0, 3, 0)
local PIVOT = (ROOT_AT * SHOULDER_C0).Position

type Rig = {
	model: Model,
	weapon: BasePart,
	shoulder: Motor6D,
	grip: Motor6D,
	arm: BasePart,
	root: BasePart,
}

local function rig(): Rig
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = ROOT_AT
	root.Parent = model
	model.PrimaryPart = root
	local arm = Instance.new("Part")
	arm.Name = "RightArm"
	arm.Size = Vector3.new(1, 2, 1)
	arm.Parent = model
	local weapon = Instance.new("Part")
	weapon.Name = "Weapon"
	weapon.Size = Vector3.new(0.2, 4, 0.2)
	weapon.Position = PIVOT
	weapon:SetAttribute(fx.trail.colorAttribute, TOKEN)
	weapon.Parent = model
	local start = Instance.new("Attachment")
	start.Name = "TrailStart"
	start.CFrame = CFrame.new(0, -1.4, 0)
	start.Parent = weapon
	local finish = Instance.new("Attachment")
	finish.Name = "TrailEnd"
	finish.CFrame = CFrame.new(0, 2, 0)
	finish.Parent = weapon
	-- Lune derives no WorldPosition; the tip ring (swingDirection) reads it.
	finish.WorldPosition = PIVOT
	local shoulder = Instance.new("Motor6D")
	shoulder.Name = "RightShoulder"
	shoulder.Part0 = root
	shoulder.Part1 = arm
	shoulder.C0 = SHOULDER_C0
	shoulder.C1 = CFrame.new(0, 0.5, 0)
	shoulder.Transform = CFrame.identity
	shoulder.Parent = root
	local grip = Instance.new("Motor6D")
	grip.Name = "Weapon"
	grip.Part0 = arm
	grip.Part1 = weapon
	grip.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	grip.C1 = CFrame.new(0, -1.6, 0)
	grip.Transform = CFrame.identity
	grip.Parent = arm
	return { model = model, weapon = weapon, shoulder = shoulder, grip = grip, arm = arm, root = root }
end

type Drive = {
	frame: () -> (),
	sleep: () -> (),
	setHeld: (held: boolean) -> (),
	finish: () -> (),
}

-- The render step, Heartbeat, both clocks and the hit-stop read driven by hand: a frame runs the
-- render step (the pose readers', where the module samples) and then Heartbeat.
local function drive(): Drive
	local clock = 0
	local held = false
	local renderFn: ((dt: number) -> ())? = nil
	local watchFn: ((dt: number) -> ())? = nil
	local function now(): number
		return clock
	end
	Engine.setViewer(function()
		return Vector3.zero
	end)
	Engine.setClock(now)
	Trails.start()
	Trails.bind({
		now = now,
		onRender = function(fn: (dt: number) -> ()): () -> ()
			renderFn = fn
			return function()
				renderFn = nil
			end
		end,
		onWatch = function(fn: (dt: number) -> ()): () -> ()
			watchFn = fn
			return function()
				watchFn = nil
			end
		end,
		clear = function(_trail: Trail) end,
		held = function(_model: Instance): boolean
			return held
		end,
	})
	return {
		frame = function()
			clock += FRAME
			assert(renderFn ~= nil, "Trails connected no render step");
			(renderFn :: (dt: number) -> ())(FRAME)
			assert(watchFn ~= nil, "Trails connected no watchdog");
			(watchFn :: (dt: number) -> ())(FRAME)
		end,
		sleep = function()
			clock += FRAME
			assert(watchFn ~= nil, "Trails connected no watchdog");
			(watchFn :: (dt: number) -> ())(FRAME)
		end,
		setHeld = function(value: boolean)
			held = value
		end,
		finish = function()
			Trails.bind(nil)
			Trails.reset()
			Engine.setViewer(nil)
			Engine.setClock(nil)
		end,
	}
end

-- Runs `body` with a fresh drive and always puts the engine back.
local function driven(body: (drive: Drive) -> ())
	local current = drive()
	local ok, err = pcall(body, current)
	current.finish()
	if not ok then
		error(err, 0)
	end
end

local function turn(target: Rig, degrees: number)
	target.shoulder.Transform = CFrame.Angles(math.rad(degrees), 0, 0)
end

local function viewOf(model: Model): any
	return (Trails :: any).ribbonOf(model)
end

local function beamsOf(model: Model, layer: number): { Beam }
	local view = viewOf(model)
	return if view ~= nil then view.beams[layer] else {}
end

-- The host part that holds a rig's ribbon Beams now (nil while it draws none).
local function hostOf(model: Model): Instance?
	for layer in RIBBON.layers do
		local beams = beamsOf(model, layer)
		if #beams > 0 then
			return beams[1].Parent
		end
	end
	return nil
end

describe("A ribbon names the rig it draws (D-362)", function()
	it("each lit rig's ribbon host carries that rig's name, and a pooled ribbon takes its new rig's", function()
		driven(function(d)
			expect(RIBBON.ownerAttribute).never.toBeNil()
			local player, kobold = rig(), rig()
			player.model.Name = "PlayerRig"
			kobold.model.Name = "KoboldRig"
			for _, target in { player, kobold } do
				turn(target, 0)
				Trails.attach(target.model)
			end
			d.frame()
			Trails.setActive(player.model, true, "Art")
			Trails.setActive(kobold.model, true, "Basic")
			d.frame()
			turn(player, 90)
			turn(kobold, 90)
			d.frame()
			for _, target in { player, kobold } do
				local host = hostOf(target.model)
				expect(host).never.toBeNil()
				expect((host :: Instance):GetAttribute(RIBBON.ownerAttribute)).toBe(target.model:GetFullName())
			end
			expect(hostOf(player.model)).never.toBe(hostOf(kobold.model))
			-- The player's goes out and fades back to the pool, named by no rig; the kobold's next
			-- stroke may take it.
			local playerHost = hostOf(player.model) :: Instance
			Trails.setActive(player.model, false, "Art")
			for _ = 1, 60 do
				d.frame()
			end
			expect(viewOf(player.model)).toBeNil()
			expect(playerHost:GetAttribute(RIBBON.ownerAttribute)).toBeNil()
			Trails.setActive(kobold.model, false, "Basic")
			for _ = 1, 60 do
				d.frame()
			end
			Trails.setActive(kobold.model, true, "Basic")
			d.frame()
			turn(kobold, 0)
			d.frame()
			local host = hostOf(kobold.model)
			expect(host).never.toBeNil()
			expect((host :: Instance):GetAttribute(RIBBON.ownerAttribute)).toBe(kobold.model:GetFullName())
		end)
	end)
end)
