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

	An enemy's attack keeps the server's beat (D-172). The server pauses an unresolved attack for a
	player's hit by HitConfirmed attackPause (capped per attack, nothing for a launched rush), and
	that is all the attack clip and its telegraph move: the telegraph starts where the server's
	wind-up began (serverNow - serverTime ago) and its end moves by each pause; the clip
	ActionStarted played keeps its beat (Choreo keepBeat) and every pause shifts it (shiftBeat).
	The rig's hit-stop stays the only freeze, on contact as before, and the clip evens whatever it
	held beyond the server's pause. Until the server's word comes, a contact's hold counts as the
	pause the server will give it (what it added to the rig's hold, inside the attack's cap); the
	HitConfirmed swaps in the server's own, and a contact not confirmed within combat.luau
	contact.allowanceSeconds takes it back (a confirmation after that still corrects it).

	A Charger's rush is drawn on the server's timeline (D-171, choreo/RushDraw): its telegraph arms
	the launch it predicts (wind-up start + windUp + the pauses), RushStarted replaces the line and
	the clock with the server's, RushTurned its path (a glance's bend, a clipped corner's sidestep,
	D-206, D-207), RushEnded caps it (a jam, a slam's "Wall" with where the snout meets the face) or
	stops it and says where the server's body stopped (the hand-back waits for the root there,
	D-210), a Stagger or a Break stops it where it is drawn, and a death leaves the body where it was
	drawn. The drawn body meets the world as the server's does (choreo/RushWorld, D-205 to D-209): the
	server's worldAhead cast from the drawn body (RushDraw.room) slams it with its snout on a wall's
	face, bends it along a glancing wall and sidesteps a clipped corner before any message says so,
	and a ground probe under it (RushDraw.ground) stands it on the ground its root climbs.
	Replication.rushContact fires on the frame the drawn body reaches each contact, where it meets
	the face. While the body is drawn away from its root the root part is hidden, and a launched
	rush is not held by a hit on it (the server holds nothing of it either). An enemy's flinch during its attack plays with the rig's
	attackFlinch weights (D-173): the weapon arm stays on the attack. An enemy's own strike holds
	its rig only for what the hit-stop has beyond the hold after the snap its clip already showed
	on the server's beat, a launched rush's not at all (D-176).

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
local AI = require(Shared.data.ai)
local Signal = require(Shared.util.Signal)
local RushWorld = require(Shared.choreo.RushWorld)
local ClipSampler = require(Shared.choreo.ClipSampler)
local CameraMath = require(script.Parent.Parent.camera.CameraMath)
local ActionLogic = require(script.Parent.ActionLogic)
local Siblings = require(script.Parent.Siblings)

