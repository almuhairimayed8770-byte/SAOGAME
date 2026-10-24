--!strict
--[[
	The dodge's first move (D-179). Every dodge clip's extension key (0.07 s, 4.8 of its 8 studs) used
	ExpoOut, which put 3.88 studs of root travel into the first 60 fps frame (then 0.74 and 0.14):
	the body jumped and threw the follow camera about 3 studs in one drawn frame on a back dodge.
	The first key's travel is now spread over 2 to 3 frames. Everything else about the dodge stays:
	the distance, the duration, the key times and their root positions, the landing and recovery
	keys, the footstep and the invulnerability window (combat.luau).
]]

local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Combat = Harness.load("src/shared/data/combat")

local F = Combat.hitStopFrameSeconds -- one 60 fps frame
local DODGES = {
	{ name = "DodgeForward", axis = 3, sign = -1 },
	{ name = "DodgeBack", axis = 3, sign = 1 },
	{ name = "DodgeLeft", axis = 1, sign = -1 },
	{ name = "DodgeRight", axis = 1, sign = 1 },
}

local function clipOf(name: string): any
	return Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
end

local function travel(clip: any, from: number, to: number): number
	local a = ClipSampler.rootMotionAt(clip, from)
	local b = ClipSampler.rootMotionAt(clip, to)
	return math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
end

describe("the dodge's first move", function()
	for _, dodge in DODGES do
		it(("%s spreads its first key's travel over 2 to 3 drawn frames"):format(dodge.name), function()
			local clip = clipOf(dodge.name)
			local first = clip.keys[2]
			local studs = travel(clip, 0, first.time)
			expect(studs).toBeCloseTo(4.8, 1e-6)
			-- Wherever the 60 fps clock falls, no frame carries half of it; the first frame from the
			-- start carries the most.
			local worst = 0
			for phase = 0, 7 do
				local t = phase / 8 * F
				while t < first.time + F do
					worst = math.max(worst, travel(clip, t, t + F))
					t += F
				end
			end
			expect(worst / studs).toBeLessThanOrEqual(0.5)
			-- Still a snap, not a push: the first three frames from the start carry most of it.
			expect(travel(clip, 0, 3 * F) / studs).toBeGreaterThanOrEqual(0.85)
			expect(travel(clip, 0, F) / studs).toBeGreaterThanOrEqual(0.3)
		end)

		it(("%s keeps its distance, duration, keys, landing and footstep"):format(dodge.name), function()
			local clip = clipOf(dodge.name)
			expect(clip.duration).toBeCloseTo(0.38, 1e-9)
			local times = {}
			local along = {}
			for _, key in clip.keys do
				table.insert(times, key.time)
				table.insert(along, (key.root.pos :: any)[dodge.axis] * dodge.sign)
			end
			expect(times).toEqual({ 0, 0.07, 0.25, 0.38 })
			expect(along).toEqual({ 0, 4.8, 8, 8 })
			expect(clip.keys[3].easing).toBe("QuadOut")
			expect(clip.keys[4].easing).toBe("BackOut")
			local finish = ClipSampler.rootMotionAt(clip, clip.duration)
			expect(finish[dodge.axis] * dodge.sign).toBeCloseTo(Combat.dodgeDistance, 1e-9)
			-- Landed by the dodge's end; the step and the invulnerability are the dodge's own.
			local landed = ClipSampler.rootMotionAt(clip, Combat.dodgeDuration)
			expect(landed[dodge.axis] * dodge.sign).toBeCloseTo(Combat.dodgeDistance, 1e-9)
			expect(#clip.events).toBe(1)
			expect(clip.events[1].kind).toBe("Footstep")
			expect(clip.events[1].time).toBeCloseTo(0.3, 1e-9)
			expect(Combat.dodgeDuration).toBe(0.25)
			expect(Combat.dodgeInvulnerability).toBe(0.1)
		end)
	end
end)
