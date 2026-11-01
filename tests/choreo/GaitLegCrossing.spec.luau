--!strict
--[[
	GaitLegCrossing: the drawn run's legs pass each other without crossing (D-481). Every attack
	the player starts out of the drawn run blends in over it (ClipAudit's Run@ plans), so a shin
	inside the other shin in the run shows in each of them.

	RunDrawn is traced alone through ClipAudit (the Lab plan: the real clip on the hit matrix's
	player, its root carried at the clip's ground speed) at each review.audit sampleHz, and the
	deepest a right-leg part (thigh, shin, foot) goes into a left-leg part is held to
	review.audit.overlapStuds, the audit's bar for a limb inside the body. Both feet plant 0.1
	inside the hips (stride.touchdown), so the swinging leg turns out past the planted one; with
	no turn the right shin went 0.234 into the left one.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Dev = Harness.load("src/shared/data/dev")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")

local Audit = Dev.review.audit
local root = Harness.repoRoot()

-- tools/ modules are plain Lune scripts: load one with only Lune's own libraries to require.
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target) :: any
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

-- The audit's leg pair for the player: the right leg's parts against the left leg's.
local function legPair(): ({ string }, { string })
	for _, pair in Audit.rigs.PlayerR15.pairs do
		if table.find(pair.a, "RightUpperLeg") ~= nil then
			return pair.a, pair.b
		end
	end
	error("review.audit.rigs.PlayerR15 has no leg pair")
end

type Deepest = { depth: number, a: string, b: string, at: number }

-- The deepest right-leg part in a left-leg part over one traced cycle of `id` at `hz`.
local function deepest(body: any, id: string, hz: number): Deepest
	local clip = ClipLibrary.get(id)
	local plan = ClipAudit.plans(clip, ClipLibrary.get)[1]
	expect(plan.label).toBe("Lab")
	local right, left = legPair()
	local worst: Deepest = { depth = 0, a = "", b = "", at = 0 }
	local frames = 0
	for _, frame in ClipAudit.trace(body, plan, hz) do
		if frame.clipTime == nil then
			continue
		end
		frames += 1
		for _, a in right do
			for _, b in left do
				local depth = ClipAudit.overlapDepth(frame.solved[a], body.sizes[a], frame.solved[b], body.sizes[b])
				if depth > worst.depth then
					worst = { depth = depth, a = a, b = b, at = frame.clipTime :: number }
				end
			end
		end
	end
	-- One whole cycle at least was traced.
	expect(frames >= math.floor(clip.duration * hz)).toBe(true)
	return worst
end

describe("GaitLegCrossing: the drawn run's legs pass each other", function()
	local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
	local avatar, field = HitMatrix.standing(Harness)
	local body = ClipAudit.body(avatar.model, "PlayerR15", avatar.base, ClipAudit.topOf(field.CFrame, field.Size))

	for _, hz in Audit.sampleHz do
		it(("RunDrawn keeps each leg out of the other at %d Hz"):format(hz), function()
			local worst = deepest(body, "player/OneHandedSword/RunDrawn", hz)
			print(
				("  RunDrawn at %d Hz: deepest %.3f studs (%s into %s at %.4f s), bar %.2f"):format(
					hz,
					worst.depth,
					worst.a,
					worst.b,
					worst.at,
					Audit.overlapStuds
				)
			)
			expect(worst.depth <= Audit.overlapStuds).toBe(true)
		end)
	end
end)
