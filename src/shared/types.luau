--!strict
--[[
	Shared Luau types for Skyspire.

	Every table that crosses a module boundary (data rows, clip definitions, remote payloads,
	service records) is described here so that `--!strict` can check it everywhere.
	Numbers that tune the game never live here; they live in `src/shared/data/`.
]]

local Types = {}

-- ---------------------------------------------------------------------------------------------
-- Enumerations (string unions so they are readable in data tables and in the debugger)
-- ---------------------------------------------------------------------------------------------

export type WeaponCategory =
	"OneHandedSword"
	| "Rapier"
	| "TwoHandedSword"
	| "Katana"
	| "Dagger"
	| "Spear"
	| "Axe"
	| "Mace"
	| "Shield"
	| "MartialArts"
	| "TwinFang"
	| "AegisBlade"

export type Archetype =
	"Charger"
	| "Brute"
	| "Skirmisher"
	| "Lancer"
	| "Swarm"
	| "Guard"
	| "CasterBeast"
	| "Stalker"
	| "WardenConstruct"

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Apex"

-- White / red / yellow telegraph edge (section 6).
export type TelegraphKind = "Normal" | "Unblockable" | "GuardBreak"

export type ThreatBand = "Verge" | "Reach" | "Blight"

-- 3 / 6 / 10 frames of hit-stop (section 6).
export type HitStopTier = "Normal" | "Final" | "Kill"

export type StatusKind = "Bleed" | "Poison" | "Paralysis" | "Stun" | "Burn" | "Freeze"

export type ShatterKind = "Beast" | "Construct" | "Plant" | "Humanoid" | "Boss"

export type CursorColor = "Green" | "Orange" | "Red"

export type EquipSlot = "Weapon" | "OffHand" | "Chest" | "Legs" | "Hands" | "Boots" | "Head" | "OverLayer" | "Accessory"

export type Precondition = "Standing" | "Moving" | "Airborne" | "AfterParry"

export type Quality = "High" | "Medium" | "Low"

-- ---------------------------------------------------------------------------------------------
-- Plain-number geometry (no Roblox datatypes at module load; see docs/DECISIONS.md D-003)
-- ---------------------------------------------------------------------------------------------

export type Vec3 = { number } -- { x, y, z }
export type ColorRGB = { number } -- { r, g, b } in 0..1

-- ---------------------------------------------------------------------------------------------
-- Blade Arts (section 8)
-- ---------------------------------------------------------------------------------------------

export type ArtDef = {
	id: string, -- "OneHandedSword.Horizontal"
	name: string, -- "Horizontal"
	weapon: WeaponCategory,
	unlock: number, -- proficiency required, 0..1000
	hits: number, -- damage windows in the clip
	startup: number, -- seconds; includes the 0.15 s start pose and 0.1 s activation hold
	total: number, -- seconds from input to the last hit
	postMotion: number, -- seconds locked in the end pose after the last hit
	multiplier: number, -- damage multiplier per hit against weapon attack
	gaugeDamage: number, -- Guard Gauge damage per hit
	rootMotion: number, -- studs carried forward across the execution
	clip: string, -- clip id, e.g. "player/OneHandedSword/Horizontal"
	preconditions: { Precondition }?, -- which stance the pose system needs to pick this Art
	ultimate: boolean?,
	note: string?,
}

-- ---------------------------------------------------------------------------------------------
-- Items (sections 8, 12, 13)
-- ---------------------------------------------------------------------------------------------

export type WeaponDef = {
	id: string,
	name: string,
	category: WeaponCategory,
	rarity: Rarity,
	attack: number,
	gaugeDamage: number,
	durability: number,
	weight: number, -- counts against the STR weight limit
	trailWidth: number, -- studs
	trailColor: string, -- palette token name
	reach: number, -- studs; the capsule sweep length
	floor: number,
	slots: number, -- enhancement slots 0..5
	named: boolean?, -- a named weapon (section 8) that is also a skin once owned
	source: string?, -- "LAB" | "FieldBoss" | "MiniDungeon" | "Smith" | "Drop" | "Vendor"
}

export type ArmorDef = {
	id: string,
	name: string,
	slot: EquipSlot,
	rarity: Rarity,
	defense: number,
	weight: number,
	agiPenalty: number, -- flat AGI lost while worn (heavy sets)
	durability: number,
	floor: number,
	set: string?, -- Apex set id when part of one
}

-- ---------------------------------------------------------------------------------------------
-- Enemies (section 9)
-- ---------------------------------------------------------------------------------------------

