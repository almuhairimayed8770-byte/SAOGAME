--!strict
--[[
	The body the gait generator poses: the hit matrix's standing player on its field
	(tools/hitmatrix/HitMatrix.luau HitMatrix.standing, the PlayerR15 rig with the sword in hand),
	with the rig's joints read once (Pose.chain) so each forward-kinematics solve is plain arithmetic.
]]

local HitMatrix = require("../hitmatrix/HitMatrix")
local Ik = require("./Ik")

export type Rig = {
	ClipSampler: any, -- src/shared/choreo/ClipSampler, loaded through the harness
	locomotion: any, -- src/shared/data/choreo locomotion (runSpeed, sprintSpeed)
	base: CFrame, -- the root part standing on the field
	ground: number, -- the field's top, in root space (Y)
	footSize: Vector3, -- the LeftFoot part's size (both feet match)
	solve: (offsets: Ik.Offsets) -> Ik.Solved, -- every part's world frame under the offsets
}

local Rig = {}

-- How far a box reaches below its center along world Y.
local function halfHeight(cframe: CFrame, size: Vector3): number
	local half = size * 0.5
	return math.abs(cframe.RightVector.Y) * half.X
		+ math.abs(cframe.UpVector.Y) * half.Y
		+ math.abs(cframe.LookVector.Y) * half.Z
end

--- Builds the standing body through the test harness (tests/_harness/Harness.luau).
function Rig.new(Harness: any): Rig
	local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
	local Pose = Harness.load("src/shared/choreo/Pose")
	local Choreo = Harness.load("src/shared/data/choreo")
	local avatar, field = HitMatrix.standing(Harness)
	local model = avatar.model
	local base: CFrame = avatar.base
	local fieldFrame: CFrame = field.CFrame
	local fieldTop = fieldFrame.Position.Y + halfHeight(fieldFrame, field.Size)
	-- The sword stays in the hand, so the joints never change: one chain serves every solve.
	local chain = Pose.chain(model)
	return {
		ClipSampler = ClipSampler,
		locomotion = Choreo.locomotion,
		base = base,
		ground = fieldTop - base.Position.Y,
		footSize = model:FindFirstChild("LeftFoot", true).Size,
		solve = function(offsets: Ik.Offsets): Ik.Solved
			return Pose.solve(model, base, offsets, chain)
		end,
	}
end

return Rig