local SheathState, hasSheathState = Siblings.load(script.Parent.Parent, "choreo.SheathState")
local RushDraw, hasRushDraw = Siblings.load(script.Parent.Parent, "choreo.RushDraw")
local DrawnBody = Siblings.load(script.Parent.Parent, "choreo.DrawnBody")
local TelegraphShapes, hasTelegraphShapes = Siblings.load(script.Parent.Parent, "fx.TelegraphShapes")

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
	-- WallSlam-like: slam(point, normal) -> puffs, the dust of a rush's slam (D-217); none: no dust.
	wallSlam: any?,
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
	-- The server's clock (workspace:GetServerTimeNow), the one remotes stamp serverTime on: enemy
	-- telegraphs start on it and rushes are drawn on it. Without it a telegraph starts on receipt
	-- and no rush is drawn.
	serverNow: (() -> number)?,
	-- The local fighter's defence as CharacterController knows it: its state now, and the time on
	-- `now`'s clock it last stood in a guard or a dodge (nil: not since it spawned). Without it no
	-- enemy blow on the local fighter shows before the server's word (D-258).
	localDefence: (() -> (string, number?))?,
	-- CharacterController.awaitsKey: true while the local fighter's swing (its Art and request's
	-- sequence number) has yet to show hit `windowIndex`'s strike key on this client's clip. The
	-- server's word for that hit waits for the key frame then (D-267). Without it the word plays
	-- when it comes.
	keyAhead: ((windowIndex: number, artId: string?, swing: number?) -> boolean)?,
	-- workspace:Blockcast as the server's worldAhead makes it (RushDraw.WorldCast: how far, and the
	-- face's normal): a drawn rush stops where the world stops its root, never at ground it climbs.
	-- Without it the drawn rush stops only at RushEnded.
	worldCast: ((
		start: CFrame,
		size: Vector3,
		vector: Vector3,
		group: string,
		exclude: Instance
	) -> (number?, Vector3?))?,
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
--- Fires (record, kind, point, normal) on the frame a rush's drawn body reaches a contact with the
--- world (D-208): "Slam" as its snout rests on a wall's face, "Glance" as it starts along a glancing
--- wall, "Clip" as it shoulders past a corner; `point` is where the body meets the face (world
--- space), `normal` the face's flat normal toward the body. Once per contact, the server's word or
--- this client's own cast's, whichever the drawn body reaches first.
Replication.rushContact = Signal.new() :: Signal.Signal<any, string, Vector3, Vector3>

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
	swing: number?, -- the swing's sequence number (HitConfirmed echoes it)
	at: number,
	seen: number,
	run: number,
	tier: string,
	moment: string?,
	-- The pause its hold stood for on the target's attack (D-172) until the server's word, and that
	-- attack (nil when it paused none).
	allowance: number,
	attack: Attack?,
	-- Seconds of hold this contact asked of the local rig so far: its tier's, and every frame it
	-- held on for the word (D-CH1). Less what the rig has left, it is what the hold has shown.
	asked: number,
	-- True while its hold may still hold on for the word: until the word comes, the hold has run
	-- contact.wordHoldSeconds from the contact, a later hold's run began, or a word for a later
	-- window of the same swing says the server did not count this one.
	waiting: boolean,
}
-- An enemy's attack this client knows of (D-172): when its wind-up began on the server's clock,
-- its beats, the pause the server gave it so far (or a contact's provisional share), the attack
-- clip ActionStarted played (its handle keeps the beat) and whether it is a rush.
type Attack = {
	since: number,
	windUp: number,
	strike: number,
	rush: boolean,
	paused: number,
	handle: any?,
	def: any?, -- its row in enemies.luau (reach, arc: the shape it lands on)
	judged: boolean?, -- its strike frame was judged for the local fighter (D-258), or its word came
}
local predictions: { Prediction } = {}
-- The local fighter's hits the server confirmed before this client's blade got there (the
-- client's clip runs behind the server's by the hit-stops it held): the predictor skips them.
type EarlyConfirm = { targetId: number, windowIndex: number, artId: string?, swing: number?, seen: number }
local earlyConfirms: { EarlyConfirm } = {}
-- The server's words for the local fighter's hits that came before this client's clip showed the
-- strike's key (D-267): the server counts a point-blank hit at its window's open and runs ahead
-- by the holds this client played. Each waits for the key frame (the contact the blade makes on
-- it, or the Heartbeat after the clip showed the key), at most combat.contact.wordWaitSeconds.
-- A kill's word keeps its EntityDied (`deaths`), which plays just before it, as on the wire.
local heldWords: { { payload: any, seen: number, deaths: { any }? } } = {}
-- The word being let go now (it is not held again).
local releasing: any = nil
-- Deaths a player dealt that came while a word may be held (the server sends a kill's EntityDied
-- just before its HitConfirmed): each waits for the word that follows it, which takes it along
-- when it is held, and plays on the next Heartbeat when no held word takes it (D-267 amended).
local heldDeaths: { any } = {}
-- The death being let go now (it is not held again).
local releasingDeath: any = nil
-- The contact frame (on the clock) of the kill whose word lets its held death go now: the death's
-- silence and shatter keep that contact's beat (D-CH2).
local releasingContactAt: number? = nil
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
-- The clock at the last Heartbeat and the length of the step it closed (D-CH1): a hold that holds
-- on for its word goes on one such step at a time, so it ends on the frame the word comes.
local beatAt: number? = nil
local beatStep: number = ChoreoData.frameSeconds
-- The newest death owns the silence: how many deaths came so far, and when the silence a death
-- started ends (nil while none holds).
local deathCount = 0
local silenceEnd: number? = nil
-- enemy id -> its attack in progress (D-172).
local attacks: { [number]: Attack } = {}
-- enemy id -> its rush being drawn (D-171): its record, the drawing state, the animator and root
-- it draws on, the step hook, whether RushStarted came (`launched`), the server time from which a
-- RushEnded is this rush's (`since`), the root's transparency modifier before it was hidden, how far
-- the world lets the drawn body move and how high the ground under it stands (nil without a world
-- cast).
type Rush = {
	record: any,
	state: any,
	animator: any,
	root: BasePart?,
	unhook: (() -> ())?,
	launched: boolean,
	released: boolean?, -- its wind-up was dropped or cut: no launch retimes it (releaseRush)
	since: number,
	shownAs: number?,
	room: ((from: CFrame, direction: Vector3, distance: number) -> (number?, Vector3?))?,
	ground: ((spot: Vector3) -> number?)?,
}
local rushes: { [number]: Rush } = {}
-- enemy id -> the server time of the last rush launch heard (RushStarted), or of the last attack
-- the server dropped (RushEnded "Dropped", its wind-up's end): a Telegraph or an ActionStarted from
-- before it is that attack's own, or an older one's, come late (they are unreliable; these are not).
local launches: { [number]: number } = {}
-- enemy id -> its blow on the local fighter shown on the strike's server frame (F16, D-258), until
-- its HitConfirmed: when (`seen`, on playClock), the moment Impact played, the target and its
-- flinch clip.
type Struck = { seen: number, moment: string?, targetId: number, handle: any? }
local struck: { [number]: Struck } = {}

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

-- The frames a hit's hold of `frames` asks a rig's animator for: combat.luau hitStopShaveFrames
-- short, so the frames it freezes count exactly (F6): a pause that outlives the last counted frame
-- by a sliver would freeze a whole frame more.
local function heldFrames(frames: number): number
	return math.max(0, frames - Combat.hitStopShaveFrames)
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
	local held = heldFrames(frames)
	holdEnds = math.max(holdEnds, clock() + held * ChoreoData.frameSeconds)
	animator:hitStop(held)
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

local tickPlay: () -> ()

-- Drops the entries of a prediction list older than contact.confirmSeconds of play.
local function dropStale(list: { any }, seen: number)
	for index = #list, 1, -1 do
		if seen - list[index].seen > Combat.contact.confirmSeconds then
			table.remove(list, index)
		end
	end
end

-- Takes the oldest entry of `list` for this hit (target, window, Art, and the swing's sequence
-- number when both sides carry one), or nil. The swing number keeps a quick second swing's hit
-- from taking the first swing's word (item 4): the same target, window and Art twice in a row.
local function takeMatch(list: { any }, targetId: number, windowIndex: number, artId: string?, swing: number?): any
	for index, entry in list do
		if
			entry.targetId == targetId
			and entry.windowIndex == windowIndex
			and entry.artId == artId
			and (swing == nil or entry.swing == nil or entry.swing == swing)
		then
			table.remove(list, index)
			return entry
		end
	end
	return nil
end

-- True when the server's word for one of the local fighter's hits is to wait for its strike's key
-- on this client's clip (D-267). A kill's word waits too, and its EntityDied with it (D-267
-- amended). Words wait only on a client that ticks Heartbeat (deps.onHeartbeat), which lets them go.
local function waitsForKey(payload: any): boolean
	local keyAhead = dependencies().keyAhead
	return playTicking
		and keyAhead ~= nil
		and typeof(payload.hitIndex) == "number"
		and keyAhead(payload.hitIndex, payload.artId, payload.swing) == true
end

local function tierRank(tier: string): number
	return (Combat.hitStopFrames :: { [string]: number })[tier] or 0
end

-- The server's clock (deps.serverNow), or nil when this client has none.
local function serverClock(): number?
	local fn = dependencies().serverNow
	return if fn ~= nil then fn() else nil
end

-- A method of a dependency that may not have it (a fake animator, an older telegraph package).
local function method(object: any, name: string): any
	if typeof(object) ~= "table" then
		return nil
	end
	local found = object[name]
	return if typeof(found) == "function" then found else nil
end

-- An enemy's def and the attack named by id or played as clip `clipId`, or nil.
local function attackDefOf(record: any, attackId: string?, clipId: string?): (any, any)
	if record == nil or record.kind ~= "Enemy" then
		return nil, nil
	end
	local def = Enemies.byId(record.defId or "")
	if def == nil then
		return nil, nil
	end
	for _, attack in def.attacks do
		if attackId ~= nil and attack.id == attackId then
			return def, attack
		end
		if clipId ~= nil and ActionLogic.clipId("Enemy", def.skin, "", attack.clip) == clipId then
			return def, attack
		end
	end
	return def, nil
end

-- The attack an enemy began at server time `since` (its Telegraph and its ActionStarted carry the
-- same tick's time): the one already known, or a new one replacing the last.
local function attackAt(record: any, def: any, attack: any, since: number): Attack
	local known = attacks[record.id]
	if known ~= nil and math.abs(known.since - since) <= 0.5 * AI.tickSeconds() then
		return known
	end
	local entry: Attack = {
		since = since,
		windUp = attack.windUp,
		strike = attack.strike,
		rush = hasRushDraw and RushDraw.isRush(def.archetype, attack),
		paused = 0,
		handle = nil,
		def = attack,
		judged = false,
	}
	attacks[record.id] = entry
	return entry
end

-- True while the server may still pause this attack (Brain.pauseAttack): through the wind-up and
-- the strike before it resolves, a rush only until its launch.
local function attackOpen(attack: Attack): boolean
	local now = serverClock()
	if now == nil then
		return attack.handle ~= nil
	end
	local resolves = attack.since + attack.windUp + attack.paused + (if attack.rush then 0 else attack.strike)
	return now < resolves
end

-- The rush drawn for an enemy while the server's clock still moves its body (RushDraw.running).
local function rushRunning(id: number): boolean
	local rush = rushes[id]
	return rush ~= nil and hasRushDraw and RushDraw.running(rush.state)
end

-- Moves everything on an enemy's attack beat by `seconds` of server pause (negative takes one
-- back): the clip's beat, the telegraph's end and a predicted launch (D-171, D-172).
local function shiftAttack(record: any, attack: Attack, seconds: number)
	if seconds == 0 or attacks[record.id] ~= attack then
		return
	end
	attack.paused += seconds
	local handle = attack.handle
	if handle ~= nil then
		local animator = animatorOf(record)
		local shift = method(animator, "shiftBeat")
		if shift ~= nil then
			shift(animator, handle, seconds)
		end
	end
	local telegraphs = dependencies().telegraphs
	local delay = method(telegraphs, "delay")
	if delay ~= nil then
		delay(record.model, seconds)
	end
	local rush = rushes[record.id]
	if rush ~= nil and not rush.launched and hasRushDraw then
		RushDraw.delay(rush.state, seconds)
	end
end

-- The pause a hold of `added` seconds on an enemy's rig stands for until the server's word: what
-- its open attack's cap still allows (Brain.pauseAttack), applied at once. Returns it and the attack.
local function allowPause(record: any, added: number): (number, Attack?)
	local attack = attacks[record.id]
	if attack == nil or added <= 0 or not attackOpen(attack) then
		return 0, nil
	end
	local allowed = math.min(added, math.max(0, AI.hitStop.maxPausePerAttack - attack.paused))
	if allowed <= 0 then
		return 0, attack
	end
	shiftAttack(record, attack, allowed)
	return allowed, attack
end

-- Seconds of hit-stop an animator holds now, or nil when it cannot say.
local function pauseOf(animator: any): number?
	local read = method(animator, "pauseRemaining")
	if read == nil then
		return nil
	end
	local left = read(animator)
	return if typeof(left) == "number" then left else nil
end

-- Holds an enemy target's rig `frames` frames for a hit (never a launched rush's: the server holds
-- nothing of it) and returns what the hold added, in seconds.
local function holdTarget(record: any, frames: number): number
	if rushRunning(record.id) then
		return 0
	end
	local animator = animatorOf(record)
	local before = pauseOf(animator)
	local held = heldFrames(frames)
	animator:hitStop(held)
	local after = pauseOf(animator)
	if before == nil or after == nil then
		return held * ChoreoData.frameSeconds
	end
	return math.max(0, after - before)
end

-- Real seconds of the authored hold after its latest strike snap (D-154's hold) an enemy's attack
-- clip has already shown: from the snap's landing up to where the clip is now, or the whole hold
-- once the clip is past it. 0 for a clip not yet landed, one without such a hold, or no clip.
local function strikeHoldShown(handle: any): number
	if typeof(handle) ~= "table" or handle.done == true or typeof(handle.time) ~= "number" then
		return 0
	end
	local clip = handle.clip
	if typeof(clip) ~= "table" or typeof(clip.keys) ~= "table" then
		return 0
	end
	local keys = clip.keys
	local time: number = handle.time
	for index = #keys, 3, -1 do -- index: a hold key, after its snap key and the key before that
		if ClipSampler.isStrikeSnap(clip, index - 1) and keys[index - 2].time <= time then
			local landed = keys[index - 1].time
			if keys[index].easing ~= "Hold" or time <= landed then
				return 0
			end
			local speed = if typeof(handle.speed) == "number" and handle.speed > 0 then handle.speed else 1
			return (math.min(time, keys[index].time) - landed) / speed
		end
	end
	return 0
end

-- Holds an enemy's rig for its own strike's hit (D-176). Its attack clip keeps the server's beat
-- (D-172), so the clip's hold after the snap already showed the impact where the server resolved
-- the strike, a latency before this HitConfirmed came: the rig holds only what the hit-stop has
-- beyond the part of that hold already shown (D-154: the longer of the two, never their sum). A
-- launched rush's rig is not held at all: its body never stops (the server holds nothing of it).
local function holdStriker(record: any, frames: number)
	if rushRunning(record.id) then
		return
	end
	local attack = attacks[record.id]
	local shown = if attack ~= nil then strikeHoldShown(attack.handle) else 0
	local left = frames - shown / ChoreoData.frameSeconds
	if left > 1e-6 then
		animatorOf(record):hitStop(left)
	end
end

-- Gives back the pause a prediction stood for when the server never confirmed it (D-172).
local function giveBack(prediction: Prediction)
	local attack = prediction.attack
	if attack == nil or prediction.allowance == 0 then
		return
	end
	local record = dependencies().entities.get(prediction.targetId)
	if record ~= nil then
		shiftAttack(record, attack, -prediction.allowance)
	end
	prediction.allowance = 0
end

-- Drops the predictions older than contact.confirmSeconds of play; one not confirmed within
-- contact.allowanceSeconds gives back the pause it stood for (D-172).
local function expirePredictions(seen: number)
	for index = #predictions, 1, -1 do
		local prediction = predictions[index]
		local age = seen - prediction.seen
		if age > Combat.contact.confirmSeconds then
			table.remove(predictions, index)
			giveBack(prediction)
		elseif age > Combat.contact.allowanceSeconds and prediction.allowance ~= 0 then
			giveBack(prediction)
		end
	end
end

-- True when a hold with `left` seconds still to run freezes the next step of `step` seconds (the
-- Mixer's rule, D-228 amended: at least half of the step is owed).
local function holdsNext(left: number, step: number): boolean
	return left > ChoreoData.pauseEpsilon and left + ChoreoData.pauseEpsilon >= step * 0.5
end

-- Holds a rig on for one more step of `step` seconds unless what it holds already freezes it;
-- returns the seconds this added to its hold.
local function holdOneStep(animator: any, step: number): number
	local left = pauseOf(animator)
	if left ~= nil and holdsNext(left, step) then
		return 0
	end
	animator:hitStop(step / ChoreoData.frameSeconds)
	return math.max(0, step - (left or 0))
end

-- A contact's hold waits for its word (D-CH1). Every Heartbeat, after the render step: while a
-- contact of the hold now running on the local rig still waits for the server's HitConfirmed, has
-- held less than contact.wordHoldSeconds from its contact frame and the hold would let go on the
-- next frame, both rigs hold one more step. The word then lets them go (HitConfirmed: the frame
-- that first shows its number is still held, a stronger tier runs on in place); a word that never
-- comes lets them go at the cap with no number.
local function holdForWords(step: number)
	if #predictions == 0 then
		return
	end
	local d = dependencies()
	local localId = d.localId()
	local attacker = if localId ~= nil then d.entities.get(localId) else nil
	local now = clock()
	local waiting: { Prediction } = {}
	for _, prediction in predictions do
		if not prediction.waiting then
			continue
		end
		-- The next frame would take it past the cap (a hair over: a 60 fps clock sums short).
		if prediction.run ~= holdRun or now + step - prediction.at > Combat.contact.wordHoldSeconds + 1e-6 then
			prediction.waiting = false
		else
			table.insert(waiting, prediction)
		end
	end
	if #waiting == 0 or attacker == nil then
		return
	end
	local animator = animatorOf(attacker)
	if animator == nil then
		return
	end
	local added = holdOneStep(animator, step)
	if added > 0 then
		holdEnds = math.max(holdEnds, now + step)
		for _, prediction in waiting do
			prediction.asked += added
		end
	end
	-- The target holds on with it, unless it is in an attack the server may still pause: that keeps
	-- the server's beat (D-172), which pauses it for the hit's own hold and no more.
	local held: { [any]: boolean } = {}
	for _, prediction in waiting do
		local target = d.entities.get(prediction.targetId)
		local attack = if target ~= nil then attacks[target.id] else nil
		if
			target ~= nil
			and target ~= attacker
			and not held[target]
			and not rushRunning(target.id)
			and not (attack ~= nil and attackOpen(attack))
		then
			held[target] = true
			local targetAnimator = animatorOf(target)
			if targetAnimator ~= nil then
				holdOneStep(targetAnimator, step)
			end
		end
	end
end

function tickPlay()
	playSeconds = playClock()
	playWall = clock()
	-- A contact the server has not confirmed in time gives back the pause it stood for (D-172).
	if #predictions > 0 then
		expirePredictions(playSeconds)
	end
end

-- The root part's transparency modifier while a rush draws the body away from it.
local function hideRoot(rush: Rush, hidden: boolean)
	local root = rush.root
	if root == nil then
		return
	end
	local value = ChoreoData.enemy.rush.hiddenRootTransparency
	if hidden then
		if rush.shownAs == nil then
			rush.shownAs = root.LocalTransparencyModifier
			root.LocalTransparencyModifier = value
		end
	elseif rush.shownAs ~= nil then
		if root.LocalTransparencyModifier == value then
			root.LocalTransparencyModifier = rush.shownAs :: number
		end
		rush.shownAs = nil
	end
end

-- Stops drawing an enemy's rush: the body goes back on its root (a frozen death's stays hidden).
local function endRush(id: number)
	local rush = rushes[id]
	if rush == nil then
		return
	end
	rushes[id] = nil
	local unhook = rush.unhook
	rush.unhook = nil
	if unhook ~= nil then
		unhook()
	end
	if hasRushDraw and rush.state.phase == "Frozen" then
		return
	end
	local set = method(rush.animator, "setBodyOffset")
	if set ~= nil then
		set(rush.animator, nil)
	end
	hideRoot(rush, false)
end

-- A rush that will not run as drawn (its wind-up dropped or cut before any RushStarted): a crouch
-- keeps its turn until the late root comes round, a predicted launch slides back (RushDraw.release).
local function releaseRush(id: number)
	local rush = rushes[id]
	if rush == nil then
		return
	end
	local now = serverClock()
	local root = rush.root
	rush.released = true
	if now == nil or not RushDraw.release(rush.state, now, if root ~= nil then root.CFrame else nil) then
		endRush(id)
	end
end

-- A rush's slam on the frame its drawn snout meets the wall (D-217): the dust thrown off the
-- face and the stone thud where they meet, and a short shake when that is near the local
-- player's body (fx.wallSlam), whole up to shakeFullRadius and fading by CameraMath.falloff to
-- nothing at shakeRadius. The dust never glows: it is no flash, so it needs no flash budget.
local function slamCue(point: Vector3, normal: Vector3)
	local d = dependencies()
	local slam = Fx.wallSlam
	local dust = d.wallSlam
	if dust ~= nil then
		dust.slam(point, normal)
	end
	d.sfx.cue(slam.cue, point)
	local localId = d.localId()
	local own = if localId ~= nil then d.entities.get(localId) else nil
	local at = if own ~= nil and own.model ~= nil then d.positionOf(own.model) else nil
	local distance = if at ~= nil then (at - point).Magnitude else math.huge
	if distance <= slam.shakeRadius then
		d.camera.shake(slam.shakeTier, CameraMath.falloff(distance, slam.shakeFullRadius, slam.shakeRadius))
	end
end

-- One frame of a rush's drawing, from the animator's step (before it poses the rig).
local function stepRush(id: number, rush: Rush, dt: number)
	if rushes[id] ~= rush then
		return
	end
	local now = serverClock()
	local root = rush.root
	if now == nil or root == nil or root.Parent == nil then
		endRush(id)
		return
	end
	local rootFrame = root.CFrame
	-- The velocity the late root carries (D-256), when the root can say.
	local ok, carried = pcall(function(): any
		return (root :: BasePart).AssemblyLinearVelocity
	end)
	local velocity: Vector3? = if ok and typeof(carried) == "Vector3" then carried else nil
	local drawn = RushDraw.step(rush.state, now, dt, rootFrame, rush.room, rush.ground, velocity)
	if drawn ~= nil then
		rush.animator:setBodyOffset(rootFrame:Inverse() * drawn)
		hideRoot(rush, true)
	elseif rush.state.phase == "Done" then
		endRush(id)
	end
	-- The contacts the drawn body reached this frame, where it meets the face (D-208).
	for _, cue in RushDraw.takeCues(rush.state) do
		Replication.rushContact:Fire(rush.record, cue.kind, cue.point, cue.normal)
		if cue.kind == "Slam" then
			slamCue(cue.point, cue.normal)
		end
	end
end

-- How high a model's root centre stands above the ground under it (the Humanoid's HipHeight plus
-- half the root's height), or nil without a Humanoid.
local function hoverOf(model: Model, root: BasePart): number?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end
	local ok, hip = pcall(function(): any
		return (humanoid :: Humanoid).HipHeight
	end)
	if not ok or typeof(hip) ~= "number" then
		return nil
	end
	return hip + root.Size.Y / 2
end

-- Starts drawing an enemy's rush on `line` (the telegraph's prediction, or RushStarted's own).
local function armRush(record: any, line: any, since: number, launched: boolean)
	endRush(record.id)
	if not hasRushDraw or serverClock() == nil then
		return
	end
	local animator = animatorOf(record)
	if method(animator, "setBodyOffset") == nil or method(animator, "onStep") == nil then
		return
	end
	local model = record.model
	local root: BasePart? = if model ~= nil then (model :: Model).PrimaryPart else nil
	local rush: Rush = {
		record = record,
		state = RushDraw.new(line),
		animator = animator,
		root = root,
		unhook = nil,
		launched = launched,
		since = since,
		shownAs = nil,
		room = nil,
		ground = nil,
	}
	local cast = dependencies().worldCast
	if cast ~= nil and root ~= nil then
		-- The server's worldAhead from the drawn body: its root's own box, never its own model; the
		-- body a wall stops (its corners at rest, D-205) and the ground under it.
		local part = root :: BasePart
		rush.room = function(from: CFrame, direction: Vector3, distance: number): (number?, Vector3?)
			return RushDraw.room(from, part.Size, direction, distance, cast, model)
		end
		rush.ground = function(spot: Vector3): number?
			return RushDraw.ground(spot, cast, model)
		end
		RushDraw.setBody(
			rush.state,
			{ profile = RushWorld.profileOf(model :: Model), size = part.Size },
			hoverOf(model :: Model, part)
		)
	end
	rushes[record.id] = rush
	rush.unhook = animator:onStep(function(dt: number)
		stepRush(record.id, rush, dt)
	end)
end

-- The flinch weights an enemy plays with while its attack clip is before its PostMotionStart
-- (choreo.luau reaction.attackFlinch, D-173), or nil outside an attack.
local function attackFlinchMask(record: any): { [string]: number }?
	local mask = (ChoreoData.reaction.attackFlinch :: { [string]: { [string]: number } })[record.rig or ""]
	local attack = attacks[record.id]
	if mask == nil or attack == nil then
		return nil
	end
	local handle = attack.handle
	if typeof(handle) ~= "table" or handle.stopping == true or handle.done == true then
		return nil
	end
	local clip = handle.clip
	if typeof(clip) ~= "table" or typeof(clip.events) ~= "table" or typeof(handle.time) ~= "number" then
		return nil
	end
	for _, event in clip.events do
		if event.kind == "PostMotionStart" then
			return if handle.time < event.time then mask else nil
		end
	end
	return nil
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

-- Where an enemy's telegraph lies (F11): the ground under `origin` (its root's centre at the beat,
-- what the server sends), as this client's world cast finds it (the drawn rush's ground probe:
-- through players and enemies); else its root's hover below it; else `origin` itself.
local function grounded(record: any, origin: Vector3): Vector3
	local model = record.model
	local cast = dependencies().worldCast
	if hasRushDraw and cast ~= nil and typeof(model) == "Instance" then
		local below = RushDraw.ground(origin, cast, model)
		if below ~= nil then
			return Vector3.new(origin.X, below, origin.Z)
		end
	end
	local root = if typeof(model) == "Instance" and model:IsA("Model") then model.PrimaryPart else nil
	local hover = if root ~= nil then hoverOf(model, root) else nil
	if hover ~= nil then
		return origin - Vector3.new(0, hover, 0)
	end
	return origin
