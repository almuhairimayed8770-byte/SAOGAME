--!strict
--[[
	The red line of a dropped wind-up comes down at the drop, and the next charge's line is its own
	(PC 1cf87aa M9 307: "the red line stays visible without a break from the first telegraph through
	the drop to the launch"). DevCombat's "hold" (or "enemy") drops a boar's wind-up (RushEnded
	"Dropped") and the "charge" sent right after begins a fresh one (0.03 s later on the PC), whose
	Telegraph draws a new line on the same spot. The real Replication and the real Telegraphs, frame
	by frame on the client's clock: the dropped line's pieces are clear from the drop's frame on, the
	new line fades in from clear at its own wind-up's start and is gone at its launch, and the boar
	never shows two lines. A pooled piece the new line takes back stays in the world, clear while no
	line holds it: a logger that counts the pool's parts sees them "through" the drop (D-442).
]]
local Replication = Harness.load("src/client/controllers/Replication")
local Telegraphs = Harness.load("src/client/fx/Telegraphs")
local TelegraphShapes = Harness.load("src/client/fx/TelegraphShapes")
local Engine = Harness.load("src/client/fx/Engine")
local Enemies = Harness.load("src/shared/data/enemies")
local Fx = Harness.load("src/shared/data/fx")

local FRAME = 1 / 60
local BOAR = Enemies.byId("FrenzyBoar")
local CHARGE = BOAR.attacks[1]

local function recorder(): any
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

local function fakeSignal(): any
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
		Fire = function() end,
	}
end

type Frame = { at: number, visible: number, pieces: { BasePart }, alpha: number, showing: boolean }

-- How opaque a ground piece is drawn (the decal's when it carries a texture, else the part's).
local function opacity(part: BasePart): number
	local decal = part:FindFirstChild("Decal")
	if decal ~= nil and decal:IsA("Decal") and decal.Texture ~= "" then
		return 1 - decal.Transparency
	end
	return 1 - part.Transparency
end

-- Plays `messages` (server seconds) through Replication on a 60 fps clock for `seconds`, the real
-- Telegraphs stepped every frame, and notes every frame's ground pieces.
local function run(messages: { { at: number, name: string, payload: any } }, seconds: number): ({ Frame }, Model)
	local state = { clock = 100 }
	Engine.setClock(function(): number
		return state.clock
	end)
	Telegraphs.resetLatency()
	local model = Instance.new("Model")
	model.Name = "Boar"
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Parent = model
	local records: { [number]: any } = {
		[1] = { id = 1, model = Instance.new("Model"), kind = "Player", rig = "PlayerR15" },
		[5] = { id = 5, model = model, kind = "Enemy", rig = BOAR.skin, defId = BOAR.id, state = "Idle" },
	}
	local animator = { events = fakeSignal() }
	function animator.play(_self: any, clipId: string): any
		return { clipId = clipId }
	end
	function animator.stop() end
	function animator.hitStop() end
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return records[id]
			end,
			all = function(): { any }
				return {}
			end,
			localChanged = fakeSignal(),
		},
		localId = function(): number
			return 1
		end,
		locomotion = recorder(),
		choreo = {
			get = function(): any
				return animator
			end,
		},
		clipLibrary = {
			has = function(): boolean
				return true
			end,
		},
		trails = recorder(),
		smear = recorder(),
		shatter = recorder(),
		sparks = recorder(),
		telegraphs = Telegraphs,
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
		now = function(): number
			return state.clock
		end,
		serverNow = function(): number
			return state.clock
		end,
	} :: any)
	local sent: { [number]: boolean } = {}
	local frames: { Frame } = {}
	local start = state.clock
	while state.clock - start < seconds do
		state.clock += FRAME
		for index, message in messages do
			if not sent[index] and state.clock >= start + message.at - 1e-9 then
				sent[index] = true
				Replication.dispatch(message.name, message.payload)
			end
		end
		Telegraphs.step()
		local pieces = Telegraphs.parts(model)
		local visible, alpha = 0, 0
		-- Every pooled piece in the world, held by a line or not.
		for _, part in pieces do
			alpha = math.max(alpha, opacity(part))
		end
		for _, part in pieces do
			if opacity(part) > 1e-6 then
				visible += 1
			end
		end
		table.insert(frames, {
			at = state.clock - start,
			visible = visible,
			pieces = pieces,
			alpha = alpha,
			showing = Telegraphs.isShowing(model),
		})
	end
	Engine.setClock(nil)
	return frames, model
