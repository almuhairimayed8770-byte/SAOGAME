--!strict
--[[
	Capture prompts (section 1 "How you work", section 20 Phase 0 gate). Runs only in a place whose
	Workspace carries the DevCapture attribute (places/Playground.project.json). Shows the gate shot
	list from data/dev.luau in a SystemCyan panel: which shot is up, what the reviewer must see, the
	file it is saved to (docs/clips/phase-0/<shot>.mp4), a 3-2-1 countdown, then hides itself and
	runs a small frame counter bottom-left so the recording shows nothing but the game and the
	counter. The reviewer records with Studio's own recorder or any screen capture.

	A time-scale toggle (1x / 0.5x / 0.25x) slows every Choreo animator on this client and asks the
	server (dev remote, dev places only) to publish the scale as a workspace attribute for anything
	else that wants to honour it. Hit FX and sounds keep running at 1x, so a slowed shot reviews
	animation only; the panel says so next to the scale (Dev.timeScaleLabel). No gameplay logic
	lives here.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dev = require(Shared.data.dev)

if workspace:GetAttribute(Dev.attributes.capture) ~= true then
	return
end

local Client = script.Parent.Parent
local El = require(Client.ui.lib.El)
local Siblings = require(Client.controllers.Siblings)

local Choreo, hasChoreo = Siblings.load(Client, "choreo.Choreo")

local Capture = Dev.capture
local PanelData = Capture.panel
local CounterData = Capture.counter
local Shots = Capture.shots
local Steps = Dev.timeScale.steps

type Phase = "Idle" | "Countdown" | "Recording" | "Done"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------------------------

local shotIndex = 1
local done: { [string]: boolean } = {}
local phase: Phase = "Idle"
local countdownRemaining = 0
local elapsed = 0
local frames = 0
local doneTimer = 0
local timeScaleIndex = 1
local panelVisible = true
local reapplyTimer = 0

-- ---------------------------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------------------------

local function label(text: string, size: number, token: string, props: { [string]: any }?): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, PanelData.rowHeight),
		FontFace = El.font("system"),
		Text = text,
		TextSize = size,
		TextColor3 = El.color(token),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	if props then
		for key, value in props do
			merged[key] = value
		end
	end
	return El.new("TextLabel", merged) :: TextLabel
end

local gui = El.new("ScreenGui", {
	Name = PanelData.screenGuiName,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = PanelData.displayOrder,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}) :: ScreenGui

local panel = El.new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -PanelData.margin, 0, PanelData.margin),
	Size = UDim2.fromOffset(PanelData.width, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = El.color(PanelData.backgroundToken),
	BackgroundTransparency = PanelData.backgroundTransparency,
	BorderSizePixel = 0,
}, {
	El.new("UICorner", { CornerRadius = UDim.new(0, PanelData.cornerRadius) }),
	El.new("UIStroke", {
		Color = El.color(PanelData.borderToken),
		Thickness = PanelData.borderThickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}),
	El.new("UIPadding", {
		PaddingTop = UDim.new(0, PanelData.padding),
		PaddingBottom = UDim.new(0, PanelData.padding),
		PaddingLeft = UDim.new(0, PanelData.padding),
		PaddingRight = UDim.new(0, PanelData.padding),
	}),
	El.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, PanelData.lineGap),
	}),
}) :: Frame

local titleLabel =
	label(("Capture: %s gate shots"):format(Capture.phase), PanelData.titleTextSize, PanelData.titleToken, {
		LayoutOrder = 1,
		FontFace = El.font("system", "Bold"),
	})
local scaleLabel = label("", PanelData.textSize, PanelData.textToken, { LayoutOrder = 2 })
local shotLabels: { TextLabel } = {}
for index in Shots do
	local row = label("", PanelData.textSize, PanelData.textToken, { LayoutOrder = 10 + index })
	table.insert(shotLabels, row)
	row.Parent = panel