end

-- An attack the server dropped before it landed or launched (RushEnded "Dropped", D-254: a hold or a
-- sleep, which no stagger tells): its tell comes down, its clip fades out, a launch its telegraph
-- predicted is not drawn, and its Telegraph or ActionStarted heard late is ignored (`launches`).
-- `beat` is its wind-up's end on the server's clock: an attack known to begin after it is a newer one.
local function dropAttack(record: any, beat: number)
	local id = record.id
	launches[id] = math.max(launches[id] or -math.huge, beat)
	local attack = attacks[id]
	if attack ~= nil and attack.since > beat + 0.5 * AI.tickSeconds() then
		return
	end
	dependencies().telegraphs.hide(record.model)
	if attack ~= nil then
		attacks[id] = nil
		local handle = attack.handle
		if handle ~= nil then
			animatorOf(record):stop(handle, Combat.locomotionBlendOut)
		end
	end
	local rush = rushes[id]
	if rush ~= nil and not rush.launched then
		releaseRush(id)
	end
end

-- A model's root part, or nil (no model, no PrimaryPart).
local function primaryOf(model: any): BasePart?
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	return (model :: Model).PrimaryPart
end

-- The side a blow comes from in the target's own frame (-Z is its front), as the server names it
-- (DamageMath.staggerDirection): the flinch shown before its word is the one the word then names.
local function sideOf(from: Vector3, target: CFrame): string
	local offset = target:PointToObjectSpace(from)
	if math.abs(offset.Z) >= math.abs(offset.X) then
		return if offset.Z <= 0 then "Front" else "Back"
	end
	return if offset.X > 0 then "Right" else "Left"
