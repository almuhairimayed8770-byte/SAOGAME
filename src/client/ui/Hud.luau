--!strict
--[[
	Hud (section 14): as little as possible.

	Top-left: name, level, the HP bar (HPGreen above half, HPYellow to a quarter, HPRed below;
	the ONLY element that flashes: a brief white flash when HP drops), the numeric HP, a thin
	Guard Gauge, the status icon row (Paralysis full-width red), and the party column (built,
	empty in Phase 0). Bottom-center: the equipped Arts with their keys, fading after 5 s idle.
	A low-HP screen-edge tint ramps in below a quarter HP. The SWITCH prompt sits over the target
	for the Switch window. `bindLocal(entityId)` reads the EntityTracker record and follows its
	attribute changes.

	Every number is in ui.luau; every color is a palette token; the bar fill and the fades step
	on Heartbeat through HudLogic (no linear tweens). Accessibility: colorblind mode swaps the HP
	hues and raises a pattern overlay; the UI scale; a telegraph intensity read by Telegraphs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(Shared.data.ui)
local Palette = require(Shared.data.palette)
local Signal = require(Shared.util.Signal)
local Engine = require(script.Parent.Parent.fx.Engine)
local El = require(script.Parent.lib.El)
local HudLogic = require(script.Parent.HudLogic)
local EntityTracker = require(script.Parent.Parent.controllers.EntityTracker)
local MusicDirector = require(script.Parent.Parent.audio.MusicDirector)
local Telegraphs = require(script.Parent.Parent.fx.Telegraphs)
local Sfx = require(Shared.data.sfx)

export type ArtEntry = { name: string, key: string }
export type PartyEntry = { name: string, hp: number, maxHp: number, lucid: boolean?, weapon: string? }
export type StatusEntry = { kind: string, remaining: number? }

type Elements = {
	gui: ScreenGui,
	scale: UIScale,
	name: TextLabel,
	level: TextLabel,
	hpBack: Frame,
	hpFill: Frame,
	hpFlash: Frame,
	hpPattern: Frame,
	hpText: TextLabel,
	gaugeFill: Frame,
	statusRow: Frame,
	party: Frame,
	artList: Frame,
	artLabels: { TextLabel }, -- the key / name labels the idle fade writes each frame
	vignette: { Frame },
	switchLabel: TextLabel,
	switchCaller: TextLabel,
	switchBillboard: BillboardGui,
}

local Hud = {}

--- Fires (hp, maxHp) whenever the bound entity's HP changes (MusicDirector's low-HP hook, tests).
Hud.hpChanged = Signal.new() :: Signal.Signal<number, number>

local elements: Elements? = nil
local boundId: number? = nil
local lastHp: number? = nil
local targetFraction = 1
local shownFraction = 1
local flashStart: number? = nil
local artIdleSince = 0
local switchStart: number? = nil
local switchDuration = 0
local colorblindMode = false
local uiScale = UI.scale.default
local telegraphLevel = UI.hud.telegraphIntensity.default
local touch = false
local stopLoop: (() -> ())? = nil
local started = false

local function color(token: string): Color3
	return Palette.color3(token :: any)
end

local function label(name: string, size: number, token: string, weight: string?): TextLabel
	return El.new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		FontFace = El.font("system", weight or "Medium"),
		TextSize = size,
		TextColor3 = color(token),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeColor3 = color("OutlineInk"),
		TextStrokeTransparency = UI.hud.textStrokeTransparency,
		Text = "",
	}) :: TextLabel
end

