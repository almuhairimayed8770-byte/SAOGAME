--!strict
--[[
	MusicState: the adaptive music state machine and crossfade timing (section 15), pure.

	Four stems (ambient, explore, combat, boss) crossfade over 2 s on state changes. Combat starts
	on the first telegraph and ends 6 s after the last shatter. Below a quarter HP the music ducks
	6 dB and a heartbeat layer rises. A boss entrance cuts to silence for 1 s, then the boss stem.
	`duck(db, seconds)` lowers everything for the system voice and the death freeze.

	MusicDirector.luau owns the Sound instances and asks this module for the volumes each frame.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Combat = require(Shared.data.combat)
local Fx = require(Shared.data.fx)
local Sfx = require(Shared.data.sfx)

export type StateName = "Ambient" | "Explore" | "Combat" | "Boss"

export type Levels = {
	stems: { [string]: number }, -- stem name -> 0..1 gain (before the master duck)
	duckGain: number, -- 0..1 multiplier from the low-HP duck and explicit ducks
	heartbeat: number, -- 0..1 gain of the heartbeat layer
	silence: boolean, -- true during the boss-entrance silence
}

export type MusicState = {
	state: StateName,
	restState: StateName, -- the non-combat state combat returns to
	stemGains: { [string]: number },
	stemTargets: { [string]: number },
	lowHp: boolean,
	heartbeat: number,
	ducks: { { gain: number, until_: number } },
	silenceUntil: number,
	pendingState: StateName?,
	lastShatter: number?,
	combatArmed: boolean, -- a telegraph has been heard since the last combat end
	lastUpdate: number,
}

local MusicState = {}

local STEM_FOR_STATE: { [StateName]: string } = {
	Ambient = "ambient",
	Explore = "explore",
	Combat = "combat",
	Boss = "boss",
}

--- Volume multiplier for a dB attenuation (6 dB -> about 0.5).
function MusicState.dbToGain(db: number): number
	return 10 ^ (-db / 20) -- unit: decibels to amplitude
end

--- A fresh state machine at `now` seconds, starting in Ambient with that stem at full gain.
function MusicState.new(now: number, initial: StateName?): MusicState
	local state: StateName = initial or "Ambient"
	local gains: { [string]: number } = {}
	local targets: { [string]: number } = {}
	for _, stem in Sfx.music.stems do
		gains[stem] = 0
		targets[stem] = 0
	end
	gains[STEM_FOR_STATE[state]] = 1
	targets[STEM_FOR_STATE[state]] = 1
	return {
		state = state,
		restState = if state == "Combat" or state == "Boss" then "Explore" else state,
		stemGains = gains,
		stemTargets = targets,
		lowHp = false,
		heartbeat = 0,
		ducks = {},
		silenceUntil = -math.huge,
		pendingState = nil,
		lastShatter = nil,
		combatArmed = false,
		lastUpdate = now,
	}
end

local function retarget(self: MusicState, state: StateName)
	self.state = state
	for stem in self.stemTargets do
		self.stemTargets[stem] = 0
	end
	self.stemTargets[STEM_FOR_STATE[state]] = 1
	if state ~= "Combat" and state ~= "Boss" then
		self.restState = state
	end
end

--- Switches the state; the stems crossfade over the data's crossfade time from the next update.
function MusicState.setState(self: MusicState, state: StateName, now: number)
	if state == "Boss" then
		MusicState.bossEntrance(self, now)
		return
	end
	self.pendingState = nil
	if state ~= "Combat" then
		self.combatArmed = false
		self.lastShatter = nil
	end
	retarget(self, state)
end

--- A boss entrance: silence for the data's second, then the boss stem.
function MusicState.bossEntrance(self: MusicState, now: number)
	self.silenceUntil = now + Sfx.music.bossEntranceSilenceSeconds
	self.pendingState = "Boss"
	self.combatArmed = false
	self.lastShatter = nil
	-- Cut the current stems now; the boss stem rises when the silence ends.
	for stem in self.stemTargets do
		self.stemTargets[stem] = 0
		self.stemGains[stem] = 0
	end
end

--- Combat music starts on the first telegraph (not on aggro).
function MusicState.noteTelegraph(self: MusicState, now: number)
	self.combatArmed = true
	self.lastShatter = nil
	if self.state == "Boss" or self.pendingState == "Boss" then
		return
	end
	if self.state ~= "Combat" then
		retarget(self, "Combat")
	end
	self.lastUpdate = math.min(self.lastUpdate, now)
end

--- Every shatter restarts the 6 s countdown back to the rest state.
function MusicState.noteShatter(self: MusicState, now: number)
	if self.state == "Combat" then
		self.lastShatter = now
	end
end

--- Below a quarter HP: duck the music and raise the heartbeat; above it: release both.
function MusicState.setLowHp(self: MusicState, low: boolean)
	self.lowHp = low
end

--- Lowers everything by `db` for `seconds` (the system voice, the death freeze).
function MusicState.duck(self: MusicState, db: number, seconds: number, now: number)
	table.insert(self.ducks, { gain = MusicState.dbToGain(db), until_ = now + seconds })
end

--- Advances the crossfades to `now` and returns the gains to apply.
function MusicState.update(self: MusicState, now: number): Levels
	local dt = math.max(0, now - self.lastUpdate)
	self.lastUpdate = now

	-- Combat ends 6 s after the last shatter with no new telegraph since.
	if self.state == "Combat" and self.lastShatter ~= nil then
		if now - self.lastShatter >= Sfx.music.combatEndDelaySeconds then
			self.lastShatter = nil
			self.combatArmed = false
			retarget(self, self.restState)
		end
	end

	-- The boss silence ends: the boss stem starts rising.
	local silence = now < self.silenceUntil
	if not silence and self.pendingState ~= nil then
		local pending = self.pendingState :: StateName
		self.pendingState = nil
		retarget(self, pending)
	end

	-- Linear-in-time gain moves give an equal-power crossfade once squared below.
	local step = if Sfx.music.crossfadeSeconds > 0 then dt / Sfx.music.crossfadeSeconds else 1
	local stems: { [string]: number } = {}
	for stem, gain in self.stemGains do
		local target = self.stemTargets[stem] or 0
		local next = gain
		if target > gain then
			next = math.min(target, gain + step)
		elseif target < gain then
			next = math.max(target, gain - step)
		end
		self.stemGains[stem] = next
		-- Equal-power shape: sin(pi/2 * x) so two crossing stems sum to constant loudness.
		stems[stem] = math.sin(next * math.pi * 0.5)
	end

	-- Heartbeat layer and the low-HP duck.
	local ramp = Fx.audio.heartbeatRampSeconds
	local heartbeatStep = if ramp > 0 then dt / ramp else 1
	if self.lowHp then
		self.heartbeat = math.min(1, self.heartbeat + heartbeatStep)
	else
		self.heartbeat = math.max(0, self.heartbeat - heartbeatStep)
	end
	local duckGain = 1
	if self.lowHp then
		duckGain *= MusicState.dbToGain(Combat.lowHpMusicDuck)
	end
	for index = #self.ducks, 1, -1 do
		local duck = self.ducks[index]
		if now >= duck.until_ then
			table.remove(self.ducks, index)
		else
			duckGain = math.min(duckGain, duck.gain)
		end
	end

	return {
		stems = stems,
		duckGain = duckGain,
		heartbeat = self.heartbeat,
		silence = silence,
	}
end

--- The stem that carries a state.
function MusicState.stemFor(state: StateName): string
	return STEM_FOR_STATE[state]
end

return MusicState
