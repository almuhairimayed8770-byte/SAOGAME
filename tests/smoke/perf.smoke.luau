--!strict
--[[
	Performance smoke (run-in-roblox, Playground place): the server half of section 16
	"Performance targets per place" (docs/STUDIO_TASKS.md step 15). Plain Luau run on the server
	after Main has started everything. Every target and the load come from data:
	world.luau `performance` (heartbeat, memory, testPlayers, testEnemies, settle and sample time)
	and fx.luau `budgets` (parts, draw calls).

	1. Registers world.performance.testPlayers R15 stand-ins as players, spread on a ring around
	   the Playground field, each holding the loadout weapon WeaponBuilder hangs from its hand the
	   way PlaygroundService does for a real character. EnemyService's own player source is
	   EntityService.players(), so a registered stand-in is a target exactly like a real character
	   and no seam is swapped: the frame carries the production deps (real Net.fireAll, real player
	   list, real CombatService). Every fighter is healed back to full inside the hit that hurt it
	   (EntityService.HpChanged runs its handlers on task.spawn, before applyHit reads the HP back),
	   so hits, staggers, Breaks and attribute publishes all run but nobody dies: no stand-in drops
	   out of the brains' target lists and no enemy leaves the count.
	2. Tops EnemyService up to testEnemies with EnemyService.spawn, mixing the Phase 0 archetypes
	   in the Playground spawn-table order, clustered around the stand-ins so brains aggro,
	   telegraph and strike (CombatService.enemyStrike -> HitSweep) through the whole sample.
	   PlaygroundService's own first wave counts toward the total.
	3. Waits settleSeconds, then samples every server frame for sampleSeconds. Through the sample
	   the stand-ins fight back: every stand-in that is free turns to its nearest enemy and starts
	   the next Art of the loadout's quick slots through CombatService.beginArt, all of them on the
	   same frame at the start, so the server sweeps up to testPlayers blades at once (the arc
	   sub-samples of HitSweep.followArc included) on top of the enemies' strikes:
	   - server work per frame: os.clock from the frame's first PreAnimation / PreSimulation to the
	     end of its Heartbeat handlers (a task.defer queued from a Heartbeat handler runs after
	     every handler of that Heartbeat). This is the number asserted against
	     maxServerHeartbeatMs at heartbeatPercentile;
	   - the frame period (Heartbeat dt);
	   - Stats.HeartbeatTime and Stats.PhysicsStepTime (engine figures in seconds, reported in ms;
	     the deprecated HeartbeatTimeMs / PhysicsStepTimeMs are read only when the new ones are
	     not). Stats.HeartbeatTime is printed and warned on, not asserted: in a Studio Run session
	     the "server" is the Studio process, so the timed work above is the server-only number;
	   - Stats.InstanceCount and Stats.PrimitivesCount; Stats:GetTotalMemoryUsageMb() twice a second;
	   - BaseParts under workspace, counted before and after the sample (never per frame: a full
	     descendant walk would add its own cost to the frames it measures).
	4. Prints mean / p95 / max, then Markdown rows for the Performance table in docs/PROGRESS.md.
	5. Cleans up everything it spawned, then asserts: the load held (no stand-in died, the enemy
	   count never fell under testEnemies, hits landed, wind-ups were seen), the server work
	   percentile is under maxServerHeartbeatMs, and workspace parts are under fx.budgets.parts.
	   Memory is printed, not asserted: in Studio it covers the whole Studio process. Draw calls and
	   client fps cannot be read from a server script; they come from the MicroProfiler in Play mode.

	Run: tools/smoke.sh perf (installs this file as a server Script in a Run session of the
	Playground; see tools/smoke/SmokeRunner.luau). Errors on the first failed assertion, which the
	runner reports as SMOKE-RESULT: FAIL. Must not return at top level. Not runnable under Lune.

	First run on the owner's PC on 2026-10-18 (docs/PROGRESS.md > Performance).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Stats = game:GetService("Stats")

local PREFIX = "[perf.smoke]"
local READY_ATTRIBUTE = "SkyspireReady"
local READY_TIMEOUT = 15

-- A child the Rojo build puts in place, waited for with a timeout so a broken build fails instead of hanging.
local function childOf(parent: Instance, name: string): Instance
	local child = parent:WaitForChild(name, READY_TIMEOUT)
	if child == nil then
		error(("%s FAILED: %s.%s did not appear within %d s"):format(PREFIX, parent.Name, name, READY_TIMEOUT), 0)
	end
	return child :: Instance
end

local Shared = childOf(ReplicatedStorage, "Shared")
local Server = childOf(ServerScriptService, "Server")

local World = require(Shared.data.world)
local Fx = require(Shared.data.fx)
local Rigs = require(Shared.data.rigs)
local Enemies = require(Shared.data.enemies)
local Playground = require(Shared.data.playground)
local EntityService = require(Server.services.EntityService)
local CombatService = require(Server.services.CombatService)
local EnemyService = require(Server.services.EnemyService)
local AntiCheatService = require(Server.services.AntiCheatService)
local PlaygroundLayout = require(Server.world.PlaygroundLayout)
local WeaponBuilder = require(Server.world.WeaponBuilder)
local Weapons = require(Shared.data.weapons)

local STAND_IN_RING = 90 -- studs from the field center to each stand-in (the field is 200 in radius)
local ENEMY_DISTANCES = { 10, 16, 22 } -- studs from its stand-in, cycled: inside both archetypes' aggro range
local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5)) -- radians between cluster members, so none line up
local PHASE_POLL_SECONDS = 0.1 -- brain phases and the enemy count are polled this often while sampling
local MEMORY_SAMPLE_SECONDS = 0.5
local PERIOD_MATCH_TOLERANCE = 0.1 -- an engine heartbeat within 10% of the frame period reads as the period
local MS_PER_SECOND = 1000
local MB_PER_GB = 1000

