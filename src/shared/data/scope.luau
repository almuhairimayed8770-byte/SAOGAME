--!strict
--[[
	Phase scope (D-015). The data tables hold floors 1 to 10 and every weapon line on purpose, so
	later phases are data work, but clips are authored phase by phase. This table names the content
	whose clips the current phase must ship: the clips validator fails on a missing clip for any id
	listed here and prints one summary warning for everything else (the later-phase backlog). A clip
	file that exists is always validated in full whatever this table says.

	Ids are rows of the sibling tables: arts.luau ids ("<Weapon>.<ArtName>"), enemies.luau and
	bosses.luau ids (PascalCase) and rigs.luau ids. tools/validators/scope.luau checks that every id
	resolves, that nothing is listed twice and that every in-scope enemy's and boss's rig is in
	scope too. When a phase starts, raise `phase` and add its ids; nothing else changes.

	Phase 0 (section 20): Horizontal and Sharp Nail are the gate Arts, Vertical and Rising Arc are
	the other two One-Handed Sword Arts the ARCHITECTURE "Clips" list requires, one Charger (the
	boar) and one Brute (the kobold), no floor boss, and the three rigs those clips animate.
]]

local Scope = {}

--- The build phase whose content is in scope (section 20).
Scope.phase = 0

--- Art ids (arts.luau) whose clips must ship this phase.
Scope.arts = {
	"OneHandedSword.Horizontal",
	"OneHandedSword.Vertical",
	"OneHandedSword.RisingArc",
	"OneHandedSword.SharpNail",
} :: { string }

--- Enemy ids (enemies.luau) whose attack clips must ship this phase.
Scope.enemies = {
	"FrenzyBoar",
	"KoboldAxeman",
} :: { string }

--- Boss ids (bosses.luau) whose attack clips must ship this phase. Phase 0 has no floor boss.
Scope.bosses = {} :: { string }

--- Rig ids (rigs.luau) the in-scope clips animate.
Scope.rigs = {
	"PlayerR15",
	"Boar",
	"Kobold",
} :: { string }

local function toSet(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, id in list do
		set[id] = true
	end
	return set
end

local artSet = toSet(Scope.arts)
local enemySet = toSet(Scope.enemies)
local bossSet = toSet(Scope.bosses)
local rigSet = toSet(Scope.rigs)

--- True when this Art's clip must ship in the current phase.
function Scope.hasArt(id: string): boolean
	return artSet[id] == true
end

--- True when this enemy's attack clips must ship in the current phase.
function Scope.hasEnemy(id: string): boolean
	return enemySet[id] == true
end

--- True when this boss's attack clips must ship in the current phase.
function Scope.hasBoss(id: string): boolean
	return bossSet[id] == true
end

--- True when this rig is animated by the current phase's clips.
function Scope.hasRig(id: string): boolean
	return rigSet[id] == true
end

return Scope