export type EnemyAttackDef = {
	id: string,
	name: string,
	telegraph: TelegraphKind,
	windUp: number, -- seconds the wind-up pose is held (>= 0.3 by rule)
	strike: number, -- seconds from the end of wind-up to the hit
	recovery: number, -- seconds before the next decision
	multiplier: number, -- damage = attack * multiplier
	gaugeDamage: number,
	reach: number, -- studs
	arc: number, -- degrees of the hit cone, 0 for a line
	clip: string,
	groundShape: ("Line" | "Cone" | "Circle")?, -- telegraph decal shape on the ground
	status: StatusKind?,
}

export type EnemyDef = {
	id: string,
	name: string,
	archetype: Archetype,
	skin: string, -- rig id in rigs.luau / asset name in assets.luau
	floor: number,
	tier: number, -- scales numbers with tiers.luau
	band: ThreatBand,
	hp: number,
	attack: number,
	defense: number,
	guardGauge: number,
	guardRegenPerSecond: number, -- fraction of max gauge per second (section 6: 0.10)
	moveSpeed: number, -- studs per second
	aggroRange: number,
	leashRange: number,
	attacks: { EnemyAttackDef },
	shatter: ShatterKind,
	xp: number,
	lootTable: string,
	elite: boolean?,
	night: boolean?,
}

-- ---------------------------------------------------------------------------------------------
-- Choreo clips (section 10)
-- ---------------------------------------------------------------------------------------------

-- Linear is only permitted on the root and on the camera; a limb key with Linear fails validation.
export type Easing =
	"Linear"
	| "ExpoOut"
	| "ExpoIn"
	| "BackOut"
	| "Spring"
	| "SineInOut"
	| "QuadIn"
	| "QuadOut"
	| "Hold"

export type JointKey = {
	pos: Vec3?, -- studs, offset from the joint's rest C0
	rot: Vec3?, -- degrees, XYZ Euler offset from the joint's rest C0
}

export type ClipKey = {
	time: number, -- seconds from clip start
	easing: Easing, -- easing INTO this key from the previous one
	joints: { [string]: JointKey },
	root: JointKey?, -- root motion offset at this key (studs, degrees), applied to HumanoidRootPart
}

export type ClipEventKind =
	"HitWindowOpen"
	| "HitWindowClose"
	| "TrailOn"
	| "TrailOff"
	| "SmearOn"
	| "SmearOff"
	| "Footstep"
	| "Voice"
	| "Sfx"
	| "ActivationHold"
	| "PostMotionStart"
	| "WeaponSwap"
	| "CameraNudge"
	| "WeaponDraw" -- the hand takes the sword from its sheath
	| "WeaponSheathe" -- the sword goes back into its sheath

export type ClipEvent = {
	time: number,
	kind: ClipEventKind,
	data: { [string]: any }?,
}

-- The six beats of every attack (section 10). An attack clip must define all six.
export type Beat = "Anticipation" | "Snap" | "Smear" | "Hold" | "Settle" | "Recovery"

export type BeatSpan = { start: number, finish: number }

export type ClipLayer = "Base" | "UpperBody" | "Additive" | "FullBody"

export type ClipDef = {
	id: string, -- "player/OneHandedSword/Horizontal"
	rig: string, -- rig id from rigs.luau
	duration: number, -- seconds
	loop: boolean,
	sheathed: boolean?, -- the sword starts this clip on its sheath (back mount), not in the hand
	layer: ClipLayer,
	keys: { ClipKey },
	events: { ClipEvent },
	beats: { [Beat]: BeatSpan }?, -- required for attack clips (attack = true)
	attack: boolean?,
	hitStop: HitStopTier?,
	priority: number?, -- higher wins inside a layer
	blendIn: number?, -- seconds, default from choreo data
	blendOut: number?,
}

-- ---------------------------------------------------------------------------------------------
-- Rigs (section 10)
-- ---------------------------------------------------------------------------------------------

export type RigJoint = {
	name: string, -- joint name (a Motor6D or AnimationConstraint), e.g. "RightShoulder"
	part0: string, -- parent part name
	part1: string, -- child part name
	c0: { pos: Vec3, rot: Vec3 }, -- rest pose
	size: Vec3?, -- placeholder part size when the rig is part-built
	color: string?, -- palette token for placeholder parts
}

