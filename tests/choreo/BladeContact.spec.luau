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
