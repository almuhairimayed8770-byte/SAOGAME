--!strict
--[[
	The blade leaves a hit-stop eased, not in a jump (section 10 beats 4 and 5: the hold, then an
	overshoot of 5 to 8 degrees that springs back). The owner PC's frame log after the anim pass
	measured the weapon tip's first step after each Final freeze at 1.48 studs (Rising Arc, 60 Hz;
	1.83 at 30 Hz), 0.91 (Sharp Nail) and 0.56 (Vertical): six still frames, then most of the
	settle in one frame. The basics did the same (1.00, 1.12 and 0.53 studs at 60 Hz).

	Two things add up there. The settle key after each strike's authored Hold is eased Spring,
	whose first tenth of the segment carries most of it (Spring(0.15) = 0.94). And the freeze
	stands for the authored Hold (Mixer.hitStop's absorb): the first frame after it lands a whole
	frame into the settle (holdEnd + dt), the deepest any frame can land.

	Each attack is played the way the game plays it, through the real Mixer on the hit matrix's
	player: an Art from its start-pose hold (ActionLogic.holdClipTime), a basic from its first frame,
	the rig frozen with the tier's hit-stop (ContactPredictor.tierFor: an Art's last window and the
	chain's last basic are Final) on the frame its clock reaches each window's strike key
	(ContactPredictor.strikeKey, the contact rule), at 30, 60 and 144 frames a second. The weapon tip's step on the first frame after each
	freeze is at most review.audit.afterFreezeTipSpeed studs a second times the frame (15 studs/s:
	0.25 a 60 Hz frame, the most Horizontal's re-keyed settle shows at 60 Hz is 0.11).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local Joints = Harness.load("src/shared/choreo/Joints")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local Mixer = Harness.load("src/client/choreo/Mixer")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")

local Audit = Dev.review.audit
local HOLD_FALLBACK = Combat.startPoseTime + Combat.activationHold
-- Each attack and whether its last window is a final hit (an Art; the chain's last basic).
local ATTACKS: { { name: string, finalHit: boolean } } = {
	{ name = "Basic1", finalHit = 1 >= Combat.basicChainLength },
	{ name = "Basic2", finalHit = 2 >= Combat.basicChainLength },
	{ name = "Basic3", finalHit = 3 >= Combat.basicChainLength },
	{ name = "Horizontal", finalHit = true },
	{ name = "Vertical", finalHit = true },
	{ name = "SharpNail", finalHit = true },
	{ name = "RisingArc", finalHit = true },
}
local RATES = { 30, 60, 144 }
local root = Harness.repoRoot()

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
local avatar = HitMatrix.standing(Harness)
local chain = assert(BladeContact.chain(avatar.model), "the hit matrix's player has no blade")

local function rest()
	avatar.root.CFrame = avatar.base
	for _, joint in Joints.list(avatar.model) do
		joint.Transform = CFrame.identity
	end
end

local function tipNow(): Vector3
	local _, tip = BladeContact.blade(chain, BladeContact.read(chain))
	return tip
end

type Release = { window: number, tier: string, step: number }

-- Every freeze's release in one play of `name` at `fps`: the window, its tier and the tip's step
-- on the first frame the rig moves after it.
local function releases(name: string, finalHit: boolean, fps: number): { Release }
	rest()
	local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
	local windows = ClipSampler.hitWindows(clip)
	local keys = {}
	for index, window in windows do
		keys[index] = ContactPredictor.strikeKey(clip, window)
	end
	local dt = 1 / fps
	local mixer = Mixer.new()
	for _ = 1, 40 do
		mixer:step(dt)
	end
	local handle = mixer:play(clip)
	-- An Art plays on from its start-pose hold; a basic, which has none, from its first frame.
	local holds = false
	for _, event in clip.events or {} do
		holds = holds or event.kind == "ActivationHold"
	end
	if holds then
		mixer:seek(handle, ActionLogic.holdClipTime(clip, HOLD_FALLBACK) :: number)
	end
	mixer:step(0)
	local found: { Release } = {}
	local struck = 0
	local frozenWindow: number? = nil
	local lastTip = tipNow()
	for _ = 1, fps * 3 do
		local stepped = mixer:step(dt)
		for _, joint in Joints.list(avatar.model) do
			local offset = stepped.offsets[joint.Name]
			joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
		end
		local delta = stepped.rootDelta
		avatar.root.CFrame = avatar.root.CFrame + Vector3.new(delta[1], delta[2], delta[3])
		local tip = tipNow()
		local step = (tip - lastTip).Magnitude
		lastTip = tip
		if stepped.paused then
			frozenWindow = frozenWindow or struck
		elseif frozenWindow ~= nil then
			table.insert(found, {
				window = frozenWindow,
				tier = ContactPredictor.tierFor(frozenWindow, #windows, finalHit, false),
				step = step,
			})
			frozenWindow = nil
		end
		local nextKey = keys[struck + 1]
		if not stepped.paused and nextKey ~= nil and handle.time >= nextKey - 1e-6 then
			struck += 1
			mixer:hitStop(Combat.hitStopFrames[ContactPredictor.tierFor(struck, #windows, finalHit, false)])
		end
		if handle.done then
			break
		end
	end
	rest()
	return found
end

describe("the blade leaves a hit-stop eased", function()
	it("the review has a bar for the tip's step out of a freeze", function()
		local bar = (Audit :: any).afterFreezeTipSpeed
		expect(typeof(bar)).toBe("number")
	end)

	for _, attack in ATTACKS do
		local name = attack.name
		it(name .. ": the first frame after every freeze moves the tip under the bar at 30, 60 and 144 Hz", function()
			local bar: number? = (Audit :: any).afterFreezeTipSpeed
			local problems = {}
			for _, fps in RATES do
				local found = releases(name, attack.finalHit, fps)
				local windows = #ClipSampler.hitWindows(Harness.load("src/shared/clips/player/OneHandedSword/" .. name))
				if #found ~= windows then
					table.insert(problems, ("%d Hz: %d freezes released, %d windows"):format(fps, #found, windows))
				end
				for _, release in found do
					local most = if bar ~= nil then bar / fps else nil
					if most == nil or release.step > most + 1e-6 then
						table.insert(
							problems,
							("%d Hz hit %d (%s): %.2f studs on the first frame after the freeze (bar %s)"):format(
								fps,
								release.window,
								release.tier,
								release.step,
								if most ~= nil
									then ("%.2f"):format(most)
									else "missing: review.audit.afterFreezeTipSpeed"
							)
						)
					end
				end
			end
			expect(table.concat(problems, "\n")).toBe("")
		end)
	end
end)
