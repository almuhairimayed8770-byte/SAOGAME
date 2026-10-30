--!strict
--[[
	A remote fighter's stance the server takes away comes down as the local one's does (D-422;
	D-340 for the local fighter).

	A remote player's Art plays from its ActionStarted (Replication.handlers.ActionStarted). When a
	blow staggers that fighter before the Art's first cut, the server sends StateChanged Stagger with
	the blow's direction (CombatService on a player hit), and Replication plays the directional
	flinch, which rides the Additive layer. Before D-422 nothing stopped the Art: through this path
	its handle stayed live for 45 frames after the word, the cut swinging on through the stagger at
	301 to 453 studs a second and lighting its trail. With no direction the Stagger clip (FullBody,
	priority 30) replaced it at its own 0.15 s blend, the tip jumping about 400 studs a second on the
	first frame. The local fighter's stance comes down over combat.luau struckStanceBlendOut and
	starts no trail (CharacterController.takeArtAway, StanceLetGo.spec).

	The remote rig is the real one (Choreo animator, Locomotion, Replication.watch), stepped at
	60 Hz.

	- An Art let go in its stance (past its ActivationHold, short of its first damage frame) is
	  fading out over struckStanceBlendOut on the step after the word, and no trail lights on the
	  rig after it, whatever the flinch's direction.
	- An Art past its first damage frame stops at the locomotion blend, as the local fighter's
	  stopClip does: a directional flinch no longer lets it swing on.
]]
local Replication = Harness.load("src/client/controllers/Replication")
local ChoreoData = Harness.load("src/shared/data/choreo")
local Combat = Harness.load("src/shared/data/combat")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local function recorder(moduleName, calls)
	return setmetatable({}, {
		__index = function(_, key)
			return function(...)
				table.insert(calls, { module = moduleName, fn = key, args = { ... } })
			end
		end,
	})
end

