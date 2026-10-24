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
	an older death's shatter never ends a newer silence (one sweep's deaths share theirs). The
	silence spares the local player's own new sounds (issue 9): their clip sounds, footsteps,
	chime and the hit-stop tick of a hit they are in start inside SfxPool.asOwn, and the duck asks
	the pool to let those through at full while the music, the beds, the other fighters and the
	UI stay down.

	It also routes every rig's clip events (trail, smear,
	activation light, footsteps, clip sounds) to the FX and audio packages, so trails, smears and
	swings look and sound the same on the local fighter and on everyone else. A remote clip that
	ActionStarted starts late (the network catch-up jumps into it) still sounds the clip sounds it
	jumped over, each from where it would be by now (SfxPool.playLate): a swing whose whoosh starts
	on frame 0 keeps it. An Art's ActivationHold it jumped over still lights, chimes and ends its
	riser on the first damage frame while that frame is ahead. A TrailOn's
	`data.kind` ("Art" | "Basic") picks the trail kind for the rest of that clip's trail events.

	A render stall is the other way round (D-132): RenderStepped stops while the display sleeps,
	and the step that comes back with the whole gap jumps every clip past what happened in it.
	The events it crossed arrive marked as jumped, and only their closing half runs: a trail or
	smear goes off, the activation light goes out, the post-motion ends the clip's trail. Nothing
	starts: no clip sound or voice, footstep, chime, riser, FOV kick, trail or smear. Listeners of
	`clipEvent` still hear every one, marked (the local Art hold's freeze is state, not a show).

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

	The local fighter's hits land on contact (issue 4): the character controller hands each blade
	contact ContactPredictor finds to `Replication.contact` on the frame the blade touches, which
	plays the hit-stop on both rigs, the white flash, the nudge, the shake, the tick and the
	director's moment there and then, with no number. Its HitConfirmed (matched by target, window
	and Art within combat.luau contact.confirmSeconds of play: a stall counts as at most a jump,
	choreo.luau stall.jumpSeconds) then shows the number, the HP change and the reactions and
	replays nothing; a stronger tier from the server (a Kill or Final the contact could not know)
	runs the contact's hold on to its own length from the contact while that hold is still on,
	never restarting it or holding twice, and plays what its moment adds (Impact.hit's
	`previous`). A hold a later cut started is that cut's own: the word for the earlier cut never
	stretches it. A contact the server never confirms shows no number. A local hit the
	server confirmed before this client's blade got there (the client's clip runs behind by its
	hit-stops) plays as it always did and is not predicted again (`confirmedAlready`). Everyone
	else's hits play as before.

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
	-- Impact-like: hit(info, previous?) -> string, ownsHighlight(info) -> boolean, afterHidden(fn),
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
	-- Calls `fn` every Heartbeat (the clock the local predictions age on: a stall counts as at most
	-- a jump); without it they age on `now` alone.
	onHeartbeat: ((fn: (dt: number) -> ()) -> ())?,
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
--- Fires (record, clipId, event, jumped) for every clip event on every tracked rig; jumped is true
--- for an event a render stall's gap crossed (D-132).
Replication.clipEvent = Signal.new() :: Signal.Signal<any, string, any, boolean>
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
-- The local fighter's predicted contacts (Replication.contact, issue 4) waiting for their
-- HitConfirmed, oldest first, each kept combat.luau contact.confirmSeconds of play (`seen`, on
-- playClock): the hit-stop tier, the moment the contact played, when (`at`, on the clock) and
-- the run of holds on the local rig its hold belongs to (`run`).
type Prediction = {
	targetId: number,
	windowIndex: number,
	artId: string?,
	at: number,
	seen: number,
	run: number,
	tier: string,
	moment: string?,
}
local predictions: { Prediction } = {}
-- The local fighter's hits the server confirmed before this client's blade got there (the
-- client's clip runs behind the server's by the hit-stops it held): the predictor skips them.
type EarlyConfirm = { targetId: number, windowIndex: number, artId: string?, seen: number }
local earlyConfirms: { EarlyConfirm } = {}
-- The runs of holds on the local fighter's rig: a hold put on while none runs starts a new run,
-- one put on while one runs joins it (the same cut's other targets, a blow taken inside the
-- hold). A confirmation's stronger tier runs on only its own contact's run, so the word for an
-- earlier cut never stretches a later cut's hold. `holdEnds` is the clock's guess at when the
-- current run ends, for an animator that cannot say.
local holdRun = 0
local holdEnds = -math.huge
-- The play clock the predictions age on: seconds of play, a stall (an engine hitch, a minimised
-- window) counting as at most a jump (choreo.luau stall.jumpSeconds). Counted on the Heartbeat
-- (deps.onHeartbeat); without one it is the clock itself.
local playSeconds = 0
local playWall: number? = nil
local playTicking = false
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

