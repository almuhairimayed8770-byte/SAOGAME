--!strict
-- CombatService under Lune: fake clock, fake Net (records every fire), a fake engine for the hit
-- sweep that follows the real one's rules (a spherecast against spheres around fighter roots that
-- never reports what it starts inside, a bounds query over every fighter part), rigs built with
-- Instance.new. Timelines are stepped by hand through tick().
Harness.stubService("CollectionService", {
	AddTag = function(_self, instance, tag)
		instance:AddTag(tag)
	end,
	RemoveTag = function(_self, instance, tag)
		instance:RemoveTag(tag)
	end,
	HasTag = function(_self, instance, tag)
		return instance:HasTag(tag)
	end,
})
Harness.stubService("RunService", {
	IsServer = function()
		return true
	end,
	IsClient = function()
		return false
	end,
})

local EntityService = Harness.load("src/server/services/EntityService")
local CombatService = Harness.load("src/server/services/CombatService")
local Combat = Harness.load("src/shared/data/combat")
local Enemies = Harness.load("src/shared/data/enemies")
local Arts = Harness.load("src/shared/data/arts")
local Rigs = Harness.load("src/shared/data/rigs")
local Playground = Harness.load("src/shared/data/playground")
local Net = Harness.load("src/shared/net/Net")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local HitSweep = Harness.load("src/server/combat/HitSweep")
local Horizontal = Harness.load("src/shared/clips/player/OneHandedSword/Horizontal")
local CollectionService = Harness.game():GetService("CollectionService")

local BOAR = Enemies.byId("FrenzyBoar")
local KOBOLD = Enemies.byId("KoboldAxeman")
local CHARGE = BOAR.attacks[1] -- Unblockable: the red line on the ground (section 9)
local OVERHEAD = KOBOLD.attacks[1] -- GuardBreak: the Phase 0 parry beat
-- The boar's line rush with a white (Normal) telegraph, for the cases that exercise a held guard.
local NORMAL_RUSH = table.clone(CHARGE)
NORMAL_RUSH.telegraph = "Normal"
local HORIZONTAL = Arts.byId("OneHandedSword.Horizontal")
local FORWARD = { 0, 0, -1 }

-- ------------------------------------------------------------------------------------------
-- Fixtures
-- ------------------------------------------------------------------------------------------

local clock = { t = 500 }
local sent = {} -- every fire / fireAll: { remote, payload, player? }
local handlers = {}

local fakeNet = {
	on = function(name, handler)
		handlers[name] = handler
	end,
	fire = function(remote, player, payload)
		local ok, message = Net.validate(remote, payload)
		if not ok then
			error(("invalid %s payload: %s"):format(remote, tostring(message)))
		end
		table.insert(sent, { remote = remote, payload = payload, player = player })
	end,
	fireAll = function(remote, payload)
		local ok, message = Net.validate(remote, payload)
		if not ok then
			error(("invalid %s payload: %s"):format(remote, tostring(message)))
		end
		table.insert(sent, { remote = remote, payload = payload })
	end,
}

local noCrit = {
	NextNumber = function()
		return 0.999
	end,
}

local function sentOf(remote)
	local list = {}
	for _, entry in sent do
		if entry.remote == remote then
			table.insert(list, entry.payload)
		end
	end
	return list
end

local function lastOf(remote)
	local list = sentOf(remote)
	return list[#list]
end

-- Distance from a point to a segment and the parameter of the closest approach.
local function segmentDistance(point, origin, direction)
	local lengthSquared = direction:Dot(direction)
	if lengthSquared < 1e-12 then
		return (point - origin).Magnitude, 0
	end
	local t = math.clamp((point - origin):Dot(direction) / lengthSquared, 0, 1)
	return (point - (origin + direction * t)).Magnitude, t
end

-- Spherecast stand-in: every registered fighter is a sphere of its body radius around its root.
-- Like workspace:Spherecast it never reports a fighter the sphere already overlaps at the origin.
local function fakeCast(origin, radius, direction, exclude)
	local best, bestAlong = nil, math.huge
	for _, record in EntityService.all() do
		if table.find(exclude, record.model) == nil then
			local root = record.model.PrimaryPart
			local position = root.CFrame.Position
			local size = math.max(root.Size.X, root.Size.Z) / 2
			local distance, along = segmentDistance(position, origin, direction)
			local startsInside = (position - origin).Magnitude <= radius + size
			if not startsInside and distance <= radius + size and along < bestAlong then
				best = { Instance = root, Position = position }
				bestAlong = along
			end
		end
	end
	return best
end

-- Half size of a part's axis-aligned bounds.
local function boundsHalf(part)
	local cframe = part.CFrame
	local half = part.Size / 2
	local right, up, back = cframe.RightVector, cframe.UpVector, cframe.LookVector
	return Vector3.new(
		math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(back.X) * half.Z,
		math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(back.Y) * half.Z,
		math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(back.Z) * half.Z
	)
end

local overlapQueries = 0

-- workspace:GetPartBoundsInRadius stand-in over every fighter's parts: each queryable part (CanQuery
-- or CanCollide on) whose axis-aligned bounds come within the radius, none under an excluded
-- Instance. HitSweep measures the real boxes of what it returns.
local function fakeOverlap(center, radius, exclude)
	overlapQueries += 1
	local found = {}
	for _, record in EntityService.all() do
		if table.find(exclude, record.model) == nil then
			for _, part in record.model:GetDescendants() do
				if part:IsA("BasePart") and (part.CanQuery or part.CanCollide) then
					local half = boundsHalf(part)
					local offset = center - part.CFrame.Position
					local outside = Vector3.new(
						math.max(math.abs(offset.X) - half.X, 0),
						math.max(math.abs(offset.Y) - half.Y, 0),
						math.max(math.abs(offset.Z) - half.Z, 0)
					)
					if outside.Magnitude <= radius then
						table.insert(found, part)
					end
				end
			end
		end
	end
	return found
end

local function fresh()
	CombatService.reset()
	EntityService.reset()
	clock.t = 500
	sent = {}
	handlers = {}
	overlapQueries = 0
	local now = function()
		return clock.t
	end
	EntityService.bind({
		now = now,
		fireAll = nil,
		heartbeat = nil,
		addTag = function(instance, tag)
			CollectionService:AddTag(instance, tag)
		end,
		removeTag = function(instance, tag)
			CollectionService:RemoveTag(instance, tag)
		end,
		respawn = function() end,
		playerRemoving = nil,
	})
	CombatService.bind({
		now = now,
		net = fakeNet,
		heartbeat = nil,
		cast = fakeCast,
		overlap = fakeOverlap,
		random = noCrit,
	})
	CombatService.start()
end

