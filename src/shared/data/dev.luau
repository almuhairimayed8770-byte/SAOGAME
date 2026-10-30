--!strict
--[[
	Dev tooling numbers (section 1 "How you work", section 10 "Review loop", section 19 tools).
	Everything the capture prompts, the ClipLab review scene, the PoseEditor plugin, the pose
	server and the animation review report use lives here: hotkeys, panel layout, the review
	frame budgets, the gate shot list and the clip file-name convention.

	None of this ships to players: Capture and ClipLab run only when the place carries the
	workspace attribute named below (set in places/Playground.project.json and ClipLab), the Studio
	hooks DevAim and DevCombat (aim, trace) also need RunService:IsStudio(), and the PoseEditor is
	a Studio plugin. Hotkeys are Enum.KeyCode names and never a function key: F9 is
	the developer console, F5 to F8 are Studio's play controls, F11 and F12 are fullscreen and
	screenshot. Nor is any dev key one Studio keeps for itself while "Respect Studio shortcuts when
	game has focus" is on (I, O, Home, End, PageUp, PageDown, F1, F2, F11, F12): pressed in Play it
	never reaches the game (tools/validators/dev.luau). Letters that input.luau binds (Q, E, F, R,
	Tab, Space, 2, 3, 4, Shift) are avoided in the Playground, where gameplay input is live.

	Times are seconds, sizes are pixels at UI scale 1, distances are studs, angles are degrees,
	colors are palette tokens.
]]

-- One enemy a staged shot puts in front of the player (capture.stage, F12). Spawned fresh for the
-- shot, so its home is where it stands (its leash never walks it off) and its HP is full.
export type StagedEnemy = {
	enemy: string, -- enemies.luau def id
	distance: number, -- studs, root to root, flat, from the player
	side: number, -- degrees off the player's facing to it (+ = left)
	held: boolean, -- true: stands still and never attacks; false: let go as the take starts
	-- A let-go enemy only: let go this many seconds after the take starts, not at its start (the
	-- server times it from the "go"; the fight's boar joins after the kobold's third overhead).
	releaseAfter: number?,
	-- Its HP after staging (the kill shot), clamped to [1, maxHp] by the server, and set again as
	-- it is let go, so it comes in at this HP however long it stood held (CF).
	hp: number?,
	-- A let-go enemy only: the attacks it may begin; once it has begun this many it is held at the
	-- first moment it is free (EnemyService.limitAttacks, FK2), so the last one, a stagger after it
	-- and its recovery play out whole and no next wind-up starts inside the take. Nil: no limit.
	attacks: number?,
	-- A released Charger only (the validator asks for it): what its first charge does to a player
	-- standing on the spot, and what the shot's prompts tell them. "Meets": the telegraphed line
	-- (attack reach) reaches them and the rush hits. "Passes": the line ends short of their body and
	-- the overshoot carries the boar on over them, no hit (D-166).
	charge: ("Meets" | "Passes")?,
}

-- A staged shot's set-up (DevStage.server.luau): every field enemy held (never mid-attack) and
-- moved stage.awayStuds off the stand spot (stage.area, or on top of the ledge when `open`). The
-- staging never moves the player (D-244): one standing outside the stand ring is told to walk
-- into it first; one inside it is healed and `enemies` spawn around where it stands and faces,
-- held; the first one is the shot's target.
export type ShotStage = {
	open: boolean, -- the locomotion pass: on top of the ledge in the open, not at stage.area
	enemies: { StagedEnemy },
	lock: boolean, -- the take starts locked on the target (TargetController.lockOn)
}

-- What the camera does during a take: the lock camera, or one of capture.cameras.
export type ShotCamera = "Lock" | "Side" | "ThreeQuarter" | "Behind" | "Rear" | "Open"

-- One line of the on-screen prompt: shown from `at` seconds into the take until the next one.
export type PromptBeat = { at: number, text: string }

-- One key auto-perform presses after a reaction (Perform.chain), `delay` seconds after the key
-- before it came up (the reaction's own, then each step's): `action` held `hold` seconds, a Move
-- held until its lock target is `within` studs (flat) or `hold` passes. `cycle` (Arts) presses
-- the next of its actions each time the step comes round, the first being `action`; a reaction
-- heard while the step's Art is held cancels it and gives its turn back (EF). A LockOn step
-- locks staged enemy `enemy` (stage.enemies index) and never lets a lock go. Nothing of the step
-- or what follows it goes down past `to` seconds into the take (EF), nor past its reaction's.
export type PerformStep = {
	action: string,
	hold: number,
	delay: number,
	enemy: number?,
	cycle: { string }?,
	stick: { number }?,
	sprint: boolean?,
	within: number?,
	to: number?,
}

-- One key auto-perform presses through the real input path (InputController.handle, as the key's
-- own binding does): `action` is an input.luau action, held `hold` seconds, or capture.perform's
-- moveAction, the stick: Humanoid:Move each frame `stick` = { right, forward } on the camera's
-- view (a length of 1 is a held key, less is a part-pushed stick: the walk), with the sprint held
-- too when `sprint`. Exactly one of these times it:
-- - `at`: it goes down `at` seconds into the take;
-- - `onClip`: a reaction, `lead` seconds before the HitWindowOpen of the clip `onClip` as the
--   client draws it on staged enemy `enemy` (stage.enemies index, 1 when nil), a Guard the way
--   up earlier still (what the staging's replies read, else Telegraphs.glintLead, D-289; D-319,
--   EF): the first play only, or each
--   one when `repeats`. Every later event of the play heard moves the moment with it (the client
--   holds an attack's clip through its attacker's hit-stop). With `lock` the lock goes to that
--   enemy when its clip is heard (a guard must face its attacker). Its `chain` steps follow it; a
--   reaction heard drops the steps left of the one before it. Nothing of it, its chain included,
--   goes down past `to` seconds into the take (D-320), so what it launches lands before the cut;
-- - `every`: a standing rule, pressed every `every` seconds from `from` to `to` while no
--   reaction waits or chain runs: a BasicAttack while the lock's target stands within `within`
--   studs (flat; the attack in between), a LockOn on staged enemy `enemy` while the lock is off.
export type Perform = {
	action: string,
	hold: number,
	at: number?,
	onClip: string?,
	lead: number?,
	enemy: number?,
	repeats: boolean?,
	lock: boolean?,
	chain: { PerformStep }?,
	every: number?,
	from: number?,
	to: number?,
	within: number?,
	stick: { number }?,
	sprint: boolean?,
}

export type Shot = {
	id: string, -- file stem: docs/clips/phase-0/<id>.mp4
	title: string,
	seconds: number, -- target length of the recording; the take stops itself there
	notes: string, -- what the reviewer must be able to see
	stage: ShotStage,
	camera: ShotCamera,
	cameraSide: number, -- 1: the camera on the player's right of the line, -1 on its left
	prompts: { PromptBeat }, -- sorted by `at`, the first at 0
	perform: { Perform }, -- auto-perform's presses (the toggle is off by default)
}

-- A staged view (CameraController.setStage). The camera stands `distance` studs (flat) from its
-- anchor and `height` above it, at a bearing `degrees` off the reference toward cameraSide, and
-- aims `lookHeight` above the point `focusBias` of the way from the player to the target. The
-- reference: Line, 0 behind the anchor on the line between the fighters; Facing, 0 behind the
-- anchor's own facing; World, 0 at +Z of the anchor (90 at +X). The anchor: the player's root,
-- the target's drawn body, or the middle of the two. The aim never comes nearer the lens than the
-- anchor, and the bearing turns no faster than camera.luau lock.maxTurnDegreesPerSecond. A `fixed`
-- view stands still in the world: once the player and the target have stood where the staging put
-- them (camera.luau stage), it holds that spot and aim through the take.
export type StageCamera = {
	anchor: "Player" | "Target" | "Middle",
	reference: "Line" | "Facing" | "World",
	degrees: number,
	distance: number,
	height: number,
	focusBias: number,
	lookHeight: number,
	fixed: boolean?,
}

