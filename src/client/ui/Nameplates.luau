--!strict
--[[
	Nameplates (section 14): over every player a cursor diamond (green / orange / red from the
	Cursor attribute) and the name on hover; over every enemy a red diamond, the name, a short HP
	bar and the Guard Gauge; nothing over bosses (their bars sit at the top of the screen, Phase
	3: the `bossSeen` hook is where BossBars will attach). Plates are pooled BillboardGuis driven
	by EntityTracker.added / removed / changed; they fade past ui.nameplates.distance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(Shared.data.ui)
local Palette = require(Shared.data.palette)
local Signal = require(Shared.util.Signal)
local Engine = require(script.Parent.Parent.fx.Engine)
local Quality = require(script.Parent.Parent.fx.Quality)
local El = require(script.Parent.lib.El)
local HudLogic = require(script.Parent.HudLogic)
local EntityTracker = require(script.Parent.Parent.controllers.EntityTracker)

type Plate = {
	kind: "Player" | "Enemy",
	gui: BillboardGui,
	diamond: Frame,
	name: TextLabel,
	hpFill: Frame?,
	hpBack: Frame?,
	gaugeFill: Frame?,
	gaugeBack: Frame?,
	record: any?,
	alpha: number,
}

local Nameplates = {}

--- Fires with the record of a boss entity (no plate is drawn; BossBars will listen, Phase 3).
Nameplates.bossSeen = Signal.new() :: Signal.Signal<any>

local plates: { [number]: Plate } = {}
local pool: { [string]: { Plate } } = { Player = {}, Enemy = {} }
local localId: number? = nil
local stopLoop: (() -> ())? = nil
local sinceUpdate = 0
local hover: ((plate: Plate) -> boolean)? = nil
local started = false
local folder: Instance? = nil

-- Plates live in their own folder under the PlayerGui and point at rigs through Adornee: a plate
-- parented into a rig would be destroyed with it when the server removes the model, and a pool
-- of destroyed BillboardGuis can never be re-parented (Parent is locked after Destroy).
local function ensureFolder(): Instance
	if folder == nil then
		local gui = Engine.playerGui()
		if gui ~= nil then
			folder = Engine.folder(gui, UI.nameplates.folderName)
		else
			local detached = Instance.new("Folder")
			detached.Name = UI.nameplates.folderName
			folder = detached
		end
	end
	return folder :: Instance
end

local function diamond(size: number, token: string): Frame
	return El.new("Frame", {
		Name = "Cursor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		BackgroundColor3 = Palette.color3(token :: any),
		BorderSizePixel = 0,
	}) :: Frame
end

local function bar(width: number, height: number, token: string, backgroundTransparency: number): (Frame, Frame)
	local fill = El.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.color3(token :: any),
		BorderSizePixel = 0,
	}) :: Frame
	local back = El.new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Palette.color3("OutlineInk"),
		BackgroundTransparency = backgroundTransparency,
		BorderSizePixel = 0,
	}, { fill }) :: Frame
	return back, fill
end

