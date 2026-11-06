--!strict
-- Shatter: the shatter's sound follows the caller's weight (sfx.shatterCues). A mob shatters with
-- the Shatter cue, a player or an Elite with ShatterHeavy (the bass dive at full level), a boss
-- with BossShatter whatever weight the caller names; a two-argument call keeps the old rule (the
-- Boss kind is the boss shatter, every other kind the normal one). The pool's Play is recorded
-- through its seams; every asset has loaded and nothing is scheduled.
local Shatter = Harness.load("src/client/fx/Shatter")
local Bursts = Harness.load("src/client/fx/Bursts")
local fx = Harness.load("src/shared/data/fx")
local SfxPool = Harness.load("src/client/audio/SfxPool")
local sfx = Harness.load("src/shared/data/sfx")

-- Sound.Volume is a 32-bit float in the engine.
local FLOAT = 1e-6

type Play = { name: string, volume: number }

-- A one-part rig standing at the origin.
local function rig(): Model
	local model = Instance.new("Model")
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Parent = model
	model.PrimaryPart = torso
	return model
end

-- Runs `body` with the pool's plays recorded, then puts the pool back on the engine seams.
local function recording(body: (plays: { Play }) -> ())
	local plays: { Play } = {}
	SfxPool.reset()
	SfxPool.bind({
		now = function(): number
			return 0
		end,
		delay = function(_seconds: number, _fn: () -> ()) end,
		onStep = function(_fn: (number) -> ()): () -> ()
			return function() end
		end,
		play = function(sound: Sound): boolean
			table.insert(plays, { name = sound.Name, volume = sound.Volume })
			return true
		end,
		stop = function(_sound: Sound) end,
		timeLength = function(_sound: Sound): number
			return 30
		end,
		preload = function(_sounds: { Instance }) end,
	})
	local ok, err = pcall(body, plays)
	SfxPool.reset()
	SfxPool.bind(nil)
	if not ok then
		error(err, 0)
	end
end

local function names(plays: { Play }): { string }
	local list = {}
	for _, play in plays do
		table.insert(list, play.name)
	end
	return list
end

local function cueNames(cueName: string): { string }
	local list = {}
	for _, layer in sfx.cue(cueName) do
		table.insert(list, layer.name)
	end
	return list
end

local function volumeOf(plays: { Play }, name: string): number?
	for _, play in plays do
		if play.name == name then
			return play.volume
		end
	end
	return nil
end

describe("Shatter.play: the cue follows the caller's weight", function()
	local dive = sfx.get("impact", "SubDrop").volume

	it("shatters a mob with the Shatter cue, its bass dive 3 dB down (the old two-argument call)", function()
		recording(function(plays)
			Shatter.play(rig(), "Beast")
			expect(names(plays)).toEqual(cueNames(sfx.shatterCues.normal))
			expect(volumeOf(plays, "impact.SubDrop")).toBeCloseTo(dive * 10 ^ (-3 / 20), FLOAT)
		end)
		recording(function(plays)
			Shatter.play(rig(), "Beast", "normal")
			expect(names(plays)).toEqual(cueNames(sfx.shatterCues.normal))
		end)
	end)

	it("shatters a player or an Elite heavier: ShatterHeavy, the bass dive at full level", function()
		recording(function(plays)
			Shatter.play(rig(), "Humanoid", "heavy")
			expect(names(plays)).toEqual(cueNames(sfx.shatterCues.heavy))
			expect(volumeOf(plays, "impact.SubDrop")).toBeCloseTo(dive, FLOAT)
		end)
		-- The death row's cue name (moments.luau shatterCue) picks the same cue.
		recording(function(plays)
			Shatter.play(rig(), "Humanoid", sfx.shatterCues.heavy)
			expect(names(plays)).toEqual(cueNames(sfx.shatterCues.heavy))
			expect(volumeOf(plays, "impact.SubDrop")).toBeCloseTo(dive, FLOAT)
		end)
	end)

	it("shatters a boss as a boss whatever weight the caller names", function()
		for _, weight in { "none", "normal", "heavy", "boss" } do
			recording(function(plays)
				Shatter.play(rig(), "Boss", if weight == "none" then nil else weight :: any)
				expect(names(plays)).toEqual(cueNames(sfx.shatterCues.boss))
			end)
		end
	end)

	it("hides the rig and lays its shards for every weight", function()
		for _, weight in { "normal", "heavy" } do
			recording(function(_plays)
				local before = Shatter.liveCount()
				local model = rig()
				Shatter.play(model, "Humanoid", weight)
				expect(Shatter.liveCount()).toBeGreaterThan(before)
				expect((model:FindFirstChild("UpperTorso") :: BasePart).LocalTransparencyModifier).toBe(1)
			end)
		end
	end)
end)

