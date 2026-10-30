--!strict
--[[
	player/OneHandedSword/RisingArc: the launcher (section 8: 2 hits, startup 0.3, total 0.9,
	post-motion 0.5, 1 stud of root motion; launches small enemies). A rising diagonal cut from
	low left to high right that carries the blade over the head, then a flick from the top that
	whips it back over and down onto the target. The body sinks into the start pose and drives
	up through the legs on the snap, so the whole rig rises with the blade and stays up on the
	toes through the flick; from behind it reads as a crouch that uncoils upward. At the top the
	legs stand straight with both heels high and the torso upright (no lean back to take the rise
	away), and the head stands 0.26 studs over the drawn idle's from the snap's landing and at
	least 0.22 through its settle (tests/choreo/RisingArcRise.spec.luau, D-415; it rose 0.05).

	Timeline (the beats table describes the first strike; the flick repeats the pattern with a
	short re-cock, a 3-frame snap, a hold and a spring settle):
	  0.00-0.15  start pose (QuadOut, carried in by a blend in as long as it): the body sinks into
	             the low crouch, the sword drawn low across to the left hip with the point
	             trailing back at the height of the knee, torso wound left, the free hand opens,
	             the front foot unweights
	  0.15-0.25  activation hold: the blade lights, the crouch breathes
	  0.25-0.33  Anticipation (5 frames): the crouch deepens, the point drags down to the grass and
	             further back, against the rising cut; the front foot lifts
	  0.33-0.38  Snap 1 (3 frames, ExpoOut): the rising cut, the front foot steps in onto its toe,
	             the legs drive the hips up onto the toes, the torso whips right  (hit 1: 0.33-0.45)
	  0.34-0.38  Smear (2 frames, X: the diagonal): the snap's first two moving frames
	  0.38-0.42  Hold (hit-stop pauses the clock here on a hit)
	  0.42-0.50  Settle (Spring, 5 frames): the pose comes back 5-8 degrees from the extreme
	  0.50-0.56  re-cock (SineInOut, at an even pace): the blade carries over the head, the elbow
	             and wrist cock back together
	  0.56-0.61  Snap 2: the flick from the top, over and down onto the target, the hips unwind,
	             the torso leans in, the point ends level at the target's centre  (hit 2: 0.56-0.68)
	  0.61-0.64  Hold, then Settle to 0.75 (the arm springs back up); the rear foot pushes off
	  0.75-0.90  the heels come down, the knees take the weight, the point stays on the target;
	             the rear foot is drawn up under the body, down again by 0.9
	  0.90-1.40  Recovery / post-motion: the upper body flows back to the guard (the blade off the
	             face), the front foot steps forward into the guard stance (1.05-1.2)
	Each hit window opens on its snap's first frame (its trail ignites with it), so the server
	sweeps the whole cut, and closes in the settle; each trail goes out in its settle, so the
	re-cock between the cuts draws none.
	Hit-stop: Normal on hit 1, Final on hit 2 (the server tiers an Art's last window, as it does
	for Sharp Nail). Root motion: 1 stud forward over the two snaps (-Z is forward).
	Re-key (D-377): the sword forearm stays off the chest through the start pose and the cut (it
	sat 0.59 inside it); the root does not travel in a spring settle (each settle's step goes to
	the key after it), so a planted foot never slides under it; the post-motion no longer holds
	the blade across the face. A 0.15 s blend in and out.
	Rotations: X+ leans the torso back / swings a hanging limb forward, Y+ turns left, Z+ rolls left.
]]

local Types = require(script.Parent.Parent.Parent.Parent.types)

local function rot(x: number, y: number, z: number): Types.JointKey
	return { rot = { x, y, z } }
end

local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey
	return { pos = { px, py, pz }, rot = { rx, ry, rz } }
end

