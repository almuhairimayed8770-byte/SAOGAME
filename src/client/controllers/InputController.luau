--!strict
--[[
	InputController: ContextActionService bindings from input.luau for keyboard and mouse, gamepad
	and touch (section 6), exposed as Signals the character and target controllers consume. The
	Art key is a hold: press fires `artPressed`, release inside the cancel time fires `artReleased`
	with the held seconds, and a hold that passes the cancel time fires `artCancelled` once.

	Touch builds the mobile button layout from input.luau (section 14) through the ui package's
	`lib.El.new` when it exists, else plain ScreenGui buttons; a tap on the world is a basic attack.

	Sprint is held per source (D-338): the player's own key, button or toggle is one source (a
	`handle` call with no source); a dev tool that presses through `handle` (the capture panel's
	auto-walk and auto-perform) names its own. Sprint is on while any source holds it and
	`sprintChanged` fires only when that changes, so the player's Shift let-go never ends the
	panel's sprint, nor the panel's let-go the player's; the player alone sprints as before.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Client = script.Parent.Parent

local InputData = require(Shared.data.input)
local Signal = require(Shared.util.Signal)
local Siblings = require(script.Parent.Siblings)

local TOUCH_GUI_NAME = "SkyspireTouch"

type Hold = { slot: number, pressedAt: number, token: number, cancelled: boolean }

local InputController = {}

InputController.artPressed = Signal.new() :: Signal.Signal<number>
InputController.artReleased = Signal.new() :: Signal.Signal<number, number>
InputController.artCancelled = Signal.new() :: Signal.Signal<number>
InputController.basicAttack = Signal.new() :: Signal.Signal<>
InputController.guardChanged = Signal.new() :: Signal.Signal<boolean>
InputController.dodge = Signal.new() :: Signal.Signal<>
InputController.switchCall = Signal.new() :: Signal.Signal<>
InputController.lockToggle = Signal.new() :: Signal.Signal<>
InputController.interact = Signal.new() :: Signal.Signal<>
InputController.quickSlotRing = Signal.new() :: Signal.Signal<boolean>
InputController.sprintChanged = Signal.new() :: Signal.Signal<boolean>

local hold: Hold? = nil
local holdToken = 0
local sprinting = false
-- The sources holding the sprint now (D-338); PLAYER_SOURCE is the player's own input.
local PLAYER_SOURCE = "Player"
local sprintHolds: { [string]: true } = {}
local started = false
local touchGui: ScreenGui? = nil

local function now(): number
	return os.clock()
end

local function deviceOf(inputObject: InputObject?): string
	if inputObject == nil then
		return "keyboard"
	end
	local inputType = inputObject.UserInputType
	if inputType == Enum.UserInputType.Touch then
		return "touch"
	end
	if inputType.Name:match("^Gamepad") then
		return "gamepad"
	end
	return "keyboard"
end

local function pressArt(slot: number)
	if hold ~= nil then
		return
	end
	holdToken += 1
	local token = holdToken
	hold = { slot = slot, pressedAt = now(), token = token, cancelled = false }
	InputController.artPressed:Fire(slot)
	task.delay(InputData.art.cancelTime, function()
		local current = hold
		if current ~= nil and current.token == token and not current.cancelled then
			current.cancelled = true
			InputController.artCancelled:Fire(slot)
		end
	end)
end

local function releaseArt(slot: number)
	local current = hold
	if current == nil or current.slot ~= slot then
		return
	end
	hold = nil
	if current.cancelled then
		return
	end
	InputController.artReleased:Fire(slot, now() - current.pressedAt)
end

-- Holds or lets go of `source`'s sprint; sprint is on while any source holds it.
local function holdSprint(source: string, on: boolean)
	sprintHolds[source] = if on then true else nil
	local held = next(sprintHolds) ~= nil
	if sprinting == held then
		return
	end
	sprinting = held
	InputController.sprintChanged:Fire(held)
end

--- Routes one action state change to its Signal (ContextActionService and touch buttons share it).
--- `source` names who holds a sprint (D-338): nil is the player's own input.
function InputController.handle(
	actionName: string,
	inputState: Enum.UserInputState,
	inputObject: InputObject?,
	source: string?
)
	local began = inputState == Enum.UserInputState.Begin
	local ended = inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel
	local slot = InputData.artSlot(actionName)
	if slot ~= nil then
		if began then
			pressArt(slot)
		elseif ended then
			releaseArt(slot)
		end
	elseif actionName == "BasicAttack" then
		if began then
			InputController.basicAttack:Fire()
		end
	elseif actionName == "Guard" then
		if began then
			InputController.guardChanged:Fire(true)
		elseif ended then
			InputController.guardChanged:Fire(false)
		end
	elseif actionName == "Dodge" then
		if began then
			InputController.dodge:Fire()
		end
	elseif actionName == "SwitchCall" then
		if began then
			InputController.switchCall:Fire()
		end
	elseif actionName == "LockOn" then
		if began then
			InputController.lockToggle:Fire()
		end
	elseif actionName == "Interact" then
		if began then
			InputController.interact:Fire()
		end
	elseif actionName == "QuickSlotRing" then
		if began then
			InputController.quickSlotRing:Fire(true)
		elseif ended then
			InputController.quickSlotRing:Fire(false)
		end
	elseif actionName == "Sprint" then
		local holder = source or PLAYER_SOURCE
		local mode = (InputData.sprintMode :: any)[deviceOf(inputObject)] or "Hold"
		if mode == "Toggle" then
			if began then
				holdSprint(holder, sprintHolds[holder] == nil)
			end
		elseif began then
			holdSprint(holder, true)
		elseif ended then
			holdSprint(holder, false)
		end
	end
end

local function contextHandler(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
	InputController.handle(actionName, inputState, inputObject)
	return Enum.ContextActionResult.Sink
end

local function resolveCode(name: string): any
	if name:match("^Mouse") then
		return (Enum.UserInputType :: any)[name]
	end
	return (Enum.KeyCode :: any)[name]
end

local function codesFor(action: string): { any }
	local codes = {}
	for _, table_ in { InputData.keyboard, InputData.gamepad } do
		for _, name in (table_ :: any)[action] or {} do
			local code = resolveCode(name)
			if code ~= nil then
				table.insert(codes, code)
			end
		end
	end
	return codes
end

local function bindActions()
	local priority = (Enum.ContextActionPriority :: any)[InputData.priority].Value
	for _, action in InputData.actions do
		local codes = codesFor(action)
		if #codes > 0 then
			ContextActionService:BindActionAtPriority(action, contextHandler, false, priority, table.unpack(codes))
		end
	end
end

-- ------------------------------------------------------------------ touch layout

local function makeButton(el: any, action: string, spec: any): Instance?
	local layout = InputData.touch
	local props = {
		Name = action,
		Text = spec.label,
		TextScaled = true,
		AnchorPoint = Vector2.one / 2,
		Position = UDim2.new(1, -spec.x, 1, -spec.y),
		Size = UDim2.fromOffset(spec.size, spec.size),
		BackgroundTransparency = layout.backgroundTransparency,
		AutoButtonColor = false,
	}
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(layout.cornerRadius, 0)
	-- The ui package's El.new(className, props, children) when it is present (D-007).
	if typeof(el) == "table" and typeof(rawget(el, "new")) == "function" then
		local ok, built = pcall(el.new, "TextButton", props, { corner })
		if ok and typeof(built) == "Instance" then
			return built
		end
	end
	local button = Instance.new("TextButton")
	for key, value in props do
		(button :: any)[key] = value
	end
	corner.Parent = button
	return button
end

local function wireButton(button: Instance, action: string)
	local layout = InputData.touch
	local guiButton = button :: GuiButton
	local function isPointer(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
	end
	guiButton.InputBegan:Connect(function(input)
		if isPointer(input) then
			guiButton.BackgroundTransparency = layout.heldTransparency
			InputController.handle(action, Enum.UserInputState.Begin, input)
		end
	end)
	guiButton.InputEnded:Connect(function(input)
		if isPointer(input) then
			guiButton.BackgroundTransparency = layout.backgroundTransparency
			InputController.handle(action, Enum.UserInputState.End, input)
		end
	end)
end

local function buildTouchLayout()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local el = Siblings.load(Client, "ui.lib.El")
	local gui = Instance.new("ScreenGui")
	gui.Name = TOUCH_GUI_NAME
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = (Enum.ZIndexBehavior :: any)[InputData.touch.zIndexBehavior]
	for action, spec in InputData.touch.buttons do
		local button = makeButton(el, action, spec)
		if button ~= nil then
			wireButton(button, action)
			button.Parent = gui
		end
	end
	gui.Parent = playerGui
	touchGui = gui

	if InputData.touch.tapAttack then
		UserInputService.TouchTap:Connect(function(_positions, processed)
			if not processed then
				InputController.basicAttack:Fire()
			end
		end)
	end
end

--- True while an Art key is held.
function InputController.isHolding(): boolean
	return hold ~= nil
end

--- True while sprint is on (any source holds it).
function InputController.isSprinting(): boolean
	return sprinting
end

--- The touch ScreenGui when one was built.
function InputController.touchGui(): ScreenGui?
	return touchGui
end

--- Binds every action for every input type and builds the touch layout when touch is enabled.
function InputController.start()
	if started then
		return
	end
	started = true
	bindActions()
	if UserInputService.TouchEnabled then
		buildTouchLayout()
	end
end

return InputController