-- Seconds of a contact's hold still to run on the attacker's rig: what its animator says is left
-- (Choreo pauseRemaining), else what the clock says of a hold of `seconds` that began `at`.
local function holdRemaining(animator: any, seconds: number, at: number): number
	local read = if typeof(animator) == "table" then animator.pauseRemaining else nil
	if typeof(read) == "function" then
		local left = read(animator)
		if typeof(left) == "number" then
			return math.max(0, left)
		end
	end
	return math.max(0, seconds - (clock() - at))
end

-- Puts a hold of `frames` on the local fighter's rig and returns the run it belongs to: a new
-- run when none is holding, else the one holding.
local function holdLocal(animator: any, frames: number): number
	local read = if typeof(animator) == "table" then animator.pauseRemaining else nil
	local holding: boolean
	if typeof(read) == "function" then
		local left = read(animator)
		holding = typeof(left) == "number" and left > ChoreoData.pauseEpsilon
	else
		holding = clock() < holdEnds
	end
	if not holding then
		holdRun += 1
		holdEnds = -math.huge
	end
	holdEnds = math.max(holdEnds, clock() + math.max(0, frames) * ChoreoData.frameSeconds)
	animator:hitStop(frames)
	return holdRun
end

-- Seconds of play now: the play clock's last count plus the time since, a stall's gap counting
-- as at most a jump, whether the wake's Heartbeat or its network comes first.
local function playClock(): number
	local wall = clock()
	if not playTicking then
		return wall
	end
	local last = playWall
	if last == nil then
		playWall = wall
		return playSeconds
	end
	return playSeconds + math.min(math.max(0, wall - last), ChoreoData.stall.jumpSeconds)
end

local function tickPlay()
	playSeconds = playClock()
	playWall = clock()
end

-- Drops the entries of a prediction list older than contact.confirmSeconds of play.
local function dropStale(list: { any }, seen: number)
	for index = #list, 1, -1 do
		if seen - list[index].seen > Combat.contact.confirmSeconds then
			table.remove(list, index)
		end
	end
end

-- Takes the oldest entry of `list` for this hit (target, window, Art), or nil.
local function takeMatch(list: { any }, targetId: number, windowIndex: number, artId: string?): any
	for index, entry in list do
		if entry.targetId == targetId and entry.windowIndex == windowIndex and entry.artId == artId then
			table.remove(list, index)
			return entry
		end
	end
	return nil
end

local function tierRank(tier: string): number
	return (Combat.hitStopFrames :: { [string]: number })[tier] or 0
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

-- Runs `fn` with the sounds it starts marked as the local player's own (SfxPool.asOwn) when `own`:
-- inside a death's silence those play at full (issue 9). A pool without asOwn just runs it.
local function asOwn(own: boolean, fn: () -> ())
	local sfx = dependencies().sfx
	local wrap = if own and typeof(sfx) == "table" then rawget(sfx, "asOwn") else nil
	if typeof(wrap) == "function" then
		wrap(fn)
	else
		fn()
	end
end

