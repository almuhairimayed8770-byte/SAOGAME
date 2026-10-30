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
