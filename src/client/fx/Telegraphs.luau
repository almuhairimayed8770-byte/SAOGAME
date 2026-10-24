--!strict
--[[
	Telegraphs (sections 6 and 11): the enemy's wind-up, drawn by the client from the broadcast
	so it is never late. A Highlight fill on the enemy's weapon part in TelegraphWhite / Yellow /
	Red, plus a flat ground decal (a line, a cone fan or a circle of thin pooled parts, textured
	when the decal assets exist) that fades in over the wind-up and vanishes at the strike. The
	accessibility intensity comes from the HUD setting; its floor is still visible.

	A rig with no weapon part (the boar: its tusks are its body) is filled whole through its own
	outline Highlight (OutlineManager.tint), never a second Highlight on the same model: the engine
	draws one Highlight per adornee, and the left-over fill Highlight kept a boar from ever showing
	a hit's white (issue 3).

	On the server's beat (D-172): `show` takes how long ago the server began the wind-up (`lateBy`,
	the remote's way here), so the telegraph ends when the server's wind-up does, and `delay` moves
	that end by each pause the server gives the attack (HitConfirmed attackPause).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Palette = require(Shared.data.palette)
local Assets = require(Shared.data.assets)
local Types = require(Shared.types)
local Engine = require(script.Parent.Engine)
local Quality = require(script.Parent.Quality)
local TelegraphShapes = require(script.Parent.TelegraphShapes)
local OutlineManager = require(script.Parent.OutlineManager)
local SfxPool = require(script.Parent.Parent.audio.SfxPool)
local MusicDirector = require(script.Parent.Parent.audio.MusicDirector)
local HudLogic = require(script.Parent.Parent.ui.HudLogic)

type Active = {
	model: Instance,
	kind: string,
	windUp: number,
	start: number,
	highlight: Highlight?, -- the weapon's fill; nil when the rig's own outline is tinted instead
	color: Color3,
	release: () -> (),
	pieces: { BasePart },
}

local Telegraphs = {}

local actives: { [Instance]: Active } = {}
local highlights: { [Instance]: Highlight } = {}
local blockPool: { BasePart } = {}
local cylinderPool: { BasePart } = {}
local folder: Instance? = nil
local stopLoop: (() -> ())? = nil
local intensity: number? = nil
local intensitySource: (() -> number)? = nil

local function ensureFolder(): Instance
	if folder == nil then
		folder = Engine.folder(workspace, "FxTelegraphs")
	end
	return folder :: Instance
end

local function newPiece(circle: boolean): BasePart
	local part = Instance.new("Part")
	part.Name = if circle then "TelegraphCircle" else "TelegraphPiece"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	if circle then
		part.Shape = Enum.PartType.Cylinder
	end
	local decal = Instance.new("Decal")
	decal.Name = "Decal"
	decal.Face = if circle then Enum.NormalId.Right else Enum.NormalId.Top
	decal.Transparency = 1
	decal.Parent = part
	part.Parent = ensureFolder()
	return part
end

local function acquire(circle: boolean): BasePart
	local pool = if circle then cylinderPool else blockPool
	local part = table.remove(pool)
	if part == nil then
		part = newPiece(circle)
	end
	return part :: BasePart
end

local function release(part: BasePart)
	part.Transparency = 1
	local decal = part:FindFirstChild("Decal")
	if decal ~= nil and decal:IsA("Decal") then
		decal.Transparency = 1
	end
	local circle = part.Name == "TelegraphCircle"
	table.insert(if circle then cylinderPool else blockPool, part)
end

local function findWeaponPart(model: Instance): BasePart?
	for _, descendant in model:GetDescendants() do
		if descendant.Name == "Weapon" and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function highlightFor(model: Instance): Highlight
	local existing = highlights[model]
	if existing ~= nil then
		return existing
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "TelegraphFill"
	highlight.OutlineTransparency = Fx.telegraph.outlineTransparency
	highlight.FillTransparency = 1
	highlight.DepthMode = (Enum.HighlightDepthMode :: any)[Fx.outline.depthMode]
	highlight.Enabled = false
	highlight.Parent = model
	highlights[model] = highlight
	-- A rig the server removes takes its Highlight with it; drop our handle and any live telegraph.
	Engine.onRemoved(model, function()
		Telegraphs.forget(model)
	end)
	return highlight
end

local function currentIntensity(): number
	if intensitySource ~= nil then
		return HudLogic.telegraphIntensity(intensitySource())
	end
	return HudLogic.telegraphIntensity(intensity)
end

local function placePiece(part: BasePart, piece: TelegraphShapes.Piece, color: Color3, textureKind: string)
	local center = Engine.toVector(piece.center)
	local size = Engine.toVector(piece.size)
	if piece.circle then
		-- A cylinder's axis is X; stand it on its side so the flat face points up.
		part.Size = Vector3.new(size.Y, size.X, size.Z)
		part.CFrame = CFrame.new(center) * CFrame.Angles(0, piece.yaw, 0) * CFrame.Angles(0, 0, math.rad(90))
	else
		part.Size = size
		part.CFrame = CFrame.new(center) * CFrame.Angles(0, piece.yaw, 0)
	end
	part.Color = color
	local decal = part:FindFirstChild("Decal")
	if decal ~= nil and decal:IsA("Decal") then
		local assetName = Fx.telegraph.decal.textureAssets[textureKind]
		if assetName ~= nil and Assets.isReady(assetName) then
			decal.Texture = Assets.url(assetName)
			decal.Color3 = color
		else
			decal.Texture = ""
		end
	end
end

local function applyAlpha(active: Active, now: number)
	local elapsed = now - active.start
	local level = currentIntensity()
	local alpha = TelegraphShapes.decalAlpha(elapsed, active.windUp, level)
	for _, part in active.pieces do
		part.Transparency = 1 - alpha
		local decal = part:FindFirstChild("Decal")
		if decal ~= nil and decal:IsA("Decal") then
			-- With a texture the decal carries the shape and the part stays nearly clear.
			if decal.Texture ~= "" then
				decal.Transparency = 1 - alpha
				part.Transparency = 1
			else
				decal.Transparency = 1
			end
		end
	end
	local fill = TelegraphShapes.fillTransparency(elapsed, active.windUp, level)
	local highlight = active.highlight
	if highlight ~= nil then
		highlight.FillTransparency = fill
	else
		OutlineManager.tint(active.model, active.color, fill)
	end
end

local function step()
	local now = Engine.now()
	-- Hiding clears the current key of `actives`, which Luau allows mid-traversal (no per-frame copy).
	for model, active in actives do
		if TelegraphShapes.isOver(now - active.start, active.windUp) then
			Telegraphs.hide(model)
		else
			applyAlpha(active, now)
		end
	end
	if next(actives) == nil and stopLoop ~= nil then
		stopLoop()
		stopLoop = nil
	end
end

local function ensureLoop()
	if stopLoop ~= nil then
		return
	end
	stopLoop = Engine.onHeartbeat(function()
		step()
	end)
end

--- Draws the wind-up for an enemy: weapon fill plus a ground shape at `origin` facing `facing`.
--- `lateBy`: seconds since the server began the wind-up (the telegraph is that far into it).
function Telegraphs.show(
	model: Instance,
	kind: string,
	windUp: number,
	origin: Vector3,
	facing: Vector3,
	shape: Types.TelegraphShape?,
	lateBy: number?
)
	if actives[model] ~= nil then
		Telegraphs.hide(model)
	end
	local token = TelegraphShapes.token(kind)
	local color = Palette.color3(token :: any)
	local weapon = findWeaponPart(model)
	local highlight: Highlight? = nil
	if weapon ~= nil then
		local fill = highlightFor(model)
		fill.Adornee = weapon
		fill.FillColor = color
		fill.FillTransparency = 1
		fill.Enabled = true
		highlight = fill
	end
	-- The weapon's fill is a Highlight of its own; a whole-rig tint can light an outline the
	-- budget had off. Either way it holds a slot while it shows.
	local releaseSlot = OutlineManager.reserve()

	local pieces: { BasePart } = {}
	if Quality.params().groundDecals then
		local resolved: TelegraphShapes.Shape? = if shape ~= nil
			then { kind = shape.kind, length = shape.length, width = shape.width }
			else nil
		local layout = TelegraphShapes.pieces(resolved, Engine.toTable(origin), Engine.toTable(facing))
		local textureKind = if resolved ~= nil then resolved.kind else TelegraphShapes.defaultShape().kind
		for _, piece in layout do
			local part = acquire(piece.circle)
			placePiece(part, piece, color, textureKind)
			table.insert(pieces, part)
		end
	end

	local now = Engine.now()
	local active: Active = {
		model = model,
		kind = kind,
		windUp = math.max(windUp, 0),
		start = now - math.max(0, lateBy or 0),
		highlight = highlight,
		color = color,
		release = releaseSlot,
		pieces = pieces,
	}
	actives[model] = active
	applyAlpha(active, now)
	ensureLoop()

	local sound = Fx.telegraph.sounds[kind] or Fx.telegraph.sounds.Normal
	SfxPool.play(sound, origin)
	MusicDirector.noteTelegraph()
end

--- Moves the end of an enemy's telegraph by `seconds` (negative: earlier): the server paused (or
--- did not pause) its wind-up by that much. A rig showing none is left alone.
function Telegraphs.delay(model: Instance, seconds: number)
	local active = actives[model]
	if active ~= nil then
		active.start += seconds
	end
end

--- Removes an enemy's telegraph (the strike landed, the enemy died or was interrupted).
function Telegraphs.hide(model: Instance)
	local active = actives[model]
	if active == nil then
		return
	end
	actives[model] = nil
	local highlight = active.highlight
	if highlight ~= nil then
		highlight.Enabled = false
		highlight.FillTransparency = 1
	else
		OutlineManager.untint(model)
	end
	active.release()
	for _, part in active.pieces do
		release(part)
	end
end

--- Forgets a rig entirely (it left the world).
function Telegraphs.forget(model: Instance)
	Telegraphs.hide(model)
	local highlight = highlights[model]
	if highlight ~= nil then
		highlights[model] = nil
		pcall(function()
			highlight:Destroy()
		end)
	end
end

--- Sets the accessibility intensity (0.5..1; the floor is still visible).
function Telegraphs.setIntensity(value: number?)
	intensity = value
end

--- Binds where the intensity is read from each frame (the HUD's setting), replacing the static value.
function Telegraphs.setIntensitySource(source: (() -> number)?)
	intensitySource = source
end

--- True while an enemy is telegraphing.
function Telegraphs.isShowing(model: Instance): boolean
	return actives[model] ~= nil
end

--- Advances the fades by hand (tests, or outside Heartbeat).
function Telegraphs.step()
	step()
end

--- Nothing to start: loops begin with the first telegraph. Kept for the client's uniform start order.
function Telegraphs.start() end

return Telegraphs
