--!strict
--[[
	GaitHandOff: how an attack takes the body from a moving gait (D-404).

	An attack clip is authored from the drawn stance and blends in over its own blendIn (4 to 9
	frames). Cut over a running body, that blend crossed the run's stride and arm swing into the
	attack's first pose in a frame or two: a foot or an upper arm turned up to 31 degrees in one
	frame (dev.luau review.audit.popDegrees is 20). So when an attack starts while a gait clip
	shows, the gait's phase stands where the attack found it (Locomotion) and the attack takes each
	joint choreo.luau locomotion.handOff lists over that joint's own blend in (Mixer.handOff): the
	data's seconds, or the clip's own blendIn when longer, times the joint's factor. Every blend is
	done by the attack's first strike key (ContactPredictor.strikeKey), the pose its hit is drawn at
	(tools/validators/choreo.luau): the server counts the swing from the clip's pose alone, and the
	blade the eye sees on the contact frame is that pose. ClipAudit's Run@ plans play the same
	hand-off.

		local blends = GaitHandOff.blends(clip) -- { [joint]: seconds }
		if GaitHandOff.applies(clip) then mixer:handOff(handle, blends) end

	A dodge (D-528) takes the body the same way from any stance or gait it cuts nothing in, over
	choreo.luau locomotion.dodgeHandOff's per-joint seconds, and the gait's phase and blend stand
	under it until it lets go (Locomotion). A dodge that played to its end hands the legs back at
	dodgeHandOff.resumePhase, the point of the stride that fits its landing (D-609). A turn in
	place it cuts (dodgeHandOff.takesFrom) is a stance too: the dodge takes the body from it over
	the same blends, and the turn stands under it until they have come in (D-613).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ChoreoData = require(Shared.data.choreo)
local Types = require(Shared.types)

local GaitHandOff = {}

--- True for a clip the hand-off takes the body for: an attack.
function GaitHandOff.applies(clip: Types.ClipDef): boolean
	return clip.attack == true
end

-- The dodge clips' ids (choreo.luau locomotion.dodgeHandOff.clips) and their joints' blends.
local DODGES: { [string]: boolean } = {}
for _, name in ChoreoData.locomotion.dodgeHandOff.clips do
	DODGES[ChoreoData.locomotion.clipPrefix .. name] = true
end

--- True for a dodge clip (D-528): it takes the body over locomotion.dodgeHandOff's blends from
--- any stance or gait, and the gait stands under it until it lets go.
function GaitHandOff.dodges(clip: Types.ClipDef): boolean
	return DODGES[clip.id] == true
end

--- True while a dodge clip plays on `mixer` and holds the body (not letting go). No allocation.
function GaitHandOff.dodgeLive(mixer: any): boolean
	for id in DODGES do
		local handle = mixer:find(id)
		if handle ~= nil and not handle.done then
			return true
		end
	end
	return false
end

--- D-657: the dodge clip playing on `mixer` whose pose hides the gait, or nil: one that holds
--- the body (not letting go) at its whole weight, its envelope and every hand-off joint's own
--- blend come in. A dodge keys every joint a gait clip keys, so the gait's weights may move under
--- it unseen. A joint left to a live sheath clip (D-580) never comes in: such a dodge hides none.
--- No allocation.
function GaitHandOff.coveringDodge(mixer: any): any?
	for id in DODGES do
		local handle = mixer:find(id)
		if handle ~= nil and not handle.done and handle.weight >= 1 and handle.fade >= 1 then
			local covers = true
			local fades = handle.jointFade
			if fades ~= nil then
				for _, fade in fades do
					if fade < 1 then
						covers = false
						break
					end
				end
			end
			if covers then
				return handle
			end
		end
	end
	return nil
end

-- The one-shots a dodge takes the body from over its joints' blends (dodgeHandOff.takesFrom), by
-- clip id, and the longest of those blends.
local TAKES_FROM: { [string]: boolean } = {}
for _, name in ChoreoData.locomotion.dodgeHandOff.takesFrom do
	TAKES_FROM[ChoreoData.locomotion.clipPrefix .. name] = true
end
local LONGEST_DODGE_BLEND = 0
for _, seconds in ChoreoData.locomotion.dodgeHandOff.joints do
	LONGEST_DODGE_BLEND = math.max(LONGEST_DODGE_BLEND, seconds)
end

--- True for a locomotion one-shot a dodge takes the body from as from a stance (D-613): a turn
--- in place, not an action to cut.
function GaitHandOff.dodgeTakesFrom(clip: Types.ClipDef): boolean
	return TAKES_FROM[clip.id] == true
end

--- The longest of the dodge's joint blends (seconds): a one-shot it takes the body from stands
--- under it this long.
function GaitHandOff.dodgeBlendSeconds(): number
	return LONGEST_DODGE_BLEND
end

--- Each listed joint's blend in (seconds) for a dodge taking the body (D-528): the data's own
--- table, read only.
function GaitHandOff.dodgeBlends(): { [string]: number }
	return ChoreoData.locomotion.dodgeHandOff.joints
end

--- Each listed joint's blend in (seconds) for `clip` taking the body from a moving gait. A fresh
--- table each call (an attack starts a few times a second at most).
function GaitHandOff.blends(clip: Types.ClipDef): { [string]: number }
	local config = ChoreoData.locomotion.handOff
	local base = math.max(clip.blendIn or ChoreoData.blendIn, config.seconds)
	local blends: { [string]: number } = {}
	for name, factor in config.joints do
		blends[name] = base * factor
	end
	return blends
end

return GaitHandOff