local function liveRemote(liveOptions: { isLocal: boolean? }?)
	local isLocal = liveOptions ~= nil and liveOptions.isLocal == true
	local function frameSignal()
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
		-- Choreo's rig step (bound just before the camera's): the spec steps the rigs itself.
		BindToRenderStep = function() end,
		UnbindFromRenderStep = function() end,
	})
	local Choreo = Harness.load("src/client/choreo/Choreo")
	local Locomotion = Harness.load("src/client/choreo/Locomotion")
	local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
	local Rigs = Harness.load("src/shared/data/rigs")
	local RigBuilder = Harness.load("src/server/world/RigBuilder")
	local WeaponBuilder = Harness.load("src/server/world/WeaponBuilder")
	local WeaponModels = Harness.load("src/shared/data/weaponModels")
	local Weapons = Harness.load("src/shared/data/weapons")
	local clock = 100
	Choreo.configure({
		now = function()
			return clock
		end,
		cameraPosition = function()
			return Vector3.zero
		end,
	})

	local model = Instance.new("Model")
	model.Name = "Ren"
	model:SetAttribute("Rig", "PlayerR15")
	model:SetAttribute("Drawn", false)
	model:SetAttribute("State", "Idle")
	local parts = {}
	local function part(name)
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
	local weapon = nil
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and item.Name == WeaponModels.motorName then
			weapon = item
		end
	end

	local record =
		{ id = 2, model = model, kind = "Player", rig = "PlayerR15", weaponId = "TrialistSword", name = "Ren" }
	local calls = {}
	local warningsBefore = #Harness.warnings()
	local function stamped(moduleName)
		return setmetatable({}, {
			__index = function(_, key)
				return function(...)
					table.insert(calls, { module = moduleName, fn = key, args = { ... }, at = clock })
				end
			end,
		})
	end
	Replication.bind({
		net = { on = function() end },
		entities = {
			get = function(id)
				return if id == 2 then record else nil
			end,
		},
		localId = function()
			return if isLocal then 2 else 1
		end,
		locomotion = {
			attach = function(animator, rig, options)
				local withoutIK = table.clone(options or {})
				withoutIK.footIK = false
				return Locomotion.attach(animator, rig, withoutIK)
			end,
			destroy = Locomotion.destroy,
			humanoidTracker = Locomotion.humanoidTracker,
		},
		choreo = Choreo,
		clipLibrary = ClipLibrary,
		trails = recorder("trails", calls),
		smear = recorder("smear", calls),
		shatter = recorder("shatter", calls),
		sparks = recorder("sparks", calls),
		telegraphs = recorder("telegraphs", calls),
		outline = recorder("outline", calls),
		switchRing = recorder("switchRing", calls),
		digits = recorder("digits", calls),
		hud = recorder("hud", calls),
		systemLine = recorder("systemLine", calls),
		sfx = recorder("sfx", calls),
		impact = stamped("impact"),
		camera = recorder("camera", calls),
		weaponCategory = function()
			return "OneHandedSword"
		end,
		trailToken = function()
			return "TrailCyanWhite"
		end,
		positionOf = function()
			return Vector3.zero
		end,
		schedule = function() end,
		now = function()
			return clock
		end,
	})
	Replication.watch(record)
	local animator = Choreo.get(model)
	local drawId = ChoreoData.locomotion.clipPrefix .. ChoreoData.sheath.clips.draw
	local live = {
		record = record,
		model = model,
		animator = animator,
		drawSteps = 0, -- steps that showed a Draw clip
		firstDraw = nil :: number?, -- the step that first showed one
		steps = 0,
	}
	-- One 60 Hz frame; records whether a Draw clip is on the rig.
	function live.step()
		clock += 1 / 60
		live.steps += 1
		animator:step(1 / 60)
		for _, handle in animator.mixer:handles() do
			if handle.clipId == drawId then
				live.drawSteps += 1
				live.firstDraw = live.firstDraw or live.steps
				break
			end
		end
	end
	-- Time passing with no frame rendered (a render stall): the clock moves, nothing steps.
	function live.advance(seconds: number)
		clock += seconds
	end
	function live.inHand(): boolean
		return weapon ~= nil and weapon.Part0 == parts.RightHand
	end
	function live.now(): number
		return clock
	end
	-- The calls the recorders took for `module.fn`, in order.
	function live.calls(moduleName: string, fn: string): { any }
		local found = {}
		for _, call in calls do
			if call.module == moduleName and call.fn == fn then
				table.insert(found, call)
			end
		end
		return found
	end
	-- Signal handler errors warned since this rig was built (a throw inside Replication's handlers).
	function live.handlerErrors(): { string }
		local found = {}
		local warnings = Harness.warnings()
		for index = warningsBefore + 1, #warnings do
			if warnings[index]:find("[Signal] handler error", 1, true) then
				table.insert(found, warnings[index])
			end
		end
		return found
	end
	function live.release()
		Replication.unwatch(record)
		Choreo.release(model)
		Choreo.configure({
			now = function()
				return 0
			end,
		})
	end
	return live
end

describe("a remote fighter's struck stance comes down like the local one's (D-422)", function()
	for _, art in { "SharpNail", "Vertical", "Horizontal" } do
		for _, direction in { "Front", "Back", "none" } do
			it(
				("%s, staggered %s: the Art fades over struckStanceBlendOut and lights no trail"):format(
					art,
					if direction == "none" then "with no direction" else "from the " .. direction
				),
				function()
					local live = liveRemote()
					live.model:SetAttribute("Drawn", true)
					for _ = 1, 30 do
						live.step()
					end
					local clipId = ChoreoData.locomotion.clipPrefix .. art
					Replication.dispatch("ActionStarted", {
						entityId = 2,
						clipId = clipId,
						serverTime = live.now() - 0.05,
						facing = { 0, 0, -1 },
					})
					-- Into the stance: past the ActivationHold (0.15), short of the first damage frame.
					for _ = 1, 8 do
						live.step()
					end
					local lightsBefore = 0
					for _, call in live.calls("trails", "setActive") do
						lightsBefore += if call.args[2] == true then 1 else 0
					end
					Replication.dispatch("StateChanged", {
						entityId = 2,
						state = "Stagger",
						duration = Combat.staggerDuration,
						direction = if direction == "none" then nil else direction,
					})
					live.step()
					local art: any = nil
					for _, handle in live.animator.mixer:handles() do
						if handle.clipId == clipId then
							art = handle
						end
					end
					local ok, err = pcall(function()
						expect(art).never.toBeNil()
						expect(art.stopping).toBe(true)
						expect(art.blendOut).toBeCloseTo(Combat.struckStanceBlendOut, 1e-6)
						for _ = 1, math.ceil(Combat.struckStanceBlendOut * 60) + 2 do
							live.step()
						end
						local lights = 0
						for _, call in live.calls("trails", "setActive") do
							lights += if call.args[2] == true then 1 else 0
						end
						expect(lights - lightsBefore).toBe(0)
					end)
					live.release()
					if not ok then
						error(err, 0)
					end
				end
			)
		end
	end

	-- The fade holds the pose it was let go in (D-294 on the local rig): the Art's clock stands from
	-- the word on, so the fade crosses none of its keys. With the clock running, a remote stance
	-- staggered from the Front swung on into its cut under the fade at 277 (Horizontal) to 377
	-- (Sharp Nail) studs a second on frames 7 to 11 after the word; the local stance comes down
	-- under combat.luau struckStanceTipSpeed (StanceLetGo.spec). A directional flinch rides the
	-- Additive layer, so past its hit frame the tip is the fade's alone; the Stagger clip with no
	-- direction is the blow's own recoil (its 0.15 s blend in), not the fade's.
	for _, art in { "SharpNail", "Vertical", "Horizontal" } do
		for _, direction in { "Front", "Back", "Left", "Right", "none" } do
			it(
				("%s, staggered %s: the Art stands where it was let go%s"):format(
					art,
					if direction == "none" then "with no direction" else "from the " .. direction,
					if direction == "none" then "" else " and the tip stays under struckStanceTipSpeed"
				),
				function()
					local live = liveRemote()
					live.model:SetAttribute("Drawn", true)
					for _ = 1, 30 do
						live.step()
					end
					local clipId = ChoreoData.locomotion.clipPrefix .. art
					Replication.dispatch("ActionStarted", {
						entityId = 2,
						clipId = clipId,
						serverTime = live.now() - 0.05,
						facing = { 0, 0, -1 },
					})
					for _ = 1, 8 do
						live.step()
					end
					local handle: any = nil
					for _, candidate in live.animator.mixer:handles() do
						if candidate.clipId == clipId then
							handle = candidate
						end
					end
					local chain = BladeContact.chain(live.model :: any) :: any
					local _, last = BladeContact.blade(chain, BladeContact.read(chain))
					Replication.dispatch("StateChanged", {
						entityId = 2,
						state = "Stagger",
						duration = Combat.staggerDuration,
						direction = if direction == "none" then nil else direction,
					})
					local letGoAt = handle.time
					local fastest, fastestAt, moved = 0, 0, 0
					for frame = 1, math.ceil(Combat.struckStanceBlendOut * 60) + 2 do
						live.step()
						if not handle.done then
							moved = math.max(moved, math.abs(handle.time - letGoAt))
						end
						local _, tip = BladeContact.blade(chain, BladeContact.read(chain))
						local speed = (tip - last).Magnitude * 60
						last = tip
						-- The flinch's own hit frame may move fast (D-340).
						if frame > 1 and speed > fastest then
							fastest, fastestAt = speed, frame
						end
					end
					live.release()
					local problems = {}
					if moved > 1e-9 then
						table.insert(problems, ("the Art's clock ran %.3f s past the let-go"):format(moved))
					end
					if direction ~= "none" and fastest > Combat.struckStanceTipSpeed then
						table.insert(
							problems,
							("the tip moved %.0f studs/s on frame %d after the word (bar %g)"):format(
								fastest,
								fastestAt,
								Combat.struckStanceTipSpeed
							)
						)
					end
					expect(table.concat(problems, "; ")).toBe("")
				end
			)
		end
	end

	it("an Art past its first damage frame stops at the locomotion blend on a directional flinch", function()
		local live = liveRemote()
		live.model:SetAttribute("Drawn", true)
		for _ = 1, 30 do
			live.step()
		end
		local clipId = ChoreoData.locomotion.clipPrefix .. "SharpNail"
		Replication.dispatch("ActionStarted", {
			entityId = 2,
			clipId = clipId,
			serverTime = live.now() - 0.05,
			facing = { 0, 0, -1 },
		})
		local art: any = nil
		for _, handle in live.animator.mixer:handles() do
			if handle.clipId == clipId then
				art = handle
			end
		end
		local first = math.huge
		for _, event in art.clip.events do
			if event.kind == "HitWindowOpen" then
				first = math.min(first, event.time)
			end
		end
		while art.time <= first + 1 / 60 do
			live.step()
		end
		Replication.dispatch("StateChanged", {
			entityId = 2,
			state = "Stagger",
			duration = Combat.staggerDuration,
			direction = "Front",
		})
		local ok, err = pcall(function()
			expect(art.stopping).toBe(true)
			expect(art.blendOut).toBeCloseTo(Combat.locomotionBlendOut, 1e-6)
		end)
		live.release()
		if not ok then
			error(err, 0)
		end
	end)
end)

local Dev = Harness.load("src/shared/data/dev")
local WeaponModels = Harness.load("src/shared/data/weaponModels")
local Audit = Dev.review.audit

-- Each body part's frame in the root's (the motors solved from the root out), as ClipAudit reads a
-- pop: a part turning in the root part's frame.
local function partFrames(model: Model): { [string]: CFrame }
	local motors: { [string]: Motor6D } = {}
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") and item.Name ~= WeaponModels.motorName and item.Part1 ~= nil then
			motors[(item.Part1 :: BasePart).Name] = item
		end
	end
	local frames: { [string]: CFrame } = { HumanoidRootPart = CFrame.identity }
	local function solve(name: string): CFrame
		local known = frames[name]
		if known ~= nil then
			return known
		end
		local motor = motors[name]
		local parent = solve((motor.Part0 :: BasePart).Name)
		local frame = parent * motor.C0 * motor.Transform * motor.C1:Inverse()
		frames[name] = frame
		return frame
	end
	for name in motors do
		solve(name)
	end
	return frames
end

-- The most any part turned between two solved poses (degrees), and which part.
local function turned(before: { [string]: CFrame }, after: { [string]: CFrame }): (number, string)
	local most, which = 0, ""
	for name, frame in after do
		local was = before[name]
		if was ~= nil then
			local _, angle = was:ToObjectSpace(frame):ToAxisAngle()
			local degrees = math.deg(math.abs(angle))
			if degrees > most then
				most, which = degrees, name
			end
		end
	end
	return most, which
end

-- A remote fighter's cancels take the body as the local fighter's do (D-408 on other screens,
-- D-409): Replication's ActionStarted for a player hands over from the action it cut (Mixer
-- handOver, the cut clip in `cancels`): the cut clip holds its pose and the new one takes the
-- body within review.audit.cancel.snapFrames, and from the frame after them no part turns more
-- than review.audit.popDegrees in a 60 Hz frame. Played without the hand-over, the cut clip ran
-- on under its fade and the new one came in over its own blend: an Art out of Basic1 turned the
-- right arm 24 and 31 degrees on the 3rd and 4th frames, Sharp Nail out of Basic3 25 and 27.
describe("a remote fighter's cancel takes the body as a snap (D-408, D-409)", function()
	local CANCELS = {
		{ clip = "Horizontal", over = "Basic1", gap = 0.1 },
		{ clip = "Vertical", over = "Basic2", gap = 0.1 },
		{ clip = "SharpNail", over = "Basic3", gap = 0.1 },
		{ clip = "DodgeLeft", over = "Basic1", gap = 0.1 },
		{ clip = "DodgeBack", over = "Basic1", gap = 0.1 },
		{ clip = "DodgeLeft", over = "RisingArc", gap = 0.2 },
	}
	for _, case in CANCELS do
		it(
			("%s cutting %s %.2f s in holds the cut clip and pops nothing after the snap"):format(
				case.clip,
				case.over,
				case.gap
			),
			function()
				local live = liveRemote()
				live.model:SetAttribute("Drawn", true)
				for _ = 1, 30 do
					live.step()
				end
				local prefix = ChoreoData.locomotion.clipPrefix
				Replication.dispatch("ActionStarted", {
					entityId = 2,
					clipId = prefix .. case.over,
					serverTime = live.now(),
					facing = { 0, 0, -1 },
				})
				for _ = 1, math.round(case.gap * 60) do
					live.step()
				end
				local cut: any = nil
				for _, handle in live.animator.mixer:handles() do
					if handle.clipId == prefix .. case.over and not handle.stopping then
						cut = handle
					end
				end
				local lightsOut = #live.calls("trails", "activationLight")
				local before = partFrames(live.model)
				Replication.dispatch("ActionStarted", {
					entityId = 2,
					clipId = prefix .. case.clip,
					serverTime = live.now(),
					facing = { 0, 0, -1 },
				})
				local cutAt = cut.time
				local problems = {}
				for frame = 1, 20 do
					live.step()
					local after = partFrames(live.model)
					local degrees, part = turned(before, after)
					before = after
					if frame > Audit.cancel.snapFrames and degrees > Audit.popDegrees then
						table.insert(problems, ("frame %d: %s turned %.1f degrees"):format(frame, part, degrees))
					end
					if not cut.done and math.abs(cut.time - cutAt) > 1e-9 then
						table.insert(
							problems,
							("frame %d: the cut %s ran on to %.3f s"):format(frame, case.over, cut.time)
						)
					end
				end
				-- An Art cut in its stance puts its blade light out as it goes (the cut clip's clock
				-- stands, so no HitWindowOpen of its own does).
				local lights = live.calls("trails", "activationLight")
				if case.over == "RisingArc" then
					local out = false
					for index = lightsOut + 1, #lights do
						out = out or lights[index].args[2] == false
					end
					if not out then
						table.insert(problems, "the cut Art's light stayed on")
					end
				end
				live.release()
				expect(table.concat(problems, "; ")).toBe("")
			end
		)
	end
end)

