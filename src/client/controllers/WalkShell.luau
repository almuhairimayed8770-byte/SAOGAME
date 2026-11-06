--!strict
--[[
	WalkShell (item 236, D-430): the local character's stick walk stops where its body shell touches
	an enemy, never inside it.

	The engine stops a character's colliding column (its root, torsos and head) at an enemy's blocker
	faces (D-198, D-315), and by then the arms and hands are already inside the enemy: the drawn
	left hand 1.08 studs inside a side-on boar's torso, 0.53 inside a kobold's arm. BodyShell.boxes
	is the rest of the body as boxes in the root's space, over the idle the stance stands in (drawn
	or sheathed). Each frame CharacterController asks `hold` for the stick's move, and the move is
	cut where a box would stand deeper than contact.standOff.wallGapStuds in a solid enemy's body
	face (keepOut.bodyFace, while it collides) or in what it holds (BodyShell.heldShapes: a kobold's
	axe as boxes over its idle; the face over the axe's whole footprint stopped a drawn walk-in past
	the reach a basic hits at). What the cut leaves slides along the box it met, so a walk at an
	angle runs on along the enemy's side.

	A move never goes deeper than the body already stands (an enemy that walked in, a swing's
	stand-off, a draw that brings the hand forward), and a move out is always free. The shell is no
	physics body: nothing pushes with it, an enemy walking in never shoves the player, and a swing's
	own keep-out (D-314) is untouched, since only the stick's walk is held.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Combat = require(Shared.data.combat)
local BodyShell = require(Shared.choreo.BodyShell)

local WalkShell = {}

--- A box the shell may not enter, in the world, with the radius of the sphere round it.
export type Obstacle = { frame: CFrame, size: Vector3, reach: number }

local TOUCH: number = Combat.contact.standOff.wallGapStuds
local HALVINGS: number = Combat.contact.walkShell.halvings
local BODY_FACE: string = Combat.contact.standOff.keepOut.bodyFace
local EPSILON = 1e-6

--- Adds to `into` what of `enemy` the shell meets, in the world: its body face while it collides
--- (a rushing body's and a shattered corpse's do not), and what it holds, where its root stands.
function WalkShell.obstaclesOf(enemy: Model, into: { Obstacle }): { Obstacle }
	local root = enemy.PrimaryPart
	local face = enemy:FindFirstChild(BODY_FACE)
	if root == nil or face == nil or not face:IsA("BasePart") or not (face :: BasePart).CanCollide then
		return into
	end
	local part = face :: BasePart
	table.insert(into, { frame = part.CFrame, size = part.Size, reach = part.Size.Magnitude / 2 })
	local rootFrame = root.CFrame
	for _, box in BodyShell.heldShapes(enemy) do
		table.insert(into, { frame = rootFrame * box.frame, size = box.size, reach = box.size.Magnitude / 2 })
	end
	return into
end

--- How deep the shell stands in the obstacle it is deepest in, the root at `at` (-huge when none
--- is near), and the way out of that one (nil when it stands in none).
function WalkShell.deepest(at: CFrame, shell: { BodyShell.Box }, obstacles: { Obstacle }): (number, Vector3?)
	local worst: number, out: Vector3? = -math.huge, nil
	for _, box in shell do
		local frame = at * box.frame
		local reach = box.size.Magnitude / 2
		for _, obstacle in obstacles do
			if (frame.Position - obstacle.frame.Position).Magnitude >= reach + obstacle.reach then
				continue
			end
			local depth, way = BodyShell.depth(frame, box.size, obstacle.frame, obstacle.size)
			if depth > worst then
				worst, out = depth, way
			end
		end
	end
	return worst, out
end

-- The longest share (0 to 1) of `move` from `at` that keeps the shell within `allowed`, and the
-- least share past it that does not (where the shell first meets what stops it; 1 when nothing does).
local function share(
	at: CFrame,
	move: Vector3,
	shell: { BodyShell.Box },
	obstacles: { Obstacle },
	allowed: number
): (number, number)
	if (WalkShell.deepest(at + move, shell, obstacles)) <= allowed then
		return 1, 1
	end
	local low, high = 0, 1
	for _ = 1, HALVINGS do
		local middle = (low + high) / 2
		if (WalkShell.deepest(at + move * middle, shell, obstacles)) <= allowed then
			low = middle
		else
			high = middle
		end
	end
	return low, high
end

--- What of `move` (one frame's walk, studs, in the world) the shell lets the root at `at` take:
--- the longest share that leaves no box deeper than wallGapStuds in an obstacle (or than the shell
--- already stands), then what the cut left along the face it met (the way out of it where the
--- shell first meets it), as far as that fits too.
function WalkShell.limit(at: CFrame, move: Vector3, shell: { BodyShell.Box }, obstacles: { Obstacle }): Vector3
	if move.Magnitude < EPSILON or #shell == 0 or #obstacles == 0 then
		return move
	end
	local allowed = math.max(TOUCH, (WalkShell.deepest(at, shell, obstacles)))
	local first, meets = share(at, move, shell, obstacles, allowed)
	if first >= 1 then
		return move
	end
	local taken = move * first
	local _, out = WalkShell.deepest(at + move * meets, shell, obstacles)
	if out == nil then
		return taken
	end
	local flat = Vector3.new(out.X, 0, out.Z)
	if flat.Magnitude < EPSILON then
		return taken
	end
	local normal = flat.Unit
	local rest = move - taken
	local along = rest - normal * rest:Dot(normal)
	if along.Magnitude < EPSILON then
		return taken
	end
	return taken + along * (share(at + taken, along, shell, obstacles, allowed))
end

--- The stick's walk for this frame once the shell has held it (CharacterController): the Humanoid
--- walks `direction`, which carries the root `studs` this frame; `enemies` are the tracker's records
--- (each with its `model`), the character's own skipped. Returns the direction to walk (the same
--- one, the face's way for a slide, or zero once nothing fits) and the share of the walk's speed
--- that fits this frame (1 when nothing is in the way): the engine's Move takes a direction only,
--- so the speed is the Humanoid's WalkSpeed to cut.
function WalkShell.hold(
	model: Model,
	root: BasePart,
	direction: Vector3,
	studs: number,
	drawn: boolean,
	enemies: { any }
): (Vector3, number)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if studs <= EPSILON or flat.Magnitude < EPSILON then
		return direction, 1
	end
	local obstacles: { Obstacle } = {}
	for _, record in enemies do
		local other = if typeof(record) == "table" then record.model else nil
		if typeof(other) == "Instance" and other ~= model and other:IsA("Model") then
			WalkShell.obstaclesOf(other :: Model, obstacles)
		end
	end
	if #obstacles == 0 then
		return direction, 1
	end
	local move = flat.Unit * studs
	local allowed = WalkShell.limit(root.CFrame, move, BodyShell.boxes(model, drawn), obstacles)
	if (allowed - move).Magnitude < EPSILON then
		return direction, 1
	end
	if allowed.Magnitude < EPSILON then
		return Vector3.zero, 0
	end
	return allowed.Unit, allowed.Magnitude / studs
end

return WalkShell
