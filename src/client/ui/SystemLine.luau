--!strict
--[[
	SystemLine (section 14): a centered line of system text with a short chime. SystemWhite in the
	system font by default; WardedPurple for Warded popups (with the purple chime); CursorRed at
	the larger size for the Architect's lines. Lines queue and play one at a time: fade in, hold,
	fade out, stepped on Heartbeat (no TweenService). The Architect's red hex sky is Phase 3; a
	hook is kept so the announcement can raise it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(Shared.data.ui)
local Palette = require(Shared.data.palette)
local Engine = require(script.Parent.Parent.fx.Engine)
local El = require(script.Parent.lib.El)
local SfxPool = require(script.Parent.Parent.audio.SfxPool)

type Line = { text: string, token: string, chime: string? }

local SystemLine = {}

local queue: { Line } = {}
local label: TextLabel? = nil
local stroke: UIStroke? = nil
local current: Line? = nil
local phaseStart = 0
local phase: "In" | "Hold" | "Out" | "Gap" | "Idle" = "Idle"
local stopLoop: (() -> ())? = nil
local skyHook: ((text: string, token: string) -> ())? = nil
local shown = 0

local function build(parent: Instance?)
	if label ~= nil then
		return
	end
	local config = UI.systemLine
	local text = El.new("TextLabel", {
		Name = "SystemLine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, config.yFraction),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = El.font("system", "Medium"),
		TextSize = config.textSize,
		TextColor3 = Palette.color3(config.defaultToken :: any),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		TextStrokeColor3 = Palette.color3("OutlineInk"),
		TextWrapped = true,
		Text = "",
	}) :: TextLabel
	local outline = El.new("UIStroke", {
		Thickness = config.strokeThickness,
		Color = Palette.color3("OutlineInk"),
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}) :: UIStroke
	outline.Parent = text
	local gui = El.new("ScreenGui", {
		Name = config.screenGuiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = config.displayOrder,
	}, { text })
	if parent ~= nil then
		pcall(function()
			gui.Parent = parent
		end)
	end
	label = text
	stroke = outline
end

local function setTransparency(value: number)
	local text = label :: TextLabel
	text.TextTransparency = value
	local config = UI.systemLine
	if stroke ~= nil then
		(stroke :: UIStroke).Transparency = config.strokeTransparency + (1 - config.strokeTransparency) * value
	end
end

local function present(line: Line)
	local config = UI.systemLine
	local text = label :: TextLabel
	local token = if Palette.tokens[line.token] ~= nil then line.token else config.defaultToken
	text.Text = line.text
	text.TextColor3 = Palette.color3(token :: any)
	text.TextSize = if config.largeTokens[token] then config.largeTextSize else config.textSize
	setTransparency(1)
	current = line
	phase = "In"
	phaseStart = Engine.now()
	shown += 1
	local chime = line.chime or config.chimes[token] or config.chimes.default
	if chime ~= nil and chime ~= "" then
		pcall(SfxPool.play, chime)
	end
	if skyHook ~= nil and config.largeTokens[token] then
		pcall(skyHook :: any, line.text, token)
	end
end

local function step()
	local config = UI.systemLine
	local now = Engine.now()
	local elapsed = now - phaseStart
	if phase == "Idle" then
		local nextLine = table.remove(queue, 1)
		if nextLine ~= nil then
			present(nextLine)
		elseif stopLoop ~= nil then
			stopLoop()
			stopLoop = nil
		end
	elseif phase == "In" then
		local t = math.clamp(elapsed / math.max(1e-6, config.fadeIn), 0, 1)
		setTransparency(1 - (1 - (1 - t) * (1 - t)))
		if t >= 1 then
			phase = "Hold"
			phaseStart = now
		end
	elseif phase == "Hold" then
		setTransparency(0)
		if elapsed >= config.hold then
			phase = "Out"
			phaseStart = now
		end
	elseif phase == "Out" then
		local t = math.clamp(elapsed / math.max(1e-6, config.fadeOut), 0, 1)
		setTransparency(t * t)
		if t >= 1 then
			phase = "Gap"
			phaseStart = now
			current = nil
		end
	elseif phase == "Gap" then
		if elapsed >= config.gap then
			phase = "Idle"
			phaseStart = now
		end
	end
end

local function ensureLoop()
	if stopLoop == nil then
		stopLoop = Engine.onHeartbeat(function()
			step()
		end)
	end
end

--- Queues a system line: `token` is a palette token (SystemWhite, WardedPurple, CursorRed...),
--- `chime` a sfx name ("ui.SystemLine"); the token's chime plays when none is given.
function SystemLine.show(text: string, token: string?, chime: string?)
	build(Engine.playerGui())
	if #queue >= UI.systemLine.maxQueue then
		table.remove(queue, 1)
	end
	table.insert(queue, { text = text, token = token or UI.systemLine.defaultToken, chime = chime })
	ensureLoop()
	if phase == "Idle" then
		step()
	end
end

--- Drops every queued line and hides the current one.
function SystemLine.clear()
	table.clear(queue)
	if label ~= nil then
		setTransparency(1)
	end
	current = nil
	phase = "Idle"
end

--- The line on screen right now, if any.
function SystemLine.current(): Line?
	return current
end

--- Lines queued behind the current one.
function SystemLine.queued(): number
	return #queue
end

--- Lines shown so far (tests).
function SystemLine.shownCount(): number
	return shown
end

--- Installs the Architect's sky hook (Phase 3: the red hex sky behind a large announcement).
function SystemLine.setSkyHook(hook: ((text: string, token: string) -> ())?)
	skyHook = hook
end

--- Advances the fades by hand (tests).
function SystemLine.step()
	step()
end

--- Builds the label under the PlayerGui.
function SystemLine.start()
	build(Engine.playerGui())
end

return SystemLine
