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
]]

local CharacterReady = {}

-- What the waits read from the engine; injectable so they run under Lune.
export type Engine = {
	now: () -> number,
	step: () -> (),
	appearanceLoaded: (player: Player) -> boolean,
}

local engine: Engine = {
	now = os.clock,
	step = function()
		task.wait()
	end,
	appearanceLoaded = function(player: Player): boolean
		return player:HasAppearanceLoaded()
	end,
}

--- Waits until `character` is parented, dressed and built; false when it was replaced or never parented.
function CharacterReady.wait(player: any, character: Model, timeout: number, override: Engine?): boolean
	local e = override or engine
	local isPlayer = typeof(player) == "Instance" and (player :: Instance):IsA("Player")
	local deadline = e.now() + timeout
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
	return character.Parent ~= nil and not replaced()
end

return CharacterReady
