--!strict
--[[
	ContactPredictor (issue 4): the frame the local blade first touches an enemy's body.

	The player is the hit matrix's body (the engine-style R15, AnimationConstraint joints, the
	WeaponBuilder sword with TrailStart and TrailEnd); a frame poses it as Choreo does (each joint's
	Transform from the clip, the root carried by the clip's root motion) at 60 fps. Enemies are
	RigBuilder rigs placed as the hit matrix places them (dev.luau hitMatrix.setups). Each frame
	the predictor sweeps the blade from the frame before.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Combat = Harness.load("src/shared/data/combat")
local Dev = Harness.load("src/shared/data/dev")
local Enemies = Harness.load("src/shared/data/enemies")
local Weapons = Harness.load("src/shared/data/weapons")
local Arts = Harness.load("src/shared/data/arts")
local Rigs = Harness.load("src/shared/data/rigs")
local World = Harness.load("src/shared/data/world")
local Playground = Harness.load("src/shared/data/playground")
local ClipSampler = Harness.load("src/shared/choreo/ClipSampler")
local Pose = Harness.load("src/shared/choreo/Pose")
local Joints = Harness.load("src/shared/choreo/Joints")
local BladeContact = Harness.load("src/shared/choreo/BladeContact")
local RigBuilder = Harness.load("src/server/world/RigBuilder")
local PlaygroundLayout = Harness.load("src/server/world/PlaygroundLayout")
local ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers")
local ContactPredictor = Harness.load("src/client/controllers/ContactPredictor")

local FRAME = 1 / 60
local root = Harness.repoRoot()

local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
local avatar = HitMatrix.standing(Harness)
local WEAPON = Weapons.byId(Playground.loadout.weapon)

local function setupOf(id: string): any
	for _, setup in Dev.hitMatrix.setups do
		if setup.id == id then
			return setup
		end
	end
	error("no setup " .. id)
end

-- An enemy's rig in its rest pose `distance` in front of the player (HitMatrix's placeEnemy).
local function placeEnemy(setupId: string, distance: number): (any, any)
	local setup = setupOf(setupId)
	local def = Enemies.byId(setup.enemy)
	local rig = Rigs[def.skin]
	local model = RigBuilder.build(def.skin)
	local height = PlaygroundLayout.rootHeight(rig.hipHeight, model.PrimaryPart.Size.Y, World.spawn.groundEpsilon)
	local frame = avatar.base
		* CFrame.new(0, height - avatar.rootHeight, -distance)
		* CFrame.Angles(0, math.pi + math.rad(setup.yaw), 0)
	for name, solved in Pose.solve(model, frame, {}) do
		local part = model:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.CFrame = solved
		end
	end
	return model, def
end

local function record(id: number, model: any, def: any, overrides: { [string]: any }?): any
	local entry: { [string]: any } = {
		id = id,
		model = model,
		kind = "Enemy",
		state = "Idle",
		defId = def.id,
		hp = def.hp,
		maxHp = def.hp,
		elite = false,
	}
	for key, value in overrides or {} do
		entry[key] = value
	end
	return entry
end

-- Poses the avatar at a clip time as Choreo and the controller do: the joints' Transforms from the
-- clip, the root carried from its start by the clip's root motion.
local function poseAt(clip: any, time: number)
	local offsets = ClipSampler.sample(clip, time)
	for _, joint in Joints.list(avatar.model) do
		local offset = offsets[joint.Name]
		joint.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
	end
	local start = ClipSampler.rootMotionAt(clip, 0)
	local now = ClipSampler.rootMotionAt(clip, time)
	avatar.root.CFrame = avatar.base * CFrame.new(now[1] - start[1], now[2] - start[2], now[3] - start[3])
end

type Attack = { name: string, clip: any, artId: string?, finalHit: boolean, multiplier: number }

local function attack(name: string): Attack
	local clip = Harness.load("src/shared/clips/player/OneHandedSword/" .. name)
	if name:sub(1, 5) == "Basic" then
		local index = tonumber(name:sub(6)) :: number
		return {
			name = name,
			clip = clip,
			artId = nil,
			finalHit = index >= Combat.basicChainLength,
			multiplier = Combat.basicAttackMultiplier,
		}
	end
	local art = Arts.byId("OneHandedSword." .. name)
	return { name = name, clip = clip, artId = art.id, finalHit = true, multiplier = art.multiplier }
end

local ATTACKS = { "Basic1", "Basic2", "Basic3", "Horizontal", "Vertical", "RisingArc", "SharpNail" }

-- Plays a swing at 60 fps from `phase` of a frame into the clip; returns each contact with the
-- clip time of the frame it came on.
local function swing(
	which: Attack,
	targets: { any },
	options: { phase: number?, confirmed: any?, freezeAt: number?, freezeFrames: number? }?
): { { contact: any, time: number, frame: number } }
	local opts = options or {}
	local predictor = ContactPredictor.new({
		targets = function(): { any }
			return targets
		end,
		confirmed = opts.confirmed,
	})
	local ok = predictor:begin({
		model = avatar.model,
		clip = which.clip,
		artId = which.artId,
		finalHit = which.finalHit,
		multiplier = which.multiplier,
		weaponAttack = WEAPON.attack,
	})
	assert(ok, "begin refused " .. which.name)
	local found = {}
	local time = 0
	local frame = 0
	local frozen = 0
	local didFreeze = false
	poseAt(which.clip, 0)
	predictor:step(0)
	time = (opts.phase or 0) * FRAME
	while time <= which.clip.duration + FRAME do
		frame += 1
		local t = math.min(time, which.clip.duration)
		poseAt(which.clip, t)
		for _, contact in predictor:step(t) do
			table.insert(found, { contact = contact, time = t, frame = frame })
		end
		if opts.freezeAt ~= nil and not didFreeze and t >= opts.freezeAt then
			didFreeze = true
			frozen = opts.freezeFrames or 0
		end
		if frozen > 0 then
			frozen -= 1
		else
			time += FRAME
		end
	end
	predictor:stop()
	return found
end

-- The first clip time (at TOUCH_STEP) the clip's exact blade touches any of the parts, inside window w.
local TOUCH_STEP = 1 / 480
local function firstTouch(which: Attack, parts: { any }, window: any): number?
	local chain = BladeContact.chain(avatar.model)
	local step = TOUCH_STEP
	local t = window.open
	while t <= window.close + 1e-9 do
		poseAt(which.clip, t)
		local guard, tip = BladeContact.blade(chain :: any, BladeContact.read(chain :: any))
		if BladeContact.touch(guard, tip, parts, Combat.hitSphereRadius) then
			return t
		end
		t += step
	end
	return nil
end

local function bodyParts(model: any): { any }
	local list = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and BladeContact.queryable(part) then
			table.insert(list, part)
		end
	end
	return list
end

describe("ContactPredictor on the real rigs", function()
	it("predicts every window of every attack at real-fight range, on the frame the blade gets there", function()
		local cases = { { "BoarSide", 3.5 }, { "Kobold", 3.5 }, { "BoarFacing", 7 } }
		for _, case in cases do
			local enemy, def = placeEnemy(case[1], case[2])
			local parts = bodyParts(enemy)
			for _, name in ATTACKS do
				local which = attack(name)
				local windows = ClipSampler.hitWindows(which.clip)
				local snaps = ReviewMarkers.strikeSnaps(which.clip)
				local touches = {}
				for index, window in windows do
					touches[index] = firstTouch(which, parts, window) or false
				end
				for _, phase in { 0, 0.5 } do
					local found = swing(which, { record(5, enemy, def) }, { phase = phase })
					for index, window in windows do
						local touch: number? = touches[index] or nil
						local mine = nil
						for _, entry in found do
							if entry.contact.windowIndex == index then
								expect(mine == nil).toBe(true) -- once per window
								mine = entry
							end
						end
						if touch == nil then
							-- The true blade never reaches this enemy in this window: no prediction.
							expect(mine).toBe(nil)
							continue
						end
						if mine == nil then
							error(
								("%s %s@%s window %d phase %.1f: touched at %.4f, never predicted"):format(
									name,
									case[1],
									tostring(case[2]),
									index,
									phase,
									touch :: number
								)
							)
						end
						-- The first rendered frame at or after the true first touch (to the 480 Hz
						-- search's step): never a frame early, never a frame late, never before the
						-- window and never after the strike's snap has ended.
						expect(mine.contact.targetId).toBe(5)
						expect(mine.time >= window.open - 1e-9).toBe(true)
						local firstFrameAfter = touch :: number
						if
							mine.time < firstFrameAfter - TOUCH_STEP - 1e-9
							or mine.time > firstFrameAfter + FRAME + 1e-6
						then
							error(
								("%s %s window %d: contact at %.4f, the blade got there at %.4f"):format(
									name,
									case[1],
									index,
									mine.time,
									firstFrameAfter
								)
							)
						end
						local snap = snaps[index]
						expect(mine.time <= snap.finish + FRAME + 1e-9).toBe(true)
					end
				end
			end
		end
	end)

	it("names the tier the server gives: Final on an Art's last window and the chain's third swing", function()
		local enemy, def = placeEnemy("BoarSide", 3.5)
		for _, name in ATTACKS do
			local which = attack(name)
			local windows = ClipSampler.hitWindows(which.clip)
			for _, entry in swing(which, { record(5, enemy, def) }) do
				local isLast = entry.contact.windowIndex == #windows
				local expected = if which.finalHit and isLast then "Final" else "Normal"
				expect(entry.contact.tier).toBe(expected)
				expect(entry.contact.killed).toBe(false)
				expect(entry.contact.artId).toBe(which.artId)
			end
		end
	end)

	it("never predicts its own rig, a player, a dead enemy; a confirmed hit is not predicted again", function()
		local enemy, def = placeEnemy("BoarSide", 3.5)
		local twin = placeEnemy("BoarSide", 3.5)
		local sharp = attack("SharpNail")
		local own = { id = 1, model = avatar.model, kind = "Player", state = "Art", hp = 300, maxHp = 300 }
		local other = { id = 2, model = twin, kind = "Player", state = "Idle", hp = 300, maxHp = 300 }
		local dead = record(3, twin, def, { state = "Dead" })
		expect(#swing(sharp, { own, other, dead })).toBe(0)
		-- The server confirmed window 2 before the blade got there.
		local found = swing(sharp, { record(5, enemy, def) }, {
			confirmed = function(targetId: number, windowIndex: number, artId: string?): boolean
				return targetId == 5 and windowIndex == 2 and artId == sharp.artId
			end,
		})
		local windows = {}
		for _, entry in found do
			table.insert(windows, entry.contact.windowIndex)
		end
		expect(table.concat(windows, ",")).toBe("1,3")
	end)

	it("touches at most combat.maxTargetsPerWindow fighters in one window", function()
		local def = Enemies.byId("FrenzyBoar")
		local crowd = {}
		for index = 1, Combat.maxTargetsPerWindow + 3 do
			local model = placeEnemy("BoarSide", 3.5)
			table.insert(crowd, record(10 + index, model, def))
		end
		local found = swing(attack("Horizontal"), crowd)
		expect(#found).toBe(Combat.maxTargetsPerWindow)
	end)

	it("sweeps nothing while the clip stands still (a hit-stop) and goes on from where it stood", function()
		local enemy, def = placeEnemy("BoarSide", 3.5)
		local sharp = attack("SharpNail")
		local windows = ClipSampler.hitWindows(sharp.clip)
		-- Freeze 10 frames right after window 1 opens: the contacts still come once each.
		local found = swing(sharp, { record(5, enemy, def) }, { freezeAt = windows[1].open, freezeFrames = 10 })
		local seen = {}
		for _, entry in found do
			expect(seen[entry.contact.windowIndex]).toBe(nil)
			seen[entry.contact.windowIndex] = true
		end
		expect(#found).toBe(#windows)
	end)

	it("follows a snap between frames: a target only the arc between two frames passes is touched", function()
		local sharp = attack("SharpNail")
		local window = ClipSampler.hitWindows(sharp.clip)[1]
		local chain = BladeContact.chain(avatar.model) :: any
		-- The two frames of the snap the blade moves farthest between.
		local before, after = window.open, window.open + FRAME
		poseAt(sharp.clip, before)
		local from = BladeContact.copy(BladeContact.read(chain))
		poseAt(sharp.clip, after)
		local to = BladeContact.read(chain)
		local _, tipFrom = BladeContact.blade(chain, from)
		local _, tipTo = BladeContact.blade(chain, to)
		local _, tipMiddle = BladeContact.blade(chain, to, from, 0.5)
		expect((tipTo - tipFrom).Magnitude > 3 * Combat.hitSphereRadius).toBe(true)
		-- A small target just past the middle of the tip's path, out of reach of both frames' blades.
		local model = Instance.new("Model")
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		local outward = (tipMiddle - (tipFrom + tipTo) / 2).Unit
		part.CFrame = CFrame.new(tipMiddle + outward * 0.3)
		part.Parent = model
		model.PrimaryPart = part
		expect((BladeContact.touch(BladeContact.blade(chain, from), tipFrom, { part }, Combat.hitSphereRadius))).toBe(
			false
		)
		local guardTo = BladeContact.blade(chain, to)
		expect((BladeContact.touch(guardTo, tipTo, { part }, Combat.hitSphereRadius))).toBe(false)
		local predictor = ContactPredictor.new({
			targets = function(): { any }
				return { { id = 9, model = model, kind = "Enemy", state = "Idle", hp = 50, maxHp = 50, defId = "" } }
			end,
		})
		predictor:begin({
			model = avatar.model,
			clip = sharp.clip,
			artId = sharp.artId,
			finalHit = true,
			multiplier = sharp.multiplier,
			weaponAttack = WEAPON.attack,
		})
		poseAt(sharp.clip, before)
		expect(#predictor:step(before)).toBe(0)
		poseAt(sharp.clip, after)
		local contacts = predictor:step(after)
		expect(#contacts).toBe(1)
		expect(contacts[1].targetId).toBe(9)
	end)

	it("refuses a rig without a blade or a clip without a window, and stop ends the swing", function()
		local predictor = ContactPredictor.new({
			targets = function(): { any }
				return {}
			end,
		})
		local bare = Instance.new("Model")
		local part = Instance.new("Part")
		part.Parent = bare
		bare.PrimaryPart = part
		local sharp = attack("SharpNail")
		local swingOf = function(model: any, clip: any): any
			return {
				model = model,
				clip = clip,
				artId = nil,
				finalHit = false,
				multiplier = 1,
				weaponAttack = 1,
			}
		end
		expect(predictor:begin(swingOf(bare, sharp.clip))).toBe(false)
		expect(predictor:active()).toBe(false)
		local idle = Harness.load("src/shared/clips/player/OneHandedSword/Idle")
		expect(predictor:begin(swingOf(avatar.model, idle))).toBe(false)
		expect(predictor:begin(swingOf(avatar.model, sharp.clip))).toBe(true)
		expect(predictor:active()).toBe(true)
		predictor:stop()
		expect(predictor:active()).toBe(false)
		expect(#predictor:step(0.4)).toBe(0)
	end)
end)

describe("ContactPredictor kill rule", function()
	local boar = Enemies.byId("FrenzyBoar")
	local scaled = Enemies.scaled(boar)
	local function least(multiplier: number, elite: boolean?): number
		local def = if elite then Enemies.variant(scaled, "Elite") else scaled
		return math.max(Combat.minimumDamage, math.floor(WEAPON.attack * multiplier - def.defense + 0.5))
	end
	local margin = 0.5 + scaled.hp * Combat.outOfCombatRegenPerSecond * Combat.contact.killRegenSeconds

	it("takes the section 6 formula's floor: no STR, no crit, the enemy's scaled defense", function()
		local art = Arts.byId("OneHandedSword.SharpNail")
		local entry = record(5, nil, boar, { hp = scaled.hp, maxHp = scaled.hp })
		expect(ContactPredictor.leastDamage(entry, WEAPON.attack, art.multiplier)).toBe(least(art.multiplier))
		local elite = record(5, nil, boar, { elite = true })
		expect(ContactPredictor.leastDamage(elite, WEAPON.attack, art.multiplier)).toBe(least(art.multiplier, true))
		expect(ContactPredictor.leastDamage(entry, 0, 1)).toBe(Combat.minimumDamage)
	end)

	it("predicts a kill only when the least damage reaches HP plus rounding and regen", function()
		local art = Arts.byId("OneHandedSword.SharpNail")
		local damage = least(art.multiplier)
		local sure = math.floor(damage - margin)
		expect(sure > 0).toBe(true)
		local function kills(hp: number, overrides: { [string]: any }?): boolean
			local values: { [string]: any } = { hp = hp, maxHp = scaled.hp }
			for key, value in overrides or {} do
				values[key] = value
			end
			return ContactPredictor.provesKill(record(5, nil, boar, values), WEAPON.attack, art.multiplier)
		end
		expect(kills(sure)).toBe(true)
		expect(kills(1)).toBe(true)
		-- Exactly the damage, or within the margin above it: the server may see more HP.
		expect(kills(damage)).toBe(false)
		expect(kills(damage - margin + 0.01)).toBe(false)
		-- Nothing left to take, an unknown def, a player, a missing HP: no prediction.
		expect(kills(0)).toBe(false)
		expect(kills(1, { defId = "NoSuchEnemy" })).toBe(false)
		expect(kills(1, { kind = "Player" })).toBe(false)
		expect(kills(1, { maxHp = "x" })).toBe(false)
	end)

	it("a predicted kill is Kill tier and the swing never hits that enemy again", function()
		local enemy = placeEnemy("BoarSide", 3.5)
		local sharp = attack("SharpNail")
		local found = swing(sharp, { record(5, enemy, boar, { hp = 1, maxHp = scaled.hp }) })
		expect(#found).toBe(1)
		expect(found[1].contact.windowIndex).toBe(1)
		expect(found[1].contact.tier).toBe("Kill")
		expect(found[1].contact.killed).toBe(true)
	end)

	it("tierFor: Kill over everything, Final only on the final hit's last window", function()
		expect(ContactPredictor.tierFor(1, 3, true, false)).toBe("Normal")
		expect(ContactPredictor.tierFor(3, 3, true, false)).toBe("Final")
		expect(ContactPredictor.tierFor(3, 3, false, false)).toBe("Normal")
		expect(ContactPredictor.tierFor(1, 1, false, true)).toBe("Kill")
		expect(ContactPredictor.tierFor(1, 3, true, true)).toBe("Kill")
	end)
end)

describe("ContactPredictor swing numbers and drawn-away parts (items 4, D-171)", function()
	-- One swing of Sharp Nail at a boar 3.5 studs out, with `deps` beyond the targets.
	local function sweep(number: number?, deps: { [string]: any }): { any }
		local enemy, def = placeEnemy("BoarSide", 3.5)
		local sharp = attack("SharpNail")
		local target = record(5, enemy, def)
		local options: { [string]: any } = {
			targets = function(): { any }
				return { target }
			end,
		}
		for key, value in deps do
			options[key] = value
		end
		local predictor = ContactPredictor.new(options :: any)
		assert(predictor:begin({
			model = avatar.model,
			clip = sharp.clip,
			artId = sharp.artId,
			finalHit = true,
			multiplier = sharp.multiplier,
			weaponAttack = WEAPON.attack,
			swing = number,
		}))
		local found = {}
		local time = 0
		poseAt(sharp.clip, 0)
		predictor:step(0)
		while time <= sharp.clip.duration do
			time += FRAME
			poseAt(sharp.clip, math.min(time, sharp.clip.duration))
			for _, contact in predictor:step(math.min(time, sharp.clip.duration)) do
				table.insert(found, contact)
			end
		end
		predictor:stop()
		return found
	end

	it("every contact carries the swing's number, and the confirmed check is asked with it", function()
		local asked: { any } = {}
		local found = sweep(9, {
			confirmed = function(_targetId: number, _windowIndex: number, _artId: string?, swing: number?): boolean
				table.insert(asked, swing)
				return false
			end,
		})
		expect(#found > 0).toBe(true)
		for _, contact in found do
			expect(contact.swing).toBe(9)
		end
		expect(#asked).toBe(#found)
		for _, swing in asked do
			expect(swing).toBe(9)
		end
		-- A swing without one predicts as before.
		for _, contact in sweep(nil, {}) do
			expect(contact.swing).toBe(nil)
		end
	end)

	it("skips a part the body is drawn away from; the rest of the body is still struck", function()
		local plain = sweep(nil, {})
		local rootOnly = sweep(nil, {
			hidden = function(part: any): boolean
				return part.Name == "HumanoidRootPart"
			end,
		})
		expect(#rootOnly).toBe(#plain)
		local none = sweep(nil, {
			hidden = function(): boolean
				return true
			end,
		})
		expect(#none).toBe(0)
	end)

	it("walks the tracker's frozen live list as it is, the same contacts as a list of its own (item 5)", function()
		local plain = sweep(nil, {})
		local enemy, def = placeEnemy("BoarSide", 3.5)
		local frozen = table.freeze({ record(5, enemy, def) })
		local walked = sweep(nil, {
			targets = function(): { any }
				return frozen
			end,
		})
		expect(#walked).toBe(#plain)
		expect(#frozen).toBe(1)
	end)
end)
