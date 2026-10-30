--!strict
--[[
	An enemy's blow on the local fighter shows its beats in order on one frame base (amends D-258):
	the contact (the frame that first draws the attack's clip at its strike, the server's strike
	frame), then both bodies frozen for the blow's tier from the next frame on, the white flash and
	the server's number inside that freeze. While the server's word has not come the freeze holds on,
	one frame at a time, at most combat.contact.wordHoldSeconds from the contact (as a contact of the
	local fighter's own blade does, D-312); the frame that first shows the number is still frozen.

	Studio (PC rehearsal cebade4-e, shot 7, the Kobold's Overhead at the player): the white flash
	showed on f106/102/102, two frames before the HitConfirmed (f108/104/104); the number came on the
	message frame; the Kobold froze 0 or 1 frame and the player not at all. Through the real path
	below before this change: the player froze no frame; the Kobold froze none either (its clip's own
	authored hold after the snap was all that stood still), the flash drew on the frame after the
	contact and the number up to 7 frames after it (0.1 s of lag), outside any freeze.

	The path: Mixers for both rigs (the Kobold playing its Overhead from the server's time, as Choreo
	does), Replication bound with a Heartbeat, the local fighter's defence and the server's clock.
	The server's Telegraph and ActionStarted at the attack's start, its StateChanged and HitConfirmed
	on its strike frame, each heard `latency` later, before the frame's render step or after it. A
	frame is frozen when the rig's Mixer holds it (StepResult.paused).
]]

local Combat = Harness.load("src/shared/data/combat")
local Enemies = Harness.load("src/shared/data/enemies")
local Mixer = Harness.load("src/client/choreo/Mixer")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Replication = Harness.load("src/client/controllers/Replication")
local FrameClock = Harness.load("src/client/fx/FrameClock")
local Impact = Harness.load("src/client/fx/Impact")
local ImpactFrames = Harness.load("src/client/fx/ImpactFrames")
local FlashBudget = Harness.load("src/client/fx/FlashBudget")
local IMPACT_LOOKS = Harness.load("src/shared/data/impact").looks
-- The engine draws a pose on the frame after the step that wrote it (D-342): the engine's lag,
-- not impact.poseLagFrames (the code's model of it).
local ENGINE_LAG = 1

local DEF = Enemies.byId("KoboldAxeman")
local OVERHEAD: any = nil
for _, attack in DEF.attacks do
	if attack.id == "Overhead" then
		OVERHEAD = attack
	end
end
assert(OVERHEAD ~= nil, "the Kobold has no Overhead")
local CLIP_ID = "enemy/" .. DEF.skin .. "/" .. OVERHEAD.clip
-- Clip seconds from the attack's start to its strike (the server's strike frame).
local STRIKE = OVERHEAD.windUp + OVERHEAD.strike

local function clipOf(clipId: string): any
	local ok, clip = pcall(function(): any
		return Harness.load("src/shared/clips/" .. clipId)
	end)
	return if ok then clip else nil
end

local function recorder(): any
	return setmetatable({}, {
		__index = function(): any
			return function(): any
				return nil
			end
		end,
	})
end

-- Stands a model's root at `position` looking along `look` (flat).
local function placed(name: string, position: Vector3, look: Vector3): Model
	local model = Instance.new("Model")
	model.Name = name
	local part = Instance.new("Part")
	part.Name = "HumanoidRootPart"
	part.Size = Vector3.new(2, 2, 1)
	part.Parent = model
	model.PrimaryPart = part
	part.CFrame = CFrame.lookAt(position, position + look)
	return model
end

type Log = {
	frames: number,
	contact: number?, -- the frame that first draws the Overhead at its strike
	me: { [number]: boolean }, -- the local rig's Mixer held the frame
	them: { [number]: boolean }, -- the Kobold's Mixer held the frame
	-- What a reader of the hold sees after every render step (Last + 1, Choreo isPaused): the rig
	-- still holds.
	myFlags: { [number]: boolean },
	theirFlags: { [number]: boolean },
	flash: number?, -- the first frame the local fighter's white flash shows on
	number: number?, -- the first frame the server's number shows on
	flinchStopped: boolean,
	flinches: number, -- the flinch clips played on the local fighter
	pose: { [number]: number }, -- the local rig's pose each frame, summed over its joints
	theirPose: { [number]: number }, -- the Kobold's pose each frame, summed over its joints
	-- With `pictures`: the overlay's look each frame draws (ImpactFrames.look after its render
	-- step), and the frame the Kill moment played on.
	looks: { [number]: string },
	kill: number?,
}

-- One number for a pose: every joint offset's position and rotation summed (a still pose repeats it).
local function poseSum(offsets: any): number
	local total = 0
	for _, offset in offsets do
		total += offset.pos[1] + offset.pos[2] + offset.pos[3] + offset.rot[1] + offset.rot[2] + offset.rot[3]
	end
	return total
end

-- Plays the Overhead at the local fighter through the real path. options: afterRender (the
-- server's messages are heard after the frame's render step), phase (the attack starts this much
-- of a frame off the client's frame grid), late (the word comes this much later still), noWord
-- (the server never confirms the blow), wordFirst (the HitConfirmed comes before the Stagger word,
-- as the server sends them), kill (the blow kills the fighter: a Kill hit-stop and the Dead word),
-- pictures (the real Impact director and ImpactFrames overlay play the moments, logging looks).
local function play(fps: number, latency: number, options: any?): Log
	local opts = options or {}
	local dt = 1 / fps
	local clock = 50
	local offset = 50 -- the server's clock runs this far ahead of this client's
	local function server(): number
		return clock + offset
	end
	local frame = 0
	local phase = "render"
	local log: Log = {
		frames = 0,
		me = {},
		them = {},
		myFlags = {},
		theirFlags = {},
		flinchStopped = false,
		flinches = 0,
		pose = {},
		theirPose = {},
		looks = {},
	}
	-- The frame a call made now first shows on: this one up to the end of its render steps, else
	-- the next.
	local function shownOn(): number
		return if phase == "after" then frame + 1 else frame
	end
	-- The real FrameClock on this loop's render steps (its start, its posed mark after the rigs'
	-- step, its end), and the controller's step after its contacts (CharacterController.afterContacts).
	local clockStart: ((dt: number) -> ())? = nil
	local clockPosed: ((dt: number) -> ())? = nil
	local clockEnd: ((dt: number) -> ())? = nil
	FrameClock.bind({
		now = function(): number
			return clock
		end,
		onFrameStart = function(fn: any): () -> ()
			clockStart = fn
			return function()
				clockStart = nil
			end
		end,
		onPosed = function(fn: any): () -> ()
			clockPosed = fn
			return function()
				clockPosed = nil
			end
		end,
		onFrameEnd = function(fn: any): () -> ()
			clockEnd = fn
			return function()
				clockEnd = nil
			end
		end,
		onHeartbeat = function(): () -> ()
			return function() end
		end,
	} :: any)
	FrameClock.after(1, function() end)()
	local afterContacts: { (dt: number) -> () } = {}
	local mixer = Mixer.new()
	local enemyMixer = Mixer.new()
	local me = placed("Me", Vector3.new(0, 3, -3.5), Vector3.new(0, 0, 1))
	local kobold = placed("Kobold", Vector3.new(0, 3, 0), Vector3.new(0, 0, -1))
	local idle = clipOf("player/OneHandedSword/Idle")
	if idle ~= nil then
		mixer:play(idle)
	end
	local overhead: any = nil
	-- The clock at the Kobold's last render step: a clip played since then moves by the whole of
	-- its first step, the part before it was played too (Choreo's sinceStep).
	local enemyStepAt = clock
	local animators: { [any]: any } = {
		[me] = {
			hitStop = function(_self: any, frames: number)
				mixer:hitStop(frames)
			end,
			pauseRemaining = function(_self: any): number
				return mixer:pauseRemaining()
			end,
			play = function(_self: any, clipId: string): any
				if string.find(clipId, "Flinch", 1, true) ~= nil then
					log.flinches += 1
				end
				local clip = clipOf(clipId)
				return if clip ~= nil then mixer:play(clip) else { clipId = clipId }
			end,
			stop = function(_self: any, handle: any, blendOut: number?)
				if typeof(handle) == "table" and handle.clip ~= nil then
					log.flinchStopped = true
					mixer:stop(handle, blendOut)
				end
			end,
		},
		[kobold] = {
			hitStop = function(_self: any, frames: number)
				enemyMixer:hitStop(frames)
			end,
			pauseRemaining = function(_self: any): number
				return enemyMixer:pauseRemaining()
			end,
			play = function(_self: any, clipId: string, playOptions: any?): any
				local clip = clipOf(clipId)
				if clip == nil then
					return { clipId = clipId }
				end
				local o = playOptions or {}
				local handle = enemyMixer:play(
					clip,
					{ serverTime = o.serverTime, now = server(), speed = o.speed, sinceStep = clock - enemyStepAt }
				)
				if clipId == CLIP_ID then
					overhead = handle
				end
				return handle
			end,
			stop = function(_self: any, handle: any, blendOut: number?)
				if typeof(handle) == "table" and handle.clip ~= nil then
					enemyMixer:stop(handle, blendOut)
				end
			end,
			-- As Choreo's animator: the clip keeps the server's beat up to its first hit window, and
			-- gives back what its first step moves it ahead.
			keepBeat = function(_self: any, handle: any, serverTime: number?)
				local first = ClipSampler.hitWindows(handle.clip)[1]
				if first == nil then
					return
				end
				local owed = 0
				if serverTime ~= nil then
					owed = math.max(0, (server() - serverTime) - handle.time / handle.speed)
				end
				owed -= handle.sinceStep or 0
				enemyMixer:keepBeat(handle, first.open, owed)
			end,
			shiftBeat = function(_self: any, handle: any, seconds: number)
				enemyMixer:shiftBeat(handle, seconds)
			end,
		},
	}
	local records: { [number]: any } = {
		[1] = { id = 1, model = me, kind = "Player", rig = "PlayerR15", weaponId = "TrialistSword" },
		[8] = { id = 8, model = kobold, kind = "Enemy", rig = DEF.skin, defId = DEF.id },
	}
	local outline = setmetatable({
		flash = function(model: any)
			if model == me and log.flash == nil then
				log.flash = shownOn()
			end
		end,
	}, { __index = recorder() })
	local digits = setmetatable({
		show = function()
			if log.number == nil then
				log.number = shownOn()
			end
		end,
	}, { __index = recorder() })
	local impact: any = setmetatable({
		hit = function(): string
			return "Hit"
		end,
		ownsHighlight = function(): boolean
			return false
		end,
	}, { __index = recorder() })
	-- With `pictures`, the real director and the real overlay on this loop's clock and render step
	-- (fx.luau renderOrder.impactFrames, after the controller's), and the real flash budget.
	local overlayStep: ((dt: number) -> ())? = nil
	local overlayWatch: ((dt: number) -> ())? = nil
	local scheduled: { { at: number, fn: () -> () } } = {}
	if opts.pictures then
		ImpactFrames.bind({
			now = function(): number
				return clock
			end,
			onRender = function(step: (dt: number) -> ()): () -> ()
				overlayStep = step
				return function()
					if overlayStep == step then
						overlayStep = nil
					end
				end
			end,
			onHeartbeat = function(step: (dt: number) -> ()): () -> ()
				overlayWatch = step
				return function()
					if overlayWatch == step then
						overlayWatch = nil
					end
				end
			end,
			playerGui = function()
				return Instance.new("Folder")
			end,
			camera = function()
				return nil
			end,
			project = function()
				return nil
			end,
			aspect = function()
				return 16 / 9
			end,
			quality = function()
				return "High"
			end,
			random = Random.new(3),
			pace = (FrameClock :: any).pace,
		} :: any)
		FlashBudget.reset()
		Impact.bind({
			impactFrames = ImpactFrames,
			glint = recorder(),
			slashArc = recorder(),
			speedLines = recorder(),
			trails = recorder(),
			sfx = recorder(),
			camera = recorder(),
			outline = recorder(),
			now = function(): number
				return clock
			end,
			viewerPosition = function(): Vector3
				return Vector3.new(0, 5, 10)
			end,
			positionOf = function(): Vector3
				return Vector3.zero
			end,
			delay = function(seconds: number, fn: () -> ())
				table.insert(scheduled, { at = clock + seconds, fn = fn })
			end,
		} :: any)
		impact = setmetatable({
			hit = function(info: any, previous: string?): string
				local name = Impact.hit(info, previous)
				if name == "Kill" and log.kill == nil then
					log.kill = shownOn()
				end
				return name
			end,
		}, { __index = Impact })
	end
	local heartbeat: any = nil
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id: number): any
				return records[id]
			end,
			all = function(): { any }
				return {}
			end,
		},
		localId = function(): number?
			return 1
		end,
		locomotion = recorder(),
		choreo = {
			get = function(model: any): any
				return animators[model]
			end,
		},
		clipLibrary = {
			has = function(): boolean
				return true
			end,
		},
		trails = recorder(),
		smear = recorder(),
		shatter = recorder(),
		sparks = recorder(),
		telegraphs = recorder(),
		outline = outline,
		switchRing = recorder(),
		digits = digits,
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
		serverNow = server,
		onHeartbeat = function(fn: any)
			heartbeat = fn
		end,
		atPose = (FrameClock :: any).atPose,
		pace = (FrameClock :: any).pace,
		onFrame = function(fn: (dt: number) -> ())
			table.insert(afterContacts, fn)
		end,
		localDefence = function(): (string, number?)
			return "Idle", nil
		end,
	} :: any)
	-- The attack starts on a server frame a little ahead, `phase` of a frame off this client's grid.
	local since = server() + 0.2 + (opts.phase or 0) * dt
	local words: { any } = {
		{
			at = since + latency,
			name = "Telegraph",
			payload = {
				entityId = 8,
				attackId = OVERHEAD.id,
				kind = OVERHEAD.telegraph,
				windUp = OVERHEAD.windUp,
				serverTime = since,
				origin = { 0, 3, 0 },
				facing = { 0, 0, -1 },
				shape = { kind = OVERHEAD.groundShape, length = OVERHEAD.reach, width = OVERHEAD.arc },
			},
		},
		{
			at = since + latency,
			name = "ActionStarted",
			payload = { entityId = 8, clipId = CLIP_ID, serverTime = since, facing = { 0, 0, -1 } },
		},
	}
	if not opts.noWord then
		local heard = since + STRIKE + latency + (opts.late or 0)
		table.insert(words, {
			at = heard,
			name = "StateChanged",
			payload = if opts.kill
				then { entityId = 1, state = "Dead" }
				else { entityId = 1, state = "Stagger", duration = 0.5, direction = "Front" },
		})
		table.insert(words, {
			at = heard,
			name = "HitConfirmed",
			payload = {
				attackerId = 8,
				targetId = 1,
				damage = 34,
				hpRemoved = if opts.kill then 20 else nil,
				crit = false,
				gaugeDamage = 0,
				killed = opts.kill == true,
				broke = false,
				hitStop = if opts.kill then "Kill" else "Normal",
				position = { 0, 3, -3.5 },
				parried = false,
				guarded = false,
				hitIndex = 1,
			},
		})
		if opts.wordFirst then
			-- The Stagger word after the HitConfirmed, in one packet.
			local stagger = table.remove(words, #words - 1)
			table.insert(words, stagger)
		end
	end
	local function deliver()
		while #words > 0 and server() >= words[1].at - 1e-9 do
			local word = table.remove(words, 1)
			Replication.dispatch(word.name, word.payload)
		end
	end
	local finish = since + STRIKE + 1.2
	while server() < finish do
		frame += 1
		clock += dt
		phase = "before"
		local s = 1
		while s <= #scheduled do
			if clock >= scheduled[s].at - 1e-9 then
				(table.remove(scheduled, s) :: { at: number, fn: () -> () }).fn()
			else
				s += 1
			end
		end
		if not opts.afterRender then
			deliver()
		end
		phase = "render"
		if clockStart ~= nil then
			clockStart(dt)
		end
		local theirs = enemyMixer:step(dt)
		log.them[frame] = theirs.paused
		log.theirPose[frame] = poseSum(theirs.offsets)
		enemyStepAt = clock
		if clockPosed ~= nil then
			clockPosed(dt)
		end
		local mine = mixer:step(dt)
		log.me[frame] = mine.paused
		log.pose[frame] = poseSum(mine.offsets)
		if log.contact == nil and overhead ~= nil and overhead.time >= STRIKE - 1e-6 then
			log.contact = frame
		end
		for _, after in afterContacts do
			after(dt)
		end
		-- The overlay's render step (after the controller's and the camera's), then what it shows.
		if overlayStep ~= nil then
			overlayStep(dt)
		end
		if opts.pictures then
			local look = ImpactFrames.look()
			if look ~= nil then
				log.looks[frame] = look
			end
		end
		if clockEnd ~= nil then
			clockEnd(dt)
		end
		log.myFlags[frame] = mixer:pauseRemaining() > 0
		log.theirFlags[frame] = enemyMixer:pauseRemaining() > 0
		phase = "after"
		if opts.afterRender then
			deliver()
		end
		if heartbeat ~= nil then
			heartbeat(dt)
		end
		if overlayWatch ~= nil then
			overlayWatch(dt)
		end
	end
	if opts.pictures then
		ImpactFrames.bind(nil)
		FlashBudget.reset()
		Impact.bind({})
	end
	log.frames = frame
	return log
end

-- The frames a hold of `frames` (at 60) freezes at `fps`: the nearest whole count (D-271).
local function framesAt(frames: number, fps: number): number
	return math.floor(frames / 60 * fps + 0.5)
end

-- The frozen frames from the frame after `contact` on, without a break.
local function runFrom(paused: { [number]: boolean }, contact: number): number
	local length = 0
	while paused[contact + 1 + length] do
		length += 1
	end
	return length
end

local function describeCase(fps: number, latency: number, afterRender: boolean, phase: number): string
	return ("%d fps, %d ms%s, phase %.2f"):format(
		fps,
		math.floor(latency * 1000 + 0.5),
		if afterRender then " (heard after the render step)" else "",
		phase
	)
end

describe("an enemy's blow on the local fighter shows its beats on one frame base", function()
	it(
		"both bodies freeze for its tier from the frame after the contact; the flash and the number show inside",
		function()
			local cap = Combat.contact.wordHoldSeconds
			local checked, waited, planned = 0, 0, 0
			for _, fps in { 30, 60, 144 } do
				local tier = framesAt(Combat.hitStopFrames.Normal, fps)
				for _, latency in { 0, 1 / 60, 0.05, 0.1 } do
					for _, afterRender in { false, true } do
						-- A word heard before a render step is at least a frame old: it left the server
						-- on an earlier frame (Roblox hears the network after the render step, D-155).
						if not afterRender and latency < 1 / fps - 1e-9 then
							continue
						end
						for _, phase in { 0, 0.37 } do
							planned += 1
							local where = describeCase(fps, latency, afterRender, phase)
							local log = play(fps, latency, { afterRender = afterRender, phase = phase })
							local contact = log.contact
							if contact == nil then
								error(where .. ": the Overhead never reached its strike")
							end
							for f = 1, contact do
								if log.me[f] or log.them[f] then
									error(
										("%s: a rig froze on frame %d, before the contact (%d)"):format(
											where,
											f,
											contact
										)
									)
								end
							end
							local mine = runFrom(log.me, contact)
							local theirs = runFrom(log.them, contact)
							if mine < tier or theirs < tier then
								error(
									("%s: from the contact (frame %d) the fighter froze %d frames and the Kobold %d, the tier is %d"):format(
										where,
										contact,
										mine,
										theirs,
										tier
									)
								)
							end
							if log.flash ~= contact + 1 then
								error(
									("%s: the flash first showed on frame %s, the contact is %d"):format(
										where,
										tostring(log.flash),
										contact
									)
								)
							end
							local shown = log.number
							if shown == nil then
								error(where .. ": no number")
							end
							if shown <= contact or shown > contact + mine or shown > contact + theirs then
								error(
									("%s: the number showed on frame %d, the fighter froze %d to %d and the Kobold %d to %d"):format(
										where,
										shown,
										contact + 1,
										contact + mine,
										contact + 1,
										contact + theirs
									)
								)
							end
							-- Held on for the word and no longer: the tier, or up to the frame the number shows.
							local want = math.max(tier, shown - contact)
							if mine ~= want or theirs ~= want then
								error(
									("%s: froze %d (fighter) and %d (Kobold) frames, the tier and the word ask %d"):format(
										where,
										mine,
										theirs,
										want
									)
								)
							end
							if want > math.max(tier, math.floor(cap * fps + 1e-6)) then
								error(("%s: froze %d frames, past the cap"):format(where, want))
							end
							for f = contact + want + 1, log.frames do
								if log.me[f] or log.them[f] then
									error(("%s: froze again on frame %d"):format(where, f))
								end
							end
							checked += 1
							if want > tier then
								waited += 1
							end
						end
					end
				end
			end
			expect(planned >= 36).toBe(true)
			expect(checked).toBe(planned)
			-- The lags past a Normal's frames are what held on.
			expect(waited > 0).toBe(true)
		end
	)

	it("the wait for the word is one freeze on both rigs, in the hold's flag as on screen (D-347)", function()
		local waited = 0
		for _, fps in { 30, 60, 144 } do
			local tier = framesAt(Combat.hitStopFrames.Normal, fps)
			for _, latency in { 0.05, 0.1, 0.1 + 1 / 60 } do
				for _, afterRender in { false, true } do
					local where = describeCase(fps, latency, afterRender, 0)
					local log = play(fps, latency, { afterRender = afterRender })
					local contact = log.contact :: number
					for label, rig in { fighter = { log.me, log.myFlags }, Kobold = { log.them, log.theirFlags } } do
						local run = runFrom(rig[1], contact)
						if run > tier then
							waited += 1
						end
						-- The flag stands from the first frozen step to the last one's eve (the blow is
						-- judged on the Heartbeat after the strike's frame, past that frame's readers).
						for f = contact + 1, contact + run - 1 do
							if not rig[2][f] then
								error(
									("%s: the %s's flag fell on frame %d inside its freeze (%d to %d)"):format(
										where,
										label,
										f,
										contact + 1,
										contact + run
									)
								)
							end
						end
					end
				end
			end
		end
		expect(waited > 0).toBe(true)
	end)

	it("past the cap both bodies go on, the number shows when it comes, and nothing freezes again", function()
		for _, fps in { 60, 144 } do
			local log = play(fps, 0.05, { late = 0.3 })
			local contact = log.contact :: number
			local cap = math.floor(Combat.contact.wordHoldSeconds * fps + 1e-6)
			expect(runFrom(log.me, contact)).toBe(cap)
			expect(runFrom(log.them, contact)).toBe(cap)
			expect(log.flash).toBe(contact + 1)
			expect((log.number :: number) > contact + cap).toBe(true)
			for f = contact + cap + 1, log.frames do
				expect(log.me[f]).toBe(false)
				expect(log.them[f]).toBe(false)
			end
		end
	end)

	it("its flinch plays once and the frozen fighter holds still, whichever word comes first", function()
		for _, fps in { 30, 60, 144 } do
			for _, wordFirst in { false, true } do
				for _, latency in { 1 / 60, 0.05, 0.1 } do
					local where = ("%d fps, %d ms, %s first"):format(
						fps,
						math.floor(latency * 1000 + 0.5),
						if wordFirst then "the HitConfirmed" else "the Stagger"
					)
					local log = play(fps, latency, { afterRender = true, wordFirst = wordFirst })
					local contact = log.contact :: number
					local run = runFrom(log.me, contact)
					if log.flinches ~= 1 then
						error(("%s: %d flinches played"):format(where, log.flinches))
					end
					-- The first frozen frame shows the blow's flinch at its first key; the rest repeat it.
					for f = contact + 2, contact + run do
						if math.abs(log.pose[f] - log.pose[contact + 1]) > 1e-9 then
							error(
								("%s: the fighter moved on frame %d inside its freeze (%d to %d)"):format(
									where,
									f,
									contact + 1,
									contact + run
								)
							)
						end
					end
				end
			end
		end
	end)

	-- A kill's word heard late inside the wait (0.12 to 0.2 s) starts its picture when the freeze it
	-- joins is nearly done: on the HM tree both bodies moved on under its figure frames (at 60 fps
	-- up to 4 of the Kill's 6 frames on the Kobold, 2 on the fighter; at 144 up to 13 of 15). The
	-- word holds both bodies over its picture (D-350): every frame that draws the figures draws the
	-- Kobold at its strike and the fighter at its flinch's first key, one freeze, frozen no longer
	-- than the picture asks. Through the real director and overlay.
	it("a kill heard late inside the wait draws its whole picture on both struck bodies (D-350)", function()
		local checked = 0
		for _, fps in { 30, 60, 144 } do
			for _, latency in { 0.05, 0.1, 0.12, 0.15, 0.18, 0.2 } do
				for _, afterRender in { false, true } do
					local where = describeCase(fps, latency, afterRender, 0)
					local log = play(fps, latency, { afterRender = afterRender, kill = true, pictures = true })
					local contact = log.contact :: number
					local kill = log.kill
					if kill == nil then
						error(where .. ": no kill played")
					end
					local struckThem, struckMe = log.theirPose[contact], log.pose[contact + 1]
					local last: number? = nil
					for f = contact, log.frames do
						local look = log.looks[f]
						local row = if look ~= nil then IMPACT_LOOKS[look] else nil
						if row == nil then
							continue
						end
						last = f
						-- A frame that draws the figures draws the pose its rigs' step wrote ENGINE_LAG
						-- frames before (D-342).
						if row.figures ~= nil then
							local movedThem = math.abs(log.theirPose[f - ENGINE_LAG] - struckThem) > 1e-9
							local movedMe = math.abs(log.pose[f - ENGINE_LAG] - struckMe) > 1e-9
							if movedThem or movedMe then
								error(
									("%s: the %s look on frame %d drew %s moved on (the contact on %d, the kill's word on %d)"):format(
										where,
										look :: string,
										f,
										if movedThem then "a Kobold" else "a fighter",
										contact,
										kill :: number
									)
								)
							end
						end
					end
					-- Past the cap: no picture (D-348).
					if last == nil then
						if (kill :: number) - contact <= math.floor(Combat.contact.wordHoldSeconds * fps + 1e-6) then
							error(
								("%s: the kill on frame %d inside the wait showed no picture"):format(
									where,
									kill :: number
								)
							)
						end
						continue
					end
					checked += 1
					-- One freeze on each rig: once it lets go it never comes back.
					for label, paused in { fighter = log.me, Kobold = log.them } do
						local fell: number? = nil
						for f = contact + 1, log.frames do
							if not paused[f] then
								fell = fell or f
							elseif fell ~= nil then
								error(
									("%s: the %s froze again on frame %d after letting go on %d"):format(
										where,
										label,
										f,
										fell
									)
								)
							end
						end
					end
					-- Frozen to the eve of the picture's last frame (that frame draws the step before it),
					-- or where the hold lets go without one (the Kill hold, D-313, or the wait for the
					-- word, D-312) if later: the picture asks for no frame more.
					local bare = play(fps, latency, { afterRender = afterRender, kill = true })
					for label, rig in { Kobold = { log.them, bare.them }, fighter = { log.me, bare.me } } do
						local without = contact + runFrom(rig[2], contact)
						local got = contact + runFrom(rig[1], contact)
						if got ~= math.max((last :: number) - ENGINE_LAG, without) then
							error(
								("%s: the %s froze to frame %d, the picture ended on %d and the hold without it on %d (contact %d, kill %d)"):format(
									where,
									label,
									got,
									last :: number,
									without,
									contact,
									kill :: number
								)
							)
						end
					end
				end
			end
		end
		expect(checked).toBeGreaterThan(30)
	end)

	it("a blow the server never confirms freezes to the cap, shows no number and takes the flinch back", function()
		for _, fps in { 60, 144 } do
			local log = play(fps, 0.05, { noWord = true })
			local contact = log.contact :: number
			local cap = math.floor(Combat.contact.wordHoldSeconds * fps + 1e-6)
			expect(runFrom(log.me, contact)).toBe(cap)
			expect(runFrom(log.them, contact)).toBe(cap)
			expect(log.number).toBe(nil)
			expect(log.flinchStopped).toBe(true)
		end
	end)
end)
