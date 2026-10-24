--!strict
--[[
	CollisionGroups (D-167) under Lune: a PhysicsService stand-in records what register asks for, an
	overlap stand-in answers clear's query. A rushing body passes through players and enemies and
	runs on the world; every other pair keeps colliding; a stopped rush rejoins only when clear.
]]

local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local AI = Harness.load("src/shared/data/ai")

local GROUPS = AI.collision

-- A PhysicsService stand-in: registered names and the collidable table (true unless set).
local function physics()
	local fake: any = { registered = {}, registerCalls = 0, apart = {} }
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
	it("registers the three groups; a rushing body passes players and enemies, every other pair collides", function()
		local fake = physics()
		expect(CollisionGroups.register(fake)).toBe(true)
		for _, name in CollisionGroups.names() do
			expect(fake.registered[name]).toBe(true)
		end
		expect(fake.collides(GROUPS.rushing, GROUPS.players)).toBe(false)
		expect(fake.collides(GROUPS.rushing, GROUPS.enemies)).toBe(false)
		expect(fake.collides(GROUPS.rushing, GROUPS.rushing)).toBe(false)
		expect(fake.collides(GROUPS.rushing, "Default")).toBe(true) -- it still runs on the world
		expect(fake.collides(GROUPS.players, GROUPS.enemies)).toBe(true)
		expect(fake.collides(GROUPS.players, GROUPS.players)).toBe(true)
		expect(fake.collides(GROUPS.enemies, GROUPS.enemies)).toBe(true)
		-- A second call registers nothing twice.
		expect(CollisionGroups.register(fake)).toBe(true)
		expect(fake.registerCalls).toBe(3)
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
			CollisionGroups.assign(enemy, GROUPS.enemies)
			expect(root.CollisionGroup).toBe(GROUPS.enemies)
			expect(snout.CollisionGroup).toBe(GROUPS.enemies)
			expect(deep.CollisionGroup).toBe(GROUPS.enemies)

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
end)
