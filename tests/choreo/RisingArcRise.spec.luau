--!strict
--[[
	Rising Arc rises onto the toes (section 8: the launcher; the clip's own header: "the legs drive
	the hips up onto the toes ... from behind it reads as a crouch that uncoils upward"). The owner
	PC's rehearsal on cebade4 (shot 5) measured the head only 0.06-0.07 studs over standing through
	the first cut and its hold: the root rose, but the leaning torso took most of it back and one
	foot stood heel-down with its toe in the air.

	The clip is posed on the hit matrix's player (HitMatrix.standing: feet on the Playground field,
	as GroundClearance.spec poses every clip) at 60 fps from the first snap's landing through its
	settle, against the drawn idle's first frame ("standing"):
	- the head peaks at least PEAK_RISE over standing (the aim is about 0.3) and stays at least
	  HELD_RISE over it from the snap's landing through the settle;
	- on each of those frames both heels are up: each foot's heel edge at least HEEL_LIFT over its
	  toe edge;
	- and both feet stand on the field: each foot's lowest point no lower than the idle's lowest foot
	  point less SINK_SLACK (the idle stance itself sinks the front foot a little) and no higher than
	  FLOAT over the field's top.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")

local root = Harness.repoRoot()

local PEAK_RISE = 0.25
local HELD_RISE = 0.2
local HEEL_LIFT = 0.2
local SINK_SLACK = 0.03
local FLOAT = 0.1
local FRAME = 1 / 60
local FEET = { "LeftFoot", "RightFoot" }

-- tools/ modules are plain Lune scripts: load one with only Lune's own libraries to require.
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
local avatar, field = HitMatrix.standing(Harness)
local chain = Pose.chain(avatar.model)
local fieldTop = field.CFrame.Position.Y
	+ math.abs(field.CFrame.RightVector.Y) * field.Size.X * 0.5
	+ math.abs(field.CFrame.UpVector.Y) * field.Size.Y * 0.5
	+ math.abs(field.CFrame.LookVector.Y) * field.Size.Z * 0.5

local footSizes: { [string]: any } = {}
for _, name in FEET do
	local part = avatar.model:FindFirstChild(name, true)
	assert(part ~= nil and part:IsA("BasePart"), "the hit matrix's player has no " .. name)
	footSizes[name] = (part :: any).Size
end

type Foot = { heel: number, toe: number, lowest: number }
type Measure = { head: number, feet: { [string]: Foot } }

-- The head's height and each foot's heel and toe edges (the lowest corner of the back and of the
-- front half of the foot's box: +Z is the heel), all over the field's top.
local function measure(offsets: any): Measure
	local solved = Pose.solve(avatar.model, avatar.base, offsets, chain)
	local feet = {}
	for _, name in FEET do
		local frame = solved[name]
		local size = footSizes[name]
		local heel, toe = math.huge, math.huge
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = frame * Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)
					local height = corner.Y - fieldTop
					if sz > 0 then
						heel = math.min(heel, height)
					else
						toe = math.min(toe, height)
					end
				end
			end
		end
		feet[name] = { heel = heel, toe = toe, lowest = math.min(heel, toe) }
	end
	return { head = solved.Head.Position.Y - fieldTop, feet = feet }
end

local idle = measure(ClipSampler.sample(ClipLibrary.get("player/OneHandedSword/IdleDrawn"), 0))
local idleLowest = math.min(idle.feet.LeftFoot.lowest, idle.feet.RightFoot.lowest)
local clip = ClipLibrary.get("player/OneHandedSword/RisingArc")

-- The frames from the first snap's landing through its settle (the first Spring key after it).
local function riseFrames(): { number }
	local from = clip.beats.Snap.finish
	local to = clip.beats.Settle.finish
	local times = {}
	for index = 0, math.floor((to - from) / FRAME + 1e-6) do
		table.insert(times, from + index * FRAME)
	end
	return times
end

describe("Rising Arc rises onto the toes (shot 5)", function()
	it(
		"the head peaks about 0.3 studs over standing and stays up from the snap's landing through its settle",
		function()
			local peak, peakAt = -math.huge, 0
			local low: { string } = {}
			for _, t in riseFrames() do
				local rise = measure(ClipSampler.sample(clip, t)).head - idle.head
				if rise > peak then
					peak, peakAt = rise, t
				end
				if rise < HELD_RISE then
					table.insert(low, ("%.4f s: %+.3f"):format(t, rise))
				end
			end
			if peak < PEAK_RISE or #low > 0 then
				error(
					("the head peaks %+.3f over standing at %.4f s (at least %.2f) and drops under %.2f on %d frame(s): %s"):format(
						peak,
						peakAt,
						PEAK_RISE,
						HELD_RISE,
						#low,
						table.concat(low, ", ")
					)
				)
			end
		end
	)

	it("lifts both heels and keeps both feet on the field through the rise", function()
		local problems: { string } = {}
		for _, t in riseFrames() do
			local now = measure(ClipSampler.sample(clip, t))
			for _, name in FEET do
				local foot = now.feet[name]
				if foot.heel - foot.toe < HEEL_LIFT then
					table.insert(
						problems,
						("%.4f s %s: heel %+.3f over its toe (at least %.2f)"):format(
							t,
							name,
							foot.heel - foot.toe,
							HEEL_LIFT
						)
					)
				end
				if foot.lowest < idleLowest - SINK_SLACK or foot.lowest > FLOAT then
					table.insert(
						problems,
						("%.4f s %s: lowest point %+.3f over the field (from %+.3f, the idle's lowest less %.2f, to %+.2f)"):format(
							t,
							name,
							foot.lowest,
							idleLowest - SINK_SLACK,
							SINK_SLACK,
							FLOAT
						)
					)
				end
			end
		end
		if #problems > 0 then
			error(("%d foot problem(s):\n%s"):format(#problems, table.concat(problems, "\n")))
		end
	end)
end)