local performance = World.performance
local PERCENTILE_LABEL = ("p%d"):format(math.floor(performance.heartbeatPercentile * 100 + 0.5))
local HOW = ("run-in-roblox, %d stand-ins swinging Arts, %d enemies, server only"):format(
	performance.testPlayers,
	performance.testEnemies
)

local function check(condition: boolean, message: string)
	if not condition then
		error(PREFIX .. " FAILED: " .. message, 0)
	end
	print(PREFIX .. " ok: " .. message)
end

local function report(message: string)
	print(PREFIX .. " " .. message)
end

-- ------------------------------------------------------------------------------------------
-- Number helpers
-- ------------------------------------------------------------------------------------------

type Summary = { count: number, mean: number, percentile: number, max: number }

-- Mean, the heartbeat percentile (nearest rank) and the max of a sample, or nil when it is empty.
local function summarize(values: { number }): Summary?
	local count = #values
	if count == 0 then
		return nil
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local total = 0
	for _, value in sorted do
		total += value
	end
	local rank = math.clamp(math.ceil(performance.heartbeatPercentile * count), 1, count)
	return { count = count, mean = total / count, percentile = sorted[rank], max = sorted[count] }
end

-- 60000 -> "60,000"
local function withCommas(value: number): string
	local digits = tostring(math.floor(value + 0.5))
	local sign = ""
	if digits:sub(1, 1) == "-" then
		sign = "-"
		digits = digits:sub(2)
	end
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if grouped:sub(1, 1) == "," then
		grouped = grouped:sub(2)
	end
	return sign .. grouped
end

-- A target: 1200 -> "1.2 GB", 600 -> "600 MB"
local function formatTargetMb(megabytes: number): string
	if megabytes >= MB_PER_GB then
		return ("%g GB"):format(megabytes / MB_PER_GB)
	end
	return ("%s MB"):format(withCommas(megabytes))
end

-- A measurement: 1850.4 -> "1,850 MB"
local function formatMb(megabytes: number): string
	return ("%s MB"):format(withCommas(megabytes))
end

