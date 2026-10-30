--!strict
--[[
	The ClipLab's hotkeys bind above the default character scripts (LabKeys, D-413). Those scripts
	bind the arrows and Space through ContextActionService to move and jump, so the lab's keys
	read off UserInputService (the arrows pick a clip and orbit the camera, Space pauses) also
	walked or jumped the player's character on the PlayerR15 pedestal, under the review. Every lab
	key is bound at dev.luau clipLab.actionPriority, above the default, and sinks its input; the
	ClipLab binds through LabKeys and reads no key off UserInputService.
]]

local fs = require("@lune/fs")

local Dev = Harness.load("src/shared/data/dev")
local LabKeys = Harness.load("src/client/dev/LabKeys")

local Lab = Dev.clipLab

-- A ContextActionService that records each binding.
local function fakeService()
	local bound: { [string]: { handler: any, priority: number, codes: { any } } } = {}
	local service = {}
	function service:BindActionAtPriority(name: string, handler: any, _touch: boolean, priority: number, ...: any)
		bound[name] = { handler = handler, priority = priority, codes = { ... } }
	end
	return service, bound
end

describe("LabKeys: the ClipLab's hotkeys", function()
	it("binds every hotkey above the default character scripts' priority", function()
		local priority = (Enum.ContextActionPriority :: any)[Lab.actionPriority].Value
		expect(priority > Enum.ContextActionPriority.Medium.Value).toBe(true)
		local service, bound = fakeService()
		local bindings: { [any]: any } = {}
		for _, name in Lab.hotkeys do
			bindings[(Enum.KeyCode :: any)[name]] = { pressed = function() end }
		end
		local names = LabKeys.bind(service, "ClipLab", priority, bindings)
		local count = 0
		for _ in Lab.hotkeys do
			count += 1
		end
		expect(#names).toBe(count)
		for _, name in names do
			expect(bound[name].priority).toBe(priority)
			expect(#bound[name].codes).toBe(1)
		end
		-- The keys the character scripts bind are among them.
		for _, key in { "Up", "Down", "Left", "Right", "Space" } do
			expect(bound["ClipLab" .. key]).never.toBeNil()
		end
	end)

	it("runs a pressed key once on its way down and sinks every input on it", function()
		local service, bound = fakeService()
		local presses = 0
		LabKeys.bind(service, "ClipLab", 3000, {
			[Enum.KeyCode.Space] = {
				pressed = function()
					presses += 1
				end,
			},
		})
		local handler = bound.ClipLabSpace.handler
		for _, state in { Enum.UserInputState.Begin, Enum.UserInputState.End, Enum.UserInputState.Cancel } do
			expect(handler("ClipLabSpace", state, nil)).toBe(Enum.ContextActionResult.Sink)
		end
		expect(presses).toBe(1)
	end)

	it("holds a held key from its way down until it comes up or is taken", function()
		local service, bound = fakeService()
		local downs: { boolean } = {}
		LabKeys.bind(service, "ClipLab", 3000, {
			[Enum.KeyCode.Left] = {
				held = function(down: boolean)
					table.insert(downs, down)
				end,
			},
		})
		local handler = bound.ClipLabLeft.handler
		handler("ClipLabLeft", Enum.UserInputState.Begin, nil)
		handler("ClipLabLeft", Enum.UserInputState.End, nil)
		handler("ClipLabLeft", Enum.UserInputState.Begin, nil)
		handler("ClipLabLeft", Enum.UserInputState.Cancel, nil)
		expect(downs).toEqual({ true, false, true, false })
	end)

	it("is how the ClipLab reads its keys: no key off UserInputService", function()
		local source = fs.readFile(Harness.repoRoot() .. "/src/client/dev/ClipLab.client.luau")
		expect(source:find("LabKeys.bind(", 1, true)).never.toBeNil()
		expect(source:find("UserInputService", 1, true)).toBeNil()
		expect(source:find("Lab.actionPriority", 1, true)).never.toBeNil()
	end)
end)
