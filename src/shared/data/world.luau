--!strict
--[[
	World building tunables (sections 5, 11, 16, 20; D-005, D-013). playground.luau says where the
	rim, pillars, clouds and kill volume are; this table says how PlaygroundBuilder makes them:
	rail count and heights, pillar material and the SurfaceLights that light the ceiling underside,
	the cloud billboards' particle shape, the kill volume part, folder names and the part budget.
	`performance` holds the section 16 per-place targets and the load the perf smoke measures them
	under (tests/smoke/perf.smoke.luau).

	Environment colors here are {r, g, b} triples like lighting.luau (the palette is for UI and FX
	only). Distances are studs, times are seconds, angles are degrees, fractions are 0..1.
]]

local World = {
	playground = {
		modelName = "Playground", -- the Model places/Playground.project.json builds
		partBudget = 2000, -- the whole Playground model, counted after the build
		partCountAttribute = "PartCount",
		folders = {
			railing = "Railing",
			pillars = "Pillars",
			clouds = "Clouds",
			enemies = "Enemies", -- under workspace: EnemyService parents spawned rigs here
			entities = "Entities", -- under workspace: non-enemy server-built fighters (stand-ins, dummies)
		},
		killVolumeName = "KillVolume",
	},

	railing = {
		railCount = 2, -- a top rail at the post height and one at half of it
		material = "SmoothPlastic",
		postColor = { 0.62, 0.6, 0.56 },
		railColor = { 0.68, 0.66, 0.62 },
		railOverlap = 1.0, -- fraction of a post's width each rail runs past its posts (no gaps)
	},

	pillars = {
		material = "Slate",
		color = { 0.42, 0.4, 0.38 }, -- the ceiling's stone
		ceilingGap = 4, -- studs between a pillar's top and the ceiling underside, room for the light to spread
		light = {
			angle = 180, -- a full hemisphere up onto the ceiling underside
			color = { 1, 0.9, 0.75 }, -- warm stone light (section 11: "lit from below by SurfaceLights")
			shadows = false,
		},
	},

	clouds = {
		particlesPerEmitter = 4, -- 24 emitters x 4 = 96 of the 400-particle budget
		lifetime = { min = 14, max = 20 },
		lightEmission = 0.15,
		spreadDegrees = 18, -- around the tangent the particles drift along
		rotationDegreesPerSecond = 2, -- +/- slow turn
		heightJitter = 30, -- the ring undulates this far above and below the drop
		radialJitter = 25,
		emitterPartSize = 1, -- the invisible host part
		color = { 1, 1, 1 },
		-- When fx.luau is present its High quality tier sets the emitter count; this is the fallback.
		fallbackCountKey = "cloudCount",
	},

	killVolume = {
		-- The kill volume is a check, not a trap: PlaygroundService kills any fighter whose root is
		-- below playground.killVolume.y on Heartbeat. The part only marks the plane for debugging.
		transparency = 1,
		checkInterval = 0.25, -- seconds between root-height scans
	},

	spawn = {
		-- A spawned pack member stands this far above its spawn point's ground: hipHeight plus half
		-- the root part (the Humanoid holds the root bottom at HipHeight above the floor).
		groundEpsilon = 0.05, -- lifted a hair so a rig never starts inside the field
	},

	character = {
		-- Humanoid scale NumberValues the engine reads (Humanoid children); PlaygroundService writes
		-- rigs.luau PlayerR15.scale into them.
		scaleValues = {
			bodyHeight = "BodyHeightScale",
			bodyWidth = "BodyWidthScale",
			bodyDepth = "BodyDepthScale",
			head = "HeadScale",
		},
		partWaitSeconds = 10, -- how long CharacterAdded waits for the Humanoid, the hand and a finished character (D-046)
	},

	anticheat = {
		-- Policy strings and the few knobs that are not in combat.luau's section 17 block
		-- (sample interval, speed cap, slack, teleport distance, kick threshold and window live there).
		shadowAttribute = "Shadowed", -- set true on the Player at shadowFraction of the kick threshold (routes to Trial servers later)
		shadowFraction = 0.5, -- fraction of combat.anomalyKickThreshold whose window weight sets the shadow flag
		teleportWeightCapFraction = 0.5, -- one teleport anomaly weighs at most this fraction of the kick threshold
		kickText = "The system has ended your session: anomalous movement.", -- the system line and the kick message
		lineToken = "SystemCyan", -- palette token of the system line
		kickDelay = 0.5, -- seconds between the system line and the kick, so the line is seen
		abuseWeight = 1, -- anomaly weight of one Net abuse report (rate limit or schema failure)
		speedWeight = 1, -- anomaly weight of one over-speed sample
		minimumAnomalies = 2, -- a kick needs at least this many separate anomalies (never on a single one)
		reasons = { speed = "speed", teleport = "teleport", abuse = "abuse" },
		-- Per-remote rate limits (section 17) for every client-to-server remote in net/Remotes.luau:
		-- requests per second refilled and the burst a bucket holds; a rejection is one abuse report
		-- weighted by abuseWeight. The client never sends BasicAttackRequest faster than its
		-- perSecond (ActionLogic.basicReady), so honest mashing stays inside the bucket and the
		-- burst only absorbs network jitter.
		-- A stall an honest client's paced sends must ride out without tripping its bucket: a
		-- clientBurst plus perSecond times this must fit inside burst.
		remoteStallSeconds = 0.3,
		remoteRates = {
			ClientReady = { perSecond = 1, burst = 2 },
			ArtRequest = { perSecond = 6, burst = 3 },
			BasicAttackRequest = { perSecond = 6, burst = 3 },
			GuardRequest = { perSecond = 12, burst = 6, clientBurst = 2 },
			DodgeRequest = { perSecond = 4, burst = 2 },
			TargetRequest = { perSecond = 8, burst = 4 },
			SwitchCallRequest = { perSecond = 2, burst = 2 },
		},
	},

	performance = {
		-- Section 16 "Performance targets per place". Parts and draw calls are fx.budgets.parts and
		-- fx.budgets.drawCalls (the section 11 scene budgets carry the same numbers); they are not
		-- repeated here. tests/smoke/perf.smoke.luau loads the Playground with testPlayers stand-ins
		-- and testEnemies enemies, lets it settle, samples every server frame and asserts the
		-- server work per frame at heartbeatPercentile and the part count. Memory is printed, not
		-- asserted: in Studio the engine reports the whole Studio process.
		maxServerHeartbeatMs = 12, -- server work per frame, at heartbeatPercentile of the sampled frames
		heartbeatPercentile = 0.95, -- fraction of sampled frames that must come in under the target
		maxMemoryMbPc = 1200, -- 1.2 GB
		maxMemoryMbMobile = 600,
		testPlayers = 8, -- section 16: "with 8 players and 60 enemies" (section 17: MaxPlayers 8)
		testEnemies = 60,
		settleSeconds = 5, -- after the last spawn, before sampling: brains aggro, paths compute, spawn hitches pass
		sampleSeconds = 20,
	},
}

return World