local function newPlate(kind: "Player" | "Enemy"): Plate
	local config = if kind == "Player" then UI.nameplates.player else UI.nameplates.enemy
	local root = El.new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}) :: Frame
	local layout = El.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, if kind == "Enemy" then UI.nameplates.enemy.gap else 2),
	})
	layout.Parent = root
	local cursorToken = if kind == "Player"
		then UI.nameplates.player.cursorTokens[UI.nameplates.player.defaultCursor]
		else UI.nameplates.enemy.diamondToken
	local cursor = diamond(config.diamondSize, cursorToken)
	cursor.LayoutOrder = 1
	-- The diamond is rotated, so give it a square holder the layout can measure.
	local holder = El.new("Frame", {
		Name = "CursorHolder",
		Size = UDim2.fromOffset(config.diamondSize * 2, config.diamondSize * 2),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, { cursor })
	cursor.Position = UDim2.fromScale(0.5, 0.5)
	holder.Parent = root
	local name = El.new("TextLabel", {
		Name = "Name",
		Size = UDim2.new(1, 0, 0, config.nameTextSize + 2),
		BackgroundTransparency = 1,
		FontFace = El.font("system", "Medium"),
		TextSize = config.nameTextSize,
		TextColor3 = Palette.color3(config.nameToken :: any),
		TextStrokeColor3 = Palette.color3("OutlineInk"),
		TextStrokeTransparency = 0.5,
		Text = "",
		LayoutOrder = 2,
	}) :: TextLabel
	name.Parent = root
	local hpBack, hpFill, gaugeBack, gaugeFill = nil, nil, nil, nil
	if kind == "Enemy" then
		local enemy = UI.nameplates.enemy
		hpBack, hpFill = bar(enemy.hpBar.width, enemy.hpBar.height, "HPGreen", enemy.hpBar.backgroundTransparency)
		hpBack.LayoutOrder = 3 -- index: layout order
		hpBack.Parent = root
		gaugeBack, gaugeFill = bar(
			enemy.gaugeBar.width,
			enemy.gaugeBar.height,
			enemy.gaugeBar.token,
			enemy.gaugeBar.backgroundTransparency
		)
		gaugeBack.LayoutOrder = 4 -- index: layout order
		gaugeBack.Parent = root
	end
	local gui = El.new("BillboardGui", {
		Name = "Nameplate",
		AlwaysOnTop = true,
		LightInfluence = UI.nameplates.lightInfluence,
		Size = UDim2.fromOffset(config.width, config.height),
		StudsOffsetWorldSpace = Vector3.new(0, config.offsetStuds, 0),
		MaxDistance = UI.nameplates.distance + UI.nameplates.fadeBand,
		Enabled = false,
		Parent = ensureFolder(),
	}, { root }) :: BillboardGui
	return {
		kind = kind,
		gui = gui,
		diamond = cursor,
		name = name,
		hpFill = hpFill,
		hpBack = hpBack,
		gaugeFill = gaugeFill,
		gaugeBack = gaugeBack,
		record = nil,
		alpha = 1,
	}
end

local function acquire(kind: "Player" | "Enemy"): Plate
	local plate = table.remove(pool[kind])
	if plate == nil then
		plate = newPlate(kind)
	end
	return plate :: Plate
end

local function release(plate: Plate)
	plate.gui.Enabled = false
	pcall(function()
		plate.gui.Adornee = nil
	end)
	plate.record = nil
	table.insert(pool[plate.kind], plate)
end

local function isBoss(record: any): boolean
	local model = record.model
	if model ~= nil then
		local ok, flag = pcall(function()
			return model:GetAttribute(UI.nameplates.bossAttribute)
		end)
		if ok and flag == true then
			return true
		end
	end
	return false
end

local function applyAlpha(plate: Plate, alpha: number, showName: boolean)
	plate.alpha = alpha
	local transparency = 1 - alpha
	plate.diamond.BackgroundTransparency = transparency
	plate.name.TextTransparency = if showName then transparency else 1
	plate.name.TextStrokeTransparency = if showName then 0.5 + 0.5 * transparency else 1
	if plate.hpBack ~= nil then
		(plate.hpBack :: Frame).BackgroundTransparency = UI.nameplates.enemy.hpBar.backgroundTransparency
			+ (1 - UI.nameplates.enemy.hpBar.backgroundTransparency) * transparency;
		(plate.hpFill :: Frame).BackgroundTransparency = transparency
	end
	if plate.gaugeBack ~= nil then
		(plate.gaugeBack :: Frame).BackgroundTransparency = UI.nameplates.enemy.gaugeBar.backgroundTransparency
			+ (1 - UI.nameplates.enemy.gaugeBar.backgroundTransparency) * transparency;
		(plate.gaugeFill :: Frame).BackgroundTransparency = transparency
	end
end

--- Rewrites a plate from its record (name, cursor color, HP and gauge bars).
function Nameplates.refresh(record: any)
	local plate = plates[record.id]
	if plate == nil then
		return
	end
	plate.name.Text = record.name or ""
	-- Nothing hangs over a frozen, shattering rig: the plate goes with the first HP it lost.
	plate.gui.Enabled = record.state ~= "Dead"
	if plate.kind == "Player" then
		local tokens = UI.nameplates.player.cursorTokens
		local token = tokens[record.cursor] or tokens[UI.nameplates.player.defaultCursor]
		plate.diamond.BackgroundColor3 = Palette.color3(token :: any)
	else
		local fraction = HudLogic.fraction(record.hp or 0, record.maxHp or 0)
		local fill = plate.hpFill :: Frame
		fill.Size = UDim2.fromScale(fraction, 1)
		fill.BackgroundColor3 = Palette.color3(HudLogic.hpToken(fraction, false) :: any)
		local gauge = plate.gaugeFill :: Frame
		gauge.Size = UDim2.fromScale(HudLogic.fraction(record.gauge or 0, record.maxGauge or 0), 1)
	end
end

--- Gives a tracked record its plate (none for bosses, which fire `bossSeen` instead).
function Nameplates.attach(record: any)
	if plates[record.id] ~= nil then
		return
	end
	if isBoss(record) then
		Nameplates.bossSeen:Fire(record)
		return
	end
	local kind: "Player" | "Enemy" = if record.kind == "Player" then "Player" else "Enemy"
	local plate = acquire(kind)
	plate.record = record
	plates[record.id] = plate
	local adornee: Instance? = nil
	pcall(function()
		adornee = record.model.PrimaryPart
	end)
	plate.gui.Adornee = adornee or record.model
	plate.gui.Enabled = true
	Nameplates.refresh(record)
	applyAlpha(plate, 1, kind == "Enemy")
end

--- Returns a record's plate to the pool.
function Nameplates.detach(record: any)
	local plate = plates[record.id]
	if plate == nil then
		return
	end
	plates[record.id] = nil
	release(plate)
end

--- The local entity: its own plate hides the name.
function Nameplates.setLocalId(id: number?)
	localId = id
end

--- Replaces the hover test (tests); the default compares the plate to the mouse position.
function Nameplates.setHoverTest(test: ((plate: any) -> boolean)?)
	hover = test
end

local function defaultHover(plate: Plate): boolean
	local camera = Engine.camera()
	if camera == nil then
		return false
	end
	local position = Engine.modelPosition(if plate.record ~= nil then plate.record.model else nil)
	if position == nil then
		return false
	end
	local ok, result = pcall(function()
		local screen, visible = (camera :: any):WorldToViewportPoint(position + plate.gui.StudsOffsetWorldSpace)
		if not visible then
			return false
		end
		local mouse = (game:GetService("UserInputService") :: any):GetMouseLocation()
		return (Vector2.new(screen.X, screen.Y) - mouse).Magnitude <= UI.nameplates.hoverRadiusPixels
	end)
	return ok and result == true
end

--- Fades plates by distance and shows player names on hover (called at the tier's rate).
function Nameplates.update()
	local distance = UI.nameplates.distance
	local band = math.max(1e-6, UI.nameplates.fadeBand)
	for id, plate in plates do
		local position = Engine.modelPosition(if plate.record ~= nil then plate.record.model else nil)
		local alpha = 1
		if position ~= nil then
			local studs = Engine.distanceTo(position)
			alpha = 1 - math.clamp((studs - distance) / band, 0, 1)
		end
		local showName = plate.kind == "Enemy"
		if plate.kind == "Player" and id ~= localId then
			showName = if hover ~= nil then hover(plate) else defaultHover(plate)
		end
		applyAlpha(plate, alpha, showName)
	end
end

--- Plates on screen right now.
function Nameplates.count(): number
	local count = 0
	for _ in plates do
		count += 1
	end
	return count
end

--- The plate for an entity id (tests).
function Nameplates.plateOf(id: number): Plate?
	return plates[id]
end

--- Wires EntityTracker and starts the fade / hover loop.
function Nameplates.start()
	if started then
		return
	end
	started = true
	while #pool.Player + #pool.Enemy < UI.nameplates.poolSize do
		table.insert(pool.Enemy, newPlate("Enemy"))
		if #pool.Player + #pool.Enemy < UI.nameplates.poolSize then
			table.insert(pool.Player, newPlate("Player"))
		end
	end
	EntityTracker.added:Connect(Nameplates.attach)
	EntityTracker.removed:Connect(Nameplates.detach)
	EntityTracker.changed:Connect(function(record: any)
		Nameplates.refresh(record)
	end)
	EntityTracker.localChanged:Connect(Nameplates.setLocalId)
	localId = EntityTracker.peekLocalId()
	for _, record in EntityTracker.all() do
		Nameplates.attach(record)
	end
	stopLoop = Engine.onHeartbeat(function(dt: number)
		sinceUpdate += dt
		if sinceUpdate >= 1 / Quality.params().nameplateHz then
			sinceUpdate = 0
			Nameplates.update()
		end
	end)
end

--- Stops the fade loop (place teardown).
function Nameplates.stop()
	if stopLoop ~= nil then
		stopLoop()
		stopLoop = nil
	end
	started = false
end

return Nameplates
