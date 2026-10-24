--!strict
-- ActionLogic.holdClipTime and ActionLogic.freezeAt: where a held Art clip freezes, and when a
-- render stall kept its rig from getting there (D-138).
local ActionLogic = Harness.load("src/client/controllers/ActionLogic")
local Combat = Harness.load("src/shared/data/combat")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")

local FALLBACK = Combat.startPoseTime + Combat.activationHold

describe("ActionLogic.holdClipTime", function()
	it("is the clip's first ActivationHold, or the section 6 time when that comes first or there is none", function()
		local early = { events = { { time = 0.4, kind = "Sfx" }, { time = 0.15, kind = "ActivationHold" } } }
		expect(ActionLogic.holdClipTime(early, FALLBACK)).toBe(math.min(0.15, FALLBACK))
		local twice = { events = { { time = 0.2, kind = "ActivationHold" }, { time = 0.1, kind = "ActivationHold" } } }
		expect(ActionLogic.holdClipTime(twice, FALLBACK)).toBe(math.min(0.1, FALLBACK))
		local late = { events = { { time = FALLBACK + 0.5, kind = "ActivationHold" } } }
		expect(ActionLogic.holdClipTime(late, FALLBACK)).toBe(FALLBACK)
		expect(ActionLogic.holdClipTime({ events = {} }, FALLBACK)).toBe(FALLBACK)
	end)

	it("reads every Art clip the data ships at its authored hold", function()
		for _, id in ClipLibrary.all() do
			local clip = ClipLibrary.get(id)
			local first: number? = nil
			for _, event in clip.events do
				if event.kind == "ActivationHold" then
					first = math.min(first or math.huge, event.time)
				end
			end
			if first ~= nil then
				expect(ActionLogic.holdClipTime(clip, FALLBACK)).toBe(math.min(first, FALLBACK))
			end
		end
	end)

	it("is nil for what is not clip data", function()
		expect(ActionLogic.holdClipTime(nil, FALLBACK)).toBeNil()
		expect(ActionLogic.holdClipTime("player/OneHandedSword/Horizontal", FALLBACK)).toBeNil()
		expect(ActionLogic.holdClipTime({}, FALLBACK)).toBeNil()
	end)
end)

describe("ActionLogic.freezeAt", function()
	local HOLD = 0.15

	it("a rig stepped all along freezes where it is, at the time the key has been down", function()
		-- The ActivationHold step (the rig stepped this frame) and the capture's fallback (stepped
		-- every frame, its slowed clip short of the hold) alike.
		local clipTime, seek = ActionLogic.freezeAt(10, 10.16, HOLD, 10.16)
		expect(clipTime).toBeCloseTo(0.16, 1e-9)
		expect(seek).toBe(false)
		clipTime, seek = ActionLogic.freezeAt(10, 10.25, HOLD, 10.25 - 1 / 60)
		expect(clipTime).toBeCloseTo(0.25, 1e-9)
		expect(seek).toBe(false)
		-- Stepped exactly at the hold's time: it got there.
		clipTime, seek = ActionLogic.freezeAt(10, 10.25, HOLD, 10 + HOLD)
		expect(clipTime).toBeCloseTo(0.25, 1e-9)
		expect(seek).toBe(false)
	end)

	it("a rig last stepped before its clip could reach the hold freezes at the hold, moved there", function()
		-- Pressed in the dark (last stepped long before the press), or just before a stall.
		local clipTime, seek = ActionLogic.freezeAt(10, 10.25, HOLD, 8)
		expect(clipTime).toBe(HOLD)
		expect(seek).toBe(true)
		clipTime, seek = ActionLogic.freezeAt(10, 10.25, HOLD, 10.1)
		expect(clipTime).toBe(HOLD)
		expect(seek).toBe(true)
		-- Never stepped at all.
		clipTime, seek = ActionLogic.freezeAt(10, 10.5, HOLD, nil)
		expect(clipTime).toBe(HOLD)
		expect(seek).toBe(true)
	end)

	it("a hold younger than its hold pose, or a clip with no clip clock, freezes where it is", function()
		local clipTime, seek = ActionLogic.freezeAt(10, 10.1, HOLD, 8)
		expect(clipTime).toBeCloseTo(0.1, 1e-9)
		expect(seek).toBe(false)
		clipTime, seek = ActionLogic.freezeAt(10, 10.25, nil, 8)
		expect(clipTime).toBeCloseTo(0.25, 1e-9)
		expect(seek).toBe(false)
		-- A press stamped after now (clock skew) is a zero hold.
		clipTime, seek = ActionLogic.freezeAt(10, 9.9, HOLD, 9.9)
		expect(clipTime).toBe(0)
		expect(seek).toBe(false)
	end)
end)
