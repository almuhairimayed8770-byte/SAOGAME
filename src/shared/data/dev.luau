--!strict
--[[
	Dev tooling numbers (section 1 "How you work", section 10 "Review loop", section 19 tools).
	Everything the capture prompts, the ClipLab review scene, the PoseEditor plugin, the pose
	server and the animation review report use lives here: hotkeys, panel layout, the review
	frame budgets, the gate shot list and the clip file-name convention.

	None of this ships to players: Capture and ClipLab run only when the place carries the
	workspace attribute named below (set in places/Playground.project.json and ClipLab), and the
	PoseEditor is a Studio plugin. Hotkeys are Enum.KeyCode names and never a function key: F9 is
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
		beats = { "Anticipation", "Snap", "Smear", "Hold", "Settle", "Recovery" },
		humanColumns = { "Watched at 0.25x", "Problems seen", "Fixed" },
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
				notes = "guard tapped inside the window; spark and ring; the enemy staggers",
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
				seconds = 10,
				notes = "walk, run, sprint drawn and sheathed, turn in place, skid stop, jump and land; no T-pose, no sliding foot",
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
		},
	},
}

--- The repo-relative file a gate shot is recorded to: docs/clips/<phase>/<shot>.<ext>.
function Dev.clipPath(shotId: string): string
	return ("%s/%s.%s"):format(Dev.capture.clipDirectory, shotId, Dev.capture.fileExtension)
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
