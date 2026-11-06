--!strict
--[[
	The ClipLab's game-paced views (LabPlayback, D-653). AT 532(m): the walk view took no speed
	(0.25x / 0.5x / 1x slow motion, Pause, frame steps), so the boar's walk at 7 studs/s alone (its
	wheel's pace) could not be played as the game plays it. AT 533(a): the lab looped the boar's
	Stagger 0-1.00 with no blend into the idle, so its blend-out rows could not be read.
	Walk pace plays a rig's data walk as RigDriver does at a share of its walkSpeed, the rig carried
	along its facing; play once plays a one-shot over the rig's idle with the game's own blends.
]]

local Dev = Harness.load("src/shared/data/dev")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Rigs = Harness.load("src/shared/data/rigs")
local LabPlayback = Harness.load("src/client/dev/LabPlayback")

local Lab = Dev.clipLab
local Stride = ChoreoData.locomotion.stride

describe("LabPlayback: the ClipLab's walk pace (AT 532(m))", function()
	it("plays the boar's walk at 7 studs/s alone, at half its clip rate", function()
		expect(Rigs.Boar.walkSpeed).toBe(14)
		expect(table.find(Lab.walkShares, 0.5) ~= nil).toBe(true)
		local pace = LabPlayback.walkPace("Boar", 0.5, 1) :: any
		expect(pace.speed).toBeCloseTo(7, 1e-9)
		expect(pace.rate).toBeCloseTo(0.5, 1e-9)
		expect(pace.walk).toBeCloseTo(1, 1e-9)
		expect(pace.idle).toBeCloseTo(0, 1e-9)
	end)

	it("paces every share as RigDriver does: never under rateFloor, the idle under a slower walk", function()
		for _, rig in { "Boar", "Kobold" } do
			for _, share in Lab.walkShares do
				local pace = LabPlayback.walkPace(rig, share, 1) :: any
				expect(pace.speed).toBeCloseTo(share * Rigs[rig].walkSpeed, 1e-9)
				expect(pace.rate).toBeCloseTo(math.max(share, Stride.rateFloor), 1e-9)
				expect(pace.walk + pace.idle).toBeCloseTo(1, 1e-9)
			end
		end
		-- Under rateFloor of its walkSpeed the walk plays at rateFloor and the idle takes the rest.
		local slow = LabPlayback.walkPace("Boar", Stride.rateFloor / 2, 1) :: any
		expect(slow.rate).toBeCloseTo(Stride.rateFloor, 1e-9)
		expect(slow.walk).toBeCloseTo(0.5, 1e-9)
		expect(slow.idle).toBeCloseTo(0.5, 1e-9)
		-- The player walks on its blend space: no data walk to pace.
		expect(LabPlayback.walkPace("PlayerR15", 0.5, 1)).toBeNil()
		expect(LabPlayback.walkOf("Boar")).toBe("enemy/Boar/Walk")
	end)

	it("carries the rig along its facing and puts it back on its pedestal every walkLoopSeconds", function()
		local origin = CFrame.lookAt(Vector3.new(-14, 3, 0), Vector3.new(-14, 3, -1))
		local loop = Lab.walkLoopSeconds
		local at = LabPlayback.carried(origin, 7, loop / 2, loop)
		expect((at.Position - Vector3.new(-14, 3, -3.5 * loop)).Magnitude).toBeCloseTo(0, 1e-6)
		local back = LabPlayback.carried(origin, 7, loop + 0.1, loop)
		expect((back.Position - Vector3.new(-14, 3, -0.7)).Magnitude).toBeCloseTo(0, 1e-6)
		expect(back.LookVector:Dot(origin.LookVector)).toBeCloseTo(1, 1e-6)
	end)

	it("cycles the shares from in place and back", function()
		local seen: { number } = {}
		local share: number? = LabPlayback.nextShare(nil, Lab.walkShares)
		while share ~= nil do
			table.insert(seen, share)
			share = LabPlayback.nextShare(share, Lab.walkShares)
		end
		expect(seen).toEqual(Lab.walkShares)
	end)
end)

describe("LabPlayback: the ClipLab plays a one-shot once into the idle (AT 533(a))", function()
	it("names each enemy rig's idle to blend into", function()
		expect(LabPlayback.idleOf("Boar")).toBe("enemy/Boar/Idle")
		expect(LabPlayback.idleOf("Kobold")).toBe("enemy/Kobold/Idle")
		expect(Lab.onceIdleSeconds > 0).toBe(true)
	end)

	it("the lab binds the walk pace and play once keys, and its script uses them", function()
		expect(Lab.hotkeys.walkPace).toBe("W")
		expect(Lab.hotkeys.playOnce).toBe("Q")
		local source = Harness.readFile("src/client/dev/ClipLab.client.luau")
		expect(source:find("bind(keys.walkPace, cycleWalk)", 1, true) ~= nil).toBe(true)
		expect(source:find("bind(keys.playOnce, toggleOnce)", 1, true) ~= nil).toBe(true)
		expect(source:find("LabPlayback.carried(", 1, true) ~= nil).toBe(true)
	end)
end)
