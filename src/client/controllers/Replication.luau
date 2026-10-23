--!strict
--[[
	Replication: every server-to-client remote becomes a client reaction (ARCHITECTURE "Client
	reactions to remotes"): clips on other rigs, telegraphs, hit-stop, digits, highlight flashes,
	an enemy's additive directional flinch, the parry spark burst, camera nudge and shake, the HP
	flash, the death freeze (Music, SFX and UI ducked) and shatter, the death system line after the
	shatter, other system lines, the Switch ring. A Stagger, Break, guard break or death hides the
	wind-up telegraph it interrupted.

	The impact director (fx/Impact.luau) owns every hit, parry, block and guard sound and the reel
	accents: each HitConfirmed becomes one Impact.hit(info); a guard break or raise, a remote dodge
	(ActionStarted of a "/Dodge" clip), an Art activation (the clip's ActivationHold) and a shatter
	call it too. Replication keeps the hit-stop tick (2D, for the people in the hit; a hit that
	breaks a player's guard ticks Final; one per sweep, a stronger tier's taking over), the
	digits, the reactions, the flinch, one camera nudge per sweep, the shake and the HP flash. The
	blow that breaks a player's guard reaches the director as a guarded hit: StateChanged
	GuardBroken already played the break's crack, and the blow is the block under it. A death
	waits the kill's hit-stop (Moments.deathDuckDelay) before the silence, so the kill is heard;
	the shatter and the system line move by the same lead, and an enemy's death vocal plays at
	once (the silence chops it), once for one sweep's deaths of the same voice. The newest death
	owns the silence: one inside another's silence brings the sound back at once for its kill, and
	an older death's shatter never ends a newer silence (one sweep's deaths share theirs).

	It also routes every rig's clip events (trail, smear,
	activation light, footsteps, clip sounds) to the FX and audio packages, so trails, smears and
	swings look and sound the same on the local fighter and on everyone else. A remote clip that
	ActionStarted starts late (the network catch-up jumps into it) still sounds the clip sounds it
	jumped over, each from where it would be by now (SfxPool.playLate): a swing whose whoosh starts
	on frame 0 keeps it. An Art's ActivationHold it jumped over still lights, chimes and ends its
	riser on the first damage frame while that frame is ahead. A TrailOn's
	`data.kind` ("Art" | "Basic") picks the trail kind for the rest of that clip's trail events.

	Every tracked rig this client does not own (other players, enemies) gets a locomotion driver
	(Locomotion.attach) when it is watched, so it walks instead of sliding on its idle pose; an
	enemy's idle and walk start at its own id's phase (Locomotion.idlePhase, D-123). The
	local rig's locomotion belongs to the character controller (Locomotion.new), so watch skips it:
	by id once the tracker has resolved it, by the character model before that, and a driver that
	slipped onto the local rig in between is dropped when the tracker's `localChanged` fires.
	Unwatch releases the driver, the trail, the telegraph highlight, the smear and the reaction clip.

	A remote player's driver sees the Drawn attribute through SheathState.riseFilter: a rise counts
	choreo.luau sheath.remoteDrawDelay late. The attribute can land a frame or two before the
	unreliable ActionStarted of the attack that set it; with the delay that attack draw-cuts, and
	no Draw or drawn walk set flashes in first. A lock-on's Draw starts that much later.

	Nothing here decides damage; a rejected hit is simply a `rejected` Signal that the character
	controller turns into a cancelled prediction (section 17).

	Dependencies come in through `Replication.bind(deps)` so Lune tests dispatch payloads at fake
	modules; `Replication.start()` binds the real ones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Combat = require(Shared.data.combat)
local ChoreoData = require(Shared.data.choreo)
local Fx = require(Shared.data.fx)
local UI = require(Shared.data.ui)
local Moments = require(Shared.data.moments)
local Sfx = require(Shared.data.sfx)
local Enemies = require(Shared.data.enemies)
local Signal = require(Shared.util.Signal)
local ActionLogic = require(script.Parent.ActionLogic)
local Siblings = require(script.Parent.Siblings)

local SheathState, hasSheathState = Siblings.load(script.Parent.Parent, "choreo.SheathState")

export type Deps = {
	net: { on: (name: string, handler: (payload: any) -> ()) -> () },
	entities: any, -- EntityTracker-like: get(id), all(), added, removed
	localId: () -> number?, -- never yields
	localCharacter: (() -> Instance?)?, -- the local player's character model when it exists; never yields
	-- Locomotion-like: attach(animator, model, deps?) -> driver, destroy(driver), humanoidTracker?,
	-- idlePhase?(id) -> 0 .. 1
	locomotion: any,
	choreo: any, -- Choreo.get(model) -> animator
	clipLibrary: any, -- ClipLibrary.has(clipId)
	trails: any,
	smear: any,
	shatter: any,
	sparks: any, -- Sparks-like: parry(position)
	telegraphs: any,
	outline: any,
	switchRing: any,
	digits: any,
	hud: any,
	systemLine: any,
	sfx: any, -- SfxPool-like: play(name, position?), playLate(name, lateBy, position?), cue(name, position?, lateBy?), footstep(model, surface?), duck(db, seconds)
	-- Impact-like: hit(info) -> string, ownsHighlight(info) -> boolean, hiddenSeconds() -> number,
	-- activation(model, clipId, token, isLocal, speed?, lateBy?), dodge(model, isLocal, lateBy?),
	-- guardBreak(model, isLocal), guardRaise(model, isLocal), shatterCue(boss, heavy) -> string,
	-- death(model?, position, boss, heavy)
	impact: any,
	camera: any,
	weaponCategory: (record: any) -> string,
	trailToken: (record: any) -> string,
	positionOf: (model: Instance) -> Vector3?,
	schedule: (seconds: number, fn: () -> ()) -> (),
	now: (() -> number)?, -- monotonic seconds (one camera nudge per sweep); os.clock when nil
}

-- Sound names (family.Name in sfx.luau) the reactions play; Replication.spec checks each resolves.
-- The hit, parry, block and guard sounds are the impact director's cues (moments.luau). An
-- enemy's death vocal is Sfx.vocalName(archetype, "Death"): in Phase 0 "enemy.ChargerDeath" and
-- "enemy.BruteDeath".
local SOUNDS = {
	hitStop = { Normal = "hitStopTick.Normal", Final = "hitStopTick.Final", Kill = "hitStopTick.Kill" },
	switchPrompt = "ui.SwitchPrompt",
	systemLine = "ui.SystemLine",
}

-- StateChanged states that cancel an enemy's strike (Brain.interrupt) or end the fighter: the
-- wind-up telegraph comes down with them instead of glowing over a kneeling rig or a corpse.
local TELEGRAPH_CANCEL: { [string]: boolean } = { Stagger = true, Break = true, GuardBroken = true, Dead = true }

-- Trail kinds a clip's TrailOn may name in data.kind.
local TRAIL_KINDS: { [string]: boolean } = { Art = true, Basic = true }

local Replication = {}

--- The sound names the reactions play (tests check them against sfx.luau).
Replication.SOUNDS = SOUNDS

--- Fires (action, reason, clientTime) when the server rejects one of the local player's requests.
Replication.rejected = Signal.new() :: Signal.Signal<string, string, number?>
--- Fires (record, clipId, event) for every clip event on every tracked rig.
Replication.clipEvent = Signal.new() :: Signal.Signal<any, string, any>
--- Fires (record, state, duration?, direction?) on every StateChanged.
Replication.stateChanged = Signal.new() :: Signal.Signal<any, string, number?, string?>
--- Fires the raw HitConfirmed payload after the reactions ran (the character controller tracks parries).
Replication.hit = Signal.new() :: Signal.Signal<any>

local deps: Deps? = nil
local stateClips: { [number]: any } = {} -- entity id -> handle of the reaction clip playing
local watched: { [number]: { Disconnect: (self: any) -> () }? } = {}
local drivers: { [number]: any } = {} -- entity id -> locomotion driver on a rig this client does not own
-- entity id -> the trail kind the playing clip's TrailOn named; HitWindowOpen / Close, TrailOff and
-- PostMotionStart carry no kind, so they reuse it while the same clip is playing.
local trailKinds: { [number]: { clipId: string, kind: string } } = {}
-- enemy id -> the open Switch window on it and who opened it (that blade flashes on the Switch).
local switchOpeners: { [any]: { openerId: any } } = {}
-- entity id -> the clip ActionStarted played on it and its speed (the activation riser's timing).
local clipSpeeds: { [any]: { clipId: string, speed: number? } } = {}
-- Per attacker (its entity id, NO_ATTACKER when the payload names none): when its sweep's camera
-- nudge was given (a sweep's hits confirm within a few frames and nudge once), and its sweep's
-- hit-stop tick (when the sweep began and the strongest tier it ticked). A trade is two sweeps.
local NO_ATTACKER = {}
local lastNudges: { [any]: number } = {}
local lastTicks: { [any]: { at: number, rank: number } } = {}
-- death vocal name -> when it last played: one sweep's deaths of the same voice scream once.
local deathVocals: { [string]: number } = {}
-- The newest death owns the silence: how many deaths came so far, and when the silence a death
-- started ends (nil while none holds).
local deathCount = 0
local silenceEnd: number? = nil

local function dependencies(): Deps
	if deps == nil then
		error("Replication: call bind() or start() first")
	end
	return deps :: Deps
end

local function toVector(v: { number }?): Vector3
	if v == nil then
		return Vector3.zero
	end
	local x, y, z = table.unpack(v)
	return Vector3.new(x, y, z)
end

local function animatorOf(record: any): any
	return dependencies().choreo.get(record.model)
end

local function clock(): number
	local fn = dependencies().now
	return if fn ~= nil then fn() else os.clock()
end

-- A player's or an Elite's death shatters heavier than a mob's (D-079). An Elite is a
-- record the tracker marks elite (a spawn-time Elite variant) or a def marked elite in enemies.luau.
local function heavyDeath(record: any, isLocal: boolean): boolean
	if isLocal then
		return true
	end
	if record == nil then
		return false
	end
	if record.kind == "Player" or record.elite == true then
		return true
	end
	local def = Enemies.byId(record.defId or "")
	return def ~= nil and def.elite == true
end

-- An enemy's death vocal at the rig (a placeholder entry plays nothing; an unknown def nothing).
local function deathVocal(record: any, position: Vector3)
	if record.kind ~= "Enemy" then
		return
	end
	local def = Enemies.byId(record.defId or "")
	if def == nil then
		return
	end
	local ok, name = pcall(Sfx.vocalName, def.archetype, "Death")
	if not ok then
		return
	end
	local at = clock()
	local last = deathVocals[name]
	if last ~= nil and at - last <= Moments.sweep.mergeSeconds then
		return -- the same sweep's death: its scream is already playing
	end
	deathVocals[name] = at
	dependencies().sfx.play(name, position)
end

-- True when an attacker's sweep's hit plays its hit-stop tick: the sweep's first, or a stronger
-- tier than it ticked (a kill among final hits is heard; a final hit after the kill adds nothing).
local function ticksInSweep(tier: string, at: number, attacker: any): boolean
	local rank = (Combat.hitStopFrames :: { [string]: number })[tier] or 0
	local sweep = lastTicks[attacker]
	if sweep == nil or at - sweep.at > Moments.sweep.mergeSeconds then
		lastTicks[attacker] = { at = at, rank = rank }
		return true
	end
	if rank > sweep.rank then
		sweep.rank = rank
		return true
	end
	return false
end

-- An Art's ActivationHold a late start jumped over while its first damage frame is still ahead:
-- the activation light, the chime from where it would be by now, and the riser still ending on
-- that frame. A hold whose window the start jumped over too is over: nothing replays for it.
local function replayHold(record: any, clip: any, clipId: string, holdTime: number, clipTime: number, speed: number)
	for _, event in clip.events do
		if event.kind == "HitWindowOpen" and event.time >= holdTime and event.time <= clipTime then
			return
		end
	end
	local d = dependencies()
	local token = d.trailToken(record)
	local late = (clipTime - holdTime) / speed
	d.trails.activationLight(record.model, true, token)
	d.sfx.playLate("artChime." .. token, late, d.positionOf(record.model))
	d.impact.activation(record.model, clipId, token, false, speed, late)
end

-- Real seconds a Mixer handle started into its clip (the network catch-up), or nil when it started
-- on time or has no clip clock (an engine Animation).
local function lateOf(handle: any): number?
	if typeof(handle) ~= "table" or typeof(handle.time) ~= "number" or handle.time <= 0 then
		return nil
	end
	local speed = if typeof(handle.speed) == "number" and handle.speed > 0 then handle.speed else 1
	return handle.time / speed
end

-- The clip sounds a late start jumped over (the network catch-up starts the clip `handle.time`
-- in; the Mixer's first step fires the events from there on), each from where it would be by now,
-- and an Art's hold it jumped over (replayHold).
local function replaySkipped(record: any, handle: any, clipId: string)
	if typeof(handle) ~= "table" or typeof(handle.time) ~= "number" or handle.time <= 0 then
		return
	end
	local clip = handle.clip
	if typeof(clip) ~= "table" or typeof(clip.events) ~= "table" or clip.loop == true then
		return
	end
	local d = dependencies()
	local speed = if typeof(handle.speed) == "number" and handle.speed > 0 then handle.speed else 1
	for _, event in clip.events do
		if (event.kind == "Sfx" or event.kind == "Voice") and event.time < handle.time then
			local data = event.data
			if typeof(data) == "table" and typeof(data.name) == "string" then
				d.sfx.playLate(data.name, (handle.time - event.time) / speed, d.positionOf(record.model))
			end
		elseif event.kind == "ActivationHold" and event.time < handle.time then
			replayHold(record, clip, clipId, event.time, handle.time, speed)
		end
	end
end

local function reactionClip(record: any, name: string): string?
	local d = dependencies()
	local id = ActionLogic.clipId(record.kind, record.rig, d.weaponCategory(record), name)
	if d.clipLibrary.has(id) == true then
		return id
	end
	return nil
end

local function playReaction(record: any, name: string): boolean
	local id = reactionClip(record, name)
	if id == nil then
		return false
	end
	local previous = stateClips[record.id]
	local animator = animatorOf(record)
	if previous ~= nil then
		animator:stop(previous, Combat.locomotionBlendOut)
	end
	stateClips[record.id] = animator:play(id)
	return true
end

local function stopReaction(record: any)
	local previous = stateClips[record.id]
	if previous ~= nil then
		animatorOf(record):stop(previous, Combat.locomotionBlendOut)
		stateClips[record.id] = nil
	end
end

-- Which reaction clip a StateChanged plays, or nil when the owner handles the state.
local function stateClipName(state: string, direction: string?, isLocal: boolean): string?
	if state == "Stagger" then
		return if direction ~= nil then "Flinch" .. direction else "Stagger"
	elseif state == "GuardBroken" then
		return "GuardBreak"
	elseif state == "Break" then
		return "Break"
	elseif state == "Guard" and not isLocal then
		return "Guard"
	end
	return nil
end
Replication.stateClipName = stateClipName

local handlers: { [string]: (payload: any) -> () } = {}

function handlers.ActionStarted(payload: any)
	local d = dependencies()
	if payload.entityId == d.localId() then
		return
	end
	local record = d.entities.get(payload.entityId)
	if record == nil then
		return
	end
	local handle = animatorOf(record):play(payload.clipId, { serverTime = payload.serverTime, speed = payload.speed })
	clipSpeeds[record.id] = { clipId = payload.clipId, speed = payload.speed }
	replaySkipped(record, handle, payload.clipId)
	if string.find(payload.clipId, "/Dodge", 1, true) then
		-- A remote dodge: its whoosh in range (the local dodge is the character controller's). A
		-- dodge the catch-up started late runs its cue that much late too, so the landing keeps the
		-- clip's clock and never sounds after the clip's own footstep.
		d.impact.dodge(record.model, false, lateOf(handle))
	end
end

function handlers.Telegraph(payload: any)
	local d = dependencies()
	local record = d.entities.get(payload.entityId)
	if record == nil then
		return
	end
	d.telegraphs.show(
		record.model,
		payload.kind,
		payload.windUp,
		toVector(payload.origin),
		toVector(payload.facing),
		payload.shape
	)
end

function handlers.HitConfirmed(payload: any)
	local d = dependencies()
	local attacker = d.entities.get(payload.attackerId)
	local target = d.entities.get(payload.targetId)
	local localId = d.localId()
	local tier = payload.hitStop
	local frames = Combat.hitStopFrames[tier] or Combat.hitStopFrames.Normal
	local position = toVector(payload.position)
	local involved = payload.attackerId == localId or payload.targetId == localId

	if attacker ~= nil then
		animatorOf(attacker):hitStop(frames)
	end
	if target ~= nil and target ~= attacker then
		animatorOf(target):hitStop(frames)
	end

	local window = if payload.isSwitch then switchOpeners[payload.targetId] else nil
	local opener = if window ~= nil then d.entities.get(window.openerId) else nil
	-- The blow that breaks a player's guard (an enemy's Break is its gauge, not a guard).
	local breaksGuard = payload.broke == true and not payload.killed and target ~= nil and target.kind == "Player"
	local info = {
		tier = if Combat.hitStopFrames[tier] ~= nil then tier else "Normal",
		position = position,
		attacker = if attacker ~= nil then attacker.model else nil,
		target = if target ~= nil then target.model else nil,
		involved = involved,
		localAttacker = payload.attackerId == localId,
		trailToken = if attacker ~= nil then d.trailToken(attacker) else "SystemWhite",
		parried = payload.parried == true,
		-- The guard break's crack already played (StateChanged GuardBroken): its blow is the block.
		guarded = payload.guarded == true or breaksGuard,
		crit = payload.crit == true,
		isSwitch = payload.isSwitch == true,
		killed = payload.killed == true,
		-- An Art's hit carries its artId; a player's hit without one is a basic swing; an enemy's
		-- strike is neither.
		art = if payload.artId ~= nil then true elseif attacker ~= nil and attacker.kind == "Player" then false else nil,
		partner = if opener ~= nil then opener.model else nil,
	}
	if payload.isSwitch then
		switchOpeners[payload.targetId] = nil
	end

	if payload.parried then
		-- A perfect parry: the director's glint, inverted frame and ring; the spark burst and the
		-- parrier's blade flash wait while that frame hides the world; a short shake; no number.
		d.impact.hit(info)
		local hidden = d.impact.hiddenSeconds()
		local wait = if typeof(hidden) == "number" and hidden > 0 then hidden else 0
		local function accents()
			if target ~= nil then
				d.trails.flashWhite(target.model, Combat.highlightFlashFrames)
			end
			d.sparks.parry(position)
		end
		if wait > 0 then
			d.schedule(wait, accents)
		else
			accents()
		end
		if target ~= nil then
			playReaction(target, "Parry")
		end
		if involved then
			d.camera.shake("Normal")
		end
		Replication.hit:Fire(payload)
		return
	end

	local kind = "Normal"
	if payload.targetId == localId then
		kind = "Taken"
	elseif payload.isSwitch then
		kind = "Switch"
	elseif payload.crit then
		kind = "Crit"
	end
	if payload.damage > 0 then
		d.digits.show(position, payload.damage, kind)
	end
	if target ~= nil then
		if d.impact.ownsHighlight(info) ~= true and not breaksGuard then
			-- FinalHit and Kill flash it themselves, white, after the impact frames. The blow that
			-- breaks a guard leaves the guard break's red fill (StateChanged GuardBroken) showing.
			d.outline.flash(target.model, "SystemWhite", Combat.highlightFlashFrames)
		end
		if payload.guarded then
			playReaction(target, "GuardHit")
		end
		local direction = payload.staggerDirection
		if target.kind == "Enemy" and direction ~= nil and not payload.killed and not payload.broke then
			-- The directional hit flinch rides the Additive layer, so it plays over the idle, the walk,
			-- an attack or a Break kneel without replacing the reaction clip.
			local flinch = reactionClip(target, "Flinch" .. direction)
			if flinch ~= nil then
				animatorOf(target):play(flinch)
			end
		end
	end
	if involved then
		-- One nudge per sweep: twelve targets confirmed in one frame must not push twelve times.
		local at = clock()
		local sweepKey = if payload.attackerId ~= nil then payload.attackerId else NO_ATTACKER
		local nudgedAt = lastNudges[sweepKey]
		if nudgedAt == nil or at - nudgedAt > Moments.sweep.mergeSeconds then
			lastNudges[sweepKey] = at
			d.camera.nudge(position, Combat.cameraNudgeStuds)
		end
		d.camera.shake(tier)
		-- The hit that breaks a player's guard ticks Final (the server keeps its hit-stop tier).
		local tick = if breaksGuard and tier == "Normal" then "Final" else tier
		if SOUNDS.hitStop[tick] == nil then
			tick = "Normal"
		end
		if ticksInSweep(tick, at, sweepKey) then
			d.sfx.play(SOUNDS.hitStop[tick])
		end
	end
	if payload.targetId == localId and payload.damage > 0 then
		d.hud.flashHp()
	end
	-- The hit's cue (block, basic, crit, final, kill, Switch land), glint, crescent, line, frames.
	d.impact.hit(info)
	Replication.hit:Fire(payload)
end

function handlers.StateChanged(payload: any)
	local d = dependencies()
	local record = d.entities.get(payload.entityId)
	if record == nil then
		return
	end
	local isLocal = payload.entityId == d.localId()
	if TELEGRAPH_CANCEL[payload.state] == true then
		-- No strike follows an interrupted wind-up (a no-op when the rig shows no telegraph).
		d.telegraphs.hide(record.model)
	end
	local clipName = stateClipName(payload.state, payload.direction, isLocal)
	if clipName ~= nil then
		playReaction(record, clipName)
	elseif payload.state ~= "Dead" then
		stopReaction(record)
	end
	if payload.state == "GuardBroken" then
		d.outline.flash(record.model, "HPRed", Combat.highlightFlashFrames)
		d.impact.guardBreak(record.model, isLocal)
	elseif payload.state == "Guard" and not isLocal then
		-- The local guard's raise is predicted on the key press, with its pose.
		d.impact.guardRaise(record.model, false)
	end
	Replication.stateChanged:Fire(record, payload.state, payload.duration, payload.direction)
end

function handlers.EntityDied(payload: any)
	local d = dependencies()
	local record = d.entities.get(payload.entityId)
	local position = toVector(payload.position)
	local isLocal = payload.entityId == d.localId()
	local boss = payload.shatter == "Boss"
	local heavy = heavyDeath(record, isLocal)
	deathCount += 1
	local death = deathCount
	local diedAt = clock()
	if silenceEnd ~= nil and diedAt < (silenceEnd :: number) then
		-- Another death's silence holds: this kill is the new moment and is heard at full; its own
		-- silence follows after its hit-stop.
		silenceEnd = nil
		d.sfx.duck(0, 0)
	end
	if record ~= nil then
		local animator = animatorOf(record)
		playReaction(record, "DeathFreeze")
		animator:setTimeScale(0)
		d.trails.setActive(record.model, false, "Art")
		-- The scream starts with the kill; the silence after the hit-stop chops its tail.
		deathVocal(record, position)
	end
	-- Freeze and silence (section 6, section 11): Music, SFX and UI duck, not only the music. The
	-- silence waits the kill's hit-stop so the kill's crack and impact frames are heard first; the
	-- shatter and the line move by the same lead. Only the newest death ducks and restores: a
	-- death after this one brings its own silence, which this one's shatter never cuts short.
	local lead = Moments.deathDuckDelay()
	d.schedule(lead, function()
		if death ~= deathCount then
			return
		end
		silenceEnd = clock() + Combat.deathFreeze
		d.sfx.duck(Combat.deathDuckDb, Combat.deathFreeze)
	end)
	local named = d.impact.shatterCue(boss, heavy)
	local cue: string = if typeof(named) == "string"
		then named
		elseif boss then Sfx.shatterCues.boss
		else Sfx.shatterCues.normal
	d.schedule(lead + Combat.deathFreeze, function()
		-- The silence ends as the newest death's shatter cracks: a duck of 0 dB restores full volume
		-- and makes any pending restore stale. An older death's shatter inside a newer silence stays
		-- in it (the newest shatter is the one the silence leads to), unless that silence ends within
		-- a sweep's window anyway (one sweep's deaths are one moment and crack together).
		local ending = silenceEnd == nil or clock() >= (silenceEnd :: number) - Moments.sweep.mergeSeconds
		if death == deathCount or ending then
			silenceEnd = nil
			d.sfx.duck(0, 0)
		end
		if record ~= nil then
			-- Shatter.play plays the shatter cue itself (SfxPool.shatter) at the rig.
			d.shatter.play(record.model, payload.shatter, cue)
		else
			-- No rig left to shatter: the shatter cue still sounds where the server said it died.
			d.sfx.cue(cue, position)
		end
		d.impact.death(if record ~= nil then record.model else nil, position, boss, heavy)
	end)
	if isLocal or (record ~= nil and record.kind == "Player") then
		-- The line follows the shatter: the dying player reads their own line, everyone else the name.
		local shatterTime = if boss then Fx.shatter.bossDuration else Fx.shatter.duration
		local text = if isLocal then UI.systemLine.deathSelf else UI.systemLine.deathOther:format(payload.name)
		d.schedule(lead + Combat.deathFreeze + shatterTime, function()
			d.systemLine.show(text, "SystemWhite", SOUNDS.systemLine)
		end)
	end
end

function handlers.ActionRejected(payload: any)
	Replication.rejected:Fire(payload.action, payload.reason, payload.clientTime)
end

function handlers.SystemLine(payload: any)
	dependencies().systemLine.show(payload.text, payload.token, payload.chime)
end

function handlers.SwitchWindow(payload: any)
	local d = dependencies()
	local position = toVector(payload.position)
	d.switchRing.show(position, payload.duration)
	-- The opener's blade flashes with the partner's when the Switch lands inside the window.
	local window = { openerId = payload.openerId }
	switchOpeners[payload.entityId] = window
	d.schedule(payload.duration, function()
		-- Only this window closes: a newer one on the same enemy keeps its opener.
		if switchOpeners[payload.entityId] == window then
			switchOpeners[payload.entityId] = nil
		end
	end)
	if payload.openerId ~= d.localId() then
		if typeof(rawget(d.hud, "showSwitchPrompt")) == "function" then
			-- SWITCH sits above the enemy (section 14) when its rig is known.
			local record = d.entities.get(payload.entityId)
			d.hud.showSwitchPrompt(payload.duration, if record ~= nil then record.model else nil)
		else
			d.systemLine.show("SWITCH", "SystemCyan", SOUNDS.switchPrompt)
		end
		d.sfx.play(SOUNDS.switchPrompt)
	end
end

Replication.handlers = handlers

-- The trail kind for a clip event: the kind the event names (remembered for the rest of the
-- clip), else what this clip's TrailOn named, else the clip id ("/Basic" swings are Basic).
local function resolveTrailKind(record: any, clipId: string, event: any): string
	local data = event.data
	if typeof(data) == "table" and typeof(data.kind) == "string" and TRAIL_KINDS[data.kind] == true then
		trailKinds[record.id] = { clipId = clipId, kind = data.kind }
		return data.kind
	end
	local remembered = trailKinds[record.id]
	if remembered ~= nil and remembered.clipId == clipId then
		return remembered.kind
	end
	return if string.find(clipId, "/Basic", 1, true) then "Basic" else "Art"
end

--- Routes one clip event on a rig to the FX and audio packages (trails, smear, activation light,
--- footsteps, clip sounds).
function Replication.routeClipEvent(record: any, clipId: string, event: any)
	local d = dependencies()
	local model = record.model
	local kind = event.kind
	if kind == "HitWindowOpen" or kind == "TrailOn" then
		d.trails.setActive(model, true, resolveTrailKind(record, clipId, event))
		if kind == "HitWindowOpen" then
			d.trails.activationLight(model, false, d.trailToken(record))
		end
	elseif kind == "HitWindowClose" or kind == "TrailOff" then
		d.trails.setActive(model, false, resolveTrailKind(record, clipId, event))
	elseif kind == "SmearOn" then
		-- The smear frames run the trail at full width (section 10 beat 3) on top of any Art or
		-- Basic kind; Trails keeps the trail lit while any kind is on.
		d.smear.apply(model, true, if event.data ~= nil then event.data.axis else nil)
		d.trails.setActive(model, true, "Smear")
	elseif kind == "SmearOff" then
		d.smear.apply(model, false, if event.data ~= nil then event.data.axis else nil)
		d.trails.setActive(model, false, "Smear")
	elseif kind == "Sfx" or kind == "Voice" then
		-- data.name is a sfx.luau "family.Name"; SfxPool resolves it and skips placeholders.
		local data = event.data
		if typeof(data) == "table" and typeof(data.name) == "string" then
			d.sfx.play(data.name, d.positionOf(model))
		end
	elseif kind == "ActivationHold" then
		local token = d.trailToken(record)
		local isLocal = record.id == d.localId()
		d.trails.activationLight(model, true, token)
		d.sfx.play("artChime." .. token, d.positionOf(model))
		if isLocal then
			d.camera.fovKick()
		end
		-- The riser into the first damage frame (remote), the wind-up contour (local).
		local entry = clipSpeeds[record.id]
		local speed = if entry ~= nil and entry.clipId == clipId then entry.speed else nil
		d.impact.activation(model, clipId, token, isLocal, speed)
	elseif kind == "PostMotionStart" then
		d.trails.activationLight(model, false, d.trailToken(record))
		d.trails.setActive(model, false, resolveTrailKind(record, clipId, event))
		trailKinds[record.id] = nil
	elseif kind == "Footstep" then
		-- SfxPool resolves the surface from the event or the Humanoid's floor, and the weight
		-- from the armor attribute.
		d.sfx.footstep(model, if event.data ~= nil then event.data.surface else nil)
	end
	Replication.clipEvent:Fire(record, clipId, event)
end

-- True for the local player's own rig, whose locomotion the character controller drives. The id
-- settles it once the tracker knows it; before that (EntityTracker fires `added` before it
-- resolves the local id) the character model does.
local function isLocalRecord(record: any): boolean
	local d = dependencies()
	if record.id == d.localId() then
		return true
	end
	local localCharacter = d.localCharacter
	if localCharacter ~= nil then
		local character = localCharacter()
		return character ~= nil and character == record.model
	end
	return false
end

local function destroyDriver(id: number)
	local driver = drivers[id]
	if driver == nil then
		return
	end
	drivers[id] = nil
	dependencies().locomotion.destroy(driver)
end

-- The driver options for a remote player's rig: the default Humanoid tracker, fed the driver's
-- Drawn attribute through a rise filter (sheath.remoteDrawDelay). `driverOf` gives the driver
-- once attach has returned it. Nil (the default tracker) when the locomotion package has none.
local function remotePlayerOptions(locomotion: any, model: Instance, driverOf: () -> any): any
	if not hasSheathState or typeof(locomotion.humanoidTracker) ~= "function" then
		return nil
	end
	local filter = SheathState.riseFilter(ChoreoData.sheath.remoteDrawDelay, model:GetAttribute("Drawn") == true)
	local source = locomotion.humanoidTracker(model, function(): boolean
		return filter.value
	end)
	return {
		tracker = function(dt: number): any
			local driver = driverOf()
			if driver ~= nil then
				filter:step(dt, driver:serverDrawn() == true)
			end
			return source(dt)
		end,
	}
end

-- The driver options for an enemy rig: its idle and walk start at its own id's phase (D-123), so
-- a herd never breathes or roars in step. Nil when the locomotion package has no idlePhase.
local function enemyOptions(locomotion: any, id: number): any
	if typeof(locomotion.idlePhase) ~= "function" then
		return nil
	end
	return { phase = locomotion.idlePhase(id) }
end

-- Attaches the remote-rig locomotion driver (a player rig runs the blend space, an enemy rig its
-- idle / walk pair at its own phase) unless the rig is the local player's own.
local function attachDriver(record: any, animator: any)
	if drivers[record.id] ~= nil or isLocalRecord(record) then
		return
	end
	local d = dependencies()
	local attached: any = nil
	local options = if record.kind == "Player"
		then remotePlayerOptions(d.locomotion, record.model, function(): any
			return attached
		end)
		else enemyOptions(d.locomotion, record.id)
	local ok, driver = pcall(d.locomotion.attach, animator, record.model, options)
	if not ok then
		warn(("[Replication] locomotion for %s failed: %s"):format(tostring(record.name), tostring(driver)))
		return
	end
	if driver ~= nil and not Siblings.isStub(driver) then
		attached = driver
		drivers[record.id] = driver
	end
end

--- Starts watching a tracked rig: outline, trail attachment, clip events, and the locomotion
--- driver when the rig is not the local player's own.
function Replication.watch(record: any)
	local d = dependencies()
	if watched[record.id] ~= nil then
		return
	end
	d.outline.register(record.model)
	d.trails.attach(record.model)
	local animator = animatorOf(record)
	local events = if typeof(animator) == "table" then animator.events else nil
	local connection = nil
	if typeof(events) == "table" and typeof(events.Connect) == "function" then
		connection = events:Connect(function(clipId: string, event: any)
			Replication.routeClipEvent(record, clipId, event)
		end)
	end
	watched[record.id] = connection or { Disconnect = function() end }
	attachDriver(record, animator)
end

--- Stops watching a rig that left: drops its driver, reaction clip, outline, trail, telegraph and smear.
function Replication.unwatch(record: any)
	local d = dependencies()
	local connection = watched[record.id]
	if connection ~= nil then
		connection:Disconnect()
		watched[record.id] = nil
	end
	destroyDriver(record.id)
	stateClips[record.id] = nil
	trailKinds[record.id] = nil
	clipSpeeds[record.id] = nil
	switchOpeners[record.id] = nil
	lastNudges[record.id] = nil
	lastTicks[record.id] = nil
	d.outline.unregister(record.model)
	d.trails.detach(record.model)
	d.telegraphs.forget(record.model)
	d.smear.reset(record.model)
end

--- Installs dependencies (the test seam) and connects entity added/removed to watch/unwatch.
function Replication.bind(newDeps: Deps)
	deps = newDeps
	table.clear(stateClips)
	table.clear(watched)
	table.clear(drivers)
	table.clear(trailKinds)
	table.clear(switchOpeners)
	table.clear(clipSpeeds)
	table.clear(lastNudges)
	table.clear(lastTicks)
	table.clear(deathVocals)
	deathCount = 0
	silenceEnd = nil
	local entities = newDeps.entities
	if typeof(entities.added) == "table" then
		entities.added:Connect(Replication.watch)
		entities.removed:Connect(Replication.unwatch)
	end
	if typeof(entities.localChanged) == "table" then
		-- The local record can be watched before the tracker resolves its id; a driver attached
		-- then would double-drive the rig under the character controller's own Locomotion.
		entities.localChanged:Connect(function(id: number?)
			if id ~= nil then
				destroyDriver(id)
			end
		end)
	end
	if typeof(entities.all) == "function" then
		for _, record in entities.all() do
			Replication.watch(record)
		end
	end
end

--- Runs the handler for a remote name with a payload (what `net.on` calls; tests call it directly).
function Replication.dispatch(name: string, payload: any)
	local handler = handlers[name]
	if handler == nil then
		error(("Replication: no handler for remote '%s'"):format(name))
	end
	handler(payload)
end

--- Subscribes every handler to the bound net.
function Replication.subscribe()
	local d = dependencies()
	for name, handler in handlers do
		d.net.on(name, handler)
	end
end

--- Binds the real modules (missing siblings become no-op stubs) and subscribes to the remotes.
function Replication.start()
	local Client = script.Parent.Parent
	local player = game:GetService("Players").LocalPlayer
	local Net = require(Shared.net.Net)
	local EntityTracker = require(script.Parent.EntityTracker)
	local WeaponInfo = require(script.Parent.WeaponInfo)
	local CameraController = require(Client.camera.CameraController)
	local choreo = Siblings.load(Client, "choreo.Choreo")
	local clipLibrary = Siblings.load(Client, "choreo.ClipLibrary")
	Replication.bind({
		net = Net.client(),
		entities = EntityTracker,
		localId = EntityTracker.peekLocalId,
		localCharacter = function()
			return player.Character
		end,
		locomotion = Siblings.load(Client, "choreo.Locomotion"),
		choreo = choreo,
		clipLibrary = clipLibrary,
		trails = Siblings.load(Client, "fx.Trails"),
		smear = Siblings.load(Client, "fx.Smear"),
		shatter = Siblings.load(Client, "fx.Shatter"),
		sparks = Siblings.load(Client, "fx.Sparks"),
		telegraphs = Siblings.load(Client, "fx.Telegraphs"),
		outline = Siblings.load(Client, "fx.OutlineManager"),
		switchRing = Siblings.load(Client, "fx.SwitchRing"),
		digits = Siblings.load(Client, "fx.Digits"),
		hud = Siblings.load(Client, "ui.Hud"),
		systemLine = Siblings.load(Client, "ui.SystemLine"),
		sfx = Siblings.load(Client, "audio.SfxPool"),
		impact = Siblings.load(Client, "fx.Impact"),
		camera = CameraController,
		weaponCategory = function(record)
			return WeaponInfo.categoryOf(record.weaponId)
		end,
		trailToken = function(record)
			return WeaponInfo.trailTokenOf(record.weaponId)
		end,
		positionOf = function(model)
			local primary = (model :: Model).PrimaryPart
			return if primary ~= nil then primary.Position else nil
		end,
		schedule = function(seconds, fn)
			task.delay(seconds, fn)
		end,
		now = os.clock,
	})
	Replication.subscribe()
end

return Replication
