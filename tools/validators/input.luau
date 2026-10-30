--!strict
--[[
	Validates src/shared/data/input.luau: every action has keyboard and gamepad bindings whose
	names are real Enum.KeyCode / Enum.UserInputType members, no key is bound twice on one device,
	the section 6 bindings are in place, the cancel time is the combat.luau number, the touch
	layout has a button for every section 14 action, and the remappable list only names actions.
]]

local roblox = require("@lune/roblox")

return function(ctx: any): { string }
	local problems = {}
	local function check(ok: boolean, message: string)
		if not ok then
			table.insert(problems, "input: " .. message)
		end
	end

	local input = ctx.load("src/shared/data/input")
	local combat = ctx.load("src/shared/data/combat")

	local function codeExists(name: string): boolean
		local enum = if name:match("^Mouse") then roblox.Enum.UserInputType else roblox.Enum.KeyCode
		local ok, item = pcall(function()
			return (enum :: any)[name]
		end)
		return ok and item ~= nil
	end

	local actionSet: { [string]: boolean } = {}
	for _, action in input.actions do
		actionSet[action] = true
	end

	for _, device in { "keyboard", "gamepad" } do
		local bindings = input[device]
		local used: { [string]: string } = {}
		for _, action in input.actions do
			local names = bindings[action]
			check(typeof(names) == "table" and #names > 0, ("%s has no %s binding"):format(action, device))
			for _, name in names or {} do
				check(codeExists(name), ("%s.%s names an unknown key '%s'"):format(device, action, name))
				check(
					used[name] == nil,
					("%s key '%s' is bound to both %s and %s"):format(device, name, tostring(used[name]), action)
				)
				used[name] = action
			end
		end
		for action in bindings do
			check(actionSet[action] == true, ("%s binds an action '%s' that is not in actions"):format(device, action))
		end
	end

	-- Section 6 bindings.
	local expected = {
		keyboard = {
			BasicAttack = "MouseButton1",
			Art = "Q",
			Guard = "MouseButton2",
			Dodge = "Space",
			SwitchCall = "Tab",
			LockOn = "F",
			Interact = "E",
			QuickSlotRing = "R",
			Sprint = "LeftShift",
		},
		gamepad = {
			BasicAttack = "ButtonR2",
			Guard = "ButtonL2",
			Dodge = "ButtonB",
			SwitchCall = "ButtonL1",
			LockOn = "ButtonR3",
			Interact = "ButtonX",
			Sprint = "ButtonL3",
		},
	}
	for device, table_ in expected do
		for action, name in table_ do
			local names = input[device][action] or {}
			check(table.find(names, name) ~= nil, ("section 6 says %s.%s is %s"):format(device, action, name))
		end
	end

	check(input.art.cancelTime == combat.activationCancelTime, "art.cancelTime must be combat.activationCancelTime")
	check(input.art.slots >= 1 and input.art.defaultSlot == 1, "art.slots must be at least 1 and the default slot 1")
	check(input.artSlot("Art") == 1, "artSlot('Art') must be slot 1")
	for slot = 2, input.art.slots do
		check(input.artSlot("ArtSlot" .. slot) == slot, ("artSlot('ArtSlot%d') must be %d"):format(slot, slot))
	end
	check(input.dodge.inputDeadzone >= 0 and input.dodge.inputDeadzone < 1, "dodge.inputDeadzone must be in [0, 1)")

	for _, mode in { "keyboard", "gamepad", "touch" } do
		local value = input.sprintMode[mode]
		check(value == "Hold" or value == "Toggle", ("sprintMode.%s must be Hold or Toggle"):format(mode))
	end

	local okPriority = pcall(function()
		return (roblox.Enum.ContextActionPriority :: any)[input.priority]
	end)
	check(okPriority, ("priority '%s' is not a ContextActionPriority"):format(tostring(input.priority)))

	for _, action in { "BasicAttack", "Art", "Guard", "Dodge", "SwitchCall" } do
		check(input.touch.buttons[action] ~= nil, ("section 14 needs a touch button for %s"):format(action))
	end
	for action, button in input.touch.buttons do
		check(actionSet[action] == true, ("touch button '%s' is not an action"):format(action))
		check(
			button.size > 0 and button.x > 0 and button.y > 0,
			("touch button %s needs positive size and offsets"):format(action)
		)
		check(typeof(button.label) == "string" and #button.label > 0, ("touch button %s needs a label"):format(action))
	end
	check(
		input.touch.backgroundTransparency >= 0 and input.touch.backgroundTransparency <= 1,
		"touch.backgroundTransparency must be in 0..1"
	)
	check(input.touch.heldTransparency < input.touch.backgroundTransparency, "a held touch button must be more opaque")

	for _, action in input.remappable do
		check(actionSet[action] == true, ("remappable names an unknown action '%s'"):format(action))
	end
	for _, action in input.actions do
		check(typeof(input.displayNames[action]) == "string", ("%s has no display name"):format(action))
	end

	-- HUD key labels (section 14: the Art list shows each Art's key).
	for name, label in input.keyLabels do
		check(codeExists(name), ("keyLabels names an unknown key '%s'"):format(tostring(name)))
		check(typeof(label) == "string" and #label > 0, ("keyLabels.%s must be a non-empty string"):format(name))
	end
	check(input.keyLabel("Art", "keyboard") == "Q", "keyLabel('Art', 'keyboard') must read Q")
	for slot = 2, input.art.slots do
		local label = input.keyLabel("ArtSlot" .. slot, "keyboard")
		check(typeof(label) == "string" and #label > 0, ("Art slot %d needs a keyboard label"):format(slot))
	end
	check(input.keyLabel("Nope", "keyboard") == "", "keyLabel of an unbound action must be empty")

	return problems
end
