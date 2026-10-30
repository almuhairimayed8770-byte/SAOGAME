--!strict
--[[
	CharacterReady: waits until a spawned character is finished and in the world (D-046).

	Player.CharacterAdded fires before the engine has finished the character. Under the avatar
	loading order Roblox ships, the event fires before the character is parented to Workspace and
	before its appearance (the avatar's body parts, accessories and its own scale values) is
	applied; the rig is built and scaled after it is parented. Anything a handler writes onto the
	character at that point can be overwritten (scale values) or orphaned (a weapon hung from a hand
	the appearance replaces), and a "left before it was ready" check on Parent sees nil. Measured in
	a Studio Play session on 2026-10-18: the player's character was never registered and its sword
	was gone.

	wait(player, character, timeout) returns true once the character is parented, its appearance
	has loaded (or the timeout ran out for that part: a player whose avatar fails to load still
	plays), and one more frame has passed for the engine's rig build; false when the character was
	replaced or never parented in time. A player-like stand-in that is not a Player instance (smoke
	scripts, tests) counts as loaded. The engine reads are injectable so the waits run under Lune.

	A character that is ready joins the players collision group (D-167, CollisionGroups.joinPlayers):
	its parts are final by then, and parts added later (the weapon, accessories) join as they come,
	so a rushing enemy passes through it.

	No engine label over a player (D-178): every Humanoid in the character gets DisplayDistanceType
	None (and no name or health distance), as RigBuilder does for every rig, so the engine never
	draws its own name and health bar over another player beside our nameplate. It is done as the
	wait begins (the Humanoid usually exists at CharacterAdded, so the label is off from the first
	frame anyone sees) and again once the character is ready (a Humanoid the appearance brought).
]]

local CollisionGroups = require(script.Parent.CollisionGroups)

local CharacterReady = {}

-- What the waits read from the engine; injectable so they run under Lune.
export type Engine = {
	now: () -> number,
	step: () -> (),
	appearanceLoaded: (player: Player) -> boolean,
	-- Puts a ready character in the players collision group (D-167). Nil: no group (tests).
	collide: ((character: Model) -> ())?,
}

--- The engine's own join: the character's parts, and every part added later, in the players group
--- (Main registered the groups before any service started).
function CharacterReady.join(character: Model)
	CollisionGroups.joinPlayers(character)
end

--- Takes the engine's own name and health bar off every Humanoid in `character` (D-178).
function CharacterReady.unlabel(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Humanoid") then
			local humanoid = child :: Humanoid
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.NameDisplayDistance = 0
			humanoid.HealthDisplayDistance = 0
		end
	end
end

local engine: Engine = {
	now = os.clock,
	step = function()
		task.wait()
	end,
	appearanceLoaded = function(player: Player): boolean
		return player:HasAppearanceLoaded()
	end,
	collide = CharacterReady.join,
}

--- Waits until `character` is parented, dressed and built; false when it was replaced or never parented.
function CharacterReady.wait(player: any, character: Model, timeout: number, override: Engine?): boolean
	local e = override or engine
	local isPlayer = typeof(player) == "Instance" and (player :: Instance):IsA("Player")
	local deadline = e.now() + timeout
	CharacterReady.unlabel(character)
	local function replaced(): boolean
		return isPlayer and (player :: Player).Character ~= character
	end
	while character.Parent == nil do
		if replaced() or e.now() >= deadline then
			return false
		end
		e.step()
	end
	while isPlayer and not e.appearanceLoaded(player :: Player) and e.now() < deadline do
		if replaced() then
			return false
		end
		e.step()
	end
	e.step() -- the engine builds and scales the rig right after it parents the character
	if character.Parent == nil or replaced() then
		return false
	end
	CharacterReady.unlabel(character)
	local collide = e.collide
	if collide ~= nil then
		collide(character)
	end
	return true
end

return CharacterReady
