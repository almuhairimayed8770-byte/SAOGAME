--!strict
--[[
	DevFrameCap: the Studio frame-rate cap (Studio item 303 asks for 30 fps; the Studio menu offers
	no 30). A LocalScript that runs only in Studio in a place carrying the DevCapture attribute;
	there it binds one render step (dev.luau frameCap.priority, after every step that draws the
	frame) that, while Workspace carries frameCap.attribute as a number of frames a second within
	frameCap.least to frameCap.most, waits on os.clock until 1/cap seconds have passed since the last
	frame it let go. A frame that took longer goes at once, and with no cap (no attribute, or one out
	of range) the step returns at once. Nothing ships: no shipping script requires it.

	Loaded the way Studio runs it, with a fake RunService (IsStudio, BindToRenderStep) and a fake
	clock behind os.clock that moves SPIN seconds on each read, as a spin's own reads take time.
]]

local luau = require("@lune/luau")

local Dev = Harness.load("src/shared/data/dev")
local ChoreoData = Harness.load("src/shared/data/choreo")
local CameraData = Harness.load("src/shared/data/camera")
local FxData = Harness.load("src/shared/data/fx")

local NODE = "src/client/dev/DevFrameCap"
local FILE = "src/client/dev/DevFrameCap.client.luau"
local SPIN = 1e-4 -- seconds each os.clock read takes in the fake
local WORK = 0.005 -- the rest of a frame's work

type Bind = { name: string, priority: number, fn: (dt: number) -> () }
type Fixture = {
	binds: { Bind },
	attributes: { [string]: any },
	clock: { now: number, reads: number },
	-- Runs one frame of `work` seconds and returns how long the cap's step held it.
	frame: (work: number) -> number,
}

local function priorityOf(row: { base: string, offset: number }): number
	return (Enum.RenderPriority :: any)[row.base].Value + row.offset
end

local function load(studio: boolean, capture: any): Fixture
	local clock = { now = 100, reads = 0 }
	local binds: { Bind } = {}
	local attributes: { [string]: any } = { [Dev.attributes.capture] = capture }
	local services: { [string]: any } = {
		RunService = {
			IsStudio = function(): boolean
				return studio
			end,
			BindToRenderStep = function(_self: any, name: string, priority: number, fn: (dt: number) -> ())
				table.insert(binds, { name = name, priority = priority, fn = fn })
			end,
		},
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node(NODE)
	env.require = function(node: any): any
		return Harness.loadModule(node)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name] or error("no service " .. name)
		end,
	}
	env.workspace = {
		GetAttribute = function(_self: any, name: string): any
			return attributes[name]
		end,
	}
	env.os = {
		clock = function(): number
			clock.reads += 1
			clock.now += SPIN
			return clock.now
		end,
	}
	luau.load(Harness.readFile(FILE), { debugName = FILE, environment = env :: any })()
	local last = clock.now
	return {
		binds = binds,
		attributes = attributes,
		clock = clock,
		frame = function(work: number): number
			clock.now += work
			local before = clock.now
			local dt = before - last
			for _, bind in binds do
				bind.fn(dt)
			end
			last = clock.now
			return clock.now - before
		end,
	}
end

