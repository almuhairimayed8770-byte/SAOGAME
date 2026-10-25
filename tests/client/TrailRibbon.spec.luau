--!strict
--[[
	The weapon trail as a ribbon of sub-frame blade samples (D-261, review issue 8). The engine Trail
	takes one sample a rendered frame, so a cut that sweeps most of its arc between two frames drew
	a straight chord or a slab. A rig with a blade chain (a root part and joints out to the Weapon)
	draws its trail from the blade solved by forward kinematics at sub-steps between the frames it
	renders: the cut shows its arc, thick and in the trail's hue at full strength, only while a
	trail kind is on (the hit windows), and its tail fades where it was drawn.

	The rig is a root, an arm on a shoulder Motor6D and the Weapon on a grip Motor6D. Turning the
	shoulder's Transform about its X axis swings every point of the blade around the shoulder, so a
	point of the ribbon drawn on the arc stays at its radius from the shoulder; a chord between the
	two frames' blades would cut inside it.
]]

local Trails = Harness.load("src/client/fx/Trails")
local Engine = Harness.load("src/client/fx/Engine")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local fx = Harness.load("src/shared/data/fx")
local palette = Harness.load("src/shared/data/palette")
local choreo = Harness.load("src/shared/data/choreo")
local TrailRibbon = Harness.load("src/client/fx/TrailRibbon")

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

local function countOf(model: Model): number
	local view = viewOf(model)
	return if view ~= nil then view.count else 0
end

local function beamsOf(model: Model, layer: number): { Beam }
	local view = viewOf(model)
	return if view ~= nil then view.beams[layer] else {}
end

local function trailOf(weapon: BasePart): Trail
	return weapon:FindFirstChildOfClass("Trail") :: Trail
end

-- The trail color's hue at the ribbon's strength: HSV saturation times ribbon.saturation (<= 1).
local function saturated(color: Color3): Color3
	local hue, saturation, value = color:ToHSV()
	return Color3.fromHSV(hue, math.min(1, saturation * RIBBON.saturation), value)
end

local function expectColor(actual: Color3, expected: Color3)
	expect(actual.R).toBeCloseTo(expected.R, 1e-3)
	expect(actual.G).toBeCloseTo(expected.G, 1e-3)
	expect(actual.B).toBeCloseTo(expected.B, 1e-3)
end

