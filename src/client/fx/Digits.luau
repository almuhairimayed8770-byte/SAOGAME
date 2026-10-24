--!strict
--[[
	Digits (sections 6 and 14): the real damage number as a small floating digit that rises
	combat.digitRise studs and fades over combat.digitFadeTime. White for normal, yellow for a
	crit, cyan for a Switch, red for damage taken. The number is the integer the server sent; no
	inflation, no rounding tricks. Pooled BillboardGuis on anchored invisible parts; the rise
	eases out and the digit lands with a small overshoot, never a linear tween.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Palette = require(Shared.data.palette)
local Easing = require(Shared.util.Easing)
local Engine = require(script.Parent.Engine)
local El = require(script.Parent.Parent.ui.lib.El)

export type Kind = "Normal" | "Crit" | "Switch" | "Taken"

type Digit = {
	part: BasePart,
	gui: BillboardGui,
	label: TextLabel,
	start: number,
	baseSize: number,
	busy: boolean,
}

local Digits = {}

local pool: { Digit } = {}
local folder: Instance? = nil
local stopLoop: (() -> ())? = nil
local jitter = Random.new()

local function ensureFolder(): Instance
	if folder == nil then
		folder = Engine.folder(workspace, "FxDigits")
	end
	return folder :: Instance
end

local function newDigit(): Digit
	local config = Fx.digits
	local part = Instance.new("Part")
	part.Name = "DigitAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	local label = El.new("TextLabel", {
		Name = "Digit",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		FontFace = El.font("system", "Bold"),
		TextSize = config.textSize.Normal,
		TextColor3 = Palette.color3("DigitWhite"),
		TextStrokeColor3 = Palette.color3("OutlineInk"),
		TextStrokeTransparency = config.strokeTransparency,
		TextTransparency = 1,
		Text = "",
	}) :: TextLabel
	local gui = El.new("BillboardGui", {
		Name = "DigitGui",
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = config.maxDistance,
		Size = UDim2.fromOffset(config.billboardSize.width, config.billboardSize.height),
		StudsOffsetWorldSpace = Vector3.new(0, config.startHeight, 0),
		Enabled = false,
	}, { label }) :: BillboardGui
	gui.Parent = part
	part.Parent = ensureFolder()
	return { part = part, gui = gui, label = label, start = 0, baseSize = config.textSize.Normal, busy = false }
end

local function acquire(): Digit
	for _, digit in pool do
		if not digit.busy then
			return digit
		end
	end
	local digit = newDigit()
	table.insert(pool, digit)
	return digit
end

local function step()
	local now = Engine.now()
	local config = Fx.digits
	local anyBusy = false
	for _, digit in pool do
		if not digit.busy then
			continue
		end
		local elapsed = now - digit.start
		local t = elapsed / config.fadeTime
		if t >= 1 then
			digit.busy = false
			digit.gui.Enabled = false
			digit.label.TextTransparency = 1
			continue
		end
		anyBusy = true
		local lift = config.rise * Easing.evaluate(config.riseEasing, t)
		digit.gui.StudsOffsetWorldSpace = Vector3.new(0, config.startHeight + lift, 0)
		local transparency = 0
		if t > config.fadeStartFraction then
			transparency = (t - config.fadeStartFraction) / math.max(1e-6, 1 - config.fadeStartFraction)
		end
		digit.label.TextTransparency = transparency
		-- The punch: the number lands from a larger size with an ease-out.
		local punch = math.clamp(elapsed / config.punchTime, 0, 1)
		local scale = config.punchScale + (1 - config.punchScale) * Easing.evaluate("ExpoOut", punch)
		digit.label.TextSize = math.floor(digit.baseSize * scale + 0.5)
	end
	if not anyBusy and stopLoop ~= nil then
		stopLoop()
		stopLoop = nil
	end
end

--- Shows `amount` (the server's integer) at `position` in the kind's color.
function Digits.show(position: Vector3, amount: number, kind: Kind)
	local config = Fx.digits
	local digit = acquire()
	local token = config.tokens[kind] or config.tokens.Normal
	local size = config.textSize[kind] or config.textSize.Normal
	local offset = Vector3.new(jitter:NextNumber(-1, 1) * config.spread, 0, jitter:NextNumber(-1, 1) * config.spread)
	digit.part.CFrame = CFrame.new(position + offset)
	digit.label.Text = ("%d"):format(math.floor(amount + 0.5))
	digit.label.TextColor3 = Palette.color3(token :: any)
	digit.label.TextSize = math.floor(size * config.punchScale + 0.5)
	digit.label.TextTransparency = 0
	digit.gui.StudsOffsetWorldSpace = Vector3.new(0, config.startHeight, 0)
	digit.gui.Enabled = true
	digit.baseSize = size
	digit.start = Engine.now()
	digit.busy = true
	if stopLoop == nil then
		stopLoop = Engine.onHeartbeat(function()
			step()
		end)
	end
end

--- Digits rising right now.
function Digits.activeCount(): number
	local count = 0
	for _, digit in pool do
		if digit.busy then
			count += 1
		end
	end
	return count
end

--- Advances the digits by hand (tests).
function Digits.step()
	step()
end

--- Pre-builds the pool so the first hit never allocates.
function Digits.start()
	while #pool < Fx.digits.poolSize do
		table.insert(pool, newDigit())
	end
end

return Digits
