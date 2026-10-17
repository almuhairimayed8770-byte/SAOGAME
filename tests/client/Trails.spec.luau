--!strict
-- The weapon trail's look per kind (section 10): Art trails are full width in the trail color,
-- Basic trails thinner and whiter, and the smear frames run the trail at full width. Trail.Color
-- and WidthScale recolor the whole trail at once, so the smear frames of a Basic swing must widen
-- it without trading its whiter color for the full one, and the tail that fades after the swing
-- keeps the look of the swing that drew it.
local Trails = Harness.load("src/client/fx/Trails")
local Engine = Harness.load("src/client/fx/Engine")
local Replication = Harness.load("src/client/controllers/Replication")
local Basic1 = Harness.load("src/shared/clips/player/OneHandedSword/Basic1")
local fx = Harness.load("src/shared/data/fx")
local palette = Harness.load("src/shared/data/palette")

local TOKEN = fx.trail.defaultToken

-- A rig with a placeholder Weapon part at the viewer, so the budget lets its trail draw.
local function rig(): (Model, BasePart)
	local model = Instance.new("Model")
	local weapon = Instance.new("Part")
	weapon.Name = "Weapon"
	weapon.Size = Vector3.new(0.2, 4, 0.2)
	weapon:SetAttribute(fx.trail.colorAttribute, TOKEN)
	weapon.Parent = model
	return model, weapon
end

local function trailOf(weapon: BasePart): Trail
	return weapon:FindFirstChildOfClass("Trail") :: Trail
end

local function colorOf(weapon: BasePart): Color3
	return trailOf(weapon).Color.Keypoints[1].Value
end

local function headWidth(weapon: BasePart): number
	return trailOf(weapon).WidthScale.Keypoints[1].Value
end

local function expectColor(actual: Color3, expected: Color3)
	expect(actual.R).toBeCloseTo(expected.R, 1e-4)
	expect(actual.G).toBeCloseTo(expected.G, 1e-4)
	expect(actual.B).toBeCloseTo(expected.B, 1e-4)
end

-- Runs `body` with the viewer at the origin and puts the engine's viewer back afterwards.
local function atViewer(body: () -> ())
	Engine.setViewer(function()
		return Vector3.zero
	end)
	local ok, err = pcall(body)
	Engine.setViewer(nil)
	if not ok then
		error(err, 0)
	end
end

local fullColor = palette.color3(TOKEN)
local basicColor = fullColor:Lerp(palette.color3("TrailWhite"), fx.trail.basicWhiteBlend)

describe("Trails", function()
	it("widens a Basic swing to full width for the smear frames without losing its whiter color", function()
		atViewer(function()
			local model, weapon = rig()
			Trails.setActive(model, true, "Basic")
			expect(trailOf(weapon).Enabled).toBe(true)
			expectColor(colorOf(weapon), basicColor)
			local thin = headWidth(weapon)

			Trails.setActive(model, true, "Smear")
			expect(trailOf(weapon).Enabled).toBe(true)
			expectColor(colorOf(weapon), basicColor)
			expect(headWidth(weapon) / thin).toBeCloseTo(fx.trail.width.Smear / fx.trail.width.Basic, 1e-4)

			Trails.setActive(model, false, "Smear")
			expect(trailOf(weapon).Enabled).toBe(true)
			expectColor(colorOf(weapon), basicColor)
			expect(headWidth(weapon)).toBeCloseTo(thin, 1e-5)

			-- The swing ends: the trail stops drawing, and the tail still fading keeps the Basic look.
			Trails.setActive(model, false, "Basic")
			expect(trailOf(weapon).Enabled).toBe(false)
			expectColor(colorOf(weapon), basicColor)
			expect(headWidth(weapon)).toBeCloseTo(thin, 1e-5)
			Trails.detach(model)
		end)
	end)

	it("keeps an Art trail in the full color through its smear, and an Art over a Basic wins", function()
		atViewer(function()
			local model, weapon = rig()
			Trails.setActive(model, true, "Art")
			expectColor(colorOf(weapon), fullColor)
			local full = headWidth(weapon)
			Trails.setActive(model, true, "Smear")
			expectColor(colorOf(weapon), fullColor)
			expect(headWidth(weapon)).toBeCloseTo(full, 1e-5)
			Trails.setActive(model, false, "Smear")
			Trails.setActive(model, false, "Art")
			expect(trailOf(weapon).Enabled).toBe(false)
			expectColor(colorOf(weapon), fullColor)

			-- The next swing is a Basic, then an Art starts on top of it: the Art's look wins.
			Trails.setActive(model, true, "Basic")
			expectColor(colorOf(weapon), basicColor)
			Trails.setActive(model, true, "Art")
			expectColor(colorOf(weapon), fullColor)
			expect(headWidth(weapon)).toBeCloseTo(full, 1e-5)
			Trails.setActive(model, false, "Art")
			expectColor(colorOf(weapon), basicColor)
			Trails.setActive(model, false, "Basic")
			Trails.detach(model)
		end)
	end)

	it("Basic1's own clip events keep one color while only the smear frames go full width", function()
		atViewer(function()
			local model, weapon = rig()
			local noop = setmetatable({}, {
				__index = function()
					return function() end
				end,
			})
			Replication.bind({
				net = { on = function() end },
				entities = {},
				localId = function()
					return nil
				end,
				locomotion = noop,
				choreo = noop,
				clipLibrary = noop,
				trails = Trails,
				smear = noop,
				shatter = noop,
				sparks = noop,
				telegraphs = noop,
				outline = noop,
				switchRing = noop,
				digits = noop,
				hud = noop,
				systemLine = noop,
				sfx = noop,
				camera = noop,
				weaponCategory = function()
					return "OneHandedSword"
				end,
				trailToken = function()
					return TOKEN
				end,
				positionOf = function()
					return Vector3.zero
				end,
				schedule = function() end,
			} :: any)
			local record = { id = 41, model = model, kind = "Player", rig = "PlayerR15" }

			local smearing = false
			local thin, wide = nil :: number?, nil :: number?
			local sawTrail, sawSmear = false, false
			for _, event in Basic1.events do
				Replication.routeClipEvent(record, Basic1.id, event)
				local trail = weapon:FindFirstChildOfClass("Trail")
				if trail == nil then
					continue
				end
				sawTrail = true
				if event.kind == "SmearOn" then
					smearing = true
					sawSmear = true
				elseif event.kind == "SmearOff" then
					smearing = false
				end
				-- One color from the TrailOn to the end of the clip, smear frames included.
				expectColor(colorOf(weapon), basicColor)
				if smearing then
					expect(trailOf(weapon).Enabled).toBe(true)
					wide = wide or headWidth(weapon)
					expect(headWidth(weapon)).toBeCloseTo(wide :: number, 1e-5)
				else
					thin = thin or headWidth(weapon)
					expect(headWidth(weapon)).toBeCloseTo(thin :: number, 1e-5)
				end
			end
			expect(sawTrail).toBe(true)
			expect(sawSmear).toBe(true)
			expect(wide :: number).toBeCloseTo((thin :: number) * fx.trail.width.Smear / fx.trail.width.Basic, 1e-4)
			Trails.detach(model)
		end)
	end)
end)