local function buildVignette(parent: Instance): { Frame }
	local tint = UI.hud.lowHpTint
	local frames = {}
	local edges = {
		{ name = "Left", position = UDim2.fromScale(0, 0), size = UDim2.fromScale(tint.edgeFraction, 1), rotation = 0 },
		{
			name = "Right",
			position = UDim2.fromScale(1 - tint.edgeFraction, 0),
			size = UDim2.fromScale(tint.edgeFraction, 1),
			rotation = 180,
		},
		{ name = "Top", position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, tint.edgeFraction), rotation = 90 },
		{
			name = "Bottom",
			position = UDim2.fromScale(0, 1 - tint.edgeFraction),
			size = UDim2.fromScale(1, tint.edgeFraction),
			rotation = -90,
		},
	}
	for _, edge in edges do
		local gradient = El.new("UIGradient", {
			Rotation = edge.rotation,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		})
		local frame = El.new("Frame", {
			Name = "Vignette" .. edge.name,
			Position = edge.position,
			Size = edge.size,
			BackgroundColor3 = color(tint.token),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = parent,
		}, { gradient }) :: Frame
		table.insert(frames, frame)
	end
	return frames
end

local function build(parent: Instance?): Elements
	local hud = UI.hud
	local margin = if touch then UI.mobile.margin else hud.margin
	local barWidth = if touch then UI.mobile.hpBarWidth else hud.hpBar.width

	local gui = El.new("ScreenGui", {
		Name = hud.screenGuiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = hud.displayOrder,
	}) :: ScreenGui
	local scale = El.new("UIScale", { Scale = uiScale, Parent = gui }) :: UIScale

	local vignette = buildVignette(gui)

	local topLeft = El.new("Frame", {
		Name = "TopLeft",
		Position = UDim2.fromOffset(margin, margin),
		Size = UDim2.fromOffset(barWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		El.new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local nameRow = El.new("Frame", {
		Name = "NameRow",
		Size = UDim2.new(1, 0, 0, hud.name.textSize + 2),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = topLeft,
	}, {
		El.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, hud.level.gap),
		}),
	})
	local nameLabel = label("Name", hud.name.textSize, hud.name.token, "Bold")
	nameLabel.AutomaticSize = Enum.AutomaticSize.X
	nameLabel.Size = UDim2.fromScale(0, 1)
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = nameRow
	local levelLabel = label("Level", hud.level.textSize, hud.level.token)
	levelLabel.AutomaticSize = Enum.AutomaticSize.X
	levelLabel.Size = UDim2.fromScale(0, 1)
	levelLabel.LayoutOrder = 2
	levelLabel.Parent = nameRow

	local hpFill = El.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color(hud.hpBar.tokens.green),
		BorderSizePixel = 0,
		ZIndex = 2,
	}, { El.new("UICorner", { CornerRadius = UDim.new(0, hud.hpBar.cornerRadius) }) }) :: Frame
	local hpPattern = El.new("Frame", {
		Name = "Pattern",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color("OutlineInk"),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3, -- index: draw order above the fill
		Visible = false,
	}, {
		El.new("UIGradient", {
			Rotation = 45,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	}) :: Frame
	local hpFlash = El.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color(hud.hpBar.flashToken),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4, -- index: draw order above the pattern
	}, { El.new("UICorner", { CornerRadius = UDim.new(0, hud.hpBar.cornerRadius) }) }) :: Frame
	local hpBack = El.new("Frame", {
		Name = "HpBar",
		Size = UDim2.new(1, 0, 0, hud.hpBar.height),
		BackgroundColor3 = color(hud.hpBar.backgroundToken),
		BackgroundTransparency = hud.hpBar.backgroundTransparency,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = topLeft,
	}, { El.new("UICorner", { CornerRadius = UDim.new(0, hud.hpBar.cornerRadius) }), hpFill, hpPattern, hpFlash }) :: Frame

	local hpText = label("HpText", hud.hpText.textSize, hud.hpText.token)
	hpText.Size = UDim2.new(1, 0, 0, hud.hpText.textSize + hud.hpText.gap)
	hpText.LayoutOrder = 3 -- index: layout order
	hpText.Parent = topLeft

	local gaugeFill = El.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color(hud.guardGauge.token),
		BorderSizePixel = 0,
	}) :: Frame
	El.new("Frame", {
		Name = "GuardGauge",
		Size = UDim2.new(1, 0, 0, hud.guardGauge.height),
		BackgroundColor3 = color("OutlineInk"),
		BackgroundTransparency = hud.guardGauge.backgroundTransparency,
		BorderSizePixel = 0,
		LayoutOrder = 4, -- index: layout order
		Parent = topLeft,
	}, { gaugeFill })

	local statusRow = El.new("Frame", {
		Name = "Status",
		Size = UDim2.new(1, 0, 0, hud.statusRow.iconSize),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 5, -- index: layout order
		Parent = topLeft,
	}, {
		El.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, hud.statusRow.gap),
			Wraps = true,
		}),
		El.new("UIPadding", { PaddingTop = UDim.new(0, hud.statusRow.topGap) }),
	}) :: Frame

	local party = El.new("Frame", {
		Name = "Party",
		Size = UDim2.fromOffset(hud.party.width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 6, -- index: layout order
		Visible = not (touch and UI.mobile.partyHidden),
		Parent = topLeft,
	}, {
		El.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, hud.party.gap),
		}),
		El.new("UIPadding", { PaddingTop = UDim.new(0, hud.party.topGap) }),
	}) :: Frame

	local artList = El.new("Frame", {
		Name = "Arts",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -hud.artList.bottomMargin),
		Size = UDim2.fromOffset(0, hud.artList.rowHeight),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Visible = not (touch and UI.mobile.artListHidden),
		Parent = gui,
	}, {
		El.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, hud.artList.gap),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}) :: Frame

	local switchLabel = El.new("TextLabel", {
		Name = "SwitchPrompt",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, hud.switchPrompt.screenYFraction),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = El.font("system", "Bold"),
		TextSize = hud.switchPrompt.textSize,
		TextColor3 = color(hud.switchPrompt.token),
		TextStrokeColor3 = color("OutlineInk"),
		TextStrokeTransparency = hud.textStrokeTransparency,
		TextTransparency = 1,
		Text = hud.switchPrompt.text,
		Parent = gui,
	}) :: TextLabel
	local switchCaller = El.new("TextLabel", {
		Name = "Caller",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = El.font("system", "Medium"),
		TextSize = hud.switchPrompt.callerTextSize,
		TextColor3 = color("SystemWhite"),
		TextTransparency = 1,
		Text = "",
		Parent = switchLabel,
	}) :: TextLabel
	-- The billboard lives under the HUD's own ScreenGui and only points at the target through
	-- Adornee, so a target the server removes mid-window never takes the prompt down with it.
	local switchBillboard = El.new("BillboardGui", {
		Name = "SwitchBillboard",
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(hud.switchPrompt.billboardSize.width, hud.switchPrompt.billboardSize.height),
		StudsOffsetWorldSpace = Vector3.new(0, hud.switchPrompt.heightStuds, 0),
		Enabled = false,
		Parent = gui,
	}) :: BillboardGui

	if parent ~= nil then
		pcall(function()
			gui.Parent = parent
		end)
	end
	return {
		gui = gui,
		scale = scale,
		name = nameLabel,
		level = levelLabel,
		hpBack = hpBack,
		hpFill = hpFill,
		hpFlash = hpFlash,
		hpPattern = hpPattern,
		hpText = hpText,
		gaugeFill = gaugeFill,
		statusRow = statusRow,
		party = party,
		artList = artList,
		artLabels = {},
		vignette = vignette,
		switchLabel = switchLabel,
		switchCaller = switchCaller,
		switchBillboard = switchBillboard,
	}
