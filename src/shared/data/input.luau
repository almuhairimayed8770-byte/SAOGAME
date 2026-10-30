--!strict
--[[
	Input bindings (section 6) for keyboard and mouse, gamepad and touch, plus the mobile button
	layout (section 14). Key names are Enum.KeyCode names; mouse buttons are Enum.UserInputType
	names. InputController resolves them through Enum at bind time, so this table loads in Lune.

	Art slots: slot 1 is the Q key; slots 2 to 4 are the number keys. The hold-to-cancel time is
	the section 6 number in combat.luau. Sprint is hold on keyboard, toggle on gamepad and touch.
]]

local Combat = require(script.Parent.combat)

export type Action =
	"BasicAttack"
	| "Art"
	| "ArtSlot2"
	| "ArtSlot3"
	| "ArtSlot4"
	| "Guard"
	| "Dodge"
	| "SwitchCall"
	| "LockOn"
	| "Interact"
	| "QuickSlotRing"
	| "Sprint"

export type TouchButton = {
	x: number, -- pixels from the right edge to the button center
	y: number, -- pixels from the bottom edge to the button center
	size: number, -- pixels, square
	label: string,
}

local Input = {
	-- Every action, in binding order.
	actions = {
		"BasicAttack",
		"Art",
		"ArtSlot2",
		"ArtSlot3",
		"ArtSlot4",
		"Guard",
		"Dodge",
		"SwitchCall",
		"LockOn",
		"Interact",
		"QuickSlotRing",
		"Sprint",
	} :: { Action },

	keyboard = {
		BasicAttack = { "MouseButton1" },
		Art = { "Q" },
		ArtSlot2 = { "Two" },
		ArtSlot3 = { "Three" },
		ArtSlot4 = { "Four" },
		Guard = { "MouseButton2" },
		Dodge = { "Space" },
		SwitchCall = { "Tab" },
		LockOn = { "F" },
		Interact = { "E" },
		QuickSlotRing = { "R" },
		Sprint = { "LeftShift" },
	} :: { [Action]: { string } },

	gamepad = {
		BasicAttack = { "ButtonR2" },
		Art = { "ButtonR1" },
		ArtSlot2 = { "ButtonY" },
		ArtSlot3 = { "DPadUp" },
		ArtSlot4 = { "DPadRight" },
		Guard = { "ButtonL2" },
		Dodge = { "ButtonB" },
		SwitchCall = { "ButtonL1" },
		LockOn = { "ButtonR3" },
		Interact = { "ButtonX" },
		QuickSlotRing = { "DPadLeft" },
		Sprint = { "ButtonL3" },
	} :: { [Action]: { string } },

	-- "Hold" sprints while the key is down; "Toggle" flips on each press.
	sprintMode = {
		keyboard = "Hold",
		gamepad = "Toggle",
		touch = "Toggle",
	},

	art = {
		cancelTime = Combat.activationCancelTime, -- holding past this cancels the Art
		slots = 4,
		defaultSlot = 1, -- the Q key
	},

	dodge = {
		inputDeadzone = 0.2, -- move input below this magnitude dodges straight back
	},

	-- ContextActionService priority name; above the default character scripts so Space is a dodge.
	priority = "High",

	touch = {
		-- Buttons anchor to the bottom-right corner (section 14: left stick, right-side actions).
		buttons = {
			BasicAttack = { x = 90, y = 90, size = 88, label = "ATTACK" },
			Art = { x = 196, y = 66, size = 72, label = "ART" },
			Dodge = { x = 66, y = 196, size = 72, label = "DODGE" },
			Guard = { x = 182, y = 170, size = 64, label = "GUARD" },
			SwitchCall = { x = 276, y = 120, size = 56, label = "SWITCH" },
			LockOn = { x = 250, y = 224, size = 48, label = "LOCK" },
		} :: { [Action]: TouchButton },
		backgroundTransparency = 0.45,
		heldTransparency = 0.15,
		textSize = 14,
		cornerRadius = 0.5, -- UICorner scale: round buttons
		tapAttack = true, -- a tap on the world (not on a button) is a basic attack
		zIndexBehavior = "Sibling",
	},

	-- Actions the settings menu may rebind (section 14: remappable keys).
	remappable = {
		"BasicAttack",
		"Art",
		"ArtSlot2",
		"ArtSlot3",
		"ArtSlot4",
		"Guard",
		"Dodge",
		"SwitchCall",
		"LockOn",
		"Interact",
		"QuickSlotRing",
		"Sprint",
	} :: { Action },

	displayNames = {
		BasicAttack = "Attack",
		Art = "Art (slot 1)",
		ArtSlot2 = "Art slot 2",
		ArtSlot3 = "Art slot 3",
		ArtSlot4 = "Art slot 4",
		Guard = "Guard / Parry",
		Dodge = "Dodge",
		SwitchCall = "Switch call",
		LockOn = "Lock target",
		Interact = "Interact",
		QuickSlotRing = "Quick-slot ring",
		Sprint = "Sprint",
	} :: { [Action]: string },

	-- Short labels for the HUD (section 14: the equipped Arts with their keys). Key names that are
	-- not listed here are shown as they are ("Q", "F").
	keyLabels = {
		MouseButton1 = "LMB",
		MouseButton2 = "RMB",
		MouseButton3 = "MMB",
		One = "1",
		Two = "2",
		Three = "3",
		Four = "4",
		LeftShift = "Shift",
		Space = "Space",
		ButtonR1 = "R1",
		ButtonR2 = "R2",
		ButtonL1 = "L1",
		ButtonL2 = "L2",
		ButtonR3 = "R3",
		ButtonL3 = "L3",
		ButtonA = "A",
		ButtonB = "B",
		ButtonX = "X",
		ButtonY = "Y",
		DPadUp = "Up",
		DPadDown = "Down",
		DPadLeft = "Left",
		DPadRight = "Right",
	} :: { [string]: string },
}

--- The HUD label of an action's first binding on a device ("Q", "2", "LMB"); "" when unbound.
function Input.keyLabel(action: string, device: "keyboard" | "gamepad"): string
	local bindings = (Input :: any)[device]
	local names = if typeof(bindings) == "table" then bindings[action] else nil
	local name = if typeof(names) == "table" then names[1] else nil
	if typeof(name) ~= "string" then
		return ""
	end
	return Input.keyLabels[name] or name
end

--- The Art slot index an action maps to (1 for "Art"), or nil when the action is not an Art key.
function Input.artSlot(action: string): number?
	if action == "Art" then
		return Input.art.defaultSlot
	end
	local digit = action:match("^ArtSlot(%d)$")
	if digit then
		return tonumber(digit)
	end
	return nil
end

return Input