end

-- Takes back an enemy's blow shown before the server's word (D-258): its flinch fades if it plays.
local function takeBack(attackerId: number)
	local shown = struck[attackerId]
	if shown == nil then
		return
	end
	struck[attackerId] = nil
	local handle = shown.handle
	if handle ~= nil and stateClips[shown.targetId] == handle then
		stateClips[shown.targetId] = nil
		local target = dependencies().entities.get(shown.targetId)
		if target ~= nil then
			animatorOf(target):stop(handle, AI.strikePrediction.takeBackBlendOut)
		end
	end
end

-- True when the local fighter stands open to `attack` at its strike frame as far as this client can
-- tell (D-258): in a state a blow lands on, no guard or dodge let go within the grace (the server
-- may hold it still), and deep inside the blow's shape from where the attacker stands and faces.
local function exposedTo(attacker: any, target: any, attack: Attack): boolean
	local config = AI.strikePrediction
	local defence = dependencies().localDefence
	if defence == nil or not hasTelegraphShapes then
		return false
	end
	local state, leftAt = defence()
	if config.exposedStates[state] ~= true then
		return false
	end
	if leftAt ~= nil and clock() - leftAt < config.defenceGraceSeconds then
		return false
	end
	local def = attack.def
	local from = primaryOf(attacker.model)
	local body = primaryOf(target.model)
	if def == nil or from == nil or body == nil then
		return false
	end
	local frame = from.CFrame
	local origin, look, at = frame.Position, frame.LookVector, body.CFrame.Position
	return TelegraphShapes.deepInside(
		def.reach,
		def.arc,
		Combat.strikeLineWidth,
		{ origin.X, origin.Y, origin.Z },
		{ look.X, 0, look.Z },
		{ at.X, at.Y, at.Z },
		config.marginStuds,
		config.marginDegrees
	)
