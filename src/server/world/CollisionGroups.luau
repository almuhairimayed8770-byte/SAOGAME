--!strict
--[[
	CollisionGroups (D-167): the server's collision groups for fighters, from ai.luau `collision`.

	Three groups besides the engine's Default (the world): player characters, enemies, and an enemy
	that is rushing. Every pair collides except the ones ai.luau lists in `apart`: a rushing body
	passes through players and through other enemies (it still runs on the world), so a Charger's
	rush never jams on the player it hits or on a packmate. Players collide with players and with
	walking enemies, and enemies with each other, as before.

	What a player bumps into on a standing enemy is its blocker (D-198): one upright, invisible box
	over the root's footprint from the floor up past a player's head (RigBuilder.addBlocker), in the
	blockers group, which collides with players only. The root (a box floating at HipHeight, its top
	edge at a player's chest) no longer collides with players: walking into that edge bobbed a player
	up and slid them off sideways, while a face from the floor up past the head is a flat stop. The
	blocker never collides with the world, so the body moves on the floor and stops at walls as
	before, and a query (run as Default) never sees it. assign leaves it in its group and switches it
	on only with the enemies group, so a rush still passes through players (D-167).

	The server registers the groups once (register, from Main and EnemyService.start, either first);
	the engine replicates the group table and every part's CollisionGroup to the clients, so a
	client-simulated character passes a rushing boar on its own screen too. CharacterReady puts
	each character in the players group once it is built (joinPlayers, which also catches parts
	added later: accessories, the weapon), EnemyService puts each enemy in the enemies group at spawn
	and switches it to rushing for its rush. A stopped rush rejoins the enemies group only once its
	root has overlapped no player and no enemy (clear) for ai.collision.rejoinClearSeconds in a row
	(EnemyService, D-190), so the engine never has to push two bodies apart, not even on a client
	that still draws the body where it was; that push is what lifted one boar onto another, and a
	player onto a boar's back.

	Queries are unaffected: a RaycastParams / OverlapParams query runs as the Default group, which
	collides with the three fighter groups, so blades, spherecasts and overlap tests see every
	fighter as before, and not with the blockers, so none of them sees a blocker (HitSweep and
	BladeContact follow the same rule in their own tests).

	The engine calls are injectable (a PhysicsService stand-in for register, an overlap query for
	clear), so the rules run under Lune.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AI = require(ReplicatedStorage.Shared.data.ai)

-- The PhysicsService calls register makes (a stand-in in tests).
export type Physics = {
	IsCollisionGroupRegistered: (self: any, name: string) -> boolean,
	RegisterCollisionGroup: (self: any, name: string) -> (),
	CollisionGroupSetCollidable: (self: any, first: string, second: string, collidable: boolean) -> (),
}

-- The parts overlapping a root, excluding its own model (workspace:GetPartsInPart by default).
export type Overlap = (root: BasePart, exclude: Instance) -> { BasePart }

export type Connection = { Disconnect: (self: any) -> () }

local CollisionGroups = {}

local registered = false

--- The four group names, players first.
function CollisionGroups.names(): { string }
	local groups = AI.collision
	return { groups.players, groups.enemies, groups.rushing, groups.blockers }
end

--- Whether a part is an enemy's blocker (D-198): it lives in the blockers group from the moment it
--- is made, and assign never moves it out.
function CollisionGroups.isBlocker(part: BasePart): boolean
	return part.CollisionGroup == AI.collision.blockers
end

--- Registers the groups and makes the `apart` pairs pass through each other. Safe to call again:
--- a group already registered is left alone. With no `physics` it uses PhysicsService and runs
--- once per server. Returns false (with a warning) when the engine refused.
function CollisionGroups.register(physics: Physics?): boolean
	if physics == nil and registered then
		return true
	end
	local ok, err = pcall(function()
		local service: Physics = physics or (game:GetService("PhysicsService") :: any)
		for _, name in CollisionGroups.names() do
			if not service:IsCollisionGroupRegistered(name) then
				service:RegisterCollisionGroup(name)
			end
		end
		for _, pair in AI.collision.apart do
			service:CollisionGroupSetCollidable(pair[1], pair[2], false)
		end
	end)
	if not ok then
		warn(("[CollisionGroups] registering the fighter groups failed: %s"):format(tostring(err)))
		return false
	end
	if physics == nil then
		registered = true
	end
	return true
end

-- One part's share of assign: a blocker stays a blocker and collides only while its enemy is in
-- the enemies group (solid); every other part joins the group.
local function assignPart(part: BasePart, group: string)
	if CollisionGroups.isBlocker(part) then
		part.CanCollide = group == AI.collision.enemies
	else
		part.CollisionGroup = group
	end
end

--- Puts every BasePart of a model (or the part itself) in a group; an enemy's blocker stays in the
--- blockers group and is switched on with the enemies group only (D-198).
function CollisionGroups.assign(model: Instance, group: string)
	if model:IsA("BasePart") then
		assignPart(model, group)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			assignPart(descendant, group)
		end
	end
end

--- A part added to a character after it joined (an accessory, the weapon) joins the players group.
function CollisionGroups.playerPartAdded(descendant: Instance)
	if descendant:IsA("BasePart") then
		descendant.CollisionGroup = AI.collision.players
	end
end

--- Puts a character in the players group, and every part added to it later. Returns the watch's
--- connection (the character's Destroy ends it), or nil where the instance has no events (Lune).
function CollisionGroups.joinPlayers(character: Model): Connection?
	CollisionGroups.assign(character, AI.collision.players)
	local ok, connection = pcall(function(): Connection
		return character.DescendantAdded:Connect(CollisionGroups.playerPartAdded) :: any
	end)
	return if ok then connection else nil
end

local overlapParams: OverlapParams? = nil

local function defaultOverlap(root: BasePart, exclude: Instance): { BasePart }
	local params = overlapParams
	if params == nil then
		local created = OverlapParams.new()
		created.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams = created
		params = created
	end
	local query = params :: OverlapParams
	query.FilterDescendantsInstances = { exclude }
	return workspace:GetPartsInPart(root, query)
end

-- Whether `probe` overlaps a colliding part in one of `groups` (a failed query finds nothing).
local function touches(probe: BasePart, model: Model, overlap: Overlap?, groups: { string }): boolean
	local ok, parts = pcall(overlap or defaultOverlap, probe, model)
	if not ok then
		return false
	end
	for _, part in parts :: { BasePart } do
		if part.CanCollide and table.find(groups, part.CollisionGroup) ~= nil then
			return true
		end
	end
	return false
end

--- Whether a model's root overlaps no colliding part of a player or of another enemy, and its
--- blocker (D-198) none of a player: a body that may rejoin the enemies group without the engine
--- pushing anyone out of it. A model without a root is clear; so is one whose query fails.
function CollisionGroups.clear(model: Model, overlap: Overlap?): boolean
	local root = model.PrimaryPart
	if root == nil then
		return true
	end
	local groups = AI.collision
	if touches(root, model, overlap, { groups.players, groups.enemies }) then
		return false
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and CollisionGroups.isBlocker(part) then
			if touches(part, model, overlap, { groups.players }) then
				return false
			end
		end
	end
	return true
end

--- Forgets the once-per-server registration (tests).
function CollisionGroups.reset()
	registered = false
end

return CollisionGroups
