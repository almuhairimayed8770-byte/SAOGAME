--!strict
--[[
	DevStage: the capture's staging (F12). Runs only in Studio (RunService:IsStudio()) in a place
	whose Workspace carries the DevCapture attribute (places/Playground.project.json); anywhere else
	it returns before it requires a service or makes an instance, so a live game never has it.

	It makes a RemoteFunction (dev.luau capture.stage.remoteName) under ReplicatedStorage, the way
	the time-scale remote is made (ClipLab.server.luau), and the Capture panel asks it to set a
	gate shot up. `InvokeServer(action, shotId?)`, at most capture.stage.requestsPerSecond a player:

		"stage" shotId   sets the shot up around the player, who walks into place itself: this
		                 script never moves the player (D-244; a remote handler never moves a
		                 player, D-143). It replies { ok, shot, targetId, ids, moved }, or
		                 { ok = false, error, walk } while the player stands outside the ring:
		                 1. the enemies the last staging spawned are despawned;
		                 2. every field enemy is held (EnemyService.setHeld), and hold-new is turned on
		                    so respawns start held; one inside its wind-up or strike is waited out first
		                    (up to stage.holdWaitSeconds), never held mid-attack, since a hold cancels the
		                    attack the client already draws (a boar's crouch and line, then no rush);
		                    one still mid-attack at the deadline fails the staging;
		                 3. the open shot builds the ledge and its ramp (once): there is no jump
		                    (D-024), so its fall and land come off an edge and the way up is the ramp;
		                 4. held field enemies within stage.awayStuds of the stand spot are moved out
		                    to it (past the lock's range and every aggro radius), so the walk is safe;
		                 5. the player's root must stand in the stand ring (DevStageLogic.inRing: within
		                    stage.standRadius of the spot, its feet on the spot's floor; the open shot's
		                    on the ledge's top). Outside it the reply is { ok = false, error = "walk
		                    into the ring first", walk = the ring (x, y, z, facing, radius, tolerance,
		                    over) and a route to it (DevStageLogic.route) }, and nothing is spawned;
		                 6. inside it the player is healed to full and the shot's enemies spawn
		                    around where its root stands and faces, at their distance and side, facing
		                    the player, held; `hp` sets one's HP (the kill shot). The first is the
		                    shot's target.
		                 Step 1 runs before any other check: the first stage request the rate lets
		                 through after a take (a dead player's too, one that only asks for a walk)
		                 leaves nothing of that take on the field.
		"go"             lets go the staged enemies whose `held` is false (the take has started);
		                 one with a `releaseAfter` (CF) is let go that many seconds later instead,
		                 unless the take ends ("hold"), the field is given back or another shot is
		                 staged first. One staged with `hp` is set to it again as it is let go
		                 (EntityService.setHp restarts the out-of-combat regen wait), so it comes in
		                 at the HP the shot staged, however long it was held. It replies
		                 { ok, released, scheduled = { { id, after } } }
		"hold"           the take has ended (CS1): every staged enemy still standing is held where it
		                 is (EnemyService.setHeld: Idle at once; a wind-up is dropped, D-254, and a
		                 launched rush stops where it is), and a late "go" lets nobody go, so nothing
		                 of the take acts between takes
		"release"        gives the field back: the staged enemies are despawned, every field enemy
		                 this staging held is let go and hold-new goes back to what it was

	One staging at a time; the server owns every enemy placement, HP and hold (the client only names
	the shot and walks its own body). Replies are plain tables; a failure is { ok = false, error = ... }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dev = require(Shared.data.dev)

if not RunService:IsStudio() or workspace:GetAttribute(Dev.attributes.capture) ~= true then
	return
end

local Server = script.Parent.Parent
local Enemies = require(Shared.data.enemies)
local Rigs = require(Shared.data.rigs)
local World = require(Shared.data.world)
local Palette = require(Shared.data.palette)
local EnemyService = require(Server.services.EnemyService)
local EntityService = require(Server.services.EntityService)
local PlaygroundLayout = require(Server.world.PlaygroundLayout)
local DevStageLogic = require(script.Parent.DevStageLogic)

type Reply = { [string]: any }

local Capture = Dev.capture
local Stage = Capture.stage
local Shots = Capture.shots

-- The enemies the last staging spawned, those of them the take lets go as it starts, and those
-- it lets go partway through (dev.luau StagedEnemy.releaseAfter).
local staged: { number } = {}
local toRelease: { number } = {}
local scheduled: { { id: number, after: number } } = {}
-- The HP each staged enemy was set to (dev.luau StagedEnemy.hp), set again as it is let go.
local stagedHp: { [number]: number } = {}
-- Moves on whenever the take's late releases are called off (the take ends, the field is given
-- back, another shot stages): a delayed release made under an older one lets nobody go.
local releaseToken = 0
-- The field as it was before the first staging: hold-new, and the enemies already held (by the
-- dev hook, a cutscene); nil while the field is not this script's.
local holdNewBefore: boolean? = nil
local heldBefore: { [number]: boolean } = {}
local busy = false
local lastAt: { [Player]: number } = {}
local ledge: BasePart? = nil
local ramp: BasePart? = nil

local function fail(message: string): Reply
	return { ok = false, error = message }
end

local function isStaged(id: number): boolean
	return table.find(staged, id) ~= nil
end

local function clearStaged(): number
	local removed = 0
	for _, id in staged do
		if EnemyService.modelOf(id) ~= nil then
			EnemyService.despawn(id)
			removed += 1
		end
	end
	table.clear(staged)
	table.clear(toRelease)
	table.clear(scheduled)
	table.clear(stagedHp)
	releaseToken += 1
	return removed
end

-- Holds every field enemy outside its wind-up and strike, waiting those out; returns the ids
-- still mid-attack at the deadline (none held mid-attack).
local function holdField(): { number }
	if holdNewBefore == nil then
		holdNewBefore = EnemyService.holdsNew()
		table.clear(heldBefore)
		for _, id in EnemyService.heldIds() do
			heldBefore[id] = true
		end
	end
	EnemyService.setHoldNew(true)
	local deadline = os.clock() + Stage.holdWaitSeconds
	while true do
		local waiting: { number } = {}
		for _, id in EnemyService.ids() do
			if isStaged(id) or EnemyService.isHeld(id) then
				continue
			end
			local brain = EnemyService.brainOf(id)
			local phase = if brain ~= nil then brain:getPhase() else nil
			if DevStageLogic.canHold(phase) then
				EnemyService.setHeld(id, true)
			else
				table.insert(waiting, id)
			end
		end
		if #waiting == 0 or os.clock() >= deadline then
			return waiting
		end
		task.wait()
	end
end

-- Moves held field enemies standing within awayStuds of the spot out to it.
local function moveAway(spotX: number, spotZ: number): number
	local moved = 0
	for _, id in EnemyService.ids() do
		if isStaged(id) or not EnemyService.isHeld(id) then
			continue
		end
		local model = EnemyService.modelOf(id)
		local root = if model ~= nil then model.PrimaryPart else nil
		if model == nil or root == nil then
			continue
		end
		local at = root.Position
		local x, z = DevStageLogic.awaySpot(spotX, spotZ, at.X, at.Z, Stage.awayStuds)
		if x ~= nil and z ~= nil then
			model:PivotTo(model:GetPivot() + Vector3.new(x - at.X, 0, z - at.Z))
			moved += 1
		end
	end
	return moved
end

-- A part from a placement table's size, name, colour token and material, anchored, at `cframe`.
local function block(className: string, data: any, cframe: CFrame): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = data.name
	part.Anchored = true
	part.Size = Vector3.new(data.size[1], data.size[2], data.size[3])
	part.CFrame = cframe
	part.Material = (Enum.Material :: any)[data.material] or Enum.Material.SmoothPlastic
	part.Color = Palette.color3(data.colorToken :: any)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = workspace
	return part
end

local function ledgeBuilt(): boolean
	local existing = ledge
	return existing ~= nil and existing.Parent ~= nil
end

-- The open shot's ledge and the ramp up to its top (no jump, D-024), built once.
local function buildLedge()
	local data = Stage.ledge
	if not ledgeBuilt() then
		ledge = block("Part", data, CFrame.new(data.position[1], data.position[2], data.position[3]))
	end
	local existing = ramp
	if existing == nil or existing.Parent == nil then
		local x, y, z, yaw = DevStageLogic.rampFrame(data)
		ramp = block("WedgePart", data.ramp, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0))
	end
end

-- Spawns the shot's enemies on the field around the player's root at (x, z) facing `facing`,
-- held; returns their ids, the target first.
local function spawnStaged(shot: Dev.Shot, x: number, z: number, facing: number): ({ number }?, string?)
	local groundY = Stage.area.position[2]
	local ids: { number } = {}
	for _, entry in shot.stage.enemies do
		local def = Enemies.byId(entry.enemy)
		local rig = if def ~= nil then Rigs[def.skin] else nil
		if def == nil or rig == nil then
			return nil, ("shot %s names an enemy with no def or rig: %s"):format(shot.id, entry.enemy)
		end
		local rootSpec = if rig.parts ~= nil then (rig.parts :: any)[rig.rootPart] else nil
		local rootHeight = if rootSpec ~= nil then rootSpec.size[2] else 0
		local ex, ez = DevStageLogic.around(x, z, facing, entry.side, entry.distance)
		local face = DevStageLogic.facingFrom(ex, ez, x, z) or facing
		local y = groundY + PlaygroundLayout.rootHeight(rig.hipHeight, rootHeight, World.spawn.groundEpsilon)
		local id = EnemyService.spawn(entry.enemy, CFrame.new(ex, y, ez) * CFrame.Angles(0, math.rad(face), 0))
		EnemyService.setHeld(id, true)
		table.insert(staged, id)
		table.insert(ids, id)
		if not entry.held then
			if entry.releaseAfter ~= nil then
				table.insert(scheduled, { id = id, after = entry.releaseAfter })
			else
				table.insert(toRelease, id)
			end
		end
		if entry.hp ~= nil then
			EntityService.setHp(id, entry.hp)
			stagedHp[id] = entry.hp
		end
	end
	return ids, nil
end

local function stageShot(player: Player, shotId: unknown): Reply
	-- The last take's enemies go before anything else, whatever this request comes to (CS1).
	clearStaged()
	local index = DevStageLogic.shotIndex(Shots, shotId)
	if index == nil then
		return fail(("unknown shot %s"):format(tostring(shotId)))
	end
	local shot = Shots[index]
	local record = EntityService.fromPlayer(player)
	if record == nil or record.state == "Dead" then
		return fail("the player has no living entity (respawning?)")
	end
	local waiting = holdField()
	if #waiting > 0 then
		local names = {}
		for _, id in waiting do
			table.insert(names, tostring(id))
		end
		return fail(
			("enemies %s were still mid-attack after %g s; stage again"):format(
				table.concat(names, ", "),
				Stage.holdWaitSeconds
			)
		)
	end
	local open = shot.stage.open
	if open then
		buildLedge()
	end
	local ring = DevStageLogic.ring(open, Stage)
	local moved = moveAway(ring.x, ring.z)
	-- Where the player stands and faces; never moved here (D-244).
	local model: Model = record.model
	local root = model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil or model.Parent == nil then
		return fail("the player has no character in the world (respawning?)")
	end
	local at = root.Position
	local feet = at.Y - PlaygroundLayout.rootHeight(humanoid.HipHeight, root.Size.Y, World.spawn.groundEpsilon)
	if not DevStageLogic.inRing(ring, at.X, feet, at.Z) then
		local walk: { [string]: any } = table.clone(ring) :: any
		walk.path = DevStageLogic.route(open, Stage, ledgeBuilt(), at.X, at.Z)
		return { ok = false, error = "walk into the ring first", walk = walk, moved = moved }
	end
	EntityService.heal(record.id, record.maxHp - record.hp)
	local look = root.CFrame.LookVector
	local facing = DevStageLogic.facingFrom(0, 0, look.X, look.Z) or ring.facing
	local ids, spawnError = spawnStaged(shot, at.X, at.Z, facing)
	if ids == nil then
		return fail(spawnError or "spawn failed")
	end
	return { ok = true, shot = shot.id, targetId = ids[1], ids = ids, moved = moved }
end

-- Lets a staged enemy go at the HP its shot staged (setHp restarts the regen wait): true when it
-- was let go.
local function letGo(id: number): boolean
	if not EnemyService.setHeld(id, false) then
		return false
	end
	local hp = stagedHp[id]
	if hp ~= nil then
		EntityService.setHp(id, hp)
	end
	return true
end

local function go(): Reply
	local released: { number } = {}
	for _, id in toRelease do
		if letGo(id) then
			table.insert(released, id)
		end
	end
	table.clear(toRelease)
	-- The late ones, each once, unless the take is called off first.
	local token = releaseToken
	local later: { { id: number, after: number } } = {}
	for _, entry in scheduled do
		local id = entry.id
		task.delay(entry.after, function()
			if releaseToken == token and isStaged(id) then
				letGo(id)
			end
		end)
		table.insert(later, { id = id, after = entry.after })
	end
	table.clear(scheduled)
	return { ok = true, released = released, scheduled = later }
end

-- The take is over: its enemies stop where they stand (CS1).
local function holdTake(): Reply
	local held: { number } = {}
	for _, id in staged do
		if EnemyService.setHeld(id, true) then
			table.insert(held, id)
		end
	end
	table.clear(toRelease)
	table.clear(scheduled)
	releaseToken += 1
	return { ok = true, held = held }
end

local function release(): Reply
	local removed = clearStaged()
	local released: { number } = {}
	if holdNewBefore ~= nil then
		EnemyService.setHoldNew(holdNewBefore :: boolean)
		for _, id in EnemyService.ids() do
			if EnemyService.isHeld(id) and not heldBefore[id] and EnemyService.setHeld(id, false) then
				table.insert(released, id)
			end
		end
		holdNewBefore = nil
		table.clear(heldBefore)
	end
	return { ok = true, removed = removed, released = released }
end

local HANDLERS: { [string]: (player: Player, shotId: unknown) -> Reply } = {
	stage = stageShot,
	go = function(): Reply
		return go()
	end,
	hold = function(): Reply
		return holdTake()
	end,
	release = function(): Reply
		return release()
	end,
}

local remote = Instance.new("RemoteFunction")
remote.Name = Stage.remoteName
remote.OnServerInvoke = function(player: Player, action: unknown, shotId: unknown): Reply
	local now = os.clock()
	if not DevStageLogic.allowed(lastAt[player], now, Stage.requestsPerSecond) then
		return fail("too many requests")
	end
	lastAt[player] = now
	local handler = if typeof(action) == "string" then HANDLERS[action] else nil
	if handler == nil then
		return fail(("unknown action %s"):format(tostring(action)))
	end
	if busy then
		return fail("busy: a staging is still running")
	end
	busy = true
	local ok, reply = pcall(handler, player, shotId)
	busy = false
	if not ok then
		return fail(tostring(reply))
	end
	return reply
end
remote.Parent = ReplicatedStorage

Players.PlayerRemoving:Connect(function(player: Player)
	lastAt[player] = nil
end)