end

-- Shows an enemy's blow on the local fighter on its strike's server frame (F16, D-258): the flinch
-- from the side it comes from, the white flash and the hit's moment (its sound). HP, the number and
-- the hit-stop wait for the server's word (HitConfirmed, heardStrike).
local function showStrike(attacker: any, target: any)
	local d = dependencies()
	local from, body = primaryOf(attacker.model), primaryOf(target.model)
	if from == nil or body == nil then
		return
	end
	local bodyFrame = body.CFrame
	playReaction(target, "Flinch" .. sideOf(from.CFrame.Position, bodyFrame))
	-- What the word will say of an open blow (CombatService.enemyStrike: a Normal hit-stop).
	local info = {
		tier = "Normal",
		position = bodyFrame.Position,
		attacker = attacker.model,
		target = target.model,
		involved = true,
		localAttacker = false,
		trailToken = d.trailToken(attacker),
		parried = false,
		guarded = false,
		crit = false,
		isSwitch = false,
		killed = false,
		art = nil,
		partner = nil,
	}
	if d.impact.ownsHighlight(info) ~= true then
		d.outline.flash(target.model, "SystemWhite", Combat.highlightFlashFrames)
	end
	local moment = d.impact.hit(info)
	struck[attacker.id] = {
		seen = playClock(),
		moment = if typeof(moment) == "string" then moment else nil,
		targetId = target.id,
		handle = stateClips[target.id],
	}
end

-- The server's word on an enemy's blow at the local fighter (D-258): the blow shown before it, or
-- nil. A word that parries, guards or breaks a guard takes the shown flinch back and returns nil,
-- so the word plays its own answer whole. A word heard before the strike frame leaves it unshown.
local function heardStrike(payload: any): Struck?
	local attackerId = payload.attackerId
	local attack = attacks[attackerId]
	if attack ~= nil then
		attack.judged = true
	end
	local shown = struck[attackerId]
	if shown == nil then
		return nil
	end
	if payload.parried == true or payload.guarded == true or payload.broke == true then
		takeBack(attackerId)
		return nil
	end
	struck[attackerId] = nil
	return shown
end

-- True while the flinch of a blow shown before its word plays on `targetId` (its Stagger word does
-- not restart it).
local function flinchShown(targetId: number): boolean
	local handle = stateClips[targetId]
	if handle == nil then
		return false
	end
	for _, shown in struck do
		if shown.targetId == targetId and shown.handle == handle then
			return true
		end
	end
	return false
end

--- Judges, once, every known enemy blow whose strike frame the server's clock has reached, for the
--- local fighter (F16, D-258), and takes back the blows shown that the server has not confirmed in
--- ai.luau strikePrediction.confirmSeconds of play. Runs every Heartbeat; tests call it.
function Replication.stepStrikes()
	local d = dependencies()
	local config = AI.strikePrediction
	local seen = playClock()
	for attackerId, shown in struck do
		if seen - shown.seen > config.confirmSeconds then
			takeBack(attackerId)
		end
	end
	local now = serverClock()
	local localId = d.localId()
	if not config.enabled or now == nil or localId == nil or d.localDefence == nil then
		return
	end
	local target: any = nil
	for id, attack in attacks do
		if attack.judged == true or attack.rush or not (attack.strike > 0) then
			continue
		end
		local lands = attack.since + attack.windUp + attack.strike + attack.paused
		if now < lands then
			continue
		end
		attack.judged = true
		if now - lands > config.lateSeconds or struck[id] ~= nil then
			continue
		end
		target = target or d.entities.get(localId)
		local attacker = d.entities.get(id)
		if target ~= nil and attacker ~= nil and target.kind == "Player" and exposedTo(attacker, target, attack) then
			showStrike(attacker, target)
		end
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
	local launched = launches[record.id]
	if launched ~= nil and payload.serverTime < launched then
		-- Out of order (as D-222 guards the Telegraph): this attack has launched, or was dropped, and
		-- its clip would start from the middle of its run (item 8). The gait follows the drawn body.
		return
	end
	local animator = animatorOf(record)
	local handle = animator:play(payload.clipId, { serverTime = payload.serverTime, speed = payload.speed })
	clipSpeeds[record.id] = { clipId = payload.clipId, speed = payload.speed }
	replaySkipped(record, handle, payload.clipId)
	local def, attackDef = attackDefOf(record, nil, payload.clipId)
	if attackDef ~= nil and typeof(handle) == "table" then
		-- An enemy's attack clip keeps the server's beat (D-172), shifted by any pause already given.
		local attack = attackAt(record, def, attackDef, payload.serverTime)
		attack.handle = handle
		local keep = method(animator, "keepBeat")
		if keep ~= nil then
			keep(animator, handle, payload.serverTime)
			if attack.paused ~= 0 then
				animator:shiftBeat(handle, attack.paused)
			end
		end
	end
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
	local launched = launches[record.id]
	if launched ~= nil and payload.serverTime < launched then
		-- Out of order: this wind-up has launched (or a later one has) and the rush is drawn on the
		-- server's line already. Armed again as a guess it drew the running body back to the crouch.
		return
	end
	-- On the server's beat: the wind-up began serverTime, this long ago (D-172).
	local now = serverClock()
	local lateBy = if now ~= nil then math.max(0, now - payload.serverTime) else nil
	local origin, facing = toVector(payload.origin), toVector(payload.facing)
	local def, attackDef = attackDefOf(record, payload.attackId, nil)
	local rush = attackDef ~= nil and hasRushDraw and RushDraw.isRush(def.archetype, attackDef)
	-- A blow's tell holds to its snap (F7); a rush's line ends at its launch. Its shape lies on the
	-- ground under the root the server named (F11).
	local strike = if attackDef ~= nil and not rush then attackDef.strike else nil
	d.telegraphs.show(
		record.model,
		payload.kind,
		payload.windUp,
		grounded(record, origin),
		facing,
		payload.shape,
		lateBy,
		strike
	)
	if attackDef == nil then
		return
	end
	local attack = attackAt(record, def, attackDef, payload.serverTime)
	if attack.paused ~= 0 then
		local delay = method(d.telegraphs, "delay")
		if delay ~= nil then
			delay(record.model, attack.paused)
		end
	end
	if attack.rush then
		-- The launch it predicts, until RushStarted brings the server's own (D-171).
		local line = RushDraw.predict(attackDef, payload.serverTime + attack.paused, origin, facing)
		armRush(record, line, payload.serverTime, false)
	end