end

local function ensure(): Elements
	if elements == nil then
		touch = Engine.isTouch()
		elements = build(Engine.playerGui())
	end
	return elements :: Elements
end

local function applyRecord(record: any)
	local ui = ensure()
	ui.name.Text = record.name or ""
	ui.level.Text = if typeof(record.level) == "number" then ("Lv %d"):format(math.floor(record.level + 0.5)) else ""
	local hp = record.hp or 0
	local maxHp = record.maxHp or 0
	targetFraction = HudLogic.fraction(hp, maxHp)
	ui.hpText.Text = HudLogic.hpText(hp, maxHp)
	ui.hpFill.BackgroundColor3 = color(HudLogic.hpToken(targetFraction, colorblindMode))
	ui.gaugeFill.Size = UDim2.fromScale(HudLogic.fraction(record.gauge or 0, record.maxGauge or 0), 1)
	if HudLogic.shouldFlash(lastHp, hp) then
		Hud.flashHp()
	end
	if lastHp ~= hp then
		Hud.hpChanged:Fire(hp, maxHp)
		-- Section 15: below a quarter HP the music ducks and the heartbeat rises.
		MusicDirector.setLowHp(maxHp > 0 and targetFraction < Sfx.music.lowHpHeartbeatFraction)
	end
	lastHp = hp
