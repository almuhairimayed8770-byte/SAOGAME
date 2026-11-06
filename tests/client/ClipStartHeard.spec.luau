--!strict
--[[
	A remote rig's action clip says where it starts (Replication.clipStarted, D-513). The network
	catch-up starts a late ActionStarted's clip that far in (Mixer.catchUpStart), and the Mixer's
	first step fires only the events from there on: the ones before it never fire, not even marked
	jumped. The capture's auto-perform timed its reactions off the clip's events alone, so at
	Studio's 0.1 s lag the boar's Charge clip, whose only events before its hit window are at 0.1
	and 0.11 s, started past both, set no dodge, and the boar ran the player down at 9.9 s (AH 400
	on 0582a04).

	The real path: a real Choreo animator on a RigBuilder Boar, the real ClipLibrary's Charge clip,
	the remotes through the real Replication (ActionStarted, watch's event routing), on a fake clock
	that is the server's too.
]]

local function frameSignal(): any
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
Harness.stubService("RunService", {
	RenderStepped = frameSignal(),
	Heartbeat = frameSignal(),
	PreSimulation = frameSignal(),
	-- Choreo's rig step: the spec steps the rig itself.
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Replication = Harness.load("src/client/controllers/Replication")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local Enemies = Harness.load("src/shared/data/enemies")

local FRAME = 1 / 60
local BOAR = Enemies.byId("FrenzyBoar")
local CLIP_ID = "enemy/" .. BOAR.skin .. "/Charge"
local CLIP = ClipLibrary.get(CLIP_ID)

local clock = 100
local function now(): number
	return clock
end
Choreo.configure({
	now = now,
	cameraPosition = function(): Vector3
		return Vector3.zero
	end,
})

local function recorder(): any
	return setmetatable({}, {
		__index = function(_self: any, _key: string): any
			return function(): any
				return nil
			end
		end,
	})
end

local function openOf(clip: any): number
	for _, event in clip.events do
		if event.kind == "HitWindowOpen" then
			return event.time
		end
	end
	error("no hit window")
end

type Heard = { kind: string, clipTime: number, at: number }

-- The boar's Charge clip started `late` seconds behind the server (ActionStarted's serverTime that
-- long ago), stepped `frames` frames: what clipStarted and clipEvent said, in order.
local function charge(late: number, frames: number): { Heard }
	clock = 100
	local model = RigBuilder.build(BOAR.skin)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.new(0, 3, 0)
	root.Position = root.CFrame.Position
	local folder = Instance.new("Folder")
	model.Parent = folder
	local record =
		{ id = 9, model = model, kind = "Enemy", defId = BOAR.id, rig = BOAR.skin, state = "Idle", hp = 4, maxHp = 120 }
	local me = Instance.new("Model")
	local mine = { id = 1, model = me, kind = "Player", state = "Idle", weaponId = "TrialistSword" }
	local quiet = {
		hitStop = function() end,
		pauseRemaining = function(): number
			return 0
		end,
		play = function() end,
	}
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == 9 then record elseif id == 1 then mine else nil
			end,
		},
		localId = function(): number?
			return 1
		end,
		locomotion = recorder(),
		choreo = {
			get = function(target: any): any
				return if target == me then quiet else Choreo.get(target)
			end,
		},
		clipLibrary = ClipLibrary,
		trails = recorder(),
		smear = recorder(),
		shatter = recorder(),
		sparks = recorder(),
		telegraphs = recorder(),
		outline = recorder(),
		switchRing = recorder(),
		digits = recorder(),
		hud = recorder(),
		systemLine = recorder(),
		sfx = recorder(),
		impact = recorder(),
		camera = recorder(),
		weaponCategory = function(): string
			return "OneHandedSword"
		end,
		trailToken = function(): string
			return "TrailCyanWhite"
		end,
		positionOf = function(): Vector3
			return Vector3.zero
		end,
		schedule = function() end,
		now = now,
		serverNow = now,
	} :: any)
	local heard: { Heard } = {}
	local started = (Replication :: any).clipStarted
	assert(started ~= nil, "Replication has no clipStarted signal")
	local startConnection = started:Connect(function(who: any, clipId: string, clipTime: number)
		if who == record and clipId == CLIP_ID then
			table.insert(heard, { kind = "Start", clipTime = clipTime, at = clock })
		end
	end)
	local eventConnection = Replication.clipEvent:Connect(
		function(who: any, clipId: string, event: any, jumped: boolean)
			if who == record and clipId == CLIP_ID and not jumped then
				table.insert(heard, { kind = event.kind, clipTime = event.time, at = clock })
			end
		end
	)
	Replication.watch(record)
	local animator = Choreo.get(model)
	animator:step(FRAME)
	Replication.dispatch(
		"ActionStarted",
		{ entityId = 9, clipId = CLIP_ID, serverTime = clock - late, facing = { 0, 0, -1 } }
	)
	for _ = 1, frames do
		clock += FRAME
		animator:step(FRAME)
	end
	startConnection:Disconnect()
	eventConnection:Disconnect()
	Replication.unwatch(record)
	return heard
end

describe("Replication.clipStarted (D-513)", function()
	it("says where a late-started Charge clip starts, though none of its events before the hit window fire", function()
		local open = openOf(CLIP)
		local early = 0
		for _, event in CLIP.events do
			if event.time < open then
				early = math.max(early, event.time)
			end
		end
		-- Studio's 0.1 s lag started the clip past 0.11 s, the last event before its window.
		local late = 0.15
		expect(early < late).toBe(true)
		local heard = charge(late, math.ceil((open - late) / FRAME) + 2)
		expect(#heard > 1).toBe(true)
		-- First the start, where the catch-up put the clip.
		expect(heard[1].kind).toBe("Start")
		expect(heard[1].clipTime).toBeCloseTo(late, 1e-6)
		-- None of the clip's events before the start fires: the first heard is the window's.
		for index = 2, #heard do
			expect(heard[index].clipTime >= late).toBe(true)
		end
		expect(heard[2].clipTime).toBeCloseTo(open, 1e-6)
		-- The start is the only word in time for a press `lead` before the window (the fight's
		-- dodge, 0.3 s): the window's own event comes after that moment.
		local lead = 0.3
		expect(heard[2].at - heard[1].at > open - late - lead).toBe(true)
	end)

	it("says the clip starts at 0 when it starts on time, ahead of its first event", function()
		local heard = charge(0, 12)
		expect(heard[1].kind).toBe("Start")
		expect(heard[1].clipTime).toBeCloseTo(0, 1e-6)
		expect(heard[2].kind).never.toBe("Start")
		expect(heard[2].clipTime < 0.15).toBe(true)
		local starts = 0
		for _, entry in heard do
			if entry.kind == "Start" then
				starts += 1
			end
		end
		expect(starts).toBe(1)
	end)
end)
