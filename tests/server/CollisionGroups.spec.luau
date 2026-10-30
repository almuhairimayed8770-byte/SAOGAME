--!strict
--[[
	CollisionGroups (D-167) under Lune: a PhysicsService stand-in records what register asks for, an
	overlap stand-in answers clear's query. A rushing body passes through players and enemies and
	runs on the world; a player bumps into an enemy's blocker, never its root (D-198), and so do
	other enemies' roots and blockers (D-281), never the world or a rush; every other pair keeps
	colliding; a stopped rush rejoins only when clear.
]]

local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local AI = Harness.load("src/shared/data/ai")

local GROUPS = AI.collision

-- A PhysicsService stand-in: registered names and the collidable table (true unless set).
local function physics()
	local fake: any = { registered = { Default = true }, registerCalls = 0, apart = {} }
	function fake.IsCollisionGroupRegistered(_self, name: string): boolean
		return fake.registered[name] == true
	end
	function fake.RegisterCollisionGroup(_self, name: string)
		fake.registerCalls += 1
		fake.registered[name] = true
	end
	function fake.CollisionGroupSetCollidable(_self, first: string, second: string, collidable: boolean)
		assert(fake.registered[first] and fake.registered[second], "a pair of unregistered groups")
		local key = if first < second then first .. "|" .. second else second .. "|" .. first
		fake.apart[key] = not collidable
	end
	function fake.collides(first: string, second: string): boolean
		local key = if first < second then first .. "|" .. second else second .. "|" .. first
		return fake.apart[key] ~= true
	end
	return fake
end

local function part(name: string, parent: Instance?, group: string?, canCollide: boolean?): Part
	local created = Instance.new("Part")
	created.Name = name
	created.CanCollide = if canCollide == nil then true else canCollide
	if group ~= nil then
		created.CollisionGroup = group
	end
	created.Parent = parent
	return created
end