end

local function stepLoop(dt: number)
	local ui = ensure()
	local now = Engine.now()
	shownFraction = HudLogic.smoothFill(shownFraction, targetFraction, dt)
	ui.hpFill.Size = UDim2.fromScale(shownFraction, 1)
	if flashStart ~= nil then
		local transparency = HudLogic.flashTransparency(now - (flashStart :: number))
		ui.hpFlash.BackgroundTransparency = transparency
		if transparency >= 1 then
			flashStart = nil
		end
	end
	local tintAlpha = HudLogic.lowHpTintAlpha(targetFraction, now)
	for _, frame in ui.vignette do
		frame.BackgroundTransparency = 1 - tintAlpha
	end
	local listTransparency = HudLogic.artListTransparency(now - artIdleSince)
	for _, artLabel in ui.artLabels do
		artLabel.TextTransparency = listTransparency
	end
	if switchStart ~= nil then
		local transparency = HudLogic.switchPromptTransparency(now - (switchStart :: number), switchDuration)
		ui.switchLabel.TextTransparency = transparency
		ui.switchCaller.TextTransparency = transparency
		if transparency >= 1 then
			switchStart = nil
			ui.switchBillboard.Enabled = false
			pcall(function()
				ui.switchBillboard.Adornee = nil
			end)
			ui.switchLabel.Parent = ui.gui
		end
	end
end

--- Binds the HUD to an entity id: reads its EntityTracker record and follows attribute changes.
function Hud.bindLocal(entityId: number)
	Hud.start()
	boundId = entityId
	lastHp = nil
	local record = EntityTracker.get(entityId)
	if record ~= nil then
		applyRecord(record)
		shownFraction = targetFraction
		ensure().hpFill.Size = UDim2.fromScale(shownFraction, 1)
	end
end

--- The brief white flash on the HP bar (damage taken); the only HUD element that flashes.
function Hud.flashHp()
	local ui = ensure()
	flashStart = Engine.now()
	ui.hpFlash.BackgroundTransparency = UI.hud.hpBar.flashTransparency
end

--- Rebuilds the bottom-center Art list from {name, key} rows and resets its idle fade.
function Hud.showArts(list: { ArtEntry })
	local ui = ensure()
	local config = UI.hud.artList
	for _, child in ui.artList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(ui.artLabels)
	for index, art in list do
		local key = label("Key", config.keyTextSize, config.keyToken, "Bold")
		key.AutomaticSize = Enum.AutomaticSize.X
		key.Size = UDim2.fromScale(0, 1)
		key.Text = art.key
		key.LayoutOrder = 1
		local name = label("Name", config.nameTextSize, config.nameToken)
		name.AutomaticSize = Enum.AutomaticSize.X
		name.Size = UDim2.fromScale(0, 1)
		name.Text = art.name
		name.LayoutOrder = 2
		table.insert(ui.artLabels, key)
		table.insert(ui.artLabels, name)
		El.new("Frame", {
			Name = "Art" .. index,
			Size = UDim2.fromOffset(0, config.rowHeight),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = ui.artList,
		}, {
			El.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, config.gap * 0.5),
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			key,
			name,
		})
	end
	Hud.noteArtUse()
