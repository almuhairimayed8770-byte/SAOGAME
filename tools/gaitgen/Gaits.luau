--!strict
--[[
	The gait plans: authoring source for tools/gaitgen.luau, not game tunables. For every gait clip
	it owns: the cycle, the key times, each foot's plan (where it plants, how it rolls onto and off
	the sole, the path or leg angles of its swing), the Footsteps, the comment and header lines, and
	the root and upper body as a function of time. The sheathed set's upper bodies are smooth
	cycles written here; the drawn set's are sampled from the pinned source clips in sources/.

	Both sets' legs are twins (D-134, D-128, D-054): every drawn gait reuses its sheathed gait's
	plans, key times, Footsteps and pelvis height, so the drawn feet plant exactly where the sheathed
	ones do and the set crossfade never skates. The ground speeds written here are the clips' own
	(src/shared/data/choreo.luau stride.groundSpeed holds the measured values the game reads).
]]

local roblox = require("@lune/roblox")

local Keys = require("./Keys")
local Rig = require("./Rig")

local SourceRun = require("./sources/Run")
local SourceRunDrawn = require("./sources/RunDrawn")
local SourceSprint = require("./sources/Sprint")
local SourceSprintDrawn = require("./sources/SprintDrawn")
local SourceWalkBackDrawn = require("./sources/WalkBackDrawn")
local SourceWalkForward = require("./sources/WalkForward")
local SourceWalkForwardDrawn = require("./sources/WalkForwardDrawn")
local SourceWalkLeftDrawn = require("./sources/WalkLeftDrawn")
local SourceWalkRightDrawn = require("./sources/WalkRightDrawn")

type Gait = Keys.Gait
type Plan = Keys.Plan
type Joints = Keys.Joints

local Gaits = {}

local Vector3 = roblox.Vector3
local r = Keys.rot
local pr = Keys.posRot

local LEGS: { [string]: boolean } = {
	LeftHip = true,
	LeftKnee = true,
	LeftAnkle = true,
	RightHip = true,
	RightKnee = true,
	RightAnkle = true,
}

local function cosAt(t: number, T: number, lag: number?): number
	return math.cos(2 * math.pi * (t - (lag or 0)) / T)
end

local function sinAt(t: number, T: number, lag: number?): number
	return math.sin(2 * math.pi * (t - (lag or 0)) / T)
end

-- `count` key times evenly over the cycle, each rounded to the microsecond.
local function evenKeys(T: number, count: number): { number }
	local keys = {}
	for i = 0, count - 1 do
		table.insert(keys, math.floor(i * (T / count) * 1e6 + 0.5) / 1e6)
	end
	return keys
end

-- A run's key times: every `step` s through each stance (the left foot's from 0 to `lift`, the
-- right foot's half a cycle later) and on through its peel (`peel` s), then the swing keys
-- `swing` (left foot's half; the right foot's are half a cycle later), each rounded to the
-- microsecond. Dense keys keep the planted foot on its line (a SineInOut key slows a limb at both
-- ends, so between keys the foot runs ahead of the line and back by about a tenth of the ground
-- it covers between them).
local function stanceKeys(T: number, lift: number, step: number, peel: number, swing: { number }): { number }
	local half = {}
	local count = math.floor((lift + peel) / step + 0.5)
	for i = 0, count do
		table.insert(half, i * step)
	end
	for _, t in swing do
		table.insert(half, t)
	end
	local keys = {}
	for _, offset in { 0, T / 2 } do
		for _, t in half do
			table.insert(keys, math.floor((t + offset) * 1e6 + 0.5) / 1e6)
		end
	end
	table.sort(keys)
	return keys
end

-- The right foot's plan: the left one half a cycle later, mirrored.
local function mirrorPlan(plan: Plan, T: number): Plan
	local h = T / 2
	local out = table.clone(plan)
	out.x = -plan.x
	out.ts, out.tl, out.flatFrom, out.flatTo = plan.ts + h, plan.tl + h, plan.flatFrom + h, plan.flatTo + h
	local swingJoints: { Keys.SwingJoint } = {}
	local fromJoints = plan.swingJoints
	if fromJoints then
		for _, e in fromJoints do
			local q = table.clone(e)
			q.t = e.t + h
			table.insert(swingJoints, q)
		end
	end
	out.swingJoints = swingJoints
	local swing: { Keys.SwingPoint } = {}
	local fromSwing = plan.swing
	if fromSwing then
		for _, p in fromSwing do
			local q = table.clone(p)
			q.t = p.t + h
			q.x = -p.x
			q.roll = -p.roll
			table.insert(swing, q)
		end
	end
	out.swing = swing
	if plan.strikePivot == "left" then
		out.strikePivot = "right"
	elseif plan.strikePivot == "right" then
		out.strikePivot = "left"
	end
	if plan.liftPivot == "left" then
		out.liftPivot = "right"
	elseif plan.liftPivot == "right" then
		out.liftPivot = "left"
	end
	if out.strikePivot == "left" or out.strikePivot == "right" then
		out.strikeAngle = -plan.strikeAngle
	end
	if out.liftPivot == "left" or out.liftPivot == "right" then
		out.liftAngle = -plan.liftAngle
	end
	return out
