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
				impact = noop,
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

-- Trails.swingDirection: the module samples each tracked blade tip (TrailEnd) into a short ring
-- on its own Heartbeat; under Lune there is no Heartbeat, so the spec calls Trails.sample() once
-- per fake frame after moving the weapon part by hand. The module reads the part's Position and
-- the tip's WorldPosition, which the engine derives from the frames and Lune does not, so sampleAt
-- puts them where the engine would. Rigs other spec files attached are forgotten first
-- (Trails.reset).
local accents = Harness.load("src/shared/data/accents")

local SAMPLES = accents.swing.samples
Trails.reset()

-- Places the weapon part (its tip where the engine puts it) and records one sample, seen from
-- `viewer` (the origin, so the rig is near, unless given).
local function sampleAt(weapon: BasePart, frame: CFrame, viewer: Vector3?)
	weapon.CFrame = frame
	weapon.Position = frame.Position
	local tip = weapon:FindFirstChild("TrailEnd")
	if tip ~= nil and tip:IsA("Attachment") then
		tip.WorldPosition = (frame * tip.CFrame).Position
	end
	Engine.setViewer(function()
		return viewer or Vector3.zero
	end)
	local ok, err = pcall(Trails.sample)
	Engine.setViewer(nil)
	if not ok then
		error(err, 0)
	end
end

local function expectUnit(actual: Vector3?, expected: Vector3)
	expect(actual).never.toBeNil()
	local direction = actual :: Vector3
	local want = expected.Unit
	expect(direction.Magnitude).toBeCloseTo(1, 1e-4)
	expect(direction.X).toBeCloseTo(want.X, 1e-3)
	expect(direction.Y).toBeCloseTo(want.Y, 1e-3)
	expect(direction.Z).toBeCloseTo(want.Z, 1e-3)
end