end
local notesLabel = label("", PanelData.smallTextSize, PanelData.dimToken, { LayoutOrder = 100 })
local fileLabel = label("", PanelData.smallTextSize, PanelData.textToken, { LayoutOrder = 101 })
local countdownLabel = label("", PanelData.countdownTextSize, PanelData.titleToken, {
	LayoutOrder = 102,
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
	FontFace = El.font("system", "Bold"),
})
local keys = Capture.hotkeys
local legendLabel = label(
	("%s start countdown   %s / %s shot   %s time scale   %s hide   %s mark done"):format(
		keys.startCountdown,
		keys.previousShot,
		keys.nextShot,
		keys.cycleTimeScale,
		keys.togglePanel,
		keys.markDone
	),
	PanelData.smallTextSize,
	PanelData.dimToken,
	{ LayoutOrder = 103 }
)
local statusLabel = label("", PanelData.textSize, PanelData.doneToken, { LayoutOrder = 104 })

titleLabel.Parent = panel
scaleLabel.Parent = panel
notesLabel.Parent = panel
fileLabel.Parent = panel
countdownLabel.Parent = panel
legendLabel.Parent = panel
statusLabel.Parent = panel
panel.Parent = gui

local counter = El.new("Frame", {
	Name = "Counter",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, CounterData.margin, 1, -CounterData.margin),
	Size = UDim2.fromOffset(CounterData.width, CounterData.height),
	BackgroundColor3 = El.color(CounterData.backgroundToken),
	BackgroundTransparency = CounterData.backgroundTransparency,
	BorderSizePixel = 0,
	Visible = false,
}, {
	El.new("UICorner", { CornerRadius = UDim.new(0, PanelData.cornerRadius) }),
}) :: Frame
local counterLabel = El.new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	FontFace = El.font("system", "Bold"),
	Text = "",
	TextSize = CounterData.textSize,
	TextColor3 = El.color(CounterData.token),
	TextXAlignment = Enum.TextXAlignment.Center,
	Parent = counter,
}) :: TextLabel
counter.Parent = gui
gui.Parent = playerGui

-- ---------------------------------------------------------------------------------------------
-- Rendering the panel text
-- ---------------------------------------------------------------------------------------------

local function currentShot(): Dev.Shot
	return Shots[shotIndex]
end

local function refreshPanel()
	for index, row in shotLabels do
		local shot = Shots[index]
		local mark = if done[shot.id] then "[x]" else "[ ]"
		local pointer = if index == shotIndex then ">" else " "
		row.Text = ("%s %s %d. %s (%d s)"):format(pointer, mark, index, shot.title, shot.seconds)
		row.TextColor3 = El.color(
			if done[shot.id]
				then PanelData.doneToken
				elseif index == shotIndex then PanelData.titleToken
				else PanelData.textToken
		)
	end
	local shot = currentShot()
	notesLabel.Text = "See: " .. shot.notes
	fileLabel.Text = "Save as " .. Dev.clipPath(shot.id)
	scaleLabel.Text = Dev.timeScaleLabel(Steps[timeScaleIndex])
	if phase == "Done" then
		statusLabel.Text = ("Shot done: %s"):format(Dev.clipPath(shot.id))
	elseif phase == "Idle" then
		statusLabel.Text = ("Ready. Start your recorder, press %s, the panel hides after the count."):format(
			keys.startCountdown
		)
	else
		statusLabel.Text = ""
	end
end

local function setPanelVisible(visible: boolean)
	panelVisible = visible
	panel.Visible = visible
end

-- ---------------------------------------------------------------------------------------------
-- Time scale
-- ---------------------------------------------------------------------------------------------

local function applyTimeScaleTo(model: Instance, scale: number)
	if not hasChoreo or not model:IsA("Model") then
		return
	end
	local animator = Choreo.find(model)
	if animator ~= nil then
		animator:setTimeScale(scale)
	end
end

local function applyTimeScale()
	local scale = Steps[timeScaleIndex]
	for _, model in CollectionService:GetTagged(Capture.entityTag) do
		applyTimeScaleTo(model, scale)
	end
	local character = player.Character
	if character ~= nil then
		applyTimeScaleTo(character, scale)
	end