export type RigDef = {
	id: string, -- "PlayerR15" | "Boar" | "Kobold"
	rootPart: string,
	joints: { RigJoint },
	weaponGrip: string?, -- part name that carries the WeaponGrip attachment
	trailParts: { string }?, -- parts that carry TrailStart/TrailEnd attachments
	hipHeight: number,
	placeholder: boolean,
	assetKey: string?, -- key in assets.luau when a mesh rig exists
}

-- ---------------------------------------------------------------------------------------------
-- Combat records (server-side; section 6)
-- ---------------------------------------------------------------------------------------------

export type EntityKind = "Player" | "Enemy"

export type EntityState =
	"Idle"
	| "Moving"
	| "Art"
	| "PostMotion"
	| "Guard"
	| "GuardBroken"
	| "Dodge"
	| "Stagger"
	| "Break"
	| "Dead"

export type Stats = {
	str: number,
	agi: number,
	level: number,
}

export type HitResult = {
	attackerId: number,
	targetId: number,
	damage: number,
	crit: boolean,
	gaugeDamage: number,
	killed: boolean,
	broke: boolean, -- the hit emptied the Guard Gauge
	hitStop: HitStopTier,
	position: Vec3,
	parried: boolean,
	guarded: boolean,
	reflected: boolean, -- Mirror Shield (Phase 1)
	artId: string?,
	hitIndex: number,
}

-- ---------------------------------------------------------------------------------------------
-- Telegraph broadcast (section 11)
-- ---------------------------------------------------------------------------------------------

export type TelegraphShape = {
	kind: "Line" | "Cone" | "Circle",
	length: number,
	width: number, -- line width or cone angle in degrees or circle radius
}

-- ---------------------------------------------------------------------------------------------
-- Floor bosses (section 9; rows live in data/bosses.luau)
-- ---------------------------------------------------------------------------------------------

export type BossMechanicKind =
	"Lockstep" -- two players must act within the window or the room punishes everyone
	| "Summon" -- a guard pack or adds appear
	| "Hazard" -- the room itself attacks (fire pools, flood, fog, darkness)
	| "WeaponSwap" -- the boss changes weapon or body on this bar
	| "Shield" -- a Mirror Shield or phase shield rule
	| "Terrain" -- platforms, pillars, cover the party must use
	| "Illusion" -- false copies of the boss

export type BossMechanicDef = {
	id: string,
	name: string,
	kind: BossMechanicKind,
	description: string, -- one line for the bestiary and the designer
	window: number?, -- seconds two players have for a Lockstep (defaults to Bosses.rules.lockstepWindow)
	targets: number?, -- totems, chains, hearts... to strike together
	interval: number?, -- seconds between repeats (summons, hazards)
	failure: string?, -- what happens when the mechanic is not answered
}

export type BossSummonDef = { enemyId: string, count: number }