local function describeMs(summary: Summary?): string
	if summary == nil then
		return "no samples"
	end
	return ("mean %.2f ms, %s %.2f ms, max %.2f ms (%d frames)"):format(
		summary.mean,
		PERCENTILE_LABEL,
		summary.percentile,
		summary.max,
		summary.count
	)
end

local function describeCount(summary: Summary?): string
	if summary == nil then
		return "no samples"
	end
	return ("mean %s, %s %s, max %s"):format(
		withCommas(summary.mean),
		PERCENTILE_LABEL,
		withCommas(summary.percentile),
		withCommas(summary.max)
	)
end

local function countBaseParts(root: Instance?): number
	if root == nil then
		return 0
	end
	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- A reader for a numeric Stats property, or nil when this context cannot read it.
local function statReader(name: string): (() -> number)?
	local ok, value = pcall(function(): any
		return (Stats :: any)[name]
	end)
	if not ok or typeof(value) ~= "number" then
		return nil
	end
	return function(): number
		return (Stats :: any)[name]
	end
end

-- ------------------------------------------------------------------------------------------
-- Ready
-- ------------------------------------------------------------------------------------------

local waited = 0
while workspace:GetAttribute(READY_ATTRIBUTE) ~= true and waited < READY_TIMEOUT do
	waited += task.wait(0.1)
end
check(workspace:GetAttribute(READY_ATTRIBUTE) == true, "server services are up")

-- ------------------------------------------------------------------------------------------
-- The stand-ins: anchored R15 rigs registered as players, on a ring around the field
-- ------------------------------------------------------------------------------------------

type StandIn = { id: number, model: Model, root: BasePart, player: any }

local standIns: { StandIn } = {}
local standInIds: { [number]: boolean } = {}
local kicks = 0
local standInDeaths = 0
local entitiesFolder = workspace:FindFirstChild(World.playground.folders.entities) or workspace

-- A player-like table: what EntityService, AntiCheatService and the respawn path may call on it.
local function fakePlayer(index: number): any
	local fake: any = {
		Name = ("PerfStandIn%d"):format(index),
		DisplayName = ("Stand-in %d"):format(index),
		UserId = -index,
		Parent = nil,
		attributes = {},
	}
	function fake.Kick(_self: any, _text: string?)
		kicks += 1
	end
	function fake.SetAttribute(self: any, name: string, value: any)
		self.attributes[name] = value
	end
	function fake.GetAttribute(self: any, name: string): any
		return self.attributes[name]
	end
	function fake.LoadCharacter(_self: any) end
	return fake
end

local standInHeight = Rigs.PlayerR15.hipHeight + 1
for index = 1, performance.testPlayers do
	local angle = (index - 1) / performance.testPlayers * 2 * math.pi
	local position = Vector3.new(math.cos(angle) * STAND_IN_RING, standInHeight, math.sin(angle) * STAND_IN_RING)
	local description = Instance.new("HumanoidDescription")
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	model.Name = ("PerfStandIn%d"):format(index)
	model.Parent = entitiesFolder
	model:PivotTo(CFrame.lookAt(position, Vector3.new(0, position.Y, 0)))
	local rootPart = model.PrimaryPart or model:FindFirstChild(Rigs.PlayerR15.rootPart)
	check(rootPart ~= nil and rootPart:IsA("BasePart"), model.Name .. " has a HumanoidRootPart")
	local root = rootPart :: BasePart
	model.PrimaryPart = root -- EntityService reads the root through PrimaryPart
	root.Anchored = true
	-- The weapon a real character gets from PlaygroundService: without TrailStart / TrailEnd the
	-- server cannot sweep its swings, and the sweep is the cost this smoke has to include.
	local weaponDef = Weapons.byId(Playground.loadout.weapon)
	check(weaponDef ~= nil, "the loadout weapon exists")
	check(model:WaitForChild("RightHand", READY_TIMEOUT) ~= nil, model.Name .. " has a RightHand for the weapon")
	WeaponBuilder.equip(model, weaponDef :: any)
	local player = fakePlayer(index)
	local id = EntityService.registerPlayer(player, model, Playground.loadout)
	table.insert(standIns, { id = id, model = model, root = root, player = player })
	standInIds[id] = true