end

local function telegraph(serverTime: number): any
	return {
		entityId = 5,
		attackId = CHARGE.id,
		kind = CHARGE.telegraph,
		windUp = CHARGE.windUp,
		serverTime = serverTime,
		origin = { 0, 3, 0 },
		facing = { 0, 0, -1 },
		shape = { kind = CHARGE.groundShape, length = CHARGE.reach, width = CHARGE.arc },
	}
end

local function dropped(serverTime: number): any
	return {
		entityId = 5,
		launchedAt = serverTime,
		serverTime = serverTime,
		distance = 0,
		reason = "Dropped",
	}
end

-- The first frame at or after `at` seconds into the run.
local function frameAt(frames: { Frame }, at: number): number
	for index, frame in frames do
		if frame.at >= at - 1e-9 then
			return index
		end
	end
	return #frames
end

describe("a dropped wind-up's line and the next charge's (307, D-442)", function()
	for _, gap in { 0.03, 0 } do
		it(
			("clears the dropped line on the drop's frame; the next charge's fades in on its own (%.2f s later)"):format(
				gap
			),
			function()
				-- The rush's wind-up from t = 0.05; the hold drops it 0.3 s in; the next begins `gap` later.
				local first, drop = 0.05, 0.35
				local second = drop + gap
				local frames = run({
					{ at = first, name = "Telegraph", payload = telegraph(100 + first) },
					{ at = drop, name = "RushEnded", payload = dropped(100 + drop) },
					{ at = second, name = "Telegraph", payload = telegraph(100 + second) },
				}, second + CHARGE.windUp + 0.3)
				local dropFrame = frameAt(frames, drop)
				local secondFrame = frameAt(frames, second)
				-- The dropped line is up, at most at its fade's brightness, before the drop.
				expect(frames[dropFrame - 1].visible > 0).toBe(true)
				local firstPieces = frames[dropFrame - 1].pieces
				-- From the drop's frame until the next Telegraph, no line at all.
				for index = dropFrame, secondFrame - 1 do
					expect(frames[index].showing).toBe(false)
					expect(frames[index].visible).toBe(0)
				end
				for _, part in firstPieces do
					if secondFrame > dropFrame then
						expect(opacity(part)).toBe(0)
					end
				end
				-- The new line fades in from clear: its first frame no brighter than a fresh wind-up's.
				local fresh = TelegraphShapes.decalAlpha(FRAME, CHARGE.windUp, 1, nil, nil, nil)
				expect(frames[secondFrame].showing).toBe(true)
				expect(frames[secondFrame].alpha).toBeLessThanOrEqual(fresh + 1e-6)
				expect(frames[secondFrame].alpha).toBeLessThan(Fx.telegraph.decal.alpha * 0.5)
				-- It rises over the fade (never a jump of more than a frame of it) and is gone at its launch.
				local launchFrame = frameAt(frames, second + CHARGE.windUp)
				for index = secondFrame + 1, launchFrame - 1 do
					expect(frames[index].alpha + 1e-6).toBeGreaterThanOrEqual(frames[index - 1].alpha)
				end
				for index = launchFrame + 1, #frames do
					expect(frames[index].showing).toBe(false)
					expect(frames[index].visible).toBe(0)
				end
			end
		)
	end

	it("a next charge's Telegraph heard before the drop replaces the line, and the drop leaves it", function()
		local first, second, drop = 0.05, 0.35, 0.4
		local frames = run({
			{ at = first, name = "Telegraph", payload = telegraph(100 + first) },
			-- The unreliable Telegraph of the next charge overtakes the reliable drop it follows.
			{ at = second, name = "Telegraph", payload = telegraph(100 + second) },
			{ at = drop, name = "RushEnded", payload = dropped(100 + second - 0.01) },
		}, second + CHARGE.windUp + 0.3)
		local secondFrame = frameAt(frames, second)
		local fresh = TelegraphShapes.decalAlpha(FRAME, CHARGE.windUp, 1, nil, nil, nil)
		expect(frames[secondFrame].alpha).toBeLessThanOrEqual(fresh + 1e-6)
		local launchFrame = frameAt(frames, second + CHARGE.windUp)
		for index = secondFrame, launchFrame - 1 do
			expect(frames[index].showing).toBe(true)
		end
		for index = launchFrame + 1, #frames do
			expect(frames[index].visible).toBe(0)
		end
	end)
end)