export type BossPhaseDef = {
	bar: number, -- the HP bar (1 = the first bar) this phase starts on
	name: string,
	summary: string, -- one line, the designer's intent
	archetype: Archetype?, -- behavior module the phase borrows (a treant uproots into a Brute)
	attacks: { EnemyAttackDef }, -- telegraphed enemy attacks available in this phase
	arts: { string }?, -- player Art ids the boss executes with its own rig (Grolak's curved blade)
	mechanics: { BossMechanicDef },
	summons: { BossSummonDef }?, -- guard pack called when the phase starts
	weapon: string?, -- weapon id drawn on this bar (WeaponSwap)
	attackSpeed: number?, -- multiplier on telegraph and strike timing in this phase
}

export type BossDef = {
	id: string, -- "Grolak"
	name: string, -- "Grolak, Kobold Warlord"
	floor: number,
	tier: number,
	skin: string, -- rig id / asset key
	bars: number, -- 4 to 6 HP bars
	hpPerBar: number, -- tier-1 base; total HP = bars * hpPerBar * tier.hp
	attack: number,
	defense: number,
	guardGauge: number,
	guardRegenPerSecond: number,
	moveSpeed: number,
	phases: { BossPhaseDef }, -- one entry per bar group, ascending by bar; the first starts on bar 1
	guardPack: { BossSummonDef }, -- minions at the entrance
	lockstep: BossMechanicDef, -- the signature two-player mechanic
	enrage: { startSeconds: number, damagePerMinute: number },
	mirrorShield: boolean, -- true for every boss (section 7); the Iron Bulwark Golem never drops it
	lootTable: string,
	lab: string, -- the Last Attack Bonus item id (weapons.luau or armor.luau)
	shatter: ShatterKind,
	xp: number, -- a level's worth to the raid at tier 1
	chamber: string?, -- scene notes for the boss room
}

-- ---------------------------------------------------------------------------------------------
-- Entity registry (server-side; ARCHITECTURE "Entities", section 6 / 16 / 17)
-- ---------------------------------------------------------------------------------------------

-- What PlaygroundService hands EntityService.registerPlayer (from playground.luau's loadout).
export type Loadout = {
	level: number,
	str: number,
	agi: number,
	proficiency: { [WeaponCategory]: number },
	weapon: string, -- weapon def id
	armor: { [EquipSlot]: string }?, -- armor def ids by slot; defense is their flat sum
	artSlots: { string }?,
	hasShield: boolean?, -- widens the guard cone and raises the reduction (section 6)
}

-- The server's record of one fighter. EntityService owns every field; other services read
-- through its API and change state through its functions, never by writing here.
export type EntityRecord = {
	id: number,
	kind: EntityKind,
	defId: string, -- enemy def id, or "Player"
	name: string, -- DisplayName attribute
	model: Model,
	rig: string, -- rig id in rigs.luau
	hp: number,
	maxHp: number,
	gauge: number,
	maxGauge: number,
	gaugeRegenPerSecond: number, -- fraction of maxGauge per second
	defense: number,
	attack: number, -- enemies: def attack; players: the equipped weapon's attack
	stats: Stats,
	state: EntityState,
	stateTag: string?, -- "Basic" while the Art state is a basic-attack swing (cancelable)
	stateUntil: number?, -- server time the state expires on its own
	lockUntil: number, -- server time the body is free again (Art, post-motion, stagger, dodge)
	guardHeld: boolean,
	guardSince: number?, -- server receipt time of GuardRequest {held = true}; nil while the raise cannot parry
	guardReleasedAt: number?, -- last release; a raise inside combat.parryRearmTime after it cannot parry
	hasShield: boolean,
	invulnerableUntil: number,
	combatUntil: number, -- in combat while now < combatUntil
	lastCombatAt: number?, -- last hit dealt or taken; HP regen waits on it
	hpRegenHeld: boolean?, -- true while EnemyService holds the fighter (D-120): no HP regen at all
	lastArtHitAt: number?, -- last Art hit taken; Guard Gauge regen waits on it
	proficiency: { [WeaponCategory]: number },
	weaponId: string?,
	threat: { [number]: number }, -- attacker id -> accumulated threat
	targetId: number?, -- lock-on target (TargetRequest)
	player: Player?,
	enemyDef: EnemyDef?,
	shatter: ShatterKind,
	level: number,
	killedBy: number?,
	diedAt: number?,
	artSlots: { string }?, -- quick-slot Art ids copied from the loadout; nil (enemies, stand-ins, tests) skips the slot check
}

-- What CombatService hands EntityService.applyHit: the attack side of a hit, before defense.
export type HitRequest = {
	attackerId: number,
	rawDamage: number, -- weaponAttack * multiplier * STR * crit (* Switch / Tempo), before defense
	gaugeDamage: number,
	crit: boolean,
	parried: boolean,
	guarded: boolean,
	breakGuard: boolean?, -- GuardBreak telegraph: empties the gauge outright
	isBasic: boolean?, -- basic attacks do not pause Guard Gauge regen
	artId: string?,
	hitIndex: number,
	hitStop: HitStopTier,
	position: Vec3,
}

-- EntityService.applyHit's result: a HitResult plus what the server needed to know afterwards.
export type AppliedHit = HitResult & {
	wasInBreak: boolean, -- the target was in Break when the hit landed (zero post-motion)
	hpAfter: number,
	gaugeAfter: number,
	staggerDirection: ("Front" | "Back" | "Left" | "Right")?,
}

-- CombatService.enemyStrike's optional fifth argument: how a moving strike (a Charger's rush)
-- resolves in stretches as its body sweeps the line (D-166). A call without it resolves the whole
-- attack shape at once, as every strike did before.
export type EnemyStrikeOptions = {
	-- Line strikes: only this stretch of the line, in studs along it from the origin, counts.
	span: { from: number, to: number }?,
	-- Target ids this attack already resolved (hit, parried, guarded or dodged): skipped, and every
	-- target this call reaches is added, so each is resolved once per attack.
	resolved: { [number]: boolean }?,
}

-- Why a rush stopped early (the RushEnded remote, D-169).
export type RushEndReason = "Jammed" | "Interrupted" | "Died" | "Stopped"

Types.VERSION = 1

return Types
