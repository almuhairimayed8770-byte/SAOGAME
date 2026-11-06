--!strict
--[[
	FlashBudget: the photosensitivity guard for every full-screen flash (the reel style's impact
	frames, the soft dim, and anything later that flips the whole picture's brightness).

	A rolling window of impact.flash.windowSeconds: `request(now, cost, seconds?)` says yes, and
	records the cost, only while the costs still live plus this one stay at or under
	impact.flash.maxPerWindow (3 in any second, the common limit). A refused request records
	nothing. A cost lives until one window after its picture's last luminance change, its finish:
	`now + seconds` when it is recorded, pushed later with `hold` while the picture is still on
	screen. A cost whose finish is f counts while now - f < windowSeconds. Measuring from the end,
	not the start, is what keeps the changes of costs recorded a window apart from falling inside
	one second: every change of a recorded cost happens between its start and its finish, so any
	1-second window that holds changes of two costs holds the later one's start within a window of
	the earlier one's finish, and the later request counted it.

	`claim` is `request` that hands back the recorded entry, so the overlay can `hold` it while it
	shows and `raise` it when a bigger sequence replaces the one showing (only the difference is
	asked for). A picture left on screen while nothing renders has no known end: the overlay holds
	its claim at math.huge (never pruned, so every request meanwhile counts it) and `settle`s it at
	the frame that shows it gone.

	Every caller passes times from the same clock (Engine.now(), the fx package clock); specs pass
	their own numbers.

	The "Reduce flashing" setting is the local player's boolean attribute
	impact.reduceFlashingAttribute (default impact.reduceFlashingDefault), read the way
	Quality.luau reads its attribute: resolved on first use, watched after `start()`, and set by
	hand through `set` (the settings menu, specs). When it is on, ImpactFrames shows the dim (which
	is charged too) instead of any impact sequence.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Signal = require(Shared.util.Signal)
local Impact = require(Shared.data.impact)
local Engine = require(script.Parent.Engine)

-- A recorded cost: when it was asked for, how much, and its picture's last change.
export type Claim = { at: number, cost: number, finish: number, recorded: boolean }

local FlashBudget = {}

--- Fires with the new value whenever the Reduce flashing setting changes.
FlashBudget.changed = Signal.new() :: Signal.Signal<boolean>

local entries: { Claim } = {}
local current: boolean? = nil
local started = false

local function inWindow(entry: Claim, now: number): boolean
	return now - entry.finish < Impact.flash.windowSeconds
end

local function prune(now: number)
	for index = #entries, 1, -1 do
		if not inWindow(entries[index], now) then
			entries[index].recorded = false
			table.remove(entries, index)
		end
	end
end

local function readSetting(): boolean?
	local player = Engine.localPlayer()
	if player == nil then
		return nil
	end
	local ok, value = pcall(function()
		return player:GetAttribute(Impact.reduceFlashingAttribute)
	end)
	if ok and typeof(value) == "boolean" then
		return value
	end
	return nil
end

local function validTime(value: any): boolean
	return typeof(value) == "number" and value == value
end

local function validCost(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value ~= math.huge
end

--- The flash cost still live at `now` (each until one window after its finish).
function FlashBudget.used(now: number): number
	local total = 0
	for _, entry in entries do
		if inWindow(entry, now) then
			total += entry.cost
		end
	end
	return total
end

--- Records `cost` at `now` (its picture ending `seconds` later) and returns the entry when the
--- live costs stay at or under impact.flash.maxPerWindow; nil, recording nothing, otherwise. A
--- cost of 0 is always granted and never recorded (raise records it later if it grows).
function FlashBudget.claim(now: number, cost: number, seconds: number?): Claim?
	if not validTime(now) or not validCost(cost) then
		return nil -- a bad or negative cost must never widen the budget
	end
	local span = if seconds ~= nil and validCost(seconds) then seconds else 0
	prune(now)
	local entry: Claim = { at = now, cost = cost, finish = now + span, recorded = false }
	if cost == 0 then
		return entry
	end
	if FlashBudget.used(now) + cost > Impact.flash.maxPerWindow then
		return nil
	end
	entry.recorded = true
	table.insert(entries, entry)
	return entry
end

--- True, recording `cost` at `now` (its picture ending `seconds` later, 0 when nil), when the
--- window stays at or under impact.flash.maxPerWindow; false, recording nothing, otherwise.
function FlashBudget.request(now: number, cost: number, seconds: number?): boolean
	return FlashBudget.claim(now, cost, seconds) ~= nil
end

--- Raises a claim to `cost` when the other live costs plus `cost` fit the window; false,
--- changing nothing, otherwise. A claim already at or above `cost` is left as it is.
function FlashBudget.raise(claim: Claim, now: number, cost: number): boolean
	if not validTime(now) or not validCost(cost) then
		return false
	end
	if cost <= claim.cost then
		return true
	end
	prune(now)
	local others = FlashBudget.used(now)
	if claim.recorded and inWindow(claim, now) then
		others -= claim.cost
	end
	if others + cost > Impact.flash.maxPerWindow then
		return false
	end
	claim.cost = cost
	claim.finish = math.max(claim.finish, now)
	if not claim.recorded then
		claim.recorded = true
		table.insert(entries, claim)
	end
	return true
end

--- The claim's picture still changes at `at`: it counts until one window after that. A picture
--- left on a frozen frame (nothing renders) is held at math.huge until `settle` says when it went.
function FlashBudget.hold(claim: Claim, at: number)
	if validTime(at) and at > claim.finish then
		claim.finish = at
	end
end

--- The claim's picture made its last change at `at` (one held at math.huge while it sat on a
--- frozen frame): it counts until one window after that.
function FlashBudget.settle(claim: Claim, at: number)
	if validTime(at) then
		claim.finish = at
	end
end

--- The Reduce flashing setting: true swaps every impact sequence for the soft dim.
function FlashBudget.reduced(): boolean
	if current == nil then
		local setting = readSetting()
		current = if setting ~= nil then setting else Impact.reduceFlashingDefault
	end
	return current :: boolean
end

--- Sets the Reduce flashing setting (the settings menu, specs); fires `changed` when it differs.
function FlashBudget.set(value: boolean)
	if typeof(value) ~= "boolean" then
		error(("FlashBudget.set expects a boolean, got %s"):format(typeof(value)))
	end
	if FlashBudget.reduced() == value then
		return
	end
	current = value
	FlashBudget.changed:Fire(value)
end

--- Watches the player's Reduce flashing attribute so a menu change applies live (idempotent).
function FlashBudget.start()
	if started then
		return
	end
	started = true
	FlashBudget.reduced()
	local player = Engine.localPlayer()
	if player == nil then
		return
	end
	pcall(function()
		player:GetAttributeChangedSignal(Impact.reduceFlashingAttribute):Connect(function()
			local value = readSetting()
			FlashBudget.set(if value ~= nil then value else Impact.reduceFlashingDefault)
		end)
	end)
end

--- Forgets every recorded cost and the resolved setting (specs).
function FlashBudget.reset()
	for _, entry in entries do
		entry.recorded = false
	end
	table.clear(entries)
	current = nil
end

return FlashBudget
