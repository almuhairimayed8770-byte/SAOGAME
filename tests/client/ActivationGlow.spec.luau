--!strict
--[[
	The Art activation's blade glow (F13, section 5 "the blade glows in the Art's color"). The
	PointLight (range 8, brightness 2, section 11) barely moves a thin blade in daylight: the review
	measured the lit blade at about 173/198/217 going to 183/215/228. So the activation also puts a
	glow on the blade itself: camera-facing bands from the guard to the tip in the activation's
	color at the ribbon's saturation, drawn unlit (LightInfluence 0) so the sun cannot wash them
	out, wider than the blade so a thin blade near the camera still shows it. It holds from the
	activation past the white flash to the first damage frame (activationLight off), fades with the
	light when the Art is cancelled, and goes with the rig.
]]

local Trails = Harness.load("src/client/fx/Trails")
local FrameClock = Harness.load("src/client/fx/FrameClock")
local TrailRibbon = Harness.load("src/client/fx/TrailRibbon")
local fx = Harness.load("src/shared/data/fx")
local palette = Harness.load("src/shared/data/palette")

local FRAME = 1 / 60
local TOKEN = fx.trail.defaultToken
local GLOW = fx.activationLight.glow
-- The review's daylight blade pixel before the glow, and after the light alone (0..1).
local BLADE = Color3.fromRGB(173, 198, 217)
local LIGHT_ONLY = Color3.fromRGB(183, 215, 228)

-- A rig whose Weapon part is the one-handed sword's blade (3.2 x 0.32 x 0.1 studs).
local function rig(): (Model, BasePart)
	local model = Instance.new("Model")
	local weapon = Instance.new("Part")
	weapon.Name = "Weapon"
	weapon.Size = Vector3.new(0.32, 3.2, 0.1)
	weapon:SetAttribute(fx.trail.colorAttribute, TOKEN)
	weapon.Parent = model
	return model, weapon
end

local function glowsOf(weapon: BasePart): { Beam }
	local found: { Beam } = {}
	for _, layer in GLOW.layers do
		local beam = weapon:FindFirstChild(GLOW.name .. layer.name)
		if beam ~= nil and beam:IsA("Beam") then
			table.insert(found, beam)
		end
	end
	return found
end

local function lit(beams: { Beam }): boolean
	for _, beam in beams do
		if not beam.Enabled then
			return false
		end
	end
	return #beams > 0
end

local function anyLit(beams: { Beam }): boolean
	for _, beam in beams do
		if beam.Enabled then
			return true
		end
	end
	return false
end

-- A hand-driven FrameClock: one call is one rendered frame; the change made inside `during` shows on it.
local function frames(): ((during: (() -> ())?) -> (), () -> ())
	local startFn: ((number) -> ())? = nil
	local endFn: ((number) -> ())? = nil
	FrameClock.bind({
		now = function(): number
			return 0
		end,
		onFrameStart = function(fn)
			startFn = fn
			return function() end
		end,
		onFrameEnd = function(fn)
			endFn = fn
			return function() end
		end,
		onHeartbeat = function()
			return function() end
		end,
	})
	return function(during: (() -> ())?)
		(startFn :: (number) -> ())(FRAME)
		if during ~= nil then
			during()
		end
		(endFn :: (number) -> ())(FRAME)
	end, function()
		FrameClock.bind(nil)
	end
end

local function largest(color: Color3, other: Color3): number
	return math.max(math.abs(color.R - other.R), math.abs(color.G - other.G), math.abs(color.B - other.B))
end

describe("Activation glow on the blade (F13)", function()
	it("glows along the blade from the activation, past the white flash, to the first damage frame", function()
		local frame, done = frames()
		local model, weapon = rig()
		frame(function()
			Trails.activationLight(model, true, TOKEN)
		end)
		local beams = glowsOf(weapon)
		expect(#beams).toBe(#GLOW.layers)
		expect(lit(beams)).toBe(true)
		local start = weapon:FindFirstChild("TrailStart")
		local finish = weapon:FindFirstChild("TrailEnd")
		local thickest = math.max(weapon.Size.X, weapon.Size.Z)
		for index, beam in beams do
			expect(beam.Attachment0).toBe(start)
			expect(beam.Attachment1).toBe(finish)
			expect(beam.FaceCamera).toBe(true)
			expect(beam.LightInfluence).toBe(0)
			expect(beam.Width0).toBeCloseTo(GLOW.layers[index].width, 1e-6)
		end
		-- The body is wider than the blade, so a thin blade near the camera still shows it.
		expect(beams[1].Width0 >= thickest * 2).toBe(true)
		for _ = 1, fx.activationLight.flashFrames + 30 do
			frame()
		end
		expect(lit(beams)).toBe(true)
		-- The first damage frame: the cut takes over, the glow goes with the light.
		Trails.activationLight(model, false, TOKEN)
		expect(anyLit(beams)).toBe(false)
		Trails.detach(model)
		done()
	end)

	it("reads over the daylight blade: saturated, nearly opaque, far from the steel's own color", function()
		local frame, done = frames()
		local model, weapon = rig()
		frame(function()
			Trails.activationLight(model, true, TOKEN)
		end)
		local body = glowsOf(weapon)[1]
		local color = body.Color.Keypoints[1].Value
		local _, saturation = color:ToHSV()
		expect(saturation >= 0.6).toBe(true)
		local expected = TrailRibbon.saturate(palette.color3(TOKEN))
			:Lerp(palette.color3("SystemWhite"), GLOW.layers[1].whiteBlend)
		expect(largest(color, expected) < 1e-3).toBe(true)
		local transparency = body.Transparency.Keypoints[1].Value
		expect(transparency <= 0.25).toBe(true)
		-- The blade pixel under the body (unlit, so the sun adds nothing): the light alone moved it
		-- at most 0.07 a channel; the glow moves it by more than a quarter.
		local shown = BLADE:Lerp(color, 1 - transparency)
		expect(largest(LIGHT_ONLY, BLADE) < 0.08).toBe(true)
		expect(largest(shown, BLADE) > 0.25).toBe(true)
		Trails.detach(model)
		done()
	end)

	it("a cancelled Art's glow fades with its light and is gone when the light goes out", function()
		local beat: ((number) -> ())? = nil
		Trails.start()
		Trails.bind({
			onWatch = function(fn)
				beat = fn
				return function()
					beat = nil
				end
			end,
			onRender = function()
				return function() end
			end,
		})
		local model, weapon = rig()
		Trails.activationLight(model, true, TOKEN)
		local body = glowsOf(weapon)[1]
		local last = body.Transparency.Keypoints[1].Value
		Trails.activationLight(model, false, TOKEN, true)
		expect(body.Enabled).toBe(true)
		local steps = math.floor(fx.activationLight.cancelFadeSeconds / FRAME + 0.5)
		for _ = 1, steps - 1 do
			(beat :: (number) -> ())(FRAME)
			expect(body.Enabled).toBe(true)
			local now = body.Transparency.Keypoints[1].Value
			expect(now > last).toBe(true)
			last = now
		end
		(beat :: (number) -> ())(FRAME)
		expect(anyLit(glowsOf(weapon))).toBe(false)
		-- Lit again, it starts at full.
		Trails.activationLight(model, true, TOKEN)
		expect(body.Transparency.Keypoints[1].Value).toBeCloseTo(GLOW.layers[1].transparency, 1e-6)
		Trails.detach(model)
		expect(anyLit(glowsOf(weapon))).toBe(false)
		Trails.bind(nil)
		Trails.reset()
	end)
end)
