--!strict
--[[
	Nameplates (section 14): over every player a cursor diamond (green / orange / red from the
	Cursor attribute) and the name on hover; over every enemy a red diamond, the name, a short HP
	bar and the Guard Gauge; nothing over bosses (their bars sit at the top of the screen, Phase
	3: the `bossSeen` hook is where BossBars will attach). Plates are pooled BillboardGuis driven
	by EntityTracker.added / removed / changed; they fade past ui.nameplates.distance.

	Death (D-147): the plate holds over the frozen rig through the death freeze, its HP bar empty,
	and goes with the shatter: `hide(model)` takes it on the shatter frame (Shatter's hideRig
	calls it), and a plate nothing hid goes when the shatter is due by the schedule the death
	reaction uses (the kill's hit-stop, Moments.deathDuckDelay, then Combat.deathFreeze). Rigs
	never carry the engine's own name label (RigBuilder: DisplayDistanceType None), so the plate
	is the only name over an enemy.

	A shatter that is coming owns the plate (D-187): the death reaction scheduled it on the
	engine's task clock, which resumes a delay on a frame's start, not on the Heartbeat this
	module checks its own times on, so the same sum on two clocks took the plate a frame before
	the body (measured in Studio: plate at 0.834 s, body at 0.852 s). `expect(model, seconds)`
	(Shatter.expect, called where the shatter is scheduled) moves that plate's fallback to the
	shatter's time plus ui.nameplates.shatterGraceSeconds, so only the shatter's own hide takes
	it on time and the fallback is left for a rig whose shatter never runs on this client.

	A plate sits over the drawn body (D-193): it is adorned to the root part and follows the body
	through choreo/DrawnBody, which moves it in the same step that draws a rush's body ahead of its
	hidden root (D-171), so it never trails a charging boar, stays over a body frozen by a death
	mid-rush, and comes back onto the root with the body when the rush hands back. The fade and
	the hover test read the drawn position too (Engine.modelPosition).

	Respawns (D-177): the engine empties the PlayerGui when the local character respawns, keeping
	only the LayerCollectors whose ResetOnSpawn is false, so the plates' folder goes with it
	(measured in Studio after LoadCharacter: PlayerGui.SkyspireNameplates gone, no plates). Every
	frame (and before a new plate is handed out) the folder is checked: one that left the PlayerGui
	is put back, or rebuilt with a fresh plate for every tracked record (state, HP, the shatter's
	"gone" and its due time carried over) and a fresh pool when the reset destroyed it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(Shared.data.ui)
local Palette = require(Shared.data.palette)
local Combat = require(Shared.data.combat)
local Moments = require(Shared.data.moments)
local Signal = require(Shared.util.Signal)
local Engine = require(script.Parent.Parent.fx.Engine)
local Quality = require(script.Parent.Parent.fx.Quality)
local El = require(script.Parent.lib.El)
local HudLogic = require(script.Parent.HudLogic)
local EntityTracker = require(script.Parent.Parent.controllers.EntityTracker)
local DrawnBody = require(script.Parent.Parent.choreo.DrawnBody)

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
	-- Taken by the shatter: hidden until the plate goes back to the pool.
	gone: boolean,
	-- When the record turned Dead, the Engine.now() the shatter is due (the fallback).
	dueAt: number?,
	-- A shatter is scheduled for this rig: the Engine.now() past which the plate goes even if that
	-- shatter never hid it (its time plus the grace). Overrides dueAt.
	expected: number?,
	-- The Heartbeat that first found `expected` passed; the plate goes on a later one (D-191).
	overdueBeat: number?,
}

local Nameplates = {}

--- Fires with the record of a boss entity (no plate is drawn; BossBars will listen, Phase 3).
Nameplates.bossSeen = Signal.new() :: Signal.Signal<any>

local plates: { [number]: Plate } = {}
local pool: { [string]: { Plate } } = { Player = {}, Enemy = {} }
local localId: number? = nil
local stopLoop: (() -> ())? = nil
local sinceUpdate = 0
local beats = 0 -- Heartbeats run (the frame count expireDue waits on)
local hover: ((plate: Plate) -> boolean)? = nil
local started = false
local folder: Instance? = nil
-- Where the folder lives: the local PlayerGui (nil under Lune, where the folder stays detached).
local guiSource: (() -> Instance?)? = nil

local function guiParent(): Instance?
	if guiSource ~= nil then
		return guiSource()
	end
	return Engine.playerGui()
end

-- Plates live in their own folder under the PlayerGui and point at rigs through Adornee: a plate
-- parented into a rig would be destroyed with it when the server removes the model, and a pool
-- of destroyed BillboardGuis can never be re-parented (Parent is locked after Destroy). The folder
-- is made here, not through Engine.folder, whose cache would hand back one a respawn destroyed.
local function ensureFolder(): Instance
	if folder == nil then
		local made = Instance.new("Folder")
		made.Name = UI.nameplates.folderName
		local gui = guiParent()
		if gui ~= nil then
			pcall(function()
				made.Parent = gui
			end)
		end
		folder = made
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

-- The plate's own height over its rig's root part.
local function lift(kind: "Player" | "Enemy"): Vector3
	local config = if kind == "Player" then UI.nameplates.player else UI.nameplates.enemy
	return Vector3.new(0, config.offsetStuds, 0)
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
		TextStrokeTransparency = UI.nameplates.strokeTransparency,
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
		StudsOffsetWorldSpace = lift(kind),
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
		gone = false,
		dueAt = nil,
		expected = nil,
		overdueBeat = nil,
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
	DrawnBody.unfollow(plate.gui, lift(plate.kind))
	pcall(function()
		plate.gui.Adornee = nil
	end)
	plate.record = nil
	plate.gone = false
	plate.dueAt = nil
	plate.expected = nil
	plate.overdueBeat = nil
	table.insert(pool[plate.kind], plate)
end

-- Fills the pool up to ui.nameplates.poolSize (start, and after a respawn destroyed it).
local function warmPool()
	while #pool.Player + #pool.Enemy < UI.nameplates.poolSize do
		table.insert(pool.Enemy, newPlate("Enemy"))
		if #pool.Player + #pool.Enemy < UI.nameplates.poolSize then
			table.insert(pool.Player, newPlate("Player"))
		end
	end
end

-- Whether a plate shows: not taken by the shatter, and not past the time it goes without one. A
-- plate waiting for a scheduled shatter is taken by that shatter or by expireDue, never by a check
-- of the time alone.
local function shows(plate: Plate): boolean
	if plate.gone then
		return false
	end
	if plate.expected ~= nil then
		return true
	end
	local due = plate.dueAt
	return due == nil or Engine.now() < due
end

local function drop(plate: Plate)
	plate.gone = true
	plate.gui.Enabled = false
end

-- Plates whose fallback came due without a hide: gone now. A plate waiting for a scheduled shatter
-- goes on the Heartbeat after the first one that found its grace over (D-191): a frame that stalls
-- across the shatter's time ends with the clock past the grace while the engine has not yet
-- resumed the shatter's delay (it does so at the next frame's start), and the plate must not leave
-- a frame before the body.
local function expireDue()
	local now = Engine.now()
	for _, plate in plates do
		if plate.gone then
			continue
		end
		local expected = plate.expected
		if expected ~= nil then
			if now >= expected then
				local seen = plate.overdueBeat
				if seen == nil then
					plate.overdueBeat = beats
				elseif beats > seen then
					drop(plate)
				end
			end
		elseif plate.dueAt ~= nil and not shows(plate) then
			drop(plate)
		end
	end
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
	local stroke = UI.nameplates.strokeTransparency
	plate.name.TextStrokeTransparency = if showName then stroke + (1 - stroke) * transparency else 1
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
	-- A dead rig keeps its plate through the freeze (the HP bar empty) and loses it with the
	-- shatter; a record that is no longer Dead (a revive) holds no shatter time. A scheduled
	-- shatter (expect) may come before the Dead state reaches this client: it holds until a revive.
	if record.state == "Dead" then
		if plate.dueAt == nil then
			plate.dueAt = Engine.now() + Moments.deathDuckDelay() + Combat.deathFreeze
		end
	else
		if plate.dueAt ~= nil then
			plate.expected = nil
			plate.overdueBeat = nil
		end
		plate.dueAt = nil
	end
	plate.gui.Enabled = shows(plate)
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

-- Points a plate at its record's rig: the root when the rig has one, else the model; over the
-- drawn body while a rush draws it ahead of the root (D-193).
local function adorn(plate: Plate, record: any)
	local adornee: Instance? = nil
	pcall(function()
		adornee = record.model.PrimaryPart
	end)
	plate.gui.Adornee = adornee or record.model
	DrawnBody.follow(plate.gui, record.model, lift(plate.kind))
end

-- The folder left the PlayerGui (a respawn's reset, D-177): put it back, or, when the reset
-- destroyed it (and every plate in it), build a new one with a fresh plate for every tracked
-- record and a fresh pool. Returns true when the plates were rebuilt.
local function keepFolder(): boolean
	local current = folder
	if current == nil then
		return false
	end
	local gui = guiParent()
	if current.Parent == gui then
		return false
	end
	if gui ~= nil and pcall(function()
		current.Parent = gui
	end) then
		return false
	end
	folder = nil
	ensureFolder()
	pool.Player = {}
	pool.Enemy = {}
	for id, old in plates do
		local record = old.record
		DrawnBody.unfollow(old.gui)
		local fresh = newPlate(old.kind)
		fresh.record = record
		fresh.gone = old.gone
		fresh.dueAt = old.dueAt
		fresh.expected = old.expected
		fresh.overdueBeat = old.overdueBeat
		fresh.alpha = old.alpha
		plates[id] = fresh
		if record ~= nil then
			adorn(fresh, record)
			Nameplates.refresh(record)
		end
		-- Player names wait for the next update's hover test, as on attach.
		applyAlpha(fresh, old.alpha, fresh.kind == "Enemy")
	end
	if started then
		warmPool()
	end
	return true
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
	-- A respawn may have emptied the PlayerGui this frame: never hand out a plate it destroyed.
	keepFolder()
	local plate = acquire(kind)
	plate.record = record
	plates[record.id] = plate
	adorn(plate, record)
	plate.gone = false
	plate.dueAt = nil
	plate.expected = nil
	plate.overdueBeat = nil
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

--- The shatter takes `model`'s plate: hidden now and until it goes back to the pool. Called by
--- Shatter's hideRig on the frame the rig turns to shards (a model with no plate is ignored).
function Nameplates.hide(model: Instance)
	for _, plate in plates do
		local record = plate.record
		if record ~= nil and record.model == model then
			plate.gone = true
			plate.gui.Enabled = false
		end
	end
end

--- A shatter is scheduled for `model` in `seconds` (Shatter.expect, from the death reaction): its
--- plate waits for that shatter's hide, and goes on its own only ui.nameplates.shatterGraceSeconds
--- past the shatter's time, so a fallback never takes it before a shatter that is coming (D-187).
function Nameplates.expect(model: Instance, seconds: number)
	local at = Engine.now() + seconds + UI.nameplates.shatterGraceSeconds
	for _, plate in plates do
		local record = plate.record
		if record ~= nil and record.model == model then
			plate.expected = at
			plate.overdueBeat = nil
		end
	end
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
		local screen, visible = (camera :: any):WorldToViewportPoint(position + lift(plate.kind))
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
	keepFolder()
	expireDue()
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

--- The folder the plates live in (tests).
function Nameplates.folder(): Instance
	return ensureFolder()
end

--- Replaces where the plates' folder lives (tests stand in a PlayerGui); nil restores the local
--- PlayerGui. The next check moves the folder there.
function Nameplates.setGuiParent(source: (() -> Instance?)?)
	guiSource = source
end

-- The per-frame work: the folder kept in the PlayerGui (a respawn's reset rebuilds it on the
-- next frame at the latest), a plate whose shatter came due goes on that frame, not at the
-- tier's rate, and the fade and hover at the tier's rate.
local function heartbeat(dt: number)
	beats += 1
	keepFolder()
	expireDue()
	sinceUpdate += dt
	if sinceUpdate >= 1 / Quality.params().nameplateHz then
		sinceUpdate = 0
		Nameplates.update()
	end
end

--- Runs one frame of the Heartbeat loop by hand (tests).
function Nameplates.step(dt: number)
	heartbeat(dt)
end

--- Wires EntityTracker and starts the fade / hover loop.
function Nameplates.start()
	if started then
		return
	end
	started = true
	warmPool()
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
	stopLoop = Engine.onHeartbeat(heartbeat)
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
