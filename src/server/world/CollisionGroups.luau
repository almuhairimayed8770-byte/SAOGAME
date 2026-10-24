--!strict
--[[
	CollisionGroups (D-167): the server's collision groups for fighters, from ai.luau `collision`.

	Three groups besides the engine's Default (the world): player characters, enemies, and an enemy
	that is rushing. Every pair collides except the ones ai.luau lists in `apart`: a rushing body
	passes through players and through other enemies (it still runs on the world), so a Charger's
	rush never jams on the player it hits or on a packmate. Players collide with players and with
	walking enemies, and enemies with each other, as before.

	The server registers the groups once (register, from Main and EnemyService.start, either first);
	the engine replicates the group table and every part's CollisionGroup to the clients, so a
	client-simulated character passes a rushing boar on its own screen too. CharacterReady puts
	each character in the players group once it is built (joinPlayers, which also catches parts
	added later: accessories, the weapon), EnemyService puts each enemy in the enemies group at spawn
	and switches it to rushing for its rush. A stopped rush rejoins the enemies group only once its
	root overlaps no player and no enemy (clear), so the engine never has to push two bodies apart;
	that push is what lifted one boar onto another.

	Queries are unaffected: a RaycastParams / OverlapParams query runs as the Default group, which
	collides with all three, so blades, spherecasts and overlap tests see every fighter as before.

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

--- The three group names, players first.
function CollisionGroups.names(): { string }
	local groups = AI.collision
	return { groups.players, groups.enemies, groups.rushing }
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

--- Puts every BasePart of a model (or the part itself) in a group.
function CollisionGroups.assign(model: Instance, group: string)
	if model:IsA("BasePart") then
		model.CollisionGroup = group
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
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

--- Whether a model's root overlaps no colliding part of a player or of another enemy: a body that
--- may rejoin the enemies group without the engine pushing anyone out of it. A model without a root
--- is clear; so is one whose query fails.
function CollisionGroups.clear(model: Model, overlap: Overlap?): boolean
	local root = model.PrimaryPart
	if root == nil then
		return true
	end
	local ok, parts = pcall(overlap or defaultOverlap, root, model)
	if not ok then
		return true
	end
	local groups = AI.collision
	for _, part in parts :: { BasePart } do
		local group = part.CollisionGroup
		if part.CanCollide and (group == groups.players or group == groups.enemies) then
			return false
		end
	end
	return true
end

--- Forgets the once-per-server registration (tests).
function CollisionGroups.reset()
	registered = false
end

return CollisionGroups
