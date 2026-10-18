--!strict
--[[
	SheathState: where one rig's sword is and which sheath clip to play (pure, no Instances).

		local state = SheathState.new("Back")
		local out = state:step(dt, { target = drawn, cut = false, covered = false, drawing = false, sheathing = false, hold = false })
		-- out.place: the new place when this step moved the sword; out.play / out.stop: "Draw" or "Sheathe"
		state:onEvent("WeaponDraw", input)  -- the new place, or nil when the event is stale

	The target is what the server's Drawn attribute (or the local player's own prediction) wants.
	A "cut" is a live attack, Guard, GuardHit or Parry clip: those start with the sword in the hand
	(a draw-cut), so the sword jumps there and no Draw clip plays. Otherwise a true target plays
	Draw and the WeaponDraw event moves the sword to the hand; a target that stays false for
	sheath.sheatheDelay plays Sheathe and its WeaponSheathe event moves the sword to the back. A
	clip that ends before its event (cut short, or a Roblox clip without markers) still lands the
	sword where the target wants it; a clip this state stopped itself does not count. Nothing
	starts while the fighter is dead.

	The sword only changes hands where the hand is. While a clip above the sheath clips hides the
	right arm ("covered": a turn, a landing, a dodge, a stagger), the hand is not at the hilt, so
	Draw and Sheathe wait; one that has not moved the sword yet stops and plays again once the arm
	is free, and an event fired under the cover is ignored.

	Each step first settles the clips that just ended, then applies the cut, then the target, so a
	clip that ends without its event never plays again in the same step.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)

export type Place = "Hand" | "Back"
export type Clip = "Draw" | "Sheathe"

export type Input = {
	target: boolean, -- drawn wanted: the Drawn attribute, or the local prediction
	cut: boolean, -- a live handle (not stopping, not done) whose clip has `attack` or is in sheath.drawCutClips
	covered: boolean, -- a live clip above Draw and Sheathe keys the right arm, so the hand is not at the hilt
	drawing: boolean, -- the Draw clip is playing and not stopping
	sheathing: boolean, -- the Sheathe clip is playing and not stopping
	hold: boolean, -- the fighter is Dead: nothing starts
}

export type Output = { place: Place?, play: Clip?, stop: Clip? }

export type Config = typeof(ChoreoData.sheath)

export type SheathState = {
	place: Place,
	step: (self: SheathState, dt: number, input: Input) -> Output,
	onEvent: (self: SheathState, kind: string, input: Input) -> Place?,
}

local DRAW_EVENT = "WeaponDraw"
local SHEATHE_EVENT = "WeaponSheathe"

local SheathState = {}
SheathState.__index = SheathState

--- A state with the sword at `place` and no clip playing; `config` defaults to choreo.luau sheath.
function SheathState.new(place: Place, config: Config?): SheathState
	local self = setmetatable({
		place = place,
		config = config or ChoreoData.sheath,
		falseFor = 0, -- seconds the target has been false
		wasDrawing = false,
		wasSheathing = false,
		stoppedDraw = false, -- this state stopped the Draw clip itself
		stoppedSheathe = false,
	}, SheathState)
	return (self :: any) :: SheathState
end

function SheathState.step(self: any, dt: number, input: Input): Output
	local out: Output = {}
	-- A clip that ended on its own (not stopped here): it ran out or something else cut it short.
	local drawEnded = self.wasDrawing and not input.drawing and not self.stoppedDraw
	local sheatheEnded = self.wasSheathing and not input.sheathing and not self.stoppedSheathe
	self.wasDrawing = input.drawing
	self.wasSheathing = input.sheathing
	if not input.drawing then
		self.stoppedDraw = false
	end
	if not input.sheathing then
		self.stoppedSheathe = false
	end
	if input.hold then
		return out
	end
	local before: Place = self.place

	-- A clip that ended before its event still lands the sword where the target wants it. Under a
	-- cover the hand is elsewhere: the sword stays, and the clip plays again once the arm is free.
	local covered = input.covered == true
	if not covered then
		if drawEnded and input.target and self.place == "Back" then
			self.place = "Hand"
		elseif sheatheEnded and not input.target and not input.cut and self.place == "Hand" then
			self.place = "Back"
		end
	end

	if input.cut then
		-- The draw-cut: the clip starts with the sword in the hand.
		self.falseFor = 0
		if self.place == "Back" then
			self.place = "Hand"
			if input.drawing then
				out.stop = "Draw"
			elseif input.sheathing then
				out.stop = "Sheathe"
			end
		elseif input.sheathing then
			out.stop = "Sheathe"
		end
	elseif input.target then
		self.falseFor = 0
		if input.sheathing then
			-- Reversed mid-sheathe; if the sword already went back, Draw plays next step.
			out.stop = "Sheathe"
		elseif self.place == "Back" then
			if covered then
				-- The hand cannot reach the hilt under the cover: a Draw that has not taken the
				-- sword yet stops, and Draw starts again once the arm is free.
				if input.drawing then
					out.stop = "Draw"
				end
			elseif not input.drawing then
				out.play = "Draw"
			end
		end
	else
		self.falseFor += dt
		if input.drawing then
			out.stop = "Draw"
		elseif self.place == "Hand" then
			if input.sheathing then
				-- A Sheathe that has not put the sword away yet stops under a cover.
				if covered then
					out.stop = "Sheathe"
				end
			elseif not covered and self.falseFor >= self.config.sheatheDelay then
				out.play = "Sheathe"
			end
		end
	end

	if out.stop == "Draw" then
		self.stoppedDraw = true
	elseif out.stop == "Sheathe" then
		self.stoppedSheathe = true
	end
	if self.place ~= before then
		out.place = self.place
	end
	return out
end

--- The place a WeaponDraw or WeaponSheathe event moves the sword to, or nil when the event no
--- longer fits the target (a late event from a clip that was stopped), the arm is covered (the hand
--- is not at the hilt) or the sword is already there.
function SheathState.onEvent(self: any, kind: string, input: Input): Place?
	if input.covered then
		return nil
	end
	local place: Place? = nil
	if kind == DRAW_EVENT and (input.target or input.cut) then
		place = "Hand"
	elseif kind == SHEATHE_EVENT and not input.target and not input.cut then
		place = "Back"
	end
	if place == nil or place == self.place then
		return nil
	end
	self.place = place
	return place
end

return SheathState