-- Measured in Studio: a kill while the display slept. The shards (Heartbeat) were gone before the
-- wake; the white flash is a particle burst, and particles fly only on rendered frames. It is
-- cleared on Heartbeat at its lifetime, so the frame that comes back never shows it.
describe("Shatter's white flash across a render stall", function()
	it("clears the flash burst on Heartbeat at its lifetime", function()
		local clock = 0
		local watch: ((number) -> ())? = nil
		local cleared: { number } = {}
		local emitted = 0
		Bursts.bind({
			now = function(): number
				return clock
			end,
			onHeartbeat = function(fn: (number) -> ()): () -> ()
				watch = fn
				return function()
					if watch == fn then
						watch = nil
					end
				end
			end,
			emit = function(_emitter: any, count: number)
				emitted += count
			end,
			clear = function(_emitter: any)
				table.insert(cleared, clock)
			end,
		})
		local ok, err = pcall(function()
			recording(function(_plays)
				Shatter.play(rig(), "Beast")
				expect(emitted).toBeGreaterThan(0)
				expect(watch).never.toBeNil()
				local F = 1 / 60
				while watch ~= nil and clock < 5 do
					clock += F
					local beat = watch :: (number) -> ()
					beat(F)
				end
				expect(#cleared).toBe(1)
				expect(cleared[1]).toBeGreaterThanOrEqual(fx.shatter.flash.lifetime - 1e-9)
				expect(cleared[1]).toBeLessThanOrEqual(fx.shatter.flash.lifetime + F + 1e-9)
			end)
		end)
		Bursts.reset()
		Bursts.bind(nil)
		if not ok then
			error(err, 0)
		end
	end)
end)

-- Kills that land together (D-478): one sweep's kills, and another fight's across the map in the
-- same frame. Each body flashes and breaks where it stood, on that frame; the shatter cue cracks
-- once within one sound's reach of any of them.
describe("Shatter: kills that land together (D-478)", function()
	-- A one-part rig standing at `position`.
	local function rigAt(position: Vector3): Model
		local model = rig()
		local torso = model.PrimaryPart :: BasePart
		torso.CFrame = CFrame.new(position)
		return model
	end

	it("crack once within a sound's reach of any of them; each body flashes where it stood", function()
		local flashes: { Vector3 } = {}
		Bursts.bind({
			now = function(): number
				return 0
			end,
			onHeartbeat = function(_fn: (number) -> ()): () -> ()
				return function() end
			end,
			emit = function(emitter: any, _count: number)
				table.insert(flashes, (emitter.Parent :: BasePart).CFrame.Position)
			end,
			clear = function(_emitter: any) end,
		})
		local ok, err = pcall(function()
			recording(function(plays)
				local here = Vector3.new(0, 3, 0)
				local across = here + Vector3.new(sfx.mix.rolloffMaxDistance * 2, 0, 0)
				local beside = here + Vector3.new(fx.audio.dedupeDistance * 2, 0, 0)
				local spots = { here, across, beside }
				local before = Shatter.liveCount()
				for _, spot in spots do
					Shatter.play(rigAt(spot), "Beast")
				end
				-- One Shatter here and one across the map; the second kill here adds none.
				expect(#plays).toBe(2 * #sfx.cue(sfx.shatterCues.normal))
				-- Every body still breaks and flashes at its own spot, this frame.
				expect(Shatter.liveCount() - before).toBeGreaterThanOrEqual(3)
				expect(#flashes).toBe(#spots)
				for index, spot in spots do
					expect((flashes[index] - spot).Magnitude).toBeLessThan(1e-3)
				end
			end)
		end)
		Bursts.reset()
		Bursts.bind(nil)
		if not ok then
			error(err, 0)
		end
	end)
end)

-- The shards against the drawn limbs (AW 569(c) on 577a59a; D-681). The PC tested every shard
-- against its own part's oriented box on the row before the death row: the boar walking at 144 had
-- 4 of 40 outside, by the Tail and both tusks, 0.15 to 0.34 from their centres (1 of 72 at 60, by
-- the Tail); standing, none. Here a boar drawn mid-walk at a heading (its pose solved from the walk
-- clip on its root) shatters, and each shard is read against the part it was laid in: Shatter lays
-- them round the rig's visible parts but the root, in order, one part after another.
local Engine = Harness.load("src/client/fx/Engine")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")

-- The boar drawn at `yaw` degrees, `t` seconds into its walk: every part where the pose puts it.
local function walkingBoar(yaw: number, t: number): Model
	local model = RigBuilder.build("Boar")
	local rig = Rigs.Boar
	local height = rig.hipHeight + rig.parts[rig.rootPart].size[2] / 2
	local root = CFrame.new(3, height, -4) * CFrame.Angles(0, math.rad(yaw), 0)
	local clip = ClipLibrary.get(ChoreoData.rigs.Boar.walk)
	local solved = Pose.solve(model, root, ClipSampler.sample(clip, t))
	for _, descendant in model:GetDescendants() do
		local frame = solved[descendant.Name]
		if descendant:IsA("BasePart") and frame ~= nil then
			-- The spec's parts keep CFrame and Position apart: both are written.
			descendant.CFrame = frame
			descendant.Position = frame.Position
		end
	end
	return model
end

-- The parts Shatter lays shards in, in its order: every visible part but the root.
local function shedding(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and descendant ~= model.PrimaryPart
			and descendant.Name ~= "HumanoidRootPart"
			and descendant.Transparency < 1
		then
			table.insert(list, descendant)
		end
	end
	return list
end

describe("Shatter: every shard starts inside its drawn limb (AW 569(c); D-681)", function()
	for _, yaw in { 0, 45, 90, 135 } do
		for _, t in { 0.1, 0.3 } do
			it(("the boar walking at %d deg, %.1f s into its walk"):format(yaw, t), function()
				recording(function(_plays)
					-- Past every shatter the real clock started.
					local clock = os.clock() + 1e5
					Engine.setClock(function(): number
						return clock
					end)
					local ok, err = pcall(function()
						-- The shatters before this one are over: their shards go back to the pool.
						Shatter.step()
						-- Shatter's live folder (Engine.folder keeps one per parent and name).
						local live = Engine.folder(workspace, fx.shatter.poolFolderName .. "Live")
						local before: { [Instance]: boolean } = {}
						for _, child in live:GetChildren() do
							before[child] = true
						end
						local model = walkingBoar(yaw, t)
						local limbs = shedding(model)
						local frames: { CFrame } = {}
						for index, part in limbs do
							frames[index] = part.CFrame
						end
						Shatter.play(model, "Beast")
						local shards: { BasePart } = {}
						for _, child in live:GetChildren() do
							if not before[child] and child:IsA("BasePart") then
								table.insert(shards, child)
							end
						end
						expect(#shards).toBeGreaterThanOrEqual(#limbs)
						local worst, worstPart = 0, ""
						for index, shard in shards do
							local limb = (index - 1) % #limbs + 1
							local size = limbs[limb].Size
							local at = frames[limb]:PointToObjectSpace(shard.CFrame.Position)
							local out = math.max(
								math.abs(at.X) - size.X / 2,
								math.abs(at.Y) - size.Y / 2,
								math.abs(at.Z) - size.Z / 2
							)
							if out > worst then
								worst, worstPart = out, limbs[limb].Name
							end
						end
						if worst > 1e-6 then
							error(
								("%d shards: one starts %.3f outside its part's box, by the %s"):format(
									#shards,
									worst,
									worstPart
								)
							)
						end
						-- Every shard goes back to the pool.
						clock += 10
						Shatter.step()
					end)
					Engine.setClock(nil)
					if not ok then
						error(err, 0)
					end
				end)
			end)
		end
	end
end)