describe("Trails.swingDirection", function()
	it("reports the unit motion of the blade tip over the last samples", function()
		local model, weapon = rig()
		Trails.attach(model)
		for step = 1, SAMPLES do
			sampleAt(weapon, CFrame.new(step * 0.8, 1, -step * 0.4))
		end
		expectUnit(Trails.swingDirection(model), Vector3.new(0.8, 0, -0.4))
		Trails.detach(model)
	end)

	it("only counts the last samples: an older swing the other way is forgotten", function()
		local model, weapon = rig()
		Trails.attach(model)
		for step = 1, SAMPLES * 2 do
			sampleAt(weapon, CFrame.new(0, 0, step))
		end
		-- Then the blade turns along +X for one step fewer than the ring: the oldest sample left is
		-- the last one of the +Z run, so the answer is pure +X.
		for step = 1, SAMPLES - 1 do
			sampleAt(weapon, CFrame.new(step, 0, SAMPLES * 2))
		end
		expectUnit(Trails.swingDirection(model), Vector3.xAxis)
		Trails.detach(model)
	end)

	it("measures across the whole ring, from the oldest sample it keeps", function()
		local model, weapon = rig()
		Trails.attach(model)
		-- One step along +Z, then the rest along +X: only a direction over the whole ring keeps
		-- the +Z step (a shorter window would see pure +X).
		sampleAt(weapon, CFrame.new(0, 0, 0))
		sampleAt(weapon, CFrame.new(0, 0, 1))
		for step = 1, SAMPLES - 2 do
			sampleAt(weapon, CFrame.new(step, 0, 1))
		end
		expectUnit(Trails.swingDirection(model), Vector3.new(SAMPLES - 2, 0, 1))
		Trails.detach(model)
	end)

	it("follows the tip, not the part: a blade turning about its middle still has a direction", function()
		local model, weapon = rig()
		Trails.attach(model)
		local tip = weapon:FindFirstChild("TrailEnd") :: Attachment
		local angles = {}
		for step = 1, SAMPLES do
			local angle = step * 0.12
			table.insert(angles, angle)
			sampleAt(weapon, CFrame.new(5, 2, 0) * CFrame.Angles(0, 0, angle))
		end
		local first = (CFrame.new(5, 2, 0) * CFrame.Angles(0, 0, angles[1]) * tip.CFrame).Position
		local last = (CFrame.new(5, 2, 0) * CFrame.Angles(0, 0, angles[#angles]) * tip.CFrame).Position
		expectUnit(Trails.swingDirection(model), last - first)
		-- Tipped toward -X as it turns counterclockwise about Z.
		expect((Trails.swingDirection(model) :: Vector3).X).toBeLessThan(0)
		Trails.detach(model)
	end)

	it("reads a weapon's own TrailEnd where the builder put it", function()
		local model, weapon = rig()
		local tip = Instance.new("Attachment")
		tip.Name = "TrailEnd"
		tip.CFrame = CFrame.new(0.3, 1.5, 0)
		tip.Parent = weapon
		Trails.attach(model)
		for step = 1, SAMPLES do
			sampleAt(weapon, CFrame.Angles(step * 0.1, 0, 0))
		end
		local first = (CFrame.Angles(0.1, 0, 0) * tip.CFrame).Position
		local last = (CFrame.Angles(SAMPLES * 0.1, 0, 0) * tip.CFrame).Position
		expectUnit(Trails.swingDirection(model), last - first)
		Trails.detach(model)
	end)

	it("is nil before two samples, for a tip that barely moved, across a jump and for an unknown rig", function()
		local model, weapon = rig()
		Trails.attach(model)
		expect(Trails.swingDirection(model)).toBeNil()
		sampleAt(weapon, CFrame.new(0, 0, 0))
		expect(Trails.swingDirection(model)).toBeNil()
		-- Under minTravel across the whole ring: still.
		local creep = accents.swing.minTravel * 0.5 / SAMPLES
		for step = 1, SAMPLES do
			sampleAt(weapon, CFrame.new(step * creep, 0, 0))
		end
		expect(Trails.swingDirection(model)).toBeNil()
		-- A move just past minTravel is a direction.
		sampleAt(weapon, CFrame.new(accents.swing.minTravel * 2, 0, 0))
		expectUnit(Trails.swingDirection(model), Vector3.xAxis)
		-- A respawn or teleport: farther than maxTravel inside the ring.
		sampleAt(weapon, CFrame.new(accents.swing.maxTravel * 2, 0, 0))
		expect(Trails.swingDirection(model)).toBeNil()
		expect(Trails.swingDirection(Instance.new("Model"))).toBeNil()
		Trails.detach(model)
	end)

	it("forgets a rig's ring on detach and starts over on the next attach", function()
		local model, weapon = rig()
		Trails.attach(model)
		for step = 1, SAMPLES do
			sampleAt(weapon, CFrame.new(step, 0, 0))
		end
		expect(Trails.swingDirection(model)).never.toBeNil()
		Trails.detach(model)
		expect(Trails.swingDirection(model)).toBeNil()
		Trails.attach(model)
		sampleAt(weapon, CFrame.new(SAMPLES + 1, 0, 0))
		expect(Trails.swingDirection(model)).toBeNil()
		Trails.detach(model)
	end)

	it("sampling leaves the trail itself alone", function()
		atViewer(function()
			local model, weapon = rig()
			Trails.setActive(model, true, "Basic")
			local enabled = trailOf(weapon).Enabled
			local color = colorOf(weapon)
			local width = headWidth(weapon)
			for step = 1, SAMPLES * 2 do
				sampleAt(weapon, CFrame.new(step, 0, 0))
			end
			expect(trailOf(weapon).Enabled).toBe(enabled)
			expectColor(colorOf(weapon), color)
			expect(headWidth(weapon)).toBeCloseTo(width, 1e-6)
			Trails.setActive(model, false, "Basic")
			Trails.detach(model)
		end)
	end)
end)

-- The swing remembered after the trail goes off: a HitConfirmed lands a round trip after the
-- damage window, when the blade is already in its follow-through (or held still by the hit-stop).
describe("Trails.swingDirection memory", function()
	local MEMORY = accents.swing.memorySeconds

	-- Runs `body` with a hand clock and puts the engine's clock back afterwards.
	local function withClock(body: (clock: { now: number }) -> ())
		local clock = { now = 50 }
		Engine.setClock(function()
			return clock.now
		end)
		local ok, err = pcall(body, clock)
		Engine.setClock(nil)
		if not ok then
			error(err, 0)
		end
	end

	-- Swings the tip along +X for a whole ring with a trail kind on, one sample a frame.
	local function swing(model: Model, weapon: BasePart, clock: { now: number })
		Trails.setActive(model, true, "Basic")
		for step = 1, SAMPLES do
			clock.now += 1 / 60
			sampleAt(weapon, CFrame.new(step, 0, 0))
		end
	end

	it("answers the swing, not the follow-through, for memorySeconds after the trail goes off", function()
		withClock(function(clock)
			local model, weapon = rig()
			swing(model, weapon, clock)
			expectUnit(Trails.swingDirection(model), Vector3.xAxis)
			Trails.setActive(model, false, "Basic")
			-- The follow-through turns back along -Z.
			for step = 1, SAMPLES do
				clock.now += 1 / 60
				sampleAt(weapon, CFrame.new(SAMPLES, 0, -step))
			end
			expectUnit(Trails.swingDirection(model), Vector3.xAxis)
			-- Past the memory: the tip's motion now.
			clock.now += MEMORY
			expectUnit(Trails.swingDirection(model), Vector3.new(0, 0, -1))
			Trails.detach(model)
		end)
	end)

	it("holds the swing through a hit-stop's stillness while the trail is still on", function()
		withClock(function(clock)
			local model, weapon = rig()
			swing(model, weapon, clock)
			-- The hit-stop freezes the blade: the ring goes still.
			for _ = 1, SAMPLES do
				clock.now += 1 / 60
				sampleAt(weapon, CFrame.new(SAMPLES, 0, 0))
			end
			expectUnit(Trails.swingDirection(model), Vector3.xAxis)
			clock.now += MEMORY * 2
			expect(Trails.swingDirection(model)).toBeNil()
			Trails.setActive(model, false, "Basic")
			Trails.detach(model)
		end)
	end)

	it("answers the snap, not the settle, while the trail is still on", function()
		withClock(function(clock)
			local model, weapon = rig()
			-- The snap: fast along +X (a stud a frame).
			swing(model, weapon, clock)
			-- The overshoot and settle spring back along -X, slower, with the trail still on, until
			-- a HitConfirmed a round trip after the window asks.
			for step = 1, 2 * SAMPLES do
				clock.now += 1 / 60
				sampleAt(weapon, CFrame.new(SAMPLES - step * 0.2, 0, step * 0.05))
			end
			expectUnit(Trails.swingDirection(model), Vector3.xAxis)
			-- Past the memory the snap is forgotten: the settle's motion then.
			clock.now += MEMORY
			expect((Trails.swingDirection(model) :: Vector3).X).toBeLessThan(0)
			Trails.setActive(model, false, "Basic")
			Trails.detach(model)
		end)
	end)

	it("at a low frame rate reads the snap from the pose before the strike began", function()
		withClock(function(clock)
			local model, weapon = rig()
			Trails.attach(model)
			-- 20 fps: the last pose before the window, then the window opens with the snap.
			sampleAt(weapon, CFrame.new(0, 0, 0))
			clock.now += 0.01
			Trails.setActive(model, true, "Art")
			-- The first frame drawn after it is past the key already (the snap, then the overshoot
			-- springing back), and the next frames settle back along -X.
			clock.now += 0.04
			sampleAt(weapon, CFrame.new(3.5, 0, 0))
			for step = 1, SAMPLES - 1 do
				clock.now += 0.05
				sampleAt(weapon, CFrame.new(3.5 - step, 0, 0))
			end
			expectUnit(Trails.swingDirection(model), Vector3.xAxis)
			Trails.setActive(model, false, "Art")
			Trails.detach(model)
		end)
	end)

	it("a strike's next damage window starts a new snap", function()
		withClock(function(clock)
			local model, weapon = rig()
			-- Window 1 snaps fast along +X.
			Trails.setActive(model, true, "Art")
			for step = 1, SAMPLES do
				clock.now += 1 / 60
				sampleAt(weapon, CFrame.new(step * 2, 0, 0))
			end
			-- Window 2 of the same trail (HitWindowOpen turns Art on again) snaps slower along +Y.
			Trails.setActive(model, true, "Art")
			-- A smear frame inside it is the same snap, never a new one.
			Trails.setActive(model, true, "Smear")
			for step = 1, SAMPLES do
				clock.now += 1 / 60
				sampleAt(weapon, CFrame.new(SAMPLES * 2, step * 0.5, 0))
			end
			Trails.setActive(model, false, "Smear")
			expectUnit(Trails.swingDirection(model), Vector3.yAxis)
			Trails.setActive(model, false, "Art")
			Trails.detach(model)
		end)
	end)

	it("a new swing replaces the remembered one, and a blade that never swung has none", function()
		withClock(function(clock)
			local model, weapon = rig()
			swing(model, weapon, clock)
			-- The next swing (its TrailOn) goes along +Z while its trail is on.
			Trails.setActive(model, true, "Basic")
			for step = 1, SAMPLES do
				clock.now += 1 / 60
				sampleAt(weapon, CFrame.new(SAMPLES, 0, step))
			end
			expectUnit(Trails.swingDirection(model), Vector3.zAxis)
			Trails.setActive(model, false, "Basic")
			for _ = 1, SAMPLES do
				sampleAt(weapon, CFrame.new(SAMPLES, 0, SAMPLES))
			end
			expectUnit(Trails.swingDirection(model), Vector3.zAxis)
			Trails.detach(model)

			-- Moved with no trail on (a walk, a sheathe): nothing remembered, the motion now only.
			local idle, blade = rig()
			Trails.attach(idle)
			for step = 1, SAMPLES do
				clock.now += 1 / 60
				sampleAt(blade, CFrame.new(0, step, 0))
			end
			for _ = 1, SAMPLES do
				sampleAt(blade, CFrame.new(0, SAMPLES, 0))
			end
			expect(Trails.swingDirection(idle)).toBeNil()
			Trails.detach(idle)
		end)
	end)

	it("forgets the remembered swing on detach", function()
		withClock(function(clock)
			local model, weapon = rig()
			swing(model, weapon, clock)
			Trails.setActive(model, false, "Basic")
			Trails.detach(model)
			Trails.attach(model)
			expect(Trails.swingDirection(model)).toBeNil()
			Trails.detach(model)
		end)
	end)
end)

-- What a Heartbeat's sample costs: the tip's WorldPosition (no CFrame built), and only for rigs
-- whose answer can matter: a swinging one, or an idle one within accents.swing.sampleDistance.
describe("Trails.sample", function()
	local function range(): number
		return accents.swing.sampleDistance
	end

	it("reads the tip where the engine puts it (its WorldPosition), not a frame it builds", function()
		local model, weapon = rig()
		Trails.attach(model)
		local tip = weapon:FindFirstChild("TrailEnd") :: Attachment
		-- The part stays put; only the tip's world position moves (as a frame of a turning blade).
		weapon.Position = Vector3.zero
		Engine.setViewer(function()
			return Vector3.zero
		end)
		local ok, err = pcall(function()
			for step = 1, SAMPLES do
				tip.WorldPosition = Vector3.new(0, 1, -step * 0.6)
				Trails.sample()
			end
		end)
		Engine.setViewer(nil)
		if not ok then
			error(err, 0)
		end
		expectUnit(Trails.swingDirection(model), Vector3.new(0, 0, -1))
		Trails.detach(model)
	end)

	it("leaves an idle rig beyond the trail distance alone, and samples one that swings there", function()
		local model, weapon = rig()
		Trails.attach(model)
		local far = range() + 20
		for step = 1, SAMPLES do
			sampleAt(weapon, CFrame.new(far + step, 0, 0))
		end
		expect(Trails.swingDirection(model)).toBeNil()
		-- Within the distance it is sampled while idle.
		for step = 1, SAMPLES do
			sampleAt(weapon, CFrame.new(range() - 20 - step, 0, 0))
		end
		expectUnit(Trails.swingDirection(model), Vector3.new(-1, 0, 0))
		-- Far again and swinging: sampled, whatever the distance.
		Trails.setActive(model, true, "Art")
		for step = 1, SAMPLES do
			sampleAt(weapon, CFrame.new(far, step, 0))
		end
		expectUnit(Trails.swingDirection(model), Vector3.yAxis)
		Trails.setActive(model, false, "Art")
		Trails.detach(model)
	end)

	it("starts the ring over when a rig comes back in range: no chord across the gap", function()
		local model, weapon = rig()
		Trails.attach(model)
		sampleAt(weapon, CFrame.new(0, 0, 0))
		sampleAt(weapon, CFrame.new(0, 0, 1))
		-- Away past the distance (not sampled), then back a few studs from where it left.
		for _ = 1, SAMPLES do
			sampleAt(weapon, CFrame.new(range() + 50, 0, 0))
		end
		sampleAt(weapon, CFrame.new(6, 0, 1))
		expect(Trails.swingDirection(model)).toBeNil()
		sampleAt(weapon, CFrame.new(6, 0, 3))
		expectUnit(Trails.swingDirection(model), Vector3.zAxis)
		Trails.detach(model)
	end)

	it("skips a weapon that left the world, and starts over when it is back", function()
		local model, weapon = rig()
		Trails.attach(model)
		Trails.setActive(model, true, "Basic")
		weapon.Parent = nil
		for step = 1, SAMPLES do
			sampleAt(weapon, CFrame.new(step, 0, 0))
		end
		expect(Trails.swingDirection(model)).toBeNil()
		weapon.Parent = model
		sampleAt(weapon, CFrame.new(0, 0, 0))
		sampleAt(weapon, CFrame.new(0, 2, 0))
		expectUnit(Trails.swingDirection(model), Vector3.yAxis)
		Trails.setActive(model, false, "Basic")
		Trails.detach(model)
	end)

	it("reset forgets every rig", function()
		local model, weapon = rig()
		Trails.setActive(model, true, "Art")
		for step = 1, SAMPLES do
			sampleAt(weapon, CFrame.new(step, 0, 0))
		end
		expect(Trails.swingDirection(model)).never.toBeNil()
		Trails.reset()
		expect(Trails.swingDirection(model)).toBeNil()
		expect(Trails.tokenOf(model)).toBeNil()
		expect(trailOf(weapon).Enabled).toBe(false)
	end)
end)

-- Render stalls (D-142): RenderStepped stops while the display sleeps and Heartbeat goes on, and a
-- frame can be presented after a stall before the first render step runs (D-125). The module's
-- render step, its Heartbeat (the watchdog), its clock and Trail:Clear() are driven by hand
-- through Trails.bind: a frame runs the render step and then Heartbeat, as the engine does; a
-- frame in the dark runs Heartbeat alone.
local choreo = Harness.load("src/shared/data/choreo")

describe("Trails across a render stall (D-142)", function()
	local FRAME = 1 / 60
	local JUMP = choreo.stall.jumpSeconds

	type Clear = { trail: Trail, enabled: boolean }

	type Drive = {
		now: () -> number,
		render: () -> (),
		heartbeat: () -> (),
		frame: () -> (),
		sleep: () -> (),
		clears: { Clear },
		finish: () -> (),
	}

	local function drive(): Drive
		local clock = 0
		local renderFn: ((dt: number) -> ())? = nil
		local watchFn: ((dt: number) -> ())? = nil
		local clears: { Clear } = {}
		Engine.setViewer(function()
			return Vector3.zero
		end)
		Trails.start()
		Trails.bind({
			now = function(): number
				return clock
			end,
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
			clear = function(trail: Trail)
				table.insert(clears, { trail = trail, enabled = trail.Enabled })
			end,
		})
		local function render()
			assert(renderFn ~= nil, "Trails connected no render step")
			renderFn(FRAME)
		end
		local function heartbeat()
			assert(watchFn ~= nil, "Trails connected no watchdog")
			watchFn(FRAME)
		end
		return {
			now = function(): number
				return clock
			end,
			render = render,
			heartbeat = heartbeat,
			frame = function()
				clock += FRAME
				render()
				heartbeat()
			end,
			sleep = function()
				clock += FRAME
				heartbeat()
			end,
			clears = clears,
			finish = function()
				Trails.bind(nil)
				Trails.reset()
				Engine.setViewer(nil)
			end,
		}
	end

	-- A rig tracked from the start, its tip where the engine would put it (Lune derives no
	-- WorldPosition), so the Heartbeat's sample can read it.
	local function trackedRig(): (Model, BasePart)
		local model, weapon = rig()
		weapon.Position = Vector3.zero
		Trails.attach(model)
		local tip = weapon:FindFirstChild("TrailEnd") :: Attachment
		tip.WorldPosition = Vector3.zero
		return model, weapon
	end

	-- Sleeps until the last frame rendered more than a jump ago; returns when it went dark.
	local function sleepPastJump(d: Drive): number
		local dark = d.now()
		repeat
			d.sleep()
		until d.now() - dark > JUMP
		return dark
	end

	it("display awake: a lit trail stays lit frame after frame and is never cleared (guard)", function()
		local d = drive()
		local model, weapon = trackedRig()
		d.frame()
		Trails.setActive(model, true, "Art")
		for _ = 1, 120 do
			d.frame()
			expect(trailOf(weapon).Enabled).toBe(true)
		end
		Trails.setActive(model, false, "Art")
		expect(trailOf(weapon).Enabled).toBe(false)
		expect(#d.clears).toBe(0)
		d.finish()
	end)

	it("a stall shorter than a jump is a long frame: the trail stays lit, nothing is cleared (guard)", function()
		local d = drive()
		local model, weapon = trackedRig()
		d.frame()
		Trails.setActive(model, true, "Art")
		local dark = d.now()
		while d.now() + FRAME - dark <= JUMP do
			d.sleep()
			expect(trailOf(weapon).Enabled).toBe(true)
		end
		d.frame()
		expect(trailOf(weapon).Enabled).toBe(true)
		expect(#d.clears).toBe(0)
		d.finish()
	end)

	it("a trail lit when the display sleeps is out and cleared on the first Heartbeat past a jump", function()
		local d = drive()
		local model, weapon = trackedRig()
		d.frame()
		Trails.setActive(model, true, "Art")
		local dark = d.now()
		repeat
			d.sleep()
			if d.now() - dark <= JUMP then
				expect(trailOf(weapon).Enabled).toBe(true)
			end
		until d.now() - dark > JUMP
		-- Out before any frame can show it, its segments dropped after it went out.
		expect(trailOf(weapon).Enabled).toBe(false)
		expect(#d.clears).toBe(1)
		expect(d.clears[1].trail).toBe(trailOf(weapon))
		expect(d.clears[1].enabled).toBe(false)
		for _ = 1, 600 do
			d.sleep()
		end
		expect(trailOf(weapon).Enabled).toBe(false)
		expect(#d.clears).toBe(1)
		d.finish()
	end)

	it("nothing lights a trail in the dark: a kind turned on there, or a white flash, waits for a frame", function()
		local d = drive()
		local model, weapon = trackedRig()
		d.frame()
		sleepPastJump(d)
		-- A far rig steps on Heartbeat and its TrailOn routes as ever; a parry flashes the blade.
		Trails.setActive(model, true, "Basic")
		expect(trailOf(weapon).Enabled).toBe(false)
		Trails.flashWhite(model, 2)
		expect(trailOf(weapon).Enabled).toBe(false)
		d.sleep()
		expect(trailOf(weapon).Enabled).toBe(false)
		-- The wake's render step lights it, cleared first.
		local before = #d.clears
		d.render()
		expect(trailOf(weapon).Enabled).toBe(true)
		expect(#d.clears).toBe(before + 1)
		expect(d.clears[#d.clears].enabled).toBe(false)
		d.finish()
	end)

	it("the wake's render step clears the trail before it lights again; the jump's TrailOff puts it out", function()
		for _, order in { "trails first", "rig first" } do
			local d = drive()
			local model, weapon = trackedRig()
			d.frame()
			Trails.setActive(model, true, "Art")
			sleepPastJump(d)
			local before = #d.clears
			if order == "trails first" then
				-- The swing is still on when the render step runs: from where the blade is now.
				d.render()
				expect(#d.clears).toBe(before + 1)
				expect(d.clears[#d.clears].trail).toBe(trailOf(weapon))
				expect(d.clears[#d.clears].enabled).toBe(false)
				expect(trailOf(weapon).Enabled).toBe(true)
				-- Then the rig's jump step in the same render step: Replication closes the kind.
				Trails.setActive(model, false, "Art")
			else
				Trails.setActive(model, false, "Art")
				expect(trailOf(weapon).Enabled).toBe(false)
				d.render()
				expect(#d.clears).toBe(before + 1)
			end
			-- What the frame draws: the trail out.
			expect(trailOf(weapon).Enabled).toBe(false)
			d.heartbeat()
			d.frame()
			expect(trailOf(weapon).Enabled).toBe(false)
			d.finish()
		end
	end)

	it("a swing that goes on past the wake draws from there, and the next stall is caught again", function()
		local d = drive()
		local model, weapon = trackedRig()
		d.frame()
		Trails.setActive(model, true, "Art")
		sleepPastJump(d)
		d.frame()
		expect(trailOf(weapon).Enabled).toBe(true)
		local clears = #d.clears
		for _ = 1, 30 do
			d.frame()
			expect(trailOf(weapon).Enabled).toBe(true)
		end
		expect(#d.clears).toBe(clears)
		sleepPastJump(d)
		expect(trailOf(weapon).Enabled).toBe(false)
		expect(#d.clears).toBe(clears + 1)
		d.finish()
	end)

	it("before the first render step (a client that has drawn nothing yet) no stall is called", function()
		local d = drive()
		local model, weapon = trackedRig()
		Trails.setActive(model, true, "Art")
		for _ = 1, 120 do
			d.sleep()
		end
		expect(trailOf(weapon).Enabled).toBe(true)
		expect(#d.clears).toBe(0)
		d.finish()
	end)
end)
