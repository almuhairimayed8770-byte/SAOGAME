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
