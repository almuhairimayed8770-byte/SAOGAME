--!strict
--[[
	SmokeRunner (tools/smoke/SmokeRunner.luau): the runner tools/smoke.sh hands to run-in-roblox.
	The runner is executed here against a fake engine (workspace attributes, RunService,
	ScriptContext.Error, LogService.MessageOut, task.wait) to check that it installs the smoke
	script's exact source plus the done line as a server Script, starts the Run session, and prints
	PASS only when the script reached its last line, FAIL on the script's own error or its tagged
	check() failure, ignores errors from anything else, and times out.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local root = Harness.repoRoot()

local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path)
	local env = {
		require = function(_target: any)
			error("SmokeRunner must not require anything")
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local SmokeRunner = loadTool("tools/smoke/SmokeRunner.luau")

-- A smoke source with everything that could break the embedding: long-bracket closers of
-- several levels, template tokens, gsub replacement syntax and a trailing comment.
local TRICKY = table.concat({
	"--!strict",
	'local closers = "]] ]=] ]==]"',
	'local tokens = "{{SOURCE}} {{NAME}} %1 %%"',
	'workspace:SetAttribute("Ran", true) -- trailing comment',
}, "\n")

type Signal = { handlers: { (...any) -> () }, Connect: (any, (...any) -> ()) -> any, fire: (...any) -> () }

local function signal(): Signal
	local self = {} :: any
	self.handlers = {}
	function self.Connect(_: any, handler: (...any) -> ())
		table.insert(self.handlers, handler)
		return {
			Disconnect = function()
				local at = table.find(self.handlers, handler)
				if at then
					table.remove(self.handlers, at)
				end
			end,
		}
	end
	function self.fire(...)
		for _, handler in table.clone(self.handlers) do
			handler(...)
		end
	end
	return self
end

type Fake = {
	attributes: { [string]: any },
	printed: { string },
	installed: { [string]: any }?,
	ran: boolean,
	stopped: boolean,
	waited: number,
	scriptError: Signal,
	messageOut: Signal,
}

-- Runs a runner source against a fake engine. onRun is what "the server" does when the Run
-- session starts (the installed script finishing, erroring, or nothing at all).
local function execute(
	runner: string,
	onRun: (fake: Fake) -> (),
	preset: { [string]: any }?,
	errorLocked: boolean?,
	alreadyRunning: boolean?
): Fake
	local fake: Fake = {
		attributes = if preset then table.clone(preset) else {},
		printed = {},
		installed = nil,
		ran = false,
		stopped = false,
		waited = 0,
		scriptError = signal(),
		messageOut = signal(),
	}
	local workspace = {
		GetAttribute = function(_: any, name: string)
			return fake.attributes[name]
		end,
		SetAttribute = function(_: any, name: string, value: any)
			fake.attributes[name] = value
		end,
	}
	local services = {
		LogService = { MessageOut = fake.messageOut },
		ScriptContext = {
			Error = if errorLocked
				then {
					Connect = function()
						error("The current thread cannot connect 'Error' (lacking capability)", 0)
					end,
				}
				else fake.scriptError,
		},
		ServerScriptService = { Name = "ServerScriptService" },
		RunService = {
			IsRunning = function()
				return alreadyRunning == true
			end,
			Run = function()
				fake.ran = true
				onRun(fake)
			end,
			Stop = function()
				fake.stopped = true
			end,
		},
	}
	local env = {
		game = {
			GetService = function(_: any, name: string)
				return assert(services[name], "unexpected service " .. name)
			end,
		},
		workspace = workspace,
		Instance = {
			new = function(className: string)
				assert(className == "Script", "the runner only creates a Script")
				local instance = { ClassName = className } :: any
				function instance.GetFullName(self: any): string
					return (if self.Parent then self.Parent.Name .. "." else "") .. self.Name
				end
				fake.installed = instance
				return instance
			end,
		},
		Enum = { MessageType = { MessageError = "MessageError", MessageOutput = "MessageOutput" } },
		task = {
			wait = function(seconds: number): number
				fake.waited += seconds
				if fake.waited > 1e5 then
					error("the runner never stopped waiting", 0)
				end
				return seconds
			end,
		},
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring(select(i, ...)))
			end
			table.insert(fake.printed, table.concat(parts, " "))
		end,
		string = string,
		pcall = pcall,
		tostring = tostring,
	}
	luau.load(runner, { debugName = "runner", environment = env :: any })()
	return fake
end

local function resultLine(fake: Fake): string?
	for _, line in fake.printed do
		if
			line:sub(1, #SmokeRunner.resultPrefix + 5) == SmokeRunner.resultPrefix .. " PASS"
			or line:sub(1, #SmokeRunner.resultPrefix + 5) == SmokeRunner.resultPrefix .. " FAIL"
		then
			return line
		end
	end
	return nil
end

-- What the installed script does when it runs to the end: its own body, then the done line.
local function runInstalled(fake: Fake)
	local installed = assert(fake.installed, "the runner installed no Script")
	local env = {
		workspace = {
			GetAttribute = function(_: any, name: string)
				return fake.attributes[name]
			end,
			SetAttribute = function(_: any, name: string, value: any)
				fake.attributes[name] = value
			end,
		},
	}
	luau.load(installed.Source, { debugName = "installed", environment = env :: any })()
end

describe("SmokeRunner naming and embedding", function()
	it("names a smoke script by its file name without .luau, on either separator", function()
		expect(SmokeRunner.nameOf("tests/smoke/combat.smoke.luau")).toBe("combat.smoke")
		expect(SmokeRunner.nameOf("tests\\smoke\\perf.smoke.luau")).toBe("perf.smoke")
		expect(SmokeRunner.nameOf("rigs.smoke.luau")).toBe("rigs.smoke")
	end)

	it("picks the shortest long-bracket level the source does not close", function()
		expect(SmokeRunner.bracketLevel("print(1)")).toBe(0)
		expect(SmokeRunner.bracketLevel("a]]b")).toBe(1)
		expect(SmokeRunner.bracketLevel(TRICKY)).toBe(3)
	end)

	it("embeds the source byte for byte, first line included", function()
		local literal = SmokeRunner.longString(TRICKY)
		local value = luau.load("return " .. literal, { debugName = "literal" })()
		expect(value).toBe(TRICKY)
		local leadingNewline = "\nprint(1)\n"
		local again = luau.load("return " .. SmokeRunner.longString(leadingNewline), { debugName = "nl" })()
		expect(again).toBe(leadingNewline)
	end)

	it("writes a runner that compiles, names its source and carries every field", function()
		local runner = SmokeRunner.build({ path = "tests/smoke/tricky.smoke.luau", source = TRICKY })
		expect(function()
			luau.compile(runner)
		end).never.toThrow()
		expect(runner).toContain("from tests/smoke/tricky.smoke.luau")
		expect(runner).toContain('local NAME = "tricky.smoke"')
		expect(runner).toContain(("local TIMEOUT = %d"):format(SmokeRunner.defaultTimeoutSeconds))
		for _, token in { "{{PATH}}", "{{PREFIX}}", "{{DONE}}", "{{TIMEOUT}}", "{{POLL}}", "{{DONE_LINE}}" } do
			expect(runner).never.toContain(token)
		end
	end)

	it("wraps every smoke script under tests/smoke into a runner that compiles", function()
		local files = Harness.listFiles("tests/smoke", "%.smoke%.luau$")
		expect(#files > 0).toBe(true)
		for _, file in files do
			local source = Harness.readFile(file)
			-- The smoke script itself must parse: it only ever runs on a machine with Studio.
			expect(function()
				luau.compile(source)
			end).never.toThrow()
			local runner = SmokeRunner.build({ path = file, source = source })
			expect(function()
				luau.compile(runner)
			end).never.toThrow()
			-- The done line is appended after the last line, so a top-level return would hide it.
			expect(source:match("\nreturn[%s%(]") == nil).toBe(true)
		end
	end)

	it("rejects a smoke script that returns at top level, and allows nested returns", function()
		expect(SmokeRunner.hasTopLevelReturn("print(1)\nreturn nil\n")).toBe(true)
		expect(SmokeRunner.hasTopLevelReturn("return")).toBe(true)
		expect(SmokeRunner.hasTopLevelReturn("local function f()\n\treturn 1\nend\n")).toBe(false)
		expect(SmokeRunner.hasTopLevelReturn("local returned = 1\nreturnValue = 2\n")).toBe(false)
		expect(function()
			SmokeRunner.build({ path = "tests/smoke/bad.smoke.luau", source = "print(1)\nreturn true\n" })
		end).toThrow("returns at top level")
	end)

	it("rejects a non-positive timeout", function()
		expect(function()
			SmokeRunner.build({ path = "x.smoke.luau", source = "", timeoutSeconds = 0 })
		end).toThrow("timeoutSeconds")
	end)
end)

describe("SmokeRunner against a fake engine", function()
	local path = "tests/smoke/tricky.smoke.luau"

	it("installs the exact source plus the done line as a server Script and passes when it finishes", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY })
		local fake = execute(runner, runInstalled)
		local installed = assert(fake.installed, "the runner installed no Script")
		expect(installed.Name).toBe("tricky.smoke")
		expect(installed.Parent.Name).toBe("ServerScriptService")
		expect(installed.Source).toBe(TRICKY .. SmokeRunner.doneLine())
		expect(fake.ran).toBe(true)
		expect(fake.attributes.Ran).toBe(true)
		expect(fake.attributes[SmokeRunner.doneAttribute]).toBe(true)
		expect(resultLine(fake)).toBe(SmokeRunner.resultPrefix .. " PASS tricky.smoke")
		expect(fake.stopped).toBe(true)
	end)

	it("clears a done attribute left from an earlier run before starting", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY, timeoutSeconds = 1 })
		-- The attribute is still true from an earlier run and this run's script never finishes.
		local fake = execute(runner, function(_fake) end, { [SmokeRunner.doneAttribute] = true })
		expect(resultLine(fake) :: string).toContain("FAIL tricky.smoke: timed out")
	end)

	it("fails with the message and trace of an error raised by the installed script", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY })
		local fake = execute(runner, function(f)
			f.scriptError.fire("attempt to index nil", "Script 'tricky.smoke', Line 3", f.installed)
		end)
		local line = resultLine(fake) :: string
		expect(line).toContain("FAIL tricky.smoke: attempt to index nil")
		expect(line).toContain("Line 3")
		expect(fake.waited).toBe(0)
	end)

	it("fails on an error raised in a module the script called (origin is the module)", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY })
		local fake = execute(runner, function(f)
			f.scriptError.fire(
				"ServerScriptService.Server.services.EnemyService:88: attempt to index nil",
				"ServerScriptService.Server.services.EnemyService, line 88\nServerScriptService.tricky.smoke, line 12",
				{ Name = "EnemyService" }
			)
		end)
		expect(resultLine(fake) :: string).toContain(
			"FAIL tricky.smoke: ServerScriptService.Server.services.EnemyService:88"
		)
	end)

	it("never installs or runs a second copy when loaded inside a running session", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY })
		expect(function()
			execute(runner, runInstalled, nil, nil, true)
		end).toThrow("never stopped waiting")
	end)

	it("fails on the script's own tagged check() failure in the output", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY })
		local fake = execute(runner, function(f)
			f.messageOut.fire("[tricky.smoke] FAILED: server services are up", "MessageError")
		end)
		expect(resultLine(fake) :: string).toContain("FAIL tricky.smoke: [tricky.smoke] FAILED: server services are up")
	end)

	it("ignores errors from other scripts and plugins, and tagged lines that are not errors", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY })
		local fake = execute(runner, function(f)
			f.scriptError.fire("debug.profileEnd() - No active profile annotation", "MaterialManager", {})
			f.messageOut.fire("ContentId failed: Asset type does not match requested type", "MessageError")
			f.messageOut.fire("[tricky.smoke] ok: server services are up", "MessageOutput")
			runInstalled(f)
		end)
		expect(resultLine(fake)).toBe(SmokeRunner.resultPrefix .. " PASS tricky.smoke")
	end)

	it("fails with the reason when the Run session cannot start", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY })
		local fake = execute(runner, function(_f)
			error("Run is not available", 0)
		end)
		expect(resultLine(fake) :: string).toContain(
			"FAIL tricky.smoke: could not start a Run session: Run is not available"
		)
		expect(fake.waited).toBe(0)
	end)

	it("still catches tagged failures when ScriptContext.Error cannot be connected", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY })
		local fake = execute(runner, function(f)
			f.messageOut.fire("[tricky.smoke] FAILED: the boar telegraphs", "MessageError")
		end, nil, true)
		expect(resultLine(fake) :: string).toContain("FAIL tricky.smoke: [tricky.smoke] FAILED: the boar telegraphs")
		local noted = false
		for _, line in fake.printed do
			if line:find("ScriptContext.Error unavailable", 1, true) then
				noted = true
			end
		end
		expect(noted).toBe(true)
	end)

	it("times out when the script neither finishes nor fails", function()
		local runner = SmokeRunner.build({ path = path, source = TRICKY, timeoutSeconds = 2 })
		local fake = execute(runner, function(_f) end)
		expect(resultLine(fake) :: string).toContain("FAIL tricky.smoke: timed out after 2 s")
		expect(fake.waited).toBeGreaterThanOrEqual(2)
		expect(fake.waited).toBeLessThan(2 + SmokeRunner.pollSeconds * 2)
		expect(fake.stopped).toBe(true)
	end)
end)
