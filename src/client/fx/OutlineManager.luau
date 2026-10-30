--!strict
--[[
	OutlineManager (section 11): one Highlight per player and enemy within the quality tier's
	outline distance, OutlineColor a near-black of the rig's base color, OutlineTransparency 0,
	FillTransparency 1. The engine renders 31 Highlights at once, so rigs are ranked by importance
	(boss, lock target, party always on) then distance, and the rest are disabled until they rank.
	Telegraphs reserve slots from the same budget for their weapon fills.

	`flash(model, token, frames)` fills the Highlight with a token color for N rendered frames
	(white on a hit, red on a guard break) and then restores it.

	`tint(model, color, fillTransparency)` fills the rig's own Highlight with a telegraph's color
	until `untint`: the wind-up of a rig with no weapon part (the boar's tusks are its body). The
	engine draws one Highlight per adornee, so a second Highlight on the same model (the old
	TelegraphFill) could hide this one, and a boar never showed a hit's white (issue 3). A flash
	over a tint wins for its frames, then the tint comes back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fx = require(Shared.data.fx)
local Palette = require(Shared.data.palette)
local Engine = require(script.Parent.Engine)
local FrameClock = require(script.Parent.FrameClock)
local Quality = require(script.Parent.Quality)
local OutlineRanking = require(script.Parent.OutlineRanking)

export type Importance = OutlineRanking.Importance

type Entry = {
	model: Instance,
	importance: Importance,
	highlight: Highlight,
	ranked: boolean, -- inside the budget on the last rank
	flashCancel: (() -> ())?,
	flashing: boolean,
	tinted: boolean, -- a telegraph's fill (tintColor, tintTransparency) is on
	tintColor: Color3,
	tintTransparency: number,
	suspended: boolean, -- hidden by the shatter
}

local OutlineManager = {}

local entries: { [Instance]: Entry } = {}
local reserved = 0
local stopLoop: (() -> ())? = nil
local sinceRank = 0

local function baseColor(model: Instance): Color3
	for _, name in Fx.outline.basePartNames do
		local part = model:FindFirstChild(name, true)
		if part ~= nil and part:IsA("BasePart") then
			return part.Color
		end
	end
	for _, part in Engine.parts(model) do
		return part.Color
	end
	return Palette.color3("PlaceholderSteel")
end

local function inkFor(model: Instance): Color3
	local base = baseColor(model)
	local rgb = OutlineRanking.inkColor({ base.R, base.G, base.B }, Palette.rgb("OutlineInk"), Fx.outline.inkBlend)
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

local function applyEnabled(entry: Entry)
	entry.highlight.Enabled = not entry.suspended and (entry.ranked or entry.flashing or entry.tinted)
end

-- The fill when no flash is on: the telegraph's tint, else none.
local function applyRestingFill(entry: Entry)
	if entry.tinted then
		entry.highlight.FillColor = entry.tintColor
		entry.highlight.FillTransparency = entry.tintTransparency
	else
		entry.highlight.FillTransparency = Fx.outline.fillTransparency
	end
end

--- Re-ranks every registered rig against the budget and the tier's distance.
function OutlineManager.rerank()
	local params = Quality.params()
	local candidates: { OutlineRanking.Candidate } = {}
	for model, entry in entries do
		if entry.suspended then
			continue
		end
		local position = Engine.modelPosition(model)
		local distance = if position ~= nil then Engine.distanceTo(position) else math.huge
		table.insert(candidates, { key = model, importance = entry.importance, distance = distance })
	end
	local budget = math.max(0, math.min(Fx.outline.budget, Fx.budgets.highlights) - reserved)
	local _, chosen = OutlineRanking.select(candidates, budget, params.outlineDistance)
	for model, entry in entries do
		entry.ranked = chosen[model] == true
		applyEnabled(entry)
	end
end

--- Creates the rig's Highlight (disabled until it ranks) and enters it into the ranking.
function OutlineManager.register(model: Instance, importance: Importance?)
	local existing = entries[model]
	if existing ~= nil then
		if importance ~= nil then
			existing.importance = importance
		end
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "Outline"
	highlight.Adornee = model
	highlight.OutlineColor = inkFor(model)
	highlight.OutlineTransparency = Fx.outline.outlineTransparency
	highlight.FillTransparency = Fx.outline.fillTransparency
	highlight.FillColor = Palette.color3("SystemWhite")
	highlight.DepthMode = (Enum.HighlightDepthMode :: any)[Fx.outline.depthMode]
	highlight.Enabled = false
	highlight.Parent = model
	entries[model] = {
		model = model,
		importance = importance or "Normal",
		highlight = highlight,
		ranked = false,
		flashCancel = nil,
		flashing = false,
		tinted = false,
		tintColor = highlight.FillColor,
		tintTransparency = Fx.outline.fillTransparency,
		suspended = false,
	}
	OutlineManager.rerank()
end

--- Removes the rig's Highlight and frees its slot.
function OutlineManager.unregister(model: Instance)
	local entry = entries[model]
	if entry == nil then
		return
	end
	if entry.flashCancel ~= nil then
		entry.flashCancel()
	end
	entry.highlight:Destroy()
	entries[model] = nil
	OutlineManager.rerank()
end

--- Sets a rig's importance ("Boss" | "Lock" | "Party" | "Normal"); the important ones are always on.
function OutlineManager.setImportance(model: Instance, importance: Importance)
	local entry = entries[model]
	if entry == nil then
		OutlineManager.register(model, importance)
		return
	end
	entry.importance = importance
	OutlineManager.rerank()
end

--- Fills the rig's Highlight with a token color for `frames` rendered frames, then restores it.
function OutlineManager.flash(model: Instance, token: string, frames: number)
	if entries[model] == nil then
		OutlineManager.register(model)
	end
	local entry = entries[model] :: Entry
	if entry.flashCancel ~= nil then
		entry.flashCancel()
	end
	local resolved = if Palette.tokens[token] ~= nil then token else "SystemWhite"
	entry.highlight.FillColor = Palette.color3(resolved :: any)
	entry.highlight.FillTransparency = Fx.outline.flashFillTransparency
	entry.flashing = true
	applyEnabled(entry)
	entry.flashCancel = FrameClock.after(frames, function()
		entry.flashing = false
		entry.flashCancel = nil
		applyRestingFill(entry)
		applyEnabled(entry)
	end)
end

--- Fills the rig's own Highlight with `color` at `fillTransparency` until `untint` (a telegraph on
--- a rig with no weapon part); a flash shows over it for its frames.
function OutlineManager.tint(model: Instance, color: Color3, fillTransparency: number)
	if entries[model] == nil then
		OutlineManager.register(model)
	end
	local entry = entries[model] :: Entry
	entry.tinted = true
	entry.tintColor = color
	entry.tintTransparency = fillTransparency
	if not entry.flashing then
		applyRestingFill(entry)
	end
	applyEnabled(entry)
end

--- Takes a telegraph's tint off the rig's Highlight (a flash showing keeps its frames).
function OutlineManager.untint(model: Instance)
	local entry = entries[model]
	if entry == nil or not entry.tinted then
		return
	end
	entry.tinted = false
	if not entry.flashing then
		applyRestingFill(entry)
	end
	applyEnabled(entry)
end

--- Hides (true) or restores (false) a rig's outline without forgetting it (the shatter hides the rig).
function OutlineManager.suspend(model: Instance, hidden: boolean)
	local entry = entries[model]
	if entry == nil then
		return
	end
	entry.suspended = hidden
	applyEnabled(entry)
	OutlineManager.rerank()
end

--- Takes one Highlight slot from the budget (telegraph weapon fills); returns a release function.
function OutlineManager.reserve(): () -> ()
	reserved += 1
	OutlineManager.rerank()
	local released = false
	return function()
		if released then
			return
		end
		released = true
		reserved = math.max(0, reserved - 1)
		OutlineManager.rerank()
	end
end

--- True when the rig's Highlight is enabled right now.
function OutlineManager.isEnabled(model: Instance): boolean
	local entry = entries[model]
	return entry ~= nil and entry.highlight.Enabled
end

--- Highlights enabled right now (budget checks).
function OutlineManager.enabledCount(): number
	local count = 0
	for _, entry in entries do
		if entry.highlight.Enabled then
			count += 1
		end
	end
	return count + reserved
end

--- Starts the periodic re-rank (rigs move) and follows quality changes.
function OutlineManager.start()
	if stopLoop ~= nil then
		return
	end
	Quality.changed:Connect(function()
		OutlineManager.rerank()
	end)
	stopLoop = Engine.onHeartbeat(function(dt: number)
		sinceRank += dt
		if sinceRank >= Fx.outline.rerankInterval then
			sinceRank = 0
			OutlineManager.rerank()
		end
	end)
end

return OutlineManager
