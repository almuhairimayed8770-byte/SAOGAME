--!strict
-- The accents on the shared step (Glint, SlashArc, SpeedLines) run every rendered frame, so a
-- frame of theirs should build as little as it can: each module is loaded here a second time with
-- counting wrappers around the datatype constructors, driven by a fake clock and a fake step, and
-- the constructors each frame calls are counted. Building on play is fine; building per frame
-- only where the picture really changes.
local luau = require("@lune/luau")
local AccentStep = Harness.load("src/client/fx/AccentStep")
local Quality = Harness.load("src/client/fx/Quality")
local accents = Harness.load("src/shared/data/accents")

local F = accents.frameSeconds
local COUNTED: { [string]: { string } } = {
	NumberSequence = { "new" },
	NumberSequenceKeypoint = { "new" },
	ColorSequence = { "new" },
	UDim2 = { "new", "fromScale", "fromOffset" },
	Vector2 = { "new" },
	CFrame = { "new", "fromMatrix" },
}

local counts: { [string]: number } = {}

local function total(prefix: string): number
	local sum = 0
	for name, value in counts do
		if name:sub(1, #prefix) == prefix then
			sum += value
		end
	end
	return sum
end

-- A fresh copy of the module at `path` whose datatype constructors count into `counts`; its
-- dependencies are the shared harness modules.
local function loadCounting(path: string): any
	local env = Harness.environment()
	for typeName, constructors in COUNTED do
		local real = env[typeName]
		local wrapped = setmetatable({}, { __index = real })
		for _, constructor in constructors do
			local original = real[constructor]
			wrapped[constructor] = function(...)
				local key = typeName .. "." .. constructor
				counts[key] = (counts[key] or 0) + 1
				return original(...)
			end
		end
		env[typeName] = wrapped
	end
	env.script = Harness.node(path)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	local chunk = luau.load(Harness.readFile(path .. ".luau"), { debugName = path, environment = env :: any })
	return chunk()
end

local clock = 0
local steps: { (dt: number) -> () } = {}
local overrides: AccentStep.Overrides = {
	now = function()
		return clock
	end,
	onStep = function(fn: (dt: number) -> ()): () -> ()
		table.insert(steps, fn)
		return function()
			local index = table.find(steps, fn)
			if index ~= nil then
				table.remove(steps, index)
			end
		end
	end,
	viewport = function()
		return Vector2.new(1920, 1080)
	end,
}

-- One frame on the fake step; returns what it built.
local function frame(): { [string]: number }
	table.clear(counts)
	clock += F
	for _, fn in table.clone(steps) do
		fn(F)
	end
	return table.clone(counts)
end

-- Runs `body` at High on an empty fake step (a case that failed midway leaves no loop behind).
local function atHigh(body: () -> ())
	table.clear(steps)
	local before = Quality.get()
	Quality.set("High")
	local ok, err = pcall(body)
	Quality.set(before)
	if not ok then
		error(err, 0)
	end
end

local function sum(built: { [string]: number }, prefix: string): number
	local value = 0
	for name, count in built do
		if name:sub(1, #prefix) == prefix then
			value += count
		end
	end
	return value
end

describe("Accents on the shared step", function()
	it("a wiping crescent and a slash line build no sequence and no CFrame per frame", function()
		atHigh(function()
			local SlashArc = loadCounting("src/client/fx/SlashArc")
			SlashArc.bind(overrides)
			SlashArc.start()
			SlashArc.play(Vector3.new(0, 3, 0), Vector3.xAxis, Vector3.zAxis, "TrailCyanWhite", "Large")
			SlashArc.line(Vector3.new(0, 3, 0), Vector3.xAxis, "Large")
			local frames = 0
			while SlashArc.activeCount() + SlashArc.activeLines() > 0 do
				local built = frame()
				frames += 1
				expect(sum(built, "NumberSequence")).toBe(0)
				expect(sum(built, "CFrame")).toBe(0)
				expect(sum(built, "ColorSequence")).toBe(0)
				expect(frames < 60).toBe(true)
			end
			-- The whole life ran: the longer of the two, frame by frame.
			local size = accents.slashArc.sizes.Large
			local line = accents.slashLine.sizes.Large
			expect(frames).toBeGreaterThanOrEqual(
				math.max(size.holdFrames + size.wipeFrames, line.growFrames + line.holdFrames + line.thinFrames)
			)
			-- A second crescent on the warm pool builds no sequence on play either.
			table.clear(counts)
			SlashArc.play(Vector3.new(0, 3, 0), Vector3.xAxis, Vector3.zAxis, "TrailCyanWhite", "Medium")
			expect(total("NumberSequence")).toBe(0)
			SlashArc.reset()
		end)
	end)

	it("a glint builds nothing while it holds at full size and one size a frame while it moves", function()
		atHigh(function()
			local Glint = loadCounting("src/client/fx/Glint")
			Glint.bind(overrides)
			Glint.start()
			-- The parry's glint holds longest. Its first full-size frame sizes it; the rest of the
			-- hold builds nothing.
			local size = accents.glint.sizes.Parry
			Glint.play(Vector3.new(0, 3, 0), "Parry", "TrailCyanWhite")
			local holdStart = (size.punchFrames + 1) * F
			local holdEnd = (size.punchFrames + size.holdFrames) * F
			local playedAt = clock
			local held = 0
			while Glint.activeCount() > 0 do
				local built = frame()
				local elapsed = clock - playedAt
				if elapsed >= holdStart - 1e-9 and elapsed <= holdEnd - 1e-6 then
					held += 1
					expect(sum(built, "UDim2") + sum(built, "Vector2")).toBe(0)
				else
					expect(sum(built, "UDim2")).toBeLessThanOrEqual(1)
					expect(sum(built, "Vector2")).toBeLessThanOrEqual(1)
				end
				expect(sum(built, "NumberSequence")).toBe(0)
				expect(elapsed < 2).toBe(true)
			end
			expect(held).toBe(size.holdFrames - 1)
			Glint.reset()
		end)
	end)

	it("speed lines build nothing while they hold and lay a line only when it moves", function()
		atHigh(function()
			local SpeedLines = loadCounting("src/client/fx/SpeedLines")
			SpeedLines.bind(overrides)
			SpeedLines.start()
			local kind = accents.speedLines.kinds.Dodge
			SpeedLines.play("Dodge")
			local shown = #SpeedLines.view().lines
			expect(shown).toBeGreaterThan(0)
			local playedAt = clock
			local holdStart = kind.inFrames * F
			local holdEnd = kind.seconds - kind.outFrames * F
			local held = 0
			while SpeedLines.isShowing() do
				local built = frame()
				local elapsed = clock - playedAt
				-- Position and Size, at most, for each line it shows.
				expect(sum(built, "UDim2")).toBeLessThanOrEqual(2 * shown)
				if elapsed >= holdStart + F - 1e-9 and elapsed < holdEnd - 1e-6 then
					held += 1
					expect(sum(built, "UDim2")).toBe(0)
				end
				expect(sum(built, "NumberSequence")).toBe(0)
				expect(elapsed < 2).toBe(true)
			end
			expect(held).toBeGreaterThan(0)
			SpeedLines.reset()
		end)
	end)
end)
