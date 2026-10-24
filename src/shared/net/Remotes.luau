--!strict
--[[
	Remote definitions (section 17). Every remote has a kind, a direction, a payload schema and,
	for client-to-server remotes, a rate limit (world.luau anticheat.remoteRates, keyed by the
	remote's name). The server validates every payload against the schema before any handler runs;
	a payload that fails is dropped and counted as an anomaly.

	Payloads are always one table. Entity ids are integers assigned by the server; positions and
	facings are plain {x, y, z} tables so schemas can check them.
]]

local Check = require(script.Parent.Parent.util.Check)
local World = require(script.Parent.Parent.data.world)
local AI = require(script.Parent.Parent.data.ai)
local Combat = require(script.Parent.Parent.data.combat)

export type Kind = "Event" | "Unreliable" | "Function"
export type Direction = "ClientToServer" | "ServerToClient"

export type RemoteDef = {
	kind: Kind,
	direction: Direction,
	schema: Check.Checker,
	rate: { perSecond: number, burst: number }?, -- ClientToServer only
}

local rates = World.anticheat.remoteRates

local entityId = Check.integer(1)
local artId = Check.string(64)
local clipId = Check.string(96)
local unitVec = Check.vec3(1.0001)
local worldVec = Check.vec3(100000)
local hitStopTier = Check.literal("Normal", "Final", "Kill")
local telegraphKind = Check.literal("Normal", "Unblockable", "GuardBreak")
local shatterKind = Check.literal("Beast", "Construct", "Plant", "Humanoid", "Boss")
local entityState =
	Check.literal("Idle", "Moving", "Art", "PostMotion", "Guard", "GuardBroken", "Dodge", "Stagger", "Break", "Dead")
-- A swing's sequence number (item 4): the client numbers each swing it sends, the server echoes it
-- on that swing's HitConfirmed so a predicted hit matches the swing that made it.
local swingNumber = Check.optional(Check.integer(1, Combat.contact.swingSequenceMax))
local telegraphShape = Check.strictInterface({
	kind = Check.literal("Line", "Cone", "Circle"),
	length = Check.number(0, 200),
	width = Check.number(0, 360),
})

local Remotes: { [string]: RemoteDef } = {
	-- ------------------------------------------------------------------ client -> server
	ClientReady = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({}),
		rate = rates.ClientReady,
	},
	ArtRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			artId = artId,
			facing = unitVec,
			clientTime = Check.number(0),
			swing = swingNumber,
		}),
		rate = rates.ArtRequest,
	},
	BasicAttackRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			facing = unitVec,
			clientTime = Check.number(0),
			swing = swingNumber,
		}),
		rate = rates.BasicAttackRequest,
	},
	GuardRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			held = Check.boolean,
			facing = unitVec,
			clientTime = Check.number(0),
		}),
		rate = rates.GuardRequest,
	},
	DodgeRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			direction = Check.vec3(1.0001),
			clientTime = Check.number(0),
		}),
		rate = rates.DodgeRequest,
	},
	TargetRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			entityId = Check.optional(entityId),
		}),
		rate = rates.TargetRequest,
	},
	SwitchCallRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({}),
		rate = rates.SwitchCallRequest,
	},

	-- ------------------------------------------------------------------ server -> client (reliable)
	HitConfirmed = {
		kind = "Event",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			attackerId = entityId,
			targetId = entityId,
			damage = Check.number(0),
			crit = Check.boolean,
			gaugeDamage = Check.number(0),
			killed = Check.boolean,
			broke = Check.boolean,
			hitStop = hitStopTier,
			position = worldVec,
			parried = Check.boolean,
			guarded = Check.boolean,
			reflected = Check.boolean,
			artId = Check.optional(artId),
			hitIndex = Check.integer(0),
			isSwitch = Check.optional(Check.boolean),
			staggerDirection = Check.optional(Check.literal("Front", "Back", "Left", "Right")),
			-- D-168: present when the target is an enemy whose attack was unresolved (its wind-up, or its
			-- strike before it resolved): the seconds this hit pushed that attack's timeline back (0 once
			-- the per-attack cap is spent, or for a rush that has launched). Clients hold the enemy's
			-- attack clip and its telegraph for exactly this long; absent, they freeze it as for any hit.
			attackPause = Check.optional(Check.number(0, AI.hitStop.maxPausePerAttack)),
			-- The sequence number the hitting swing's request carried (absent for a request without
			-- one, and for every hit that is not a player's swing).
			swing = swingNumber,
		}),
	},
	EntityDied = {
		kind = "Event",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			entityId = entityId,
			shatter = shatterKind,
			position = worldVec,
			name = Check.string(64),
			byPlayer = Check.optional(Check.boolean),
		}),
	},
	StateChanged = {
		kind = "Event",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			entityId = entityId,
			state = entityState,
			duration = Check.optional(Check.number(0)),
			direction = Check.optional(Check.literal("Front", "Back", "Left", "Right")),
		}),
	},
	ActionRejected = {
		kind = "Event",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			action = Check.literal("Art", "BasicAttack", "Guard", "Dodge", "Target", "Switch"),
			reason = Check.string(96),
			clientTime = Check.optional(Check.number(0)),
		}),
	},
	SystemLine = {
		kind = "Event",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			text = Check.string(200),
			token = Check.string(32),
			chime = Check.optional(Check.string(48)),
		}),
	},

	-- ------------------------------------------------------------------ server -> client (unreliable)
	ActionStarted = {
		kind = "Unreliable",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			entityId = entityId,
			clipId = clipId,
			serverTime = Check.number(0),
			facing = unitVec,
			artId = Check.optional(artId),
			speed = Check.optional(Check.number(0.1, 4)),
		}),
	},
	Telegraph = {
		kind = "Unreliable",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			entityId = entityId,
			attackId = Check.string(64),
			kind = telegraphKind,
			windUp = Check.number(0),
			serverTime = Check.number(0),
			origin = worldVec,
			facing = unitVec,
			shape = Check.optional(telegraphShape),
		}),
	},
	-- D-169: a Charger's rush launched. Clients draw the body down the line on the server's clock,
	-- distance = speed * clamp(serverNow - serverTime, 0, duration) from `origin`, instead of
	-- waiting for the replicated root, so the snout reaches a player when the server's hit does.
	RushStarted = {
		kind = "Unreliable",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			entityId = entityId,
			attackId = Check.string(64),
			serverTime = Check.number(0), -- the launch beat: telegraph serverTime + windUp + pauses (D-182)
			origin = worldVec, -- the crouch point (the root's position)
			direction = unitVec, -- along the telegraphed line
			speed = Check.number(0),
			duration = Check.number(0), -- seconds the run lasts (reach + overshoot) / speed
		}),
	},
	-- D-169: the rush stopped before its duration ran out. `launchedAt` is the RushStarted serverTime
	-- it ends; `distance` how far down the line the server's body stands. "Jammed" bodies keep
	-- striking on the clock (the hits never wait for the body); the others have stopped for good.
	RushEnded = {
		kind = "Unreliable",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			entityId = entityId,
			launchedAt = Check.number(0),
			serverTime = Check.number(0),
			distance = Check.number(0),
			reason = Check.literal("Jammed", "Interrupted", "Died", "Stopped"),
		}),
	},
	SwitchWindow = {
		kind = "Unreliable",
		direction = "ServerToClient",
		schema = Check.strictInterface({
			entityId = entityId,
			openerId = entityId,
			position = worldVec,
			duration = Check.number(0),
			serverTime = Check.number(0),
		}),
	},
}

return Remotes