describe("CollisionGroups (D-167)", function()
	it("registers the four groups; a rushing body passes players and enemies; blockers meet fighters", function()
		local fake = physics()
		expect(CollisionGroups.register(fake)).toBe(true)
		expect(#CollisionGroups.names()).toBe(4)
		for _, name in CollisionGroups.names() do
			expect(fake.registered[name]).toBe(true)
		end
		expect(fake.collides(GROUPS.rushing, GROUPS.players)).toBe(false)
		expect(fake.collides(GROUPS.rushing, GROUPS.enemies)).toBe(false)
		expect(fake.collides(GROUPS.rushing, GROUPS.rushing)).toBe(false)
		expect(fake.collides(GROUPS.rushing, "Default")).toBe(true) -- it still runs on the world
		expect(fake.collides(GROUPS.players, GROUPS.players)).toBe(true)
		expect(fake.collides(GROUPS.enemies, GROUPS.enemies)).toBe(true)
		expect(fake.collides(GROUPS.enemies, "Default")).toBe(true)
		-- D-198: a player meets an enemy's blocker, not its root. D-281: another enemy's root and its
		-- blocker meet it too, so no enemy stands inside another; the world and a rush never do.
		expect(fake.collides(GROUPS.players, GROUPS.enemies)).toBe(false)
		expect(fake.collides(GROUPS.blockers, GROUPS.players)).toBe(true)
		expect(fake.collides(GROUPS.blockers, "Default")).toBe(false)
		expect(fake.collides(GROUPS.blockers, GROUPS.enemies)).toBe(true)
		expect(fake.collides(GROUPS.blockers, GROUPS.rushing)).toBe(false)
		expect(fake.collides(GROUPS.blockers, GROUPS.blockers)).toBe(true)
		-- A second call registers nothing twice.
		expect(CollisionGroups.register(fake)).toBe(true)
		expect(fake.registerCalls).toBe(4)
	end)

	it("a refused registration is reported, never thrown", function()
		local broken = {
			IsCollisionGroupRegistered = function()
				error("no physics here")
			end,
		}
		expect(CollisionGroups.register(broken :: any)).toBe(false)
	end)

	it(
		"assign puts every part of a model in the group; joinPlayers does it for a character and its later parts",
		function()
			local enemy = Instance.new("Model")
			local root = part("HumanoidRootPart", enemy)
			local snout = part("Snout", enemy, nil, false)
			local folder = Instance.new("Folder")
			folder.Parent = enemy
			local deep = part("Deep", folder)
			local blocker = part("Blocker", enemy, GROUPS.blockers, false)
			CollisionGroups.assign(enemy, GROUPS.enemies)
			expect(root.CollisionGroup).toBe(GROUPS.enemies)
			expect(snout.CollisionGroup).toBe(GROUPS.enemies)
			expect(deep.CollisionGroup).toBe(GROUPS.enemies)
			-- The blocker stays a blocker, and collides only while its enemy is solid (D-198).
			expect(blocker.CollisionGroup).toBe(GROUPS.blockers)
			expect(blocker.CanCollide).toBe(true)
			CollisionGroups.assign(enemy, GROUPS.rushing)
			expect(root.CollisionGroup).toBe(GROUPS.rushing)
			expect(blocker.CollisionGroup).toBe(GROUPS.blockers)
			expect(blocker.CanCollide).toBe(false)
			expect(root.CanCollide).toBe(true)
			CollisionGroups.assign(enemy, GROUPS.enemies)
			expect(blocker.CanCollide).toBe(true)
			expect(CollisionGroups.isBlocker(blocker)).toBe(true)
			expect(CollisionGroups.isBlocker(root)).toBe(false)

			local character = Instance.new("Model")
			local torso = part("UpperTorso", character)
			CollisionGroups.joinPlayers(character)
			expect(torso.CollisionGroup).toBe(GROUPS.players)
			local sword = part("Handle", character)
			CollisionGroups.playerPartAdded(sword)
			expect(sword.CollisionGroup).toBe(GROUPS.players)
			CollisionGroups.playerPartAdded(Instance.new("Attachment")) -- not a part: ignored
		end
	)

	it("clear: a root overlapping a colliding player or enemy part is not clear; the world and props are", function()
		local boar = Instance.new("Model")
		boar.PrimaryPart = part("HumanoidRootPart", boar, GROUPS.rushing)
		local found: { BasePart } = {}
		local asked: any = nil
		local function overlap(root: BasePart, exclude: Instance): { BasePart }
			asked = { root = root, exclude = exclude }
			return found
		end
		expect(CollisionGroups.clear(boar, overlap)).toBe(true)
		expect(asked.root).toBe(boar.PrimaryPart)
		expect(asked.exclude).toBe(boar)
		found = { part("Floor", nil, "Default"), part("Sword", nil, GROUPS.players, false) }
		expect(CollisionGroups.clear(boar, overlap)).toBe(true)
		found = { part("Floor", nil, "Default"), part("UpperTorso", nil, GROUPS.players) }
		expect(CollisionGroups.clear(boar, overlap)).toBe(false)
		found = { part("HumanoidRootPart", nil, GROUPS.enemies) }
		expect(CollisionGroups.clear(boar, overlap)).toBe(false)
		found = { part("HumanoidRootPart", nil, GROUPS.rushing) } -- another rush passes through it anyway
		expect(CollisionGroups.clear(boar, overlap)).toBe(true)
		expect(CollisionGroups.clear(Instance.new("Model"), overlap)).toBe(true)
	end)

	it("clear: a blocker overlapping a player is not clear; other enemies are EnemyService's (D-198, D-281)", function()
		local boar = Instance.new("Model")
		local root = part("HumanoidRootPart", boar, GROUPS.rushing)
		boar.PrimaryPart = root
		local blocker = part("Blocker", boar, GROUPS.blockers, false)
		local byProbe: { [BasePart]: { BasePart } } = {}
		local asked: { BasePart } = {}
		local function overlap(probe: BasePart, _exclude: Instance): { BasePart }
			table.insert(asked, probe)
			return byProbe[probe] or {}
		end
		expect(CollisionGroups.clear(boar, overlap)).toBe(true)
		expect(table.find(asked, root)).never.toBeNil()
		expect(table.find(asked, blocker)).never.toBeNil()
		-- A player over the blocker but clear of the root (a head above the root's top).
		byProbe[blocker] = { part("Head", nil, GROUPS.players) }
		expect(CollisionGroups.clear(boar, overlap)).toBe(false)
		-- Another enemy's root or blocker inside this blocker is left to EnemyService.blockerClear
		-- (D-281), which judges blocker against blocker on the parts' own boxes: the engine's query
		-- never sees a blocker (CanQuery off), and a blocker covers its body's root.
		byProbe[blocker] = { part("HumanoidRootPart", nil, GROUPS.enemies), part("Blocker", nil, GROUPS.blockers) }
		expect(CollisionGroups.clear(boar, overlap)).toBe(true)
	end)
end)
