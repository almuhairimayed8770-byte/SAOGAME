--!strict
--[[
	AntiCheatService under Lune: the real EntityService (fake clock, net, tags) as the registry, a
	fake CombatService that says which Art runs, fakes that record attributes, kicks and system
	lines. Watching through Registered, honest movement, the Art / Dodge allowances, the carried
	state across a sample, teleports, the shadow flag, the kick (never on one anomaly), Net abuse,
	the sliding window, death and respawn resets, and the sample clock.
]]

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

local AntiCheatService = Harness.load("src/server/services/AntiCheatService")
local EntityService = Harness.load("src/server/services/EntityService")
local Rules = Harness.load("src/server/anticheat/Rules")
local Signal = Harness.load("src/shared/util/Signal")
local Combat = Harness.load("src/shared/data/combat")
local World = Harness.load("src/shared/data/world")
local Arts = Harness.load("src/shared/data/arts")
local Playground = Harness.load("src/shared/data/playground")
local CollectionService = Harness.game():GetService("CollectionService")

local INTERVAL = Combat.anticheatSampleInterval
-- The sprint allowance over `seconds`: the cap over the interval plus the section 17 lag budget.
local function allowance(seconds: number): number
	return Combat.maxSpeedStudsPerSecond * (seconds + Combat.lagAllowance)
end
local SPRINT = allowance(INTERVAL)
local TELEPORT = 200

-- ------------------------------------------------------------------------------------------
-- Fixtures
-- ------------------------------------------------------------------------------------------

local clock = { t = 1000 }
local currentArt: any = nil
local attributes: { [any]: { [string]: any } } = {}
local kicks: { any } = {}
local lines: { any } = {}
local logs: { string } = {}
local abuse: any = nil
local removing: any = nil

