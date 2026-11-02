--!strict
--[[
	Another player's swing on a watcher's screen through a hit-stop (AN 468(a), D-556, D-557).

	A watcher (B) draws A's Vertical on A's copy here: the clip ActionStarted started (caught up by
	the network's lateness), the root where replication puts it, the hit-stop A's HitConfirmed
	asks for. The PC (006f057) saw two things at lag 0:

	- The freeze landed early. The word froze A's copy on arrival, at clip 0.383 to 0.391, while A's
	  own screen froze on the contact at 0.401 to 0.404: B held the snap in the air short of its end
	  pose, and the clip's own hold after the snap was skipped on the release (the hit-stop stands
	  in for it, section 10 beat 4). Now the word waits until the copy shows the strike's key, as
	  the local fighter's word does (D-267), so the hold freezes the key pose (D-557).
	- The frozen frames still laid ribbon. The copy's pose holds, but its replicated root still
	  moves (A's stand-off reaches B later than A's clip does), so the blade drifted 0.02 to 0.07 a
	  row and laid a segment on 2 to 4 of the 13 to 14 frozen rows at 144. A frame drawn held lays
	  nothing now; the stroke goes on from that frame's blade once the clip moves (D-556).

	The real path: a RigBuilder player rig with its drawn WeaponBuilder sword, a real Choreo
	animator, the real ClipLibrary clip, ActionStarted and HitConfirmed through the real
	Replication (its Heartbeat step that lets held words go, atPose and atStepPose on the real
	FrameClock), and the real Trails and TrailRibbon on their render steps. Lune derives no
	WorldPosition, so TrailEnd goes where the rig's joints pose it before the readers run.
]]

local function frameSignal(): any
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
Harness.stubService("RunService", {
	RenderStepped = frameSignal(),
	Heartbeat = frameSignal(),
	PreSimulation = frameSignal(),
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})

local Choreo = Harness.load("src/client/choreo/Choreo")
local Locomotion = Harness.load("src/client/choreo/Locomotion")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local FrameClock = Harness.load("src/client/fx/FrameClock")
local Replication = Harness.load("src/client/controllers/Replication")
local Trails = Harness.load("src/client/fx/Trails")
local TrailRibbon = Harness.load("src/client/fx/TrailRibbon")
local Engine = Harness.load("src/client/fx/Engine")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Combat = Harness.load("src/shared/data/combat")
local Rigs = Harness.load("src/shared/data/rigs")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Weapons = Harness.load("src/shared/data/weapons")

local VERTICAL = ChoreoData.locomotion.clipPrefix .. "Vertical"
local VERTICAL_ART = "OneHandedSword.Vertical"
-- Vertical's strike key: its snap (0.35 to 0.40) lands, and its own hold runs to 0.43.
local KEY, HOLD_END = 0.4, 0.43
local EPSILON = Combat.contact.keyEpsilon
local RATES = { 30, 60, 144 }
-- The PC's lag-0 catch-up: B's first Basic1 row read clip 0.058 to 0.065.
local LAG_ZERO = 0.06
local A_ID, B_ID, BOAR_ID = 2, 1, 10

local clock = 100
local frame = 0
Choreo.configure({
	now = function(): number
		return clock
	end,
	cameraPosition = function(): Vector3
		return Vector3.zero
	end,
})

local function recorder(): any
	return setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
end

-- A's copy: a player rig with its sword drawn.
local function build(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Ren"
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", true)
	model:SetAttribute("State", "Idle")
	local parts: { [string]: BasePart } = {}
	local function part(name: string): BasePart
		if parts[name] == nil then
			local created = Instance.new("Part")
			created.Name = name
			created.Size = Vector3.new(1, 1, 1)
			created.CFrame = CFrame.new(0, 3, 0)
			created.Position = Vector3.new(0, 3, 0)
			created.AssemblyLinearVelocity = Vector3.zero
			created.Parent = model
			parts[name] = created
		end
		return parts[name]
	end
	for _, joint in Rigs.PlayerR15.joints do
		if joint.name ~= WeaponModels.motorName then
			local motor = Instance.new("Motor6D")
			motor.Name = joint.name
			motor.Part0 = part(joint.part0)
			motor.Part1 = part(joint.part1)
			motor.C0 = RigBuilder.frameOf(joint.c0)
			motor.Parent = motor.Part1
		end
	end
	model.PrimaryPart = parts.HumanoidRootPart
	local humanoid = Instance.new("Humanoid")
	humanoid.MoveDirection = Vector3.zero
	humanoid.FloorMaterial = Enum.Material.Plastic
	humanoid.Parent = model
	WeaponBuilder.equip(model, Weapons.byId("TrialistSword"))
	local world = Instance.new("Folder")
	model.Parent = world
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			local ok = pcall(function(): Vector3
				return item.Position
			end)
			if not ok then
				item.Position = Vector3.new(0, 3, 0)
			end
		end
	end
	return model, parts.HumanoidRootPart
end

-- The word the take sends when the copy's clip reaches `at` (after that frame's Heartbeat).
type Word = { at: number, attackerId: number, targetId: number, artId: string? }