end

local function publishTimeScale()
	local remote = ReplicatedStorage:FindFirstChild(Dev.timeScale.remoteName)
	if remote ~= nil and remote:IsA("RemoteEvent") then
		remote:FireServer(Steps[timeScaleIndex])
	end
end

local function cycleTimeScale()
	timeScaleIndex = timeScaleIndex % #Steps + 1
	applyTimeScale()
	publishTimeScale()
	refreshPanel()
end

-- ---------------------------------------------------------------------------------------------
-- Shot flow
-- ---------------------------------------------------------------------------------------------

local function startCountdown()
	if phase == "Countdown" or phase == "Recording" then
		return
	end
	phase = "Countdown"
	countdownRemaining = Capture.countdownSeconds
	countdownLabel.Visible = true
	countdownLabel.Text = tostring(Capture.countdownSeconds)
	setPanelVisible(true)
	refreshPanel()
end

local function startRecording()
	phase = "Recording"
	elapsed = 0
	frames = 0
	countdownLabel.Visible = false
	setPanelVisible(false)
	counter.Visible = true
end

local function markDone()
	if phase ~= "Recording" then
		return
	end
	done[currentShot().id] = true
	phase = "Done"
	doneTimer = Capture.doneHoldSeconds
	counter.Visible = false
	setPanelVisible(true)
	refreshPanel()
end

local function moveShot(delta: number)
	if phase == "Countdown" or phase == "Recording" then
		return
	end
	shotIndex = (shotIndex - 1 + delta) % #Shots + 1
	phase = "Idle"
	refreshPanel()
end

local function counterText(): string
	local shot = currentShot()
	local target = shot.seconds
	if elapsed >= target then
		return ("%s  f %d  %.1f s  target %d s reached, %s to mark done"):format(
			shot.id,
			frames,
			elapsed,
			target,
			keys.markDone
		)
	end
	return ("%s  f %d  %.1f / %d s  %gx"):format(shot.id, frames, elapsed, target, Steps[timeScaleIndex])
end

-- ---------------------------------------------------------------------------------------------
-- Input and the per-frame step
-- ---------------------------------------------------------------------------------------------

local function keyCode(name: string): Enum.KeyCode?
	local ok, result = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok then result else nil
end

local bindings: { [Enum.KeyCode]: () -> () } = {}
local function bind(name: string, fn: () -> ())
	local code = keyCode(name)
	if code ~= nil then
		bindings[code] = fn
	else
		warn(("[Capture] unknown key %s in dev.luau"):format(name))
	end
end

bind(keys.startCountdown, startCountdown)
bind(keys.nextShot, function()
	moveShot(1)
end)
bind(keys.previousShot, function()
	moveShot(-1)
end)
bind(keys.cycleTimeScale, cycleTimeScale)
bind(keys.togglePanel, function()
	setPanelVisible(not panelVisible)
end)
bind(keys.markDone, markDone)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local fn = bindings[input.KeyCode]
	if fn ~= nil then
		fn()
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	if phase == "Countdown" then
		countdownRemaining -= dt
		if countdownRemaining <= 0 then
			startRecording()
		else
			countdownLabel.Text = tostring(math.ceil(countdownRemaining))
		end
	elseif phase == "Recording" then
		elapsed += dt
		frames += 1
		counterLabel.Text = counterText()
		if elapsed >= currentShot().seconds then
			counterLabel.TextColor3 = El.color(PanelData.doneToken)
		else
			counterLabel.TextColor3 = El.color(CounterData.token)
		end
	elseif phase == "Done" then
		doneTimer -= dt
		if doneTimer <= 0 then
			phase = "Idle"
			moveShot(1)
		end
	end

	if Steps[timeScaleIndex] ~= Dev.timeScale.default then
		reapplyTimer += dt
		if reapplyTimer >= Capture.timeScaleReapplySeconds then
			reapplyTimer = 0
			applyTimeScale()
		end
	end
end)

player.CharacterAdded:Connect(function()
	task.defer(applyTimeScale)
end)

refreshPanel()
