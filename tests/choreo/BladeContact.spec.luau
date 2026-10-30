--!strict
--[[
	BladeContact (issue 4): the blade a rig shows (TrailStart to TrailEnd, the trails' segment) solved
	from the joints' Transforms by forward kinematics, the server's box distance, and the touch
	rule. The body is the hit matrix's (the engine-style R15 with AnimationConstraint joints and the
	WeaponBuilder sword); its Transforms are set as Choreo sets them from a clip.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local HitSweep = Harness.load("src/server/combat/HitSweep")

local root = Harness.repoRoot()

local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
local avatar = HitMatrix.standing(Harness)
local model = avatar.model

-- Writes a clip's pose at `time` into the joints' Transforms, as Choreo does.
local function pose(clip: any, time: number): any
	local offsets = ClipSampler.sample(clip, time)
	for _, joint in Joints.list(model) do
		local offset = offsets[joint.Name]
		joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
	end
	return offsets
end

local function close(a: Vector3, b: Vector3, tolerance: number?): boolean
	return (a - b).Magnitude <= (tolerance or 1e-4)
end

local SharpNail = Harness.load("src/shared/clips/player/OneHandedSword/SharpNail")

describe("BladeContact.chain and blade", function()
	it("solves the trails' segment from the Transforms exactly as Pose solves the clip", function()
		local chain = BladeContact.chain(model)
		expect(chain ~= nil).toBe(true)
		local guardAttachment = model:FindFirstChild("TrailStart", true)
		local tipAttachment = model:FindFirstChild("TrailEnd", true)
		for _, time in { 0, 0.2, 0.34, 0.36, 0.5, 0.62, 0.9 } do
			local offsets = pose(SharpNail, time)
			local current = BladeContact.read(chain :: any)
			local guard, tip = BladeContact.blade(chain :: any, current)
			local wantGuard = Pose.attachmentPosition(model, avatar.root.CFrame, offsets, guardAttachment)
			local wantTip = Pose.attachmentPosition(model, avatar.root.CFrame, offsets, tipAttachment)
			-- Lune's CFrames are single precision: the two solves differ in the fifth digit.
			expect(close(guard, wantGuard, 1e-3)).toBe(true)
			expect(close(tip, wantTip, 1e-3)).toBe(true)
		end
	end)

	it("follows the root part the frame reads, moved or turned", function()
		local chain = BladeContact.chain(model) :: any
		pose(SharpNail, 0.36)
		local before = BladeContact.read(chain)
		local _, tip = BladeContact.blade(chain, before)
		local moved = BladeContact.copy(before)
		moved.root = CFrame.new(3, 0, -2) * before.root * CFrame.Angles(0, math.rad(30), 0)
		local _, movedTip = BladeContact.blade(chain, moved)
		local expected = moved.root * (before.root:Inverse() * tip)
		expect(close(movedTip, expected, 1e-3)).toBe(true)
	end)

	it("between two frames follows the arc: the ends at 0 and 1, off the chord between", function()
		local chain = BladeContact.chain(model) :: any
		pose(SharpNail, 0.3333)
		local from = BladeContact.copy(BladeContact.read(chain))
		pose(SharpNail, 0.3833)
		local to = BladeContact.read(chain)
		local _, tip0 = BladeContact.blade(chain, from)
		local _, tip1 = BladeContact.blade(chain, to)
		local _, atStart = BladeContact.blade(chain, to, from, 0)
		local _, atEnd = BladeContact.blade(chain, to, from, 1)
		local _, middle = BladeContact.blade(chain, to, from, 0.5)
		expect(close(atStart, tip0)).toBe(true)
		expect(close(atEnd, tip1)).toBe(true)
		-- The snap swings the blade through a wide arc: its middle is well off the straight chord.
		local chordMiddle = (tip0 + tip1) / 2
		expect((tip1 - tip0).Magnitude > 4).toBe(true)
		expect((middle - chordMiddle).Magnitude > 0.5).toBe(true)
	end)

	it("read reuses its pose table and copy keeps a frame apart from the next read", function()
		local chain = BladeContact.chain(model) :: any
		pose(SharpNail, 0.1)
		local into = BladeContact.read(chain)
		local kept = BladeContact.copy(into)
		pose(SharpNail, 0.36)
		local again = BladeContact.read(chain, into)
		expect(again).toBe(into)
		local _, tipKept = BladeContact.blade(chain, kept)
		local _, tipNow = BladeContact.blade(chain, again)
		expect((tipKept - tipNow).Magnitude > 1).toBe(true)
		expect(#again.transforms).toBe(#chain.links)
	end)

	it("finds no chain without trail attachments, with them on two parts, or with no joint path", function()
		local bare = Instance.new("Model")
		local part = Instance.new("Part")
		part.Parent = bare
		bare.PrimaryPart = part
		expect(BladeContact.chain(bare)).toBe(nil)

		local split = Instance.new("Model")
		local a, b = Instance.new("Part"), Instance.new("Part")
		a.Parent, b.Parent = split, split
		split.PrimaryPart = a
		local start, finish = Instance.new("Attachment"), Instance.new("Attachment")
		start.Name, finish.Name = "TrailStart", "TrailEnd"
		start.Parent, finish.Parent = a, b
		expect(BladeContact.chain(split)).toBe(nil)

		-- Both on a part no joint reaches.
		local loose = Instance.new("Model")
		local rootPart, blade = Instance.new("Part"), Instance.new("Part")
		rootPart.Parent, blade.Parent = loose, loose
		loose.PrimaryPart = rootPart
		local s2, f2 = Instance.new("Attachment"), Instance.new("Attachment")
		s2.Name, f2.Name = "TrailStart", "TrailEnd"
		s2.Parent, f2.Parent = blade, blade
		expect(BladeContact.chain(loose)).toBe(nil)
	end)
end)

describe("BladeContact geometry", function()
	it("measures a segment against a box exactly as the server's sweep does", function()
		local random = Random.new(1451)
		for _ = 1, 400 do
			local function vector(scale: number): Vector3
				return Vector3.new(
					random:NextNumber(-scale, scale),
					random:NextNumber(-scale, scale),
					random:NextNumber(-scale, scale)
				)
			end
			local a, b = vector(6), vector(6)
			local frame = CFrame.new(vector(2))
				* CFrame.Angles(random:NextNumber(0, 6.28), random:NextNumber(0, 6.28), random:NextNumber(0, 6.28))
			local size = Vector3.new(random:NextNumber(0.2, 4), random:NextNumber(0.2, 4), random:NextNumber(0.2, 4))
			local mine, minePoint = BladeContact.segmentBoxDistance(a, b, frame, size)
			local server, serverPoint = HitSweep.segmentBoxDistance(a, b, frame, size)
			expect(math.abs(mine - server) < 1e-9).toBe(true)
			expect(close(minePoint, serverPoint, 1e-9)).toBe(true)
		end
	end)

	local function part(position: Vector3, size: Vector3): any
		local created = Instance.new("Part")
		created.Size = size
		created.CFrame = CFrame.new(position)
		return created
	end

	it("touches a part within the hit radius, at the nearest touched part's point", function()
		local near = part(Vector3.new(0, 0, -3), Vector3.new(2, 2, 2))
		local far = part(Vector3.new(0, 0, 6), Vector3.new(2, 2, 2))
		local start, finish = Vector3.new(-3, 0, 0), Vector3.new(3, 0, 0)
		-- 2 studs from the near box's face: no touch at a radius of 1.2, a touch at 2.1.
		local touched = BladeContact.touch(start, finish, { near, far }, 1.2)
		expect(touched).toBe(false)
		local hit, at = BladeContact.touch(start, finish, { far, near }, 2.1)
		expect(hit).toBe(true)
		-- On the near box's face toward the blade, under it.
		expect(math.abs((at :: Vector3).Z + 2) < 1e-4).toBe(true)
		expect(math.abs((at :: Vector3).X) <= 1 + 1e-4).toBe(true)
		-- Through the box: distance 0.
		local through, point = BladeContact.touch(Vector3.new(0, 0, -6), Vector3.new(0, 0, 0), { near }, 0.1)
		expect(through).toBe(true)
		expect(point ~= nil).toBe(true)
	end)

	it("counts a part by its box, not its bounding sphere: a corner miss stays a miss", function()
		local box = part(Vector3.zero, Vector3.new(2, 2, 2))
		-- Passing 1.3 studs off the box's corner along its diagonal plane: inside the bounding
		-- sphere grown by the radius, outside the box grown by it.
		local offset = Vector3.new(1, 1, 0) + Vector3.new(1, 1, 0).Unit * 1.3
		local hit = BladeContact.touch(offset + Vector3.new(0, 0, -3), offset + Vector3.new(0, 0, 3), { box }, 1.2)
		expect(hit).toBe(false)
	end)

	it("splits a move into steps no end travels farther than the step, capped", function()
		local zero = Vector3.zero
		expect(BladeContact.steps(zero, zero, zero, zero, 1.2, 12)).toBe(1)
		expect(BladeContact.steps(zero, zero, Vector3.new(1, 0, 0), Vector3.new(3.7, 0, 0), 1.2, 12)).toBe(4)
		expect(BladeContact.steps(zero, zero, zero, Vector3.new(100, 0, 0), 1.2, 12)).toBe(12)
		expect(BladeContact.steps(zero, zero, zero, Vector3.new(3, 0, 0), 0, 12)).toBe(1)
	end)

	it("follows the engine's query rule: a part is skipped only with CanQuery and CanCollide off", function()
		local p = part(Vector3.zero, Vector3.one)
		p.CanCollide, p.CanQuery = true, true
		expect(BladeContact.queryable(p)).toBe(true)
		p.CanCollide, p.CanQuery = false, true
		expect(BladeContact.queryable(p)).toBe(true)
		p.CanCollide, p.CanQuery = true, false
		expect(BladeContact.queryable(p)).toBe(true)
		p.CanCollide, p.CanQuery = false, false
		expect(BladeContact.queryable(p)).toBe(false)
	end)
end)

describe("BladeContact: a fighter beside the swing is cut only by the blade itself", function()
	local function part(position: Vector3, size: Vector3): any
		local created = Instance.new("Part")
		created.Size = size
		created.CFrame = CFrame.new(position)
		return created
	end

	-- A point `distance` studs flat from `origin` at `degrees` from -Z (+ = left, the sign of a
	-- CFrame.Angles yaw), raised by `height`.
	local function at(origin: Vector3, degrees: number, distance: number, height: number?): Vector3
		local look = CFrame.Angles(0, math.rad(degrees), 0).LookVector
		return origin + look * distance + Vector3.new(0, height or 0, 0)
	end

	it("is beside outside half the cone either side of the facing, flat; in front inside it or on top", function()
		local origin = Vector3.new(4, 3, -2)
		local facing = Vector3.new(0, 0, -1)
		for _, degrees in { 0, 39, -39, 39.9 } do
			expect(BladeContact.beside(origin, facing, at(origin, degrees, 5), 80, 0.5)).toBe(false)
		end
		for _, degrees in { 41, -41, 60, -90, 135, 180 } do
			expect(BladeContact.beside(origin, facing, at(origin, degrees, 5), 80, 0.5)).toBe(true)
		end
		-- Height is ignored, and so is the facing's tilt.
		expect(BladeContact.beside(origin, Vector3.new(0, -0.9, -0.3), at(origin, 30, 5, 10), 80, 0.5)).toBe(false)
		-- Any facing: the cone turns with it.
		local turned = CFrame.Angles(0, math.rad(70), 0).LookVector
		expect(BladeContact.beside(origin, turned, at(origin, 100, 6), 80, 0.5)).toBe(false)
		expect(BladeContact.beside(origin, turned, at(origin, 20, 6), 80, 0.5)).toBe(true)
		-- On top of the origin there is no bearing: in front.
		expect(BladeContact.beside(origin, facing, origin + Vector3.new(0.3, 2, 0.2), 80, 0.5)).toBe(false)
		-- A facing with no flat part gives no cone: every fighter is in front.
		expect(BladeContact.beside(origin, Vector3.new(0, -1, 0), at(origin, 120, 5), 80, 0.5)).toBe(false)
	end)

	it("a swept blade touches a box it passes through between two far-apart blades, on the box", function()
		-- A thin post (0.2 wide) the blade sweeps across: the blade lies along Z at x = -3, then x = 3.
		local post = part(Vector3.new(0, 0, -4), Vector3.new(0.2, 4, 0.2))
		local a0, b0 = Vector3.new(-3, 0, -2), Vector3.new(-3, 0, -6)
		local a1, b1 = Vector3.new(3, 0, -2), Vector3.new(3, 0, -6)
		expect((BladeContact.touch(a0, b0, { post }, 0.2))).toBe(false)
		expect((BladeContact.touch(a1, b1, { post }, 0.2))).toBe(false)
		local hit, point = BladeContact.sweptTouch(a0, b0, a1, b1, { post }, 0.2, 0.2)
		expect(hit).toBe(true)
		expect(math.abs((point :: Vector3).X) <= 0.1 + 1e-6).toBe(true)
		expect(math.abs((point :: Vector3).Z + 4) <= 0.1 + 1e-6).toBe(true)
		-- However long the move, and whichever way it goes.
		local far = Vector3.new(30, 0, 0)
		local hitBack = BladeContact.sweptTouch(a1 + far, b1 + far, a0 - far, b0 - far, { post }, 0.2, 0.2)
		expect(hitBack).toBe(true)
	end)

	it("a swept blade that stops short of a box touches it only within the radius", function()
		local box = part(Vector3.new(2, 0, -4), Vector3.new(2, 2, 2)) -- its -X face at x = 1
		local a0, b0 = Vector3.new(-3, 0, -2), Vector3.new(-3, 0, -6)
		local function stopAt(x: number): boolean
			return (BladeContact.sweptTouch(a0, b0, Vector3.new(x, 0, -2), Vector3.new(x, 0, -6), { box }, 0.2, 0.2))
		end
		expect(stopAt(1 - 0.25)).toBe(false)
		expect(stopAt(1 - 0.15)).toBe(true)
		-- A stud short: the hit radius would reach it, the blade does not.
		expect(stopAt(0)).toBe(false)
		expect((BladeContact.touch(Vector3.new(0, 0, -2), Vector3.new(0, 0, -6), { box }, 1.2))).toBe(true)
	end)

	it("does not test the blade it starts from: that one was tested as the last move's end", function()
		local box = part(Vector3.new(0, 0, -4), Vector3.new(2, 2, 2)) -- its +X face at x = 1
		-- Starting 0.1 off the face, inside the radius, and moving straight away: only the start
		-- touches (the first step is 0.196 farther out).
		local a0, b0 = Vector3.new(1.1, 0, -3), Vector3.new(1.1, 0, -5)
		local a1, b1 = Vector3.new(6, 0, -3), Vector3.new(6, 0, -5)
		expect((BladeContact.touch(a0, b0, { box }, 0.2))).toBe(true)
		expect((BladeContact.sweptTouch(a0, b0, a1, b1, { box }, 0.2, 0.2))).toBe(false)
		-- A blade that does not move is the overlap test's alone.
		expect((BladeContact.sweptTouch(a0, b0, a0, b0, { box }, 0.2, 0.2))).toBe(false)
	end)

	-- A blade turning flat about a guard at the origin, 4 studs long: at `degrees` from -Z.
	local function turning(degrees: number): (Vector3, Vector3)
		return Vector3.zero, CFrame.Angles(0, math.rad(degrees), 0).LookVector * 4
	end
	local function solveTurn(from: number, to: number): (t: number) -> (Vector3?, Vector3?)
		return function(t: number): (Vector3?, Vector3?)
			return turning(from + (to - from) * t)
		end
	end

	it("follows the drawn arc between two far samples: a box the arc cuts and the chord misses", function()
		-- The tip sweeps -60 to +60 degrees; between, the chord's tip passes 2 studs out, the arc 4.
		local post = part(Vector3.new(0, 0, -3.8), Vector3.new(0.2, 2, 0.2))
		local a0, b0 = turning(-60)
		local a1, b1 = turning(60)
		expect((BladeContact.sweptTouch(a0, b0, a1, b1, { post }, 0.15, 0.15))).toBe(false)
		local hit, point, spent =
			BladeContact.followTouch(a0, b0, 0, a1, b1, 1, { post }, 0.15, 0.3, solveTurn(-60, 60), 16)
		expect(hit).toBe(true)
		-- On the post's box, nearest the blade.
		expect(math.abs((point :: Vector3).X) <= 0.1 + 1e-5).toBe(true)
		expect(math.abs((point :: Vector3).Z + 3.8) <= 0.1 + 1e-5).toBe(true)
		expect(spent > 0 and spent <= 16).toBe(true)
		-- With no splits left, or no solver, the move is taken straight: the chord's verdict.
		expect((BladeContact.followTouch(a0, b0, 0, a1, b1, 1, { post }, 0.15, 0.3, solveTurn(-60, 60), 0))).toBe(false)
		expect((BladeContact.followTouch(a0, b0, 0, a1, b1, 1, { post }, 0.15, 0.3, nil, 16))).toBe(false)
		-- A solver that cannot pose the middle falls back to the chord, spending the split.
		local function lost(_t: number): (Vector3?, Vector3?)
			return nil, nil
		end
		local lostHit, _, lostSpent = BladeContact.followTouch(a0, b0, 0, a1, b1, 1, { post }, 0.15, 0.3, lost, 16)
		expect(lostHit).toBe(false)
		expect(lostSpent).toBe(1)
	end)

	it("cuts only within its radius of the arc, and does not test the blade it starts from", function()
		local a0, b0 = turning(-60)
		local a1, b1 = turning(60)
		local function postAt(z: number): any
			return part(Vector3.new(0, 0, z), Vector3.new(0.2, 2, 0.2)) -- its +Z face at z + 0.1
		end
		-- The arc's tip passes 0.1 studs short of the post's face at -4.1; its chords would pass 2 short.
		local function cut(z: number, radius: number): boolean
			return (BladeContact.followTouch(a0, b0, 0, a1, b1, 1, { postAt(z) }, radius, 0.3, solveTurn(-60, 60), 16))
		end
		expect(cut(-4.2, 0.15)).toBe(true)
		expect(cut(-4.2, 0.05)).toBe(false)
		expect(cut(-4.5, 0.15)).toBe(false)
		-- Starting inside the radius and turning away: only the start touches, and it is not tested.
		local behind = part(CFrame.Angles(0, math.rad(-63), 0).LookVector * 3, Vector3.new(0.1, 2, 0.1))
		expect((BladeContact.touch(a0, b0, { behind }, 0.15))).toBe(true)
		expect((BladeContact.followTouch(a0, b0, 0, a1, b1, 1, { behind }, 0.15, 0.3, solveTurn(-60, 60), 16))).toBe(
			false
		)
	end)

	it("spends no split on a move that passes far from the body, and stops at its budget", function()
		local a0, b0 = turning(-60)
		local a1, b1 = turning(60)
		local far = part(Vector3.new(30, 0, 30), Vector3.new(2, 2, 2))
		local hit, _, spent = BladeContact.followTouch(a0, b0, 0, a1, b1, 1, { far }, 0.15, 0.3, solveTurn(-60, 60), 16)
		expect(hit).toBe(false)
		expect(spent).toBe(0)
		-- A box just past the arc's reach on its far side keeps it splitting near it, never past the budget.
		local near = part(Vector3.new(0, 0, -4.6), Vector3.new(0.2, 2, 0.2))
		local nearHit, _, nearSpent =
			BladeContact.followTouch(a0, b0, 0, a1, b1, 1, { near }, 0.15, 0.01, solveTurn(-60, 60), 5)
		expect(nearHit).toBe(false)
		expect(nearSpent <= 5).toBe(true)
	end)

	it("carries the root between two samples along its clip's root motion, not the chord", function()
		local clip = Harness.load("src/shared/clips/player/OneHandedSword/Basic3")
		local window = ClipSampler.hitWindows(clip)[1]
		local from, to = window.open, window.close
		-- Zero at both ends and for an empty span.
		expect(BladeContact.rootBow(clip, from, to, from, CFrame.identity).Magnitude < 1e-6).toBe(true)
		expect(BladeContact.rootBow(clip, from, to, to, CFrame.identity).Magnitude < 1e-6).toBe(true)
		expect(BladeContact.rootBow(clip, to, from, (from + to) / 2, CFrame.identity).Magnitude).toBe(0)
		-- Between them: the clip's root motion less the straight line, in the root's frame.
		local middle = (from + to) / 2
		local a = ClipSampler.rootMotionAt(clip, from)
		local b = ClipSampler.rootMotionAt(clip, to)
		local m = ClipSampler.rootMotionAt(clip, middle)
		local expected = Vector3.new(m[1] - (a[1] + b[1]) / 2, m[2] - (a[2] + b[2]) / 2, m[3] - (a[3] + b[3]) / 2)
		local bow = BladeContact.rootBow(clip, from, to, middle, CFrame.identity)
		expect((bow - expected).Magnitude < 1e-5).toBe(true)
		expect(bow.Magnitude > 0.1).toBe(true) -- Basic3's lunge eases: 0.2 studs off its chord here
		-- Turned with the root.
		local turned = CFrame.Angles(0, math.rad(90), 0)
		local turnedBow = BladeContact.rootBow(clip, from, to, middle, turned)
		expect((turnedBow - turned:VectorToWorldSpace(expected)).Magnitude < 1e-5).toBe(true)
	end)
end)

describe("BladeContact: a held weapon clashes, it never wounds (D-277)", function()
	local RigBuilder = Harness.load("src/server/world/RigBuilder")
	local Rigs = Harness.load("src/shared/data/rigs")

	it("a part a rigged fighter holds (its rig's trailParts) is not its body", function()
		local checked = 0
		for rigId, rig in Rigs do
			if rig.parts == nil then
				continue -- engine-built (the player's R15): its sword is not under a rig part
			end
			local built = RigBuilder.build(rigId)
			local heldNames = rig.trailParts or {}
			for _, descendant in built:GetDescendants() do
				if descendant:IsA("BasePart") then
					local isHeld = table.find(heldNames, descendant.Name) ~= nil
					expect(BladeContact.held(descendant)).toBe(isHeld)
					expect(BladeContact.hurtbox(descendant)).toBe(BladeContact.queryable(descendant) and not isHeld)
					checked += 1
				end
			end
			built:Destroy()
		end
		expect(checked > 0).toBe(true)
		-- The kobold's club, by name.
		local kobold = RigBuilder.build("Kobold")
		expect(BladeContact.held(kobold:FindFirstChild("Weapon"))).toBe(true)
		expect(BladeContact.hurtbox(kobold:FindFirstChild("Weapon"))).toBe(false)
		expect(BladeContact.hurtbox(kobold:FindFirstChild("Torso"))).toBe(true)
		kobold:Destroy()
	end)

	it("only a rig's own list counts: no rig, an unknown rig or a body part keep the engine's rule", function()
		local model = Instance.new("Model")
		local weapon = Instance.new("Part")
		weapon.Name = "Weapon"
		weapon.Parent = model
		expect(BladeContact.held(weapon)).toBe(false)
		expect(BladeContact.hurtbox(weapon)).toBe(true)
		model:SetAttribute("Rig", "NoSuchRig")
		expect(BladeContact.held(weapon)).toBe(false)
		model:SetAttribute("Rig", "Kobold")
		expect(BladeContact.held(weapon)).toBe(true)
		-- A part with no parent, or one the engine's query never sees, is no hurtbox either way.
		local loose = Instance.new("Part")
		expect(BladeContact.held(loose)).toBe(false)
		weapon.Name = "Torso"
		weapon.CanCollide, weapon.CanQuery = false, false
		expect(BladeContact.hurtbox(weapon)).toBe(false)
	end)
end)
