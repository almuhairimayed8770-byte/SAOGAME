--!strict
--[[
	TargetController: lock-on (section 6: F / R3). A press locks the best enemy inside the camera
	data's range and cone (nearest, with off-center angle priced in studs); repeated presses cycle
	down the ranked list and past the last one unlock. The lock clears when the target dies, leaves
	or walks beyond the break distance, and it ends with the player's own character: when its
	record goes Dead, when its rig goes (the tracker's local id to nil) and when a respawn replaces
	it (the local id to a different one, which can come before the old rig is gone), so a
	respawned player always starts unlocked. No lock is taken while the local record is Dead. The
	camera frames both fighters and the outline manager marks the target. Ranking lives in
	TargetRanking (tested).

	A death ends the lock (the outline, the server's lock, targetChanged and the body's turn), but
	not the shot (F4): the camera holds the lock's framing through the kill's hit-stop and the death
	freeze (CameraController.holdLock) and lets go as the body shatters, so the freeze reads as a
	still picture, never a pull-back to the free camera. Every other end (the key, a target out of
	range or gone, a respawn) lets the shot go at once.

	The target's death ends the lock when this client shows it (D-323), not when its State turns
	Dead: the State lands with the server's word, which waits for the blade's strike key (D-272),
	so the death freeze can start a few frames later. The shown kill is the kill's HitConfirmed as
	Replication plays it (Replication.hit, killed), which plays the held death just before it. A
	death with no such word (no hit killed it) lets the lock go combat.contact.wordWaitSeconds after
	the State, the longest a held death waits. The local character's own death is never held.

	Every lock change goes to the server as a TargetRequest through TrailingSend: never faster than
	the remote's rate limit, and the last change always arrives, so mashing the key cannot leave the
	server holding a lock (and the sword drawn, D-050) that the client already let go of.

	lockOn(entityId) locks a named enemy through the same path as the key (a dev helper, a tutorial
	beat); the body then turns to face the lock (CharacterController, D-112). assistCandidates lists
	the enemies the soft assist may aim a swing at when nothing is locked (AimLogic.assistPick).

	A dev capture's staged take (D-290, D-328): while stageTarget names the enemy a take stages, the
	key acts on it alone, by the rule the take's own lock presses keep (CaptureLogic.lockPress): it
	locks it when the lock is off or on another enemy and lets it go when the lock is on it, never
	stepping down the ranked list to a field enemy nearer than the staged one. Only a capture place
	(workspace DevCapture) takes a staged target; stageTarget(nil) gives the key its cycle back.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Client = script.Parent.Parent

local CameraData = require(Shared.data.camera)
local Combat = require(Shared.data.combat)
local Dev = require(Shared.data.dev)
local Moments = require(Shared.data.moments)
local Net = require(Shared.net.Net)
local TrailingSend = require(Shared.net.TrailingSend)
local Signal = require(Shared.util.Signal)

local EntityTracker = require(script.Parent.EntityTracker)
local Replication = require(script.Parent.Replication)
local TargetRanking = require(script.Parent.TargetRanking)
local AimLogic = require(script.Parent.AimLogic)
local InputController = require(script.Parent.InputController)
local Siblings = require(script.Parent.Siblings)
local CameraController = require(Client.camera.CameraController)
local DrawnBody = require(Client.choreo.DrawnBody)
local CaptureLogic = require(Client.dev.CaptureLogic)

local OutlineManager = Siblings.load(Client, "fx.OutlineManager")

local TargetController = {}

--- Fires the new target record (or nil) whenever the lock changes.
TargetController.targetChanged = Signal.new() :: Signal.Signal<any>

local target: any = nil
local sender: TrailingSend.TrailingSend? = nil -- TargetRequest, paced to its rate limit
local started = false
-- The local record's id the lock belongs to (EntityTracker's local id when last told).
local ownerId: number? = nil
-- When (os.clock) the locked target's State turned Dead, while this client has yet to show the
-- death (D-323); nil otherwise.
local dyingSince: number? = nil
-- The enemy a dev capture's staged take stages (D-290, D-328), or nil.
local stagedId: number? = nil

local function toTable(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function localPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root.Position else nil
end

-- Where an enemy is drawn: a rush draws its body ahead of its hidden root part (D-193), and the
-- lock's range, break distance and the assist measure what the player sees.
local function positionOf(record: any): Vector3?
	return DrawnBody.position(record.model)
end

local function rankingParams(): TargetRanking.Params
	local lock = CameraData.lock
	return { range = lock.range, coneDegrees = lock.coneDegrees, angleWeightStuds = lock.angleWeightStuds }
end

-- True while the local character's record is Dead: it takes no lock until the respawn.
local function localDead(): boolean
	local record = EntityTracker.localRecord()
	return record ~= nil and record.state == "Dead"
end

-- A record the lock may take: a living enemy with a position.
local function lockablePosition(record: any): Vector3?
	if record == nil or record.kind ~= "Enemy" or record.state == "Dead" then
		return nil
	end
	return positionOf(record)
end

--- Lock candidates right now: living enemies with a position, measured from the player and the camera.
function TargetController.candidates(): { TargetRanking.Candidate }
	local origin = localPosition()
	local camera = workspace.CurrentCamera
	if origin == nil or camera == nil then
		return {}
	end
	local forward = toTable(camera.CFrame.LookVector)
	local from = toTable(origin)
	local list = {}
	for _, record in EntityTracker.all() do
		local position = lockablePosition(record)
		if position == nil then
			continue
		end
		local to = toTable(position)
		table.insert(list, {
			id = record.id,
			distance = (position - origin).Magnitude,
			angle = TargetRanking.angleFrom(forward, from, to),
		})
	end
	return list
end

--- The soft assist's candidates (D-112): living enemies with a position, measured flat from
--- `origin` (studs) with their signed bearing from the flat `look` (degrees, + = left).
function TargetController.assistCandidates(origin: Vector3, look: Vector3): { AimLogic.Bearing }
	local list: { AimLogic.Bearing } = {}
	for _, record in EntityTracker.all() do
		local position = lockablePosition(record)
		if position == nil then
			continue
		end
		local dx, dz = position.X - origin.X, position.Z - origin.Z
		table.insert(list, {
			id = record.id,
			distance = math.sqrt(dx * dx + dz * dz),
			bearing = AimLogic.bearing(look.X, look.Z, dx, dz),
		})
	end
	return list
end

-- Seconds from a death to its shatter (Replication's EntityDied): the kill's hit-stop, then the freeze.
local function untilShatter(): number
	return Moments.deathDuckDelay() + Combat.deathFreeze
end

-- `death`: the lock ends with a death (the target's or the local character's); the camera holds
-- its framing until the shatter instead of letting go now (F4).
local function setTarget(record: any, death: boolean?)
	if record == target then
		return
	end
	dyingSince = nil
	if target ~= nil then
		OutlineManager.setImportance(target.model, "Normal")
	end
	target = record
	if record ~= nil then
		OutlineManager.setImportance(record.model, "Lock")
	end
	if record == nil and death == true then
		CameraController.holdLock(untilShatter())
	else
		CameraController.setLockTarget(if record ~= nil then record.model else nil)
	end
	if sender ~= nil then
		sender:set(if record ~= nil then record.id else nil)
	end
	TargetController.targetChanged:Fire(record)
end

--- The lock key: best candidate, then the next one down, then unlock. Does nothing while the
--- local character is dead. In a staged capture take it acts on the staged enemy alone (D-328).
function TargetController.toggle()
	if localDead() then
		return
	end
	local how = CaptureLogic.lockPress(stagedId, if target ~= nil then target.id else nil)
	if how == "Lock" then
		TargetController.lockOn(stagedId)
		return
	elseif how == "Release" then
		setTarget(nil)
		return
	end
	local ranked = TargetRanking.rank(TargetController.candidates(), rankingParams())
	local ids = {}
	for _, candidate in ranked do
		table.insert(ids, candidate.id)
	end
	local nextId = TargetRanking.next(ids, if target ~= nil then target.id else nil)
	setTarget(if nextId ~= nil then EntityTracker.get(nextId) else nil)
end

--- Clears the lock.
function TargetController.clear()
	setTarget(nil)
end

--- Locks the enemy `entityId` through the lock key's path (camera, outline, TargetRequest through
--- its pacer, targetChanged); nil clears. Returns false, and keeps the lock it had, when the id is
--- not a living enemy with a position within the lock range of the player, or the local character
--- is dead. The camera's cone does not apply: the caller named the enemy.
function TargetController.lockOn(entityId: number?): boolean
	if entityId == nil then
		setTarget(nil)
		return true
	end
	if localDead() then
		return false
	end
	local record = EntityTracker.get(entityId)
	local position = lockablePosition(record)
	local origin = localPosition()
	if position == nil or origin == nil or (position - origin).Magnitude > CameraData.lock.range then
		return false
	end
	setTarget(record)
	return true
end

--- The locked record, or nil.
function TargetController.current(): any
	return target
end

--- A dev capture's staged take (D-290, D-328): while `entityId` names the enemy the take stages,
--- the lock key acts on it alone (CaptureLogic.lockPress); nil, at the take's end, gives the key its
--- cycle back. Outside a capture place (workspace DevCapture) nothing is staged.
function TargetController.stageTarget(entityId: number?)
	if entityId ~= nil and workspace:GetAttribute(Dev.attributes.capture) ~= true then
		return
	end
	stagedId = entityId
end

-- The locked target's State turned Dead: the lock waits for this client to show the death
-- (D-323), at most combat.contact.wordWaitSeconds (the longest a held death waits, D-267).
local function dying(): boolean
	local since = dyingSince
	if since == nil then
		dyingSince = os.clock()
		return true
	end
	if os.clock() - since < Combat.contact.wordWaitSeconds then
		return true
	end
	setTarget(nil, true)
	return false
end

-- The client shows a kill (Replication.hit, after the held death played): the locked target's
-- death ends the lock now and the shot holds from this frame (D-323).
local function onShownHit(payload: any)
	if target ~= nil and typeof(payload) == "table" and payload.killed == true and payload.targetId == target.id then
		setTarget(nil, true)
	end
end

local function check()
	if target == nil then
		return
	end
	local origin = localPosition()
	local position = positionOf(target)
	local distance = if origin ~= nil and position ~= nil then (position - origin).Magnitude else nil
	local live = EntityTracker.get(target.id)
	local state = if live == target then target.state else nil
	if state == "Dead" and dying() then
		return
	end
	if TargetRanking.shouldClear(state, distance, CameraData.lock.breakDistance) then
		setTarget(nil, state == "Dead")
	end
end

--- Wires the lock key, the per-heartbeat validity check and entity removal.
function TargetController.start()
	if started then
		return
	end
	started = true
	local net = Net.client()
	sender = TrailingSend.new({
		gap = TrailingSend.gapOf("TargetRequest"),
		now = os.clock,
		schedule = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		send = function(entityId: number?)
			net.fire("TargetRequest", { entityId = entityId })
		end,
	})
	InputController.lockToggle:Connect(TargetController.toggle)
	EntityTracker.removed:Connect(function(record: any)
		if record == target then
			setTarget(nil)
		end
	end)
	-- The target's death, and the local character's: the lock ends with either, and the shot
	-- holds until the shatter (F4). The target's waits for this client to show it (D-323).
	EntityTracker.changed:Connect(function(record: any, attribute: string, value: any)
		if attribute ~= "State" or value ~= "Dead" then
			return
		end
		if EntityTracker.isLocal(record.id) then
			setTarget(nil, true)
		elseif record == target then
			dying()
		end
	end)
	Replication.hit:Connect(onShownHit)
	-- A respawn gives the player a new server record, and it starts with no lock. The old
	-- character's lock ends with it, whether its rig goes first (old id, nil, new id) or the new
	-- record arrives first (old id straight to the new one). A lock the client holds when the
	-- first record arrives (nil to an id: taken before the server registered the character) or
	-- when the same id comes back is sent again, so the server never misses it.
	ownerId = EntityTracker.peekLocalId()
	EntityTracker.localChanged:Connect(function(id: number?)
		local previous = ownerId
		ownerId = id
		if id == nil or (previous ~= nil and id ~= previous) then
			setTarget(nil)
		elseif target ~= nil and sender ~= nil then
			sender:set(target.id)
		end
	end)
	RunService.Heartbeat:Connect(check)
end

return TargetController
