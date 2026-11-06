--!strict
--[[
	The slam stop and the drawn rush pose (PC 1cf87aa M9/306(c): the drawn snout settled 0.32 studs
	inside the wall). The server stops a slamming body where the body it judges walls on meets the
	face, but every client draws the run in the Charge clip, whose gallop and skid carry the snout up
	to 0.23 studs past the rest pose; the clip still plays at the stop and through the daze. Every
	part the clients draw, in every pose of the Charge clip from the launch to its end, must stand
	out of the wall at the stop the slam rests the body at, head on and at an angle, or the drawn
	body stands in the wall there (D-437).

	The real path: RushWorld.bodyOf is the body EnemyService.spawn gives the Charger (its
	bodyProfile) and Replication.armRush gives RushDraw, and RushWorld.contact is the stop both judge
	a slam by.
]]

local RigBuilder = Harness.load("src/server/world/RigBuilder")
local RushWorld = Harness.load("src/shared/choreo/RushWorld")
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local CollisionGroups = Harness.load("src/server/world/CollisionGroups")
local Enemies = Harness.load("src/shared/data/enemies")
local AI = Harness.load("src/shared/data/ai")
local Brain = Harness.load("src/server/ai/Brain")

local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]
local FORWARD = Vector3.new(0, 0, -1)
local STEP = 1 / 240
-- How far a drawn part may stand in the face: a sample's rounding, nothing a player sees.
local SLACK = 0.05

-- How deep the body's own parts (never its blockers) stand past the plane through `point` with
-- outward `normal`, the root at `rootFrame`, in `offsets`' pose.
local function depthIn(
	model: Model,
	chain: any,
	offsets: any,
	rootFrame: CFrame,
	point: Vector3,
	normal: Vector3
): number
	local solved = Pose.solve(model, rootFrame, offsets, chain)
	local deepest = -math.huge
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or CollisionGroups.isBlocker(part) then
			continue
		end
		local frame = solved[part.Name]
		if frame == nil then
			continue
		end
		local half = part.Size / 2
		for _, x in { -1, 1 } do
			for _, y in { -1, 1 } do
				for _, z in { -1, 1 } do
					local corner = frame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
					deepest = math.max(deepest, -(corner - point):Dot(normal))
				end
			end
		end
	end
	return deepest
end

describe("The slam stop and the drawn Charge pose (D-437)", function()
	it("no pose the Charge clip draws from the launch on stands in the wall at the slam's stop", function()
		local model = RigBuilder.build(BOAR.skin)
		local chain = Pose.chain(model)
		local root = model.PrimaryPart :: BasePart
		local body = RushWorld.bodyOf(model) :: any
		expect(body).never.toBeNil()
		local clip = Harness.load("src/shared/clips/" .. Brain.clipIdFor(BOAR, CHARGE))
		local legs = { { at = 0, from = Vector3.zero, heading = FORWARD, facing = FORWARD } }
		local wrong: { string } = {}
		for _, meet in { 90, 75, 60, 45 } do
			expect(meet >= AI.rushWorld.glanceDegrees).toBe(true)
			-- A wall 10 studs ahead met at `meet` degrees: its outward normal, toward the body.
			local turn = math.rad(90 - meet)
			local normal = Vector3.new(math.sin(turn), 0, math.cos(turn))
			local point = FORWARD * 10
			-- Where the root's box meets it, run straight down the line from the origin.
			local half = root.Size / 2
			local reach = math.abs(normal.X) * half.X + math.abs(normal.Y) * half.Y + math.abs(normal.Z) * half.Z
			local closing = FORWARD:Dot(-normal)
			local free = ((point - Vector3.zero):Dot(-normal) - reach) / closing
			local contact = RushWorld.contact(legs, 0, free, normal, body, 0, nil)
			expect(contact.kind).toBe("Slam")
			local stop = CFrame.lookAt(FORWARD * contact.at, FORWARD * contact.at + FORWARD)
			local worst, worstAt = -math.huge, 0
			local t = CHARGE.windUp
			while t <= clip.duration + 1e-9 do
				local depth = depthIn(model, chain, ClipSampler.sample(clip, t), stop, point, normal)
				if depth > worst then
					worst, worstAt = depth, t
				end
				t += STEP
			end
			if worst > SLACK then
				table.insert(wrong, ("%d degrees: %.3f in the wall at %.3f s"):format(meet, worst, worstAt))
			end
		end
		expect(wrong).toEqual({})
	end)

	it("the body still rests on the face: no pose stands farther off it than the gallop's own reach", function()
		-- The stop leaves the rest pose short of the face by no more than the farthest pose reaches
		-- past it: the slam still reads as a slam.
		local model = RigBuilder.build(BOAR.skin)
		local body = RushWorld.bodyOf(model) :: any
		local rest = RushWorld.support(body.profile, FORWARD, FORWARD)
		local drawn = RushWorld.support(body.poses, FORWARD, FORWARD)
		expect(drawn).toBeGreaterThanOrEqual(rest)
		expect(drawn - rest).toBeLessThan(0.3)
	end)
end)
