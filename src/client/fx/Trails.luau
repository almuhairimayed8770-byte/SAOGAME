--!strict
--[[
	Trails: the weapon light trail and the activation light (section 10, section 11).

	`attach(model)` finds the Weapon part (the server's WeaponBuilder names it `Weapon` with
	`TrailStart` at the guard and `TrailEnd` at the tip; placeholder enemy weapons get the
	attachments created here), finds or creates its Trail (width from the weapon data, lifetime
	0.18 s, LightEmission 1, color the weapon's trail token) and a PointLight on the blade.

	`setActive(model, on, kind)`: Art trails are full width in the Art's color; Basic trails are
	thinner and whiter; Smear is full width for the smear frames. Several kinds may be on at once
	(a Smear inside a hit window); the trail stays enabled while any is. The width follows the
	kind that is on, the color follows the swing (Art over Basic): a Basic swing's smear frames
	go full width but stay whiter, and once every kind is off the fading tail keeps the look of
	the swing that drew it (Trail.Color and WidthScale recolor the whole trail).

	`activationLight` turns the blade light on in the trail color and flashes the weapon's
	Highlight white for three frames. `flashWhite` is the two-frame white flash on a Switch
	landing or a parry.

	Budget: at most fx.quality[tier].maxTrails trails are enabled at once; when more rigs are
	swinging, the farthest from the viewer are disabled first. Trails past the tier's distance
	stay off. Every instance is reused; nothing is created per frame.

	`swingDirection(model)`: every Heartbeat the module records each tracked blade tip's
	(TrailEnd's) world position in a short ring (accents.swing.samples long) and answers with
	the unit motion from the oldest of those samples to the newest, or nil when the tip moved
	less than accents.swing.minTravel (or jumped more than maxTravel: a respawn, a teleport).
	The slash crescent and the slash line read it for their tangent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Accents = require(Shared.data.accents)
local Palette = require(Shared.data.palette)
local Weapons = require(Shared.data.weapons)
local Assets = require(Shared.data.assets)
local Engine = require(script.Parent.Engine)
local FrameClock = require(script.Parent.FrameClock)
local Quality = require(script.Parent.Quality)
local OutlineManager = require(script.Parent.OutlineManager)

export type Kind = "Art" | "Basic" | "Smear"

type Entry = {
	model: Instance,
	weapon: BasePart,
	trail: Trail,
	light: PointLight,
	span: number, -- studs between the two attachments (the trail's natural width)
	baseWidth: number, -- studs the weapon data asks for
	token: string,
	color: Color3,
	active: { [string]: boolean },
	swing: Kind, -- the last swing kind on (Art or Basic): the color, and the width once nothing is on
	flashCancel: (() -> ())?,
	flashing: boolean,
	allowed: boolean, -- inside the budget and the distance
	removedCancel: () -> (), -- stops watching the rig for removal
	tip: Attachment, -- TrailEnd: the blade tip swingDirection follows
	tips: { Vector3 }, -- ring of the tip's last world positions
	tipHead: number, -- index of the newest sample in `tips`
	tipCount: number, -- samples recorded so far (at most SWING_SAMPLES)
}

local KIND_PRIORITY: { Kind } = { "Art", "Smear", "Basic" }
local SWING_SAMPLES = math.max(2, Accents.swing.samples)

local Trails = {}

local entries: { [Instance]: Entry } = {}
local stopLoop: (() -> ())? = nil
local sinceRank = 0

local function sequence(keys: { { number } }): NumberSequence
	local points = {}
	for _, key in keys do
		table.insert(points, NumberSequenceKeypoint.new(key[1], key[2]))
	end
	return NumberSequence.new(points)
end

local function findWeaponPart(model: Instance): BasePart?
	for _, descendant in model:GetDescendants() do
		if descendant.Name == "Weapon" and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

-- The unit axis of a part's longest dimension (the blade direction on a placeholder weapon).
local function longAxis(size: Vector3): Vector3
	if size.Y >= size.X and size.Y >= size.Z then
		return Vector3.yAxis
	elseif size.Z >= size.X then
		return Vector3.zAxis
	end
	return Vector3.xAxis
end

local function ensureAttachment(weapon: BasePart, name: string, fraction: number): Attachment
	local existing = weapon:FindFirstChild(name)
	if existing ~= nil and existing:IsA("Attachment") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	local size = weapon.Size
	local axis = longAxis(size)
	local extent = axis:Dot(size)
	attachment.CFrame = CFrame.new(axis * extent * fraction)
	attachment.Parent = weapon
	return attachment
end

-- Trail color token and width: weapon part attributes, then the entity's weapon def, then defaults.
local function resolveStyle(model: Instance, weapon: BasePart): (string, number)
	local token: string? = nil
	local width: number? = nil
	local attributeToken = weapon:GetAttribute(Fx.trail.colorAttribute)
	if typeof(attributeToken) == "string" and Palette.tokens[attributeToken] ~= nil then
		token = attributeToken
	end
	local attributeWidth = weapon:GetAttribute(Fx.trail.widthAttribute)
	if typeof(attributeWidth) == "number" and attributeWidth > 0 then
		width = attributeWidth
	end
	local weaponId = model:GetAttribute("WeaponId")
	if typeof(weaponId) == "string" then
		local def = Weapons.byId(weaponId)
		if def ~= nil then
			token = token or def.trailColor
			width = width or def.trailWidth
		end
	end
	local isEnemy = model:GetAttribute("EntityKind") == "Enemy"
	if token == nil then
		token = if isEnemy then Fx.trail.enemyToken else Fx.trail.defaultToken
	end
	if width == nil then
		width = if isEnemy then Fx.trail.enemyWidth else Fx.trail.defaultWidth
	end
	return token :: string, width :: number
end

local function ensureTrail(weapon: BasePart, start: Attachment, finish: Attachment): Trail
	local existing = weapon:FindFirstChildOfClass("Trail")
	local trail = existing or Instance.new("Trail")
	trail.Name = "Trail"
	trail.Attachment0 = start
	trail.Attachment1 = finish
	trail.Lifetime = Fx.trail.lifetime
	trail.LightEmission = Fx.trail.lightEmission
	trail.MinLength = Fx.trail.minLength
	trail.Transparency = sequence(Fx.trail.transparencyKeys)
	trail.FaceCamera = true
	trail.Enabled = false
	if Assets.isReady(Fx.trail.textureAsset) then
		trail.Texture = Assets.url(Fx.trail.textureAsset)
	end
	if existing == nil then
		trail.Parent = weapon
	end
	return trail
end

local function ensureLight(weapon: BasePart): PointLight
	local existing = weapon:FindFirstChildOfClass("PointLight")
	local light = existing or Instance.new("PointLight")
	light.Name = "ActivationLight"
	light.Range = Fx.activationLight.range
	light.Brightness = Fx.activationLight.brightness
	light.Enabled = false
	if existing == nil then
		light.Parent = weapon
	end
	return light
end

local function activeKind(entry: Entry): Kind?
	for _, kind in KIND_PRIORITY do
		if entry.active[kind] then
			return kind
		end
	end
	return nil
end

local function wantsTrail(entry: Entry): boolean
	return entry.flashing or activeKind(entry) ~= nil
end

-- The swing whose look the trail wears: Art over Basic while either is on, else the last one, so
-- neither a Smear frame nor the fade after the swing changes the color.
local function swingKind(entry: Entry): Kind
	if entry.active.Art then
		return "Art"
	elseif entry.active.Basic then
		return "Basic"
	end
	return entry.swing
end

local function applyAppearance(entry: Entry)
	local swing = swingKind(entry)
	entry.swing = swing
	local kind = activeKind(entry) or swing
	local multiplier = Fx.trail.width[kind] or Fx.trail.width.Art
	local scale = if entry.span > 1e-6 then entry.baseWidth / entry.span else 1
	local widthKeys = {}
	for _, key in Fx.trail.widthKeys do
		table.insert(widthKeys, { key[1], key[2] * scale * multiplier })
	end
	entry.trail.WidthScale = sequence(widthKeys)
	local color = entry.color
	if entry.flashing then
		color = Palette.color3(Fx.trail.flashToken :: any)
	elseif swing == "Basic" then
		color = entry.color:Lerp(Palette.color3("TrailWhite"), Fx.trail.basicWhiteBlend)
	end
	entry.trail.Color = ColorSequence.new(color)
	entry.trail.Enabled = wantsTrail(entry) and entry.allowed
end

-- Re-ranks which active trails are allowed: nearest first, inside the tier's distance, up to maxTrails.
local function rebalance()
	local params = Quality.params()
	local wanting: { { entry: Entry, distance: number } } = {}
	for _, entry in entries do
		if wantsTrail(entry) then
			local position = Engine.modelPosition(entry.model)
			local distance = if position ~= nil then Engine.distanceTo(position) else 0
			table.insert(wanting, { entry = entry, distance = distance })
		else
			entry.allowed = true
		end
	end
	table.sort(wanting, function(a, b)
		return a.distance < b.distance
	end)
	local budget = math.min(params.maxTrails, Fx.budgets.trails)
	for index, item in wanting do
		local allowed = index <= budget and item.distance <= params.trailDistance
		if allowed ~= item.entry.allowed then
			item.entry.allowed = allowed
			applyAppearance(item.entry)
		end
	end
end

--- Finds (or builds) the Trail and PointLight on a rig's Weapon part; returns nil for rigs without one.
function Trails.attach(model: Instance): boolean
	if entries[model] ~= nil then
		return true
	end
	local weapon = findWeaponPart(model)
	if weapon == nil then
		return false
	end
	Trails.start()
	local start = ensureAttachment(weapon, "TrailStart", Fx.trail.placeholderStart)
	local finish = ensureAttachment(weapon, "TrailEnd", Fx.trail.placeholderEnd)
	local token, width = resolveStyle(model, weapon)
	local color = Palette.color3(token :: any)
	local entry: Entry = {
		model = model,
		weapon = weapon,
		trail = ensureTrail(weapon, start, finish),
		light = ensureLight(weapon),
		span = (start.CFrame.Position - finish.CFrame.Position).Magnitude,
		baseWidth = width,
		token = token,
		color = color,
		active = {},
		swing = "Art",
		flashCancel = nil,
		flashing = false,
		allowed = true,
		removedCancel = Engine.onRemoved(model, function()
			Trails.detach(model)
		end),
		tip = finish,
		tips = {},
		tipHead = 0,
		tipCount = 0,
	}
	entry.light.Color = color
	entries[model] = entry
	applyAppearance(entry)
	return true
end

--- Forgets a rig (its instances stay on the weapon; the rig is leaving anyway). Called by the
--- shatter and when the rig leaves the world, so the entry table never grows with dead rigs.
function Trails.detach(model: Instance)
	local entry = entries[model]
	if entry == nil then
		return
	end
	if entry.flashCancel ~= nil then
		entry.flashCancel()
	end
	entry.removedCancel()
	entry.trail.Enabled = false
	entry.light.Enabled = false
	entries[model] = nil
end

--- Turns a trail kind on or off: Art (full width, the Art's color), Basic (thinner, whiter), Smear (full).
function Trails.setActive(model: Instance, on: boolean, kind: Kind)
	if entries[model] == nil and not Trails.attach(model) then
		return
	end
	local entry = entries[model] :: Entry
	entry.active[kind] = if on then true else nil
	applyAppearance(entry)
	rebalance()
end

--- The activation light on the blade (range 8, brightness 2) in the trail color, plus the
--- three-frame SystemWhite flash on the weapon's Highlight when it turns on.
function Trails.activationLight(model: Instance, on: boolean, token: string?)
	if entries[model] == nil and not Trails.attach(model) then
		return
	end
	local entry = entries[model] :: Entry
	if token ~= nil and Palette.tokens[token] ~= nil then
		entry.light.Color = Palette.color3(token :: any)
	else
		entry.light.Color = entry.color
	end
	entry.light.Enabled = on
	if on then
		OutlineManager.flash(model, Fx.activationLight.flashToken, Fx.activationLight.flashFrames)
	end
end

--- Flashes the trail white and on for `frames` rendered frames (Switch landing, parry).
function Trails.flashWhite(model: Instance, frames: number)
	if entries[model] == nil and not Trails.attach(model) then
		return
	end
	local entry = entries[model] :: Entry
	if entry.flashCancel ~= nil then
		entry.flashCancel()
	end
	entry.flashing = true
	applyAppearance(entry)
	rebalance()
	entry.flashCancel = FrameClock.after(frames, function()
		entry.flashing = false
		entry.flashCancel = nil
		applyAppearance(entry)
		rebalance()
	end)
end

--- The trail color token a rig resolved to (for the activation chime); nil when unattached.
function Trails.tokenOf(model: Instance): string?
	local entry = entries[model]
	return if entry ~= nil then entry.token else nil
end

--- True when the rig's trail is currently enabled.
function Trails.isEnabled(model: Instance): boolean
	local entry = entries[model]
	return entry ~= nil and entry.trail.Enabled
end

--- Records each tracked blade tip's world position in its ring (Heartbeat runs it; specs call it).
function Trails.sample()
	for _, entry in entries do
		-- The attachment's world position: its part's frame times its own (Attachment.WorldPosition).
		local position = (entry.weapon.CFrame * entry.tip.CFrame).Position
		entry.tipHead = entry.tipHead % SWING_SAMPLES + 1
		entry.tips[entry.tipHead] = position
		entry.tipCount = math.min(entry.tipCount + 1, SWING_SAMPLES)
	end
end

--- The unit direction the blade tip moved over the last few samples; nil when unknown or still.
function Trails.swingDirection(model: Instance): Vector3?
	local entry = entries[model]
	if entry == nil or entry.tipCount < 2 then
		return nil
	end
	local back = entry.tipCount - 1
	local oldest = entry.tips[(entry.tipHead - 1 - back) % SWING_SAMPLES + 1]
	local motion = entry.tips[entry.tipHead] - oldest
	local travel = motion.Magnitude
	if travel <= Accents.swing.minTravel or travel > Accents.swing.maxTravel then
		return nil
	end
	return motion / travel
end

--- Starts the periodic budget re-rank (rigs move) and follows quality changes.
function Trails.start()
	if stopLoop ~= nil then
		return
	end
	Quality.changed:Connect(function()
		rebalance()
	end)
	stopLoop = Engine.onHeartbeat(function(dt: number)
		Trails.sample()
		sinceRank += dt
		if sinceRank >= Fx.trail.rankInterval then
			sinceRank = 0
			rebalance()
		end
	end)
end

return Trails