-- The camera and the hit-stop tick of a hit the local player is in: one nudge toward it per sweep
-- (twelve targets confirmed in one frame must not push twelve times; none when `nudge` is false),
-- the shake of its tier, and the tick once per sweep (a stronger tier's taking over).
local function feelHit(sweepKey: any, position: Vector3, tier: string, tick: string, nudge: boolean)
	local d = dependencies()
	local at = clock()
	if nudge then
		local nudgedAt = lastNudges[sweepKey]
		if nudgedAt == nil or at - nudgedAt > Moments.sweep.mergeSeconds then
			lastNudges[sweepKey] = at
			d.camera.nudge(position, Combat.cameraNudgeStuds)
		end
	end
	d.camera.shake(tier)
	local sound = if SOUNDS.hitStop[tick] ~= nil then tick else "Normal"
	if ticksInSweep(sound, at, sweepKey) then
		asOwn(true, function()
			d.sfx.play(SOUNDS.hitStop[sound])
		end)
	end
end

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

	-- The local fighter's hit its blade already played on contact (issue 4): this brings the number,
	-- the reactions and what a stronger tier adds; nothing that played replays. One the server
	-- confirmed first is remembered, so the contact that follows is not predicted.
	local predicted: Prediction? = nil
	if localId ~= nil and payload.attackerId == localId and payload.parried ~= true then
		local seen = playClock()
		dropStale(predictions, seen)
		dropStale(earlyConfirms, seen)
		predicted = takeMatch(predictions, payload.targetId, payload.hitIndex, payload.artId)
		if predicted == nil then
			table.insert(earlyConfirms, {
				targetId = payload.targetId,
				windowIndex = payload.hitIndex,
				artId = payload.artId,
				seen = seen,
			})
		end
	end
	-- How much more the server's tier holds than the contact did (0: nothing to add).
	local upgrade = if predicted ~= nil
		then (if Combat.hitStopFrames[tier] ~= nil then tierRank(tier) - tierRank(predicted.tier) else 0)
		else 0

	if predicted ~= nil then
		if upgrade > 0 and attacker ~= nil and predicted.run == holdRun then
			-- The contact's hold, while it is still on, runs on to the stronger tier's length from
			-- the contact, never restarted. One that already let go is not stopped again: a hit
			-- holds once (issue 6), and a later cut's hold is that cut's own; the stronger tier
			-- still sounds and shows below.
			local animator = animatorOf(attacker)
			local predictedSeconds = Combat.hitStopFrames[predicted.tier] * ChoreoData.frameSeconds
			local remaining = holdRemaining(animator, predictedSeconds, predicted.at)
			if remaining > 0 then
				local held = math.max(0, predictedSeconds - remaining)
				local left = frames - held / ChoreoData.frameSeconds
				if left > 0 then
					animator:hitStop(left)
					holdEnds = math.max(holdEnds, clock() + left * ChoreoData.frameSeconds)
					if target ~= nil and target ~= attacker then
						animatorOf(target):hitStop(left)
					end
				end
			end
		end
	else
		if attacker ~= nil then
			if payload.attackerId == localId then
				holdLocal(animatorOf(attacker), frames)
			else
				animatorOf(attacker):hitStop(frames)
			end
		end
		if target ~= nil and target ~= attacker then
			if payload.targetId == localId then
				holdLocal(animatorOf(target), frames)
			else
				animatorOf(target):hitStop(frames)
			end
		end
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
		local function accents()
			if target ~= nil then
				d.trails.flashWhite(target.model, Combat.highlightFlashFrames)
			end
			d.sparks.parry(position)
		end
		-- On the first frame after the inverted frame (the render step that takes it down).
		d.impact.afterHidden(accents)
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
		if predicted == nil and d.impact.ownsHighlight(info) ~= true and not breaksGuard then
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
	if involved and (predicted == nil or upgrade > 0) then
		-- The hit that breaks a player's guard ticks Final (the server keeps its hit-stop tier). A
		-- contact's upgrade shakes and ticks at the stronger tier; the contact gave the nudge.
		local tick = if breaksGuard and tier == "Normal" then "Final" else tier
		local sweepKey = if payload.attackerId ~= nil then payload.attackerId else NO_ATTACKER
		feelHit(sweepKey, position, tier, tick, predicted == nil)
	end
	if payload.targetId == localId and payload.damage > 0 then
		d.hud.flashHp()
	end
	-- The hit's cue (block, basic, crit, final, kill, Switch land), glint, crescent, line, frames;
	-- after a contact, only what the server's stronger tier adds to the moment it played.
	if predicted == nil then
		d.impact.hit(info)
	elseif upgrade > 0 then
		d.impact.hit(info, predicted.moment)
	end
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
		-- The local player's own new sounds play through it at full (issue 9).
		d.sfx.duck(Combat.deathDuckDb, Combat.deathFreeze, true)
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

--- Plays one of the local fighter's predicted contacts (ContactPredictor, issue 4) on the frame
--- its blade touched the enemy: the hit-stop on both rigs at the contact's tier, the white flash
--- (unless the moment owns it), the camera nudge and shake, the hit-stop tick and the director's
--- moment (its cue, accents and impact frames). No number and no HP change: those wait for the
--- server's HitConfirmed, which then plays only what its tier adds. A contact the server never
--- confirms shows no number. False (nothing played) when this client does not track the local
--- fighter or the target yet: the confirmation then plays the hit whole.
function Replication.contact(contact: any): boolean
	local d = dependencies()
	local localId = d.localId()
	local attacker = if localId ~= nil then d.entities.get(localId) else nil
	local target = d.entities.get(contact.targetId)
	if attacker == nil or target == nil or target == attacker then
		return false
	end
	local tier = if Combat.hitStopFrames[contact.tier] ~= nil then contact.tier else "Normal"
	local frames = Combat.hitStopFrames[tier]
	local position: Vector3 = contact.position
	local run = holdLocal(animatorOf(attacker), frames)
	animatorOf(target):hitStop(frames)
	-- What the contact knows of the hit: no crit, no Switch (the server rolls those), a kill only
	-- when ContactPredictor proved it.
	local info = {
		tier = tier,
		position = position,
		attacker = attacker.model,
		target = target.model,
		involved = true,
		localAttacker = true,
		trailToken = d.trailToken(attacker),
		parried = false,
		guarded = false,
		crit = false,
		isSwitch = false,
		killed = tier == "Kill",
		art = contact.artId ~= nil,
		partner = nil,
	}
	if d.impact.ownsHighlight(info) ~= true then
		d.outline.flash(target.model, "SystemWhite", Combat.highlightFlashFrames)
	end
	feelHit(localId, position, tier, tier, true)
	local moment = d.impact.hit(info)
	local seen = playClock()
	dropStale(predictions, seen)
	table.insert(predictions, {
		targetId = contact.targetId,
		windowIndex = contact.windowIndex,
		artId = contact.artId,
		at = clock(),
		seen = seen,
		run = run,
		tier = tier,
		moment = if typeof(moment) == "string" then moment else nil,
	})
	return true
end

--- True when the server already confirmed this hit of the local fighter's (it came before the
--- blade got there on this client): the predictor skips it, so nothing plays twice. Each
--- confirmation answers once.
function Replication.confirmedAlready(targetId: number, windowIndex: number, artId: string?): boolean
	if deps == nil then
		return false
	end
	dropStale(earlyConfirms, playClock())
	return takeMatch(earlyConfirms, targetId, windowIndex, artId) ~= nil