type Take = {
	shown: { [number]: number }, -- per frame, the clip time it draws (its rig's step of the frame before)
	held: { [number]: boolean }, -- per frame, the rig is drawn held (Choreo heldShown)
	pushes: { [number]: number }, -- per frame, the samples the ribbon kept
	longest: number, -- the longest segment the stroke laid
	cues: { number }, -- the frames the hit's cues played on (Impact.hit)
	sentOn: number?, -- the frame whose Heartbeat sent the word
	sentAt: number?, -- the copy's clip time then
	firstHeld: number?, -- the first frame drawn held
	endFrame: number?, -- the first frame that draws the clip at its key or past it (the end pose)
	lastPush: number?, -- the last frame the ribbon kept a sample on
}

-- Plays A's Vertical on its copy at `fps`, its ActionStarted `late` seconds after the server's
-- start, its root moving `drift` studs a second (replication carrying it), and sends `word`.
local function take(fps: number, late: number, drift: Vector3, word: Word?): Take
	local model, root = build()
	local record =
		{ id = A_ID, model = model, kind = "Player", rig = "PlayerR15", weaponId = "TrialistSword", name = "Ren" }
	local hooks: { [string]: any } = {}
	local beats: { (dt: number) -> () } = {}
	local function hook(key: string)
		return function(fn: any): () -> ()
			hooks[key] = fn
			return function()
				hooks[key] = nil
			end
		end
	end
	FrameClock.bind({
		now = function(): number
			return clock
		end,
		onFrameStart = hook("start"),
		onPosed = hook("posed"),
		onFrameEnd = hook("finish"),
		onHeartbeat = function(): () -> ()
			return function() end
		end,
	} :: any)
	Engine.setViewer(function(): Vector3
		return Vector3.new(0, 5, 10)
	end)
	Engine.setClock(function(): number
		return clock
	end)
	Trails.start()
	Trails.bind({
		now = function(): number
			return clock
		end,
		onRender = hook("readers"),
		onDrawn = hook("drawn"),
		onWatch = function(): () -> ()
			return function() end
		end,
		clear = function() end,
		-- The rig's hold as the frame draws it, as the game binds it (Choreo heldShown).
		held = function(target: Instance): boolean
			local found: any = Choreo.find(target :: any)
			return found ~= nil and found:heldShown() == true
		end,
		animator = function(target: Instance): any
			return Choreo.find(target :: any)
		end,
	})
	local result: Take = { shown = {}, held = {}, pushes = {}, longest = 0, cues = {} }
	-- A cue played in the Heartbeat after a frame's render steps shows on the next frame.
	local afterRender = false
	local impact = recorder()
	impact.hit = function()
		table.insert(result.cues, if afterRender then frame + 1 else frame)
		return nil
	end
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return if id == A_ID then record else nil
			end,
		},
		localId = function(): number
			return B_ID
		end,
		locomotion = {
			-- Foot IK off: Lune casts no rays, and the swing's blade is the spec's subject.
			attach = function(animator: any, rigName: any, options: any): any
				local withoutIK = table.clone(options or {})
				withoutIK.footIK = false
				return Locomotion.attach(animator, rigName, withoutIK)
			end,
			destroy = Locomotion.destroy,
			humanoidTracker = Locomotion.humanoidTracker,
		},
		choreo = Choreo,
		clipLibrary = ClipLibrary,
		trails = Trails,
		smear = recorder(),
		shatter = recorder(),
		sparks = recorder(),
		telegraphs = recorder(),
		outline = recorder(),
		switchRing = recorder(),
		digits = recorder(),
		hud = recorder(),
		systemLine = recorder(),
		sfx = recorder(),
		impact = impact,
		camera = recorder(),
		weaponCategory = function(): string
			return "OneHandedSword"
		end,
		trailToken = function(): string
			return "TrailCyanWhite"
		end,
		positionOf = function(): Vector3
			return Vector3.zero
		end,
		schedule = function() end,
		now = function(): number
			return clock
		end,
		-- The Heartbeat after each frame's render steps: it lets the held words go (D-267).
		onHeartbeat = function(fn: (dt: number) -> ())
			table.insert(beats, fn)
		end,
		atPose = FrameClock.atPose,
		atStepPose = FrameClock.atStepPose,
	} :: any)
	Replication.watch(record)
	local animator: any = Choreo.get(model)
	local tipAttachment = model:FindFirstChild("TrailEnd", true) :: Attachment
	tipAttachment.WorldPosition = Vector3.new(0, 3, 0)
	local recording = false
	local lastTip: Vector3? = nil
	local realPush = TrailRibbon.push
	TrailRibbon.push = function(ribbon: any, guard: Vector3, tip: Vector3, born: number, joined: boolean): boolean
		local ok = realPush(ribbon, guard, tip, born, joined)
		if recording and ok then
			result.pushes[frame] = (result.pushes[frame] or 0) + 1
			if joined and lastTip ~= nil then
				result.longest = math.max(result.longest, (tip - (lastTip :: Vector3)).Magnitude)
			end
			lastTip = tip
		end
		return ok
	end
	local handle: any = nil
	local dt = 1 / fps
	local function step()
		afterRender = false
		frame += 1
		clock += dt
		if recording then
			-- Replication moves the copy's root between frames.
			root.CFrame = root.CFrame + drift * dt
		end
		hooks.start(dt)
		if handle ~= nil then
			result.shown[frame] = handle.time
		end
		if hooks.drawn ~= nil then
			hooks.drawn(0)
		end
		animator:step(dt)
		hooks.posed(dt)
		local posed = BladeContact.chain(model :: any)
		local _, posedTip = BladeContact.blade(posed, BladeContact.read(posed))
		tipAttachment.WorldPosition = posedTip
		if hooks.readers ~= nil then
			hooks.readers(0)
		end
		result.held[frame] = animator:heldShown() == true
		hooks.finish(dt)
		afterRender = true
		for _, beat in beats do
			beat(dt)
		end
	end
	local ok, err = pcall(function()
		for _ = 1, 60 do
			step()
		end
		recording = true
		Replication.dispatch("ActionStarted", {
			entityId = A_ID,
			clipId = VERTICAL,
			serverTime = clock - late,
			facing = { 0, 0, -1 },
			artId = VERTICAL_ART,
		})
		handle = animator.mixer:find(VERTICAL)
		for _ = 1, math.ceil(0.7 * fps) do
			step()
			if word ~= nil and result.sentOn == nil and handle.time >= word.at then
				result.sentOn, result.sentAt = frame, handle.time
				afterRender = true
				Replication.dispatch("HitConfirmed", {
					attackerId = word.attackerId,
					targetId = word.targetId,
					damage = 10,
					hpRemoved = 10,
					crit = false,
					gaugeDamage = 0,
					killed = false,
					broke = false,
					hitStop = "Final",
					position = { 0, 3, -3 },
					parried = false,
					guarded = false,
					reflected = false,
					artId = word.artId,
					hitIndex = 1,
				})
			end
		end
	end)
	TrailRibbon.push = realPush
	Replication.unwatch(record)
	Trails.bind(nil)
	Trails.reset()
	Engine.setViewer(nil)
	Engine.setClock(nil)
	Choreo.release(model)
	FrameClock.bind(nil)
	if not ok then
		error(err, 0)
	end
	for f = 1, frame do
		local shown = result.shown[f]
		if shown ~= nil then
			if result.firstHeld == nil and result.held[f] then
				result.firstHeld = f
			end
			if result.endFrame == nil and shown >= KEY - EPSILON then
				result.endFrame = f
			end
			if (result.pushes[f] or 0) > 0 then
				result.lastPush = f
			end
		end
	end
	return result