describe("Trail ribbon from sub-frame blade samples (D-261)", function()
	it("a cut that sweeps 120 degrees between two frames draws the arc around the shoulder, not its chord", function()
		driven(function(d)
			local target = rig()
			turn(target, 0)
			Trails.attach(target.model)
			d.frame()
			Trails.setActive(target.model, true, "Art")
			d.frame()
			turn(target, 120)
			d.frame()
			local view = viewOf(target.model)
			expect(view).never.toBeNil()
			-- The tip moves about 6.5 studs: the frame splits into every sub-step it may take.
			expect(view.count).toBeGreaterThanOrEqual(RIBBON.maxSubsteps)
			for layer in RIBBON.layers do
				local points = view.points[layer]
				local radius = (points[1] - PIVOT).Magnitude
				expect(radius).toBeGreaterThan(1)
				for _, point in points do
					expect((point - PIVOT).Magnitude).toBeCloseTo(radius, 1e-3)
				end
				-- The ends are the two frames' blades.
				local chord = (points[#points] - points[1]).Magnitude
				expect(chord).toBeCloseTo(2 * radius * math.sin(math.rad(60)), 1e-3)
				-- One stroke: every neighbouring pair is joined by a Beam.
				expect(#view.beams[layer]).toBe(view.count - 1)
			end
			-- The ribbon draws instead of the engine Trail; the trail still counts as on.
			expect(trailOf(target.weapon).Enabled).toBe(false)
			expect(Trails.isEnabled(target.model)).toBe(true)
		end)
	end)

	it("draws nothing outside a hit window; the tail fades where it was drawn, gone after its lifetime", function()
		driven(function(d)
			local target = rig()
			Trails.attach(target.model)
			for step = 0, 6 do
				turn(target, step * 20)
				d.frame()
			end
			expect(countOf(target.model)).toBe(0)
			Trails.setActive(target.model, true, "Art")
			for step = 7, 10 do
				turn(target, step * 20)
				d.frame()
			end
			local drawn = countOf(target.model)
			expect(drawn).toBeGreaterThan(4)
			Trails.setActive(target.model, false, "Art")
			local shown = #beamsOf(target.model, 1)
			for step = 11, 13 do
				turn(target, step * 20)
				d.frame()
				expect(countOf(target.model) <= drawn).toBe(true)
			end
			expect(#beamsOf(target.model, 1) <= shown).toBe(true)
			local frames = math.ceil(fx.trail.lifetime / FRAME) + 1
			for _ = 1, frames do
				d.frame()
			end
			expect(countOf(target.model)).toBe(0)
			expect(#beamsOf(target.model, 1)).toBe(0)
			expect(#beamsOf(target.model, 2)).toBe(0)
		end)
	end)

	it("is thick and wears the trail's hue at full strength; a Basic swing is thinner and whiter", function()
		driven(function(d)
			local target = rig()
			Trails.attach(target.model)
			d.frame()
			Trails.setActive(target.model, true, "Art")
			turn(target, 40)
			d.frame()
			local body = beamsOf(target.model, 1)
			expect(#body).toBeGreaterThan(0)
			local newest = body[#body]
			local layer = RIBBON.layers[1]
			local full = fx.trail.defaultWidth * fx.trail.width.Art
			expect(newest.Width1).toBeCloseTo(full * RIBBON.thickness * layer.width, 1e-4)
			expect(newest.Width1).toBeGreaterThan(full * 2)
			local color = newest.Color.Keypoints[1].Value
			expectColor(color, saturated(palette.color3(TOKEN)))
			local _, trailSaturation = palette.color3(TOKEN):ToHSV()
			local _, artSaturation = color:ToHSV()
			expect(artSaturation).toBeGreaterThan(trailSaturation * 2)
			-- The core is lighter than the body and glows.
			local core = beamsOf(target.model, 2)
			expect(#core).toBe(#body)
			expect(core[#core].LightEmission).toBe(RIBBON.layers[2].lightEmission)
			expect(core[#core].Width1 < newest.Width1).toBe(true)
			Trails.setActive(target.model, false, "Art")

			local other = rig()
			Trails.attach(other.model)
			d.frame()
			Trails.setActive(other.model, true, "Basic")
			turn(other, 40)
			d.frame()
			local basic = beamsOf(other.model, 1)
			expect(#basic).toBeGreaterThan(0)
			local thin = basic[#basic]
			expect(thin.Width1).toBeCloseTo(fx.trail.defaultWidth * fx.trail.width.Basic * RIBBON.thickness, 1e-4)
			local _, basicSaturation = thin.Color.Keypoints[1].Value:ToHSV()
			expect(basicSaturation < artSaturation).toBe(true)
			local expected =
				saturated(palette.color3(TOKEN)):Lerp(palette.color3("TrailWhite"), fx.trail.basicWhiteBlend)
			expectColor(thin.Color.Keypoints[1].Value, expected)
		end)
	end)

	it("a new window starts a new stroke: the last window's tail is never joined to the next cut", function()
		driven(function(d)
			local target = rig()
			Trails.attach(target.model)
			d.frame()
			Trails.setActive(target.model, true, "Art")
			turn(target, 30)
			d.frame()
			Trails.setActive(target.model, false, "Art")
			turn(target, -60)
			d.frame()
			Trails.setActive(target.model, true, "Art")
			turn(target, -90)
			d.frame()
			local view = viewOf(target.model)
			expect(view).never.toBeNil()
			-- Two strokes: one Beam fewer than one stroke of that many samples would show.
			expect(#view.beams[1]).toBe(view.count - 2)
			-- No Beam spans the gap between the strokes (the blade moved 90 degrees out of the window).
			local gap = 2 * (view.points[1][1] - PIVOT).Magnitude * math.sin(math.rad(45))
			for _, beam in view.beams[1] do
				local a = (beam.Attachment0 :: Attachment).Position
				local b = (beam.Attachment1 :: Attachment).Position
				expect((a - b).Magnitude < gap * 0.5).toBe(true)
			end
		end)
	end)

	it("holds its ages through a hit-stop, then fades", function()
		driven(function(d)
			local target = rig()
			Trails.attach(target.model)
			d.frame()
			Trails.setActive(target.model, true, "Art")
			turn(target, 60)
			d.frame()
			Trails.setActive(target.model, false, "Art")
			local count = countOf(target.model)
			local first = beamsOf(target.model, 1)[1]
			local transparency = first.Transparency.Keypoints[1].Value
			d.setHeld(true)
			for _ = 1, 20 do
				d.frame()
			end
			expect(countOf(target.model)).toBe(count)
			expect(first.Enabled).toBe(true)
			expect(first.Transparency.Keypoints[1].Value).toBeCloseTo(transparency, 1e-6)
			d.setHeld(false)
			for _ = 1, math.ceil(fx.trail.lifetime / FRAME) + 1 do
				d.frame()
			end
			expect(countOf(target.model)).toBe(0)
		end)
	end)

	it("a render stall drops the ribbon; the first frame after it draws from where the blade is", function()
		driven(function(d)
			local target = rig()
			Trails.attach(target.model)
			d.frame()
			Trails.setActive(target.model, true, "Art")
			turn(target, 30)
			d.frame()
			expect(countOf(target.model)).toBeGreaterThan(1)
			for _ = 1, math.ceil(choreo.stall.jumpSeconds / FRAME) + 2 do
				d.sleep()
			end
			expect(countOf(target.model)).toBe(0)
			turn(target, 150)
			d.frame()
			-- The window is still on: one sample where the blade is, nothing across the gap.
			expect(countOf(target.model)).toBe(1)
			expect(#beamsOf(target.model, 1)).toBe(0)
			turn(target, 160)
			d.frame()
			expect(countOf(target.model)).toBeGreaterThan(1)
		end)
	end)

	it("follows the sword to a new mount: the chain is read again when the grip joint changes", function()
		driven(function(d)
			local target = rig()
			Trails.attach(target.model)
			d.frame()
			Trails.setActive(target.model, true, "Art")
			turn(target, 20)
			d.frame()
			-- The sword moves to the back (WeaponMount writes Part0 and C0 of its joint).
			target.grip.Part0 = target.root
			target.grip.C0 = CFrame.new(0, 0, 0.6) * CFrame.Angles(0, 0, math.rad(45))
			d.frame()
			local view = viewOf(target.model)
			local chain = BladeContact.chain(target.model)
			assert(chain ~= nil, "the rig has a blade chain")
			local guard, tip = BladeContact.blade(chain, BladeContact.read(chain))
			local layer = RIBBON.layers[1]
			local newest = view.points[1][view.count]
			expect((newest - guard:Lerp(tip, layer.fraction)).Magnitude).toBeCloseTo(0, 1e-3)
			-- The jump to the back is never drawn as a cut.
			for _, beam in view.beams[1] do
				local a = (beam.Attachment0 :: Attachment).Position
				local b = (beam.Attachment1 :: Attachment).Position
				expect((a - b).Magnitude < 1).toBe(true)
			end
		end)
	end)

	it("a rig with no blade chain keeps the engine Trail", function()
		driven(function(d)
			local model = Instance.new("Model")
			local weapon = Instance.new("Part")
			weapon.Name = "Weapon"
			weapon.Size = Vector3.new(0.2, 4, 0.2)
			weapon:SetAttribute(fx.trail.colorAttribute, TOKEN)
			weapon.Parent = model
			Trails.attach(model)
			local tip = weapon:FindFirstChild("TrailEnd") :: Attachment
			tip.WorldPosition = Vector3.zero
			Trails.setActive(model, true, "Art")
			d.frame()
			expect(trailOf(weapon).Enabled).toBe(true)
			expect(viewOf(model)).toBeNil()
		end)
	end)
end)

describe("TrailRibbon's ring of samples", function()
	local STYLE = { color = Color3.new(0.5, 0.9, 1), whiteBlend = 0, width = 1, lifetime = 10 }

	local function at(index: number): Vector3
		return Vector3.new(index, 0, 0)
	end

	it("wraps past maxSamples: the newest samples in order, one Beam fewer, never newest to oldest", function()
		local ribbon = TrailRibbon.new()
		local total = RIBBON.maxSamples + 13
		for index = 1, total do
			TrailRibbon.push(ribbon, at(index), at(index) + Vector3.yAxis, index * 0.001, index > 1)
		end
		TrailRibbon.draw(ribbon, total * 0.001, STYLE)
		local view = TrailRibbon.view(ribbon)
		expect(view.count).toBe(RIBBON.maxSamples)
		local first = total - RIBBON.maxSamples + 1
		for offset, point in view.points[1] do
			expect(point.X).toBeCloseTo(first + offset - 1, 1e-6)
		end
		expect(#view.beams[1]).toBe(RIBBON.maxSamples - 1)
		for _, beam in view.beams[1] do
			local a = (beam.Attachment0 :: Attachment).Position
			local b = (beam.Attachment1 :: Attachment).Position
			expect((a - b).Magnitude).toBeCloseTo(1, 1e-6)
		end
		TrailRibbon.destroy(ribbon)
	end)

	it("skips a joined sample that barely moved; an unjoined one breaks the chain", function()
		local ribbon = TrailRibbon.new()
		expect(TrailRibbon.push(ribbon, at(0), at(0) + Vector3.yAxis, 0, false)).toBe(true)
		local still = at(0) + Vector3.yAxis * (1 + fx.trail.minLength * 0.5)
		expect(TrailRibbon.push(ribbon, at(0), still, 0.001, true)).toBe(false)
		TrailRibbon.push(ribbon, at(1), at(1) + Vector3.yAxis, 0.002, true)
		TrailRibbon.push(ribbon, at(5), at(5) + Vector3.yAxis, 0.003, false)
		TrailRibbon.push(ribbon, at(6), at(6) + Vector3.yAxis, 0.004, true)
		TrailRibbon.draw(ribbon, 0.004, STYLE)
		local view = TrailRibbon.view(ribbon)
		expect(view.count).toBe(4)
		expect(#view.beams[1]).toBe(2)
		TrailRibbon.destroy(ribbon)
	end)

	it("ages out from the tail: widths and transparency by age, nothing left after the lifetime", function()
		local ribbon = TrailRibbon.new()
		local style = { color = Color3.new(0.5, 0.9, 1), whiteBlend = 0, width = 2, lifetime = 0.2 }
		for index = 0, 4 do
			TrailRibbon.push(ribbon, at(index), at(index) + Vector3.yAxis, index * 0.05, index > 0)
		end
		TrailRibbon.draw(ribbon, 0.2, style)
		local view = TrailRibbon.view(ribbon)
		-- The first sample is a lifetime old: gone, and the Beam from it with it.
		expect(view.count).toBe(4)
		local beams = view.beams[1]
		expect(#beams).toBe(3)
		local newest = beams[#beams]
		expect(newest.Width1).toBeCloseTo(2 * TrailRibbon.evaluate(fx.trail.widthKeys, 0), 1e-6)
		expect(beams[1].Width0 < newest.Width1).toBe(true)
		local oldFade = beams[1].Transparency.Keypoints[1].Value
		local newFade = newest.Transparency.Keypoints[1].Value
		expect(oldFade > newFade).toBe(true)
		TrailRibbon.draw(ribbon, 0.4, style)
		expect(TrailRibbon.live(ribbon)).toBe(false)
		expect(#TrailRibbon.view(ribbon).beams[1]).toBe(0)
		TrailRibbon.destroy(ribbon)
	end)
end)
