--!strict
--[[
	MusicDirector (section 15): four looped stems per floor (ambient, explore, combat, boss) in
	the Music SoundGroup, crossfaded over 2 s by MusicState. Combat starts on the first telegraph
	(Telegraphs calls `noteTelegraph`) and ends 6 s after the last shatter (Shatter calls
	`noteShatter`). Below a quarter HP the music ducks 6 dB and the heartbeat layer rises
	(`setLowHp`). A boss entrance cuts to silence for 1 s, then the boss stem. `duck(db, seconds)`
	is the system voice and the death freeze.

	Stem ids are placeholders until the user supplies the floor's music (`setStems` swaps them;
	a placeholder stem is never played so the console stays clean).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Sfx = require(Shared.data.sfx)
local Engine = require(script.Parent.Parent.fx.Engine)
local MusicState = require(script.Parent.MusicState)
local SfxPool = require(script.Parent.SfxPool)

type Stem = {
	sound: Sound,
	id: string,
	playing: boolean,
}

local MusicDirector = {}

local state: MusicState.MusicState = MusicState.new(Engine.now())
local stems: { [string]: Stem } = {}
local stopLoop: (() -> ())? = nil
local lastLevels: MusicState.Levels? = nil
local started = false

local function isPlaceholder(id: string): boolean
	return id == Sfx.placeholderId or id == ""
end

local function ensureStem(name: string): Stem
	local existing = stems[name]
	if existing ~= nil then
		return existing
	end
	local sound = Instance.new("Sound")
	sound.Name = "Stem_" .. name
	sound.SoundId = Sfx.placeholderId
	sound.Looped = true
	sound.Volume = 0
	local group = SfxPool.group("Music")
	if group ~= nil then
		sound.SoundGroup = group
	end
	pcall(function()
		sound.Parent = SoundService
	end)
	local stem: Stem = { sound = sound, id = Sfx.placeholderId, playing = false }
	stems[name] = stem
	return stem
end

local function applyLevels(levels: MusicState.Levels)
	for name, stem in stems do
		local gain = if levels.silence then 0 else (levels.stems[name] or 0) * levels.duckGain
		stem.sound.Volume = gain
		local shouldPlay = gain > Fx.audio.stemFadeFloor and not isPlaceholder(stem.id)
		if shouldPlay and not stem.playing then
			stem.playing = pcall(function()
				stem.sound:Play()
			end)
		elseif not shouldPlay and stem.playing then
			stem.playing = false
			pcall(function()
				stem.sound:Stop()
			end)
		end
	end
	SfxPool.loop(Fx.audio.heartbeatLoop, if levels.silence then 0 else levels.heartbeat)
end

--- Advances the crossfades and applies the volumes (Heartbeat calls this; tests may too).
function MusicDirector.update()
	local levels = MusicState.update(state, Engine.now())
	lastLevels = levels
	applyLevels(levels)
end

--- Switches the music state: "Ambient" | "Explore" | "Combat" | "Boss" (Boss runs the entrance silence).
function MusicDirector.setState(name: MusicState.StateName)
	MusicDirector.start()
	MusicState.setState(state, name, Engine.now())
	MusicDirector.update()
end

--- Combat music starts on the first telegraph, not on aggro.
function MusicDirector.noteTelegraph()
	MusicDirector.start()
	MusicState.noteTelegraph(state, Engine.now())
end

--- Every shatter restarts the 6 s countdown back to the rest state.
function MusicDirector.noteShatter()
	MusicDirector.start()
	MusicState.noteShatter(state, Engine.now())
end

--- Below a quarter HP: the 6 dB duck and the heartbeat; above: release.
function MusicDirector.setLowHp(low: boolean)
	MusicDirector.start()
	MusicState.setLowHp(state, low)
end

--- Lowers the music by `db` for `seconds` (the system voice, the death freeze).
function MusicDirector.duck(db: number, seconds: number)
	MusicDirector.start()
	MusicState.duck(state, db, seconds, Engine.now())
	MusicDirector.update()
end

--- The boss entrance: 1 s of silence, then the boss stem.
function MusicDirector.bossEntrance()
	MusicDirector.start()
	MusicState.bossEntrance(state, Engine.now())
	MusicDirector.update()
end

--- Replaces the stem ids for the current floor ({ ambient = url, explore = url, combat = url, boss = url }).
function MusicDirector.setStems(ids: { [string]: string })
	MusicDirector.start()
	for _, name in Sfx.music.stems do
		local stem = ensureStem(name)
		local id = ids[name]
		if id ~= nil and id ~= stem.id then
			if stem.playing then
				stem.playing = false
				pcall(function()
					stem.sound:Stop()
				end)
			end
			stem.id = id
			stem.sound.SoundId = id
		end
	end
	MusicDirector.update()
end

--- The current state name.
function MusicDirector.state(): MusicState.StateName
	return state.state
end

--- The last applied levels (tests, the profiler).
function MusicDirector.levels(): MusicState.Levels?
	return lastLevels
end

--- Creates the four stems and starts the Heartbeat update.
function MusicDirector.start()
	if started then
		return
	end
	started = true
	SfxPool.start()
	state = MusicState.new(Engine.now())
	for _, name in Sfx.music.stems do
		ensureStem(name)
	end
	MusicDirector.update()
	stopLoop = Engine.onHeartbeat(function()
		MusicDirector.update()
	end)
end

--- Stops the update loop (place teardown).
function MusicDirector.stop()
	if stopLoop ~= nil then
		stopLoop()
		stopLoop = nil
	end
	started = false
end

return MusicDirector
