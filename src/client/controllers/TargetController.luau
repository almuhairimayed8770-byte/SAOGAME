--!strict
--[[
	TargetController: lock-on (section 6: F / R3). A press locks the best enemy inside the camera
	data's range and cone (nearest, with off-center angle priced in studs); repeated presses cycle
	down the ranked list and past the last one unlock. The lock clears when the target dies, leaves
	or walks beyond the break distance, and when the player's own character goes. The camera
	frames both fighters and the outline manager marks the target. Ranking lives in TargetRanking
	(tested).

	Every lock change goes to the server as a TargetRequest through TrailingSend: never faster than
	the remote's rate limit, and the last change always arrives, so mashing the key cannot leave the
	server holding a lock (and the sword drawn, D-050) that the client already let go of.

	lockOn(entityId) locks a named enemy through the same path as the key (a dev helper, a tutorial
	beat); the body then turns to face the lock (CharacterController, D-112). assistCandidates lists
	the enemies the soft assist may aim a swing at when nothing is locked (AimLogic.assistPick).
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Client = script.Parent.Parent

local CameraData = require(Shared.data.camera)
local Net = require(Shared.net.Net)
local TrailingSend = require(Shared.net.TrailingSend)
local Signal = require(Shared.util.Signal)

local EntityTracker = require(script.Parent.EntityTracker)
local TargetRanking = require(script.Parent.TargetRanking)
local AimLogic = require(script.Parent.AimLogic)
local InputController = require(script.Parent.InputController)
local Siblings = require(script.Parent.Siblings)
local CameraController = require(Client.camera.CameraController)

local OutlineManager = Siblings.load(Client, "fx.OutlineManager")

local TargetController = {}

--- Fires the new target record (or nil) whenever the lock changes.
TargetController.targetChanged = Signal.new() :: Signal.Signal<any>

local target: any = nil
local sender: TrailingSend.TrailingSend? = nil -- TargetRequest, paced to its rate limit
local started = false

local function toTable(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function localPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root.Position else nil
end

local function positionOf(record: any): Vector3?
	local primary = (record.model :: Model).PrimaryPart
	return if primary ~= nil then primary.Position else nil
end

local function rankingParams(): TargetRanking.Params
	local lock = CameraData.lock
	return { range = lock.range, coneDegrees = lock.coneDegrees, angleWeightStuds = lock.angleWeightStuds }
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

local function setTarget(record: any)
	if record == target then
		return
	end
	if target ~= nil then
		OutlineManager.setImportance(target.model, "Normal")
	end
	target = record
	if record ~= nil then
		OutlineManager.setImportance(record.model, "Lock")
	end
	CameraController.setLockTarget(if record ~= nil then record.model else nil)
	if sender ~= nil then
		sender:set(if record ~= nil then record.id else nil)
	end
	TargetController.targetChanged:Fire(record)
end

--- The lock key: best candidate, then the next one down, then unlock.
function TargetController.toggle()
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
--- not a living enemy with a position within the lock range of the player. The camera's cone does
--- not apply: the caller named the enemy.
function TargetController.lockOn(entityId: number?): boolean
	if entityId == nil then
		setTarget(nil)
		return true
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

local function check()
	if target == nil then
		return
	end
	local origin = localPosition()
	local position = positionOf(target)
	local distance = if origin ~= nil and position ~= nil then (position - origin).Magnitude else nil
	local live = EntityTracker.get(target.id)
	local state = if live == target then target.state else nil
	if TargetRanking.shouldClear(state, distance, CameraData.lock.breakDistance) then
		setTarget(nil)
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
	EntityTracker.changed:Connect(function(record: any, attribute: string, value: any)
		if record == target and attribute == "State" and value == "Dead" then
			setTarget(nil)
		end
	end)
	-- A respawn gives the player a new server record, and it starts with no lock. The old
	-- character's lock ends with it; a lock the client holds when the new record arrives (taken
	-- before the server registered it) is sent again, so the server never misses it.
	EntityTracker.localChanged:Connect(function(id: number?)
		if id == nil then
			setTarget(nil)
		elseif target ~= nil and sender ~= nil then
			sender:set(target.id)
		end
	end)
	RunService.Heartbeat:Connect(check)
end

return TargetController
