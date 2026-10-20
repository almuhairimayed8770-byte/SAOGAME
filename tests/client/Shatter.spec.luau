--!strict
-- Shatter: the shatter's sound follows the caller's weight (sfx.shatterCues). A mob shatters with
-- the Shatter cue, a player or an Elite with ShatterHeavy (the bass dive at full level), a boss
-- with BossShatter whatever weight the caller names; a two-argument call keeps the old rule (the
-- Boss kind is the boss shatter, every other kind the normal one). The pool's Play is recorded
-- through its seams; every asset has loaded and nothing is scheduled.
local Shatter = Harness.load("src/client/fx/Shatter")
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