local function cframeOf(t)
	return CFrame.new(t.pos[1], t.pos[2], t.pos[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(t.rot[1]), math.rad(t.rot[2]), math.rad(t.rot[3]))
end

-- A PlayerR15 stand-in: every Motor6D from rigs.luau, a Weapon part with TrailStart / TrailEnd,
-- a Humanoid, the root at `rootCFrame`.
local function buildPlayerRig(name, rootCFrame)
	local rig = Rigs.PlayerR15
	local model = Instance.new("Model")
	model.Name = name
	local parts = {}
	local function part(partName)
		local existing = parts[partName]
		if existing then
			return existing
		end
		local p = Instance.new("Part")
		p.Name = partName
		p.Size = Vector3.new(1, 1, 1)
		p.Parent = model
		parts[partName] = p
		return p
	end
	local root = part(rig.rootPart)
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = rootCFrame
	model.PrimaryPart = root
	for _, joint in rig.joints do
		local motor = Instance.new("Motor6D")
		motor.Name = joint.name
		motor.Part0 = part(joint.part0)
		motor.Part1 = part(joint.part1)
		motor.C0 = cframeOf(joint.c0)
		motor.C1 = CFrame.new()
		motor.Parent = motor.Part0
	end
	local trailStart = Instance.new("Attachment")
	trailStart.Name = "TrailStart"
	trailStart.CFrame = CFrame.new(0, 0.5, 0)
	trailStart.Parent = parts.Weapon
	local trailEnd = Instance.new("Attachment")
	trailEnd.Name = "TrailEnd"
	trailEnd.CFrame = CFrame.new(0, 4.5, 0)
	trailEnd.Parent = parts.Weapon
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	return model
end

local function enemyModel(name, cframe, size)
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = size
	root.CFrame = cframe
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	return model
end

local playerCount = 0
local function spawnPlayer(rootCFrame)
	playerCount += 1
	local player = { Name = "Trialist" .. playerCount, DisplayName = "Trialist", UserId = playerCount }
	local character = buildPlayerRig(player.Name, rootCFrame or CFrame.new(0, 3, 0))
	local id = EntityService.registerPlayer(player, character, Playground.loadout)
	return id, player, character
end

local function spawnBoar(cframe)
	local model = enemyModel("FrenzyBoar", cframe or CFrame.new(0, 1.2, -4), Vector3.new(2.4, 2.4, 5))
	return EntityService.registerEnemy(model, BOAR), model
end

local function spawnKobold(cframe)
	local model = enemyModel("KoboldAxeman", cframe or CFrame.new(0, 2.2, -4), Vector3.new(2, 2, 1))
	return EntityService.registerEnemy(model, KOBOLD), model
end

-- Advances both services in Heartbeat-sized steps.
local function advance(seconds, step)
	local dt = step or 1 / 60
	local remaining = seconds
	while remaining > 1e-9 do
		local slice = math.min(dt, remaining)
		clock.t += slice
		EntityService.tick(slice)
		CombatService.tick()
		remaining -= slice
	end
end

-- A request stamped with the server clock (what CharacterController sends with no lag), unless
-- `clientTime` says otherwise.
local function artPayload(artId, facing, clientTime)
	return { artId = artId, facing = facing or FORWARD, clientTime = clientTime or clock.t }
end

local function basicPayload(clientTime)
	return { facing = FORWARD, clientTime = clientTime or clock.t }
end

-- Expected Horizontal damage on the boar: Trialist Sword 18, STR 10, no crit, defense 2.
local HORIZONTAL_DAMAGE = math.floor(18 * 1.0 * (1 + 10 * Combat.strDamageScale) - BOAR.defense + 0.5)

-- ------------------------------------------------------------------------------------------
-- Validation
-- ------------------------------------------------------------------------------------------

describe("CombatService.validateArtRequest", function()
	local function check(record, art, payload, context)
		return CombatService.validateArtRequest(record, art, payload, clock.t, context)
	end

	it("accepts a legal Horizontal from Idle, Guard and a basic swing", function()
		fresh()
		local id = spawnPlayer()
		local record = EntityService.get(id)
		expect(check(record, HORIZONTAL, artPayload("OneHandedSword.Horizontal"))).toBe(true)
		EntityService.setGuard(id, true)
		expect(check(record, HORIZONTAL, artPayload("OneHandedSword.Horizontal"))).toBe(true)
		EntityService.setGuard(id, false)
		EntityService.setState(id, "Art", Combat.basicHitDuration, nil, "Basic")
		expect(check(record, HORIZONTAL, artPayload("OneHandedSword.Horizontal"))).toBe(true)
	end)

	it("rejects every bad request with its reason", function()
		fresh()
		local id = spawnPlayer()
		local record = EntityService.get(id)
		local payload = artPayload("OneHandedSword.Horizontal")
		local _, reason = check(nil, HORIZONTAL, payload)
		expect(reason).toBe("NoEntity")
		_, reason = check(record, nil, artPayload("Nothing.Here"))
		expect(reason).toBe("UnknownArt")
		_, reason = check(record, Arts.byId("Rapier.Linear"), artPayload("Rapier.Linear"))
		expect(reason).toBe("WeaponMismatch")
		_, reason = check(record, Arts.byId("OneHandedSword.SonicLeap"), artPayload("OneHandedSword.SonicLeap"))
		expect(reason).toBe("Proficiency") -- unlock 250 > the Trialist's 150
		_, reason = check(record, HORIZONTAL, artPayload("OneHandedSword.Horizontal", { 0, 0, 1 }))
		expect(reason).toBe("Facing") -- reported facing is the server's look vector reversed
		_, reason = check(record, HORIZONTAL, artPayload("OneHandedSword.Horizontal", { 0, 0, 0 }))
		expect(reason).toBe("Facing")
		-- Stance: Sonic Leap needs Moving; with the proficiency it also lacks a clip in Phase 0.
		record.proficiency.OneHandedSword = 300
		table.insert(record.artSlots, "OneHandedSword.SonicLeap") -- slotted, so the stance is what decides
		_, reason = check(record, Arts.byId("OneHandedSword.SonicLeap"), artPayload("OneHandedSword.SonicLeap"), {
			stances = { "Standing" },
		})
		expect(reason).toBe("Stance")
		_, reason = check(record, Arts.byId("OneHandedSword.SonicLeap"), artPayload("OneHandedSword.SonicLeap"), {
			stances = { "Moving" },
		})
		expect(reason).toBe("NoClip")
		-- Locks and busy states
		EntityService.setState(id, "PostMotion", 0.4)
		_, reason = check(record, HORIZONTAL, payload)
		expect(reason).toBe("Locked")
		clock.t += 0.4 - Combat.artRequestTolerance + 0.001
		expect(check(record, HORIZONTAL, payload)).toBe(true) -- inside the request tolerance
		advance(0.1)
		EntityService.setState(id, "Art", 1.0)
		_, reason = check(record, HORIZONTAL, payload)
		expect(reason).toBe("Locked")
		clock.t += 1.0
		_, reason = check(record, HORIZONTAL, payload)
		expect(reason).toBe("Busy:Art")
		advance(0.1)
		EntityService.setState(id, "Stagger", Combat.staggerDuration)
		_, reason = check(record, HORIZONTAL, payload)
		expect(reason).toBe("Locked")
		advance(1)
		-- No weapon
		record.weaponId = nil
		_, reason = check(record, HORIZONTAL, payload)
		expect(reason).toBe("NoWeapon")
		record.weaponId = "NoSuchBlade"
		_, reason = check(record, HORIZONTAL, payload)
		expect(reason).toBe("NoWeapon")
		record.weaponId = "TrialistSword"
		EntityService.die(id)
		_, reason = check(record, HORIZONTAL, payload)
		expect(reason).toBe("Dead")
	end)

	it("facing tolerance is a cosine slack around the server's look vector", function()
		fresh()
		local id = spawnPlayer()
		local record = EntityService.get(id)
		local limit = math.acos(1 - Combat.facingTolerance)
		local inside = math.deg(limit) - 3
		local outside = math.deg(limit) + 3
		local function facingAt(degrees)
			local r = math.rad(degrees)
			return { math.sin(r), 0, -math.cos(r) }
		end
		expect(check(record, HORIZONTAL, artPayload("OneHandedSword.Horizontal", facingAt(inside)))).toBe(true)
		local _, reason = check(record, HORIZONTAL, artPayload("OneHandedSword.Horizontal", facingAt(outside)))
		expect(reason).toBe("Facing")
		-- A pitched facing is compared horizontally.
		expect(check(record, HORIZONTAL, artPayload("OneHandedSword.Horizontal", { 0, -0.7, -0.7 }))).toBe(true)
	end)

	it("the AfterParry stance holds for the Switch window after a parry", function()
		fresh()
		local id = spawnPlayer()
		local record = EntityService.get(id)
		table.insert(record.artSlots, "Test") -- slotted, so the stance is what decides
		local riposte = {
			id = "Test",
			weapon = "OneHandedSword",
			unlock = 0,
			preconditions = { "AfterParry" },
			clip = HORIZONTAL.clip,
		}
		local _, reason =
			check(record, riposte, artPayload("Test"), { lastParryAt = clock.t - Combat.switchWindow - 1 })
		expect(reason).toBe("Stance")
		expect(check(record, riposte, artPayload("Test"), { lastParryAt = clock.t - Combat.switchWindow / 2 })).toBe(
			true
		)
	end)

	it("an Art must sit in the record's quick slots; a record without slots skips the check", function()
		fresh()
		local id, player = spawnPlayer()
		local record = EntityService.get(id)
		local payload = artPayload("OneHandedSword.Horizontal")
		-- The record carries its own copy of the loadout's slots.
		expect(record.artSlots).toEqual(Playground.loadout.artSlots)
		expect(record.artSlots).never.toBe(Playground.loadout.artSlots)
		-- Slotted: accepted.
		expect(check(record, HORIZONTAL, payload)).toBe(true)
		-- Unslotted: NotSlotted, after proficiency (the section 17 order) and before the lock.
		record.artSlots = { "OneHandedSword.Vertical", "OneHandedSword.SharpNail" }
		local ok, reason = check(record, HORIZONTAL, payload)
		expect(ok).toBe(false)
		expect(reason).toBe("NotSlotted")
		ok, reason = check(record, Arts.byId("OneHandedSword.SonicLeap"), artPayload("OneHandedSword.SonicLeap"))
		expect(ok).toBe(false)
		expect(reason).toBe("Proficiency")
		EntityService.setState(id, "PostMotion", 0.4)
		ok, reason = check(record, HORIZONTAL, payload)
		expect(ok).toBe(false)
		expect(reason).toBe("NotSlotted")
		advance(1)
		-- The handler answers the requester with the same reason and starts nothing.
		handlers.ArtRequest(player, payload)
		expect(#sentOf("ActionStarted")).toBe(0)
		expect(lastOf("ActionRejected").action).toBe("Art")
		expect(lastOf("ActionRejected").reason).toBe("NotSlotted")
		expect(lastOf("ActionRejected").clientTime).toBe(payload.clientTime)
		-- Basics are not Arts: the slots never apply to them.
		local basic = { facing = FORWARD, clientTime = 1 }
		expect(CombatService.validateBasicRequest(record, "player/OneHandedSword/Basic1", basic, clock.t)).toBe(true)
		-- A record without slots (stand-ins, enemies with Arts) skips the check.
		record.artSlots = nil
		expect(check(record, HORIZONTAL, payload)).toBe(true)
		handlers.ArtRequest(player, payload)
		expect(#sentOf("ActionStarted")).toBe(1)
		expect(lastOf("ActionStarted").artId).toBe("OneHandedSword.Horizontal")
	end)
end)

describe("CombatService other validators", function()
	it("validateBasicRequest", function()
		fresh()
		local id = spawnPlayer()
		local record = EntityService.get(id)
		local payload = { facing = FORWARD, clientTime = 1 }
		expect(CombatService.validateBasicRequest(record, "player/OneHandedSword/Basic1", payload, clock.t)).toBe(true)
		local _, reason = CombatService.validateBasicRequest(nil, "player/OneHandedSword/Basic1", payload, clock.t)
		expect(reason).toBe("NoEntity")
		_, reason = CombatService.validateBasicRequest(record, "player/OneHandedSword/Basic9", payload, clock.t)
		expect(reason).toBe("NoClip")
		_, reason = CombatService.validateBasicRequest(
			record,
			"player/OneHandedSword/Basic1",
			{ facing = { 0, 0, 1 }, clientTime = 1 },
			clock.t
		)
		expect(reason).toBe("Facing")
		EntityService.setState(id, "Dodge", Combat.dodgeDuration)
		_, reason = CombatService.validateBasicRequest(record, "player/OneHandedSword/Basic1", payload, clock.t)
		expect(reason).toBe("Locked")
	end)

	it("validateDodgeRequest", function()
		fresh()
		local id = spawnPlayer()
		local record = EntityService.get(id)
		local payload = { direction = { 0, 0, 1 }, clientTime = 1 }
		expect(CombatService.validateDodgeRequest(record, payload, clock.t, nil)).toBe(true)
		local _, reason = CombatService.validateDodgeRequest(record, payload, clock.t, clock.t + 0.3)
		expect(reason).toBe("Cooldown")
		expect(CombatService.validateDodgeRequest(record, payload, clock.t, clock.t + Combat.artRequestTolerance / 2)).toBe(
			true
		)
		_, reason =
			CombatService.validateDodgeRequest(record, { direction = { 0, 1, 0 }, clientTime = 1 }, clock.t, nil)
		expect(reason).toBe("Direction")
		EntityService.setState(id, "Stagger", Combat.staggerDuration)
		_, reason = CombatService.validateDodgeRequest(record, payload, clock.t, nil)
		expect(reason).toBe("Locked")
		_, reason = CombatService.validateDodgeRequest(nil, payload, clock.t, nil)
		expect(reason).toBe("NoEntity")
	end)

	it("validateGuardRequest", function()
		fresh()
		local id = spawnPlayer()
		local record = EntityService.get(id)
		expect(CombatService.validateGuardRequest(record)).toBe(true)
		EntityService.setState(id, "PostMotion", 0.4)
		local _, reason = CombatService.validateGuardRequest(record)
		expect(reason).toBe("Busy:PostMotion")
		local _, reason2 = CombatService.validateGuardRequest(nil)
		expect(reason2).toBe("NoEntity")
	end)

	it("nextBasicIndex follows the chain and its window", function()
		expect(CombatService.nextBasicIndex(0, 0, 10)).toBe(1)
		expect(CombatService.nextBasicIndex(1, 10, 10.2)).toBe(2)
		expect(CombatService.nextBasicIndex(2, 10, 10.2)).toBe(3)
		expect(CombatService.nextBasicIndex(3, 10, 10.2)).toBe(1)
		expect(CombatService.nextBasicIndex(1, 10, 10 + Combat.basicChainWindow + 0.01)).toBe(1)
	end)

	it("dodgeClipName picks the clip from the direction in the body's frame", function()
		local root = CFrame.new(0, 3, 0) -- faces -Z
		expect(CombatService.dodgeClipName(root, Vector3.new(0, 0, -1))).toBe("DodgeForward")
		expect(CombatService.dodgeClipName(root, Vector3.new(0, 0, 1))).toBe("DodgeBack")
		expect(CombatService.dodgeClipName(root, Vector3.new(1, 0, 0))).toBe("DodgeRight")
		expect(CombatService.dodgeClipName(root, Vector3.new(-1, 0, 0))).toBe("DodgeLeft")
		local turned = CFrame.lookAt(Vector3.new(), Vector3.new(1, 0, 0))
		expect(CombatService.dodgeClipName(turned, Vector3.new(1, 0, 0))).toBe("DodgeForward")
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Art timeline
-- ------------------------------------------------------------------------------------------

describe("CombatService Art timeline", function()
	it(
		"an accepted ArtRequest starts the clip for everyone, sweeps the window, hits the boar, then post-motion",
		function()
			fresh()
			local playerId, player = spawnPlayer()
			local boarId = spawnBoar()
			local landed = {}
			CombatService.HitLanded:Connect(function(hit)
				table.insert(landed, hit)
			end)
			local started = nil
			CombatService.ArtStarted:Connect(function(record, art)
				started = { record.id, art.id }
			end)
			local ended = nil
			CombatService.ArtEnded:Connect(function(record, art, hitAny)
				ended = { record.id, art.id, hitAny }
			end)

			handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
			task.wait()
			expect(#sentOf("ActionRejected")).toBe(0)
			local action = lastOf("ActionStarted")
			expect(action.entityId).toBe(playerId)
			expect(action.clipId).toBe("player/OneHandedSword/Horizontal")
			expect(action.artId).toBe("OneHandedSword.Horizontal")
			expect(action.serverTime).toBe(clock.t)
			expect(action.facing).toEqual(FORWARD)
			expect(started).toEqual({ playerId, "OneHandedSword.Horizontal" })
			local record = EntityService.get(playerId)
			expect(record.state).toBe("Art")
			expect(record.lockUntil).toBeCloseTo(clock.t + 0.6 + HORIZONTAL.postMotion, 1e-9)
			local art, startedAt = CombatService.currentArt(playerId)
			expect(art.id).toBe("OneHandedSword.Horizontal")
			expect(startedAt).toBe(clock.t)
			expect(CombatService.rootMotionAllowance(playerId)).toBe(HORIZONTAL.rootMotion + Combat.rootMotionSlack)

			-- Before the window opens nothing is hit.
			local windows = ClipSampler.hitWindows(Horizontal)
			advance(windows[1].open - 0.02)
			expect(#landed).toBe(0)
			expect(EntityService.get(boarId).hp).toBe(BOAR.hp)
			-- Through the window: exactly one hit on the boar.
			advance(windows[1].close - windows[1].open + 0.04)
			task.wait()
			expect(#landed).toBe(1)
			expect(landed[1].targetId).toBe(boarId)
			expect(landed[1].attackerId).toBe(playerId)
			expect(landed[1].damage).toBe(HORIZONTAL_DAMAGE)
			expect(landed[1].gaugeDamage).toBe(HORIZONTAL.gaugeDamage)
			expect(landed[1].hitStop).toBe("Final") -- the only window is the last window
			expect(landed[1].artId).toBe("OneHandedSword.Horizontal")
			expect(landed[1].hitIndex).toBe(1)
			expect(EntityService.get(boarId).hp).toBe(BOAR.hp - HORIZONTAL_DAMAGE)
			local confirmed = sentOf("HitConfirmed")
			expect(#confirmed).toBe(1)
			expect(confirmed[1].damage).toBe(HORIZONTAL_DAMAGE)
			expect(confirmed[1].crit).toBe(false)
			expect(confirmed[1].parried).toBe(false)
			expect(#confirmed[1].position).toBe(3)
			-- The boar faces -Z, away from the player: the blow lands on its back.
			expect(confirmed[1].staggerDirection).toBe("Back")
			local switch = lastOf("SwitchWindow")
			expect(switch.entityId).toBe(boarId)
			expect(switch.openerId).toBe(playerId)
			expect(switch.duration).toBe(Combat.switchWindow)
			-- Still executing until the end pose, then PostMotion for the Art's post-motion, then Idle.
			expect(record.state).toBe("Art")
			advance(0.6 - (clock.t - startedAt) + 0.01)
			expect(record.state).toBe("PostMotion")
			expect(lastOf("StateChanged").state).toBe("PostMotion")
			expect(lastOf("StateChanged").duration).toBe(HORIZONTAL.postMotion)
			task.wait()
			expect(ended).toEqual({ playerId, "OneHandedSword.Horizontal", true })
			expect(CombatService.currentArt(playerId)).toBeNil()
			advance(HORIZONTAL.postMotion + 0.02)
			expect(record.state).toBe("Idle")
		end
	)

	it("a multi-hit Art hits the same target once per window and marks the last window Final", function()
		fresh()
		local playerId, player = spawnPlayer()
		-- A wide training dummy: Sharp Nail's second cut rises up and to the right, over a boar-height
		-- body standing dead ahead, so a boar only takes the first and third strike at this range.
		local dummy = enemyModel("Dummy", CFrame.new(0, 2, -4), Vector3.new(6, 4, 6))
		EntityService.registerEnemy(dummy, KOBOLD)
		local landed = {}
		CombatService.HitLanded:Connect(function(hit)
			table.insert(landed, hit)
		end)
		handlers.ArtRequest(player, artPayload("OneHandedSword.SharpNail"))
		local SharpNail = Harness.load("src/shared/clips/player/OneHandedSword/SharpNail")
		local windows = ClipSampler.hitWindows(SharpNail)
		expect(#windows).toBe(3)
		advance(windows[#windows].close + 0.05)
		task.wait()
		expect(#landed).toBe(3)
		expect(landed[1].hitIndex).toBe(1)
		expect(landed[1].hitStop).toBe("Normal")
		expect(landed[2].hitStop).toBe("Normal")
		expect(landed[3].hitIndex).toBe(3)
		expect(landed[3].hitStop).toBe("Final")
		expect(#sentOf("SwitchWindow")).toBe(1) -- the ring shows once per Art
		expect(EntityService.get(playerId).state).toBe("Art")
	end)

	it("an Art landed on a Broken enemy has zero post-motion and doubles its damage", function()
		fresh()
		local playerId, player = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.setState(boarId, "Break", Combat.breakDuration)
		EntityService.get(boarId).gauge = 0
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		advance(0.6 + 0.01)
		local hit = lastOf("HitConfirmed")
		expect(hit.damage).toBe(math.floor(HORIZONTAL_DAMAGE * Combat.breakDamageMultiplier + 0.5))
		expect(EntityService.get(playerId).state).toBe("Idle")
		expect(lastOf("StateChanged").state).toBe("Idle")
	end)

	it("a stagger mid-Art cancels the timeline: no hit, ArtEnded without a landing", function()
		fresh()
		local playerId, player = spawnPlayer()
		local boarId = spawnBoar()
		local ended = nil
		CombatService.ArtEnded:Connect(function(_record, _art, hitAny)
			ended = hitAny
		end)
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		advance(0.2)
		EntityService.setState(playerId, "Stagger", Combat.staggerDuration, "Front")
		advance(0.5)
		task.wait()
		expect(#sentOf("HitConfirmed")).toBe(0)
		expect(EntityService.get(boarId).hp).toBe(BOAR.hp)
		expect(ended).toBe(false)
		expect(CombatService.currentArt(playerId)).toBeNil()
		expect(CombatService.rootMotionAllowance(playerId)).toBe(0)
	end)

	it("a kill mid-Art reports Kill hit-stop and the Art still finishes", function()
		fresh()
		local playerId, player = spawnPlayer()
		local boarId = spawnBoar()
		EntityService.get(boarId).hp = 1
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		advance(0.5)
		local hit = lastOf("HitConfirmed")
		expect(hit.killed).toBe(true)
		expect(hit.hitStop).toBe("Kill")
		expect(#sentOf("EntityDied")).toBe(1)
		expect(#sentOf("SwitchWindow")).toBe(0) -- no window on a corpse
		advance(0.2)
		expect(EntityService.get(playerId).state).toBe("PostMotion")
	end)

	it("rejects go back to the requester with the reason and the echoed clientTime", function()
		fresh()
		local _, player = spawnPlayer()
		handlers.ArtRequest(player, artPayload("OneHandedSword.SonicLeap", nil, 12.5))
		expect(#sentOf("ActionStarted")).toBe(0)
		local rejected = sent[#sent]
		expect(rejected.remote).toBe("ActionRejected")
		expect(rejected.player).toBe(player)
		expect(rejected.payload.action).toBe("Art")
		expect(rejected.payload.reason).toBe("Proficiency")
		expect(rejected.payload.clientTime).toBe(12.5)
		-- A player with no character gets NoEntity.
		local stranger = { Name = "Stranger", DisplayName = "Stranger", UserId = 99 }
		handlers.ArtRequest(stranger, artPayload("OneHandedSword.Horizontal"))
		expect(sent[#sent].payload.reason).toBe("NoEntity")
		expect(sent[#sent].player).toBe(stranger)
	end)

	it("a swordsman without trail attachments swings without hitting and warns once", function()
		fresh()
		local _, player, character = spawnPlayer()
		character:FindFirstChild("TrailStart", true):Destroy()
		spawnBoar()
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		advance(0.6)
		expect(#sentOf("HitConfirmed")).toBe(0)
		local warnings = 0
		for _, line in Harness.warnings() do
			if line:find("TrailStart", 1, true) then
				warnings += 1
			end
		end
		expect(warnings).toBe(1)
	end)

	it("beginArt is the same path for code callers (bosses, smoke tests)", function()
		fresh()
		local playerId = spawnPlayer()
		expect(CombatService.beginArt(playerId, "OneHandedSword.Vertical")).toBe(true)
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Vertical")
		local ok, reason = CombatService.beginArt(playerId, "OneHandedSword.Horizontal")
		expect(ok).toBe(false)
		expect(reason).toBe("Locked")
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The sweep under the engine's rules: casts never see what they start inside
-- ------------------------------------------------------------------------------------------

describe("CombatService hit sweep", function()
	-- Rebinds the engine with another broad phase (the casts stay the engine-like fake).
	local function useOverlap(overlap)
		CombatService.bind({
			now = function()
				return clock.t
			end,
			net = fakeNet,
			heartbeat = nil,
			cast = fakeCast,
			overlap = overlap,
			random = noCrit,
		})
	end

	local function noOverlap()
		return {}
	end

	-- Where the swordsman's blade is at clip time `time`, solved the way the server solves it.
	local function bladeAt(character, time)
		local trailStart, trailEnd = HitSweep.trailAttachments(character)
		local samples =
			HitSweep.bladePath(character, character.PrimaryPart.CFrame, Horizontal, { time }, trailStart, trailEnd)
		return samples[1]
	end

	it("a Horizontal that opens its window with the blade buried in the boar lands once", function()
		local window = ClipSampler.hitWindows(Horizontal)[1]
		for _, overlap in { fakeOverlap, noOverlap } do
			fresh()
			useOverlap(overlap)
			local _, player, character = spawnPlayer()
			local opening = bladeAt(character, window.open)
			local boarId, boarModel = spawnBoar(CFrame.new(opening.mid))
			local boarRoot = boarModel.PrimaryPart
			-- The whole blade lies inside the boar's body when the window opens.
			expect(HitSweep.segmentBoxDistance(opening.start, opening.finish, boarRoot.CFrame, boarRoot.Size)).toBe(0)
			handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
			advance(0.6)
			local confirmed = sentOf("HitConfirmed")
			if overlap == fakeOverlap then
				expect(#confirmed).toBe(1)
				expect(confirmed[1].targetId).toBe(boarId)
				expect(EntityService.get(boarId).hp).toBe(BOAR.hp - HORIZONTAL_DAMAGE)
			else
				-- The engine's casts alone never report it: every one starts inside the boar.
				expect(#confirmed).toBe(0)
			end
		end
	end)

	it("a boar that steps onto the resting blade during the Hold lands on the next frame", function()
		for _, overlap in { fakeOverlap, noOverlap } do
			fresh()
			useOverlap(overlap)
			local _, player, character = spawnPlayer()
			local boarId, boarModel = spawnBoar(CFrame.new(0, 1.2, -40))
			handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
			-- Into the clip's Hold (0.40 to 0.43): the window is open and the blade is still.
			advance(0.41)
			expect(#sentOf("HitConfirmed")).toBe(0)
			local holding = bladeAt(character, 0.41)
			expect((bladeAt(character, 0.425).finish - holding.finish).Magnitude).toBeLessThan(1e-4)
			boarModel.PrimaryPart.CFrame = CFrame.new(holding.mid)
			advance(1 / 60)
			if overlap == fakeOverlap then
				expect(#sentOf("HitConfirmed")).toBe(1)
				expect(lastOf("HitConfirmed").targetId).toBe(boarId)
			else
				expect(#sentOf("HitConfirmed")).toBe(0)
			end
			-- Still one hit (or none) by the end of the Art.
			advance(0.2)
			expect(#sentOf("HitConfirmed")).toBe(if overlap == fakeOverlap then 1 else 0)
		end
	end)

	it("every sample of a window is tested for overlap once", function()
		fresh()
		local _, player = spawnPlayer()
		spawnBoar(CFrame.new(0, 1.2, -40))
		local window = ClipSampler.hitWindows(Horizontal)[1]
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		-- Count the samples the timeline takes, frame by frame, the way stepRun asks for them.
		local expected = 0
		local sampledTo = nil
		local elapsed = 0
		while elapsed < 0.6 do
			advance(1 / 60)
			elapsed += 1 / 60
			if elapsed >= window.open and (sampledTo == nil or sampledTo < window.close) then
				local toTime = math.min(elapsed, window.close)
				local from = sampledTo or window.open
				expected += #HitSweep.sampleTimes(from, toTime, Combat.hitSampleHz, sampledTo == nil)
				sampledTo = toTime
			end
		end
		expect(expected).toBeGreaterThan(5)
		expect(overlapQueries).toBe(expected)
	end)

	it("a swordsman whose blade the joints cannot reach warns once and never hits", function()
		fresh()
		local _, player, character = spawnPlayer()
		spawnBoar()
		character:FindFirstChild("RightHand"):FindFirstChild("Weapon"):Destroy()
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		advance(1.2)
		handlers.ArtRequest(player, artPayload("OneHandedSword.Vertical"))
		advance(1.2)
		expect(#sentOf("ActionStarted")).toBe(2)
		expect(#sentOf("HitConfirmed")).toBe(0)
		local warnings = 0
		for _, line in Harness.warnings() do
			if line:find("cannot be solved", 1, true) then
				warnings += 1
			end
		end
		expect(warnings).toBe(1)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Hit direction and the lag allowance
-- ------------------------------------------------------------------------------------------

describe("CombatService hit direction", function()
	it("HitConfirmed names the side the blade came from, so the enemy flinches from it", function()
		fresh()
		local _, player = spawnPlayer()
		-- The boar faces the player: the cut lands on its front.
		spawnBoar(CFrame.lookAt(Vector3.new(0, 1.2, -4), Vector3.new(0, 1.2, 0)))
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		advance(0.6)
		local hit = lastOf("HitConfirmed")
		expect(hit).never.toBeNil()
		expect(hit.parried).toBe(false)
		expect(hit.staggerDirection).toBe("Front")
	end)
end)

describe("CombatService lag allowance", function()
	it("runStartOf clamps the client's stamp into [now - lagAllowance, now]", function()
		expect(CombatService.runStartOf(9.9, 10)).toBeCloseTo(9.9, 1e-9)
		expect(CombatService.runStartOf(10, 10)).toBe(10)
		expect(CombatService.runStartOf(5, 10)).toBeCloseTo(10 - Combat.lagAllowance, 1e-9)
		expect(CombatService.runStartOf(11, 10)).toBe(10) -- never in the future
		expect(CombatService.runStartOf(nil, 10)).toBe(10)
		expect(CombatService.runStartOf(0 / 0, 10)).toBe(10)
	end)

	it("runStartOf never reaches back before the moment the body was last free", function()
		-- Free since 9.95: a stamp further back is floored there; one after it is kept.
		expect(CombatService.runStartOf(9.85, 10, 9.95)).toBeCloseTo(9.95, 1e-9)
		expect(CombatService.runStartOf(0, 10, 9.95)).toBeCloseTo(9.95, 1e-9)
		expect(CombatService.runStartOf(9.97, 10, 9.95)).toBeCloseTo(9.97, 1e-9)
		-- Free long ago: the lag allowance is the only bound.
		expect(CombatService.runStartOf(0, 10, 5)).toBeCloseTo(10 - Combat.lagAllowance, 1e-9)
		-- A lock still running at receipt (inside artRequestTolerance, a basic being cut): no rewind.
		expect(CombatService.runStartOf(9.9, 10, 10 + Combat.artRequestTolerance)).toBe(10)
		expect(CombatService.runStartOf(0, 10, 10)).toBe(10)
		-- Still never in the future, and a missing stamp is still the receipt.
		expect(CombatService.runStartOf(11, 10, 9.95)).toBe(10)
		expect(CombatService.runStartOf(nil, 10, 9.95)).toBe(10)
	end)

	local STEP = 1 / 240

	-- Seconds from the request's receipt to its first HitConfirmed on a boar ahead, and the
	-- broadcast start relative to the receipt. The fighter has been free for a second first, so the
	-- spawn instant does not floor the rewind.
	local function firstHitAfter(lag)
		fresh()
		local _, player = spawnPlayer()
		spawnBoar()
		advance(1)
		local receivedAt = clock.t
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal", nil, receivedAt - lag))
		local started = lastOf("ActionStarted")
		while #sentOf("HitConfirmed") == 0 and clock.t - receivedAt < 1 do
			advance(STEP, STEP)
		end
		expect(#sentOf("HitConfirmed")).toBe(1)
		return clock.t - receivedAt, started.serverTime - receivedAt
	end

	it("a request stamped 0.1 s early sweeps 0.1 s sooner; one 0.5 s early is clamped to 0.15 s", function()
		local onTime, onTimeStart = firstHitAfter(0)
		local late, lateStart = firstHitAfter(0.1)
		local stale, staleStart = firstHitAfter(0.5)
		expect(onTimeStart).toBeCloseTo(0, 1e-9)
		expect(lateStart).toBeCloseTo(-0.1, 1e-6)
		expect(staleStart).toBeCloseTo(-Combat.lagAllowance, 1e-6)
		expect(onTime - late).toBeCloseTo(0.1, STEP + 1e-6)
		expect(onTime - stale).toBeCloseTo(Combat.lagAllowance, STEP + 1e-6)
	end)

	it("the clamped start moves the broadcast, the timeline and the lock; code callers start now", function()
		fresh()
		local playerId, player = spawnPlayer()
		advance(1) -- free well before the stamp: the spawn instant does not floor the rewind
		local receivedAt = clock.t
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal", nil, receivedAt - 0.1))
		expect(lastOf("ActionStarted").serverTime).toBeCloseTo(receivedAt - 0.1, 1e-6)
		local _, startedAt = CombatService.currentArt(playerId)
		expect(startedAt).toBeCloseTo(receivedAt - 0.1, 1e-6)
		local record = EntityService.get(playerId)
		expect(record.lockUntil).toBeCloseTo(receivedAt - 0.1 + 0.6 + HORIZONTAL.postMotion, 1e-6)
		-- The end pose freezes 0.6 s after the clamped start, not after the receipt.
		advance(0.6 - 0.1 + 0.01)
		expect(record.state).toBe("PostMotion")
		advance(HORIZONTAL.postMotion + 0.02)
		expect(record.state).toBe("Idle")

		-- A stamp from the future starts at the receipt.
		advance(Combat.basicChainWindow + 0.1)
		handlers.BasicAttackRequest(player, basicPayload(clock.t + 1))
		expect(lastOf("ActionStarted").serverTime).toBe(clock.t)
		advance(Combat.basicHitDuration + 0.05)
		expect(record.state).toBe("Idle")

		-- A lagged basic swing: the same clamp, its Art state shortened by the catch-up.
		advance(Combat.basicChainWindow + 0.1)
		handlers.BasicAttackRequest(player, basicPayload(clock.t - 0.05))
		expect(lastOf("ActionStarted").serverTime).toBeCloseTo(clock.t - 0.05, 1e-6)
		expect(lastOf("StateChanged").duration).toBeCloseTo(Combat.basicHitDuration - 0.05, 1e-6)
		advance(Combat.basicHitDuration + 0.05)

		-- beginArt / beginBasic (bosses, smoke tests) have no client stamp: they start now.
		expect(CombatService.beginBasic(playerId)).toBe(true)
		expect(lastOf("ActionStarted").serverTime).toBe(clock.t)
		advance(Combat.basicHitDuration + 0.05)
		expect(CombatService.beginArt(playerId, "OneHandedSword.Horizontal")).toBe(true)
		expect(lastOf("ActionStarted").serverTime).toBe(clock.t)
		expect(select(2, CombatService.currentArt(playerId))).toBe(clock.t)
	end)

	-- Steps the running Art into its PostMotion and returns the moment that lock ends.
	local function postMotionEnd(record)
		while record.state == "Art" do
			advance(1 / 60)
		end
		expect(record.state).toBe("PostMotion")
		return record.lockUntil
	end

	it("an early stamp sent at the end of PostMotion never starts before the previous lock allows", function()
		fresh()
		local playerId, player = spawnPlayer()
		advance(1)
		local record = EntityService.get(playerId)
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		local firstStart = lastOf("ActionStarted").serverTime
		local firstLock = record.lockUntil - firstStart
		local lockEnd = postMotionEnd(record)

		-- Sent the moment the request tolerance accepts it, stamped far in the past: the lock is still
		-- running at receipt, so the Art starts at the receipt, never up to lagAllowance inside it.
		clock.t = lockEnd - Combat.artRequestTolerance
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal", nil, 0))
		expect(#sentOf("ActionRejected")).toBe(0)
		local secondStart = lastOf("ActionStarted").serverTime
		expect(secondStart).toBe(clock.t)
		expect(secondStart).toBeGreaterThanOrEqual(lockEnd - Combat.artRequestTolerance)
		expect(select(2, CombatService.currentArt(playerId))).toBe(clock.t)
		expect(record.lockUntil).toBeCloseTo(clock.t + firstLock, 1e-9) -- the whole lock, none cut away
		-- Back to back, Arts are as far apart as the clip allows (section 17): the lock less the tolerance.
		expect(secondStart - firstStart).toBeGreaterThanOrEqual(firstLock - Combat.artRequestTolerance - 1e-9)

		-- Sent after that lock ran out, stamped far in the past: it rewinds to the moment the body
		-- became free and no further.
		lockEnd = postMotionEnd(record)
		advance(lockEnd - clock.t + 0.05)
		expect(record.state).toBe("Idle")
		local freeAt = record.lockUntil
		expect(freeAt).toBeGreaterThanOrEqual(lockEnd)
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal", nil, 0))
		expect(#sentOf("ActionRejected")).toBe(0)
		expect(lastOf("ActionStarted").serverTime).toBe(freeAt)
		expect(lastOf("ActionStarted").serverTime).toBeLessThan(clock.t) -- still a rewind, just a bounded one
	end)

	it("an early stamp sent out of a Stagger never starts inside the stagger", function()
		fresh()
		local playerId, player = spawnPlayer()
		local koboldId = spawnKobold(CFrame.lookAt(Vector3.new(0, 2.2, -4), Vector3.new(0, 2.2, 0)))
		advance(1)
		local record = EntityService.get(playerId)
		local function stagger()
			CombatService.enemyStrike(koboldId, OVERHEAD, Vector3.new(0, 2.2, -4), Vector3.new(0, 0, 1))
			expect(record.state).toBe("Stagger")
			return record.lockUntil
		end

		-- Accepted inside the request tolerance: the stagger still runs, so the Art starts at receipt.
		local staggerEnd = stagger()
		clock.t = staggerEnd - Combat.artRequestTolerance
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal", nil, 0))
		expect(#sentOf("ActionRejected")).toBe(0)
		expect(lastOf("ActionStarted").serverTime).toBe(clock.t)
		expect(lastOf("ActionStarted").serverTime).toBeGreaterThanOrEqual(staggerEnd - Combat.artRequestTolerance)

		-- The same for a basic swing, after a second stagger has cut that Art.
		staggerEnd = stagger()
		expect(CombatService.currentArt(playerId)).toBeNil()
		clock.t = staggerEnd - Combat.artRequestTolerance
		handlers.BasicAttackRequest(player, basicPayload(0))
		expect(#sentOf("ActionRejected")).toBe(0)
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic1")
		expect(lastOf("ActionStarted").serverTime).toBe(clock.t)

		-- Sent after the stagger ran out: back to the moment the body stood up, no further.
		staggerEnd = stagger()
		advance(staggerEnd - clock.t + 0.05)
		expect(record.state).toBe("Idle")
		local freeAt = record.lockUntil
		expect(freeAt).toBeGreaterThanOrEqual(staggerEnd)
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal", nil, 0))
		expect(#sentOf("ActionRejected")).toBe(0)
		expect(lastOf("ActionStarted").serverTime).toBe(freeAt)
		expect(select(2, CombatService.currentArt(playerId))).toBe(freeAt)
	end)

	it("a basic swing still in flight is cut at receipt: the next basic or Art never rewinds into it", function()
		fresh()
		local playerId, player = spawnPlayer()
		advance(1)
		local record = EntityService.get(playerId)
		handlers.BasicAttackRequest(player, basicPayload())
		advance(0.2)
		expect(record.stateTag).toBe("Basic")
		expect(record.lockUntil).toBeGreaterThan(clock.t)
		-- The next basic, stamped 0.1 s early, starts at its receipt with its whole swing.
		handlers.BasicAttackRequest(player, basicPayload(clock.t - 0.1))
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic2")
		expect(lastOf("ActionStarted").serverTime).toBe(clock.t)
		expect(lastOf("StateChanged").duration).toBe(Combat.basicHitDuration)
		-- An Art cutting that swing, stamped 0.1 s early, starts at its receipt too.
		advance(0.2)
		expect(record.stateTag).toBe("Basic")
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal", nil, clock.t - 0.1))
		expect(lastOf("ActionStarted").artId).toBe("OneHandedSword.Horizontal")
		expect(lastOf("ActionStarted").serverTime).toBe(clock.t)
		expect(select(2, CombatService.currentArt(playerId))).toBe(clock.t)
		expect(#sentOf("ActionRejected")).toBe(0)
	end)

	it("the basic chain counts its window from the rewound start, the clock the client swung on", function()
		fresh()
		local _, player = spawnPlayer()
		advance(1)
		-- Basic1 stamped and received at t0; Basic2 pressed at t0 + 0.55 (inside the window) and
		-- delivered at t0 + 0.65 (outside it): the server picks Basic2, started where it was pressed.
		local t0 = clock.t
		handlers.BasicAttackRequest(player, basicPayload(t0))
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic1")
		-- The premise: 0.55 s is inside the chain window, 0.65 s is past it.
		expect(0.55).toBeLessThan(Combat.basicChainWindow)
		expect(0.65).toBeGreaterThan(Combat.basicChainWindow)
		advance(0.65)
		expect(clock.t - t0).toBeCloseTo(0.65, 1e-9)
		handlers.BasicAttackRequest(player, basicPayload(t0 + 0.55))
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic2")
		expect(lastOf("ActionStarted").serverTime).toBeCloseTo(t0 + 0.55, 1e-9)

		-- Basic1 stamped t1 - 0.1 and received at t1; Basic2 stamped and received at t1 + 0.55: the
		-- chain window ran from t1 - 0.1, so it closed and the chain restarts at Basic1.
		advance(1)
		local t1 = clock.t
		handlers.BasicAttackRequest(player, basicPayload(t1 - 0.1))
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic1")
		expect(lastOf("ActionStarted").serverTime).toBeCloseTo(t1 - 0.1, 1e-9)
		advance(0.55)
		handlers.BasicAttackRequest(player, basicPayload())
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic1")
		expect(lastOf("ActionStarted").serverTime).toBe(clock.t)
		expect(#sentOf("ActionRejected")).toBe(0)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Basic attacks and dodges
-- ------------------------------------------------------------------------------------------

describe("CombatService basics and dodge", function()
	it("the three-hit chain picks Basic1..3 inside the window and restarts outside it", function()
		fresh()
		local playerId, player = spawnPlayer()
		spawnBoar()
		handlers.BasicAttackRequest(player, basicPayload())
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic1")
		expect(lastOf("ActionStarted").artId).toBeNil()
		local record = EntityService.get(playerId)
		expect(record.state).toBe("Art")
		expect(record.stateTag).toBe("Basic")
		expect(lastOf("StateChanged").duration).toBe(Combat.basicHitDuration)
		advance(0.3)
		-- The first swing landed with the basic multiplier and a tenth of the gauge.
		local hit = lastOf("HitConfirmed")
		expect(hit).never.toBeNil()
		expect(hit.damage).toBe(math.floor(18 * Combat.basicAttackMultiplier * 1.12 - BOAR.defense + 0.5))
		expect(hit.gaugeDamage).toBeCloseTo(HORIZONTAL.gaugeDamage * Combat.basicAttackGaugeFraction, 1e-9)
		expect(hit.artId).toBeNil()
		expect(hit.hitStop).toBe("Normal") -- only the chain's third swing is the final hit
		handlers.BasicAttackRequest(player, basicPayload())
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic2")
		advance(0.3)
		expect(lastOf("HitConfirmed").hitStop).toBe("Normal")
		handlers.BasicAttackRequest(player, basicPayload())
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic3")
		advance(0.3)
		expect(lastOf("HitConfirmed").hitStop).toBe("Final")
		handlers.BasicAttackRequest(player, basicPayload())
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic1")
		advance(Combat.basicChainWindow + 0.5)
		expect(record.state).toBe("Idle")
		handlers.BasicAttackRequest(player, basicPayload())
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/Basic1")
		expect(#sentOf("ActionRejected")).toBe(0)
	end)

	it("an Art can cancel a basic swing; a basic cannot interrupt an Art", function()
		fresh()
		local playerId, player = spawnPlayer()
		handlers.BasicAttackRequest(player, basicPayload())
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		expect(#sentOf("ActionRejected")).toBe(0)
		expect(EntityService.get(playerId).stateTag).toBeNil()
		local art = CombatService.currentArt(playerId)
		expect(art.id).toBe("OneHandedSword.Horizontal")
		handlers.BasicAttackRequest(player, basicPayload())
		expect(lastOf("ActionRejected").action).toBe("BasicAttack")
		expect(lastOf("ActionRejected").reason).toBe("Locked")
	end)

	it("a dodge sets Dodge, grants invulnerability frames, picks the clip and enforces the cooldown", function()
		fresh()
		local playerId, player = spawnPlayer()
		EntityService.setGuard(playerId, true)
		handlers.DodgeRequest(player, { direction = { 0, 0, 1 }, clientTime = 3 })
		local record = EntityService.get(playerId)
		expect(record.state).toBe("Dodge")
		expect(record.guardHeld).toBe(false)
		expect(EntityService.isInvulnerable(playerId)).toBe(true)
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/DodgeBack")
		expect(lastOf("StateChanged").duration).toBe(Combat.dodgeDuration)
		advance(Combat.dodgeInvulnerability + 0.01)
		expect(EntityService.isInvulnerable(playerId)).toBe(false)
		advance(Combat.dodgeDuration)
		expect(record.state).toBe("Idle")
		handlers.DodgeRequest(player, { direction = { 1, 0, 0 }, clientTime = 4 })
		expect(lastOf("ActionRejected").action).toBe("Dodge")
		expect(lastOf("ActionRejected").reason).toBe("Cooldown")
		advance(Combat.dodgeCooldown)
		handlers.DodgeRequest(player, { direction = { 1, 0, 0 }, clientTime = 5 })
		expect(lastOf("ActionStarted").clipId).toBe("player/OneHandedSword/DodgeRight")
	end)

	it("guard requests raise and lower the guard and reject a raise mid-lock", function()
		fresh()
		local playerId, player = spawnPlayer()
		handlers.GuardRequest(player, { held = true, facing = FORWARD, clientTime = 1 })
		local record = EntityService.get(playerId)
		expect(record.state).toBe("Guard")
		handlers.GuardRequest(player, { held = false, facing = FORWARD, clientTime = 2 })
		expect(record.state).toBe("Idle")
		EntityService.setState(playerId, "PostMotion", 0.4)
		handlers.GuardRequest(player, { held = true, facing = FORWARD, clientTime = 3 })
		expect(lastOf("ActionRejected").action).toBe("Guard")
		expect(lastOf("ActionRejected").reason).toBe("Busy:PostMotion")
		-- Releasing is always accepted, even while locked.
		local before = #sentOf("ActionRejected")
		handlers.GuardRequest(player, { held = false, facing = FORWARD, clientTime = 4 })
		expect(#sentOf("ActionRejected")).toBe(before)
	end)

	it("target, switch call and client ready", function()
		fresh()
		local playerId, player = spawnPlayer()
		local boarId = spawnBoar()
		handlers.TargetRequest(player, { entityId = boarId })
		expect(EntityService.get(playerId).targetId).toBe(boarId)
		handlers.TargetRequest(player, { entityId = 777 })
		expect(lastOf("ActionRejected").action).toBe("Target")
		handlers.TargetRequest(player, {})
		expect(EntityService.get(playerId).targetId).toBeNil()
		handlers.SwitchCallRequest(player, {})
		expect(CombatService.isReady(player)).toBe(false)
		handlers.ClientReady(player, {})
		expect(CombatService.isReady(player)).toBe(true)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Enemy strikes
-- ------------------------------------------------------------------------------------------

describe("CombatService.enemyStrike", function()
	-- The kobold stands 4 studs in front of the player (toward -Z) and faces the player (+Z).
	local KOBOLD_CFRAME = CFrame.lookAt(Vector3.new(0, 2.2, -4), Vector3.new(0, 2.2, 0))

	local function strikeOverhead(koboldId)
		return CombatService.enemyStrike(koboldId, OVERHEAD, Vector3.new(0, 2.2, -4), Vector3.new(0, 0, 1))
	end

	it("full damage on an open player: HitConfirmed, a directional stagger, an Art cancelled", function()
		fresh()
		local playerId, player = spawnPlayer()
		local koboldId = spawnKobold(KOBOLD_CFRAME)
		handlers.ArtRequest(player, artPayload("OneHandedSword.Horizontal"))
		local results = strikeOverhead(koboldId)
		expect(#results).toBe(1)
		local expected = math.floor(KOBOLD.attack * OVERHEAD.multiplier - EntityService.get(playerId).defense + 0.5)
		expect(results[1].damage).toBe(expected)
		expect(results[1].guarded).toBe(false)
		expect(results[1].parried).toBe(false)
		expect(EntityService.get(playerId).hp).toBe(300 - expected)
		expect(EntityService.get(playerId).gauge).toBe(100) -- an open hit costs HP, never gauge
		expect(results[1].gaugeDamage).toBe(0)
		expect(EntityService.get(playerId).state).toBe("Stagger")
		expect(lastOf("StateChanged").state).toBe("Stagger")
		expect(lastOf("StateChanged").direction).toBe("Front")
		expect(lastOf("StateChanged").duration).toBe(Combat.staggerDuration)
		expect(CombatService.currentArt(playerId)).toBeNil()
		local hit = lastOf("HitConfirmed")
		expect(hit.attackerId).toBe(koboldId)
		expect(hit.targetId).toBe(playerId)
		expect(hit.hitStop).toBe("Normal")
		expect(hit.staggerDirection).toBe("Front") -- the same side the StateChanged flinch names
	end)

	it(
		"a guard raised inside the parry window parries: no damage, the enemy staggers, a Switch window opens",
		function()
			fresh()
			local playerId, player = spawnPlayer()
			local koboldId = spawnKobold(KOBOLD_CFRAME)
			local parried = nil
			CombatService.Parried:Connect(function(playerRecord, enemyRecord)
				parried = { playerRecord.id, enemyRecord.id }
			end)
			EntityService.setState(koboldId, "Art", 1.4)
			handlers.GuardRequest(player, { held = true, facing = FORWARD, clientTime = 1 })
			clock.t += Combat.parryWindow / 2
			local results = strikeOverhead(koboldId)
			task.wait()
			expect(#results).toBe(1)
			expect(results[1].parried).toBe(true)
			expect(results[1].damage).toBe(0)
			expect(EntityService.get(playerId).hp).toBe(300)
			expect(EntityService.get(playerId).gauge).toBe(100)
			expect(EntityService.get(playerId).state).toBe("Guard")
			expect(EntityService.get(koboldId).state).toBe("Stagger")
			expect(lastOf("StateChanged").entityId).toBe(koboldId)
			expect(lastOf("StateChanged").duration).toBe(Combat.parryStagger)
			local hit = lastOf("HitConfirmed")
			expect(hit.parried).toBe(true)
			expect(hit.damage).toBe(0)
			local switch = lastOf("SwitchWindow")
			expect(switch.entityId).toBe(koboldId)
			expect(switch.openerId).toBe(playerId)
			expect(parried).toEqual({ playerId, koboldId })
			-- The parry stagger runs out and the kobold stands again.
			advance(Combat.parryStagger + 0.1)
			expect(EntityService.get(koboldId).state).toBe("Idle")
		end
	)

	it("a guard held longer than the window blocks a Normal strike: reduced damage, gauge drain, no stagger", function()
		fresh()
		local playerId, player = spawnPlayer()
		local boarId = spawnBoar(CFrame.lookAt(Vector3.new(0, 1.2, -6), Vector3.new(0, 1.2, 0)))
		handlers.GuardRequest(player, { held = true, facing = FORWARD, clientTime = 1 })
		clock.t += 1
		local results = CombatService.enemyStrike(boarId, NORMAL_RUSH, Vector3.new(0, 1.2, -6), Vector3.new(0, 0, 1))
		expect(#results).toBe(1)
		local open = math.floor(BOAR.attack * NORMAL_RUSH.multiplier - EntityService.get(playerId).defense + 0.5)
		expect(results[1].guarded).toBe(true)
		expect(results[1].damage).toBe(math.floor(open * (1 - Combat.guardReduction) + 0.5))
		expect(results[1].gaugeDamage).toBeCloseTo(NORMAL_RUSH.gaugeDamage * Combat.guardGaugeDrainFraction, 1e-9)
		expect(EntityService.get(playerId).state).toBe("Guard")
		expect(EntityService.get(playerId).gauge).toBe(100 - NORMAL_RUSH.gaugeDamage)
		expect(lastOf("HitConfirmed").guarded).toBe(true)
	end)

	it("a GuardBreak telegraph smashes a held guard: full damage and GuardBroken", function()
		fresh()
		local playerId, player = spawnPlayer()
		local koboldId = spawnKobold(KOBOLD_CFRAME)
		handlers.GuardRequest(player, { held = true, facing = FORWARD, clientTime = 1 })
		clock.t += 1
		local results = strikeOverhead(koboldId)
		local expected = math.floor(KOBOLD.attack * OVERHEAD.multiplier - EntityService.get(playerId).defense + 0.5)
		expect(results[1].damage).toBe(expected)
		expect(results[1].guarded).toBe(false)
		expect(results[1].broke).toBe(true)
		expect(EntityService.get(playerId).state).toBe("GuardBroken")
		expect(EntityService.get(playerId).gauge).toBe(0)
	end)

	it("an Unblockable strike ignores guard and parry alike", function()
		fresh()
		local playerId, player = spawnPlayer()
		local koboldId = spawnKobold(KOBOLD_CFRAME)
		local unblockable = table.clone(OVERHEAD)
		unblockable.telegraph = "Unblockable"
		handlers.GuardRequest(player, { held = true, facing = FORWARD, clientTime = 1 })
		local results = CombatService.enemyStrike(koboldId, unblockable, Vector3.new(0, 2.2, -4), Vector3.new(0, 0, 1))
		expect(results[1].parried).toBe(false)
		expect(results[1].guarded).toBe(false)
		expect(results[1].damage).toBeGreaterThan(0)
		expect(EntityService.get(playerId).gauge).toBe(100) -- it went through the guard, not into it
		expect(EntityService.get(playerId).state).toBe("Stagger")
	end)

	it("a guard does not cover an attack from behind", function()
		fresh()
		local playerId, player = spawnPlayer()
		-- The kobold stands behind the player (+Z) facing it.
		local koboldId = spawnKobold(CFrame.lookAt(Vector3.new(0, 2.2, 4), Vector3.new(0, 2.2, 0)))
		handlers.GuardRequest(player, { held = true, facing = FORWARD, clientTime = 1 })
		local results = CombatService.enemyStrike(koboldId, OVERHEAD, Vector3.new(0, 2.2, 4), Vector3.new(0, 0, -1))
		expect(#results).toBe(1)
		expect(results[1].parried).toBe(false)
		expect(results[1].guarded).toBe(false)
		expect(EntityService.get(playerId).state).toBe("Stagger")
		expect(lastOf("StateChanged").direction).toBe("Back")
	end)

	it("the guard cone follows the server's root, never the GuardRequest's facing", function()
		fresh()
		-- The root faces -Z; the boar rushes from behind (+Z) toward -Z.
		local behind = CFrame.lookAt(Vector3.new(0, 1.2, 6), Vector3.new(0, 1.2, 0))
		local playerId, player = spawnPlayer()
		local boarId = spawnBoar(behind)
		-- The client claims to face the boar; the server never reads that axis.
		handlers.GuardRequest(player, { held = true, facing = { 0, 0, 1 }, clientTime = clock.t })
		expect(#sentOf("ActionRejected")).toBe(0)
		expect(EntityService.get(playerId).state).toBe("Guard")
		clock.t += 1
		local results = CombatService.enemyStrike(boarId, NORMAL_RUSH, Vector3.new(0, 1.2, 6), Vector3.new(0, 0, -1))
		expect(#results).toBe(1)
		local open = math.floor(BOAR.attack * NORMAL_RUSH.multiplier - EntityService.get(playerId).defense + 0.5)
		expect(results[1].guarded).toBe(false)
		expect(results[1].damage).toBe(open)
		expect(EntityService.get(playerId).state).toBe("Stagger")
		expect(lastOf("StateChanged").direction).toBe("Back")

		-- A root turned toward the boar covers it, whatever facing the request reports.
		fresh()
		local turnedId, turned = spawnPlayer(CFrame.lookAt(Vector3.new(0, 3, 0), Vector3.new(0, 3, 1)))
		boarId = spawnBoar(behind)
		handlers.GuardRequest(turned, { held = true, facing = FORWARD, clientTime = clock.t })
		clock.t += 1
		results = CombatService.enemyStrike(boarId, NORMAL_RUSH, Vector3.new(0, 1.2, 6), Vector3.new(0, 0, -1))
		expect(#results).toBe(1)
		expect(results[1].guarded).toBe(true)
		expect(EntityService.get(turnedId).state).toBe("Guard")
	end)

	it("the boar's Unblockable rush is never parried or guarded; the kobold's Overhead still parries", function()
		fresh()
		local playerId, player = spawnPlayer()
		local boarId = spawnBoar(CFrame.lookAt(Vector3.new(0, 1.2, -6), Vector3.new(0, 1.2, 0)))
		expect(CHARGE.telegraph).toBe("Unblockable")
		handlers.GuardRequest(player, { held = true, facing = FORWARD, clientTime = clock.t })
		clock.t += Combat.parryWindow / 2 -- inside the parry window
		local results = CombatService.enemyStrike(boarId, CHARGE, Vector3.new(0, 1.2, -6), Vector3.new(0, 0, 1))
		expect(#results).toBe(1)
		local open = math.floor(BOAR.attack * CHARGE.multiplier - EntityService.get(playerId).defense + 0.5)
		expect(results[1].parried).toBe(false)
		expect(results[1].guarded).toBe(false)
		expect(results[1].damage).toBe(open)
		expect(EntityService.get(playerId).gauge).toBe(100) -- through the guard, not into it
		expect(EntityService.get(playerId).state).toBe("Stagger")
		expect(EntityService.get(boarId).state).toBe("Idle") -- no parry stagger
		expect(#sentOf("SwitchWindow")).toBe(0)

		-- The Phase 0 parry beat is the kobold: its yellow GuardBreak Overhead parries inside the window.
		fresh()
		local guardId, guard = spawnPlayer()
		local koboldId = spawnKobold(KOBOLD_CFRAME)
		expect(OVERHEAD.telegraph).toBe("GuardBreak")
		handlers.GuardRequest(guard, { held = true, facing = FORWARD, clientTime = clock.t })
		clock.t += Combat.parryWindow / 2
		results = strikeOverhead(koboldId)
		expect(#results).toBe(1)
		expect(results[1].parried).toBe(true)
		expect(EntityService.get(guardId).hp).toBe(300)
		expect(EntityService.get(koboldId).state).toBe("Stagger")
	end)

	it("dodge frames make the strike miss entirely", function()
		fresh()
		local playerId, player = spawnPlayer()
		local koboldId = spawnKobold(KOBOLD_CFRAME)
		handlers.DodgeRequest(player, { direction = { 1, 0, 0 }, clientTime = 1 })
		local results = strikeOverhead(koboldId)
		expect(#results).toBe(0)
		expect(#sentOf("HitConfirmed")).toBe(0)
		expect(EntityService.get(playerId).hp).toBe(300)
		-- Past the invulnerability frames (but still dodging) the body is hit.
		advance(Combat.dodgeInvulnerability + 0.01)
		expect(#strikeOverhead(koboldId)).toBe(1)
	end)

	it("a line strike takes the player ahead and misses the one beside", function()
		fresh()
		spawnPlayer(CFrame.new(0, 3, -10)) -- ahead of the boar's charge
		local besideId = spawnPlayer(CFrame.new(6, 3, -6)) -- beside the line
		local boarId = spawnBoar(CFrame.new(0, 1.2, 0))
		local results = CombatService.enemyStrike(boarId, CHARGE, Vector3.new(0, 1.2, 0), Vector3.new(0, 0, -1))
		expect(#results).toBe(1)
		expect(results[1].targetId).never.toBe(besideId)
		expect(EntityService.get(besideId).hp).toBe(300)
	end)

	it("a cone strike respects reach and arc", function()
		fresh()
		spawnPlayer(CFrame.new(0, 3, -4))
		spawnPlayer(CFrame.new(0, 3, -12)) -- past the Overhead's 6-stud reach
		spawnPlayer(CFrame.new(5, 3, 0)) -- 90 degrees off a 60-degree cone
		local koboldId = spawnKobold(CFrame.new(0, 2.2, 0))
		local results = CombatService.enemyStrike(koboldId, OVERHEAD, Vector3.new(0, 2.2, 0), Vector3.new(0, 0, -1))
		expect(#results).toBe(1)
	end)

	it("origin and facing may be plain {x, y, z} tables", function()
		fresh()
		spawnPlayer()
		local koboldId = spawnKobold(KOBOLD_CFRAME)
		local results = CombatService.enemyStrike(koboldId, OVERHEAD, { 0, 2.2, -4 }, { 0, 0, 1 })
		expect(#results).toBe(1)
	end)

	it("a dead or unknown enemy strikes nothing; a dead player is not struck", function()
		fresh()
		local playerId = spawnPlayer()
		local koboldId = spawnKobold(KOBOLD_CFRAME)
		expect(#CombatService.enemyStrike(999, OVERHEAD, Vector3.new(), Vector3.new(0, 0, 1))).toBe(0)
		EntityService.die(playerId)
		expect(#strikeOverhead(koboldId)).toBe(0)
		EntityService.die(koboldId)
		expect(#strikeOverhead(koboldId)).toBe(0)
	end)

	it("a killing strike reports Kill and the player dies", function()
		fresh()
		local playerId = spawnPlayer()
		local koboldId = spawnKobold(KOBOLD_CFRAME)
		EntityService.get(playerId).hp = 1
		local results = strikeOverhead(koboldId)
		expect(results[1].killed).toBe(true)
		expect(results[1].hitStop).toBe("Kill")
		expect(EntityService.get(playerId).state).toBe("Dead")
		expect(lastOf("EntityDied").entityId).toBe(playerId)
		expect(lastOf("EntityDied").byPlayer).toBe(false)
	end)
end)
