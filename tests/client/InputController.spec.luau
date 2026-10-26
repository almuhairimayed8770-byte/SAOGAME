--!strict
--[[
	InputController's sprint, held per source (D-338). The player's own key (Shift, held; the pad's
	and the screen's button, toggled, input.luau sprintMode) is one source; the capture panel's
	auto-walk and auto-perform press the sprint through the same input path as another source
	(InputController.handle's fourth argument). Sprint is on while any source holds it, and
	sprintChanged fires only when that changes, so a Shift tap during the panel's sprinted walk
	leaves the walk's sprint on (the single sprint flag round C left open), and the player alone sprints exactly as
	before: the first case pins that.

	The real module, loaded fresh for each case with no services bound (start is never called).
]]

local luau = require("@lune/luau")

local CONTROLLER_PATH = "src/client/controllers/InputController"
local PANEL = "CapturePanel"

type Input = {
	handle: (action: string, state: Enum.UserInputState, object: any, source: string?) -> (),
	isSprinting: () -> boolean,
	sprintChanged: any,
}

local function load(): (Input, { boolean })
	local services: { [string]: any } = {
		ReplicatedStorage = Harness.game():GetService("ReplicatedStorage"),
	}
	local env = Harness.environment()
	env.script = Harness.node(CONTROLLER_PATH)
	env.require = function(target: any): any
		return Harness.loadModule(target)
	end
	env.game = {
		GetService = function(_self: any, name: string): any
			return services[name] or {}
		end,
	}
	local input = luau.load(
		Harness.readFile(CONTROLLER_PATH .. ".luau"),
		{ debugName = CONTROLLER_PATH, environment = env :: any }
	)() :: Input
	local fired: { boolean } = {}
	input.sprintChanged:Connect(function(on: boolean)
		table.insert(fired, on)
	end)
	return input, fired
end

local KEYBOARD = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.LeftShift }
local GAMEPAD = { UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonL3 }
local TOUCH = { UserInputType = Enum.UserInputType.Touch }

local BEGIN = Enum.UserInputState.Begin
local END = Enum.UserInputState.End
local CANCEL = Enum.UserInputState.Cancel

describe("InputController sprint held per source (D-338)", function()
	it("sprints the player alone as before: Shift holds it, the pad's and the screen's button toggle it", function()
		local input, fired = load()
		local steps: { { object: any, state: Enum.UserInputState, on: boolean } } = {
			{ object = KEYBOARD, state = BEGIN, on = true },
			{ object = KEYBOARD, state = BEGIN, on = true }, -- a repeat changes nothing
			{ object = KEYBOARD, state = END, on = false },
			{ object = GAMEPAD, state = BEGIN, on = true },
			{ object = GAMEPAD, state = END, on = true }, -- a toggle's let-go changes nothing
			{ object = GAMEPAD, state = BEGIN, on = false },
			{ object = TOUCH, state = BEGIN, on = true },
			{ object = KEYBOARD, state = BEGIN, on = true },
			{ object = KEYBOARD, state = END, on = false }, -- the key's let-go ends a toggled sprint
			{ object = TOUCH, state = BEGIN, on = true },
			{ object = GAMEPAD, state = BEGIN, on = false }, -- any toggle flips the player's sprint
			{ object = KEYBOARD, state = BEGIN, on = true },
			{ object = KEYBOARD, state = CANCEL, on = false },
			{ object = KEYBOARD, state = END, on = false },
		}
		for index, step in steps do
			input.handle("Sprint", step.state, step.object)
			expect(("%d %s"):format(index, tostring(input.isSprinting()))).toBe(
				("%d %s"):format(index, tostring(step.on))
			)
		end
		expect(fired).toEqual({ true, false, true, false, true, false, true, false, true, false })
	end)

	it("keeps the panel's sprint on through a Shift tap, off once the panel lets go", function()
		local input, fired = load()
		input.handle("Sprint", BEGIN, nil, PANEL)
		expect(input.isSprinting()).toBe(true)
		input.handle("Sprint", BEGIN, KEYBOARD)
		input.handle("Sprint", END, KEYBOARD)
		expect(input.isSprinting()).toBe(true)
		expect(fired).toEqual({ true })
		input.handle("Sprint", END, nil, PANEL)
		expect(input.isSprinting()).toBe(false)
		expect(fired).toEqual({ true, false })
	end)

	it("keeps the player's held Shift sprinting when the panel lets go of its own", function()
		local input, fired = load()
		input.handle("Sprint", BEGIN, KEYBOARD)
		input.handle("Sprint", BEGIN, nil, PANEL)
		input.handle("Sprint", END, nil, PANEL)
		expect(input.isSprinting()).toBe(true)
		expect(fired).toEqual({ true })
		input.handle("Sprint", END, KEYBOARD)
		expect(input.isSprinting()).toBe(false)
		expect(fired).toEqual({ true, false })
	end)

	it("turns the player's own toggle on under the panel's sprint, kept once the panel lets go", function()
		local input, fired = load()
		input.handle("Sprint", BEGIN, nil, PANEL)
		input.handle("Sprint", BEGIN, GAMEPAD)
		expect(input.isSprinting()).toBe(true)
		input.handle("Sprint", END, nil, PANEL)
		expect(input.isSprinting()).toBe(true)
		input.handle("Sprint", BEGIN, GAMEPAD)
		expect(input.isSprinting()).toBe(false)
		expect(fired).toEqual({ true, false })
	end)

	it("ignores a let-go from a source that holds nothing; a Cancel ends that source's hold", function()
		local input, fired = load()
		input.handle("Sprint", END, nil, PANEL)
		input.handle("Sprint", CANCEL, KEYBOARD)
		expect(input.isSprinting()).toBe(false)
		expect(fired).toEqual({})
		input.handle("Sprint", BEGIN, nil, PANEL)
		input.handle("Sprint", BEGIN, nil, PANEL)
		input.handle("Sprint", CANCEL, nil, PANEL)
		expect(input.isSprinting()).toBe(false)
		expect(fired).toEqual({ true, false })
	end)
end)