end

-- The mirror of a plan (left foot <-> right foot, x flipped), same times.
local function flipPlan(plan: Plan): Plan
	local out = table.clone(plan)
	out.x = -plan.x
	local swing: { Keys.SwingPoint } = {}
	local fromSwing = plan.swing
	if fromSwing then
		for _, p in fromSwing do
			local q = table.clone(p)
			q.x = -p.x
			q.roll = -p.roll
			table.insert(swing, q)
		end
	end
	out.swing = swing
	local swap: { [string]: Keys.Pivot } = { left = "right", right = "left" }
	out.strikePivot = swap[plan.strikePivot] or plan.strikePivot
	out.liftPivot = swap[plan.liftPivot] or plan.liftPivot
	if plan.strikePivot == "left" or plan.strikePivot == "right" then
		out.strikeAngle = -plan.strikeAngle
	end
	if plan.liftPivot == "left" or plan.liftPivot == "right" then
		out.liftAngle = -plan.liftAngle
	end
	return out
end

-- A source clip sampled at t: every joint `keep` accepts, rotation only.
local function sampledRotations(rig: Rig.Rig, source: Keys.SourceClip, t: number, keep: (string) -> boolean): Joints
	local out: Joints = {}
	for name, offset in rig.ClipSampler.sample(source, t) do
		if keep(name) then
			out[name] = { rot = { offset.rot[1], offset.rot[2], offset.rot[3] } }
		end
	end
	return out
end

-- A source clip sampled at t: every joint `keep` accepts, with its position where it moves.
local function sampledJoints(rig: Rig.Rig, source: Keys.SourceClip, t: number, keep: (string) -> boolean): Joints
	local out: Joints = {}
	for name, offset in rig.ClipSampler.sample(source, t) do
		if keep(name) then
			local pos = offset.pos
			local moved = math.abs(pos[1]) + math.abs(pos[2]) + math.abs(pos[3]) > 1e-9
			out[name] = if moved
				then { pos = { pos[1], pos[2], pos[3] }, rot = { offset.rot[1], offset.rot[2], offset.rot[3] } }
				else { rot = { offset.rot[1], offset.rot[2], offset.rot[3] } }
		end
	end
	return out
end

local function notLeg(joint: string): boolean
	return not LEGS[joint]
end

type WalkBody = {
	pelvis: number,
	bob: number,
	arm: number,
	armX: number,
	lean: number,
	waist: number,
	neck: number,
	pelvisYaw: number,
	shoulderYaw: number,
	roll: number,
	swayX: number,
}

local function walkUpper(t: number, T: number, opts: WalkBody): Joints
	local c = cosAt(t, T) -- 1 at the left plant
	local s = sinAt(t, T)
	local bob = cosAt(t, T / 2) -- 1 at each plant (double support, the body lowest)
	local sway = cosAt(t, T, T / 4) -- 1 at the left foot's mid-stance
	local arm = opts.arm
	return {
		Root = pr(
			opts.swayX * -sway,
			opts.pelvis - opts.bob * bob,
			0,
			opts.lean,
			opts.pelvisYaw * -c,
			opts.roll * sway
		),
		Waist = r(opts.waist, opts.shoulderYaw * c, -opts.roll * sway),
		Neck = r(opts.neck, -(opts.shoulderYaw - opts.pelvisYaw) * c, 0),
		LeftShoulder = r(opts.armX - arm * c, 0, -6 - 1 * s),
		LeftElbow = r(14 - 5 * c, 0, 0),
		LeftWrist = r(-4, 0, 0),
		RightShoulder = r(opts.armX + arm * c, 0, 6 - 1 * s),
		RightElbow = r(14 + 5 * c, 0, 0),
		RightWrist = r(-4, 0, 0),
	}
end