-- A cut takes its trail and smear with it (D-410). A cancel holds the clip it cuts (D-408; on
-- other screens D-409), so that clip's own HitWindowClose, TrailOff and SmearOff never came: a
-- basic a dodge cut between its SmearOn and SmearOff kept its trail lit and its blade stretched 90
-- frames on (for as long as the rig lived), the local fighter's and a remote one's alike; one a
-- later basic cut kept its trail through the new swing's anticipation (15 frames). The local
-- fighter's cancel is played as CharacterController plays it (handOver, the cut clip in
-- `cancels`), a remote one's from its ActionStarted.
describe("a cut takes its trail and smear with it (D-410)", function()
	local CUTS = {
		{ clip = "DodgeLeft", over = "Basic1", gap = 0.125 },
		{ clip = "Horizontal", over = "Basic1", gap = 0.125, lights = "Art" },
		{ clip = "Basic2", over = "Basic1", gap = 0.15, lights = "Basic" },
	}
	for _, mode in { "local", "remote" } do
		for _, case in CUTS do
			it(("%s: %s cutting %s %.3f s in"):format(mode, case.clip, case.over, case.gap), function()
				local live = liveRemote({ isLocal = mode == "local" })
				live.model:SetAttribute("Drawn", true)
				for _ = 1, 30 do
					live.step()
				end
				local prefix = ChoreoData.locomotion.clipPrefix
				local function start(clipId: string, cut: any?): any
					if mode == "local" then
						return live.animator:play(
							prefix .. clipId,
							{ handOver = true, cancels = if cut ~= nil then { cut } else nil }
						)
					end
					Replication.dispatch("ActionStarted", {
						entityId = 2,
						clipId = prefix .. clipId,
						serverTime = live.now(),
						facing = { 0, 0, -1 },
					})
					return nil
				end
				start(case.over)
				local cut: any = nil
				for _, handle in live.animator.mixer:handles() do
					if handle.clipId == prefix .. case.over and not handle.stopping then
						cut = handle
					end
				end
				while cut.time < case.gap do
					live.step()
				end
				-- What the trail and the smear show, from the recorders' calls in order.
				local kinds: { [string]: boolean } = {}
				local stretched = false
				local seenKinds, seenSmears = 0, 0
				local function shown(): string
					local active = live.calls("trails", "setActive")
					for index = seenKinds + 1, #active do
						kinds[active[index].args[3]] = active[index].args[2] == true
					end
					seenKinds = #active
					local smears = live.calls("smear", "apply")
					for index = seenSmears + 1, #smears do
						stretched = smears[index].args[2] == true
					end
					seenSmears = #smears
					local on = {}
					for kind, lit in kinds do
						if lit then
							table.insert(on, kind)
						end
					end
					table.sort(on)
					if stretched then
						table.insert(on, "stretched blade")
					end
					return table.concat(on, "+")
				end
				local before = shown()
				start(case.clip, cut)
				local problems = {}
				local lit = false
				for frame = 1, 90 do
					live.step()
					local now = shown()
					if frame == 1 and now ~= "" then
						table.insert(
							problems,
							("frame 1 after the cut (%s at the cut): %s still on"):format(before, now)
						)
					end
					if case.lights ~= nil and kinds[case.lights] then
						lit = true
					end
				end
				local after = shown()
				if after ~= "" then
					table.insert(problems, ("90 frames after the cut: %s still on"):format(after))
				end
				if case.lights ~= nil and not lit then
					table.insert(problems, ("%s's own %s trail never lit"):format(case.clip, case.lights))
				end
				live.release()
				expect(table.concat(problems, "; ")).toBe("")
			end)
		end
	end
end)