local clip: Types.ClipDef = {
	id = "player/OneHandedSword/RisingArc",
	rig = "PlayerR15",
	duration = 1.4,
	loop = false,
	layer = "FullBody",
	priority = 20,
	attack = true,
	hitStop = "Normal",
	blendIn = 0.15,
	blendOut = 0.15,
	keys = {
		{
			-- ready stance
			time = 0,
			easing = "QuadOut",
			joints = {
				Root = posRot(0, -0.12, 0, 0, 0, 0),
				Waist = rot(-8, -12, 0),
				Neck = rot(6, 12, 0),
				RightShoulder = rot(30, 0, 10),
				RightElbow = rot(35, 0, 0),
				RightWrist = rot(-25, 0, 0),
				Weapon = rot(-50, 0, 0),
				LeftShoulder = rot(25, 0, -15),
				LeftElbow = rot(50, 0, 0),
				LeftWrist = rot(0, 0, 10),
				LeftHip = rot(24.5, -1, -5.9),
				LeftKnee = rot(-37.5, 0, 0),
				LeftAnkle = rot(12.9, 0.4, 5.8),
				RightHip = rot(-4.4, 0.8, 6.6),
				RightKnee = rot(-32.4, 0, 0),
				RightAnkle = rot(24.8, 1.1, -6.5),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- start pose: the body sinks, the sword low and back at the left hip, the point trailing
			time = 0.15,
			easing = "QuadOut",
			joints = {
				Root = posRot(-0.06, -0.34, 0.04, 0, 8, 2),
				Waist = rot(-24.8, 51.2, 18),
				Neck = rot(15, -34.8, -8.4),
				RightShoulder = rot(34.5, 8.7, -3.5),
				RightElbow = rot(29.1, 0, 0),
				RightWrist = rot(-11.3, -20.9, -27.9),
				Weapon = rot(-82, 0, 38),
				LeftShoulder = rot(36, 0, -24),
				LeftElbow = rot(30, 0, 0),
				LeftWrist = rot(0, 0, 22),
				LeftHip = rot(45.5, -2, -5.3),
				LeftKnee = rot(-68.2, 0, 0),
				LeftAnkle = rot(26.1, -8.2, 3.6),
				RightHip = rot(8.1, 0.9, 4.8),
				RightKnee = rot(-63, 0, 0),
				RightAnkle = rot(38.1, -5, -8.6),
			},
		},
		{
			-- activation hold: the crouch breathes, the point drifts lower
			time = 0.25,
			easing = "SineInOut",
			joints = {
				Root = posRot(-0.06, -0.36, 0.04, 0, 9, 2),
				Waist = rot(-24.8, 51.2, 18),
				RightShoulder = rot(31.8, 5, -3.6),
				Weapon = rot(-82, 0, 38),
				LeftWrist = rot(0, 0, 22),
				LeftAnkle = rot(26.6, -9.2, 3.5),
				LeftHip = rot(47, -2, -5.1),
				LeftKnee = rot(-70.2, 0, 0),
				RightAnkle = rot(39.4, -5.9, -8.6),
				RightElbow = rot(35.4, 0, 0),
				RightHip = rot(8.4, 0.7, 4.5),
				RightKnee = rot(-64.7, 0, 0),
				RightWrist = rot(-15.3, -17.9, -28.2),
			},
		},
		{
			-- anticipation: the crouch deepens, the point drags lower and further back
			time = 0.3333,
			easing = "QuadIn",
			joints = {
				Root = posRot(-0.08, -0.42, 0.06, 0, 12, 3),
				Waist = rot(-26, 60, 20),
				Neck = rot(16, -46, -9),
				RightShoulder = rot(33.3, 7.1, -4.7),
				RightElbow = rot(22.8, 0, 0),
				RightWrist = rot(-14.6, -21.3, -12.7),
				Weapon = rot(-90, 0, 38),
				LeftShoulder = rot(61.4, 16, -29.5),
				LeftElbow = rot(24, 0, 0),
				LeftKnee = rot(-88.3, 0, 0),
				LeftAnkle = rot(7.1, -7.7, -3.9),
				RightKnee = rot(-74.5, 0, 0),
				RightAnkle = rot(38, -7.2, -10.5),
				LeftHip = rot(70.8, -0.4, -0.4),
				LeftWrist = rot(-6.1, -22.8, 29.5),
				RightHip = rot(13.1, 0.6, 3.9),
			},
			root = { pos = { 0, 0, 0 } },
		},
		{
			-- snap 1: the rising cut, past the final pose; the legs drive the hips up onto the toes:
			-- the knees straight, both heels high, the torso upright
			time = 0.3833,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.08, 0.18, -0.06, 0, -12, -4),
				Waist = rot(0, -34, -10),
				Neck = rot(2, 30, 3),
				RightShoulder = rot(134, 0, 40),
				RightElbow = rot(12, 0, 0),
				RightWrist = rot(10, 0, -18),
				Weapon = rot(-46, 0, 20),
				LeftShoulder = rot(-32, 0, -36),
				LeftElbow = rot(38, 0, 0),
				LeftWrist = rot(0, 0, 0),
				LeftHip = rot(3.8, -0.4, -4.4),
				LeftKnee = rot(-6, 0, 0),
				LeftAnkle = rot(-20, 13, 14.1),
				RightHip = rot(-16, 3, 12.6),
				RightKnee = rot(-12, 0, 0),
				RightAnkle = rot(-20, 11.7, 2.4),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			-- hold on contact
			time = 0.4167,
			easing = "Hold",
			joints = {
				Root = posRot(0.08, 0.18, -0.06, 0, -12, -4),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			-- out of the hold (QuadIn): the settle starts slow, so the first frame after a freeze barely moves
			time = 0.4583,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(-20, 12.45, 13.15),
				LeftHip = rot(0.1, -0.6, -4.5),
				LeftKnee = rot(0, 0, 0),
				LeftShoulder = rot(-29, 0, -35),
				Neck = rot(1.5, 28, 2.5),
				RightAnkle = rot(-38, 11.3, 1.35),
				RightElbow = rot(16, 0, 0),
				RightHip = rot(-17.3, 2.65, 12.2),
				RightKnee = rot(-8, 0, 0),
				RightShoulder = rot(131, 0, 37),
				Root = posRot(0.07, 0.17, -0.07, 0, -11, -3.5),
				Waist = rot(2, -31, -9),
				Weapon = rot(-48, 0, 17.5),
			},
		},
		{
			-- settle 1 (6 frames): back 5-8 degrees from the extreme, still up on the toes
			time = 0.5,
			easing = "Spring",
			joints = {
				Root = posRot(0.06, 0.18, -0.08, 0, -10, -3),
				Waist = rot(4, -28, -8),
				Neck = rot(1, 26, 2),
				RightShoulder = rot(128, 0, 34),
				RightElbow = rot(20, 0, 0),
				Weapon = rot(-50, 0, 15),
				LeftShoulder = rot(-26, 0, -34),
				LeftAnkle = rot(-20, 11.9, 12.2),
				LeftHip = rot(0.3, -0.8, -4.6),
				LeftKnee = rot(0, 0, 0),
				RightAnkle = rot(-44, 10.9, 0.3),
				RightHip = rot(-18.7, 2.3, 11.8),
				RightKnee = rot(-4, 0, 0),
			},
			root = { pos = { 0, 0, -0.5 } },
		},
		{
			-- re-cock: the blade carries over the head, the elbow and wrist cock back. The waist twists less
			-- than the upper body turns, keeping the hips off the scabbard; Root and the hips take up the rest,
			-- so the torso, arm and blade stand where they did
			time = 0.56,
			easing = "SineInOut",
			joints = {
				Root = posRot(0.06, -0.02, -0.12, 3, -11.6, 0.7),
				Waist = rot(10, -17, -9),
				Neck = rot(-6, 18, 1),
				RightShoulder = rot(148, 0, 24),
				RightElbow = rot(36, 0, 0),
				RightWrist = rot(-26, 0, -6),
				Weapon = rot(-34, 0, 4),
				LeftShoulder = rot(-18, 0, -30),
				LeftHip = rot(16.8, 1.8, -8.4),
				RightHip = rot(-20.9, 4.3, 9.7),
				LeftAnkle = rot(4.3, 10.1, 11.1),
				LeftKnee = rot(-44, 0, 0),
				RightAnkle = rot(-14.7, 9.7, -0.1),
				RightKnee = rot(-21.8, 0, 0),
			},
			root = { pos = { 0, 0, -0.6 } },
		},
		{
			-- snap 2: the flick whips over the top and down onto the target, past the final pose; the hips
			-- unwind and the torso leans into it, the point ends level on the target's centre
			time = 0.61,
			easing = "ExpoOut",
			joints = {
				Root = posRot(0.02, -0.08, -0.14, 0, -8, -4),
				Waist = rot(-10, -8, -6),
				Neck = rot(8, 16, 2),
				RightShoulder = rot(100, 0, 0),
				RightElbow = rot(7, 0, 0),
				RightWrist = rot(-24, 0, -34),
				Weapon = rot(-84, 0, 18),
				LeftShoulder = rot(-28, 0, -38),
				LeftElbow = rot(34, 0, 0),
				LeftHip = rot(6.4, 2, -0.9),
				RightHip = rot(-6.5, 4.6, 13.8),
				LeftKnee = rot(-37.6, 0, 0),
				LeftAnkle = rot(15.8, 10.3, 7.5),
				RightKnee = rot(-54.7, 0, 0),
				RightAnkle = rot(1.4, 9.4, -2.1),
			},
			root = { pos = { 0, 0, -0.9 } },
		},
		{
			-- hold 2
			time = 0.64,
			easing = "Hold",
			joints = {
				Root = posRot(0.02, -0.08, -0.14, 0, -8, -4),
			},
			root = { pos = { 0, 0, -0.9 } },
		},
		{
			-- out of the hold (QuadIn): the settle starts slow, so the first frame after a freeze barely moves
			time = 0.695,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(18.35, 10.05, 7.35),
				LeftHip = rot(7.8, 1.75, -1.5),
				LeftKnee = rot(-40.45, 0, 0),
				LeftShoulder = rot(-25, 0, -37),
				Neck = rot(7, 15.5, 2),
				RightAnkle = rot(4.7, 9.1, -2.7),
				RightElbow = rot(8, 0, 0),
				RightHip = rot(-7.85, 4.1, 13.3),
				RightKnee = rot(-54.05, 0, 0),
				RightShoulder = rot(103, 0, 2),
				RightWrist = rot(-21, 0, -31),
				Root = posRot(0.02, -0.1, -0.14, 0, -7.5, -3.5),
				Waist = rot(-9, -8, -5.5),
				Weapon = rot(-82, 0, 16),
			},
		},
		{
			-- settle 2: the flick springs back up 5-8 degrees
			time = 0.75,
			easing = "Spring",
			joints = {
				Root = posRot(0.02, -0.12, -0.14, 0, -7, -3),
				Waist = rot(-8, -8, -5),
				Neck = rot(6, 15, 2),
				RightShoulder = rot(106, 0, 4),
				RightElbow = rot(10, 0, 0),
				RightWrist = rot(-18, 0, -28),
				Weapon = rot(-80, 0, 14),
				LeftShoulder = rot(-22, 0, -36),
				LeftAnkle = rot(20.9, 9.8, 7.2),
				LeftHip = rot(9.2, 1.5, -2.1),
				LeftKnee = rot(-43.3, 0, 0),
				RightAnkle = rot(8, 8.8, -3.3),
				RightHip = rot(-9.2, 3.6, 12.8),
				RightKnee = rot(-53.4, 0, 0),
			},
			root = { pos = { 0, 0, -0.9 } },
		},
		{
			time = 0.84,
			easing = "QuadOut",
			joints = {
				LeftAnkle = rot(34.1, 8.7, 5.2),
				LeftHip = rot(8.2, 2.7, -2.8),
				LeftKnee = rot(-47.1, 0, 0),
				LeftShoulder = rot(-20.3, 0, -34.3),
				Neck = rot(6, 14.2, 1.2),
				RightAnkle = rot(35.1, 6.3, -7.6),
				RightElbow = rot(13.4, 0, 0),
				RightHip = rot(7.1, 5.2, 10.9),
				RightKnee = rot(-61.7, 0, 0),
				RightShoulder = rot(104.3, 0, 5.7),
				Root = posRot(0.003, -0.221, -0.106, 0, -6.2, -2.2),
				Waist = rot(-4.6, -8, -4.2),
				Weapon = rot(-78.3, 0, 12.3),
			},
			root = { pos = { 0, 0, -0.984 } },
		},
		{
			-- end pose: the heels come down, the knees take the weight, the point stays on the target
			time = 0.9,
			easing = "SineInOut",
			joints = {
				Root = posRot(0, -0.24, -0.1, 0, -6, -2),
				Waist = rot(-4, -8, -4),
				Neck = rot(6, 14, 1),
				RightShoulder = rot(104, 0, 6),
				RightElbow = rot(14, 0, 0),
				Weapon = rot(-78, 0, 12),
				LeftShoulder = rot(-20, 0, -34),
				LeftHip = rot(5.4, 3, -2.7),
				LeftKnee = rot(-43.3, 0, 0),
				LeftAnkle = rot(37.1, 8.7, 4.4),
				RightHip = rot(2.2, 3.8, 10.8),
				RightKnee = rot(-50.3, 0, 0),
				RightAnkle = rot(36.5, 5.4, -8),
			},
			root = { pos = { 0, 0, -1 } },
		},
		{
			-- post-motion micro keys: caught with the blade out, the point trembling
			time = 1.05,
			easing = "SineInOut",
			joints = {
				Waist = rot(-4.5, -9.2, -2.8),
				Neck = rot(6.7, 13.4, 0.7),
				Weapon = rot(-68.9, 0, 9.1),
				RightWrist = rot(-19.4, 0, -18.9),
				LeftAnkle = rot(34, 7.3, 4.8),
				LeftElbow = rot(38.8, 0, 0),
				LeftHip = rot(5.7, 2.5, -3.6),
				LeftKnee = rot(-40.4, 0, 0),
				LeftShoulder = rot(-6.5, 0, -28.3),
				LeftWrist = rot(0, 0, 3),
				RightAnkle = rot(33.3, 4.1, -7.5),
				RightElbow = rot(20.3, 0, 0),
				RightHip = rot(0.7, 2.9, 9.5),
				RightKnee = rot(-45.7, 0, 0),
				RightShoulder = rot(81.8, 0, 7.2),
				Root = posRot(0, -0.204, -0.07, 0, -4.2, -1.4),
			},
		},
		{
			time = 1.125,
			easing = "QuadIn",
			joints = {
				LeftAnkle = rot(34.3, 3.6, 7.7),
				LeftElbow = rot(41.6, 0, 0),
				LeftHip = rot(39.1, -2, -6),
				LeftKnee = rot(-84.2, 0, 0),
				LeftShoulder = rot(1.4, 0, -25),
				LeftWrist = rot(0, 0, 4.8),
				Neck = rot(6.2, 12.9, 0.5),
				RightAnkle = rot(31.4, 3.3, -7.2),
				RightElbow = rot(24, 0, 0),
				RightHip = rot(-0.3, 2.3, 8.8),
				RightKnee = rot(-42.8, 0, 0),
				RightShoulder = rot(68.9, 0, 7.9),
				RightWrist = rot(-21.1, 0, -14.5),
				Root = posRot(0, -0.183, -0.053, 0, -3.2, -1),
				Waist = rot(-5.5, -9.9, -2.1),
				Weapon = rot(-64.5, 0, 6.5),
			},
			root = { pos = { 0, 0, -1 } },
		},
		{
			time = 1.2,
			easing = "QuadIn",
			joints = {
				Waist = rot(-6.6, -10.6, -1.4),
				Neck = rot(5.7, 12.4, 0.4),
				Weapon = rot(-60.1, 0, 3.9),
				RightWrist = rot(-22.9, 0, -10.1),
				LeftAnkle = rot(17.7, 1.8, 6),
				LeftElbow = rot(44.4, 0, 0),
				LeftHip = rot(26.4, -0.4, -5.8),
				LeftKnee = rot(-44.4, 0, 0),
				LeftShoulder = rot(9.3, 0, -21.6),
				LeftWrist = rot(0, 0, 6.5),
				RightAnkle = rot(29.3, 2.6, -6.9),
				RightElbow = rot(27.7, 0, 0),
				RightHip = rot(-1.5, 1.8, 8),
				RightKnee = rot(-39.7, 0, 0),
				RightShoulder = rot(55.9, 0, 8.6),
				Root = posRot(0, -0.162, -0.035, 0, -2.1, -0.7),
			},
		},
		{
			time = 1.4,
			easing = "SineInOut",
			joints = {
				LeftShoulder = rot(19.8, 0, -17.3),
				RightShoulder = rot(38.8, 0, 9.5),
				RightWrist = rot(-24.2, 0, -3.4),
				LeftAnkle = rot(18.6, 0.5, 6),
				LeftElbow = rot(48.1, 0, 0),
				LeftHip = rot(30, -0.9, -6.1),
				LeftKnee = rot(-48.8, 0, 0),
				LeftWrist = rot(0, 0, 8.8),
				Neck = rot(5.9, 12.1, 0.1),
				RightAnkle = rot(31.8, 1.5, -6.8),
				RightElbow = rot(32.5, 0, 0),
				RightHip = rot(1.2, 1.9, 7.2),
				RightKnee = rot(-44.9, 0, 0),
				Root = posRot(0, -0.134, -0.012, 0, -0.7, -0.2),
				Waist = rot(-7.5, -11.5, -0.5),
				Weapon = rot(-53.5, 0, 1.3),
			},
		},
	},
	events = {
		{ time = 0.15, kind = "ActivationHold", data = { hold = 0.1 } },
		{ time = 0.27, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.3333, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.3333, kind = "HitWindowOpen", data = { hit = 1 } },
		{ time = 0.3416, kind = "SmearOn", data = { axis = "X" } },
		{ time = 0.375, kind = "SmearOff" },
		{ time = 0.45, kind = "HitWindowClose", data = { hit = 1 } },
		{ time = 0.49, kind = "TrailOff" },
		{ time = 0.5, kind = "Sfx", data = { name = "whoosh.Medium" } },
		{ time = 0.56, kind = "TrailOn", data = { kind = "Art" } },
		{ time = 0.56, kind = "HitWindowOpen", data = { hit = 2 } },
		{ time = 0.5683, kind = "SmearOn", data = { axis = "Y" } },
		{ time = 0.6017, kind = "SmearOff" },
		{ time = 0.68, kind = "HitWindowClose", data = { hit = 2 } },
		{ time = 0.72, kind = "TrailOff" },
		{ time = 0.9, kind = "PostMotionStart" },
	},
	beats = {
		Anticipation = { start = 0.25, finish = 0.3333 },
		Snap = { start = 0.3333, finish = 0.3833 },
		Smear = { start = 0.3416, finish = 0.375 },
		Hold = { start = 0.3833, finish = 0.4167 },
		Settle = { start = 0.4167, finish = 0.5167 },
		Recovery = { start = 0.9, finish = 1.4 },
	},
}

return clip
