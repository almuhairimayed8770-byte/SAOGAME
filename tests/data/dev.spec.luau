--!strict
-- dev.luau's helpers that the dev tools show on screen.
local Dev = Harness.load("src/shared/data/dev")

describe("dev.luau time-scale label", function()
	it("says at 1x only the scale, and below it that only animation slows", function()
		expect(Dev.timeScaleLabel(1)).toBe("Time scale 1x")
		for _, scale in Dev.timeScale.steps do
			if scale ~= 1 then
				local text = Dev.timeScaleLabel(scale)
				expect(text:find(("%gx"):format(scale), 1, true)).never.toBeNil()
				expect(text:find(Dev.timeScale.slowNote, 1, true)).never.toBeNil()
			end
		end
		expect(Dev.timeScaleLabel(0.25)).toBe("Time scale 0.25x (animation only: hit FX and sounds run at 1x)")
	end)

	it("the Capture panel shows that label", function()
		local source = Harness.readFile("src/client/dev/Capture.client.luau")
		expect(source:find("scaleLabel.Text = Dev.timeScaleLabel(Steps[timeScaleIndex])", 1, true)).never.toBeNil()
	end)
end)

-- ------------------------------------------------------------------------------------------
-- The Studio dev hooks (D-114): aim (DevAim.client) and trace (DevCombat.server)
-- ------------------------------------------------------------------------------------------

local luau = require("@lune/luau")

local VALIDATOR = "tools/validators/dev.luau"

local function runValidator(mutate: ((dev: any) -> ())?): { string }
	local validator =
		luau.load(Harness.readFile(VALIDATOR), { debugName = VALIDATOR, environment = {} :: any })() :: (any) -> { string }
	local copy = Dev
	if mutate ~= nil then
		local function deepCopy(value: any): any
			if typeof(value) ~= "table" then
				return value
			end
			local out = {}
			for key, inner in value do
				out[key] = deepCopy(inner)
			end
			return setmetatable(out, getmetatable(value))
		end
		copy = deepCopy(Dev)
		mutate(copy)
	end
	return validator({
		load = function(path: string): any
			if path == "src/shared/data/dev" then
				return copy
			end
			return Harness.load(path)
		end,
		listFiles = Harness.listFiles,
		readFile = Harness.readFile,
		repoRoot = Harness.repoRoot(),
	})
end

local function hasProblem(problems: { string }, needle: string): boolean
	for _, line in problems do
		if line:find(needle, 1, true) then
			return true
		end
	end
	return false
end