end

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

-- A clip's one-shot on a rig (a clip sound or voice, an Art's activation, a footstep).
local function routeOneShot(record: any, clipId: string, event: any)
	local d = dependencies()
	local model = record.model
	local kind = event.kind
	if kind == "Sfx" or kind == "Voice" then
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
	elseif kind == "Footstep" then
		-- SfxPool resolves the surface from the event or the Humanoid's floor, and the weight
		-- from the armor attribute.
		d.sfx.footstep(model, if event.data ~= nil then event.data.surface else nil)
	end
end

--- Routes one clip event on a rig to the FX and audio packages (trails, smear, activation light,
--- footsteps, clip sounds). `jumped`: a render stall's gap crossed it (D-132); only what it closes runs.
function Replication.routeClipEvent(record: any, clipId: string, event: any, jumped: boolean?)
	local d = dependencies()
	local model = record.model
	local kind = event.kind
	local starts = jumped ~= true
	if kind == "HitWindowOpen" or kind == "TrailOn" then
		-- A jumped one still names the clip's trail kind for the events after it.
		local trailKind = resolveTrailKind(record, clipId, event)
		if starts then
			d.trails.setActive(model, true, trailKind)
		end
		if kind == "HitWindowOpen" then
			d.trails.activationLight(model, false, d.trailToken(record))
		end
	elseif kind == "HitWindowClose" or kind == "TrailOff" then
		d.trails.setActive(model, false, resolveTrailKind(record, clipId, event))
	elseif kind == "SmearOn" then
		-- The smear frames run the trail at full width (section 10 beat 3) on top of any Art or
		-- Basic kind; Trails keeps the trail lit while any kind is on.
		if starts then
			d.smear.apply(model, true, if event.data ~= nil then event.data.axis else nil)
			d.trails.setActive(model, true, "Smear")
		end
	elseif kind == "SmearOff" then
		d.smear.apply(model, false, if event.data ~= nil then event.data.axis else nil)
		d.trails.setActive(model, false, "Smear")
	elseif kind == "PostMotionStart" then
		d.trails.activationLight(model, false, d.trailToken(record))
		d.trails.setActive(model, false, resolveTrailKind(record, clipId, event))
		trailKinds[record.id] = nil
	elseif starts then
		-- The one-shots. A clip sound or voice, an Art's activation (light, chime, kick, riser) or a
		-- footstep that a render stall's gap jumped over is over: nothing replays. The local
		-- fighter's are their own: inside a death's silence they play at full (issue 9).
		asOwn(record.id == d.localId(), function()
			routeOneShot(record, clipId, event)
		end)
	end
	Replication.clipEvent:Fire(record, clipId, event, not starts)
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
		connection = events:Connect(function(clipId: string, event: any, jumped: boolean?)
			Replication.routeClipEvent(record, clipId, event, jumped)
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
	table.clear(predictions)
	table.clear(earlyConfirms)
	holdRun = 0
	holdEnds = -math.huge
	playSeconds = 0
	playWall = nil
	playTicking = typeof(newDeps.onHeartbeat) == "function"
	if playTicking then
		(newDeps.onHeartbeat :: any)(tickPlay)
	end
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
		onHeartbeat = function(fn)
			game:GetService("RunService").Heartbeat:Connect(fn)
		end,
	})
	Replication.subscribe()
end

return Replication