end

-- The samples the ribbon kept on frames drawn held.
local function onHeld(result: Take): number
	local count = 0
	for f, pushes in result.pushes do
		if result.held[f] then
			count += pushes
		end
	end
	return count
end

-- A's word for its own hit on the boar (this client does not track it).
local function hitWord(at: number): Word
	return { at = at, attackerId = A_ID, targetId = BOAR_ID, artId = VERTICAL_ART }
end

describe("Trails: a frame drawn held lays nothing on a watcher's copy (D-556)", function()
	it(
		"a copy frozen mid-stroke whose root still moves: no sample while held, the stroke on to its end pose",
		function()
			-- A boar's blow on A, seen by B, freezes A's copy at once wherever its swing is (the word
			-- names A as the target), and replication moves A's root 4 studs a second meanwhile.
			-- Before: a drift along the cut laid a sample on every held frame at 30 and 60 and on every
			-- other one at 144 (6 at 60, 7 at 144); a drift against it turned the cut back on a held
			-- frame and ended the stroke short of its end pose (the rest of the snap never drawn).
			local drifts: { [string]: Vector3 } = {
				forward = Vector3.new(0, 0, -4),
				back = Vector3.new(0, 0, 4),
				down = Vector3.new(0, -4, 0),
				up = Vector3.new(0, 4, 0),
				side = Vector3.new(4, 0, 0),
			}
			for _, fps in RATES do
				-- The stroke with no freeze and a still root: its longest segment (1.51 at 30 fps, where
				-- the sub-step cap spreads the snap's frame over 8 samples, 0.79 at 60, 0.46 at 144).
				local still = take(fps, LAG_ZERO, Vector3.zero, nil)
				for name, drift in drifts do
					for _, at in { 0.36, 0.385 } do
						local result = take(fps, LAG_ZERO, drift, { at = at, attackerId = BOAR_ID, targetId = A_ID })
						local label = ("%d fps, drift %s, frozen at %.3f"):format(fps, name, at)
						expect({ label, result.firstHeld ~= nil, (result.sentAt :: number) < KEY }).toEqual({
							label,
							true,
							true,
						})
						expect({ label, onHeld(result) }).toEqual({ label, 0 })
						-- The stroke reaches its end pose after the release, and ends there (D-539).
						expect({ label, result.lastPush, result.endFrame ~= nil }).toEqual({
							label,
							result.endFrame,
							true,
						})
						-- The release's first segment spans what the root moved under the held pose (the
						-- freeze's 0.1 s and a frame), never more.
						local reach = still.longest
							+ drift.Magnitude * (Combat.hitStopFrames.Final / 60 + 1 / fps)
							+ 0.05
						expect({ label, result.longest <= reach }).toEqual({ label, true })
					end
				end
			end
		end
	)
end)

describe("Replication: a watcher's copy holds another player's hit on its strike's key (D-557)", function()
	it(
		"a word that comes before the copy shows the key freezes the key pose, its cues on the frame drawing it",
		function()
			-- Before: the copy froze where the word found it (clip 0.36 to 0.391, the PC's 0.383 to
			-- 0.391), the snap 0.1 to 1.9 studs short of its end, and its release skipped the clip's
			-- own hold (0.40 to 0.43). Now the first frame drawn held shows the key pose, the hit's cues
			-- play on the frame before it (the first that draws the key), and the ribbon's last segment
			-- is on that frame: the PC's 468(a) with N the end pose's row.
			for _, fps in RATES do
				for _, drift in { Vector3.zero, Vector3.new(0, 0, -4) } do
					for _, at in { 0.36, 0.383, 0.391 } do
						local result = take(fps, LAG_ZERO, drift, hitWord(at))
						local label = ("%d fps, drift %.0f, word at %.3f"):format(fps, drift.Magnitude, at)
						local sentAt = result.sentAt :: number
						expect({ label, sentAt < KEY - EPSILON }).toEqual({ label, true })
						local firstHeld = result.firstHeld :: number
						local frozen = result.shown[firstHeld]
						expect({ label, frozen >= KEY - EPSILON, frozen <= HOLD_END + 1e-6 }).toEqual({
							label,
							true,
							true,
						})
						-- The frame before the first held one draws the key pose, the frame before that
						-- did not yet.
						expect({ label, result.endFrame }).toEqual({ label, firstHeld - 1 })
						expect({ label, result.cues }).toEqual({ label, { firstHeld - 1 } })
						expect({ label, onHeld(result), result.lastPush }).toEqual({ label, 0, result.endFrame })
					end
				end
			end
		end
	)

	it(
		"a word after the key, one on the local fighter, or one for another swing freezes at once (unchanged)",
		function()
			-- At lag 0.1 the word comes past the key (the PC's 468 at lag 0.1 passed): it freezes on
			-- the next step, as before. A hit on the local fighter keeps its own timing (D-258,
			-- D-355), and a word for an Art the copy is not playing does not wait on it.
			for _, fps in RATES do
				local cases: { [string]: Word } = {
					["after the key"] = hitWord(0.45),
					["on the local fighter"] = { at = 0.383, attackerId = A_ID, targetId = B_ID, artId = VERTICAL_ART },
					["another swing"] = {
						at = 0.383,
						attackerId = A_ID,
						targetId = BOAR_ID,
						artId = "OneHandedSword.Horizontal",
					},
				}
				for name, word in cases do
					local result = take(fps, LAG_ZERO, Vector3.zero, word)
					local label = ("%d fps, %s"):format(fps, name)
					local sentOn = result.sentOn :: number
					-- The step after the word is frozen, and the frame after it draws it held.
					expect({ label, result.firstHeld, result.shown[result.firstHeld :: number] }).toEqual({
						label,
						sentOn + 2,
						result.sentAt,
					})
					expect({ label, result.cues }).toEqual({ label, { sentOn + 1 } })
				end
			end
		end
	)
end)
