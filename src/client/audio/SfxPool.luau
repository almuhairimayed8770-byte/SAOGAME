--!strict
--[[
	SfxPool (section 15): pooled Sounds for every entry in sfx.luau, by "family.Name".

	`start()` creates the SoundGroups (Master with Music / SFX / UI / Voice under it) with the
	mix rules from sfx.luau and fx.luau. `play(name, position?)` takes a pooled Sound for the
	entry, pitches it inside its range, and plays it either in 3D (parented to a pooled anchored
	part at the position, roll-off from the data) or in 2D under SoundService. The same sound at
	the same spot inside the dedupe window plays once, so a hit heard through two reactions does
	not double. Placeholder entries (rbxassetid://0) go through the whole path but never call
	Play, so the console is not filled with load failures until the real ids arrive.

	Helpers: `hit(tier, position, surface)` (impact plus the metallic ring), `hitStopTick(tier)`,
	`parry(position)`, `shatter(position, boss)`, `footstep(model, surface?, weight?)` (surface
	from the Humanoid's FloorMaterial when the clip event carries none), `loop(name, gain)` for
	the heartbeat layer, `duck(db, seconds)` for the system voice.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Sfx = require(Shared.data.sfx)
local Engine = require(script.Parent.Parent.fx.Engine)
local MusicState = require(script.Parent.MusicState)

type Voice = {
	sound: Sound,
	busyUntil: number,
	emitter: BasePart?,
}

type Loop = {
	sound: Sound,
	entry: Sfx.Entry,
	playing: boolean,
}

local SfxPool = {}

local groups: { [string]: SoundGroup } = {}
local voices: { [string]: { Voice } } = {}
local loops: { [string]: Loop } = {}
local emitterPool: { BasePart } = {}
local emitterFolder: Instance? = nil
local recent: { { name: string, position: Vector3?, time: number } } = {}
local stats: { requested: number, played: number, deduped: number, placeholders: number } =
	{ requested = 0, played = 0, deduped = 0, placeholders = 0 }
local duckGeneration = 0
local started = false
local pitch = Random.new()

local function splitName(name: string): (string, string)
	local family, entryName = name:match("^([^%.]+)%.(.+)$")
	if family == nil or entryName == nil then
		error(("SfxPool: sound name '%s' is not 'family.Name'"):format(tostring(name)))
	end
	return family :: string, entryName :: string
end

local function groupFor(family: string): SoundGroup?
	return groups[Sfx.groupOf(family)]
end

local function ensureEmitterFolder(): Instance
	if emitterFolder == nil then
		emitterFolder = Engine.folder(workspace, Fx.audio.emitterFolderName)
	end
	return emitterFolder :: Instance
end

local function newEmitter(): BasePart
	local part = Instance.new("Part")
	part.Name = "SfxEmitter"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Parent = ensureEmitterFolder()
	return part
end

local function acquireEmitter(): BasePart
	local part = table.remove(emitterPool)
	if part == nil then
		part = newEmitter()
	end
	return part :: BasePart
end

local function releaseEmitter(part: BasePart)
	table.insert(emitterPool, part)
end

local function newSound(entry: Sfx.Entry, family: string, entryName: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = family .. "." .. entryName
	sound.SoundId = entry.id
	sound.Volume = entry.volume
	sound.RollOffMinDistance = Sfx.mix.rolloffMinDistance
	sound.RollOffMaxDistance = Sfx.mix.rolloffMaxDistance
	sound.PlayOnRemove = false
	local group = groupFor(family)
	if group ~= nil then
		sound.SoundGroup = group
	end
	return sound
end

local function isPlaying(sound: Sound): boolean
	local ok, playing = pcall(function()
		return (sound :: any).IsPlaying
	end)
	return ok and playing == true
end

local function acquireVoice(name: string, entry: Sfx.Entry, family: string, entryName: string): Voice
	local list = voices[name]
	if list == nil then
		list = {}
		voices[name] = list
	end
	local now = Engine.now()
	local oldest: Voice? = nil
	for _, voice in list do
		if voice.emitter == nil and now >= voice.busyUntil and not isPlaying(voice.sound) then
			return voice
		end
		if oldest == nil or voice.busyUntil < (oldest :: Voice).busyUntil then
			oldest = voice
		end
	end
	if #list < Sfx.mix.pooledVoicesPerEntry then
		local voice: Voice = { sound = newSound(entry, family, entryName), busyUntil = 0, emitter = nil }
		table.insert(list, voice)
		return voice
	end
	-- Every voice is busy: steal the one that has been playing longest.
	local victim = oldest :: Voice
	pcall(function()
		victim.sound:Stop()
	end)
	if victim.emitter ~= nil then
		releaseEmitter(victim.emitter :: BasePart)
		victim.emitter = nil
	end
	return victim
end

local function isDuplicate(name: string, position: Vector3?, now: number): boolean
	local window = Fx.audio.dedupeSeconds
	for index = #recent, 1, -1 do
		local item = recent[index]
		if now - item.time > window then
			table.remove(recent, index)
			continue
		end
		if item.name ~= name then
			continue
		end
		if position == nil or item.position == nil then
			if position == nil and item.position == nil then
				return true
			end
		elseif (position - (item.position :: Vector3)).Magnitude <= Fx.audio.dedupeDistance then
			return true
		end
	end
	return false
end

local function applyGroupVolume(name: string, volume: number)
	local group = groups[name]
	if group ~= nil then
		group.Volume = volume
	end
end

local function baseGroupVolume(name: string): number
	local base = Fx.audio.groupVolumes[name] or 1
	if name == "Music" and Engine.isTouch() then
		base *= MusicState.dbToGain(-Sfx.mix.mobileMusicOffsetDb)
	end
	return base
end

--- Creates the SoundGroups under SoundService with the section 15 mix levels.
function SfxPool.start()
	if started then
		return
	end
	started = true
	local master: SoundGroup? = nil
	for _, name in Sfx.groups do
		local group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = baseGroupVolume(name)
		groups[name] = group
		if name == "Master" then
			master = group
			pcall(function()
				group.Parent = SoundService
			end)
		end
	end
	for name, group in groups do
		if name ~= "Master" and master ~= nil then
			group.Parent = master
		end
	end
end

--- Plays "family.Name" at a world position (3D) or everywhere (2D). Returns the Sound, or nil
--- when the sound was deduped or is a placeholder.
function SfxPool.play(name: string, position: Vector3?): Sound?
	SfxPool.start()
	stats.requested += 1
	local family, entryName = splitName(name)
	local entry = Sfx.get(family, entryName)
	local now = Engine.now()
	if isDuplicate(name, position, now) then
		stats.deduped += 1
		return nil
	end
	table.insert(recent, { name = name, position = position, time = now })
	if entry.placeholder then
		stats.placeholders += 1
		return nil
	end
	local voice = acquireVoice(name, entry, family, entryName)
	local sound = voice.sound
	sound.Volume = entry.volume
	if entry.pitchRange ~= nil then
		local range = entry.pitchRange :: { number }
		sound.PlaybackSpeed = pitch:NextNumber(range[1], range[2])
	else
		sound.PlaybackSpeed = 1
	end
	if entry.spatial and position ~= nil then
		local emitter = acquireEmitter()
		emitter.CFrame = CFrame.new(position)
		voice.emitter = emitter
		sound.Parent = emitter
	else
		voice.emitter = nil
		pcall(function()
			sound.Parent = SoundService
		end)
	end
	voice.busyUntil = now + Fx.audio.maxSoundLength
	local ok = pcall(function()
		sound:Play()
	end)
	if ok then
		stats.played += 1
	end
	local function finish()
		if voice.emitter ~= nil then
			task.delay(Fx.audio.emitterReleaseDelay, function()
				if voice.emitter ~= nil then
					releaseEmitter(voice.emitter :: BasePart)
					voice.emitter = nil
				end
				voice.busyUntil = 0
			end)
		else
			voice.busyUntil = 0
		end
	end
	local connected = pcall(function()
		sound.Ended:Once(finish)
	end)
	if not connected then
		task.delay(Fx.audio.maxSoundLength, finish)
	end
	return sound
end

--- A looped layer (the heartbeat) at `gain` 0..1 of its data volume; 0 stops it.
function SfxPool.loop(name: string, gain: number)
	SfxPool.start()
	local loop = loops[name]
	if loop == nil then
		local family, entryName = splitName(name)
		local entry = Sfx.get(family, entryName)
		local sound = newSound(entry, family, entryName)
		sound.Looped = true
		pcall(function()
			sound.Parent = SoundService
		end)
		loop = { sound = sound, entry = entry, playing = false }
		loops[name] = loop
	end
	local resolved = loop :: Loop
	local above = MusicState.dbToGain(-Sfx.mix.heartbeatOverAllDb)
	resolved.sound.Volume = resolved.entry.volume * math.clamp(gain, 0, 1) * above
	local shouldPlay = gain > Fx.audio.stemFadeFloor and not resolved.entry.placeholder
	if shouldPlay and not resolved.playing then
		resolved.playing = pcall(function()
			resolved.sound:Play()
		end)
	elseif not shouldPlay and resolved.playing then
		resolved.playing = false
		pcall(function()
			resolved.sound:Stop()
		end)
	end
end

--- The impact for a hit-stop tier plus the short metallic ring (section 15).
function SfxPool.hit(tier: string, position: Vector3?, surface: string?)
	local impact = "impact." .. (surface or "Flesh")
	if tier == "Kill" then
		impact = "impact.Kill"
	elseif tier == "Final" then
		impact = "impact.FinalHit"
	end
	SfxPool.play(impact, position)
	SfxPool.play("impact.Ring", position)
end

--- The hit-stop tick for a tier (2D; it is the player's own frame freezing).
function SfxPool.hitStopTick(tier: string)
	local entry = Sfx.families.hitStopTick.entries[tier]
	SfxPool.play("hitStopTick." .. (if entry ~= nil then tier else "Normal"))
end

--- The parry: a bright steel clash with its ring.
function SfxPool.parry(position: Vector3?)
	SfxPool.play("guard.Parry", position)
end

--- The shatter: the glass crack then the rising chime; bosses get the slow crack and the boom.
function SfxPool.shatter(position: Vector3?, boss: boolean?)
	local sounds = Fx.shatter.sounds
	if boss then
		SfxPool.play(sounds.bossCrack, position)
		SfxPool.play(sounds.bossBoom)
	else
		SfxPool.play(sounds.crack, position)
	end
	task.delay(Fx.shatter.chimeDelay, function()
		SfxPool.play(sounds.chime, position)
	end)
end

--- The footstep surface for a character: the event's surface, else the Humanoid's floor material.
function SfxPool.surfaceOf(model: Instance?, surface: string?): string
	if surface ~= nil and Sfx.families.footsteps.entries[surface .. "Light"] ~= nil then
		return surface
	end
	if model ~= nil then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil then
			local ok, material = pcall(function()
				return (humanoid :: any).FloorMaterial
			end)
			if ok and material ~= nil then
				local mapped = Fx.audio.materialSurface[(material :: any).Name]
				if mapped ~= nil then
					return mapped
				end
			end
		end
	end
	return Fx.audio.defaultSurface
end

--- A footstep for a character by surface and weight (Light / Armored from the Armored attribute).
function SfxPool.footstep(model: Instance?, surface: string?, weight: string?)
	local resolvedSurface = SfxPool.surfaceOf(model, surface)
	local resolvedWeight = weight
	if resolvedWeight == nil then
		local armored = if model ~= nil then model:GetAttribute(Fx.audio.armoredAttribute) else nil
		resolvedWeight = if armored == true then "Armored" else "Light"
	end
	SfxPool.play("footsteps." .. resolvedSurface .. resolvedWeight, Engine.modelPosition(model))
end

--- Sets a group's slider (0..1 of its data level): "Master" | "Music" | "SFX" | "UI" | "Voice".
function SfxPool.setGroupVolume(name: string, fraction: number)
	applyGroupVolume(name, baseGroupVolume(name) * math.clamp(fraction, 0, 1))
end

--- Ducks Music, SFX and UI by `db` for `seconds` (the system voice ducks everything by 8 dB).
function SfxPool.duck(db: number, seconds: number)
	duckGeneration += 1
	local generation = duckGeneration
	local gain = MusicState.dbToGain(db)
	for _, name in { "Music", "SFX", "UI" } do
		applyGroupVolume(name, baseGroupVolume(name) * gain)
	end
	task.delay(seconds, function()
		if generation ~= duckGeneration then
			return
		end
		for _, name in { "Music", "SFX", "UI" } do
			applyGroupVolume(name, baseGroupVolume(name))
		end
	end)
end

--- The SoundGroup by name once started (MusicDirector routes its stems through "Music").
function SfxPool.group(name: string): SoundGroup?
	return groups[name]
end

--- Counters for the smoke test and the profiler.
function SfxPool.stats(): { requested: number, played: number, deduped: number, placeholders: number }
	return table.clone(stats)
end

return SfxPool
