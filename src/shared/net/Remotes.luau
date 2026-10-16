--!strict
--[[
	Remote definitions (section 17). Every remote has a kind, a direction, a payload schema and,
	for client-to-server remotes, a rate limit. The server validates every payload against the
	schema before any handler runs; a payload that fails is dropped and counted as an anomaly.

	Payloads are always one table. Entity ids are integers assigned by the server; positions and
	facings are plain {x, y, z} tables so schemas can check them.
]]

local Check = require(script.Parent.Parent.util.Check)

export type Kind = "Event" | "Unreliable" | "Function"
export type Direction = "ClientToServer" | "ServerToClient"

export type RemoteDef = {
	kind: Kind,
	direction: Direction,
	schema: Check.Checker,
	rate: { perSecond: number, burst: number }?, -- ClientToServer only
}

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
		rate = { perSecond = 1, burst = 2 },
	},
	ArtRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			artId = artId,
			facing = unitVec,
			clientTime = Check.number(0),
		}),
		rate = { perSecond = 6, burst = 3 },
	},
	BasicAttackRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			facing = unitVec,
			clientTime = Check.number(0),
		}),
		rate = { perSecond = 6, burst = 3 },
	},
	GuardRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			held = Check.boolean,
			facing = unitVec,
			clientTime = Check.number(0),
		}),
		rate = { perSecond = 12, burst = 6 },
	},
	DodgeRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			direction = Check.vec3(1.0001),
			clientTime = Check.number(0),
		}),
		rate = { perSecond = 4, burst = 2 },
	},
	TargetRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({
			entityId = Check.optional(entityId),
		}),
		rate = { perSecond = 8, burst = 4 },
	},
	SwitchCallRequest = {
		kind = "Event",
		direction = "ClientToServer",
		schema = Check.strictInterface({}),
		rate = { perSecond = 2, burst = 2 },
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
