--!strict
--[[
	LabPlayback: the ClipLab's two views paced as the game plays a clip (D-653; AT 532(m),
	533(a)), apart from the lab's script so they run in Lune.

	Walk pace: a rig's data walk (choreo.luau rigs[rig].walk) played as RigDriver plays it at a
	share of the rig's walkSpeed (rigs.luau): its clip rate speed / walkSpeed, never under
	stride.rateFloor, its weight against the rig's idle by LocomotionState.gaitWeights (the walk
	alone from rateFloor of walkSpeed up), and the rig carried along its facing at that speed so a
	planted foot holds the stage as it does the field; it is put back on its pedestal every
	dev.luau clipLab.walkLoopSeconds. The lab cycles the share through clipLab.walkShares and back
	to in place (the clip at its own rate, as before).

	Play once: a one-shot played once over the rig's idle (choreo.luau rigs[rig].idle) with its own
	blend in and out (the clip's, else choreo.luau blendOut: as the game plays a reaction or an
	attack over the locomotion), the idle shown clipLab.onceIdleSeconds after the clip has blended
	out, then played again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChoreoData = require(Shared.data.choreo)
local Rigs = require(Shared.data.rigs)
local LocomotionState = require(script.Parent.Parent.choreo.LocomotionState)

local Stride = ChoreoData.locomotion.stride

export type WalkPace = {
	speed: number, -- studs a second the rig is carried at
	rate: number, -- the walk clip's rate
	walk: number, -- the walk's weight
	idle: number, -- the idle's weight under it
}

local LabPlayback = {}

--- The rig's data walk clip id, or nil (a rig the game walks on a blend space, or none).
function LabPlayback.walkOf(rigId: string): string?
	local clips = ChoreoData.rigs[rigId]
	return if clips ~= nil then clips.walk else nil
end

--- The rig's data idle clip id, or nil.
function LabPlayback.idleOf(rigId: string): string?
	local clips = ChoreoData.rigs[rigId]
	return if clips ~= nil then clips.idle else nil
end

--- The rig's walk at `share` of its walkSpeed, as RigDriver plays it (`walkDuration`: the walk
--- clip's length). Nil for a rig with no data walk or walkSpeed.
function LabPlayback.walkPace(rigId: string, share: number, walkDuration: number): WalkPace?
	local rig = Rigs[rigId]
	if LabPlayback.walkOf(rigId) == nil or rig == nil or typeof(rig.walkSpeed) ~= "number" or rig.walkSpeed <= 0 then
		return nil
	end
	local walkSpeed: number = rig.walkSpeed
	local speed = math.max(0, share) * walkSpeed
	local walk, _, _, idle = LocomotionState.gaitWeights(speed, walkSpeed, walkDuration)
	return {
		speed = speed,
		rate = math.max(speed / walkSpeed, Stride.rateFloor),
		walk = walk,
		idle = idle,
	}
end

--- Where a rig set off from `origin` (its pedestal's pivot) stands `elapsed` seconds on, carried
--- along its facing at `speed` and put back on `origin` every `loopSeconds`.
function LabPlayback.carried(origin: CFrame, speed: number, elapsed: number, loopSeconds: number): CFrame
	local into = if loopSeconds > 0 then elapsed % loopSeconds else elapsed
	return origin + origin.LookVector * speed * into
end

--- The share after `current` in `shares`: in place (nil) leads to the first, the last back to nil.
function LabPlayback.nextShare(current: number?, shares: { number }): number?
	if current == nil then
		return shares[1]
	end
	local index = table.find(shares, current)
	if index == nil or index >= #shares then
		return nil
	end
	return shares[index + 1]
end

return LabPlayback