local Dev = {
	-- Workspace attributes that switch the dev scripts on (set in the dev place project files).
	attributes = {
		capture = "DevCapture",
		clipLab = "ClipLab",
		timeScale = "DevTimeScale", -- written by the server from the dev remote; dev places only
	},

	-- The Studio frame-rate cap (DevFrameCap.client.luau, Studio item 303: Studio's own menu offers
	-- no 30): set the Workspace attribute to a number of frames a second from least to most and
	-- every frame is held to that rate; no attribute (or one out of range) holds nothing. Its
	-- render step runs after every step that draws the frame (camera.luau renderOrder.late is Last).
	frameCap = {
		attribute = "DevFrameCap",
		least = 15,
		most = 60,
		priority = { base = "Last", offset = 1 },
	},

	-- Slow motion for review: the capture panel cycles these, the ClipLab offers them as buttons.
	timeScale = {
		steps = { 1, 0.5, 0.25 },
		default = 1,
		remoteName = "DevTimeScale", -- RemoteEvent under ReplicatedStorage, created by the dev server script
		remotePerSecond = 4, -- the server ignores faster requests
		-- The Choreo animators slow down, and in Studio so does the local body's own movement (its
		-- walk, the two-step stop, the lock turn, the snap's whip: CharacterController
		-- .setCaptureTimeScale; never in live play), so its slowed feet keep their ground and its
		-- blend stays the 1x one (a slowed run shows Run); the reel's impact frames, accents,
		-- risers and every sound keep real time, so a slowed recording judges poses, not hit sync.
		-- Every step is above 0 and at most 1 (tools/validators/dev.luau): never faster than play.
		slowNote = "animation only: hit FX and sounds run at 1x",
	},

	-- The Studio aim hook (src/client/dev/DevAim.client.luau, D-114). A Studio MCP execute_luau in
	-- the Client context cannot drive the game's controllers itself: its require returns a fresh
	-- module copy, not the game's live one. So a game LocalScript (Studio and DevCapture only)
	-- puts a BindableFunction under the LocalPlayer, and :Invoke(command, args) runs inside the
	-- game's module cache: it locks through TargetController.lockOn or the F path and swings by
	-- firing InputController's own signals, so every request goes out through CharacterController
	-- (aim snap, rate drop, prediction) and every server check runs unchanged. It reports the body's
	-- yaw off the target at the send, the target's HP before and after, the hits and any
	-- rejection. Every wait is task.wait (Heartbeat): with the Studio display asleep RenderStepped
	-- runs 0 times a second while Heartbeat runs 60. tools/validators/dev.luau ties each number to
	-- the game numbers it waits on.
	aim = {
		bindableName = "SkyspireDevAim",
		-- "lock" waits until the body's flat look is this close to the lock: under combat.luau
		-- aim.snapDegrees, so the swing's own snap finishes the turn.
		faceToleranceDegrees = 10,
		-- ...or this long. The lock turn (aim.lockTurnRate) comes round from straight behind in
		-- 0.25 s while RenderStepped runs; with the display asleep it never comes.
		faceTimeoutSeconds = 1,
		-- "face" turns the root itself on Heartbeat, at the lock turn's rate: the stand-in for the
		-- lock turn when no render step runs. Reported as a dev turn, never as the game's.
		faceDegreesPerSecond = 720,
		-- After a dev turn: the server sees the turned root (its facing check reads the replicated
		-- root) and the client's yaw history (combat.lagAllowance long) holds only the new facing.
		replicationSettleSeconds = 0.25,
		-- Art key press to release: past the start pose and activation hold (0.25), well short of
		-- the cancel time (1.0), so the release launches from the frozen glowing stance.
		artHoldSeconds = 0.35,
		-- Send to send for basic swings: no faster than BasicAttackRequest's refill, after the
		-- server's swing (basicHitDuration) and its hit window plus the lag allowance, and inside
		-- basicChainWindow, so three swings run the Basic1-2-3 chain. A swing's hits are the ones
		-- that arrive before the next swing goes.
		swingGapSeconds = 0.45,
		-- The longest wait for the body to be free before a swing, and for an Art's run (Art,
		-- PostMotion, then free) to end after its release.
		runTimeoutSeconds = 3,
		-- "guard" and "dodge": how long to listen for a rejection.
		actionSettleSeconds = 0.25,
		maxSwings = 10, -- one "swing" command at most
		decimals = 2, -- reported studs, degrees and seconds are rounded to this many places
	},

	-- The Studio combat trace hook (src/server/dev/DevCombat.server.luau, D-114): a BindableFunction
	-- under ServerScriptService, Studio and DevCapture only. "trace" sets CombatService.traceSink
	-- (one compact Output line per closed damage window of a player's run: facing, root look, hits,
	-- the nearest enemy's distance, bearing and blade clearance) and keeps the last keepEvents for
	-- "events"; "basic" and "art" start a swing through the live CombatService and return its
	-- windows' trace; "hp" lists the enemies; "hold" freezes enemies (EnemyService.setHeld and
	-- setHoldNew, D-120); "sethp" and "heal" set HP (EntityService.setHp and heal, D-121). The
	-- last three need no numbers of their own.
	trace = {
		bindableName = "SkyspireDevCombat",
		keepEvents = 60, -- at least aim.maxSwings x the most windows a loadout attack has
		runTimeoutSeconds = 3, -- "basic" / "art" wait at most this long for the run's last window
		printPrefix = "[DevCombat]",
		decimals = 2,
	},

	-- DevCombat "place" (D-143): the safe dev teleport. The server pivots a player's character to a
	-- point (and a facing) and tells the anti-cheat the move was its own
	-- (AntiCheatService.serverMoved): no sample is judged for settleSeconds while the client takes
	-- the new position up and its positions from before the move still arrive, then the next
	-- sample starts fresh. At least a sample interval and the lag allowance (combat.luau), with
	-- room for Studio's simulated replication lag (tests/data/dev.spec.luau).
	place = {
		settleSeconds = 1,
		-- Studs: a position past this on any axis is refused as a typo, not a place in the world.
		maxCoordinate = 10000,
	},

	-- DevCombat's Studio test hooks (D-333), so a Studio check needs no hand-built scene: "enemy"
	-- places a living enemy, "walk" walks one to a point at its own pace, "charge" makes a Charger
	-- rush at a point (EnemyService.place, walk and charge: a server-owned body, no anti-cheat
	-- involved), "part" and "clearparts" make and remove temporary anchored parts (a wall, a 35 to
	-- 45 degree slope, a stair run). Every point is a floor point (an enemy's root goes its rig's
	-- root height above it, as a spawn's does), each axis within place.maxCoordinate.
	-- tools/validators/dev.luau ties each number to the game numbers it waits on.
	hooks = {
		-- "walk" has arrived when the root stands this close to the point (flat studs): under ai.luau
		-- leash.homeRadius, so where it stops is its home and its leash never walks it back.
		arriveStuds = 1,
		-- A longer walk is refused; one not there after walkTimeoutSeconds ends where the body
		-- stands. The timeout gives the slowest walking enemy twice its straight walk.
		maxWalkStuds = 60,
		walkTimeoutSeconds = 30,
		-- "charge" waits at most this long for the rush to be over: past every Charger rush's
		-- wind-up (with the hit-stop pauses it may take) and run.
		chargeTimeoutSeconds = 3,
		-- "part": the folder under Workspace the parts live in and how many it holds at once (a stair
		-- run of 16 steps, a slope and their walls), each side's least and most studs, how late
		-- `after` may make one (a part dropped into a rush's path: at most a charge's wait), how
		-- long a given name may be, and how the parts look.
		folderName = "SkyspireDevParts",
		maxParts = 32,
		minPartStuds = 0.2,
		maxPartStuds = 512,
		maxAfterSeconds = 3,
		maxNameLength = 40,
		partColorToken = "PlaceholderSteel",
		partMaterial = "Slate",
		-- "pack" (item 315): at most this many members, a natural pack's top (playground.luau
		-- packSize) and some, all of whom fit clear of each other in the widest scatter disc.
		maxPackSize = 6,
		-- "place" with onWindUp (302(b)): the move lands `after` seconds into the enemy's next
		-- wind-up, at most maxPlaceAfterSeconds (anywhere in any wind-up, even one hits paused, and
		-- the strike after it); it gives up when no wind-up starts within windUpWaitSeconds (longer
		-- than any enemy's whole attack, so one attacking on a loop starts its next inside it).
		maxPlaceAfterSeconds = 3,
		windUpWaitSeconds = 10,
	},

	-- tools/pose-server.luau (Lune) and the PoseEditor plugin's HttpService calls.
	poseServer = {
		host = "127.0.0.1",
		port = 34873,
		clipsRoute = "/clips",
		healthRoute = "/health",
		maxBodyBytes = 262144,
		requestTimeoutSeconds = 15,
		idSegments = { min = 2, max = 4 }, -- "enemy/Boar/Charge" has 3
	},

	-- The review report (section 10 "Review loop", section 21 gate line 2).
	review = {
		fps = 60,
		outputPath = "docs/ANIMATION_REVIEW.md",
		clipsDirectory = "src/shared/clips",
		-- Section 10 frame budgets for the beats of every attack.
		anticipationFrames = { min = 4, max = 10 },
		snapFrames = { min = 2, max = 4 },
		smearFrames = 2,
		settleFrames = { min = 6, max = 12 },
		-- Trail timing relative to the hit windows: how early the trail may ignite and how late it
		-- may linger before it counts as "trail outside a window".
		trailLeadFramesMax = 6,
		trailLagFramesMax = 8,
		-- How far a hit window may open after its strike's snap starts (or close before the snap
		-- ends) and still cover it. A hundredth of a frame: wide enough for clip times written to
		-- four decimals (0.3333 for frame 20 is 0.002 frames off), narrow enough that an ExpoOut
		-- snap has done at most 3.4% of its arc before the server starts sweeping (a 2-frame snap).
		-- Half a frame would let a window skip about two thirds of a 3-frame snap.
		windowSnapToleranceFrames = 0.01,
		beats = { "Anticipation", "Snap", "Smear", "Hold", "Settle", "Recovery" },
		humanColumns = { "Watched at 0.25x", "Problems seen", "Fixed" },
		-- The body review (src/client/dev/ClipAudit.luau; section 10 "Review loop", section 21 gate
		-- line 4: no popping limb or sliding foot in any clip). Every attack and one-shot is played
		-- through the real Mixer on the real rig, the way the game plays it, sampled at each of
		-- `sampleHz` (a 60 fps frame and every frame of the 0.25x review), and measured per 60 Hz
		-- frame. tools/animation-review.luau writes what breaks these into the Problems column and
		-- tests/choreo/ClipAudit.spec.luau fails on it.
		audit = {
			sampleHz = { 60, 240 },
			-- A pop: a body part turning more than this in one 60 Hz frame, in the root part's frame,
			-- outside a strike's snap (the snap is the fastest motion in the game on purpose). 20 deg
			-- a frame is 1200 deg/s: a settle's overshoot spring or a fast guard raise stays under it,
			-- a limb that reaches its key in one frame (an ExpoOut key a frame or two long out of a
			-- far pose) does not.
			popDegrees = 20,
			-- Steps under this are left out of the report (it lists only what a reader may look at).
			reportDegrees = 8,
			-- No limb visibly inside the body: the deepest one part may sink into another it is not
			-- jointed to (boxes of the rig's part sizes, the head its drawn size), a tenth of a limb's
			-- width (the stride code's own bar for a foot that moves: locomotion.stride.slideBar).
			overlapStuds = 0.1,
			-- The weapon in the body (the hand on the hilt and its forearm aside): groundClearance
			-- offBody.heldMargin keeps the sword 0.05 off in the key poses; between them it may brush.
			weaponStuds = 0.1,
			-- Planted feet do not move: a grounded foot's least-moving grounded corner travels at
			-- most this across the field in one frame (the drawn gaits' bar, locomotion.stride.slideBar)
			-- and at most footDriftStuds from where it touched down over the whole plant, and no
			-- corner goes deeper than footSinkStuds below the field.
			footSlideStuds = 0.1,
			footDriftStuds = 0.25,
			footSinkStuds = 0.1,
			-- The anticipation (section 10 beat 1: the weapon pulls the opposite way), one an attack
			-- (the first strike's; a later strike's is reported only). Its chord (where the tip goes
			-- over the beat) against the strike's chord: a cosine at most maxCosine (an angle of 120
			-- deg or more: a pull the eye reads as "the other way", where -0.37 read weak and -0.59
			-- read on the review PC); the tip travels at least minTravel; it never moves faster in a
			-- frame than maxSpeedShare of the snap's peak (the snap is the fastest motion in the game;
			-- a pull at nearly half its speed reads as part of the swing); and from the gameplay
			-- camera it is behind the body for at most maxHiddenShare of the beat.
			anticipation = {
				maxCosine = -0.5,
				minTravel = 1,
				maxSpeedShare = 0.4,
				maxHiddenShare = 0.5,
			},
			-- Section 10 beat 6, then the 0.2 s blend back to locomotion: the weapon's tip comes back
			-- within returnStuds of where the game blends to (the drawn idle's guard) by the end of
			-- the Recovery, so the blend is a settle and not a second swing.
			returnStuds = 2.5,
			-- The Recovery is a stance, not a blade held across the face: the blade passes in front
			-- of the face (inside its width and height, ahead of it) for at most this share of the
			-- Recovery's frames (a cut through the face line on the way to the stance is fine; a
			-- held guard across it is not).
			recoveryFaceShare = 0.5,
			-- Section 10 beats 4 and 5: the blade leaves a hit-stop eased (D-405). On the first frame
			-- the rig moves after a freeze, the weapon's tip moves at most this many studs a second
			-- times the frame (0.25 a 60 Hz frame; Horizontal's QuadIn settle shows 0.11). A Spring
			-- settle out of the hold threw most of the settle into that frame (Rising Arc 1.48 studs).
			afterFreezeTipSpeed = 15,
			-- A cancel (D-408, choreo.luau handOver): the action that cuts a live one takes the body
			-- within snapFrames 60 Hz frames (section 10 beat 2: a snap is 2 to 4 frames). Those frames
			-- are the cut's snap (no pop judged); no part turns back inside them by more than
			-- reportDegrees, and from the frame after them the pop rule holds.
			cancel = {
				snapFrames = 3,
			},
			-- The trace: what plays under the clip starts this long before it, and the trace runs on
			-- this long after the clip's blend-out is done.
			leadSeconds = 0.5,
			settleSeconds = 0.4,
			-- A trace stops here even if the clip never ends (a stuck clock): past the longest a
			-- trace can run (the lead, a chain, the longest clip, its blend-out and the settle).
			maxTraceSeconds = 60,
			-- A looping clip is traced one whole cycle and this far past its wrap.
			loopOverSeconds = 0.05,
			-- Points along the blade the Recovery's face cover is read at.
			segmentSamples = 16,
			-- Where in the drawn idle's cycle and the drawn run's (a share of its cycle) an attack
			-- starts, and how long after a basic the next one starts on the swing's beat
			-- (combat.luau basicHitDuration: the swing's Art state ends). The audit also chains it
			-- mashed, one world.luau BasicAttackRequest refill after the swing (the earliest).
			idlePhases = { 0, 6 },
			runPhases = { 0, 0.5 },
			chainSeconds = 0.35,
			-- The kinds a finding has (the spec's pending list names them).
			kinds = { "Pop", "Overlap", "Weapon", "Slide", "Drift", "Sink", "Anticipation", "Return", "Recovery" },
			-- The clips the audit plays (tests/choreo/ClipAudit.spec.luau, the review's Problems
			-- column): every player attack and every player one-shot (the dodges, guard, parry,
			-- reactions, death, jump, landing, fall, skid and breathing), and every boar and kobold
			-- clip. The player's locomotion loops and the draw and sheathe have their own specs
			-- (Stride, SheathTip, GroundClearance).
			clips = {
				"player/OneHandedSword/Basic1",
				"player/OneHandedSword/Basic2",
				"player/OneHandedSword/Basic3",
				"player/OneHandedSword/Horizontal",
				"player/OneHandedSword/Vertical",
				"player/OneHandedSword/SharpNail",
				"player/OneHandedSword/RisingArc",
				"player/OneHandedSword/DodgeBack",
				"player/OneHandedSword/DodgeForward",
				"player/OneHandedSword/DodgeLeft",
				"player/OneHandedSword/DodgeRight",
				"player/OneHandedSword/Parry",
				"player/OneHandedSword/Guard",
				"player/OneHandedSword/GuardHit",
				"player/OneHandedSword/GuardBreak",
				"player/OneHandedSword/FlinchBack",
				"player/OneHandedSword/FlinchFront",
				"player/OneHandedSword/FlinchLeft",
				"player/OneHandedSword/FlinchRight",
				"player/OneHandedSword/Stagger",
				"player/OneHandedSword/DeathFreeze",
				"player/OneHandedSword/Jump",
				"player/OneHandedSword/Land",
				"player/OneHandedSword/Fall",
				"player/OneHandedSword/Skid",
				"player/OneHandedSword/Breathe",
				"enemy/Boar/Charge",
				"enemy/Boar/Idle",
				"enemy/Boar/Walk",
				"enemy/Boar/Break",
				"enemy/Boar/DeathFreeze",
				"enemy/Boar/FlinchBack",
				"enemy/Boar/FlinchFront",
				"enemy/Boar/FlinchLeft",
				"enemy/Boar/FlinchRight",
				"enemy/Boar/Stagger",
				"enemy/Kobold/Overhead",
				"enemy/Kobold/Idle",
				"enemy/Kobold/Walk",
				"enemy/Kobold/Break",
				"enemy/Kobold/DeathFreeze",
				"enemy/Kobold/FlinchBack",
				"enemy/Kobold/FlinchFront",
				"enemy/Kobold/FlinchLeft",
				"enemy/Kobold/FlinchRight",
				"enemy/Kobold/Stagger",
			},
			-- Per rig: the visible body (HumanoidRootPart is not drawn), the part groups that must
			-- stay out of each other (every a against every b; a jointed pair is left out), the
			-- weapon parts and the body parts they may touch, the tip point the strike is read at
			-- (an attachment, or a part and an offset in it), the feet, the drawn size of a part
			-- smaller than its box (a share of the box on each axis: the R15 head is a 2x1x1 box
			-- under a 1.25 head mesh), what plays under a clip (`idle` as the fallback, `breathing`
			-- additive over it; the player's attacks over `drawnIdle` and out of `drawnRun`), the
			-- basic chain, a clip whose body the server carries (`rush`: an enemies.luau attack) and
			-- the head the Recovery rule reads; `over` (a clip the game plays out of another: a guard
			-- reaction out of the guard, which it stops); `walk` (the enemy walk the server carries at the
			-- rig's walkSpeed), `airborne` (clips played in the air: feet not held to the field),
			-- `slideFree` (clips the controller slides on purpose: their sink is judged, not their
			-- slide) and `views` (where the gameplay camera sees the rig from, each judged: "Behind"
			-- the player, an enemy from the "Front" where the player squares up to it. From behind
			-- an enemy its tell is the Telegraphs' to show, not the pose's: the boar's Charge tusk
			-- is behind its body there for the whole beat, D-402, D-414).
			rigs = {
				PlayerR15 = {
					body = {
						"Head",
						"UpperTorso",
						"LowerTorso",
						"RightUpperArm",
						"RightLowerArm",
						"RightHand",
						"LeftUpperArm",
						"LeftLowerArm",
						"LeftHand",
						"RightUpperLeg",
						"RightLowerLeg",
						"RightFoot",
						"LeftUpperLeg",
						"LeftLowerLeg",
						"LeftFoot",
					},
					pairs = {
						{
							a = {
								"RightUpperArm",
								"RightLowerArm",
								"RightHand",
								"LeftUpperArm",
								"LeftLowerArm",
								"LeftHand",
							},
							b = { "Head", "UpperTorso", "LowerTorso" },
						},
						{
							a = { "RightUpperArm", "RightLowerArm", "RightHand" },
							b = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
						},
						{
							a = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
							b = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
						},
					},
					weapon = { "Weapon", "Guard", "Grip" },
					weaponFree = { "RightHand", "RightLowerArm" },
					tip = { attachment = "TrailEnd" },
					feet = { "LeftFoot", "RightFoot" },
					visible = { Head = { 0.625, 1.25, 1.25 } },
					idle = "player/OneHandedSword/Idle",
					breathing = "player/OneHandedSword/Breathe",
					drawnIdle = "player/OneHandedSword/IdleDrawn",
					drawnRun = "player/OneHandedSword/RunDrawn",
					chain = {
						["player/OneHandedSword/Basic2"] = "player/OneHandedSword/Basic1",
						["player/OneHandedSword/Basic3"] = "player/OneHandedSword/Basic2",
					},
					-- The cancels the game allows (ActionLogic STARTABLE, D-408): the clip that cuts in,
					-- the clip it cuts and how far into that one (0.15 s into an Art is its start-pose
					-- hold, combat.luau startPoseTime). ClipAudit plays each as a "Cancel" plan.
					cancels = {
						{ clip = "player/OneHandedSword/Horizontal", over = "player/OneHandedSword/Basic1", gap = 0.1 },
						{ clip = "player/OneHandedSword/Horizontal", over = "player/OneHandedSword/Basic1", gap = 0.2 },
						{ clip = "player/OneHandedSword/Vertical", over = "player/OneHandedSword/Basic2", gap = 0.1 },
						{ clip = "player/OneHandedSword/SharpNail", over = "player/OneHandedSword/Basic3", gap = 0.1 },
						{ clip = "player/OneHandedSword/DodgeLeft", over = "player/OneHandedSword/Basic1", gap = 0.1 },
						{ clip = "player/OneHandedSword/DodgeRight", over = "player/OneHandedSword/Basic1", gap = 0.1 },
						{ clip = "player/OneHandedSword/DodgeBack", over = "player/OneHandedSword/Basic1", gap = 0.1 },
						{
							clip = "player/OneHandedSword/DodgeForward",
							over = "player/OneHandedSword/Guard",
							gap = 0.5,
						},
						{
							clip = "player/OneHandedSword/DodgeBack",
							over = "player/OneHandedSword/Horizontal",
							gap = 0.15,
						},
						{
							clip = "player/OneHandedSword/DodgeLeft",
							over = "player/OneHandedSword/RisingArc",
							gap = 0.15,
						},
						{ clip = "player/OneHandedSword/Guard", over = "player/OneHandedSword/Basic1", gap = 0.1 },
					},
					-- Played out of the guard (their key 0 is the Guard's pose).
					over = {
						["player/OneHandedSword/Parry"] = "player/OneHandedSword/Guard",
						["player/OneHandedSword/GuardHit"] = "player/OneHandedSword/Guard",
						["player/OneHandedSword/GuardBreak"] = "player/OneHandedSword/Guard",
					},
					head = "Head",
					-- Played in the air (the Humanoid leaves the ground as the Jump starts).
					airborne = { "player/OneHandedSword/Jump", "player/OneHandedSword/Fall" },
					-- The two-step stop's skid: the controller slides the body to a stop under it.
					slideFree = { "player/OneHandedSword/Skid" },
					views = { "Behind" },
				},
				Boar = {
					body = {
						"Torso",
						"Head",
						"Snout",
						"TuskLeft",
						"TuskRight",
						"FrontLeftLeg",
						"FrontRightLeg",
						"BackLeftLeg",
						"BackRightLeg",
						"Tail",
					},
					pairs = {
						{ a = { "FrontLeftLeg", "BackLeftLeg" }, b = { "FrontRightLeg", "BackRightLeg" } },
						{ a = { "FrontLeftLeg", "FrontRightLeg" }, b = { "BackLeftLeg", "BackRightLeg" } },
						{ a = { "Head", "Snout", "TuskLeft", "TuskRight" }, b = { "FrontLeftLeg", "FrontRightLeg" } },
					},
					tip = { part = "Snout", offset = { 0, 0, -0.6 } },
					feet = { "FrontLeftLeg", "FrontRightLeg", "BackLeftLeg", "BackRightLeg" },
					idle = "enemy/Boar/Idle",
					walk = "enemy/Boar/Walk",
					rush = { ["enemy/Boar/Charge"] = { enemy = "FrenzyBoar", attack = "Charge" } },
					views = { "Front" },
				},
				Kobold = {
					body = { "Torso", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg" },
					pairs = {
						{ a = { "LeftArm", "RightArm" }, b = { "Head" } },
						{ a = { "LeftLeg" }, b = { "RightLeg" } },
						{ a = { "LeftArm" }, b = { "RightArm" } },
					},
					weapon = { "Weapon" },
					weaponFree = { "RightArm" },
					tip = { attachment = "TrailEnd" },
					feet = { "LeftLeg", "RightLeg" },
					idle = "enemy/Kobold/Idle",
					walk = "enemy/Kobold/Walk",
					head = "Head",
					views = { "Front" },
				},
			},
		},
	},

	-- The server hit matrix (section 20 Phase 0 gate: "the server registered every hit").
	-- tools/hit-matrix.luau prints it and tests/server/HitMatrix.spec.luau fails on any miss at a
	-- real-fight placement. Every Phase 0 player attack (playground.luau loadout.artSlots, then the
	-- basic chain) and every hit of it is swung through the server's own path (CombatService and
	-- HitSweep over an engine-faithful fake world) at an enemy placed in front of the player.
	-- Distances are studs, root to root on the ground plane; angles are degrees.
	hitMatrix = {
		-- The player character as the engine builds it for a blank avatar (classic blocky R15, body
		-- type and proportion scale 0): part sizes and each joint's rig attachments at scale 1, the
		-- Part0-side position then the Part1-side one (rigs.luau PlayerR15 names the joints). At
		-- scale 1 the feet hang 2.35 below the root's center, so the engine's HipHeight is 1.35.
		-- The matrix scales every part and attachment by rigs.luau PlayerR15.scale the way the
		-- avatar scaling system does once PlaygroundService.applyScale writes the scale values
		-- (width, height, depth on the body and the root; head scale on the head), joins the
		-- parts with AnimationConstraints (the Avatar Joint Upgrade) and stands the feet on the
		-- field, which is where the Humanoid's recomputed HipHeight holds the root.
		avatar = {
			parts = {
				HumanoidRootPart = { 2, 2, 1 },
				LowerTorso = { 2, 0.4, 1 },
				UpperTorso = { 2, 1.6, 1 },
				Head = { 2, 1, 1 },
				RightUpperArm = { 1, 1.1687, 1 },
				RightLowerArm = { 1, 1.0519, 1 },
				RightHand = { 1, 0.3, 1 },
				LeftUpperArm = { 1, 1.1687, 1 },
				LeftLowerArm = { 1, 1.0519, 1 },
				LeftHand = { 1, 0.3, 1 },
				RightUpperLeg = { 1, 1.2166, 1 },
				RightLowerLeg = { 1, 1.1931, 1 },
				RightFoot = { 1, 0.3, 1 },
				LeftUpperLeg = { 1, 1.2166, 1 },
				LeftLowerLeg = { 1, 1.1931, 1 },
				LeftFoot = { 1, 0.3, 1 },
			},
			attachments = {
				Root = { { 0, -0.35, 0 }, { 0, -0.2, 0 } },
				Waist = { { 0, 0.2, 0 }, { 0, -0.8, 0 } },
				Neck = { { 0, 0.8, 0 }, { 0, -0.5, 0 } },
				RightShoulder = { { 1, 0.563, 0 }, { -0.5, 0.3943, 0 } },
				RightElbow = { { 0, -0.3342, 0 }, { 0, 0.2586, 0 } },
				RightWrist = { { 0, -0.5009, 0 }, { 0, 0.125, 0 } },
				LeftShoulder = { { -1, 0.563, 0 }, { 0.5, 0.3943, 0 } },
				LeftElbow = { { 0, -0.3341, 0 }, { 0, 0.2587, 0 } },
				LeftWrist = { { 0, -0.5009, 0 }, { 0, 0.125, 0 } },
				RightHip = { { 0.5, -0.2, 0 }, { 0, 0.4208, 0 } },
				RightKnee = { { 0, -0.4009, 0 }, { 0, 0.3792, 0 } },
				RightAnkle = { { 0, -0.5472, 0 }, { 0, 0.1019, 0 } },
				LeftHip = { { -0.5, -0.2, 0 }, { 0, 0.4208, 0 } },
				LeftKnee = { { 0, -0.4011, 0 }, { 0, 0.379, 0 } },
				LeftAnkle = { { 0, -0.5472, 0 }, { 0, 0.1019, 0 } },
			},
		},
		-- Where the first server frame after the swing starts lands, as a fraction of a 60 Hz frame:
		-- the clip clock and the Heartbeat are not in step, so every hit is swung at each phase and
		-- must register at all of them.
		framePhases = { 0, 0.25, 0.5, 0.75 },
		-- The local client's frame rates each swing is also drawn at (fix F2: the client predicts
		-- the hit from the frames it renders; a hit it draws must register at every server phase).
		clientFps = { 30, 60, 144 },
		-- How finely the report traces the true blade to say how close it came to a target it missed.
		clearanceSampleHz = 600,
		-- Real-fight ranges are written rounded inward to this step (the spec re-derives them).
		rangeStep = 0.05,
		-- The vertical span of the player's body the "nearest surface" is measured from (studs above
		-- the ground: the avatar's feet to above its head).
		bodyColumnHeight = 8,
		-- Each setup stands one enemy in front of the player, its root on the line straight ahead.
		-- yaw turns the enemy from facing the player toward its own left (90: side-on, the head
		-- pointing to the player's right). A real fight stands between realFight.min, where the
		-- two bodies touch (any enemy body part, its held weapon aside, against the player's rest
		-- pose), and realFight.max, where the nearest point of the enemy's body is the loadout
		-- weapon's reach (weapons.luau) from the player's root: the idea enemy strikes use for
		-- their reach (HitSweep.coneTargets: distance minus the target's radius), measured to the
		-- nearest body point rather than the root part's half-extent, which only widens the range
		-- the matrix must cover. `distances` are the placements swung at; the ones outside
		-- realFight are reported, never required.
		setups = {
			{
				id = "BoarFacing",
				enemy = "FrenzyBoar",
				yaw = 0,
				-- The snout reaches 5.6 in front of the root, the player's chest 0.475 in front of
				-- his: they touch at 6.075. The snout tip is at reach (4.5) from 10.1.
				realFight = { min = 6.1, max = 10.1 },
				distances = { 6.1, 7, 8, 9, 10.1, 11.5 },
			},
			{
				id = "BoarSide",
				enemy = "FrenzyBoar",
				yaw = 90,
				-- The flank (torso and legs) is 1.3 from the boar's root: touching at 1.775, at reach
				-- from 5.8. The Charger's counter (section 9: sidestep, hit the flank).
				realFight = { min = 1.8, max = 5.8 },
				distances = { 1.8, 2.5, 3.5, 4.5, 5.8, 7 },
			},
			{
				id = "Kobold",
				enemy = "KoboldAxeman",
				yaw = 0,
				-- The head reaches 0.75 in front of the root and meets the player's (0.53) at 1.28;
				-- the body is at reach from 5.25. 3.5 is where the Brute stops walking in (ai.luau
				-- stopDistance) and 4.8 where it starts its overhead (reach 6 x engageFraction 0.8).
				realFight = { min = 1.3, max = 5.25 },
				distances = { 1.3, 2.3, 3.5, 4.8, 5.25, 6.5 },
			},
			-- Point-blank (fix F2): the enemy at the player's shoulder, `bearing` degrees right of the
			-- look (negative: left), outside the aim assist's cone (combat.aim.assistConeDegrees), so
			-- nothing turns the body to it. 75 degrees puts it inside the blade's start pose: the
			-- Horizontal, Sharp Nail's last cut and the first basic start with the blade out to the
			-- right (its guard at 80 to 127 degrees), the Rising Arc's first cut to the left (-62 to
			-- -108). Its hits are reported, never required (`pointBlank`); every hit the client
			-- draws there must still register, and every one that registers must be drawn. The
			-- range is derived along the bearing as above: the kobold's body touches the player's
			-- arm at 2.55 (its head reaches 0.75 in front of its root), the side-on boar's flank at
			-- 3.25.
			{
				id = "KoboldRightShoulder",
				enemy = "KoboldAxeman",
				yaw = 0,
				bearing = 75,
				pointBlank = true,
				realFight = { min = 2.55, max = 5.25 },
				distances = { 2.55, 3, 3.5, 4.2, 5.25 },
			},
			{
				id = "KoboldLeftShoulder",
				enemy = "KoboldAxeman",
				yaw = 0,
				bearing = -75,
				pointBlank = true,
				realFight = { min = 2.55, max = 5.25 },
				distances = { 2.55, 3, 3.5, 4.2, 5.25 },
			},
			{
				id = "BoarRightShoulder",
				enemy = "FrenzyBoar",
				yaw = 90,
				bearing = 75,
				pointBlank = true,
				realFight = { min = 3.25, max = 5.8 },
				distances = { 3.25, 3.75, 4.5, 5.8 },
			},
			{
				id = "BoarLeftShoulder",
				enemy = "FrenzyBoar",
				yaw = 90,
				bearing = -75,
				pointBlank = true,
				realFight = { min = 3.25, max = 5.8 },
				distances = { 3.25, 3.75, 4.5, 5.8 },
			},
		},
	},

	-- Ground clearance (tests/choreo/GroundClearance.spec.luau): no player clip drives the sword
	-- into the ground. Every clip of the loadout weapon's category is posed on the hit matrix's
	-- player (hitMatrix.avatar above, feet on the Playground field) at sampleHz and at every key
	-- time, and fails when the blade's tip or guard end (TrailEnd / TrailStart) sinks below the
	-- field's top face by more than bladeMargin, or any corner of a hand goes below it.
	groundClearance = {
		-- Every frame of the 0.25x review loop (section 10), and of a 240 Hz display at 1x. At 60 Hz
		-- the first frame of an ExpoOut key, where most of its motion happens, and the peak of a
		-- BackOut or Spring overshoot fall between samples: a side dodge authored with its point
		-- 0.23 stud in the field 1/240 s into its ExpoOut extension passes at 60 Hz.
		sampleHz = 240,
		-- How deep the blade's tip or guard end may sink below the field: a tenth of a stud, under a
		-- third of the blade's 0.32 width. The two ends are points on the blade's center line; one
		-- that deep reads as a point resting on the grass, the way the anime's low cuts finish at the
		-- floor, while anything deeper shows the blade going into the ground. Hands get no margin.
		bladeMargin = 0.1,
		-- UpperBody and Additive clips are posed over this Base clip at the same clock time, the
		-- drawn stance a fight layers them on (Mixer: an UpperBody clip overrides the joints it keys,
		-- an Additive one adds to them); Base and FullBody clips are posed alone.
		layeredOver = "IdleDrawn",
		-- The Base clip under a clip that puts the sword away (a WeaponSheathe event): the sheathed
		-- set is already playing when Sheathe starts (D-050).
		layeredOverSheathed = "Idle",
		-- The sword changes hands (WeaponDraw, WeaponSheathe) where the hand is: posed once on the
		-- hand (the clip's Weapon key) and once on the back mount, the grip moves at most
		-- maxDistance studs and the blade turns at most maxDegrees, so the swap does not pop.
		handoff = { maxDistance = 0.4, maxDegrees = 30 },
		-- Off the body (D-050): the sword on the back (blade, guard, grip) and the scabbard keep `margin`
		-- from every body part but the sheath's own, by the part's group, in the poses GroundClearance
		-- lists (the sheathed and drawn sets, every one-shot, the flinches over the sets, the attacks,
		-- Guard, Parry, Draw and Sheathe), and stay above the field. It poses without Breathe, which adds
		-- to every pose on its own clock: held at either end of the breath, over those poses at 240 Hz, it
		-- brings the head at most 0.0097 studs nearer the sword or scabbard, the arms 0.027, the legs
		-- 0.039 and the hips 0.0100 (`torso` is the LowerTorso: the sheath hangs on the UpperTorso), so
		-- each margin is that rounded up and no breath closes the gap.
		offBody = {
			margin = { head = 0.01, arms = 0.03, legs = 0.04, torso = 0.01 },
			-- The sword in the hand (blade and guard) never goes into a body part but the hand on
			-- the hilt and its forearm. Contact only: posed without Breathe, whose breath and
			-- tremor bring the held guard up to 0.075 studs nearer the legs, more than a moving
			-- sword can keep from a stepping thigh.
			heldMargin = 0,
			-- For this long before a WeaponDraw and after a WeaponSheathe the right hand is on the
			-- hilt: the grip and guard may meet that hand and its forearm.
			onHilt = 0.1,
			-- A clip laid over a looping Base clip starts at this many points spread over the base's
			-- cycle, and at more when the base is longer than that many of the clip, so that every
			-- base frame plays under some frame of it (a looping clip needs only the second rule).
			starts = 4,
			-- A one-shot also starts at most startSpacing seconds apart in the base's cycle, up to
			-- maxStarts: a flinch peaks once, and over a 0.9 s walk the scabbard met the left foot
			-- only from starts in a 0.13 s band that 4 starts stepped over. 0.075 s is 12 starts on
			-- a walk; the cap holds only on the 12 s idles, which move too slowly to need more.
			startSpacing = 0.075,
			maxStarts = 24,
			-- The scabbard lies on the back: along the length of it that crosses the back, its face
			-- nearest the back stays within this of the back's face and never goes into it. A fifth
			-- of a stud is about 6 cm on the 5.33-stud figure, a coat and a strap: the most that
			-- still reads as worn on the back, and the room the hilt needs to clear the head.
			backGap = 0.2,
			-- Turns (TurnClearance.spec.luau): the real Locomotion carries the body through a drawn
			-- reversal, the stick swung straight back after `settle` seconds straight ahead, the root
			-- yawing toward it at each of `yawRates` (degrees a second; the lean reaches its cap at
			-- 250) while it moves at each of `speeds` (studs a second), to either side, and on for
			-- `after` seconds. The scabbard keeps `margin` all through, posed at sampleHz.
			turns = {
				speeds = { 6, 8, 12, 16, 24 },
				yawRates = { 180, 240, 360, 480 },
				settle = 1,
				after = 0.3,
			},
		},
		-- Draw and Sheathe as the client plays them (SheathTip.spec.luau, choreo.luau
		-- sheath.drawTipSpeed, sheatheTipSpeed and bladeTurnRate): each case stands `settle`
		-- seconds in its start state, the Drawn target flips, and it runs until the clip has blended
		-- out and `after` seconds more, at each of `speeds` (studs a second: standing, the walk, the
		-- run and the sprint) and stepped at each of `stepHz` (a 60 fps frame, the 240 Hz review).
		-- `hitch`: one frame `seconds` long among `hz` frames lands after each of the clip's first
		-- `steps` steps, so the blend in takes a big share of the hitch at once.
		sheathTip = {
			settle = 0.5,
			after = 0.3,
			speeds = { 0, 8, 16, 24 },
			stepHz = { 60, 240 },
			hitch = { seconds = 0.1, hz = 60, steps = 3 },
		},
		-- From a WeaponDraw until the blade is clear of the scabbard, and back from a WeaponSheathe
		-- to where it first meets it, every long edge of the blade that is partly inside the
		-- scabbard's walls stays within them, posed at `sampleHz`. For `seconds` from the event
		-- the blade runs along its sheath and comes out by at most `poke`: a blade that cuts out
		-- through the side of its sheath reads as a broken model. The pull ends with the grip 1.53
		-- studs from the shoulder (a straight arm reaches 2.29) and 2 studs of blade still in, so
		-- the rest swings out over the mouth: an edge passes up to 0.167 out (0.174 with Breathe)
		-- for 14 ms of Draw and 12 ms of Sheathe, under one 60 Hz frame, held by `swingOut`.
		-- Breathe, always on, adds its wrist and sword tremor to every pose: from `breathPhases`
		-- points of its cycle it brings an edge up to 0.106 out in the slide, held by `breathe`.
		-- Each Additive one-shot (the flinches) is posed landing every `leadStep` seconds.
		sheathSlide = {
			seconds = 0.05,
			sampleHz = 960,
			poke = 0,
			swingOut = 0.18,
			breathe = 0.11,
			breathPhases = 16,
			leadStep = 0.02,
		},
	},

	-- Gate recordings (section 20 Phase 0 gate; section 1: the capture script's on-screen prompts).
	-- Every shot stages itself (F12): P asks the server to set it up (DevStage.server.luau, Studio
	-- with DevCapture only), the camera takes the shot's view, a 3-2-1 runs, then the take records
	-- with a prompt naming the move and its moment and stops itself at the target length.
	capture = {
		phase = "phase-0",
		clipDirectory = "docs/clips/phase-0",
		fileExtension = "mp4",
		countdownSeconds = 3,
		entityTag = "SkyspireEntity", -- CollectionService tag on every fighter (ARCHITECTURE "Entities")
		doneHoldSeconds = 4, -- how long the "shot done" line stays before the panel returns to idle
		timeScaleReapplySeconds = 0.5, -- while slowed, re-apply the scale to animators that appeared since
		-- K before the target length asks first (the counter says so); a second K inside this many
		-- seconds ends the take unmarked. At or past the target, K marks it done at once.
		confirmSeconds = 2,
		-- Seconds the client waits for the server's staging before it gives up on the shot (the
		-- server waits out field attacks for up to stage.holdWaitSeconds first).
		stageTimeoutSeconds = 8,
		hotkeys = {
			startCountdown = "P", -- stage the shot, then 3-2-1, then the panel hides and the take runs
			nextShot = "RightBracket",
			previousShot = "LeftBracket",
			cycleTimeScale = "T", -- 1x / 0.5x / 0.25x (not O: Studio keeps O for its own shortcut)
			togglePanel = "H",
			markDone = "K",
			autoPerform = "U", -- auto-perform on or off (off when the panel starts)
			releaseStage = "J", -- give the field back: staged enemies gone, field holds let go
		},
		panel = {
			screenGuiName = "SkyspireCapture",
			displayOrder = 50,
			width = 400,
			padding = 12,
			margin = 24, -- from the top-right corner
			rowHeight = 22,
			titleTextSize = 18,
			textSize = 14,
			smallTextSize = 12,
			backgroundToken = "OutlineInk",
			backgroundTransparency = 0.25,
			borderToken = "SystemCyan",
			borderThickness = 1,
			titleToken = "SystemCyan",
			textToken = "SystemWhite",
			dimToken = "ShardBlue",
			doneToken = "HPGreen",
			cornerRadius = 6,
			lineGap = 4,
			countdownTextSize = 48,
		},
		counter = {
			-- The small frame counter shown bottom-left while a shot is being recorded (no blinking:
			-- the HP bar is the only HUD element allowed to flash). It is as wide as its text plus
			-- paddingX either side, and its text is written before it shows.
			height = 28,
			margin = 24,
			paddingX = 10,
			textSize = 16,
			token = "SystemCyan",
			backgroundToken = "OutlineInk",
			backgroundTransparency = 0.35,
		},
		-- The render-frame tick (dev only, D-336), shown with the counter: beside f, r counts every
		-- RenderStepped since the take started, never paused, and a size-pixel square margin pixels
		-- in from the screen's bottom-right corner swaps between its two colors every rendered
		-- frame, so a recording shows each frame the engine drew and any the recorder dropped or
		-- doubled. The two colors differ in hue, their relative luminance within maxLuminanceStep:
		-- a swap a recording tells apart, never a flash.
		frameTick = {
			size = 12,
			margin = 4,
			tokens = { "SystemCyan", "DigitYellow" },
			maxLuminanceStep = 0.05,
		},
		-- The move and its moment (the shot's prompts), just above the counter while a take runs.
		prompt = {
			height = 34,
			gap = 8, -- pixels between it and the counter
			paddingX = 12,
			textSize = 22,
			token = "SystemWhite",
			backgroundToken = "OutlineInk",
			backgroundTransparency = 0.35,
		},
		-- An Art launches when its key comes up (section 6), a basic when its key goes down. A timed
		-- Art's take holds the key long enough for the lit stance to read on camera: at least this
		-- many seconds past the start pose (combat.luau startPoseTime) before the release, and short
		-- of the cancel. Its prompts say when to press and hold and when to let go (a beat at each),
		-- so a human's launch lands where auto-perform's does (tools/validators/dev.luau).
		artGlowSeconds = 0.3,
		-- Auto-perform (the autoPerform key) presses each shot's `perform` keys through the real
		-- input path. Only at 1x: slowed, the drawn clips run late on the server's clock. A perform
		-- entry whose action is moveAction is the stick, not a key: it goes to Humanoid:Move from
		-- the walk's render step (walk.renderOrder), as the control script's keys would.
		perform = {
			defaultOn = false,
			moveAction = "Move",
			-- A guard reaction goes down the way up early (EF): how long the staging's asks took to
			-- reach the server on its clock (each reply's receivedAt less the ask's send on this
			-- client's server clock, the least of a staging's asks). Never more than this; Studio's
			-- network simulation runs to 0.25 s each way.
			wayUpMax = 0.5,
		},
		-- The server's half (DevStage.server.luau).
		stage = {
			remoteName = "DevStage", -- RemoteFunction under ReplicatedStorage, made by DevStage
			requestsPerSecond = 2, -- one player's faster requests are refused
			-- Held field enemies nearer the stand spot than this are moved out to it: past the lock's
			-- range (camera.luau lock.range, 60) and every aggro radius, so none joins or is locked.
			awayStuds = 70,
			-- The longest a field enemy's wind-up or strike is waited out before it is held (a hold
			-- inside a wind-up leaves a rush drawn that never comes).
			holdWaitSeconds = 3,
			-- The player's root as the staging reads it (D-447). Studio replicates a client-owned
			-- character a moment late, and the walk's last leg runs along the shot's facing at the
			-- sprint: read the frame the body came to rest, the root still trailed it by a few studs,
			-- short of the spot, so a boar staged 12 studs ahead of that read stood under 10 from
			-- where the player rested (ai.luau minChargeDistance) and circled out before its only
			-- charge (or the read fell outside the ring and asked for another walk). A root read
			-- within settleNearStuds (flat) of the
			-- spot is read again every frame until it has moved no more than settleStuds over
			-- settleSeconds, for up to settleTimeoutSeconds, and the ring check and the spawn use that
			-- read; one farther off is taken at once (the reply is a walk).
			settleNearStuds = 10,
			settleStuds = 0.05,
			settleSeconds = 0.15,
			settleTimeoutSeconds = 1,
			-- The stand ring (D-244: the staging never moves the player). The shot stages only once
			-- the player's root stands within standRadius studs (flat) of the stand spot, its feet
			-- within standHeightTolerance studs of the spot's floor (the open shot: over the ledge's
			-- top); otherwise the reply asks for a walk into the ring. The ring is wider than the
			-- auto-walk's rest target (capture.walk.restStuds): the walk lets go short of the spot by
			-- the stop's carry and the body comes to rest on it.
			standRadius = 3,
			standHeightTolerance = 1,
			-- The walk the reply asks for: a route that keeps routeMarginStuds off the ledge and its
			-- ramp and runs its last approachStuds along the spot's facing, so a body that walks it
			-- arrives facing the shot's way (the walk turns it, AutoRotate on the move direction).
			approachStuds = 6,
			routeMarginStuds = 3,
			-- Where the player stands for every shot but the open one: a ground point on the field
			-- and a facing (degrees, 0 looks along -Z, + turns left), clear of every spawn point.
			area = { position = { 0, 0, -10 }, facing = 0 },
			-- The open shot's ledge (D-024: no jump, so the fall and land come off an edge). Built once,
			-- anchored, on the first open shot. The player starts on top, standInset studs in from its
			-- +Z edge, facing its -Z edge: a walk of size Z - standInset to the drop.
			ledge = {
				name = "DevStageLedge",
				size = { 16, 6, 16 }, -- the top 6 studs over the field: a Land with weight (choreo landing)
				position = { 0, 3, 40 }, -- its center
				standInset = 2,
				facing = 0,
				colorToken = "PlaceholderSteel",
				material = "Slate",
				-- The way up (no jump): an anchored wedge built with the ledge, centred on it across X,
				-- its tall end against the ledge's +Z face and as tall as the ledge, sloping down
				-- size[3] studs away along +Z (atan(6 / 18), about 18 degrees). Behind the player's
				-- start, out of the run off the -Z edge.
				ramp = {
					name = "DevStageRamp",
					size = { 8, 6, 18 }, -- width (X), height (Y, the ledge's), length (Z)
					colorToken = "PlaceholderSteel",
					material = "Slate",
				},
			},
		},
		-- The client's half of the walk into the stand ring (Capture.client.luau). When a staging
		-- asks for a walk the panel marks the ring and walks the body there itself: the walk's
		-- direction goes to Humanoid:Move each frame from a render step at renderOrder (after the
		-- control script's own Move at Input, before the character controller reads MoveDirection
		-- at choreo.luau renderOrder.character), so the controller, Locomotion and the two-step stop
		-- see the same input a held key gives. The walk holds input.luau's sprintAction through the
		-- input path (as the key does, as the panel's own source: D-338, so the player's Shift
		-- let-go never lets go of it), so it runs at the sprint and its stop is the Skid's: above
		-- choreo locomotion.skidSpeedThreshold the two-step stop (D-059) carries nothing, and the
		-- body stops where the walk lets go. It steers to each route point until it is within
		-- waypointStuds; on the last leg (the approach along the spot's facing) it follows the
		-- leg's line, aiming lookaheadStuds past the root's foot on it, so the body runs square to
		-- the shot's way, and lets go when the spot is the stop's carry ahead: none at the sprint,
		-- the walk's speed x carrySeconds below the Skid's threshold (the two-step stop's carry
		-- at run speed, 1.8 to 4.2 studs by where the stride is, 3.0 in the middle: 0.186 s at 16
		-- studs per second), or the carry the last sprint stop was seen to make when the engine
		-- slid it on. Once the body is slower than restSpeed (studs per second, flat) it is at
		-- rest, and it stays so for askSettleSeconds (real seconds) before the shot is asked for:
		-- the server reads the root as it last replicated, which in Studio trails the client, and
		-- a root asked for the frame it stopped was read where it was in its slide (outside the
		-- ring: a new walk, which sprinted the body on the spot back to the approach and round
		-- again; inside it: enemies staged off where it stands, CW). At rest more than restStuds
		-- (flat) off the spot or restDegrees off its facing, it corrects (at most secondWalks times
		-- a staging), never at a sprint: it walks at correctSpeed to correctBackStuds behind the spot
		-- along the approach (unless it already stands that far behind it, on the line), then in
		-- along it at ahead / creepSeconds studs a second (at most correctSpeed) and lets go once
		-- that falls under creepEndSpeed, so the body arrives as good as stopped and the two-step
		-- stop carries nothing. Otherwise the shot is asked for again (a root outside the ring gets
		-- a new walk). A walk asked for while the root stands within correctWithinStuds of the spot
		-- (flat, its feet within the ring's height tolerance) never runs the route: in the ring it
		-- starts at the rest check, and outside it is a correction from where the root stands (the
		-- server's new walk, not one of the secondWalks). On the spot but off its facing alone, it
		-- turns there at faceDegreesPerSecond and stands faceSettleSeconds (step 14). A cancelKeys key
		-- (Enum.KeyCode names: the default control script's movement keys), pressed or held at any
		-- point after P, hands the walk to the player until P: the walk lets go of the sprint and
		-- never moves the body again (the ring stays and the ask comes once the root stands in it at
		-- rest); J and P end it, and timeoutSeconds never does (317(a)). timeoutSeconds (on the
		-- capture's clock) ends a walk nobody walks: the auto-walk's, or one the world blocked.
		walk = {
			timeoutSeconds = 15,
			waypointStuds = 1,
			lookaheadStuds = 1.5,
			sprintAction = "Sprint",
			carrySeconds = 0.186,
			restSpeed = 0.25,
			restStuds = 1,
			restDegrees = 5,
			secondWalks = 2,
			askSettleSeconds = 0.5,
			correctWithinStuds = 4,
			correctBackStuds = 2.5,
			correctSpeed = 8,
			creepSeconds = 0.2,
			creepEndSpeed = 0.15,
			faceDegreesPerSecond = 360,
			faceSettleSeconds = 0.35,
			-- The blocked rule (316(b)): a walk whose push has not moved the root blockedStuds
			-- (flat) in blockedSeconds (on the capture's clock) lets go and leaves the ring to the
			-- player.
			blockedSeconds = 1,
			blockedStuds = 0.25,
			cancelKeys = { "W", "A", "S", "D", "Up", "Down", "Left", "Right" },
			renderOrder = { base = "Input", offset = 1 },
			-- The ring: a flat client-made disc (no collision, no query) the stand ring's size.
			ring = {
				name = "DevStageRing",
				thickness = 0.2,
				colorToken = "SystemCyan",
				material = "Neon",
				transparency = 0.45,
			},
		},
		-- The staged views (CameraController.setStage, StageCamera). Side frames the Arts and the
		-- kill; ThreeQuarter the kobold's overhead and the parry, from wide on the side of its axe
		-- hand (those shots take cameraSide -1), so the player never stands between the lens and the
		-- kobold or its axe (tests/client/CameraStageFraming.spec.luau); Behind holds the boar's
		-- whole charge still (fixed) from high behind its right flank, the side its pass shoulders
		-- past the player on (cameraSide 1): it looks down the line from over the crouch, so the
		-- crouch, the launch, the contact, the skid and the turn all play in one frame, and it stands
		-- far enough off the line that the skid's end and the turn, 10 studs past the player on the
		-- line, never fall behind the player's body, and high enough that the snout coming round
		-- in the turn clears the player's head (tests/client/CameraBehindFraming.spec.luau); Rear
		-- reads the boar's wind-up from behind it (FB4, section 10 "Enemy animation rules"): still,
		-- 20 degrees off the line behind the crouch, low enough that the red line shows past its
		-- body, for the crouch and the launch only (no view that near the line keeps the skid and
		-- the turn clear of the player: tests/client/CameraRearFraming.spec.luau); Open watches the
		-- locomotion pass from the player's +X, so a run along -Z crosses the screen.
		cameras = {
			Side = {
				anchor = "Middle",
				reference = "Line",
				degrees = 90,
				distance = 11,
				height = 1.5,
				focusBias = 0.5,
				lookHeight = 1,
			},
			ThreeQuarter = {
				anchor = "Player",
				reference = "Line",
				degrees = 75,
				distance = 14,
				height = 3,
				focusBias = 0.5,
				lookHeight = 1,
			},
			Behind = {
				anchor = "Target",
				reference = "Line",
				degrees = 75,
				distance = 14,
				height = 14,
				focusBias = 0.3,
				lookHeight = 1,
				fixed = true,
			},
			Rear = {
				anchor = "Target",
				reference = "Line",
				degrees = 20,
				distance = 14,
				height = 7,
				focusBias = 0.5,
				lookHeight = 1,
				fixed = true,
			},
			Open = {
				anchor = "Player",
				reference = "World",
				degrees = 90,
				distance = 16,
				height = 2,
				focusBias = 0,
				lookHeight = 1,
			},
		} :: { [string]: StageCamera },
		shots = {
			{
				id = "fight-boar-kobold",
				title = "The fight (gate clip)",
				seconds = 20,
				notes = "one boar and one kobold; every attack shows the six beats; a parry spark; a kill shatter; the server registered every hit (a digit per hit)",
				stage = {
					open = false,
					lock = true,
					enemies = {
						{ enemy = "KoboldAxeman", distance = 9, side = 0, held = false },
						-- Off the player's left shoulder, out of the swings at the kobold, held until the
						-- kobold's third overhead has been parried: its crouch comes in the kobold's
						-- stagger, its line across the player's back step, and its skid is the kill.
						-- One basic's HP (combat basic damage on it): the kill lands in the half
						-- second between its skid and the kobold's next overhead.
						{
							enemy = "FrenzyBoar",
							distance = 12,
							side = 100,
							held = false,
							releaseAfter = 8.6,
							charge = "Meets",
							hp = 4,
						},
					},
				},
				camera = "Lock",
				cameraSide = 1,
				prompts = {
					{
						at = 0,
						text = "Fight the kobold: basics (left mouse) in reach; guard (right mouse) as its axe drops for the parry, then Q",
					},
					{ at = 5, text = "The next overhead: guard for the parry, then 2" },
					{
						at = 8.6,
						text = "The boar is let go: the crouch, the red line, then it charges into you: dodge (Space) back across it",
					},
					{
						at = 9.8,
						text = "Lock the boar (F), sprint at its skid (Shift+W), basics: the kill, the freeze, the shatter",
					},
					{ at = 11.5, text = "Lock the kobold (F): guard each overhead for the parry, then 4, then 3" },
				},
				-- Auto-perform reacts to what this client draws (CF): a guard on each of the kobold's
				-- overheads (the parry), then the next Art; a dodge on the boar's crouch, the lock on it
				-- and a sprint at its skid; between, basics on the lock's target in reach and the lock
				-- back on the kobold once the boar is gone.
				perform = {
					{
						action = "Guard",
						onClip = "enemy/Kobold/Overhead",
						enemy = 1,
						repeats = true,
						lock = true,
						-- As parry-spark's: the way up comes on top (D-319, EF).
						lead = 0.04,
						hold = 0.3,
						-- Every overhead the take shows is guarded (EF: at 0.05 s in Studio the sixth
						-- came late, its guard past 19 s was dropped, and the basics swung into it).
						to = 20,
						chain = {
							{
								action = "Art",
								delay = 0.15,
								hold = 0.5,
								cycle = { "Art", "ArtSlot2", "ArtSlot4", "ArtSlot3" },
								-- The last parry's Art (down at about 19.2 s, launched about 19.7 s)
								-- would land after the 20 s cut, where its number is never seen (D-320).
								to = 19,
							},
						},
					},
					{
						action = "Dodge",
						onClip = "enemy/Boar/Charge",
						enemy = 2,
						repeats = true,
						lead = 0.3,
						hold = 0.05,
						chain = {
							{ action = "LockOn", enemy = 2, delay = 0.6, hold = 0.05 } :: PerformStep,
							{
								action = "Move",
								stick = { 0, 1 },
								sprint = true,
								within = 4.5,
								delay = 0.25,
								hold = 1.2,
							},
						},
					},
					{ action = "BasicAttack", every = 0.4, from = 0.3, to = 19.5, within = 5.5, hold = 0.05 },
					{ action = "LockOn", enemy = 1, every = 0.2, hold = 0.05 },
				},
			},
			{
				id = "art-horizontal",
				title = "Art: Horizontal",
				seconds = 5,
				notes = "start pose, activation glow, anticipation, snap, smear, hold, settle, post-motion",
				stage = {
					open = false,
					lock = true,
					enemies = { { enemy = "KoboldAxeman", distance = 3.5, side = 0, held = true } },
				},
				camera = "Side",
				cameraSide = 1,
				-- An Art launches on its key's release: down at 0.5 s, lit from 0.65 s, up (the cut) at 1.0 s.
				prompts = {
					{ at = 0, text = "Horizontal (Q): press and hold Q at 0.5 s, let go at 1.0 s; stand still" },
					{ at = 0.5, text = "Hold Q: the start pose, then the glow" },
					{ at = 1, text = "Let go of Q now: the cut" },
					{ at = 2, text = "Hold still: settle and post-motion" },
				},
				perform = { { action = "Art", at = 0.5, hold = 0.5 } },
			},
			{
				id = "art-vertical",
				title = "Art: Vertical",
				seconds = 5,
				notes = "the overhead cut; gauge-heavy hit; same six beats",
				stage = {
					open = false,
					lock = true,
					enemies = { { enemy = "KoboldAxeman", distance = 3.5, side = 0, held = true } },
				},
				camera = "Side",
				cameraSide = 1,
				prompts = {
					{ at = 0, text = "Vertical (2): press and hold 2 at 0.5 s, let go at 1.0 s; stand still" },
					{ at = 0.5, text = "Hold 2: the start pose, then the glow" },
					{ at = 1, text = "Let go of 2 now: the overhead cut" },
					{ at = 2, text = "Hold still: settle and post-motion" },
				},
				perform = { { action = "ArtSlot2", at = 0.5, hold = 0.5 } },
			},
			{
				id = "art-sharp-nail",
				title = "Art: Sharp Nail",
				seconds = 5,
				notes = "three hits, three hit-stops, the trail on only in the windows",
				stage = {
					open = false,
					lock = true,
					enemies = { { enemy = "KoboldAxeman", distance = 3.5, side = 0, held = true } },
				},
				camera = "Side",
				cameraSide = 1,
				prompts = {
					{ at = 0, text = "Sharp Nail (4): press and hold 4 at 0.5 s, let go at 1.0 s; stand still" },
					{ at = 0.5, text = "Hold 4: the start pose, then the glow" },
					{ at = 1, text = "Let go of 4 now: three hits, three hit-stops" },
					{ at = 2.5, text = "Hold still: the settle and post-motion" },
				},
				perform = { { action = "ArtSlot4", at = 0.5, hold = 0.5 } },
			},
			{
				id = "art-rising-arc",
				title = "Art: Rising Arc",
				seconds = 5,
				notes = "the sunken start pose, the rise onto the toes, two hits with Normal then Final hit-stop, the trail on only in the windows",
				stage = {
					open = false,
					lock = true,
					enemies = { { enemy = "KoboldAxeman", distance = 3.5, side = 0, held = true } },
				},
				camera = "Side",
				cameraSide = 1,
				prompts = {
					{ at = 0, text = "Rising Arc (3): press and hold 3 at 0.5 s, let go at 1.0 s; stand still" },
					{ at = 0.5, text = "Hold 3: the sunken start pose, then the glow" },
					{ at = 1, text = "Let go of 3 now: the rise, two hits" },
					{ at = 2.5, text = "Hold still: the settle and post-motion" },
				},
				perform = { { action = "ArtSlot3", at = 0.5, hold = 0.5 } },
			},
			{
				id = "enemy-boar-charge",
				title = "Boar: Charge telegraph and strike",
				seconds = 5,
				notes = "0.6 s crouch with the red line, the launch, the skid and the turn, from the flank (the read from behind is enemy-boar-charge-rear)",
				stage = {
					open = false,
					lock = false,
					-- Inside its line (reach 14): the charge meets the player, then the overshoot runs on.
					enemies = { { enemy = "FrenzyBoar", distance = 12, side = 0, held = false, charge = "Meets" } },
				},
				camera = "Behind",
				cameraSide = 1,
				prompts = {
					{ at = 0, text = "Stand still: the boar crouches (0.6 s, red line), then charges into you" },
					{ at = 1.5, text = "Stand still: it runs on past you, the skid and the turn" },
				},
				perform = {},
			},
			{
				id = "enemy-kobold-overhead",
				title = "Kobold: Overhead telegraph and strike",
				seconds = 5,
				notes = "1.0 s wind-up with the yellow edge, the chop, the recovery",
				stage = {
					open = false,
					lock = false,
					-- One overhead (FK2): no second wind-up fills the take's last second.
					enemies = { { enemy = "KoboldAxeman", distance = 4.5, side = 0, held = false, attacks = 1 } },
				},
				camera = "ThreeQuarter",
				cameraSide = -1, -- the kobold holds its axe in its right hand: the lens on that side
				prompts = {
					{ at = 0, text = "Stand still: the 1.0 s wind-up, the yellow edge" },
					{ at = 2.5, text = "Stand still: the chop and the recovery" },
				},
				perform = {},
			},
			{
				id = "parry-spark",
				title = "Parry",
				seconds = 5,
				notes = "guard tapped inside the window against the kobold's overhead (the boar's charge is unblockable); spark and ring; the enemy staggers",
				stage = {
					open = false,
					lock = true,
					-- One overhead (FK2): no second wind-up fills the take's last second.
					enemies = { { enemy = "KoboldAxeman", distance = 4.5, side = 0, held = false, attacks = 1 } },
				},
				camera = "ThreeQuarter",
				cameraSide = -1, -- the kobold holds its axe in its right hand: the lens on that side
				prompts = {
					{ at = 0, text = "Parry: guard (right mouse) as the axe starts down" },
					{ at = 3, text = "Hold still: the spark, the ring, the stagger" },
				},
				-- The guard leaves `lead` before the hit window and the latency lead earlier still
				-- (Telegraphs.glintLead, D-289): 0.04 parries at 0 to 100 ms on Studio's link and a
				-- live one with at least 18 ms to spare (tests/client/ParryGlint.spec.luau, D-319).
				perform = {
					{ action = "Guard", onClip = "enemy/Kobold/Overhead", lead = 0.04, hold = 0.4 },
				},
			},
			{
				id = "kill-shatter",
				title = "Kill and shatter",
				seconds = 5,
				notes = "the 10-frame kill hit-stop, the 0.5 s freeze and silence, the shards rising",
				stage = {
					open = false,
					lock = true,
					enemies = { { enemy = "KoboldAxeman", distance = 3.5, side = 0, held = true, hp = 1 } },
				},
				camera = "Side",
				cameraSide = 1,
				-- A basic swings on its click: the click's beat is the swing's.
				prompts = {
					{ at = 0, text = "Kill: one click (left mouse) at 1.0 s; the basic swings on the click" },
					{ at = 1, text = "Click now (left mouse): the kill" },
					{ at = 1.5, text = "Hold still: the freeze, the silence, the shards" },
				},
				perform = { { action = "BasicAttack", at = 1, hold = 0.05 } },
			},
			{
				id = "locomotion",
				title = "Locomotion pass",
				seconds = 14,
				notes = "sheathed: walk, run, sprint with the sword on the back; lock on to draw; drawn: walk, run, sprint with the blade low and back; turn in place, skid stop, fall off the ledge and land; no T-pose, no sliding foot",
				stage = {
					open = true,
					lock = false,
					-- ahead and left of the run: inside the lock's range and the Open view's cone at about 5 s
					enemies = { { enemy = "KoboldAxeman", distance = 60, side = 20, held = true } },
				},
				camera = "Open",
				cameraSide = 1,
				prompts = {
					-- Every run names its key: under the Open view D runs to screen right and A to screen
					-- left, across the frame (W and S run at and away from the lens). The walk is a
					-- part-pushed stick (there is no walk key; auto-perform pushes it half way). Turn in
					-- place is the lock turning a body that stands still (LocomotionState): the keys only
					-- move it.
					{ at = 0, text = "Sheathed: walk right (D) on a half-pushed stick, off the ledge: fall and land" },
					{ at = 2.5, text = "Sheathed: run right (D), then sprint (Shift+D)" },
					{ at = 5, text = "Let go; lock on the kobold (F): the sword draws; F again" },
					{ at = 6.5, text = "Drawn: walk left (A) half-pushed, run (A), then sprint (Shift+A)" },
					{ at = 8.8, text = "Let go and stand" },
					{
						at = 10,
						text = "Lock on the kobold behind you (F): the turn in place; F again",
					},
					{ at = 12, text = "Sprint right (Shift+D), then let go: the skid stop" },
				},
				-- The stick on the Open view's frame (CF): { right, forward }, D is right. Half pushed
				-- walks (8 studs a second), full runs, the sprint held with it sprints.
				perform = {
					{ action = "Move", at = 0, hold = 2.5, stick = { 0.5, 0 } },
					{ action = "Move", at = 2.5, hold = 1, stick = { 1, 0 } },
					{ action = "Move", at = 3.5, hold = 1.3, stick = { 1, 0 }, sprint = true },
					{ action = "LockOn", at = 5, hold = 0.05 },
					{ action = "LockOn", at = 5.8, hold = 0.05 },
					{ action = "Move", at = 6.5, hold = 0.8, stick = { -0.5, 0 } },
					{ action = "Move", at = 7.3, hold = 0.8, stick = { -1, 0 } },
					{ action = "Move", at = 8.1, hold = 0.7, stick = { -1, 0 }, sprint = true },
					{ action = "LockOn", at = 10.2, hold = 0.05 },
					{ action = "LockOn", at = 11.2, hold = 0.05 },
					{ action = "Move", at = 12, hold = 1.2, stick = { 1, 0 }, sprint = true },
				},
			},
			{
				id = "enemy-boar-charge-rear",
				title = "Boar: Charge wind-up from behind",
				seconds = 2,
				notes = "the 0.6 s crouch and the red line readable from behind the boar, then the launch into the player",
				-- enemy-boar-charge's stage: the same charge, seen from behind the boar.
				stage = {
					open = false,
					lock = false,
					enemies = { { enemy = "FrenzyBoar", distance = 12, side = 0, held = false, charge = "Meets" } },
				},
				camera = "Rear",
				cameraSide = 1,
				prompts = {
					{ at = 0, text = "Stand still: the boar crouches (0.6 s, red line), then charges into you" },
				},
				perform = {},
			},
		} :: { Shot },
	},
	-- The clip review scene (section 10 "Review loop").
	clipLab = {
		stageFolderName = "ClipLabStage",
		lightingPreset = "ruin", -- lighting.luau biome preset: silver stone, cool neutral
		rigAttribute = "Rig", -- the rig id attribute Choreo reads (ARCHITECTURE "Entities")
		speeds = { 0.25, 0.5, 1 },
		defaultSpeed = 1,
		abInterval = 1.2, -- seconds per half of the A/B (clip / rest pose) alternation
		hitStopPreview = true, -- pause the clock on each strike key like a landed hit would
		stageWaitSeconds = 10,
		-- ContextActionService priority name the hotkeys bind at (LabKeys, D-413): above the
		-- default character scripts, which bind the arrows and Space to move and jump.
		actionPriority = "High",
		hotkeys = {
			speedSlow = "One",
			speedHalf = "Two",
			speedFull = "Three",
			playPause = "Space",
			stepBack = "Comma",
			stepForward = "Period",
			restart = "R",
			abToggle = "B",
			previousClip = "Up",
			nextClip = "Down",
			orbitLeft = "Left",
			orbitRight = "Right",
			hitStopToggle = "H",
		},
		rigs = {
			-- One pedestal per rig id; the player's own character stands on the PlayerR15 one.
			{ rig = "PlayerR15", position = { 0, 0, 0 } },
			{ rig = "Boar", position = { -14, 0, 0 } },
			{ rig = "Kobold", position = { 14, 0, 0 } },
		},
		pedestal = { size = { 10, 1, 10 }, color = "PlaceholderSteel", transparency = 0 },
		stage = { radius = 60, thickness = 2, color = "OutlineInk", transparency = 0.1 },
		-- Three-point light. The camera looks at the rigs' faces from their -Z side (camera.startYaw),
		-- so the key and the fill stand on that side, high and low, and the rim stands behind them,
		-- above the shoulders, so a dark outfit's edge reads against the backdrop.
		keyLight = { position = { 10, 16, -14 }, range = 60, brightness = 2.4, color = "SystemWhite" },
		fillLight = { position = { -14, 7, -10 }, range = 50, brightness = 1.2, color = "ShardBlue" },
		rimLight = { position = { 0, 12, 12 }, range = 40, brightness = 2.5, color = "TrailIvory" },
		-- The place's backdrop wall (places/ClipLab.project.json Workspace.ClipLab), colored here: a mid
		-- grey a black outfit stands out against.
		backdrop = { part = "Backdrop", color = "PlaceholderSteel" },
		-- Over the lighting preset, for the lab only: a brighter ambient and diffuse so the folds of
		-- dark cloth show, and a little exposure.
		lighting = {
			ambient = { 0.5, 0.52, 0.56 },
			outdoorAmbient = { 0.58, 0.6, 0.66 },
			environmentDiffuseScale = 1,
			exposureCompensation = 0.3,
		},
		camera = {
			distance = 13,
			height = 3.5,
			focusHeight = 2.5, -- above the pedestal top
			fov = 50,
			orbitDegreesPerSecond = 60,
			startYaw = 30, -- degrees; 0 looks at the rig's face
			lag = 0.1, -- seconds; the camera eases between rigs
		},
		-- Fallback weapon when WeaponBuilder is not in the build: a blade-shaped part on the right hand.
		fallbackWeapon = { size = { 0.3, 3.4, 0.5 }, color = "PlaceholderSteel", gripOffset = { 0, -1.4, 0 } },
		panel = {
			screenGuiName = "SkyspireClipLab",
			displayOrder = 40,
			margin = 16,
			listWidth = 300,
			rowHeight = 20,
			headerHeight = 24,
			textSize = 13,
			titleTextSize = 16,
			controlsHeight = 36,
			controlRows = 3, -- 3 speeds + 6 transport and toggle buttons at 4 per row inside listWidth
			buttonWidth = 64,
			buttonGap = 6,
			padding = 10,
			backgroundToken = "OutlineInk",
			backgroundTransparency = 0.25,
			borderToken = "SystemCyan",
			textToken = "SystemWhite",
			dimToken = "ShardBlue",
			selectedToken = "SystemCyan",
			cornerRadius = 6,
			readoutHeight = 26,
			problemsHeight = 60,
		},
		timeline = {
			height = 72,
			bottomMargin = 24,
			sideMargin = 240,
			laneHeight = 10,
			laneGap = 3,
			tickWidth = 2,
			playheadWidth = 2,
			playheadToken = "SystemWhite",
			backgroundToken = "OutlineInk",
			backgroundTransparency = 0.35,
			labelTextSize = 11,
			labelWidth = 72, -- the lane-name column at the left of the bar
			minMarkerWidth = 3, -- pixels; an instant event is drawn at least this wide
			-- Lane 1: the six beats. Lane 2: hit windows. Lane 3: trail and smear. Lane 4: other events.
			lanes = { "Beats", "HitWindows", "TrailSmear", "Events" },
			beatTokens = {
				Anticipation = "ShardBlue",
				Snap = "SystemWhite",
				Smear = "TrailCyanWhite",
				Hold = "HPYellow",
				Settle = "TrailPaleGold",
				Recovery = "WardedPurple",
			},
			hitWindowToken = "HPRed",
			trailToken = "TrailCyanWhite",
			smearToken = "SystemWhite",
			eventToken = "HPGreen",
			eventTokens = {
				ActivationHold = "SystemCyan",
				PostMotionStart = "WardedPurple",
				Footstep = "PlaceholderWood",
				Sfx = "HPGreen",
				Voice = "TorchWarm",
				CameraNudge = "CursorOrange",
				WeaponSwap = "TrailOrange",
				WeaponDraw = "PlaceholderSteel",
				WeaponSheathe = "ShatterSilver",
			},
		},
	},

	-- The PoseEditor Studio plugin (section 10: scrubs any clip, drags joints, writes the table back).
	poseEditor = {
		toolbarName = "Skyspire",
		buttonName = "PoseEditor",
		buttonTooltip = "Scrub, pose and save Choreo clips",
		widgetName = "SkyspirePoseEditor",
		widgetTitle = "Skyspire PoseEditor",
		widgetSize = { width = 420, height = 640 },
		widgetMinSize = { width = 320, height = 400 },
		rowHeight = 24,
		textSize = 13,
		padding = 8,
		layoutColumns = 6, -- a row is laid out on this many equal columns
		scrubStepFrames = 1,
		defaultNewKeyEasing = "SineInOut",
		keyTimeTolerance = 0.0005, -- seconds; a scrub within this of a key selects it
		positionHandleStuds = 0.1, -- studs per drag step on the Handles
		rotationHandleDegrees = 2, -- degrees per drag step on the ArcHandles
		positionDecimals = 3,
		rotationDecimals = 1,
		previewAttribute = "PoseEditorPreview", -- set on the rig while the editor drives its joints
		tokens = {
			background = "OutlineInk",
			text = "SystemWhite",
			dim = "ShardBlue",
			accent = "SystemCyan",
			ok = "HPGreen",
			warn = "HPYellow",
			bad = "HPRed",
		},
		easings = { "ExpoOut", "ExpoIn", "BackOut", "Spring", "SineInOut", "QuadIn", "QuadOut", "Hold", "Linear" },
		eventKinds = {
			"HitWindowOpen",
			"HitWindowClose",
			"TrailOn",
			"TrailOff",
			"SmearOn",
			"SmearOff",
			"Footstep",
			"Voice",
			"Sfx",
			"ActivationHold",
			"PostMotionStart",
			"WeaponSwap",
			"CameraNudge",
			"WeaponDraw",
			"WeaponSheathe",
		},
	},
}

--- The repo-relative file a gate shot is recorded to: docs/clips/<phase>/<shot>.<ext>.
function Dev.clipPath(shotId: string): string
	return ("%s/%s.%s"):format(Dev.capture.clipDirectory, shotId, Dev.capture.fileExtension)
end

--- The capture panel's time-scale line: the scale, and below 1x the note that only animation slows.
function Dev.timeScaleLabel(scale: number): string
	if scale == 1 then
		return ("Time scale %gx"):format(scale)
	end
	return ("Time scale %gx (%s)"):format(scale, Dev.timeScale.slowNote)
end

--- The URL the PoseEditor posts a clip to.
function Dev.clipUrl(clipId: string): string
	local server = Dev.poseServer
	return ("http://%s:%d%s/%s"):format(server.host, server.port, server.clipsRoute, clipId)
end

--- True when a clip id is well formed for the pose server: 2 to 4 alphanumeric segments, no dots.
function Dev.isClipId(id: string): boolean
	local segments = 0
	for segment in id:gmatch("[^/]+") do
		segments += 1
		if not segment:match("^%a[%w]*$") then
			return false
		end
	end
	local range = Dev.poseServer.idSegments
	if segments < range.min or segments > range.max then
		return false
	end
	-- "a//b" has an empty segment that gmatch skips; the join must rebuild the id exactly.
	local parts = {}
	for segment in id:gmatch("[^/]+") do
		table.insert(parts, segment)
	end
	return table.concat(parts, "/") == id
end

return Dev