local function fresh()
	AntiCheatService.reset()
	EntityService.reset()
	clock.t = 1000
	currentArt = nil
	attributes = {}
	kicks = {}
	lines = {}
	logs = {}
	abuse = Signal.new()
	removing = Signal.new()
	EntityService.bind({
		now = function()
			return clock.t
		end,
		fireAll = function() end,
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
	AntiCheatService.bind({
		now = function()
			return clock.t
		end,
		entities = EntityService,
		combat = {
			currentArt = function(_id)
				return currentArt
			end,
		},
		net = {
			abuse = abuse,
			fire = function(name, player, payload)
				table.insert(lines, { name = name, player = player, payload = payload })
			end,
		},
		players = { PlayerRemoving = removing },
		heartbeat = nil,
		setAttribute = function(player, name, value)
			attributes[player] = attributes[player] or {}
			attributes[player][name] = value
		end,
		kick = function(player, text)
			table.insert(kicks, { player = player, text = text })
		end,
		log = function(message)
			table.insert(logs, message)
		end,
	})
end

local function character(name: string?): (any, any)
	local model = Instance.new("Model")
	model.Name = name or "Tester"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	local parent = Instance.new("Folder")
	model.Parent = parent
	return model, root
end

local playerCount = 0
local function player(): any
	playerCount += 1
	return { Name = "Tester" .. playerCount, DisplayName = "Tester", UserId = 1000 + playerCount }
end

-- A registered, watched player standing at the origin with a first sample taken.
local function fighter(): (any, number, any)
	local who = player()
	local model, root = character(who.Name)
	local id = EntityService.registerPlayer(who, model, Playground.loadout)
	task.wait() -- Registered fires on its own thread
	AntiCheatService.sample(who, INTERVAL) -- the first sample only records the position
	return who, id, root
end

-- Moves the root `studs` along +X and samples once over `interval` seconds.
local function move(who: any, root: any, studs: number, interval: number?): any
	local position = root.CFrame.Position
	root.CFrame = CFrame.new(position.X + studs, position.Y, position.Z)
	clock.t += interval or INTERVAL
	return AntiCheatService.sample(who, interval or INTERVAL)
end

-- ------------------------------------------------------------------------------------------
-- Watching
-- ------------------------------------------------------------------------------------------

describe("AntiCheatService watching", function()
	it("watches a player when EntityService registers their character and forgets them on PlayerRemoving", function()
		fresh()
		local who = player()
		local model = character(who.Name)
		expect(AntiCheatService.isWatched(who)).toBe(false)
		EntityService.registerPlayer(who, model, Playground.loadout)
		task.wait()
		expect(AntiCheatService.isWatched(who)).toBe(true)
		expect(AntiCheatService.stats().watched).toBe(1)
		removing:Fire(who)
		task.wait()
		expect(AntiCheatService.isWatched(who)).toBe(false)
		expect(AntiCheatService.stats().watched).toBe(0)
	end)

	it("does not watch enemies, and watching twice counts once", function()
		fresh()
		local who = player()
		AntiCheatService.watch(who)
		AntiCheatService.watch(who)
		expect(AntiCheatService.stats().watched).toBe(1)
		expect(AntiCheatService.flagsOf(who)).toEqual({})
		expect(AntiCheatService.flagsOf(player())).toEqual({})
		expect(AntiCheatService.isShadowed(who)).toBe(false)
		expect(AntiCheatService.isKicked(who)).toBe(false)
	end)

	it("start() picks up players already registered", function()
		fresh()
		local who = player()
		local model = character(who.Name)
		AntiCheatService.reset()
		EntityService.registerPlayer(who, model, Playground.loadout)
		task.wait()
		expect(AntiCheatService.isWatched(who)).toBe(false)
		fresh()
		EntityService.registerPlayer(who, model, Playground.loadout)
		task.wait()
		AntiCheatService.reset()
		-- No bind after the reset: start() has to rebuild its view from EntityService.players().
		AntiCheatService.bind({
			now = function()
				return clock.t
			end,
			entities = EntityService,
			setAttribute = function() end,
			kick = function() end,
		})
		AntiCheatService.start()
		expect(AntiCheatService.isWatched(who)).toBe(true)
		AntiCheatService.start() -- idempotent
		expect(AntiCheatService.stats().watched).toBe(1)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Movement
-- ------------------------------------------------------------------------------------------

describe("AntiCheatService movement samples", function()
	it("an honest sprint inside the cap is never flagged", function()
		fresh()
		local who, _, root = fighter()
		for _ = 1, 20 do
			local verdict = move(who, root, SPRINT - 0.1)
			expect(verdict.kind).toBe("ok")
		end
		expect(AntiCheatService.flagsOf(who)).toEqual({})
		expect(AntiCheatService.stats().samples).toBe(20)
		expect(AntiCheatService.stats().flags).toBe(0)
	end)

	it("falling and jumping are not judged: a vertical drop of any size is fine", function()
		fresh()
		local who, _, root = fighter()
		root.CFrame = CFrame.new(0, -500, 0)
		clock.t += INTERVAL
		expect(AntiCheatService.sample(who, INTERVAL).kind).toBe("ok")
	end)

	it("over the cap is an over-speed anomaly, logged with the UserId and the reason, and fires Flagged", function()
		fresh()
		local who, _, root = fighter()
		local flagged: { any } = {}
		AntiCheatService.Flagged:Connect(function(flaggedPlayer, reason, weight)
			table.insert(flagged, { player = flaggedPlayer, reason = reason, weight = weight })
		end)
		local verdict = move(who, root, SPRINT + 2)
		task.wait()
		expect(verdict.kind).toBe("speed")
		expect(#flagged).toBe(1)
		expect(flagged[1].player).toBe(who)
		expect(flagged[1].weight).toBe(World.anticheat.speedWeight)
		expect(flagged[1].reason:find(World.anticheat.reasons.speed, 1, true)).toBe(1)
		expect(#logs).toBe(1)
		expect(logs[1]:find("userId=" .. who.UserId, 1, true)).toBeTruthy()
		expect(logs[1]:find(World.anticheat.reasons.speed, 1, true)).toBeTruthy()
		local stats = AntiCheatService.stats()
		expect(stats.speed).toBe(1)
		expect(stats.flags).toBe(1)
		expect(#AntiCheatService.flagsOf(who)).toBe(1)
		-- One anomaly is neither a shadow nor a kick.
		expect(attributes[who]).toBe(nil)
		expect(#kicks).toBe(0)
	end)

	it("mid-Art the running Art's rootMotion plus the slack is allowed; a basic swing gets only the slack", function()
		fresh()
		local who, id, root = fighter()
		local leap = Arts.byId("OneHandedSword.SonicLeap")
		currentArt = leap
		EntityService.setState(id, "Art", 2)
		local allowed = SPRINT + leap.rootMotion + Combat.rootMotionSlack
		expect(move(who, root, allowed - 0.1).kind).toBe("ok")
		expect(move(who, root, allowed + 0.5).kind).toBe("speed")
		-- A basic swing: CombatService reports no Art while the state is Art.
		currentArt = nil
		expect(move(who, root, SPRINT + Combat.rootMotionSlack - 0.1).kind).toBe("ok")
		expect(move(who, root, SPRINT + Combat.rootMotionSlack + 0.5).kind).toBe("speed")
	end)

	it("without CombatService the weapon category's largest Art is assumed", function()
		fresh()
		local who, id, root = fighter()
		AntiCheatService.bind({
			now = function()
				return clock.t
			end,
			entities = EntityService,
			combat = nil,
			setAttribute = function() end,
			kick = function() end,
		})
		AntiCheatService.watch(who)
		AntiCheatService.sample(who, INTERVAL)
		EntityService.setState(id, "Art", 2)
		local largest = Rules.maxRootMotion("OneHandedSword")
		expect(move(who, root, SPRINT + largest + Combat.rootMotionSlack - 0.1).kind).toBe("ok")
		expect(move(who, root, SPRINT + largest + Combat.rootMotionSlack + 0.5).kind).toBe("speed")
	end)

	it(
		"the state of the previous sample covers the interval too: an Art ending between samples is not punished",
		function()
			fresh()
			local who, id, root = fighter()
			local leap = Arts.byId("OneHandedSword.SonicLeap")
			currentArt = leap
			EntityService.setState(id, "Art", 2)
			expect(move(who, root, 1).kind).toBe("ok") -- the Art sample: the state is now carried
			currentArt = nil
			EntityService.setState(id, "Idle")
			local carried = SPRINT + leap.rootMotion + Combat.rootMotionSlack
			expect(move(who, root, carried - 0.1).kind).toBe("ok")
			-- Two samples later the carry is gone.
			expect(move(who, root, carried - 0.1).kind).toBe("speed")
		end
	)

	it("mid-Dodge the dodge distance is added", function()
		fresh()
		local who, id, root = fighter()
		EntityService.setState(id, "Dodge", 1)
		expect(move(who, root, SPRINT + Combat.dodgeDistance - 0.1).kind).toBe("ok")
		EntityService.setState(id, "Idle")
		move(who, root, 0) -- clear the carried Dodge
		expect(move(who, root, SPRINT + Combat.dodgeDistance - 0.1).kind).toBe("speed")
	end)

	it("a longer interval (lag spike) scales the allowance", function()
		fresh()
		local who, _, root = fighter()
		expect(move(who, root, allowance(2) - 0.1, 2).kind).toBe("ok")
		-- A hair over the cap after a long spike: flagged with the smallest weight, whatever the kind.
		local verdict = move(who, root, allowance(2) + 0.5, 2)
		expect(verdict.kind == "speed" or verdict.kind == "teleport").toBe(true)
		expect(verdict.weight).toBe(1)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Teleports, the shadow flag and the kick
-- ------------------------------------------------------------------------------------------

describe("AntiCheatService teleports and the kick", function()
	it("one teleport is a weighted anomaly that never kicks on its own, however far", function()
		fresh()
		local who, _, root = fighter()
		local verdict = move(who, root, 1e6)
		task.wait()
		expect(verdict.kind).toBe("teleport")
		expect(verdict.weight).toBe(math.floor(Combat.anomalyKickThreshold / 2))
		expect(#kicks).toBe(0)
		expect(AntiCheatService.isKicked(who)).toBe(false)
		expect(AntiCheatService.stats().teleport).toBe(1)
		-- Half the threshold in one anomaly: shadowed, but still here.
		expect(AntiCheatService.isShadowed(who)).toBe(true)
		expect(attributes[who][World.anticheat.shadowAttribute]).toBe(true)
	end)

	it("five 200-stud teleports inside a second: shadowed first, then a system line and the kick", function()
		fresh()
		local who, _, root = fighter()
		local shadowed: { any } = {}
		local kicked: { any } = {}
		AntiCheatService.Shadowed:Connect(function(shadowedPlayer)
			table.insert(shadowed, shadowedPlayer)
		end)
		AntiCheatService.Kicked:Connect(function(kickedPlayer, reason)
			table.insert(kicked, { player = kickedPlayer, reason = reason })
		end)
		local kickedAfter: number? = nil
		for index = 1, 5 do
			local verdict = move(who, root, TELEPORT, 0.2)
			if verdict ~= nil then
				expect(verdict.kind).toBe("teleport")
				expect(verdict.weight).toBe(5)
			end
			if kickedAfter == nil and AntiCheatService.isKicked(who) then
				kickedAfter = index
			end
		end
		task.wait()
		expect(kickedAfter).toBeTruthy()
		expect(kickedAfter).toBeGreaterThanOrEqual(World.anticheat.minimumAnomalies)
		expect(kickedAfter).toBeLessThanOrEqual(5)
		expect(#kicks).toBe(1)
		expect(kicks[1].player).toBe(who)
		expect(kicks[1].text).toBe(World.anticheat.kickText)
		expect(#lines).toBe(1)
		expect(lines[1].name).toBe("SystemLine")
		expect(lines[1].player).toBe(who)
		expect(lines[1].payload.text).toBe(World.anticheat.kickText)
		expect(lines[1].payload.token).toBe(World.anticheat.lineToken)
		expect(#shadowed).toBe(1)
		expect(#kicked).toBe(1)
		expect(kicked[1].reason:find(World.anticheat.reasons.teleport, 1, true)).toBe(1)
		expect(attributes[who][World.anticheat.shadowAttribute]).toBe(true)
		local stats = AntiCheatService.stats()
		expect(stats.kicked).toBe(1)
		expect(stats.shadowed).toBe(1)
		expect(stats.teleport).toBe(kickedAfter)
		-- A kicked player is not sampled or kicked again.
		expect(move(who, root, TELEPORT)).toBe(nil)
		AntiCheatService.flag(who, "again", 1)
		expect(#kicks).toBe(1)
		expect(AntiCheatService.stats().kicked).toBe(1)
	end)

	it("the shadow flag comes at half the threshold of plain over-speed samples and is set once", function()
		fresh()
		local who, _, root = fighter()
		local half = math.ceil(Combat.anomalyKickThreshold / 2 / World.anticheat.speedWeight)
		for index = 1, half do
			move(who, root, SPRINT + 1)
			expect(AntiCheatService.isShadowed(who)).toBe(index >= half)
		end
		move(who, root, SPRINT + 1)
		expect(AntiCheatService.stats().shadowed).toBe(1)
		expect(#kicks).toBe(0)
	end)

	it("the threshold of over-speed samples inside the window is a kick; spread past the window it is not", function()
		fresh()
		local who, _, root = fighter()
		for _ = 1, Combat.anomalyKickThreshold - 1 do
			move(who, root, SPRINT + 1)
		end
		expect(#kicks).toBe(0)
		move(who, root, SPRINT + 1)
		expect(#kicks).toBe(1)

		fresh()
		local slow, _, slowRoot = fighter()
		local gap = Combat.anomalyWindow / (Combat.anomalyKickThreshold - 2)
		for _ = 1, Combat.anomalyKickThreshold * 2 do
			move(slow, slowRoot, 0)
			clock.t += gap
			move(slow, slowRoot, allowance(gap) + 1, gap)
		end
		expect(#kicks).toBe(0)
		expect(#AntiCheatService.flagsOf(slow)).toBeLessThan(Combat.anomalyKickThreshold)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Net abuse
-- ------------------------------------------------------------------------------------------

describe("AntiCheatService Net abuse", function()
	it("each abuse report is one anomaly against the player, watched or not", function()
		fresh()
		local who = player()
		abuse:Fire(who, "ArtRequest", "rate")
		task.wait()
		expect(AntiCheatService.isWatched(who)).toBe(true)
		local flags = AntiCheatService.flagsOf(who)
		expect(#flags).toBe(1)
		expect(flags[1].weight).toBe(World.anticheat.abuseWeight)
		expect(flags[1].reason:find(World.anticheat.reasons.abuse, 1, true)).toBe(1)
		expect(flags[1].reason:find("ArtRequest", 1, true)).toBeTruthy()
		expect(AntiCheatService.stats().abuse).toBe(1)
	end)

	it("a flood of abuse reports reaches the kick, with the system line first", function()
		fresh()
		local who = player()
		for _ = 1, Combat.anomalyKickThreshold do
			AntiCheatService.reportAbuse(who, "GuardRequest", "schema: bad payload")
		end
		expect(#kicks).toBe(1)
		expect(#lines).toBe(1)
		expect(AntiCheatService.isKicked(who)).toBe(true)
	end)
end)

-- ------------------------------------------------------------------------------------------
-- Death, respawn and the sample clock
-- ------------------------------------------------------------------------------------------

describe("AntiCheatService resets and the clock", function()
	it("a dead fighter is not judged and the respawn jump after death is not a teleport", function()
		fresh()
		local who, id, root = fighter()
		EntityService.die(id, nil)
		expect(move(who, root, TELEPORT)).toBe(nil)
		-- A new character far away: the first sample only records.
		local model, newRoot = character(who.Name)
		newRoot.CFrame = CFrame.new(TELEPORT * 2, 3, 0)
		EntityService.registerPlayer(who, model, Playground.loadout)
		task.wait()
		clock.t += INTERVAL
		expect(AntiCheatService.sample(who, INTERVAL)).toBe(nil)
		expect(move(who, newRoot, 1).kind).toBe("ok")
		expect(AntiCheatService.stats().flags).toBe(0)
	end)

	it("an unregistered player keeps their flags but loses the sample", function()
		fresh()
		local who, id, root = fighter()
		move(who, root, SPRINT + 1)
		expect(#AntiCheatService.flagsOf(who)).toBe(1)
		EntityService.unregister(id)
		task.wait()
		expect(AntiCheatService.isWatched(who)).toBe(true)
		expect(#AntiCheatService.flagsOf(who)).toBe(1)
		clock.t += INTERVAL
		expect(AntiCheatService.sample(who, INTERVAL)).toBe(nil)
	end)

	it("an unknown player samples to nothing", function()
		fresh()
		expect(AntiCheatService.sample(player(), INTERVAL)).toBe(nil)
	end)

	it(
		"a character that lost its root (reset / removed while registered) resets the sample instead of teleporting to the origin",
		function()
			fresh()
			-- A fighter standing far from the origin, so a sample that read EntityService's zero
			-- position for a rootless model would be a teleport of several weights.
			local function farFighter(x: number, z: number): (any, number, any)
				local who = player()
				local model, root = character(who.Name)
				root.CFrame = CFrame.new(x, 3, z)
				local id = EntityService.registerPlayer(who, model, Playground.loadout)
				task.wait()
				AntiCheatService.sample(who, INTERVAL) -- records the far position
				return who, id, root
			end
			local who, id, root = farFighter(TELEPORT, TELEPORT)
			expect(move(who, root, 1).kind).toBe("ok")
			local model = EntityService.get(id).model
			root:Destroy()
			expect(model.PrimaryPart == nil or (model.PrimaryPart :: any).Parent == nil).toBe(true)
			clock.t += INTERVAL
			expect(AntiCheatService.sample(who, INTERVAL)).toBe(nil)
			expect(AntiCheatService.stats().flags).toBe(0)
			-- The whole model gone (the engine removed the character): still nothing to judge.
			local other, otherId, otherRoot = farFighter(-TELEPORT, 0)
			expect(move(other, otherRoot, 1).kind).toBe("ok")
			EntityService.get(otherId).model.Parent = nil
			clock.t += INTERVAL
			expect(AntiCheatService.sample(other, INTERVAL)).toBe(nil)
			expect(AntiCheatService.stats().flags).toBe(0)
			expect(AntiCheatService.isShadowed(who)).toBe(false)
			expect(AntiCheatService.isShadowed(other)).toBe(false)
			-- A fresh character far from the last one: the first sample only records, as after a respawn.
			local again, againRoot = character(who.Name)
			againRoot.CFrame = CFrame.new(0, 3, -TELEPORT)
			EntityService.registerPlayer(who, again, Playground.loadout)
			task.wait()
			clock.t += INTERVAL
			expect(AntiCheatService.sample(who, INTERVAL)).toBe(nil)
			expect(move(who, againRoot, 1).kind).toBe("ok")
			expect(AntiCheatService.stats().flags).toBe(0)
		end
	)

	it("tick samples every anticheatSampleInterval with the real elapsed time as the interval", function()
		fresh()
		local _, _, root = fighter()
		local position = root.CFrame.Position
		-- Move the whole sprint allowance for 0.3 s before the sample lands at 0.3 s (three 0.1 s ticks).
		root.CFrame = CFrame.new(position.X + Combat.maxSpeedStudsPerSecond * 0.3 - 0.1, position.Y, position.Z)
		local step = INTERVAL / 2.5
		for _ = 1, 2 do
			clock.t += step
			AntiCheatService.tick(step)
		end
		expect(AntiCheatService.stats().samples).toBe(0)
		clock.t += step
		AntiCheatService.tick(step)
		expect(AntiCheatService.stats().samples).toBe(1)
		expect(AntiCheatService.stats().flags).toBe(0)
		-- The next sample covers a single interval: a step past its allowance (cap plus lag budget) is over.
		local last = root.CFrame.Position
		root.CFrame = CFrame.new(last.X + allowance(INTERVAL) + 1, last.Y, last.Z)
		clock.t += INTERVAL
		AntiCheatService.tick(INTERVAL)
		expect(AntiCheatService.stats().samples).toBe(2)
		expect(AntiCheatService.stats().flags).toBe(1)
	end)

	it("reset forgets everything", function()
		fresh()
		local who, _, root = fighter()
		move(who, root, SPRINT + 1)
		AntiCheatService.reset()
		expect(AntiCheatService.isWatched(who)).toBe(false)
		local stats = AntiCheatService.stats()
		expect(stats.watched).toBe(0)
		expect(stats.flags).toBe(0)
		expect(stats.samples).toBe(0)
	end)
end)