end
check(#EntityService.players() >= performance.testPlayers, ("%d stand-ins are registered as players"):format(#standIns))

-- Keep every fighter standing: heal a hurt stand-in or enemy back to full inside the hit that
-- hurt it. These stay connected until the stand-ins are gone; the sampler's own connections go first.
local standInConnections: { any } = {}
table.insert(
	standInConnections,
	EntityService.HpChanged:Connect(function(record: any, oldHp: number, newHp: number)
		if newHp < oldHp and record.state ~= "Dead" then
			EntityService.heal(record.id, record.maxHp - newHp)
		end
	end)
)
table.insert(
	standInConnections,
	EntityService.Died:Connect(function(record: any)
		if standInIds[record.id] then
			standInDeaths += 1
		end
	end)
)

-- ------------------------------------------------------------------------------------------
-- The enemies: top EnemyService up to testEnemies, clustered around the stand-ins
-- ------------------------------------------------------------------------------------------

local mix: { string } = {}
for _, spawn in Playground.spawns do
	table.insert(mix, spawn.enemy)
end
check(#mix > 0, "the Playground spawn table names the Phase 0 archetypes")

local function rootHeightOf(defId: string): number
	local def = Enemies.byId(defId)
	if def == nil then
		error(("%s FAILED: the spawn table names unknown enemy %s"):format(PREFIX, defId), 0)
	end
	local rig = (Rigs :: any)[def.skin]
	if rig == nil then
		error(("%s FAILED: %s uses rig %s, which rigs.luau does not define"):format(PREFIX, defId, def.skin), 0)
	end
	local rootSpec = if rig.parts ~= nil then rig.parts[rig.rootPart] else nil
	local rootSizeY = if rootSpec ~= nil then rootSpec.size[2] else 0
	return PlaygroundLayout.rootHeight(rig.hipHeight, rootSizeY, World.spawn.groundEpsilon)
end

local waveCount = EnemyService.count() -- PlaygroundService's first wave
local spawnedIds: { number } = {}
local spawnedByDef: { [string]: number } = {}
local needed = math.max(0, performance.testEnemies - waveCount)
for index = 1, needed do
	local defId = mix[(index - 1) % #mix + 1]
	local standIn = standIns[(index - 1) % #standIns + 1]
	local member = math.floor((index - 1) / #standIns) -- 0-based place in this stand-in's cluster
	local distance = ENEMY_DISTANCES[member % #ENEMY_DISTANCES + 1]
	local angle = member * GOLDEN_ANGLE
	local center = standIn.root.Position
	local from =
		Vector3.new(center.X + math.cos(angle) * distance, rootHeightOf(defId), center.Z + math.sin(angle) * distance)
	local id = EnemyService.spawn(defId, CFrame.lookAt(from, Vector3.new(center.X, from.Y, center.Z)))
	table.insert(spawnedIds, id)
	spawnedByDef[defId] = (spawnedByDef[defId] or 0) + 1
end
check(
	EnemyService.count() >= performance.testEnemies,
	("%d enemies are alive (%d from the Playground wave, %d spawned here)"):format(
		EnemyService.count(),
		waveCount,
		#spawnedIds
	)
)

local landedOnStandIns = 0
local landedByStandIns = 0
local sampling = false
local sampleConnections: { any } = {} -- engine and Signal connections alike
table.insert(
	sampleConnections,
	CombatService.HitLanded:Connect(function(hit: any)
		if sampling and standInIds[hit.targetId] then
			landedOnStandIns += 1
		end
		if sampling and standInIds[hit.attackerId] then
			landedByStandIns += 1
		end
	end)
)

-- The stand-ins fight back: each free one turns to its nearest enemy and starts the next Art of
-- the loadout's quick slots. An anchored root is turned in place (no travel for the anti-cheat).
local artSlots = Playground.loadout.artSlots
local nextArt: { [number]: number } = {}
local artsStarted = 0
local artsRefused: { [string]: number } = {}

local function nearestEnemyPosition(from: Vector3): Vector3?
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, id in EnemyService.ids() do
		local model = EnemyService.modelOf(id)
		local root = if model ~= nil then model.PrimaryPart else nil
		if root ~= nil then
			local distance = (root.Position - from).Magnitude
			if distance < bestDistance then
				best = root.Position
				bestDistance = distance
			end
		end
	end
	return best
end

local function swingFreeStandIns()
	for _, standIn in standIns do
		local record = EntityService.get(standIn.id)
		if record ~= nil and (record.state == "Idle" or record.state == "Moving") then
			local at = standIn.root.Position
			local enemy = nearestEnemyPosition(at)
			if enemy ~= nil and (Vector3.new(enemy.X, at.Y, enemy.Z) - at).Magnitude > 0 then
				standIn.root.CFrame = CFrame.lookAt(at, Vector3.new(enemy.X, at.Y, enemy.Z))
			end
			local slot = nextArt[standIn.id] or 1
			local ok, reason =
				CombatService.beginArt(standIn.id, artSlots[(slot - 1) % #artSlots + 1], standIn.root.CFrame.LookVector)
			if ok then
				artsStarted += 1
				nextArt[standIn.id] = slot + 1
			else
				local key = tostring(reason)
				artsRefused[key] = (artsRefused[key] or 0) + 1
				if key ~= "Locked" and key:sub(1, 5) ~= "Busy:" then
					nextArt[standIn.id] = slot + 1 -- an Art this body can never start now: try the next
				end
			end
		end
	end
end

report(("settling for %g s"):format(performance.settleSeconds))
task.wait(performance.settleSeconds)

-- ------------------------------------------------------------------------------------------
-- The sample
-- ------------------------------------------------------------------------------------------

-- A Stats property and the factor that turns its value into the reported unit (ms, or a count).
type StatSource = { name: string, scale: number }
type StatSeries = { name: string, read: () -> number, values: { number } }

-- A series over the first readable property of `sources` (preferred first), or nil when none is.
local function statSeries(sources: { StatSource }): StatSeries?
	for _, source in sources do
		local read = statReader(source.name)
		if read ~= nil then
			local reader: () -> number = read -- a non-optional local for the closure below
			local scale = source.scale
			return {
				name = source.name,
				read = function(): number
					return reader() * scale
				end,
				values = {},
			}
		end
	end
	return nil
end

-- What the sampler reads off Stats every frame. HeartbeatTime and PhysicsStepTime are seconds; the
-- *Ms properties they replaced are deprecated and only read when the new ones are not there.
local STAT_SPECS = {
	{
		key = "heartbeat",
		ms = true,
		sources = { { name = "HeartbeatTime", scale = MS_PER_SECOND }, { name = "HeartbeatTimeMs", scale = 1 } },
	},
	{
		key = "physics",
		ms = true,
		sources = { { name = "PhysicsStepTime", scale = MS_PER_SECOND }, { name = "PhysicsStepTimeMs", scale = 1 } },
	},
	{ key = "instances", ms = false, sources = { { name = "InstanceCount", scale = 1 } } },
	{ key = "primitives", ms = false, sources = { { name = "PrimitivesCount", scale = 1 } } },
}

local msSeries: { StatSeries } = {}
local countSeries: { StatSeries } = {}
local unreadable: { string } = {}
local heartbeatSeries: StatSeries? = nil
for _, spec in STAT_SPECS do
	local series = statSeries(spec.sources)
	if series == nil then
		local names = {}
		for _, source in spec.sources do
			table.insert(names, "Stats." .. source.name)
		end
		table.insert(unreadable, table.concat(names, " / "))
		continue
	end
	table.insert(if spec.ms then msSeries else countSeries, series)
	if spec.key == "heartbeat" then
		heartbeatSeries = series
	end
end
local memoryReadable = pcall(function()
	return Stats:GetTotalMemoryUsageMb()
end)

local workMs: { number } = {}
local periodMs: { number } = {}
local memoryMb: { number } = {}
local frameStart: number? = nil
local nextMemoryAt = 0

local function markFrameStart()
	if frameStart == nil then
		frameStart = os.clock()
	end
end

local function markFrameEnd()
	local started = frameStart
	frameStart = nil
	if sampling and started ~= nil then
		table.insert(workMs, (os.clock() - started) * MS_PER_SECOND)
	end
end

local function onHeartbeat(dt: number)
	if not sampling then
		return
	end
	table.insert(periodMs, dt * MS_PER_SECOND)
	for _, series in msSeries do
		table.insert(series.values, series.read())
	end
	for _, series in countSeries do
		table.insert(series.values, series.read())
	end
	local now = os.clock()
	if memoryReadable and now >= nextMemoryAt then
		nextMemoryAt = now + MEMORY_SAMPLE_SECONDS
		table.insert(memoryMb, Stats:GetTotalMemoryUsageMb())
	end
	task.defer(markFrameEnd) -- runs after every handler of this Heartbeat
end

local partsBefore = countBaseParts(workspace)
-- PreAnimation is the frame's first server-side step; pcall in case this context refuses it (some
-- RunService events are client-only), in which case PreSimulation alone opens the frame.
local preAnimationOk, preAnimation = pcall(function(): any
	return RunService.PreAnimation:Connect(markFrameStart)
end)
if preAnimationOk then
	table.insert(sampleConnections, preAnimation)
else
	report(
		("RunService.PreAnimation not connectable here (%s); frames open at PreSimulation"):format(
			tostring(preAnimation)
		)
	)
end
table.insert(sampleConnections, RunService.PreSimulation:Connect(markFrameStart))
table.insert(sampleConnections, RunService.Heartbeat:Connect(onHeartbeat))

local windUpSeen: { [number]: boolean } = {}
local fewestEnemies = EnemyService.count()
sampling = true
local sampleEndsAt = os.clock() + performance.sampleSeconds
swingFreeStandIns() -- every stand-in on the same frame: their snaps land together
while os.clock() < sampleEndsAt do
	task.wait(PHASE_POLL_SECONDS)
	swingFreeStandIns()
	fewestEnemies = math.min(fewestEnemies, EnemyService.count())
	for _, id in EnemyService.ids() do
		local brain = EnemyService.brainOf(id)
		if brain ~= nil and brain:getPhase() == "WindUp" then
			windUpSeen[id] = true
		end
	end
end
sampling = false
for _, connection in sampleConnections do
	connection:Disconnect()
end
local partsAfter = countBaseParts(workspace)
local partsMax = math.max(partsBefore, partsAfter)
local playgroundParts = countBaseParts(workspace:FindFirstChild(World.playground.modelName))
local enemyParts = countBaseParts(workspace:FindFirstChild(World.playground.folders.enemies))
local standInParts = 0
for _, standIn in standIns do
	standInParts += countBaseParts(standIn.model)
end
local windUps = 0
for _ in windUpSeen do
	windUps += 1
end

-- ------------------------------------------------------------------------------------------
-- The report
-- ------------------------------------------------------------------------------------------

local work = summarize(workMs)
local period = summarize(periodMs)
local statSummaries: { [string]: Summary? } = {}
for _, series in msSeries do
	statSummaries[series.name] = summarize(series.values)
end
for _, series in countSeries do
	statSummaries[series.name] = summarize(series.values)
end
local memory = summarize(memoryMb)

local mixParts: { string } = {}
for defId, count in spawnedByDef do
	table.insert(mixParts, ("%d %s"):format(count, defId))
end
table.sort(mixParts)

report(
	("load: %d stand-ins registered as players, %d enemies (%d from the Playground wave; spawned here: %s), settled %g s, sampled %g s"):format(
		#standIns,
		waveCount + #spawnedIds,
		waveCount,
		if #mixParts > 0 then table.concat(mixParts, ", ") else "none",
		performance.settleSeconds,
		performance.sampleSeconds
	)
)
report(
	("load held: %d hits landed on the stand-ins, %d enemies wound up, fewest enemies alive %d, stand-in deaths %d, anti-cheat kicks %d"):format(
		landedOnStandIns,
		windUps,
		fewestEnemies,
		standInDeaths,
		kicks
	)
)
local refusedParts: { string } = {}
for reason, count in artsRefused do
	table.insert(refusedParts, ("%s x%d"):format(reason, count))
end
table.sort(refusedParts)
report(
	("stand-ins fought back: %d Arts started (%s), %d hits landed on enemies; refused: %s"):format(
		artsStarted,
		table.concat(artSlots, ", "),
		landedByStandIns,
		if #refusedParts > 0 then table.concat(refusedParts, ", ") else "none"
	)
)
report(
	("server work per frame (first PreAnimation / PreSimulation to the end of Heartbeat, os.clock): %s; target %s under %g ms"):format(
		describeMs(work),
		PERCENTILE_LABEL,
		performance.maxServerHeartbeatMs
	)
)
report(("frame period (Heartbeat dt): %s"):format(describeMs(period)))
if period ~= nil and period.mean > 0 then
	report(("server steps per second: %.1f"):format(MS_PER_SECOND / period.mean))
end
for _, series in msSeries do
	report(("Stats.%s: %s"):format(series.name, describeMs(statSummaries[series.name])))
end
for _, series in countSeries do
	report(("Stats.%s: %s"):format(series.name, describeCount(statSummaries[series.name])))
end
for _, names in unreadable do
	report(("%s: not readable from a server script here"):format(names))
end

local heartbeatName = if heartbeatSeries ~= nil then "Stats." .. heartbeatSeries.name else "Stats.HeartbeatTime"
local heartbeatStat = if heartbeatSeries ~= nil then statSummaries[heartbeatSeries.name] else nil
if heartbeatStat ~= nil and period ~= nil and period.mean > 0 then
	local ratio = heartbeatStat.mean / period.mean
	if math.abs(ratio - 1) <= PERIOD_MATCH_TOLERANCE then
		report(
			("note: %s (mean %.2f ms) tracks the frame period (mean %.2f ms) here rather than the work; the assertion uses the timed server work"):format(
				heartbeatName,
				heartbeatStat.mean,
				period.mean
			)
		)
	else
		report(
			("note: %s (mean %.2f ms) next to the timed server work (mean %.2f ms); in a Studio Run session the engine figure covers the Studio process's jobs too"):format(
				heartbeatName,
				heartbeatStat.mean,
				if work ~= nil then work.mean else 0
			)
		)
	end
	if heartbeatStat.percentile >= performance.maxServerHeartbeatMs then
		warn(
			("%s %s %s %.2f ms is not under the %g ms target. Not asserted (Studio process, not a live server): confirm on a live server in Developer Console (F9) > Server Jobs"):format(
				PREFIX,
				heartbeatName,
				PERCENTILE_LABEL,
				heartbeatStat.percentile,
				performance.maxServerHeartbeatMs
			)
		)
	end
end

report(
	("workspace BaseParts: %s before the sample, %s after (Playground model %s, enemies %s, stand-ins %s); budget under %s"):format(
		withCommas(partsBefore),
		withCommas(partsAfter),
		withCommas(playgroundParts),
		withCommas(enemyParts),
		withCommas(standInParts),
		withCommas(Fx.budgets.parts)
	)
)
if memory ~= nil then
	report(
		("memory (Stats:GetTotalMemoryUsageMb every %g s): mean %s, max %s. Not asserted: in Studio this is the whole Studio process (editor, plugins, rendering), so it overstates a live server. Targets: under %s on PC, under %s on mobile, read on the device"):format(
			MEMORY_SAMPLE_SECONDS,
			formatMb(memory.mean),
			formatMb(memory.max),
			formatTargetMb(performance.maxMemoryMbPc),
			formatTargetMb(performance.maxMemoryMbMobile)
		)
	)
else
	report("memory: Stats:GetTotalMemoryUsageMb is not readable from a server script here")
end
report(
	("draw calls (target under %s) and client fps are not readable from a server script: read them from the MicroProfiler (Ctrl+F6) in Play mode"):format(
		withCommas(Fx.budgets.drawCalls)
	)
)

-- Ready-to-paste rows for the Performance table in docs/PROGRESS.md (Measure | Target | Measured | Where / how).
local primitives = statSummaries.PrimitivesCount
local heartbeatCell = if work ~= nil
	then ("%s %.2f ms, mean %.2f ms, max %.2f ms (timed server work per frame over %d frames)"):format(
		PERCENTILE_LABEL,
		work.percentile,
		work.mean,
		work.max,
		work.count
	)
	else "no frames timed"
if heartbeatStat ~= nil then
	heartbeatCell ..= ("; %s %s %.2f ms"):format(heartbeatName, PERCENTILE_LABEL, heartbeatStat.percentile)
end
local partsCell = ("%s BaseParts in workspace"):format(withCommas(partsMax))
if primitives ~= nil then
	partsCell ..= (" (Stats.PrimitivesCount max %s)"):format(withCommas(primitives.max))
end
local memoryCell = if memory ~= nil
	then ("%s (whole Studio process, not a live server)"):format(formatMb(memory.max))
	else "not readable"

local rows = {
	{ "Parts loaded", ("under %s"):format(withCommas(Fx.budgets.parts)), partsCell },
	{
		("Server heartbeat with %d players and %d enemies"):format(performance.testPlayers, performance.testEnemies),
		("under %g ms"):format(performance.maxServerHeartbeatMs),
		heartbeatCell,
	},
	{ "Memory, PC", ("under %s"):format(formatTargetMb(performance.maxMemoryMbPc)), memoryCell },
}
report("paste into docs/PROGRESS.md > Performance (each row replaces the row with the same Measure):")
for _, row in rows do
	print(("| %s | %s | %s | %s |"):format(row[1], row[2], row[3], HOW))
end

-- ------------------------------------------------------------------------------------------
-- Clean up, then assert
-- ------------------------------------------------------------------------------------------

for _, id in spawnedIds do
	EnemyService.despawn(id)
end
for _, standIn in standIns do
	EntityService.unregister(standIn.id)
	AntiCheatService.forget(standIn.player)
	standIn.model:Destroy()
end
for _, connection in standInConnections do
	connection:Disconnect()
end

local leftovers = 0
for _, id in spawnedIds do
	if EnemyService.modelOf(id) ~= nil or EntityService.get(id) ~= nil then
		leftovers += 1
	end
end
check(leftovers == 0, ("the %d enemies this run spawned are despawned and unregistered"):format(#spawnedIds))
local standInsLeft = 0
for _, standIn in standIns do
	if EntityService.get(standIn.id) ~= nil or standIn.model.Parent ~= nil then
		standInsLeft += 1
	end
end
check(standInsLeft == 0, "every stand-in is unregistered and destroyed")

check(work ~= nil, "the sampler timed server frames")
check(standInDeaths == 0, "no stand-in died during the run, so every enemy kept a target")
check(
	fewestEnemies >= performance.testEnemies,
	("at least %d enemies stayed alive through the sample (fewest %d)"):format(performance.testEnemies, fewestEnemies)
)
check(landedOnStandIns > 0, ("enemies landed %d hits on the stand-ins during the sample"):format(landedOnStandIns))
check(windUps > 0, ("%d enemies wound up a telegraphed attack during the sample"):format(windUps))
check(
	artsStarted >= #standIns,
	("the stand-ins started %d Arts during the sample, at least one each"):format(artsStarted)
)
local workSummary = work :: Summary
check(
	workSummary.percentile < performance.maxServerHeartbeatMs,
	("server work %s %.2f ms is under %g ms"):format(
		PERCENTILE_LABEL,
		workSummary.percentile,
		performance.maxServerHeartbeatMs
	)
)
check(
	partsMax < Fx.budgets.parts,
	("%s BaseParts in workspace is under %s"):format(withCommas(partsMax), withCommas(Fx.budgets.parts))
)

print(PREFIX .. " all checks passed")