end

function handlers.RushStarted(payload: any)
	local d = dependencies()
	if payload.entityId == d.localId() then
		return
	end
	local record = d.entities.get(payload.entityId)
	if record == nil or not hasRushDraw then
		return
	end
	launches[record.id] = math.max(launches[record.id] or -math.huge, payload.serverTime)
	local _, attackDef = attackDefOf(record, payload.attackId, nil)
	local line = {
		origin = toVector(payload.origin),
		direction = toVector(payload.direction),
		speed = payload.speed,
		length = payload.speed * payload.duration,
		strike = if attackDef ~= nil then attackDef.strike else payload.duration,
		startedAt = payload.serverTime,
	}
	local rush = rushes[record.id]
	if rush ~= nil and not rush.launched and rush.released ~= true and rush.state.phase ~= "Done" then
		RushDraw.retime(rush.state, line)
		rush.launched = true
	else
		armRush(record, line, payload.serverTime, true)
	end
end

-- The rush drawn for an enemy that a rush message stamped `launchedAt` is about, or nil (nothing
-- drawn, or an earlier rush's message).
local function rushOf(payload: any): Rush?
	local rush = rushes[payload.entityId]
	if rush == nil or payload.launchedAt < rush.since - 0.5 * AI.tickSeconds() then
		return nil
	end
	return rush
end

function handlers.RushEnded(payload: any)
	if payload.reason == "Dropped" then
		local record = dependencies().entities.get(payload.entityId)
		if record ~= nil then
			dropAttack(record, payload.launchedAt)
		end
		return
	end
	local rush = rushOf(payload)
	if rush == nil then
		return
	end
	if payload.reason == "Jammed" then
		RushDraw.jam(rush.state, payload.distance)
	elseif payload.reason == "Wall" then
		-- A slam (D-208): the body stops with its snout on the face, where the cue plays.
		local contact = if payload.contact ~= nil then toVector(payload.contact) else nil
		local normal = if payload.normal ~= nil then toVector(payload.normal) else nil
		RushDraw.wall(rush.state, payload.distance, contact, normal)
	else
		RushDraw.stop(rush.state, payload.distance, payload.serverTime)
	end
	-- Where the server's body stops: the hand-back waits for the root there (D-210).
	RushDraw.rest(rush.state, payload.distance)
end

function handlers.RushTurned(payload: any)
	local rush = rushOf(payload)
	if rush == nil then
		return
	end
	-- The server's path (D-206, D-207): the drawn body runs it from here on.
	local legs = {}
	for _, leg in payload.legs do
		table.insert(legs, {
			at = leg.at,
			from = toVector(leg.from) * Vector3.new(1, 0, 1),
			heading = toVector(leg.heading),
			facing = toVector(leg.facing),
		})
	end
	RushDraw.turn(rush.state, legs, payload.kind, payload.at, toVector(payload.contact), toVector(payload.normal))
end

-- Plays one death the server sent (EntityDied) that was held for its kill's word.
local function playDeath(payload: any)
	releasingDeath = payload
	handlers.EntityDied(payload)
	releasingDeath = nil
end

-- Plays the held deaths of `entityId` (nil: every one) now, oldest first.
local function releaseDeaths(entityId: number?)
	local index = 1
	while index <= #heldDeaths do
		local death = heldDeaths[index]
		if entityId == nil or death.entityId == entityId then
			table.remove(heldDeaths, index)
			playDeath(death)
		else
			index += 1
		end
	end
end

-- The held deaths of `entityId`, taken from the list for the kill's word that holds them.
local function takeDeaths(entityId: number): { any }?
	local taken: { any }? = nil
	local index = 1
	while index <= #heldDeaths do
		local death = heldDeaths[index]
		if death.entityId == entityId then
			table.remove(heldDeaths, index)
			taken = taken or {}
			table.insert(taken :: { any }, death)
		else
			index += 1
		end
	end
	return taken
end

-- A held death's shatter comes as late as its word may wait: what goes with the body (its plate,
-- whose own time began with the Dead state) waits for it, never leaving before the body (D-187).
local function expectLate(payload: any)
	local d = dependencies()
	local record = d.entities.get(payload.entityId)
	local expect = method(d.shatter, "expect")
	if record ~= nil and expect ~= nil then
		expect(record.model, Combat.contact.wordWaitSeconds + Moments.deathDuckDelay() + Combat.deathFreeze)
	end
end

