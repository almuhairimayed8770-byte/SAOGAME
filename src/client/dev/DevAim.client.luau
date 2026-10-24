--!strict
--[[
	DevAim: the Studio aim hook (D-114). Runs only in Studio (RunService:IsStudio()) in a place whose
	Workspace carries the DevCapture attribute (places/Playground.project.json); anywhere else it
	returns before it requires a controller or makes an instance.

	A Studio MCP execute_luau in the Client context gets a fresh copy of any module it requires, not
	the game's live one, so it cannot reach the running controllers. This LocalScript can: it puts a
	BindableFunction (data/dev.luau aim.bindableName) under the LocalPlayer, and
	`:Invoke(command, args)` runs the command here, inside the game's module cache:

		"help"                         the command list
		"status"                       client and server state, the lock and the body's yaw off it,
		                               every enemy (id, name, HP, State, distance, yaw off the body)
		"lock"  { id?, clear? }        TargetController.lockOn(id), or with no id and no lock the F
		                               key's own path; then waits until the body faces the lock within
		                               aim.faceToleranceDegrees or aim.faceTimeoutSeconds passes
		"face"  { id? }                turns the body itself, on Heartbeat, to the enemy (else the lock,
		                               else the nearest), then waits aim.replicationSettleSeconds. The
		                               stand-in for the lock turn, which runs on RenderStepped and so
		                               not at all while the Studio display sleeps; reported as a dev turn
		"swing" { kind?, slot?, count?, id? }
		                               fires InputController.basicAttack, or artPressed(slot) then
		                               artReleased(slot, held) after aim.artHoldSeconds, `count` times:
		                               basics aim.swingGapSeconds apart (the chain carries on), each
		                               Art once the last one's run is over. Per swing: the target, the
		                               body's yaw off it before the send and the yaw off it of the
		                               facing the request carried (yawAtSend: the body whips round to
		                               it over combat.luau aim.snapTurnSeconds after the send), its HP
		                               before and after, the hits this client dealt, any rejection,
		                               the server states seen
		"guard" { held }               fires InputController.guardChanged(held)
		"dodge"                        fires InputController.dodge

	Every request goes out through CharacterController exactly as a key press sends it (its aim
	snap, its rate drop, its prediction), so every server check runs unchanged; nothing here fires
	a remote or decides a hit. Every wait is task.wait, which Heartbeat resumes: with the display
	asleep RenderStepped runs 0 times a second while Heartbeat runs 60. Replies are plain tables
	(numbers rounded to aim.decimals places) that execute_luau can JSON-encode; a failure is
	{ ok = false, error = ... }. One yielding command runs at a time.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dev = require(Shared.data.dev)

if not RunService:IsStudio() or workspace:GetAttribute(Dev.attributes.capture) ~= true then
	return
end

local Client = script.Parent.Parent
local InputData = require(Shared.data.input)
local InputController = require(Client.controllers.InputController)
local TargetController = require(Client.controllers.TargetController)
local CharacterController = require(Client.controllers.CharacterController)
local EntityTracker = require(Client.controllers.EntityTracker)
local Replication = require(Client.controllers.Replication)
local DevAimLogic = require(script.Parent.DevAimLogic)

type Reply = { [string]: any }
type Record = EntityTracker.Record
type Collector = {
	hits: { any },
	rejections: { { action: string, reason: string } },
	states: { string },
	stop: () -> (),
}

local Aim = Dev.aim
local player = Players.LocalPlayer

local NO_TURN_HINT = "the body did not reach the lock in aim.faceTimeoutSeconds. The lock turn runs on "
	.. "RenderStepped, which does not run while the Studio display sleeps; 'face' turns the body on Heartbeat."

local busy = false

local function now(): number
	return os.clock()
end

local function round(value: number?): number?
	return DevAimLogic.round(value, Aim.decimals)
end

local function fail(message: string): Reply
	return { ok = false, error = message }
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function positionOf(record: Record?): Vector3?
	if record == nil then
		return nil
	end
	local primary = record.model.PrimaryPart
	return if primary ~= nil then primary.Position else nil
end

-- Degrees (+ = left) from the body's flat look to the record, and the flat distance to it.
local function bearingTo(root: BasePart, record: Record?): (number?, number?)
	local position = positionOf(record)
	if position == nil then
		return nil, nil
	end
	local look = root.CFrame.LookVector
	local origin = root.Position
	local dx, dz = position.X - origin.X, position.Z - origin.Z
	return DevAimLogic.yawOff(look.X, look.Z, dx, dz), math.sqrt(dx * dx + dz * dz)
end

local function yawTo(root: BasePart, record: Record?): number?
	local yaw = bearingTo(root, record)
	return yaw
end

-- Degrees (+ = left) from a facing ({x, y, z}, as a request carries it) at the body to the record.
local function facingYawTo(root: BasePart, facing: { number }, record: Record?): number?
	local position = positionOf(record)
	if position == nil then
		return nil
	end
	local origin = root.Position
	return DevAimLogic.yawOff(facing[1], facing[3], position.X - origin.X, position.Z - origin.Z)
end

local function enemies(): { Record }
	local list = {}
	for _, record in EntityTracker.all() do
		if record.kind == "Enemy" then
			table.insert(list, record)
		end
	end
	return list
end

local function candidates(root: BasePart): { DevAimLogic.Candidate }
	local list = {}
	for _, record in enemies() do
		local _, distance = bearingTo(root, record)
		if distance ~= nil and record.state ~= "Dead" then
			table.insert(list, { id = record.id, distance = distance })
		end
	end
	return list
end

local function lockId(): number?
	local record = TargetController.current()
	return if record ~= nil then record.id else nil
end

local function serverState(): string?
	local record = EntityTracker.localRecord()
	return if record ~= nil then record.state else nil
end

-- Waits a Heartbeat at a time until `condition` holds or `seconds` pass; true when it held.
local function waitUntil(condition: () -> boolean, seconds: number): boolean
	local deadline = now() + seconds
	while not condition() do
		if now() >= deadline then
			return false
		end
		task.wait()
	end
	return true
end

-- Listens for what the server says about this client's actions until stopped.
local function collect(): Collector
	local localId = EntityTracker.peekLocalId()
	local hits: { any } = {}
	local rejections: { { action: string, reason: string } } = {}
	local states: { string } = {}
	local connections = {
		Replication.hit:Connect(function(payload: any)
			if localId ~= nil and payload.attackerId == localId then
				table.insert(hits, payload)
			end
		end),
		Replication.rejected:Connect(function(action: string, reason: string)
			table.insert(rejections, { action = action, reason = reason })
		end),
		EntityTracker.changed:Connect(function(record: Record, attribute: string, value: any)
			if record.id == localId and attribute == "State" and typeof(value) == "string" then
				table.insert(states, value)
			end
		end),
	}
	return {
		hits = hits,
		rejections = rejections,
		states = states,
		stop = function()
			for _, connection in connections do
				connection:Disconnect()
			end
		end,
	}
end

local function rejectionText(collector: Collector): string?
	local first = collector.rejections[1]
	return if first ~= nil then ("%s: %s"):format(first.action, first.reason) else nil
end

local function optionalId(args: { [string]: any }): (number?, string?)
	local id = args.id
	if id ~= nil and typeof(id) ~= "number" then
		return nil, "id must be an entity id (a number)"
	end
	return id, nil
end

-- ------------------------------------------------------------------ commands

local function help(): Reply
	return { ok = true, commands = DevAimLogic.COMMANDS, bindable = Aim.bindableName }
end

local function status(): Reply
	local root = rootPart()
	if root == nil then
		return fail("no character root")
	end
	local lock = TargetController.current()
	local lockYaw, lockDistance = bearingTo(root, lock)
	local list = {}
	for _, record in enemies() do
		local yaw, distance = bearingTo(root, record)
		table.insert(list, {
			id = record.id,
			name = record.name,
			hp = record.hp,
			maxHp = record.maxHp,
			state = record.state,
			distance = round(distance),
			yawOff = round(yaw),
		})
	end
	table.sort(list, function(a, b)
		local da, db = a.distance or math.huge, b.distance or math.huge
		if da ~= db then
			return da < db
		end
		return a.id < b.id
	end)
	local me = EntityTracker.localRecord()
	return {
		ok = true,
		entityId = EntityTracker.peekLocalId(),
		state = CharacterController.state(),
		serverState = serverState(),
		hp = if me ~= nil then me.hp else nil,
		maxHp = if me ~= nil then me.maxHp else nil,
		lockId = if lock ~= nil then lock.id else nil,
		lockName = if lock ~= nil then lock.name else nil,
		bodyYawOff = round(lockYaw),
		lockDistance = round(lockDistance),
		enemies = list,
	}
end

local function lock(args: { [string]: any }): Reply
	local root = rootPart()
	if root == nil then
		return fail("no character root")
	end
	if args.clear == true then
		TargetController.lockOn(nil)
		return { ok = true, lockId = nil }
	end
	local id, err = optionalId(args)
	if err ~= nil then
		return fail(err)
	end
	if id ~= nil then
		if not TargetController.lockOn(id) then
			return fail(("entity %d is not a live, lockable enemy within the lock range"):format(id))
		end
	elseif TargetController.current() == nil then
		InputController.lockToggle:Fire() -- the F key's own path
	end
	local record = TargetController.current()
	if record == nil then
		return fail("nothing locked: no enemy in the lock range and the camera's cone")
	end
	local yawBefore = yawTo(root, record)
	local started = now()
	local faced = waitUntil(function(): boolean
		local current = rootPart()
		return current ~= nil and DevAimLogic.faced(yawTo(current, record), Aim.faceToleranceDegrees)
	end, Aim.faceTimeoutSeconds)
	local current = rootPart() or root
	local reply: Reply = {
		ok = true,
		lockId = record.id,
		lockName = record.name,
		faced = faced,
		yawBefore = round(yawBefore),
		yawOff = round(yawTo(current, record)),
		waited = round(now() - started),
	}
	if not faced then
		reply.hint = NO_TURN_HINT
	end
	return reply
end

local function face(args: { [string]: any }): Reply
	local root = rootPart()
	if root == nil then
		return fail("no character root")
	end
	local id, err = optionalId(args)
	if err ~= nil then
		return fail(err)
	end
	local targetId = DevAimLogic.pickTarget(id, lockId(), candidates(root))
	local record = if targetId ~= nil then EntityTracker.get(targetId) else nil
	if record == nil or positionOf(record) == nil then
		return fail("no enemy to face")
	end
	local yawBefore = yawTo(root, record)
	local started = now()
	local deadline = started + Aim.faceTimeoutSeconds
	local faced = false
	while now() < deadline do
		local dt = task.wait()
		local current = rootPart()
		local yaw = if current ~= nil then yawTo(current, record) else nil
		if current == nil or yaw == nil then
			break
		end
		local step = DevAimLogic.turnStep(yaw, Aim.faceDegreesPerSecond, dt)
		local frame = current.CFrame
		current.CFrame = CFrame.new(frame.Position) * CFrame.Angles(0, math.rad(step), 0) * frame.Rotation
		if step == yaw then
			faced = true
			break
		end
	end
	-- The server's facing check reads the replicated root; the client's yaw history must age out.
	task.wait(Aim.replicationSettleSeconds)
	local current = rootPart() or root
	return {
		ok = true,
		targetId = record.id,
		targetName = record.name,
		turnedBy = "dev",
		faced = faced,
		yawBefore = round(yawBefore),
		yawOff = round(yawTo(current, record)),
		seconds = round(now() - started),
	}
end

-- One swing of a plan. Returns its report and when it was sent.
local function swingOnce(plan: DevAimLogic.SwingPlan, index: number, id: number?, lastSend: number): (Reply, number?)
	local wasFree = waitUntil(function(): boolean
		return DevAimLogic.isFree(serverState())
	end, Aim.runTimeoutSeconds)
	local earliest = lastSend + Aim.swingGapSeconds
	waitUntil(function(): boolean
		return now() >= earliest
	end, Aim.swingGapSeconds)
	local root = rootPart()
	if root == nil then
		return fail("no character root"), nil
	end
	local targetId = DevAimLogic.pickTarget(id, lockId(), candidates(root))
	local target = if targetId ~= nil then EntityTracker.get(targetId) else nil
	local yawBefore, distance = bearingTo(root, target)
	local hpBefore = if target ~= nil then target.hp else nil
	local stateBefore = CharacterController.state()
	local facingBefore = CharacterController.lastFacing()
	local collector = collect()
	local sentAt: number
	if plan.kind == "basic" then
		InputController.basicAttack:Fire()
		sentAt = now()
	else
		InputController.artPressed:Fire(plan.slot)
		local pressedAt = now()
		task.wait(Aim.artHoldSeconds)
		InputController.artReleased:Fire(plan.slot, now() - pressedAt)
		sentAt = now()
	end
	-- The request has gone (the controller sends inside the signal) with a new facing table: the
	-- facing it carried, which the body only shows once its whip is over (item 102). With no new
	-- request, the body's own look.
	local atSend = rootPart() or root
	local sent = CharacterController.lastFacing()
	local yawAtSend = if sent ~= nil and sent ~= facingBefore
		then facingYawTo(atSend, sent, target)
		else yawTo(atSend, target)
	local clientState = CharacterController.state()
	if plan.kind == "basic" then
		waitUntil(function(): boolean
			return now() >= sentAt + Aim.swingGapSeconds
		end, Aim.swingGapSeconds)
	else
		waitUntil(function(): boolean
			return #collector.rejections > 0 or DevAimLogic.artRunOver(collector.states)
		end, Aim.runTimeoutSeconds)
	end
	collector.stop()
	local count, damage = DevAimLogic.tally(collector.hits)
	local struck = {}
	for _, hit in collector.hits do
		table.insert(struck, { targetId = hit.targetId, damage = round(hit.damage), killed = hit.killed })
	end
	return {
		ok = true,
		index = index,
		kind = plan.kind,
		slot = if plan.kind == "art" then plan.slot else nil,
		targetId = targetId,
		targetName = if target ~= nil then target.name else nil,
		distance = round(distance),
		yawBefore = round(yawBefore),
		yawAtSend = round(yawAtSend),
		hpBefore = hpBefore,
		hpAfter = if target ~= nil then target.hp else nil,
		hits = count,
		damage = round(damage),
		struck = struck,
		rejected = rejectionText(collector),
		wasFree = wasFree,
		clientStateBefore = stateBefore,
		clientState = clientState,
		serverStates = collector.states,
	},
		sentAt
end

local function swing(args: { [string]: any }): Reply
	local plan, planError = DevAimLogic.swingPlan(args, {
		maxSwings = Aim.maxSwings,
		defaultSlot = InputData.art.defaultSlot,
		slots = InputData.art.slots,
	})
	if plan == nil then
		return fail(planError or "bad swing args")
	end
	local id, idError = optionalId(args)
	if idError ~= nil then
		return fail(idError)
	end
	local swings = {}
	local landed = 0
	local lastSend = -math.huge
	for index = 1, plan.count do
		local result, sentAt = swingOnce(plan, index, id, lastSend)
		table.insert(swings, result)
		if sentAt == nil then
			break
		end
		landed += result.hits
		lastSend = sentAt
	end
	return { ok = true, kind = plan.kind, count = plan.count, landed = landed, lockId = lockId(), swings = swings }
end

local function settle(fire: () -> ()): Reply
	local collector = collect()
	fire()
	task.wait(Aim.actionSettleSeconds)
	collector.stop()
	return {
		ok = true,
		state = CharacterController.state(),
		serverState = serverState(),
		rejected = rejectionText(collector),
		serverStates = collector.states,
	}
end

local function guard(args: { [string]: any }): Reply
	local held = args.held ~= false
	local reply = settle(function()
		InputController.guardChanged:Fire(held)
	end)
	reply.held = held
	return reply
end

local function dodge(): Reply
	return settle(function()
		InputController.dodge:Fire()
	end)
end

-- ------------------------------------------------------------------ the BindableFunction

local HANDLERS: { [string]: (args: { [string]: any }) -> Reply } = {
	help = help,
	status = status,
	lock = lock,
	face = face,
	swing = swing,
	guard = guard,
	dodge = dodge,
}
local YIELDS: { [string]: boolean } = { lock = true, face = true, swing = true, guard = true, dodge = true }

local function invoke(command: unknown, rawArgs: unknown): Reply
	local handler = if typeof(command) == "string" then HANDLERS[command] else nil
	if handler == nil then
		return {
			ok = false,
			error = ("unknown command %s"):format(tostring(command)),
			commands = DevAimLogic.COMMANDS,
		}
	end
	local yields = YIELDS[command :: string] == true
	if yields and busy then
		return fail("busy: another command is still running")
	end
	busy = busy or yields
	local ok, reply = pcall(handler, DevAimLogic.args(rawArgs))
	if yields then
		busy = false
	end
	if not ok then
		return fail(tostring(reply))
	end
	return reply
end

local bindable = Instance.new("BindableFunction")
bindable.Name = Aim.bindableName
bindable.OnInvoke = invoke
bindable.Parent = player
