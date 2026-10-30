--!strict
--[[
	A cancel is a snap that reads as intent (D-401 decided; section 10 beat 2, a snap is 2-4 frames
	eased expo-out, "deliberately under-animated so the eye reads the pose, not the path"). The game
	cancels (ActionLogic STARTABLE): an Art, the guard or the next basic out of a basic; a dodge out
	of a basic, the guard or an Art's start-pose hold. The action that cuts in takes the body over
	within review.audit.cancel.snapFrames 60 Hz frames, the cancelled clip holding its pose while
	it hands over (its own motion never shows through the cross-fade), no part turning back inside
	the hand-over, and the 20 degree pop rule holding from the frame after it.

	On the anim pass, at 60 Hz, the hand-overs pop 53 degrees (an Art out of Basic1 at 0.1 s), 48-50
	(a dodge over Basic1 at 0.1 s, every part turning back the next frame: the cancelled Basic1 runs
	on into its strike snap under the fade), 41-61 (a dodge over the guard) and 45-53 (a dodge out of
	an Art's start-pose hold, three frames past 20 as the 0.05 s SineInOut cross-fade spans a pose
	140 degrees away); the guard raised during a basic does not show until the basic has played out
	(Basic1 on FullBody covers the guard's UpperBody layer), and nothing in the review plays these.

	- The review has the cancel rule's data (review.audit.cancel.snapFrames, 2 to 4).
	- ClipAudit.plans builds "Cancel ..." plans for a clip that cuts in.
	- Each cancel below, played through the real Mixer on the real rig the way the game cancels it,
	  as such a plan (handOver = true), has no finding at 60 or 240 Hz.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Dev = Harness.load("src/shared/data/dev")
local ChoreoData = Harness.load("src/shared/data/choreo")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")

local Audit = Dev.review.audit
local CONFIG = Audit.rigs.PlayerR15
local P = "player/OneHandedSword/"
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

-- The cancels the game allows, the clip that cuts in, the one it cancels and how far into it
-- (0.15 s into an Art is its start-pose hold, combat.startPoseTime). `stop`: the cut-in plays on
-- another layer, so the game stops the cancelled clip itself (the guard over a basic).
local CANCELS = {
	{ clip = "Horizontal", over = "Basic1", gap = 0.1 },
	{ clip = "Horizontal", over = "Basic1", gap = 0.2 },
	{ clip = "Vertical", over = "Basic2", gap = 0.1 },
	{ clip = "SharpNail", over = "Basic3", gap = 0.1 },
	{ clip = "DodgeLeft", over = "Basic1", gap = 0.1 },
	{ clip = "DodgeRight", over = "Basic1", gap = 0.1 },
	{ clip = "DodgeBack", over = "Basic1", gap = 0.1 },
	{ clip = "DodgeForward", over = "Guard", gap = 0.5 },
	{ clip = "DodgeBack", over = "Horizontal", gap = 0.15 },
	{ clip = "DodgeLeft", over = "RisingArc", gap = 0.15 },
	{ clip = "Guard", over = "Basic1", gap = 0.1, stop = true },
}

-- What plays under every player clip (ClipAudit.plans' own: the idle, the breathing, the drawn idle).
local function under(): { any }
	return {
		{ clip = ClipLibrary.get(CONFIG.idle), at = 0, startTime = 0, fallback = true, blendIn = 0 },
		{ clip = ClipLibrary.get(CONFIG.breathing), at = 0, coexist = true, blendIn = 0 },
		{ clip = ClipLibrary.get(CONFIG.drawnIdle), at = 0, startTime = 0, coexist = true, weight = 1, blendIn = 0 },
	}
end

describe("a cancel is a snap that reads as intent (D-401)", function()
	it("the review has the cancel rule's data", function()
		local cancel = (Audit :: any).cancel
		expect(typeof(cancel)).toBe("table")
		local frames = if typeof(cancel) == "table" then cancel.snapFrames else nil
		expect(typeof(frames) == "number" and frames >= 2 and frames <= 4).toBe(true)
	end)

	it("ClipAudit plans the cancels the game allows into a dodge and an Art", function()
		for _, name in { "DodgeLeft", "Horizontal" } do
			local labels = {}
			for _, plan in ClipAudit.plans(ClipLibrary.get(P .. name), ClipLibrary.get) do
				if plan.label:sub(1, 6) == "Cancel" then
					table.insert(labels, plan.label)
				end
			end
			expect(#labels > 0).toBe(true)
		end
	end)

	for _, case in CANCELS do
		it(("%s cancelling %s %.2f s in hands over as a snap"):format(case.clip, case.over, case.gap), function()
			local clip = ClipLibrary.get(P .. case.clip)
			local lead = math.max(Audit.leadSeconds, case.gap + 0.1)
			local plays = under()
			table.insert(plays, { clip = ClipLibrary.get(P .. case.over), at = lead - case.gap })
			table.insert(plays, { clip = clip, at = lead, measured = true })
			local over = ClipLibrary.get(P .. case.over)
			local plan: any = {
				label = ("Cancel %s@%.2f"):format(case.over, case.gap),
				plays = plays,
				-- The cut-in on another layer stops the cancelled clip as it starts (the guard
				-- over a basic, CharacterController.setGuard); a same-layer play stops it itself.
				stops = if case.stop
					then { { at = lead, clipId = over.id, blendOut = clip.blendIn or ChoreoData.blendIn } }
					else nil,
				settle = Audit.settleSeconds,
				-- The measured clip cuts in over a live action: its first cancel.snapFrames are a snap.
				handOver = true,
			}
			local lines = {}
			for _, hz in Audit.sampleHz do
				for _, finding in ClipAudit.findings(clip, ClipAudit.run(body, clip, plan, hz)) do
					table.insert(lines, finding.text)
				end
			end
			expect(table.concat(lines, "\n")).toBe("")
		end)
	end
end)
