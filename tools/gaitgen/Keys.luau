--!strict
--[[
	Shared shapes for the gait generator (tools/gaitgen.luau): joint keys as the clips write them,
	the pinned upper-body source clips in sources/, and the gait plans in Gaits.luau. Positions are
	studs, rotations degrees (X, Y, Z), all in the clip's own conventions (types.luau JointKey).
]]

--- One joint offset as a clip key stores it.
export type JointKey = { pos: { number }?, rot: { number } }

--- Joint name -> offset, one key's worth (or one upper-body pose).
export type Joints = { [string]: JointKey }

--- A key of a source clip: what ClipSampler reads (time, easing, joints).
export type SourceKey = { time: number, easing: string, joints: Joints }

--- A source clip: a looping key list sampled with the game's own ClipSampler.
export type SourceClip = { duration: number, loop: boolean, keys: { SourceKey } }

--- The point of the sole a foot rolls about: heel, toe, sole center, or an outer edge (side-steps).
export type Pivot = "heel" | "toe" | "center" | "left" | "right"

--- A point the swinging foot passes through at time `t`: the sole center in root space (studs),
--- pitch (X+ toes up) and roll (Z+ rolls left) in degrees.
export type SwingPoint = { t: number, x: number, y: number, z: number, pitch: number, roll: number }

--- A swing key whose hip, knee and ankle X are set by hand; hip Y/Z and ankle Z blend from the
--- lift-off solution to the strike solution.
export type SwingJoint = { t: number, hip: number, knee: number, ankle: number }

--- The toe-off of a fast gait: for `duration` s after the lift the foot keeps going back with the
--- ground while the pivot rises `rise` studs and the foot rolls `angle` degrees further (both eased
--- in from the lift), so the toe leaves the field moving with it instead of stopping under the
--- root and skating forward. Keys inside it are solved by IK; one must fall at its end.
export type Peel = { duration: number, rise: number, angle: number }

--- One foot's cycle. It strikes at `ts` on `strikePivot` tipped `strikeAngle` degrees, rolls flat
--- by `flatFrom`, stays flat to `flatTo`, and leaves by `tl` rolled `liftAngle` about `liftPivot`
--- (eased by `liftPower` when set, smoothstep otherwise), then peels off the field (`peel`) when
--- set. (`x`, `z`) is where the flat sole center sits at the strike; while planted it moves against
--- the root's travel. The swing from the lift (or the peel's end) to the next strike follows
--- `swing` points (a Hermite path solved by IK) or `swingJoints`: hand-set keys, and between them
--- (a key the plan does not set) the leg as the clip would play it without that key.
export type Plan = {
	x: number,
	z: number,
	ts: number,
	tl: number,
	strikePivot: Pivot,
	strikeAngle: number,
	flatFrom: number,
	flatTo: number,
	liftPivot: Pivot,
	liftAngle: number,
	liftPower: number?,
	peel: Peel?,
	swing: { SwingPoint }?,
	swingJoints: { SwingJoint }?,
}

export type Plans = { Left: Plan, Right: Plan }

--- A Footstep event (the clip's `events`).
export type Footstep = { time: number, foot: string }

--- Everything one clip is generated from.
export type Gait = {
	duration: number,
	speed: number, -- how fast a planted foot moves back under the root (studs/s)
	dir: Vector3, -- the root's direction of travel (root space)
	keyTimes: { number },
	plans: Plans,
	events: { Footstep },
	comments: { [number]: string }, -- a key's comment line, by key time
	header: { string }, -- the clip's header comment, one line each
	upper: (t: number) -> Joints, -- the root and upper body at time t (legs are solved)
	sheathed: boolean,
	-- Solved as given, then every joint mirrored left <-> right (WalkRight is WalkLeft mirrored).
	mirrored: boolean,
}

local Keys = {}

--- A rotation-only joint key.
function Keys.rot(x: number, y: number, z: number): JointKey
	return { rot = { x, y, z } }
end

--- A joint key that moves and rotates.
function Keys.posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

--- A looping source clip.
function Keys.source(duration: number, keys: { SourceKey }): SourceClip
	return { duration = duration, loop = true, keys = keys }
end

return Keys
