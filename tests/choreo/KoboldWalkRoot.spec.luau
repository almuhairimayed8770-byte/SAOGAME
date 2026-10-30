--!strict
--[[
	The Kobold's walk carries its body where its idle does (section 10, section 21 gate line 4: "No
	T-pose, A-pose, frozen rig, popping limb or sliding foot appears in any clip"; D-418). The rig
	driver crossfades enemy/Kobold/Idle into enemy/Kobold/Walk by speed (choreo.luau rigs.Kobold).
	The idle was re-keyed to stand its root 0.3 higher, on the rig's leg length; the walk was not,
	so every start and stop dropped the body 0.28 in the 0.15 s blend and the walk's planted foot
	stood 0.11 to 0.32 below the field (ClipAudit kept a pending Sink of 0.23 for it).

	- The walk's root height, averaged over its cycle, is within review.audit.footSinkStuds of the
	  idle's.
	- ClipAudit finds no Sink for the walk in any plan.

	The bounds are review.audit's own; none moves. The walk's stride against the rig's walkSpeed
	(its Slide and Drift) is still pending in ClipAudit.spec.
]]

local Dev = Harness.load("src/shared/data/dev")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local RigBuilder = Harness.load("src/server/world/RigBuilder")

local Audit = Dev.review.audit
local SAMPLES = 240

-- The root key's height averaged over a clip's cycle.
local function meanRootHeight(clip: any): number
	local sum = 0
	for index = 0, SAMPLES - 1 do
		local key = ClipSampler.sample(clip, clip.duration * index / SAMPLES).Root
		sum += if key ~= nil and key.pos ~= nil then key.pos[2] else 0
	end
	return sum / SAMPLES
end

describe("the Kobold's walk carries its body where its idle does (D-418)", function()
	it("keeps its root at the idle's height, so the crossfade does not drop the body", function()
		local idle = meanRootHeight(ClipLibrary.get("enemy/Kobold/Idle"))
		local walk = meanRootHeight(ClipLibrary.get("enemy/Kobold/Walk"))
		local gap = math.abs(idle - walk)
		expect(
			if gap <= Audit.footSinkStuds
				then ""
				else ("the body drops %.2f from the idle to the walk (max %.2f)"):format(gap, Audit.footSinkStuds)
		).toBe("")
	end)

	it("has no Sink in any plan", function()
		local clip = ClipLibrary.get("enemy/Kobold/Walk")
		local body = ClipAudit.standingBody(RigBuilder.build(clip.rig), clip.rig)
		local _, findings = ClipAudit.audit(body, clip, ClipLibrary.get)
		local lines = {}
		for _, finding in ClipAudit.worst(findings) do
			if finding.kind == "Sink" then
				table.insert(lines, finding.text)
			end
		end
		expect(table.concat(lines, "\n")).toBe("")
	end)
end)