describe("DevFrameCap (Studio item 303)", function()
	it("binds one step after every step that draws the frame, only in Studio with DevCapture", function()
		expect(#load(false, true).binds).toBe(0)
		expect(#load(true, nil).binds).toBe(0)
		expect(#load(true, "true").binds).toBe(0)
		local fixture = load(true, true)
		expect(#fixture.binds).toBe(1)
		local priority = fixture.binds[1].priority
		expect(priority).toBe(priorityOf(Dev.frameCap.priority))
		for _, rows in { ChoreoData.renderOrder, CameraData.renderOrder, FxData.renderOrder } do
			for _, row in rows :: any do
				expect(priority > priorityOf(row)).toBe(true)
			end
		end
	end)

	it("holds every frame to 1/30 s at a cap of 30", function()
		local fixture = load(true, true)
		fixture.attributes[Dev.frameCap.attribute] = 30
		fixture.frame(WORK)
		local started = fixture.clock.now
		local frames = 60
		local shortest, longest = math.huge, 0
		local previous = started
		for _ = 1, frames do
			fixture.frame(WORK)
			local length = fixture.clock.now - previous
			previous = fixture.clock.now
			shortest = math.min(shortest, length)
			longest = math.max(longest, length)
		end
		local fps = frames / (fixture.clock.now - started)
		print(("  cap 30: frames %.2f to %.2f ms, %.2f fps"):format(shortest * 1000, longest * 1000, fps))
		expect(shortest >= 1 / 30 - 1e-9).toBe(true)
		expect(longest <= 1 / 30 + 3 * SPIN).toBe(true)
		expect(math.abs(fps - 30) <= 0.1).toBe(true)
	end)

	it("spaces its own releases 1/cap apart whatever runs around it; a later reader sees that run vary", function()
		-- Item 397(b) (D-510): the PC's logger at Last+2 read frames as short as 31.94 ms at the 30
		-- cap. Each frame here: work before the cap (2 to 12 ms), the cap's step, a gap before a
		-- reader bound after it (0, or up to 1.5 ms), then the rest of the frame before the engine's
		-- next frame starts (the draw, physics, the Heartbeat: 1 to 3 ms). The engine's render step
		-- dt is the time from one frame's start to the next.
		local rng = Random.new(3)
		local fixture = load(true, true)
		local cap = fixture.binds[1].fn
		fixture.attributes[Dev.frameCap.attribute] = 30
		local function run(gapMost: number): (number, number, number, number, number)
			local clock = fixture.clock
			local lastStart, lastRelease, lastRead = nil :: number?, nil :: number?, nil :: number?
			local releaseLeast, readLeast, dtLeast, dtMost = math.huge, math.huge, math.huge, 0
			local dtSum, dtCount = 0, 0
			for frame = 1, 300 do
				local start = clock.now
				local dt = if lastStart ~= nil then start - lastStart else 1 / 30
				lastStart = start
				clock.now += 0.002 + rng:NextNumber() * 0.010
				cap(dt)
				local release = clock.now
				clock.now += rng:NextNumber() * gapMost
				clock.now += SPIN -- the reader's own os.clock read
				local read = clock.now
				clock.now += 0.001 + rng:NextNumber() * 0.002
				if frame > 2 then
					releaseLeast = math.min(releaseLeast, release - (lastRelease :: number))
					readLeast = math.min(readLeast, read - (lastRead :: number))
					dtLeast, dtMost = math.min(dtLeast, dt), math.max(dtMost, dt)
					dtSum += dt
					dtCount += 1
				end
				lastRelease, lastRead = release, read
			end
			return releaseLeast, readLeast, dtLeast, dtMost, dtSum / dtCount
		end
		for _, gapMost in { 0, 0.0015 } do
			local release, read, dtLeast, dtMost, dtMean = run(gapMost)
			print(
				("  gap to %.1f ms: releases >= %.3f ms, the reader's os.clock >= %.3f, dt %.3f to %.3f (mean %.3f)"):format(
					gapMost * 1000,
					release * 1000,
					read * 1000,
					dtLeast * 1000,
					dtMost * 1000,
					dtMean * 1000
				)
			)
			-- The cap's guarantee is its own release spacing.
			expect(release >= 1 / 30 - 1e-9).toBe(true)
			-- A reader right after it sees it as it is, less what varies between the two.
			expect(read >= 1 / 30 - gapMost - 1e-9).toBe(true)
			-- The engine's dt keeps the mean, not each frame.
			expect(math.abs(dtMean - 1 / 30) <= 1e-4).toBe(true)
		end
	end)

	it("lets a frame that took longer go at once, and never holds without a cap in range", function()
		local fixture = load(true, true)
		fixture.attributes[Dev.frameCap.attribute] = 30
		fixture.frame(WORK)
		expect(fixture.frame(0.05) <= 3 * SPIN).toBe(true)
		for _, value in { nil, Dev.frameCap.least - 1, Dev.frameCap.most + 1, "30", 0 / 0 } do
			fixture.attributes[Dev.frameCap.attribute] = value
			fixture.frame(WORK)
			expect(fixture.frame(WORK) <= 3 * SPIN).toBe(true)
		end
	end)
end)
