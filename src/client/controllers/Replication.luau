--!strict
--[[
	Replication: every server-to-client remote becomes a client reaction (ARCHITECTURE "Client
	reactions to remotes"): clips on other rigs, telegraphs, hit-stop, digits, highlight flashes,
	an enemy's additive directional flinch, the parry spark burst, camera nudge and shake, the HP
	flash, the death freeze (Music, SFX and UI ducked) and shatter, the death system line after the
	shatter, other system lines, the Switch ring. A Stagger, Break, guard break or death hides the
	wind-up telegraph it interrupted. It also routes every rig's clip events (trail, smear,
	activation light, footsteps, clip sounds) to the FX and audio packages, so trails, smears and
	swings look and sound the same on the local fighter and on everyone else. A TrailOn's
	`data.kind` ("Art" | "Basic") picks the trail kind for the rest of that clip's trail events.

	Every tracked rig this client does not own (other players, enemies) gets a locomotion driver
	(Locomotion.attach) when it is watched, so it walks instead of sliding on its idle pose. The
	local rig's locomotion belongs to the character controller (Locomotion.new), so watch skips it:
	by id once the tracker has resolved it, by the character model before that, and a driver that
	slipped onto the local rig in between is dropped when the tracker's `localChanged` fires.
	Unwatch releases the driver, the trail, the telegraph highlight, the smear and the reaction clip.

	A remote player's driver sees the Drawn attribute through SheathState.riseFilter: a rise counts
	choreo.luau sheath.remoteDrawDelay late. The attribute can land a frame or two before the
	unreliable ActionStarted of the attack that set it; with the delay that attack draw-cuts, and
	no Draw or drawn walk set flashes in first. A lock-on's Draw starts that much later.

	Nothing here decides damage; a rejected hit is simply a `rejected` Signal that the character
	controller turns into a cancelled prediction (section 17).

	Dependencies come in through `Replication.bind(deps)` so Lune tests dispatch payloads at fake
	modules; `Replication.start()` binds the real ones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Combat = require(Shared.data.combat)
local ChoreoData = require(Shared.data.choreo)
local Fx = require(Shared.data.fx)
local UI = require(Shared.data.ui)
local Signal = require(Shared.util.Signal)
local ActionLogic = require(script.Parent.ActionLogic)
local Siblings = require(script.Parent.Siblings)

local SheathState, hasSheathState = Siblings.load(script.Parent.Parent, "choreo.SheathState")

export type Deps = {
	net: { on: (name: string, handler: (payload: any) -> ()) -> () },
	entities: any, -- EntityTracker-like: get(id), all(), added, removed
	localId: () -> number?, -- never yields
	localCharacter: (() -> Instance?)?, -- the local player's character model when it exists; never yields
	locomotion: any, -- Locomotion-like: attach(animator, model, deps?) -> driver, destroy(driver), humanoidTracker?
	choreo: any, -- Choreo.get(model) -> animator
	clipLibrary: any, -- ClipLibrary.has(clipId)
	trails: any,
	smear: any,
	shatter: any,
	sparks: any, -- Sparks-like: parry(position)
	telegraphs: any,
	outline: any,
	switchRing: any,
	digits: any,
	hud: any,
	systemLine: any,
	sfx: any, -- SfxPool-like: play(name, position?), footstep(model, surface?), duck(db, seconds)
	camera: any,
	weaponCategory: (record: any) -> string,
	trailToken: (record: any) -> string,
	positionOf: (model: Instance) -> Vector3?,
	schedule: (seconds: number, fn: () -> ()) -> (),
}

-- Sound names (family.Name in sfx.luau) the reactions play; Replication.spec checks each resolves.
local SOUNDS = {
	impact = { Normal = "impact.Flesh", Final = "impact.FinalHit", Kill = "impact.Kill" },
	hitStop = { Normal = "hitStopTick.Normal", Final = "hitStopTick.Final", Kill = "hitStopTick.Kill" },
	parry = "guard.Parry",
	block = "guard.Block",
	guardBreak = "guard.GuardBreak",
	shatterCrack = "shatter.Crack",
	switchPrompt = "ui.SwitchPrompt",
	switchLand = "ui.SwitchLand",
	systemLine = "ui.SystemLine",
}

-- StateChanged states that cancel an enemy's strike (Brain.interrupt) or end the fighter: the
-- wind-up telegraph comes down with them instead of glowing over a kneeling rig or a corpse.
local TELEGRAPH_CANCEL: { [string]: boolean } = { Stagger = true, Break = true, GuardBroken = true, Dead = true }

-- Trail kinds a clip's TrailOn may name in data.kind.
local TRAIL_KINDS: { [string]: boolean } = { Art = true, Basic = true }

local Replication = {}

--- The sound names the reactions play (tests check them against sfx.luau).
Replication.SOUNDS = SOUNDS

--- Fires (action, reason, clientTime) when the server rejects one of the local player's requests.
Replication.rejected = Signal.new() :: Signal.Signal<string, string, number?>
--- Fires (record, clipId, event) for every clip event on every tracked rig.
Replication.clipEvent = Signal.new() :: Signal.Signal<any, string, any>
--- Fires (record, state, duration?, direction?) on every StateChanged.
Replication.stateChanged = Signal.new() :: Signal.Signal<any, string, number?, string?>
--- Fires the raw HitConfirmed payload after the reactions ran (the character controller tracks parries).
Replication.hit = Signal.new() :: Signal.Signal<any>

local deps: Deps? = nil
local stateClips: { [number]: any } = {} -- entity id -> handle of the reaction clip playing
local watched: { [number]: { Disconnect: (self: any) -> () }? } = {}
local drivers: { [number]: any } = {} -- entity id -> locomotion driver on a rig this client does not own
-- entity id -> the trail kind the playing clip's TrailOn named; HitWindowOpen / Close, TrailOff and
-- PostMotionStart carry no kind, so they reuse it while the same clip is playing.
local trailKinds: { [number]: { clipId: string, kind: string } } = {}

local function dependencies(): Deps
	if deps == nil then
		error("Replication: call bind() or start() first")
	end
	return deps :: Deps
end

local function toVector(v: { number }?): Vector3
	if v == nil then
		return Vector3.zero
	end
	local x, y, z = table.unpack(v)
	return Vector3.new(x, y, z)
end

local function animatorOf(record: any): any
	return dependencies().choreo.get(record.model)
end

local function reactionClip(record: any, name: string): string?
	local d = dependencies()
	local id = ActionLogic.clipId(record.kind, record.rig, d.weaponCategory(record), name)
	if d.clipLibrary.has(id) == true then
		return id
	end
	return nil
end

local function playReaction(record: any, name: string): boolean
	local id = reactionClip(record, name)
	if id == nil then
		return false
	end
	local previous = stateClips[record.id]
	local animator = animatorOf(record)
	if previous ~= nil then
		animator:stop(previous, Combat.locomotionBlendOut)
	end
	stateClips[record.id] = animator:play(id)
	return true
end

local function stopReaction(record: any)
	local previous = stateClips[record.id]
	if previous ~= nil then
		animatorOf(record):stop(previous, Combat.locomotionBlendOut)
		stateClips[record.id] = nil
	end
end

-- Which reaction clip a StateChanged plays, or nil when the owner handles the state.
local function stateClipName(state: string, direction: string?, isLocal: boolean): string?
	if state == "Stagger" then
		return if direction ~= nil then "Flinch" .. direction else "Stagger"
	elseif state == "GuardBroken" then
		return "GuardBreak"
	elseif state == "Break" then
		return "Break"
	elseif state == "Guard" and not isLocal then
		return "Guard"
	end
	return nil
end
Replication.stateClipName = stateClipName

local handlers: { [string]: (payload: any) -> () } = {}

function handlers.ActionStarted(payload: any)
	local d = dependencies()
	if payload.entityId == d.localId() then
		return
	end
	local record = d.entities.get(payload.entityId)
	if record == nil then
		return
	end
	animatorOf(record):play(payload.clipId, { serverTime = payload.serverTime, speed = payload.speed })
end

function handlers.Telegraph(payload: any)
	local d = dependencies()
	local record = d.entities.get(payload.entityId)
	if record == nil then
		return
	end
	d.telegraphs.show(
		record.model,
		payload.kind,
		payload.windUp,
		toVector(payload.origin),
		toVector(payload.facing),
		payload.shape
	)
end

function handlers.HitConfirmed(payload: any)
	local d = dependencies()
	local attacker = d.entities.get(payload.attackerId)
	local target = d.entities.get(payload.targetId)
	local localId = d.localId()
	local tier = payload.hitStop
	local frames = Combat.hitStopFrames[tier] or Combat.hitStopFrames.Normal
	local position = toVector(payload.position)
	local involved = payload.attackerId == localId or payload.targetId == localId

	if attacker ~= nil then
		animatorOf(attacker):hitStop(frames)
	end
	if target ~= nil and target ~= attacker then
		animatorOf(target):hitStop(frames)
	end

	if payload.parried then
		-- A perfect parry: spark burst, the metallic ring, a short shake; no number.
		if target ~= nil then
			d.trails.flashWhite(target.model, Combat.highlightFlashFrames)
			playReaction(target, "Parry")
		end
		d.sparks.parry(position)
		d.sfx.play(SOUNDS.parry, position)
		if involved then
			d.camera.shake("Normal")
		end
		Replication.hit:Fire(payload)
		return
	end

	local kind = "Normal"
	if payload.targetId == localId then
		kind = "Taken"
	elseif payload.isSwitch then
		kind = "Switch"
	elseif payload.crit then
		kind = "Crit"
	end
	if payload.damage > 0 then
		d.digits.show(position, payload.damage, kind)
	end
	if target ~= nil then
		d.outline.flash(target.model, "SystemWhite", Combat.highlightFlashFrames)
		if payload.guarded then
			playReaction(target, "GuardHit")
		end
		local direction = payload.staggerDirection
		if target.kind == "Enemy" and direction ~= nil and not payload.killed and not payload.broke then
			-- The directional hit flinch rides the Additive layer, so it plays over the idle, the walk,
			-- an attack or a Break kneel without replacing the reaction clip.
			local flinch = reactionClip(target, "Flinch" .. direction)
			if flinch ~= nil then
				animatorOf(target):play(flinch)
			end
		end
	end
	if payload.isSwitch and attacker ~= nil then
		d.trails.flashWhite(attacker.model, Combat.highlightFlashFrames)
		d.sfx.play(SOUNDS.switchLand, position)
	end
	if involved then
		d.camera.nudge(position, Combat.cameraNudgeStuds)
		d.camera.shake(tier)
		d.sfx.play(SOUNDS.hitStop[tier] or SOUNDS.hitStop.Normal)
	end
	if payload.targetId == localId and payload.damage > 0 then
		d.hud.flashHp()
	end
	d.sfx.play(if payload.guarded then SOUNDS.block else (SOUNDS.impact[tier] or SOUNDS.impact.Normal), position)
	Replication.hit:Fire(payload)
end

function handlers.StateChanged(payload: any)
	local d = dependencies()
	local record = d.entities.get(payload.entityId)
	if record == nil then
		return
	end
	local isLocal = payload.entityId == d.localId()
	if TELEGRAPH_CANCEL[payload.state] == true then
		-- No strike follows an interrupted wind-up (a no-op when the rig shows no telegraph).
		d.telegraphs.hide(record.model)
	end
	local clipName = stateClipName(payload.state, payload.direction, isLocal)
	if clipName ~= nil then
		playReaction(record, clipName)
	elseif payload.state ~= "Dead" then
		stopReaction(record)
	end
	if payload.state == "GuardBroken" then
		d.outline.flash(record.model, "HPRed", Combat.highlightFlashFrames)
		d.sfx.play(SOUNDS.guardBreak, d.positionOf(record.model))
	end
	Replication.stateChanged:Fire(record, payload.state, payload.duration, payload.direction)
end

function handlers.EntityDied(payload: any)
	local d = dependencies()
	local record = d.entities.get(payload.entityId)
	local position = toVector(payload.position)
	if record ~= nil then
		local animator = animatorOf(record)
		playReaction(record, "DeathFreeze")
		animator:setTimeScale(0)
		d.trails.setActive(record.model, false, "Art")
	end
	-- Freeze and silence (section 6, section 11): Music, SFX and UI duck, not only the music.
	d.sfx.duck(Combat.deathDuckDb, Combat.deathFreeze)
	d.schedule(Combat.deathFreeze, function()
		-- The silence ends as this shatter cracks. SfxPool keeps only the newest duck, so without
		-- this a second death inside the freeze would keep the groups down and swallow this crack
		-- and chime; a duck of 0 dB restores full volume and makes any pending restore stale.
		d.sfx.duck(0, 0)
		if record ~= nil then
			-- Shatter.play plays the crack itself (SfxPool.shatter) at the rig.
			d.shatter.play(record.model, payload.shatter)
		else
			-- No rig left to shatter: the crack still sounds where the server said it died.
			d.sfx.play(SOUNDS.shatterCrack, position)
		end
	end)
	local isLocal = payload.entityId == d.localId()
	if isLocal or (record ~= nil and record.kind == "Player") then
		-- The line follows the shatter: the dying player reads their own line, everyone else the name.
		local shatterTime = if payload.shatter == "Boss" then Fx.shatter.bossDuration else Fx.shatter.duration
		local text = if isLocal then UI.systemLine.deathSelf else UI.systemLine.deathOther:format(payload.name)
		d.schedule(Combat.deathFreeze + shatterTime, function()
			d.systemLine.show(text, "SystemWhite", SOUNDS.systemLine)
		end)
	end
end

function handlers.ActionRejected(payload: any)
	Replication.rejected:Fire(payload.action, payload.reason, payload.clientTime)
end

function handlers.SystemLine(payload: any)
	dependencies().systemLine.show(payload.text, payload.token, payload.chime)
end

function handlers.SwitchWindow(payload: any)
	local d = dependencies()
	local position = toVector(payload.position)
	d.switchRing.show(position, payload.duration)
	if payload.openerId ~= d.localId() then
		if typeof(rawget(d.hud, "showSwitchPrompt")) == "function" then
			-- SWITCH sits above the enemy (section 14) when its rig is known.
			local record = d.entities.get(payload.entityId)
			d.hud.showSwitchPrompt(payload.duration, if record ~= nil then record.model else nil)
		else
			d.systemLine.show("SWITCH", "SystemCyan", SOUNDS.switchPrompt)
		end
		d.sfx.play(SOUNDS.switchPrompt)
	end
end

Replication.handlers = handlers

-- The trail kind for a clip event: the kind the event names (remembered for the rest of the
-- clip), else what this clip's TrailOn named, else the clip id ("/Basic" swings are Basic).
local function resolveTrailKind(record: any, clipId: string, event: any): string
	local data = event.data
	if typeof(data) == "table" and typeof(data.kind) == "string" and TRAIL_KINDS[data.kind] == true then
		trailKinds[record.id] = { clipId = clipId, kind = data.kind }
		return data.kind
	end
	local remembered = trailKinds[record.id]
	if remembered ~= nil and remembered.clipId == clipId then
		return remembered.kind
	end
	return if string.find(clipId, "/Basic", 1, true) then "Basic" else "Art"
end

--- Routes one clip event on a rig to the FX and audio packages (trails, smear, activation light,
--- footsteps, clip sounds).
function Replication.routeClipEvent(record: any, clipId: string, event: any)
	local d = dependencies()
	local model = record.model
	local kind = event.kind
	if kind == "HitWindowOpen" or kind == "TrailOn" then
		d.trails.setActive(model, true, resolveTrailKind(record, clipId, event))
		if kind == "HitWindowOpen" then
			d.trails.activationLight(model, false, d.trailToken(record))
		end
	elseif kind == "HitWindowClose" or kind == "TrailOff" then
		d.trails.setActive(model, false, resolveTrailKind(record, clipId, event))
	elseif kind == "SmearOn" then
		-- The smear frames run the trail at full width (section 10 beat 3) on top of any Art or
		-- Basic kind; Trails keeps the trail lit while any kind is on.
		d.smear.apply(model, true, if event.data ~= nil then event.data.axis else nil)
		d.trails.setActive(model, true, "Smear")
	elseif kind == "SmearOff" then
		d.smear.apply(model, false, if event.data ~= nil then event.data.axis else nil)
		d.trails.setActive(model, false, "Smear")
	elseif kind == "Sfx" or kind == "Voice" then
		-- data.name is a sfx.luau "family.Name"; SfxPool resolves it and skips placeholders.
		local data = event.data
		if typeof(data) == "table" and typeof(data.name) == "string" then
			d.sfx.play(data.name, d.positionOf(model))
		end
	elseif kind == "ActivationHold" then
		local token = d.trailToken(record)
		d.trails.activationLight(model, true, token)
		d.sfx.play("artChime." .. token, d.positionOf(model))
		if record.id == d.localId() then
			d.camera.fovKick()
		end
	elseif kind == "PostMotionStart" then
		d.trails.activationLight(model, false, d.trailToken(record))
		d.trails.setActive(model, false, resolveTrailKind(record, clipId, event))
		trailKinds[record.id] = nil
	elseif kind == "Footstep" then
		-- SfxPool resolves the surface from the event or the Humanoid's floor, and the weight
		-- from the armor attribute.
		d.sfx.footstep(model, if event.data ~= nil then event.data.surface else nil)
	end
	Replication.clipEvent:Fire(record, clipId, event)
end

-- True for the local player's own rig, whose locomotion the character controller drives. The id
-- settles it once the tracker knows it; before that (EntityTracker fires `added` before it
-- resolves the local id) the character model does.
local function isLocalRecord(record: any): boolean
	local d = dependencies()
	if record.id == d.localId() then
		return true
	end
	local localCharacter = d.localCharacter
	if localCharacter ~= nil then
		local character = localCharacter()
		return character ~= nil and character == record.model
	end
	return false
end

local function destroyDriver(id: number)
	local driver = drivers[id]
	if driver == nil then
		return
	end
	drivers[id] = nil
	dependencies().locomotion.destroy(driver)
end

-- The driver options for a remote player's rig: the default Humanoid tracker, fed the driver's
-- Drawn attribute through a rise filter (sheath.remoteDrawDelay). `driverOf` gives the driver
-- once attach has returned it. Nil (the default tracker) when the locomotion package has none.
local function remotePlayerOptions(locomotion: any, model: Instance, driverOf: () -> any): any
	if not hasSheathState or typeof(locomotion.humanoidTracker) ~= "function" then
		return nil
	end
	local filter = SheathState.riseFilter(ChoreoData.sheath.remoteDrawDelay, model:GetAttribute("Drawn") == true)
	local source = locomotion.humanoidTracker(model, function(): boolean
		return filter.value
	end)
	return {
		tracker = function(dt: number): any
			local driver = driverOf()
			if driver ~= nil then
				filter:step(dt, driver:serverDrawn() == true)
			end
			return source(dt)
		end,
	}
end

-- Attaches the remote-rig locomotion driver (a player rig runs the blend space, an enemy rig its
-- idle / walk pair) unless the rig is the local player's own.
local function attachDriver(record: any, animator: any)
	if drivers[record.id] ~= nil or isLocalRecord(record) then
		return
	end
	local d = dependencies()
	local attached: any = nil
	local options = if record.kind == "Player"
		then remotePlayerOptions(d.locomotion, record.model, function(): any
			return attached
		end)
		else nil
	local ok, driver = pcall(d.locomotion.attach, animator, record.model, options)
	if not ok then
		warn(("[Replication] locomotion for %s failed: %s"):format(tostring(record.name), tostring(driver)))
		return
	end
	if driver ~= nil and not Siblings.isStub(driver) then
		attached = driver
		drivers[record.id] = driver
	end
end

--- Starts watching a tracked rig: outline, trail attachment, clip events, and the locomotion
--- driver when the rig is not the local player's own.
function Replication.watch(record: any)
	local d = dependencies()
	if watched[record.id] ~= nil then
		return
	end
	d.outline.register(record.model)
	d.trails.attach(record.model)
	local animator = animatorOf(record)
	local events = if typeof(animator) == "table" then animator.events else nil
	local connection = nil
	if typeof(events) == "table" and typeof(events.Connect) == "function" then
		connection = events:Connect(function(clipId: string, event: any)
			Replication.routeClipEvent(record, clipId, event)
		end)
	end
	watched[record.id] = connection or { Disconnect = function() end }
	attachDriver(record, animator)
end

--- Stops watching a rig that left: drops its driver, reaction clip, outline, trail, telegraph and smear.
function Replication.unwatch(record: any)
	local d = dependencies()
	local connection = watched[record.id]
	if connection ~= nil then
		connection:Disconnect()
		watched[record.id] = nil
	end
	destroyDriver(record.id)
	stateClips[record.id] = nil
	trailKinds[record.id] = nil
	d.outline.unregister(record.model)
	d.trails.detach(record.model)
	d.telegraphs.forget(record.model)
	d.smear.reset(record.model)
end

--- Installs dependencies (the test seam) and connects entity added/removed to watch/unwatch.
function Replication.bind(newDeps: Deps)
	deps = newDeps
	table.clear(stateClips)
	table.clear(watched)
	table.clear(drivers)
	table.clear(trailKinds)
	local entities = newDeps.entities
	if typeof(entities.added) == "table" then
		entities.added:Connect(Replication.watch)
		entities.removed:Connect(Replication.unwatch)
	end
	if typeof(entities.localChanged) == "table" then
		-- The local record can be watched before the tracker resolves its id; a driver attached
		-- then would double-drive the rig under the character controller's own Locomotion.
		entities.localChanged:Connect(function(id: number?)
			if id ~= nil then
				destroyDriver(id)
			end
		end)
	end
	if typeof(entities.all) == "function" then
		for _, record in entities.all() do
			Replication.watch(record)
		end
	end
end

--- Runs the handler for a remote name with a payload (what `net.on` calls; tests call it directly).
function Replication.dispatch(name: string, payload: any)
	local handler = handlers[name]
	if handler == nil then
		error(("Replication: no handler for remote '%s'"):format(name))
	end
	handler(payload)
end

--- Subscribes every handler to the bound net.
function Replication.subscribe()
	local d = dependencies()
	for name, handler in handlers do
		d.net.on(name, handler)
	end
end

--- Binds the real modules (missing siblings become no-op stubs) and subscribes to the remotes.
function Replication.start()
	local Client = script.Parent.Parent
	local player = game:GetService("Players").LocalPlayer
	local Net = require(Shared.net.Net)
	local EntityTracker = require(script.Parent.EntityTracker)
	local WeaponInfo = require(script.Parent.WeaponInfo)
	local CameraController = require(Client.camera.CameraController)
	local choreo = Siblings.load(Client, "choreo.Choreo")
	local clipLibrary = Siblings.load(Client, "choreo.ClipLibrary")
	Replication.bind({
		net = Net.client(),
		entities = EntityTracker,
		localId = EntityTracker.peekLocalId,
		localCharacter = function()
			return player.Character
		end,
		locomotion = Siblings.load(Client, "choreo.Locomotion"),
		choreo = choreo,
		clipLibrary = clipLibrary,
		trails = Siblings.load(Client, "fx.Trails"),
		smear = Siblings.load(Client, "fx.Smear"),
		shatter = Siblings.load(Client, "fx.Shatter"),
		sparks = Siblings.load(Client, "fx.Sparks"),
		telegraphs = Siblings.load(Client, "fx.Telegraphs"),
		outline = Siblings.load(Client, "fx.OutlineManager"),
		switchRing = Siblings.load(Client, "fx.SwitchRing"),
		digits = Siblings.load(Client, "fx.Digits"),
		hud = Siblings.load(Client, "ui.Hud"),
		systemLine = Siblings.load(Client, "ui.SystemLine"),
		sfx = Siblings.load(Client, "audio.SfxPool"),
		camera = CameraController,
		weaponCategory = function(record)
			return WeaponInfo.categoryOf(record.weaponId)
		end,
		trailToken = function(record)
			return WeaponInfo.trailTokenOf(record.weaponId)
		end,
		positionOf = function(model)
			local primary = (model :: Model).PrimaryPart
			return if primary ~= nil then primary.Position else nil
		end,
		schedule = function(seconds, fn)
			task.delay(seconds, fn)
		end,
	})
	Replication.subscribe()
end

return Replication
