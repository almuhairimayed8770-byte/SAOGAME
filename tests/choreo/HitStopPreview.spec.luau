--!strict
--[[
	A previewed hit-stop holds the pose the game holds (D-394 amended, D-412; anim-result
	openIssues 10). The game freezes a swing on the frame its clock reaches each window's strike key
	(ContactPredictor.strikeKey: the strike snap's last key, the contact rule) and the Mixer's
	hit-stop then stands in for the authored Hold after it (Mixer.hitStop's absorb). The body
	review's hit-stop plan (ClipAudit Plan.hitStopFrames, ClipAudit.trace) froze instead on the
	frame the clock passed HitWindowOpen, the snap's first frame: Horizontal and Vertical held 0.35
	for their 0.40 key, Rising Arc 0.33 and 0.57 for 0.38 and 0.61, Sharp Nail 0.33, 0.58 and 0.86
	for 0.38, 0.63 and 0.90, poses the game never holds. (The ClipLab's own preview,
	ReviewMarkers.hitStopPreview, has its spec in tests/tools/ReviewMarkers.spec.luau.)
	Each Art the weapon has a clip for, traced through ClipAudit.trace (the real Mixer on the hit
	matrix's player) with the Final tier's frames at every window at 60 Hz: the first frame of each
	freeze shows the clip's clock at that window's strike key (within one frame's step).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Arts = Harness.load("src/shared/data/arts")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")

local HZ = 60
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
local avatar, field = HitMatrix.standing(Harness)
local body = ClipAudit.body(avatar.model, "PlayerR15", avatar.base, ClipAudit.topOf(field.CFrame, field.Size))

describe("a previewed hit-stop holds the pose the game holds", function()
	for _, art in Arts.list("OneHandedSword") do
		local name = art.clip:match("[^/]+$") or art.clip
		local id = "player/OneHandedSword/" .. name
		if not fs.isFile(root .. "/src/shared/clips/" .. id .. ".luau") then
			continue
		end
		it(name .. ": every freeze starts on the strike key", function()
			local clip = ClipLibrary.get(id)
			local lab: any = nil
			for _, plan in ClipAudit.plans(clip, ClipLibrary.get) do
				if plan.label == "Lab" then
					lab = table.clone(plan)
				end
			end
			assert(lab ~= nil, "no Lab plan")
			lab.hitStopFrames = Combat.hitStopFrames.Final
			local frames = ClipAudit.trace(body, lab, HZ)
			local held: { number } = {}
			local last: number? = nil
			local holding = false
			for _, frame in frames do
				local now = frame.clipTime
				if now ~= nil and last ~= nil and math.abs(now - last) < 1e-9 then
					if not holding then
						table.insert(held, now)
					end
					holding = true
				else
					holding = false
				end
				last = now
			end
			local problems = {}
			local windows = ClipSampler.hitWindows(clip)
			for index, window in windows do
				local key = ContactPredictor.strikeKey(clip, window)
				local at = held[index]
				if at == nil or math.abs(at - key) > 1 / HZ + 1e-6 then
					table.insert(
						problems,
						("window %d: the freeze holds clip time %s, the game holds the strike key %.4f"):format(
							index,
							if at ~= nil then ("%.4f"):format(at) else "none",
							key
						)
					)
				end
			end
			expect(table.concat(problems, "\n")).toBe("")
		end)
	end
end)
