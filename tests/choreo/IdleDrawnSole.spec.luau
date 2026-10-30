--!strict
--[[
	The drawn idle keeps its feet on the field (section 10, section 21 gate line 4: "No T-pose,
	A-pose, frozen rig, popping limb or sliding foot appears in any clip"; D-417). Every attack,
	flinch and drawn turn plays over IdleDrawn, so its sole is under all of them. On the anim pass
	its weight shift at 3 s straightened the left knee to -12 while the root rolled 2 degrees onto
	that side and sank the left foot 0.16 below the field (every flinch kept a pending Sink for it
	in ClipAudit.spec), and the rear foot rose from 0.04 to 0.22 over it.

	- ClipAudit finds no Sink for IdleDrawn in any plan: no foot corner goes more than
	  review.audit.footSinkStuds under the field over the cycle.
	- Both feet hold where the cycle starts them: no foot's centre rises or sinks more than
	  locomotion.stride.contact off its start (a planted corner stays planted), nor moves more than
	  review.audit.footDriftStuds over the cycle.

	The bounds are review.audit's own; none moves.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local ChoreoData = Harness.load("src/shared/data/choreo")
local Dev = Harness.load("src/shared/data/dev")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")

local Audit = Dev.review.audit
local CONTACT = ChoreoData.locomotion.stride.contact
local root = Harness.repoRoot()
local ID = "player/OneHandedSword/IdleDrawn"

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

describe("the drawn idle keeps its feet on the field (D-417)", function()
	it("has no Sink in any plan", function()
		local _, findings = ClipAudit.audit(body, ClipLibrary.get(ID), ClipLibrary.get)
		local lines = {}
		for _, finding in ClipAudit.worst(findings) do
			if finding.kind == "Sink" then
				table.insert(lines, finding.text)
			end
		end
		expect(table.concat(lines, "\n")).toBe("")
	end)

	it("holds both feet where the cycle starts them", function()
		local clip = ClipLibrary.get(ID)
		local function feetAt(time: number): { [string]: CFrame }
			local solved = Pose.solve(body.model, body.base, ClipSampler.sample(clip, time), body.chain)
			return { LeftFoot = solved.LeftFoot, RightFoot = solved.RightFoot }
		end
		local start = feetAt(0)
		local problems = {}
		for index = 1, 240 do
			local time = clip.duration * index / 240
			for name, frame in feetAt(time) do
				local from = start[name].Position
				local moved = Vector3.new(frame.Position.X - from.X, 0, frame.Position.Z - from.Z).Magnitude
				local rose = frame.Position.Y - from.Y
				if moved > Audit.footDriftStuds or math.abs(rose) > CONTACT then
					table.insert(
						problems,
						("%s at %.2f s: moved %.3f (max %.2f), rose %.3f (max %.2f)"):format(
							name,
							time,
							moved,
							Audit.footDriftStuds,
							rose,
							CONTACT
						)
					)
				end
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)
end)