-- True when this EntityDied is held for its kill's word (D-267 amended): a kill word already held
-- for its key takes it along; a death a player dealt while words may wait waits for the word the
-- server sends right after it. The local fighter's own death is never held.
local function holdsDeath(payload: any): boolean
	if payload == releasingDeath then
		return false
	end
	for _, word in heldWords do
		if word.payload.targetId == payload.entityId and word.payload.killed == true then
			local deaths = word.deaths or {}
			table.insert(deaths, payload)
			word.deaths = deaths
			expectLate(payload)
			return true
		end
	end
	local d = dependencies()
	if not playTicking or d.keyAhead == nil or payload.byPlayer ~= true or payload.entityId == d.localId() then
		return false
	end
	table.insert(heldDeaths, payload)
	expectLate(payload)
	return true
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
		expirePredictions(seen)
		dropStale(earlyConfirms, seen)
		predicted = takeMatch(predictions, payload.targetId, payload.hitIndex, payload.artId, payload.swing)
		-- The server counts a swing's windows in order: a word for a later window of the swing says
		-- an earlier one still waiting was not counted, and its hold waits no more (D-CH1).
		for _, other in predictions do
			if
				other.waiting
				and typeof(payload.hitIndex) == "number"
				and other.windowIndex < payload.hitIndex
				and other.artId == payload.artId
				and (other.swing == nil or payload.swing == nil or other.swing == payload.swing)
			then
				other.waiting = false
			end
		end
		if predicted == nil and payload ~= releasing and waitsForKey(payload) then
			-- Before the blade showed the key: the hold starts on the key frame (D-267), and a kill's
			-- freeze, silence and shatter with it (its EntityDied came just before it).
			local deaths = if payload.killed == true then takeDeaths(payload.targetId) else nil
			table.insert(heldWords, { payload = payload, seen = seen, deaths = deaths })
			return
		end
		if predicted == nil then
			table.insert(earlyConfirms, {
				targetId = payload.targetId,
				windowIndex = payload.hitIndex,
				artId = payload.artId,
				swing = payload.swing,
				seen = seen,
			})
		end
	end
	-- A death held for this word plays first, as it came (D-267 amended), on its contact's beat.
	if #heldDeaths > 0 then
		releasingContactAt = if predicted ~= nil then predicted.at else nil
		releaseDeaths(payload.targetId)
		releasingContactAt = nil
	end
	-- An enemy's blow on the local fighter shown on its strike frame (D-258): this word brings the
	-- number and what it adds; one that guards or parries took the flinch back.
	local shown: Struck? = nil
	if localId ~= nil and payload.targetId == localId and payload.attackerId ~= nil then
		shown = heardStrike(payload)
	end
	-- The pause the server gave the target's attack (D-172): a contact's provisional share gives way
	-- to it; a hit nobody predicted brings it whole. Absent: none (no open attack, or a kill).
	local serverPause = if typeof(payload.attackPause) == "number" then payload.attackPause else 0
	-- How much more the server's tier holds than the contact did (0: nothing to add).
	local upgrade = if predicted ~= nil
		then (if Combat.hitStopFrames[tier] ~= nil then tierRank(tier) - tierRank(predicted.tier) else 0)
		else 0

	if predicted ~= nil then
		if attacker ~= nil and predicted.run == holdRun then
			-- The contact's hold, while it is still on or waits for this word (D-CH1), runs on to the
			-- stronger tier's length from the contact, never restarted: a Kill that comes inside a
			-- Normal's hold, or while the hold waits for it, is one unbroken freeze. One that already
			-- let go is not stopped again: a hit holds once (issue 6), and a later cut's hold is
			-- that cut's own; the stronger tier still sounds and shows below.
			local animator = animatorOf(attacker)
			local remaining = holdRemaining(animator, predicted.asked, predicted.at)
			if remaining > 0 or predicted.waiting then
				-- What the hold has shown since the contact: all it asked for, less what is left.
				local held = math.max(0, predicted.asked - remaining)
				local upgraded = if upgrade > 0 then heldFrames(frames) * ChoreoData.frameSeconds - held else 0
				-- The frame that first shows the number is held, whether the word came before this
				-- frame's render step or after it, on every rig that held on for the word.
				local wordFrame = if predicted.waiting then beatStep else 0
				local left = math.max(upgraded, wordFrame)
				if left > remaining + ChoreoData.pauseEpsilon then
					animator:hitStop(left / ChoreoData.frameSeconds)
					holdEnds = math.max(holdEnds, clock() + left)
				end
				if target ~= nil and target ~= attacker and not rushRunning(target.id) then
					local attack = attacks[target.id]
					local targetLeft = if attack ~= nil and attackOpen(attack) then upgraded else left
					if targetLeft > 0 then
						animatorOf(target):hitStop(targetLeft / ChoreoData.frameSeconds)
					end
				end
			end
		end
		-- A contact before this client knew of the attack (its telegraph still on the way) stood
		-- for no pause: the server's comes whole, to the attack known now.
		local attack = predicted.attack
		if attack == nil and target ~= nil and serverPause > 0 then
			attack = attacks[target.id]
		end
		if target ~= nil and attack ~= nil then
			shiftAttack(target, attack, serverPause - predicted.allowance)
		end
	elseif payload.parried ~= true then
		-- A parry holds neither rig (D-257): the Inverted frame is the clash, and the deflect and the
		-- stagger start on it (F8); the clips author their own hold on the clash.
		if attacker ~= nil then
			if payload.attackerId == localId then
				holdLocal(animatorOf(attacker), frames)
			elseif attacker.kind == "Enemy" then
				holdStriker(attacker, frames)
			else
				animatorOf(attacker):hitStop(heldFrames(frames))
			end
		end
		if target ~= nil and target ~= attacker then
			if payload.targetId == localId then
				-- A blow shown on its strike frame holds nothing now: its flinch is under way (D-258).
				if shown == nil then
					holdLocal(animatorOf(target), frames)
				end
			elseif target.kind == "Enemy" then
				holdTarget(target, frames)
				local attack = attacks[target.id]
				if attack ~= nil and serverPause > 0 then
					shiftAttack(target, attack, serverPause)
				end
			else
				animatorOf(target):hitStop(heldFrames(frames))
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
		if predicted == nil and shown == nil and d.impact.ownsHighlight(info) ~= true and not breaksGuard then
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
				-- During its attack the weapon arm stays on the attack (D-173).
				local mask = attackFlinchMask(target)
				if mask ~= nil then
					animatorOf(target):play(flinch, { mask = mask })
				else
					animatorOf(target):play(flinch)
				end
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
	if shown ~= nil then
		-- Only what the word adds to the moment shown on the strike frame (a kill's), D-258.
		local moment = shown.moment
		if moment ~= nil then
			d.impact.hit(info, moment)
		end
	elseif predicted == nil then
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
		attacks[record.id] = nil
		-- A rush not launched never will be; a launched one stops where it is drawn until its
		-- RushEnded says where the server's body stopped (D-171).
		local rush = rushes[record.id]
		if rush ~= nil then
			local now = serverClock()
			if now == nil then
				endRush(record.id)
			elseif not rush.launched then
				-- No RushStarted came before this (both reliable, in order): the server never
				-- launched it. The crouch keeps its turn until the late root comes round; a launch
				-- this client predicted slides back (D-255).
				releaseRush(record.id)
			else
				RushDraw.halt(rush.state, now)
			end
		end
	end
	local clipName = stateClipName(payload.state, payload.direction, isLocal)
	if clipName ~= nil then
		-- The flinch of a blow shown on its strike frame plays on (D-258).
		if not (payload.state == "Stagger" and flinchShown(record.id)) then
			playReaction(record, clipName)
		end
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
	-- A kill whose word waits for its strike's key freezes, falls silent and shatters with it.
	if holdsDeath(payload) then
		return
	end
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
		-- A rush's body dies where it is drawn: it stays there for the freeze and the shatter (D-171).
		attacks[record.id] = nil
		local rush = rushes[record.id]
		if rush ~= nil and not RushDraw.freeze(rush.state) then
			endRush(record.id)
		end
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
	-- A kill the local blade already touched counts its hit-stop from that contact frame (D-CH2):
	-- its word came a latency later, inside the hold, so the silence and the shatter keep the
	-- contact's beat, as they do when the word comes first.
	local lead = Moments.deathDuckDelay()
	local function fromContact(at: number)
		local since = diedAt - at
		if since >= 0 and since < Moments.deathDuckDelay() then
			lead = math.min(lead, Moments.deathDuckDelay() - since)
		end
	end
	if releasingContactAt ~= nil then
		fromContact(releasingContactAt :: number)
	end
	for _, prediction in predictions do
		if prediction.targetId == payload.entityId then
			fromContact(prediction.at)
		end
	end
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
	if record ~= nil then
		-- What goes with the body (its plate) waits for this shatter's hide, on the clock it is
		-- scheduled on, not on a timer of its own that runs a frame ahead of it (D-187).
		local expect = method(d.shatter, "expect")
		if expect ~= nil then
			expect(record.model, lead + Combat.deathFreeze)
		end
	end
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

-- Plays held word `index` (D-267): the server's word for a hit whose strike key this client's
-- clip now shows.
local function letGo(index: number)
	local word = table.remove(heldWords, index)
	if word == nil then
		return
	end
	-- A kill's death first, as the server sent them (D-267 amended).
	local deaths = word.deaths
	if deaths ~= nil then
		for _, death in deaths do
			playDeath(death)
		end
	end
	releasing = word.payload
	handlers.HitConfirmed(word.payload)
	releasing = nil
end

--- Plays the server's held words (D-267) once this client's clip showed their strike's key, the
--- swing stopped or changed, or they waited combat.contact.wordWaitSeconds of play. Every
--- Heartbeat, after the render step that moved the clip: the hold starts on the frame after the key
--- frame, the key pose being what freezes. A kill's word plays its death just before it, and a
--- death no held word took (another fighter's kill, a word that did not wait) plays now.
function Replication.stepWords()
	if deps == nil then
		return
	end
	releaseDeaths(nil)
	local now = playClock()
	local index = 1
	while index <= #heldWords do
		local word = heldWords[index]
		if now - word.seen > Combat.contact.wordWaitSeconds or not waitsForKey(word.payload) then
			letGo(index)
		else
			index += 1
		end
	end
end

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
	-- The target's hold stands for the pause the server will give its attack until the server says
	-- (D-172); a launched rush is not held (the server holds nothing of it).
	local allowance, attack = 0, nil
	if target.kind == "Enemy" then
		allowance, attack = allowPause(target, holdTarget(target, frames))
	else
		animatorOf(target):hitStop(heldFrames(frames))
	end
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
	expirePredictions(seen)
	table.insert(predictions, {
		targetId = contact.targetId,
		windowIndex = contact.windowIndex,
		artId = contact.artId,
		swing = if typeof(contact.swing) == "number" then contact.swing else nil,
		at = clock(),
		seen = seen,
		run = run,
		tier = tier,
		moment = if typeof(moment) == "string" then moment else nil,
		allowance = allowance,
		attack = attack,
		asked = heldFrames(frames) * ChoreoData.frameSeconds,
		-- Its hold waits for its word only on a client that ticks Heartbeat (holdForWords).
		waiting = playTicking,
	})
	-- The server's word for this hit, held for its key (D-267), plays on it now: it finds the
	-- contact just played and adds only what its tier adds.
	for index, word in heldWords do
		local payload = word.payload
		if
			payload.targetId == contact.targetId
			and payload.hitIndex == contact.windowIndex
			and payload.artId == contact.artId
			and (payload.swing == nil or contact.swing == nil or payload.swing == contact.swing)
		then
			letGo(index)
			break
		end
	end
	return true
end

--- True for a root part a rush draws its body away from (D-171): the body is not there, so the
--- local blade's contact prediction does not test it.
function Replication.drawnAway(part: Instance): boolean
	for _, rush in rushes do
		if rush.root == part and rush.shownAs ~= nil then
			return true
		end
	end
	return false
end

--- True when the server already confirmed this hit of the local fighter's (it came before the
--- blade got there on this client): the predictor skips it, so nothing plays twice. Each
--- confirmation answers once.
function Replication.confirmedAlready(targetId: number, windowIndex: number, artId: string?, swing: number?): boolean
	if deps == nil then
		return false
	end
	dropStale(earlyConfirms, playClock())
	return takeMatch(earlyConfirms, targetId, windowIndex, artId, swing) ~= nil
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

-- True when every handle of `clipId` on the rig was stopped before its end: the clip was taken
-- away (the server's Stagger, a cancelled hold, a refused swing) and fades out where it stands,
-- its clock still running. What that fade crosses only closes (F5): no tell, chime, trail or
-- smear starts on a clip the rig no longer plays. A clip that ran to its own end is not one.
local function takenAway(record: any, clipId: string): boolean
	local animator = animatorOf(record)
	local mixer = if typeof(animator) == "table" then animator.mixer else nil
	if typeof(mixer) ~= "table" or typeof(mixer.handles) ~= "function" then
		return false
	end
	local found = false
	for _, handle in mixer:handles() do
		if handle.clipId == clipId then
			if not handle.stopping or handle.ended then
				return false
			end
			found = true
		end
	end
	return found
end

--- Routes one clip event on a rig to the FX and audio packages (trails, smear, activation light,
--- footsteps, clip sounds). `jumped`: a render stall's gap crossed it (D-132); only what it closes
--- runs, as for a clip taken away (F5).
function Replication.routeClipEvent(record: any, clipId: string, event: any, jumped: boolean?)
	local d = dependencies()
	local model = record.model
	local kind = event.kind
	local closing = takenAway(record, clipId)
	local starts = jumped ~= true and not closing
	if kind == "HitWindowOpen" or kind == "TrailOn" then
		-- A jumped one still names the clip's trail kind for the events after it.
		local trailKind = resolveTrailKind(record, clipId, event)
		if starts then
			d.trails.setActive(model, true, trailKind)
		end
		if kind == "HitWindowOpen" then
			-- A clip taken away lets the light it lit fade, as a cancelled hold's does (F5).
			d.trails.activationLight(model, false, d.trailToken(record), closing)
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
	endRush(record.id)
	attacks[record.id] = nil
	launches[record.id] = nil
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
	table.clear(heldWords)
	releasing = nil
	table.clear(heldDeaths)
	releasingDeath = nil
	for id in rushes do
		endRush(id)
	end
	table.clear(attacks)
	table.clear(launches)
	table.clear(struck)
	holdRun = 0
	holdEnds = -math.huge
	playSeconds = 0
	playWall = nil
	beatAt = nil
	beatStep = ChoreoData.frameSeconds
	playTicking = typeof(newDeps.onHeartbeat) == "function"
	if playTicking then
		local onHeartbeat = newDeps.onHeartbeat :: any
		onHeartbeat(function(dt: number?)
			-- The step this Heartbeat closes: the engine's, else the clock's since the last one.
			local now = clock()
			local last = beatAt
			beatStep = if typeof(dt) == "number" and dt > 0
				then dt
				elseif last ~= nil and now > last then now - last
				else ChoreoData.frameSeconds
			beatAt = now
			tickPlay()
			-- Enemy blows on the local fighter, judged on their strike frames (D-258).
			Replication.stepStrikes()
			-- The server's words held for their strike's key (D-267).
			Replication.stepWords()
			-- Contacts' holds waiting for their words (D-CH1).
			holdForWords(beatStep)
		end)
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

local castParams: RaycastParams? = nil

-- workspace:Blockcast with the parts that collide with `group` and can collide, as the server's
-- worldAhead casts (EnemyService defaultWorldCast): a hitbox or an effect is not a wall.
local function worldCast(
	start: CFrame,
	size: Vector3,
	vector: Vector3,
	group: string,
	exclude: Instance
): (number?, Vector3?)
	local params = castParams
	if params == nil then
		local created = RaycastParams.new()
		created.FilterType = Enum.RaycastFilterType.Exclude
		created.RespectCanCollide = true
		castParams = created
		params = created
	end
	local query = params :: RaycastParams
	query.FilterDescendantsInstances = { exclude }
	query.CollisionGroup = group
	local result = workspace:Blockcast(start, size, vector, query)
	if result == nil then
		return nil, nil
	end
	return result.Distance, result.Normal
end

-- The states a defence stands in on the server a latency after the client lets it go (D-258).
local DEFENDING: { [string]: boolean } = { Guard = true, Dodge = true }

-- The local fighter's defence from CharacterController (D-258): its state now, and the os.clock time
-- it last left a guard or a dodge. Nil when the controller is missing (a stub): nothing is shown
-- before the server's word then.
local function defenceOf(controller: any): (() -> (string, number?))?
	if typeof(controller) ~= "table" or Siblings.isStub(controller) then
		return nil
	end
	local state = rawget(controller, "state")
	local changed = rawget(controller, "stateChanged")
	if typeof(state) ~= "function" or typeof(changed) ~= "table" then
		return nil
	end
	local current = state()
	local leftAt: number? = nil
	changed:Connect(function(nextState: string)
		if DEFENDING[current] == true then
			leftAt = os.clock()
		end
		current = nextState
	end)
	return function(): (string, number?)
		return state(), leftAt
	end
end

-- CharacterController.awaitsKey (D-267), or nil when the controller is missing (a stub): the
-- server's word then plays when it comes.
local function keyAheadOf(controller: any): ((windowIndex: number, artId: string?, swing: number?) -> boolean)?
	if typeof(controller) ~= "table" or Siblings.isStub(controller) then
		return nil
	end
	local awaitsKey = rawget(controller, "awaitsKey")
	return if typeof(awaitsKey) == "function" then awaitsKey else nil
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
	local controller = Siblings.load(script.Parent, "CharacterController")
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
		wallSlam = Siblings.load(Client, "fx.WallSlam"),
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
			-- Sounds sit on the drawn body, ahead of a rush's hidden root (D-193).
			local drawn = Siblings.call(DrawnBody, "position", model)
			if drawn ~= nil then
				return drawn
			end
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
		serverNow = function(): number
			return workspace:GetServerTimeNow()
		end,
		worldCast = worldCast,
		-- Loaded by name: CharacterController requires this module.
		localDefence = defenceOf(controller),
		keyAhead = keyAheadOf(controller),
	})
	Replication.subscribe()
end

return Replication
