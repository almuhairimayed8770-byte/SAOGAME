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
	screenshot. Letters that input.luau binds (Q, E, F, R, Tab, Space, 2, 3, 4, Shift) are avoided
	in the Playground, where gameplay input is live.

	Times are seconds, sizes are pixels at UI scale 1, distances are studs, angles are degrees,
	colors are palette tokens.
]]

export type Shot = {
	id: string, -- file stem: docs/clips/phase-0/<id>.mp4
	title: string,
	seconds: number, -- target length of the recording
	notes: string, -- what the reviewer must be able to see
}

local Dev = {
	-- Workspace attributes that switch the dev scripts on (set in the dev place project files).
	attributes = {
		capture = "DevCapture",
		clipLab = "ClipLab",
		timeScale = "DevTimeScale", -- written by the server from the dev remote; dev places only
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
	capture = {
		phase = "phase-0",
		clipDirectory = "docs/clips/phase-0",
		fileExtension = "mp4",
		countdownSeconds = 3,
		entityTag = "SkyspireEntity", -- CollectionService tag on every fighter (ARCHITECTURE "Entities")
		doneHoldSeconds = 4, -- how long the "shot done" line stays before the panel returns to idle
		timeScaleReapplySeconds = 0.5, -- while slowed, re-apply the scale to animators that appeared since
		hotkeys = {
			startCountdown = "P", -- prime the shot: 3-2-1, then the panel hides and the counter runs
			nextShot = "RightBracket",
			previousShot = "LeftBracket",
			cycleTimeScale = "O",
			togglePanel = "H",
			markDone = "K",
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
			-- the HP bar is the only HUD element allowed to flash).
			width = 240,
			height = 28,
			margin = 24,
			textSize = 16,
			token = "SystemCyan",
			backgroundToken = "OutlineInk",
			backgroundTransparency = 0.35,
		},
		shots = {
			{
				id = "fight-boar-kobold",
				title = "The fight (gate clip)",
				seconds = 20,
				notes = "one boar and one kobold; every attack shows the six beats; a parry spark; a kill shatter; the server registered every hit (a digit per hit)",
			},
			{
				id = "art-horizontal",
				title = "Art: Horizontal",
				seconds = 5,
				notes = "start pose, activation glow, anticipation, snap, smear, hold, settle, post-motion",
			},
			{
				id = "art-vertical",
				title = "Art: Vertical",
				seconds = 5,
				notes = "the overhead cut; gauge-heavy hit; same six beats",
			},
			{
				id = "art-sharp-nail",
				title = "Art: Sharp Nail",
				seconds = 5,
				notes = "three hits, three hit-stops, the trail on only in the windows",
			},
			{
				id = "art-rising-arc",
				title = "Art: Rising Arc",
				seconds = 5,
				notes = "the sunken start pose, the rise onto the toes, two hits with Normal then Final hit-stop, the trail on only in the windows",
			},
			{
				id = "enemy-boar-charge",
				title = "Boar: Charge telegraph and strike",
				seconds = 5,
				notes = "0.6 s crouch with the red line, the launch, the skid, readable from behind",
			},
			{
				id = "enemy-kobold-overhead",
				title = "Kobold: Overhead telegraph and strike",
				seconds = 5,
				notes = "1.0 s wind-up with the yellow edge, the chop, the recovery",
			},
			{
				id = "parry-spark",
				title = "Parry",
				seconds = 5,
				notes = "guard tapped inside the window against the kobold's overhead (the boar's charge is unblockable); spark and ring; the enemy staggers",
			},
			{
				id = "kill-shatter",
				title = "Kill and shatter",
				seconds = 5,
				notes = "the 10-frame kill hit-stop, the 0.5 s freeze and silence, the shards rising",
			},
			{
				id = "locomotion",
				title = "Locomotion pass",
				seconds = 14,
				notes = "sheathed: walk, run, sprint with the sword on the back; lock on to draw; drawn: walk, run, sprint with the blade low and back; turn in place, skid stop, jump and land; no T-pose, no sliding foot",
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
		hitStopPreview = true, -- pause the clock on HitWindowOpen like a landed hit would
		stageWaitSeconds = 10,
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
		keyLight = { position = { 12, 18, 16 }, range = 60, brightness = 2.2, color = "SystemWhite" },
		fillLight = { position = { -16, 10, 10 }, range = 50, brightness = 0.8, color = "ShardBlue" },
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