--- Every gait the generator owns, by clip name (player/OneHandedSword/<name>).
function Gaits.build(rig: Rig.Rig): { [string]: Gait }
	local locomotion = rig.locomotion
	local G: { [string]: Gait } = {}

	-----------------------------------------------------------------------------------------------
	-- Run: 0.6 s at runSpeed. Left plants at 0, right at 0.3. Short stance, long flight.
	do
		local T = 0.6
		local left: Plan = {
			x = -0.36,
			ts = 0,
			tl = 0.1,
			z = -0.45,
			strikePivot = "toe",
			strikeAngle = -10,
			flatFrom = 0.025,
			flatTo = 0.05,
			liftPivot = "toe",
			liftAngle = -45,
			peel = { duration = 0.025, rise = 0.12, angle = -10 },
			swingJoints = { -- hip X, knee X, ankle X through the swing (hip Y/Z and ankle Z blend lift to strike)
				{ t = 0.2, hip = 15, knee = -115, ankle = 15 },
				{ t = 0.3, hip = 55, knee = -120, ankle = 0 },
				{ t = 0.325, hip = 66, knee = -112, ankle = -5 },
				{ t = 0.35, hip = 74, knee = -100, ankle = -10 },
				{ t = 0.375, hip = 78, knee = -82, ankle = -12 },
				{ t = 0.4, hip = 76, knee = -62, ankle = -12 },
				{ t = 0.5, hip = 55, knee = -22, ankle = -10 },
			},
		}
		G.Run = {
			duration = T,
			speed = locomotion.runSpeed,
			dir = Vector3.new(0, 0, -1),
			keyTimes = stanceKeys(T, 0.1, 0.0125, 0.025, { 0.2 }),
			plans = { Left = left, Right = mirrorPlan(left, T) },
			events = { { time = 0.02, foot = "Left" }, { time = 0.32, foot = "Right" } },
			comments = {
				[0] = "left foot plants on the ball, the right arm forward",
				[0.05] = "left foot flat under the hips, the body at its lowest",
				[0.1] = "left toe pushes off",
				[0.2] = "flight: the left heel kicks up behind, the right knee drives through",
				[0.3] = "right foot plants on the ball, the left arm forward",
				[0.35] = "right foot flat under the hips, the body at its lowest",
				[0.4] = "right toe pushes off",
				[0.5] = "flight: the right heel kicks up behind, the left knee drives through",
			},
			header = {
				"player/OneHandedSword/Run: the sheathed set, the sword on the back.",
				"16 studs/s, a 0.6 s cycle with the same plants as RunDrawn. The anime run: the body leans",
				"forward with the head in line with it, both arms pump hard with the elbows bent and a little",
				"out at the back of the swing, and the feet strike on the ball and push off the toe with a long",
				"flight between. The head stays in line because the hilt sits just behind it: tipped back to",
				"look up, it would meet the hilt. The elbows go out at the back so the left hand passes outside",
				"the scabbard, and the waist twists only 8 degrees so the scabbard clears the hips. Each foot",
				"stays planted where it lands while the body passes over it (the keys inside a stance are",
				"0.0125 s apart so the ground speed matches) and peels off the ground going back with it.",
				"Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
			},
			-- the hand re-key for the back mount (D-050, D-055), pinned in sources/Run.luau
			upper = function(t: number): Joints
				return sampledJoints(rig, SourceRun, t, notLeg)
			end,
			sheathed = true,
			mirrored = false,
		}
	end

	-----------------------------------------------------------------------------------------------
	-- Sprint: 0.5 s at sprintSpeed. Left plants at 0, right at 0.25. Deeper lean, longer stride.
	do
		local T = 0.5
		local left: Plan = {
			x = -0.32,
			ts = 0,
			tl = 0.08,
			z = -0.58,
			strikePivot = "toe",
			strikeAngle = -12,
			flatFrom = 0.02,
			flatTo = 0.04,
			liftPivot = "toe",
			liftAngle = -55,
			peel = { duration = 0.01, rise = 0.1, angle = -5 },
			swingJoints = {
				{ t = 0.165, hip = 22, knee = -125, ankle = 15 },
				{ t = 0.25, hip = 68, knee = -125, ankle = 0 },
				{ t = 0.27, hip = 80, knee = -115, ankle = -6 },
				{ t = 0.29, hip = 88, knee = -100, ankle = -12 },
				{ t = 0.31, hip = 90, knee = -80, ankle = -14 },
				{ t = 0.33, hip = 86, knee = -58, ankle = -14 },
				{ t = 0.415, hip = 62, knee = -22, ankle = -12 },
			},
		}
		G.Sprint = {
			duration = T,
			speed = locomotion.sprintSpeed,
			dir = Vector3.new(0, 0, -1),
			keyTimes = stanceKeys(T, 0.08, 0.01, 0.01, { 0.165 }),
			plans = { Left = left, Right = mirrorPlan(left, T) },
			events = { { time = 0.02, foot = "Left" }, { time = 0.27, foot = "Right" } },
			comments = {
				[0] = "left foot plants on the ball, the right arm thrown forward",
				[0.04] = "left foot flat under the hips, the body at its lowest",
				[0.08] = "left toe drives off, the leg long behind",
				[0.165] = "flight: the left heel high behind, the right knee up",
				[0.25] = "right foot plants on the ball, the left arm thrown forward",
				[0.29] = "right foot flat under the hips, the body at its lowest",
				[0.33] = "right toe drives off, the leg long behind",
				[0.415] = "flight: the right heel high behind, the left knee up",
			},
			header = {
				"player/OneHandedSword/Sprint: the sheathed set, the sword on the back.",
				"24 studs/s, a 0.5 s cycle with the same plants as SprintDrawn. A deeper lean than Run, a",
				"longer stride with a high heel kick, and a hard arm pump; the head drives forward in line with",
				"the body (tipped back it would meet the hilt). As in Run, the elbows go out at the back of the",
				"swing past the scabbard and the waist twist stays small enough for the scabbard to clear the",
				"hips. Each foot stays planted where it lands while the body passes over it (the keys inside a",
				"stance are 0.01 s apart so the ground speed matches) and peels off the ground going back with it.",
				"Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
			},
			-- the hand re-key for the back mount (D-050, D-055), pinned in sources/Sprint.luau
			upper = function(t: number): Joints
				return sampledJoints(rig, SourceSprint, t, notLeg)
			end,
			sheathed = true,
			mirrored = false,
		}
	end

	-----------------------------------------------------------------------------------------------
	-- WalkForward: 0.9 s, left plants at 0, right at 0.45. An easy walk cannot cover walkSpeed (8
	-- studs/s, a 3.6-stud step) in a 0.9 s cycle on these legs, so it keeps its feet planted at its
	-- own natural ground speed (3.5). Keys every 0.028125 s and the swing foot's path drawn as
	-- points (D-135): the toe clears the grass as it leaves, the foot passes high under the hips,
	-- and the heel reaches out ahead and stays off the field until the strike, so the foot meets
	-- the ground only at its plant. The torso, head and arms are the earlier WalkForward's (its arm
	-- swing is tuned to pass the scabbard), sampled at the key times.
	do
		local T = 0.9
		local left: Plan = {
			x = -0.42,
			ts = 0,
			tl = 0.50625,
			z = -0.9,
			strikePivot = "heel",
			strikeAngle = 14,
			flatFrom = 0.1125,
			flatTo = 0.3375,
			liftPivot = "toe",
			liftAngle = -40,
			liftPower = 2,
			swing = {
				{ t = 0.5625, x = -0.42, y = 0.38, z = 0.8, pitch = -32, roll = 0 },
				{ t = 0.73125, x = -0.42, y = 0.26, z = -0.05, pitch = 0, roll = 0 },
				{ t = 0.84375, x = -0.42, y = 0.2, z = -0.85, pitch = 16, roll = 0 },
			},
		}
		local function keepArms(joint: string): boolean
			return joint ~= "Root" and not LEGS[joint]
		end
		G.WalkForward = {
			duration = T,
			speed = 3.5,
			dir = Vector3.new(0, 0, -1),
			keyTimes = evenKeys(T, 32),
			plans = { Left = left, Right = mirrorPlan(left, T) },
			events = { { time = 0.03, foot = "Left" }, { time = 0.48, foot = "Right" } },
			comments = {
				[0] = "left heel strikes, the right arm forward",
				[0.225] = "passing: the body high over the left foot, the right leg swinging through",
				[0.45] = "right heel strikes, the left arm forward",
				[0.675] = "passing: the body high over the right foot, the left leg swinging through",
			},
			header = {
				"player/OneHandedSword/WalkForward: the sheathed set, the sword on the back.",
				"An easy walk, a 0.9 s cycle with the same plants as WalkForwardDrawn. Heel strike, roll to",
				"the toe, the arms swinging loose and empty against the legs, the body rising over each",
				"planted foot. The arms swing well forward and only a little back, so the left hand passes in",
				"front of the scabbard. The planted foot stays put at 3.5 studs/s of ground speed (an easy",
				"stride on these legs); faster walks are carried by the run blend. The toe leaves the grass",
				"as the other heel lands, and the heel reaches out ahead and stays up until it strikes (keys",
				"every 0.028125 s keep the swing foot on its path).",
				"Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
			},
			upper = function(t: number): Joints
				local body = walkUpper(t, T, {
					pelvis = -0.06,
					bob = 0.025,
					arm = 18,
					armX = 2,
					lean = -2,
					waist = 0,
					neck = 2,
					pelvisYaw = 4,
					shoulderYaw = 6,
					roll = 2,
					swayX = 0.04,
				})
				for joint, key in sampledRotations(rig, SourceWalkForward, t, keepArms) do
					body[joint] = key
				end
				return body
			end,
			sheathed = true,
			mirrored = false,
		}
	end

	-----------------------------------------------------------------------------------------------
	-- WalkBack: 0.9 s, keys every 0.028125 s: dense enough that the planted foot's path between
	-- keys stays on the line (a SineInOut key slows a limb at both ends).
	do
		local T = 0.9
		local keys = evenKeys(T, 32)
		local SPEED = 3.0
		local TL = 0.5625
		local zLift = 0.9 - SPEED * TL
		local left: Plan = {
			x = -0.42,
			ts = 0,
			tl = TL,
			z = 0.9,
			strikePivot = "toe",
			strikeAngle = -12,
			flatFrom = 0.1125,
			flatTo = 0.3375,
			liftPivot = "heel",
			liftAngle = 16,
			-- the heel leaves last, the foot rises before it swings back, then reaches behind toe first
			swing = {
				{ t = 0.61875, x = -0.42, y = 0.16, z = zLift + 0.05, pitch = 12, roll = 0 },
				{ t = 0.73125, x = -0.42, y = 0.24, z = (zLift + 0.9) / 2 + 0.1, pitch = 0, roll = 0 },
				{ t = 0.84375, x = -0.42, y = 0.17, z = 0.86, pitch = -12, roll = 0 },
			},
		}
		G.WalkBack = {
			duration = T,
			speed = SPEED,
			dir = Vector3.new(0, 0, 1),
			keyTimes = keys,
			plans = { Left = left, Right = mirrorPlan(left, T) },
			events = { { time = 0.03, foot = "Left" }, { time = 0.48, foot = "Right" } },
			comments = {
				[0] = "left toe touches down behind, the left arm forward",
				[0.225] = "the body over the left foot, the right leg swinging back",
				[0.45] = "right toe touches down behind, the right arm forward",
				[0.5625] = "the left heel peels off last",
				[0.61875] = "the left foot is up before it swings back",
				[0.675] = "the body over the right foot, the left leg swinging back",
			},
			header = {
				"player/OneHandedSword/WalkBack: the sheathed set, the sword on the back.",
				"An easy backpedal, a 0.9 s cycle with the same plants as WalkBackDrawn. Each foot reaches",
				"back and lands on the toe, rolls flat and peels off the heel, then rises clear before it",
				"swings back; the torso stays upright and the empty arms swing short. The planted foot",
				("moves back under the root at %s studs/s (keys every 0.028125 s keep it on the line)."):format(
					tostring(SPEED)
				),
				"Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
			},
			upper = function(t: number): Joints
				return walkUpper(t, T, {
					pelvis = -0.1,
					bob = 0.03,
					arm = -12,
					armX = 2,
					lean = 0,
					waist = -2,
					neck = 2,
					pelvisYaw = -3,
					shoulderYaw = -4,
					roll = 2,
					swayX = 0.04,
				})
			end,
			sheathed = true,
			mirrored = false,
		}

		-- The drawn twin: the same legs under the drawn upper body (the earlier WalkBackDrawn's
		-- root, torso, head, arms and sword, sampled at the key times), the pelvis as low as the
		-- sheathed backpedal's so the legs reach the plants.
		local DROP = -0.08
		G.WalkBackDrawn = {
			duration = T,
			speed = SPEED,
			dir = Vector3.new(0, 0, 1),
			keyTimes = keys,
			plans = { Left = left, Right = mirrorPlan(left, T) },
			events = { { time = 0.03, foot = "Left" }, { time = 0.48, foot = "Right" } },
			comments = {
				[0] = "left toe touches down behind",
				[0.225] = "the body over the left foot, the right leg swinging back",
				[0.45] = "right toe touches down behind",
				[0.5625] = "the left heel peels off last",
				[0.61875] = "the left foot is up before it swings back",
				[0.675] = "the body over the right foot, the left leg swinging back",
			},
			header = {
				"player/OneHandedSword/WalkBackDrawn: the drawn set, the sword in the hand.",
				"Backpedal, a 0.9 s cycle with the same plants as WalkBack. The legs reach behind, land on",
				"the toe, roll flat and peel off the heel, then rise clear before they swing back; the torso",
				"stays upright and the head stays on the target. Shorter arm swing than the forward walk; the",
				("sword rides low, the point forward. The planted foot moves back under the root at %s studs/s."):format(
					tostring(SPEED)
				),
				"Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
			},
			upper = function(t: number): Joints
				local out: Joints = {}
				for name, offset in rig.ClipSampler.sample(SourceWalkBackDrawn, t) do
					if not LEGS[name] then
						local pos = { offset.pos[1], offset.pos[2], offset.pos[3] }
						if name == "Root" then
							pos[2] += DROP
						end
						local moved = math.abs(pos[1]) + math.abs(pos[2]) + math.abs(pos[3]) > 1e-9
						out[name] = if moved
							then {
								pos = { pos[1], pos[2], pos[3] },
								rot = { offset.rot[1], offset.rot[2], offset.rot[3] },
							}
							else { rot = { offset.rot[1], offset.rot[2], offset.rot[3] } }
					end
				end
				return out
			end,
			sheathed = false,
			mirrored = false,
		}
	end

	-----------------------------------------------------------------------------------------------
	-- Side steps (lock-on strafe, D-128): a quick chasse. The lead foot reaches out and plants
	-- wide, the body travels over it, and the trail foot cuts in to land where the lead foot just
	-- left as the lead springs out again: a short float between plants, so the planted foot keeps
	-- pace with a walk-speed strafe at an easy cadence. Keys every 0.028125 s keep the planted foot
	-- on its line.
	do
		local T = 0.9
		local SPEED = 3.2
		local STANCE = 0.3375 -- lead stance (s); the trail's the same
		local WIDE = 1.16 -- the lead plants this far out
		local Z = 0
		local TRAIL_Z = 0 -- the trail foot this far behind (studs)
		local TRAIL_SWING_Z = 0 -- and this much further back in its swing
		local TRAIL_LIFT = 1 -- its swing height, a fraction of LIFT
		local LIFT = 0.22
		local PELVIS = -0.09
		local BOB = 0.03
		local ARM_LIFT = 9 -- WalkLeftDrawn's sword arm, further forward than WalkRightDrawn's (degrees)
		local keys = evenKeys(T, 32)

		-- The left-lead plans (WalkLeft: the body moves left, so planted feet travel right, +x).
		local D = STANCE
		local range = SPEED * D
		local leadLift = -WIDE + range -- where the lead foot leaves
		local trailLand = WIDE - range -- the trail lands here (it lifts at +WIDE)
		local h = LIFT
		local lead: Plan = {
			x = -WIDE,
			ts = 0,
			tl = D,
			z = Z,
			strikePivot = "left",
			strikeAngle = 6,
			flatFrom = 0.05625,
			flatTo = D - 0.084375,
			liftPivot = "toe",
			liftAngle = -14,
			-- out of the way fast (the trail cuts in behind it), then a low reach out to the wide plant
			swing = {
				{ t = D + 0.05625, x = leadLift - 0.32, y = h * 0.7, z = Z, pitch = 4, roll = 0 },
				{ t = 0.45, x = -WIDE + 0.42, y = h, z = Z, pitch = 0, roll = -4 },
				{ t = 0.675, x = -WIDE - 0.02, y = h * 0.95, z = Z, pitch = 0, roll = -6 },
				{ t = 0.84375, x = -WIDE - 0.03, y = h * 0.6, z = Z, pitch = 0, roll = -6 },
			},
		}
		local trail: Plan = {
			x = trailLand,
			ts = 0.45,
			tl = 0.45 + D,
			z = TRAIL_Z,
			strikePivot = "center",
			strikeAngle = 0,
			flatFrom = 0.45 + 0.05625,
			flatTo = 0.45 + D - 0.084375,
			liftPivot = "toe",
			liftAngle = -14,
			-- lifts off wide, stays out while the lead is down, then cuts in as the lead leaves
			swing = {
				{
					t = 0.45 + D + 0.05625,
					x = WIDE - 0.06,
					y = h * 0.8 * TRAIL_LIFT,
					z = TRAIL_Z + TRAIL_SWING_Z,
					pitch = 4,
					roll = 0,
				},
				{ t = 0.1125, x = WIDE - 0.16, y = h * TRAIL_LIFT, z = TRAIL_Z + TRAIL_SWING_Z, pitch = 0, roll = 2 },
				{
					t = D,
					x = math.max(trailLand + 0.6, leadLift + 0.98),
					y = h * TRAIL_LIFT,
					z = TRAIL_Z + TRAIL_SWING_Z,
					pitch = 0,
					roll = 2,
				},
				{
					t = 0.39375,
					x = trailLand + 0.12,
					y = h * 0.5 * TRAIL_LIFT,
					z = TRAIL_Z + TRAIL_SWING_Z,
					pitch = 0,
					roll = 0,
				},
			},
		}

		-- The shuffle's pelvis: low, rising a little through each float, rolling into the move.
		-- `side` is -1 for a move to the left, 1 to the right.
		local function sideRoot(t: number, side: number): Keys.JointKey
			-- lowest at mid-stance, highest in the float between plants
			local rise = cosAt(t, T / 2, D + (0.45 - D) / 2)
			local sway = sinAt(t, T, 0) -- over the lead foot first
			return pr(side * 0.04 * sway, PELVIS + BOB * rise, 0, -1, 0, -side * 2.5)
		end

		local function sideUpper(t: number, side: number): Joints
			local c = cosAt(t, T / 2)
			return {
				Root = sideRoot(t, side),
				Waist = r(0, 0, side * 2),
				Neck = r(1, 0, side * 0.5),
				LeftShoulder = r(4 + 2 * c, 0, -8),
				LeftElbow = r(18 + 4 * c, 0, 0),
				LeftWrist = r(-4, 0, 0),
				RightShoulder = r(4 + 2 * c, 0, 8),
				RightElbow = r(18 + 4 * c, 0, 0),
				RightWrist = r(-4, 0, 0),
			}
		end

		local function sideComments(leadFoot: string, trailFoot: string): { [number]: string }
			return {
				[0] = ("%s foot plants out wide, the body over it"):format(leadFoot),
				[0.309375] = ("%s foot pushes off its toe as the body passes over it"):format(leadFoot),
				[0.39375] = ("the float: %s foot cuts in where the %s foot was"):format(trailFoot, leadFoot:lower()),
				[0.45] = ("%s foot lands, the %s foot springs out"):format(trailFoot, leadFoot:lower()),
				[0.759375] = ("%s foot pushes off wide"):format(trailFoot),
			}
		end

		G.WalkLeft = {
			duration = T,
			speed = SPEED,
			dir = Vector3.new(-1, 0, 0),
			keyTimes = keys,
			plans = { Left = lead, Right = trail },
			events = { { time = 0.03, foot = "Left" }, { time = 0.48, foot = "Right" } },
			comments = sideComments("Left", "right"),
			header = {
				"player/OneHandedSword/WalkLeft: the sheathed set, the sword on the back.",
				"A quick side shuffle to the left (lock-on strafe), a 0.9 s cycle with the same plants as",
				"WalkLeftDrawn. The left foot reaches out and plants wide, the body travels over it, and",
				"the right foot cuts in to land where the left foot just left as the left foot springs out",
				"again: a short float between plants, the pelvis low, the torso square to the target and",
				("the empty arms loose. The planted foot moves under the root at %s studs/s (keys every"):format(
					tostring(SPEED)
				),
				"0.028125 s keep it on the line), so a walk-speed strafe keeps it planted.",
				"Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left (a hanging left leg",
				"with Z- swings out to the left).",
			},
			upper = function(t: number): Joints
				return sideUpper(t, -1)
			end,
			sheathed = true,
			mirrored = false,
		}
		-- The mirror of WalkLeft: solved as WalkLeft, then every joint mirrored left <-> right.
		G.WalkRight = {
			duration = T,
			speed = SPEED,
			dir = G.WalkLeft.dir,
			keyTimes = keys,
			plans = G.WalkLeft.plans,
			events = { { time = 0.03, foot = "Right" }, { time = 0.48, foot = "Left" } },
			comments = sideComments("Right", "left"),
			header = {
				"player/OneHandedSword/WalkRight: the sheathed set, the sword on the back.",
				"The mirror of WalkLeft: a quick side shuffle to the right, a 0.9 s cycle with the same",
				"plants as WalkRightDrawn. The right foot plants wide, the left foot cuts in where it was",
				("as it springs out again. The planted foot moves under the root at %s studs/s."):format(
					tostring(SPEED)
				),
				"Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
			},
			upper = G.WalkLeft.upper,
			sheathed = true,
			mirrored = true,
		}

		-- The drawn twins: the same legs under the drawn upper body (the earlier drawn side-step's
		-- torso, head, arms and sword, sampled at the key times) on the shuffle's pelvis. Not
		-- mirrors of each other: the sword stays in the right hand.
		local function keepUpper(joint: string): boolean
			return joint ~= "Root" and not LEGS[joint]
		end
		local function drawnUpper(source: Keys.SourceClip, side: number): (t: number) -> Joints
			return function(t: number): Joints
				local out = sampledRotations(rig, source, t, keepUpper)
				-- moving left, the right (trail) thigh rises out wide under the sword hand: the hand rides higher
				local shoulder = out.RightShoulder
				if side < 0 and shoulder then
					shoulder.rot[1] += ARM_LIFT
				end
				out.Root = sideRoot(t, side)
				return out
			end
		end
		G.WalkLeftDrawn = {
			duration = T,
			speed = SPEED,
			dir = Vector3.new(-1, 0, 0),
			keyTimes = keys,
			plans = { Left = lead, Right = trail },
			events = { { time = 0.03, foot = "Left" }, { time = 0.48, foot = "Right" } },
			comments = sideComments("Left", "right"),
			header = {
				"player/OneHandedSword/WalkLeftDrawn: the drawn set, the sword in the hand.",
				"A quick side shuffle to the left with the same plants as WalkLeft: the left foot plants",
				"wide, the right foot cuts in where it was as it springs out again, the pelvis low. The",
				"torso leans a little into the move, the head stays on the target, and the sword rides low",
				("with the point forward, the sword arm %s degrees further forward than WalkRightDrawn's so"):format(
					tostring(ARM_LIFT)
				),
				"the guard stays off the right thigh as it lifts out wide (a flinch throws the chest down",
				("over it). The planted foot moves under the root at %s studs/s."):format(tostring(SPEED)),
				"Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
			},
			upper = drawnUpper(SourceWalkLeftDrawn, -1),
			sheathed = false,
			mirrored = false,
		}
		G.WalkRightDrawn = {
			duration = T,
			speed = SPEED,
			dir = Vector3.new(1, 0, 0),
			keyTimes = keys,
			plans = { Left = flipPlan(trail), Right = flipPlan(lead) },
			events = { { time = 0.03, foot = "Right" }, { time = 0.48, foot = "Left" } },
			comments = sideComments("Right", "left"),
			header = {
				"player/OneHandedSword/WalkRightDrawn: the drawn set, the sword in the hand.",
				"A quick side shuffle to the right with the same plants as WalkRight: the right (sword)",
				"foot plants wide, the left foot cuts in where it was as it springs out again, the pelvis",
				"low. The torso leans a little into the move, the head stays on the target, and the sword",
				("rides low with the point forward. The planted foot moves under the root at %s studs/s."):format(
					tostring(SPEED)
				),
				"Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
			},
			upper = drawnUpper(SourceWalkRightDrawn, 1),
			sheathed = false,
			mirrored = false,
		}
	end

	-----------------------------------------------------------------------------------------------
	-- The forward drawn twins (D-134): the sheathed gait's legs (its plans, key times and pelvis
	-- height) under the earlier drawn clip's upper body (its pelvis turn, torso, head, arms and
	-- sword) sampled at the key times, so the drawn feet plant exactly as the sheathed ones do.
	do
		local function keepUpper(joint: string): boolean
			return not LEGS[joint]
		end
		local function twin(
			sheathed: Gait,
			source: Keys.SourceClip,
			header: { string },
			comments: { [number]: string },
			drop: number
		): Gait
			return {
				duration = sheathed.duration,
				speed = sheathed.speed,
				dir = sheathed.dir,
				keyTimes = sheathed.keyTimes,
				plans = sheathed.plans,
				events = sheathed.events,
				comments = comments,
				header = header,
				upper = function(t: number): Joints
					local out = sampledRotations(rig, source, t, keepUpper)
					local legs = sheathed.upper(t)
					local pos = legs.Root.pos or { 0, 0, 0 }
					local turn = if out.Root then out.Root.rot else { 0, 0, 0 }
					out.Root = { pos = { pos[1], pos[2] + drop, pos[3] }, rot = turn }
					return out
				end,
				sheathed = false,
				mirrored = false,
			}
		end
		-- The walk's pelvis sits 0.02 lower so the legs reach (D-134).
		G.WalkForwardDrawn = twin(G.WalkForward, SourceWalkForwardDrawn, {
			"player/OneHandedSword/WalkForwardDrawn: the drawn set, the sword in the hand.",
			"An easy walk, a 0.9 s cycle with the same legs as WalkForward: heel strike, roll to the toe,",
			"the body rising over each planted foot. The sword rides low with the point forward, the",
			"wrist easing it up as the arm swings back so the point stays clear of the grass, and the free",
			"arm counter-swings, short at the back so the hand stays in front of the scabbard. The planted",
			"foot stays put at 3.5 studs/s of ground speed; faster walks are carried by the run blend.",
			"Rotations: X+ swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
		}, {
			[0] = "left heel strikes",
			[0.225] = "passing: the body high over the left foot, the right leg swinging through",
			[0.45] = "right heel strikes",
			[0.675] = "passing: the body high over the right foot, the left leg swinging through",
		}, -0.02)
		G.RunDrawn = twin(G.Run, SourceRunDrawn, {
			"player/OneHandedSword/RunDrawn: the drawn set, the sword in the hand.",
			"16 studs/s, a 0.6 s cycle with the same legs as Run. The anime run: leaned forward, the free",
			"arm pumping (the sword arm pumps shorter, its wrist keeping the point forward and off the",
			"grass), the feet striking on the ball and pushing off the toe with a long flight between.",
			"Each foot stays planted where it lands while the body passes over it (the keys inside a",
			"stance are 0.0125 s apart so the ground speed matches) and peels off the ground going back with it.",
			"Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
		}, {
			[0] = "left foot plants on the ball",
			[0.05] = "left foot flat under the hips, the body at its lowest",
			[0.1] = "left toe pushes off",
			[0.2] = "flight: the left heel kicks up behind, the right knee drives through",
			[0.3] = "right foot plants on the ball",
			[0.35] = "right foot flat under the hips, the body at its lowest",
			[0.4] = "right toe pushes off",
			[0.5] = "flight: the right heel kicks up behind, the left knee drives through",
		}, 0)
		G.SprintDrawn = twin(G.Sprint, SourceSprintDrawn, {
			"player/OneHandedSword/SprintDrawn: the drawn set, the sword in the hand.",
			"24 studs/s, a 0.5 s cycle with the same legs as Sprint: a longer stride with a high heel",
			"kick, the free arm thrown hard, the sword arm pumping short with the point forward and off",
			"the grass. Each foot stays planted where it lands while the body passes over it (the keys",
			"inside a stance are 0.01 s apart so the ground speed matches) and peels off the ground going",
			"back with it.",
			"Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.",
		}, {
			[0] = "left foot plants on the ball",
			[0.04] = "left foot flat under the hips, the body at its lowest",
			[0.08] = "left toe drives off, the leg long behind",
			[0.165] = "flight: the left heel high behind, the right knee up",
			[0.25] = "right foot plants on the ball",
			[0.29] = "right foot flat under the hips, the body at its lowest",
			[0.33] = "right toe drives off, the leg long behind",
			[0.415] = "flight: the right heel high behind, the left knee up",
		}, 0)
	end

	return G
end

return Gaits