describe("dev.luau aim and trace", function()
	it("passes the dev validator as written", function()
		expect(table.concat(runValidator(nil), "\n")).toBe("")
	end)

	it("names a BindableFunction for each helper, and they differ", function()
		expect(typeof(Dev.aim.bindableName)).toBe("string")
		expect(typeof(Dev.trace.bindableName)).toBe("string")
		expect(Dev.aim.bindableName).never.toBe(Dev.trace.bindableName)
	end)

	type Case = { name: string, needle: string, mutate: (any) -> () }
	local cases: { Case } = {
		{
			name = "a missing aim table",
			needle = "aim table is missing",
			mutate = function(d)
				d.aim = nil
			end,
		},
		{
			name = "a face tolerance the swing's snap cannot finish",
			needle = "combat.aim.snapDegrees",
			mutate = function(d)
				d.aim.faceToleranceDegrees = 45
			end,
		},
		{
			name = "a face tolerance past the server's facing acceptance",
			needle = "facing acceptance",
			mutate = function(d)
				d.aim.faceToleranceDegrees = 50
			end,
		},
		{
			name = "a face timeout shorter than the lock turn",
			needle = "lock turn from straight behind",
			mutate = function(d)
				d.aim.faceTimeoutSeconds = 0.2
			end,
		},
		{
			name = "a dev turn too slow for the face timeout",
			needle = "dev turn from straight behind",
			mutate = function(d)
				d.aim.faceDegreesPerSecond = 90
			end,
		},
		{
			name = "a settle shorter than the lag allowance",
			needle = "replicationSettleSeconds",
			mutate = function(d)
				d.aim.replicationSettleSeconds = 0.1
			end,
		},
		{
			name = "an action settle shorter than the lag allowance",
			needle = "actionSettleSeconds",
			mutate = function(d)
				d.aim.actionSettleSeconds = 0.1
			end,
		},
		{
			name = "an Art hold inside the start pose",
			needle = "start pose and activation hold",
			mutate = function(d)
				d.aim.artHoldSeconds = 0.2
			end,
		},
		{
			name = "an Art hold past the cancel time",
			needle = "activationCancelTime",
			mutate = function(d)
				d.aim.artHoldSeconds = 1.2
			end,
		},
		{
			name = "a swing gap faster than the request's refill",
			needle = "refill",
			mutate = function(d)
				d.aim.swingGapSeconds = 0.1
			end,
		},
		{
			name = "a swing gap inside the server's basic swing",
			needle = "basicHitDuration",
			mutate = function(d)
				d.aim.swingGapSeconds = 0.3
			end,
		},
		{
			name = "a swing gap that misses the window's hit",
			needle = "latest basic hit window",
			mutate = function(d)
				d.aim.swingGapSeconds = 0.37
			end,
		},
		{
			name = "a swing gap that breaks the chain",
			needle = "basicChainWindow",
			mutate = function(d)
				d.aim.swingGapSeconds = 0.7
			end,
		},
		{
			name = "a client run timeout shorter than the longest Art",
			needle = "aim.runTimeoutSeconds",
			mutate = function(d)
				d.aim.runTimeoutSeconds = 1.5
			end,
		},
		{
			name = "a server run timeout shorter than the longest Art",
			needle = "trace.runTimeoutSeconds",
			mutate = function(d)
				d.trace.runTimeoutSeconds = 1
			end,
		},
		{
			name = "a swing cap under one chain",
			needle = "aim.maxSwings",
			mutate = function(d)
				d.aim.maxSwings = 2
			end,
		},
		{
			name = "a fractional swing cap",
			needle = "aim.maxSwings",
			mutate = function(d)
				d.aim.maxSwings = 3.5
			end,
		},
		{
			name = "a trace buffer that drops a whole command's windows",
			needle = "trace.keepEvents",
			mutate = function(d)
				d.trace.keepEvents = 5
			end,
		},
		{
			name = "one name for both helpers",
			needle = "must differ",
			mutate = function(d)
				d.trace.bindableName = d.aim.bindableName
			end,
		},
		{
			name = "a name that is not a plain instance name",
			needle = "aim.bindableName must be",
			mutate = function(d)
				d.aim.bindableName = "Dev Aim"
			end,
		},
		{
			name = "a negative rounding",
			needle = "aim.decimals",
			mutate = function(d)
				d.aim.decimals = -1
			end,
		},
		{
			name = "an empty print prefix",
			needle = "printPrefix",
			mutate = function(d)
				d.trace.printPrefix = ""
			end,
		},
	}
	for _, case in cases do
		it(("catches %s"):format(case.name), function()
			local problems = runValidator(case.mutate)
			if not hasProblem(problems, case.needle) then
				error(("expected a problem with '%s', got:\n%s"):format(case.needle, table.concat(problems, "\n")), 0)
			end
		end)
	end
end)

describe("dev.luau timeScale steps", function()
	-- The capture slows the local body with these (CharacterController.setCaptureTimeScale), so a
	-- step past 1x would move it faster than the anti-cheat's cap allows.
	it("every step is above 0 and at most 1, and the default is one of them", function()
		for _, bad in { 0, -0.5, 1.5, 0 / 0, "0.5" } do
			local problems = runValidator(function(dev: any)
				dev.timeScale.steps = { 1, bad }
			end)
			expect(hasProblem(problems, "timeScale.steps")).toBe(true)
		end
		expect(hasProblem(
			runValidator(function(dev: any)
				dev.timeScale.steps = {}
			end),
			"timeScale.steps"
		)).toBe(true)
		expect(hasProblem(
			runValidator(function(dev: any)
				dev.timeScale.default = 0.75
			end),
			"timeScale.default"
		)).toBe(true)
	end)
end)