end

--- Marks the Art list as used so it stays visible for the idle time.
function Hud.noteArtUse()
	artIdleSince = Engine.now()
end

--- Rebuilds the party column from {name, hp, maxHp, lucid?} rows (empty in Phase 0).
function Hud.setParty(members: { PartyEntry })
	local ui = ensure()
	local config = UI.hud.party
	for _, child in ui.party:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, member in members do
		if index > config.maxRows then
			break
		end
		local fraction = HudLogic.fraction(member.hp, member.maxHp)
		local name = label("Name", config.nameTextSize, "SystemWhite")
		name.Size = UDim2.new(1, 0, 0, config.nameTextSize + 2)
		name.Text = member.name
		name.LayoutOrder = 1
		local fill = El.new("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(fraction, 1),
			BackgroundColor3 = color(HudLogic.hpToken(fraction, colorblindMode)),
			BorderSizePixel = 0,
		})
		local bar = El.new("Frame", {
			Name = "Bar",
			Size = UDim2.new(1, 0, 0, config.barHeight),
			BackgroundColor3 = color("OutlineInk"),
			BackgroundTransparency = UI.hud.hpBar.backgroundTransparency,
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, { fill })
		local children: { Instance } = {
			El.new(
				"UIListLayout",
				{ FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder }
			),
			name,
			bar,
		}
		if member.lucid and fraction <= UI.hud.hpBar.yellowFraction then
			local skull = label("Lucid", config.nameTextSize, config.skullToken, "Bold")
			skull.Size = UDim2.new(1, 0, 0, config.iconSize)
			skull.Text = "LUCID"
			skull.LayoutOrder = 3 -- index: layout order
			table.insert(children, skull)
		end
		El.new("Frame", {
			Name = "Member" .. index,
			Size = UDim2.new(1, 0, 0, config.rowHeight),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = ui.party,
		}, children)
	end
end

--- Rebuilds the status icon row ({kind, remaining?}); Paralysis takes the full width in red.
function Hud.setStatuses(statuses: { StatusEntry })
	local ui = ensure()
	local config = UI.hud.statusRow
	for _, child in ui.statusRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, status in statuses do
		local token = config.tokens[status.kind] or "SystemWhite"
		local full = HudLogic.statusFullWidth(status.kind)
		local text = label("Label", config.textSize, "SystemWhite", "Bold")
		text.Size = UDim2.fromScale(1, 1)
		text.TextXAlignment = Enum.TextXAlignment.Center
		text.Text = if full then string.upper(status.kind) else string.sub(status.kind, 1, 2)
		El.new("Frame", {
			Name = status.kind,
			Size = if full
				then UDim2.new(1, 0, 0, config.fullWidthHeight)
				else UDim2.fromOffset(config.iconSize, config.iconSize),
			BackgroundColor3 = color(token),
			BorderSizePixel = 0,
			LayoutOrder = if full then 0 else index,
			Parent = ui.statusRow,
		}, { El.new("UICorner", { CornerRadius = UDim.new(0, UI.hud.hpBar.cornerRadius) }), text })
	end
end

--- Shows SWITCH for `duration` seconds over `target` (a model) or at the screen position, with
--- the caller's name beside it when the ping came from a partner.
function Hud.showSwitchPrompt(duration: number?, target: Instance?, callerName: string?)
	local ui = ensure()
	switchDuration = duration or UI.hud.switchPrompt.duration
	switchStart = Engine.now()
	ui.switchCaller.Text = callerName or ""
	ui.switchLabel.TextTransparency = 0
	ui.switchCaller.TextTransparency = if callerName ~= nil then 0 else 1
	local adornee: Instance? = nil
	if target ~= nil then
		pcall(function()
			adornee = (target :: any).PrimaryPart
		end)
		adornee = adornee or target
	end
	if adornee ~= nil then
		ui.switchBillboard.Adornee = adornee
		ui.switchLabel.Position = UDim2.fromScale(0.5, 0.5)
		ui.switchLabel.Parent = ui.switchBillboard
		ui.switchBillboard.Enabled = true
	else
		ui.switchBillboard.Enabled = false
		pcall(function()
			ui.switchBillboard.Adornee = nil
		end)
		ui.switchLabel.Position = UDim2.fromScale(0.5, UI.hud.switchPrompt.screenYFraction)
		ui.switchLabel.Parent = ui.gui
	end
end

--- Colorblind mode: swaps the HP hues and shows the pattern overlay.
function Hud.setColorblind(enabled: boolean)
	colorblindMode = enabled
	local ui = ensure()
	ui.hpPattern.Visible = enabled
	ui.hpPattern.BackgroundTransparency = if enabled then UI.hud.hpBar.patternTransparency else 1
	ui.hpFill.BackgroundColor3 = color(HudLogic.hpToken(targetFraction, colorblindMode))
end

--- True when colorblind mode is on.
function Hud.colorblind(): boolean
	return colorblindMode
end

--- Sets the UI scale (clamped to ui.luau's range).
function Hud.setUiScale(scale: number?)
	uiScale = HudLogic.uiScale(scale, touch)
	ensure().scale.Scale = uiScale
end

--- The telegraph intensity (0.5..1) read by Telegraphs every frame.
function Hud.telegraphIntensity(): number
	return telegraphLevel
end

--- Sets the telegraph intensity slider (clamped; the floor is still visible).
function Hud.setTelegraphIntensity(value: number?)
	telegraphLevel = HudLogic.telegraphIntensity(value)
end

--- The entity id the HUD follows (tests).
function Hud.boundId(): number?
	return boundId
end

--- The HUD's ScreenGui (tests, the settings menu's anchor).
function Hud.gui(): ScreenGui
	return ensure().gui
end

--- The smoothed bar fraction on screen (tests).
function Hud.shownFraction(): number
	return shownFraction
end

--- Advances the HUD by `dt` by hand (tests).
function Hud.step(dt: number)
	stepLoop(dt)
end

--- Builds the HUD, reads the settings attributes, follows EntityTracker changes and starts the loop.
function Hud.start()
	if started then
		return
	end
	started = true
	ensure()
	-- The accessibility slider lives here; Telegraphs read it through this source every frame.
	Telegraphs.setIntensitySource(Hud.telegraphIntensity)
	local player = Engine.localPlayer()
	if player ~= nil then
		local settings = UI.settings
		local function readSettings()
			local cb = player:GetAttribute(settings.colorblindAttribute)
			Hud.setColorblind(cb == true)
			local scale = player:GetAttribute(settings.uiScaleAttribute)
			Hud.setUiScale(if typeof(scale) == "number" then scale else nil)
			local intensity = player:GetAttribute(settings.telegraphIntensityAttribute)
			Hud.setTelegraphIntensity(if typeof(intensity) == "number" then intensity else nil)
		end
		readSettings()
		for _, attribute in
			{ settings.colorblindAttribute, settings.uiScaleAttribute, settings.telegraphIntensityAttribute }
		do
			pcall(function()
				player:GetAttributeChangedSignal(attribute):Connect(readSettings)
			end)
		end
	else
		Hud.setUiScale(nil)
	end
	EntityTracker.changed:Connect(function(record: any)
		if boundId ~= nil and record.id == boundId then
			applyRecord(record)
		end
	end)
	EntityTracker.removed:Connect(function(record: any)
		if boundId ~= nil and record.id == boundId then
			boundId = nil
			lastHp = nil
		end
	end)
	artIdleSince = Engine.now()
	stopLoop = Engine.onHeartbeat(stepLoop)
end

--- Stops the Heartbeat loop (place teardown).
function Hud.stop()
	if stopLoop ~= nil then
		stopLoop()
		stopLoop = nil
	end
	started = false
end

return Hud
