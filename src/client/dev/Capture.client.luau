--!strict
--[[
	Capture prompts (section 1 "How you work", section 20 Phase 0 gate). Runs only in a place whose
	Workspace carries the DevCapture attribute (places/Playground.project.json). Shows the gate shot
	list from data/dev.luau in a SystemCyan panel: which shot is up, what the reviewer must see, the
	file it is saved to (docs/clips/phase-0/<shot>.mp4). The reviewer records with Studio's own
	recorder or any screen capture.

	Every shot stages itself (F12). P asks the server to set it up (DevStage.server.luau, Studio
	only: once the player stands in the shot's ring, it is healed and the shot's enemies are placed
	around where it stands and faces at their distance and side, held or let go as the take starts,
	every other enemy held well away; see the walk below), then the camera takes the
	shot's view (CameraController.setStage: a side or three-quarter view for the Arts, the parry and
	the kill, behind the boar for its charge, the lock's own camera for the fight, a fixed side view
	of the open run for locomotion) and the shot's lock is taken (TargetController.lockOn). A 3-2-1
	runs, the panel hides, the mouse cursor hides, and the take records with a frame counter
	bottom-left (its text written before it shows, its box as wide as its text) and above it a
	prompt naming the move and its moment. The take stops itself at its target length and is marked
	done; K marks it done at the target, and before it asks first: a second K inside
	capture.confirmSeconds ends the take unmarked. J gives the field back (the staged enemies gone,
	the field's holds let go). Where there is no staging remote (outside Studio) the countdown runs
	on the field as it is.

	The staging never moves the player (D-244). A player standing outside the shot's stand ring is
	told to walk into it (the reply's `walk`: the ring and a route round the ledge and up its ramp).
	The panel marks the ring with a flat SystemCyan disc on the spot, says "Walk into the ring" and
	walks the body there itself through the input path a held key takes: each frame a render step
	after the control script's (dev.luau capture.walk.renderOrder) hands the route's direction to
	Humanoid:Move, before the character controller reads MoveDirection, so the walk, Locomotion and
	the two-step stop run as they do under the keys. The route's last leg runs along the spot's
	facing, so the walk turns the body the shot's way. Within arriveStuds of the spot it lets go;
	once the body is at rest the ring goes and the shot is asked for again (no faster than the
	server's rate): a root in the ring stages, one outside gets a new walk. A movement key hands the
	walk to the player (the ring stays, the ask comes once the root stands in it at rest), J ends it
	with the field given back, P stages afresh, and walk.timeoutSeconds on the capture's clock ends
	it with a note naming what failed.

	Auto-perform (U, off by default) presses the shot's keys through the real input path
	(InputController.handle, as a key's binding does): an Art at its moment, the kill's basic, the
	locomotion pass's lock on and off, and the parry's guard `lead` seconds before the hit window of
	the target's overhead as the client draws it. Only at 1x. A lock press in a staged take acts on
	the staged target alone (D-290: it locks it, or lets it go when the lock is on it), never the
	lock key's cycle, which could step on to a field enemy nearer than it. A take that stops lets
	go of every key it holds without acting: a held Art is cancelled before its key comes up, so
	the release launches nothing.

	A time-scale toggle (1x / 0.5x / 0.25x) slows every Choreo animator on this client and asks the
	server (dev remote, dev places only) to publish the scale as a workspace attribute for anything
	else that wants to honour it. The local character goes through
	CharacterController.setCaptureTimeScale, which also moves the body on that clock (its walk, the
	two-step stop, the lock turn, the snap's whip) so the slowed feet keep their ground, and keeps a
	frozen Art stance frozen. Hit FX and sounds keep running at 1x, so a slowed shot reviews
	animation only; the panel says so next to the scale (Dev.timeScaleLabel). No gameplay logic
	lives here: the server owns every placement, HP and hold.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dev = require(Shared.data.dev)
local InputData = require(Shared.data.input)

if workspace:GetAttribute(Dev.attributes.capture) ~= true then
	return
end

local Client = script.Parent.Parent
local El = require(Client.ui.lib.El)
local Siblings = require(Client.controllers.Siblings)
local CaptureLogic = require(script.Parent.CaptureLogic)
local CameraController = require(Client.camera.CameraController)
local TargetController = require(Client.controllers.TargetController)
local InputController = require(Client.controllers.InputController)
local EntityTracker = require(Client.controllers.EntityTracker)
local Replication = require(Client.controllers.Replication)
local ClipLibrary = require(Client.choreo.ClipLibrary)
local FrameOrder = require(Client.fx.FrameOrder)
local World = require(Shared.data.world)

local Choreo, hasChoreo = Siblings.load(Client, "choreo.Choreo")
local CharacterController = Siblings.load(Client, "controllers.CharacterController")

local Capture = Dev.capture
local PanelData = Capture.panel
local CounterData = Capture.counter
local PromptData = Capture.prompt
local WalkData = Capture.walk
local RingData = WalkData.ring
local Shots = Capture.shots
local Steps = Dev.timeScale.steps

type Phase = "Idle" | "Staging" | "Walking" | "Countdown" | "Recording" | "Done"
-- The walk into the stand ring: the auto-walk steering, its let-go (waiting for the body to come
-- to rest), or the player walking it after a movement key.
type WalkMode = "Auto" | "Settle" | "Manual"

local WALK_STEP_NAME = "SkyspireCaptureWalk"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------------------------

local shotIndex = 1
local done: { [string]: boolean } = {}
local phase: Phase = "Idle"
local countdownRemaining = 0
local elapsed = 0
local frames = 0
local doneTimer = 0
local timeScaleIndex = 1
local panelVisible = true
local reapplyTimer = 0
local statusNote: string? = nil
-- The staging this panel asked for last (a reply to an older one is ignored) and its target.
local stageToken = 0
local targetId: number? = nil
-- K short of the target: a second K before this clock ends the take unmarked.
local confirmUntil: number? = nil
-- Auto-perform: on or off, the take's timed presses left, the keys it holds down, and the parry.
local autoOn = Capture.perform.defaultOn
local performing = false
local presses: { CaptureLogic.Press } = {}
local heldKeys: { [string]: boolean } = {}
local parry: Dev.Perform? = nil
local parryAt: number? = nil
-- The mouse cursor as it was before the take hid it.
local cursorBefore: boolean? = nil
-- The walk into the stand ring a staging asked for, who walks it, how long it has run (on the
-- capture's clock), the ring's disc, and when this panel last asked the server anything.
local walk: CaptureLogic.Walk? = nil
local walkMode: WalkMode = "Auto"
local walkElapsed = 0
local ringPart: BasePart? = nil
local lastAskAt: number? = nil

-- ---------------------------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------------------------

local function label(text: string, size: number, token: string, props: { [string]: any }?): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, PanelData.rowHeight),
		FontFace = El.font("system"),
		Text = text,
		TextSize = size,
		TextColor3 = El.color(token),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
	}
	if props then
		for key, value in props do
			merged[key] = value
		end
	end
	return El.new("TextLabel", merged) :: TextLabel
end

local gui = El.new("ScreenGui", {
	Name = PanelData.screenGuiName,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = PanelData.displayOrder,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}) :: ScreenGui

local panel = El.new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -PanelData.margin, 0, PanelData.margin),
	Size = UDim2.fromOffset(PanelData.width, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = El.color(PanelData.backgroundToken),
	BackgroundTransparency = PanelData.backgroundTransparency,
	BorderSizePixel = 0,
}, {
	El.new("UICorner", { CornerRadius = UDim.new(0, PanelData.cornerRadius) }),
	El.new("UIStroke", {
		Color = El.color(PanelData.borderToken),
		Thickness = PanelData.borderThickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}),
	El.new("UIPadding", {
		PaddingTop = UDim.new(0, PanelData.padding),
		PaddingBottom = UDim.new(0, PanelData.padding),
		PaddingLeft = UDim.new(0, PanelData.padding),
		PaddingRight = UDim.new(0, PanelData.padding),
	}),
	El.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, PanelData.lineGap),
	}),
}) :: Frame

local titleLabel =
	label(("Capture: %s gate shots"):format(Capture.phase), PanelData.titleTextSize, PanelData.titleToken, {
		LayoutOrder = 1,
		FontFace = El.font("system", "Bold"),
	})
local scaleLabel = label("", PanelData.textSize, PanelData.textToken, { LayoutOrder = 2 })
local autoLabel = label("", PanelData.textSize, PanelData.textToken, { LayoutOrder = 3 })
local shotLabels: { TextLabel } = {}
for index in Shots do
	local row = label("", PanelData.textSize, PanelData.textToken, { LayoutOrder = 10 + index })
	table.insert(shotLabels, row)
	row.Parent = panel
end
local notesLabel = label("", PanelData.smallTextSize, PanelData.dimToken, { LayoutOrder = 100 })
local fileLabel = label("", PanelData.smallTextSize, PanelData.textToken, { LayoutOrder = 101 })
local countdownLabel = label("", PanelData.countdownTextSize, PanelData.titleToken, {
	LayoutOrder = 102,
	TextXAlignment = Enum.TextXAlignment.Center,
	Visible = false,
	FontFace = El.font("system", "Bold"),
})
local keys = Capture.hotkeys
local legendLabel = label(
	("%s stage and record   %s / %s shot   %s time scale   %s auto-perform   %s give the field back   %s hide   %s mark done"):format(
		keys.startCountdown,
		keys.previousShot,
		keys.nextShot,
		keys.cycleTimeScale,
		keys.autoPerform,
		keys.releaseStage,
		keys.togglePanel,
		keys.markDone
	),
	PanelData.smallTextSize,
	PanelData.dimToken,
	{ LayoutOrder = 103 }
)
local statusLabel = label("", PanelData.textSize, PanelData.doneToken, { LayoutOrder = 104 })

titleLabel.Parent = panel
scaleLabel.Parent = panel
autoLabel.Parent = panel
notesLabel.Parent = panel
fileLabel.Parent = panel
countdownLabel.Parent = panel
legendLabel.Parent = panel
statusLabel.Parent = panel
panel.Parent = gui

-- A box bottom-left as wide as its text (AutomaticSize X), `bottom` pixels up from the screen's edge.
local function hudBox(name: string, height: number, bottom: number, paddingX: number, data: any): (Frame, TextLabel)
	local box = El.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, CounterData.margin, 1, -bottom),
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = El.color(data.backgroundToken),
		BackgroundTransparency = data.backgroundTransparency,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		El.new("UICorner", { CornerRadius = UDim.new(0, PanelData.cornerRadius) }),
		El.new("UIPadding", {
			PaddingLeft = UDim.new(0, paddingX),
			PaddingRight = UDim.new(0, paddingX),
		}),
	}) :: Frame
	local text = El.new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = El.font("system", "Bold"),
		Text = "",
		TextSize = data.textSize,
		TextColor3 = El.color(data.token),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = box,
	}) :: TextLabel
	box.Parent = gui
	return box, text
end

local counter, counterLabel =
	hudBox("Counter", CounterData.height, CounterData.margin, CounterData.paddingX, CounterData)
local prompt, promptLabel = hudBox(
	"Prompt",
	PromptData.height,
	CounterData.margin + CounterData.height + PromptData.gap,
	PromptData.paddingX,
	PromptData
)
gui.Parent = playerGui

-- ---------------------------------------------------------------------------------------------
-- Rendering the panel text
-- ---------------------------------------------------------------------------------------------

local function currentShot(): Dev.Shot
	return Shots[shotIndex]
end

local function refreshPanel()
	for index, row in shotLabels do
		local shot = Shots[index]
		local mark = if done[shot.id] then "[x]" else "[ ]"
		local pointer = if index == shotIndex then ">" else " "
		row.Text = ("%s %s %d. %s (%g s)"):format(pointer, mark, index, shot.title, shot.seconds)
		row.TextColor3 = El.color(
			if done[shot.id]
				then PanelData.doneToken
				elseif index == shotIndex then PanelData.titleToken
				else PanelData.textToken
		)
	end
	local shot = currentShot()
	notesLabel.Text = "See: " .. shot.notes
	fileLabel.Text = "Save as " .. Dev.clipPath(shot.id)
	scaleLabel.Text = Dev.timeScaleLabel(Steps[timeScaleIndex])
	autoLabel.Text = ("Auto-perform %s (%s; 1x only)"):format(if autoOn then "on" else "off", keys.autoPerform)
	if statusNote ~= nil then
		statusLabel.Text = statusNote :: string
	elseif phase == "Done" then
		statusLabel.Text = ("Shot done: %s"):format(Dev.clipPath(shot.id))
	elseif phase == "Staging" then
		statusLabel.Text = "Staging the shot..."
	elseif phase == "Idle" then
		statusLabel.Text = ("Ready. Start your recorder, press %s: the shot stages, counts 3-2-1 and hides the panel."):format(
			keys.startCountdown
		)
	else
		statusLabel.Text = ""
	end
end

local function setPanelVisible(visible: boolean)
	panelVisible = visible
	panel.Visible = visible
end

local function writeCounter()
	local shot = currentShot()
	counterLabel.Text = CaptureLogic.counterText({
		shotId = shot.id,
		frames = frames,
		elapsed = elapsed,
		target = shot.seconds,
		scale = Steps[timeScaleIndex],
		auto = performing,
		confirming = confirmUntil ~= nil,
		markKey = keys.markDone,
	})
end

local function writePrompt()
	local line = CaptureLogic.promptAt(currentShot().prompts, elapsed)
	promptLabel.Text = line or ""
	prompt.Visible = line ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- Time scale
-- ---------------------------------------------------------------------------------------------

local function applyTimeScaleTo(model: Instance, scale: number)
	if not hasChoreo or not model:IsA("Model") then
		return
	end
	local animator = Choreo.find(model)
	if animator ~= nil then
		animator:setTimeScale(scale)
	end
end

local function applyTimeScale()
	local scale = Steps[timeScaleIndex]
	local character = player.Character
	-- The local body: the controller takes it (and moves the body at the scale) when it can.
	local taken = Siblings.call(CharacterController, "setCaptureTimeScale", scale) == true
	for _, model in CollectionService:GetTagged(Capture.entityTag) do
		if not (taken and model == character) then
			applyTimeScaleTo(model, scale)
		end
	end
	if character ~= nil and not taken then
		applyTimeScaleTo(character, scale)
	end
end

local function publishTimeScale()
	local remote = ReplicatedStorage:FindFirstChild(Dev.timeScale.remoteName)
	if remote ~= nil and remote:IsA("RemoteEvent") then
		remote:FireServer(Steps[timeScaleIndex])
	end
end

local function cycleTimeScale()
	timeScaleIndex = timeScaleIndex % #Steps + 1
	applyTimeScale()
	publishTimeScale()
	refreshPanel()
end

-- ---------------------------------------------------------------------------------------------
-- Staging (the server's half is DevStage.server.luau)
-- ---------------------------------------------------------------------------------------------

-- Asks the staging remote; nil when this place has none (outside Studio).
local function ask(action: string, shotId: string?): any
	local remote = ReplicatedStorage:FindFirstChild(Capture.stage.remoteName)
	if remote == nil or not remote:IsA("RemoteFunction") then
		return nil
	end
	lastAskAt = os.clock()
	local ok, reply = pcall(function(): any
		return (remote :: RemoteFunction):InvokeServer(action, shotId)
	end)
	if not ok then
		return { ok = false, error = tostring(reply) }
	end
	return reply
end

-- The staged target's record once this client tracks it (it replicates a moment after the spawn).
local function waitForTarget(id: number?): any
	if id == nil then
		return nil
	end
	local deadline = os.clock() + Capture.stageTimeoutSeconds
	while true do
		local record = EntityTracker.get(id)
		if record ~= nil and (record.model :: Model?) ~= nil then
			return record
		end
		if os.clock() >= deadline then
			return nil
		end
		task.wait()
	end
end

-- The shot's camera and lock: a staged view unless the shot keeps the lock's own camera.
local function frameShot(shot: Dev.Shot, record: any)
	local model = if record ~= nil then record.model else nil
	local view = Capture.cameras[shot.camera]
	CameraController.setStage(view, model, shot.cameraSide)
	if shot.stage.lock and record ~= nil then
		TargetController.lockOn(record.id)
	elseif not shot.stage.lock then
		TargetController.clear()
	end
end

local function beginCountdown()
	phase = "Countdown"
	countdownRemaining = Capture.countdownSeconds
	countdownLabel.Visible = true
	countdownLabel.Text = tostring(Capture.countdownSeconds)
	setPanelVisible(true)
	refreshPanel()
end

-- Whether staging `token` is still the one running (P again, J or H may have moved on while
-- the server staged).
local function stillStaging(token: number): boolean
	return token == stageToken and phase == "Staging"
end

-- The ring's disc on the spot: flat, the ring's size, no collision and nothing a ray or a touch finds.
local function showRing(at: CaptureLogic.Walk)
	local part = ringPart
	if part == nil then
		local made = Instance.new("Part")
		made.Name = RingData.name
		made.Shape = Enum.PartType.Cylinder
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.CastShadow = false
		made.Material = (Enum.Material :: any)[RingData.material] or Enum.Material.SmoothPlastic
		made.Color = El.color(RingData.colorToken)
		made.Transparency = RingData.transparency
		ringPart = made
		part = made
	end
	local disc = part :: BasePart
	local diameter = at.radius * 2
	-- A cylinder's axis is X: stood on its side so its flat face looks up.
	disc.Size = Vector3.new(RingData.thickness, diameter, diameter)
	disc.CFrame = CFrame.new(at.x, at.y + RingData.thickness / 2, at.z) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = workspace
end

local function removeRing()
	local part = ringPart
	if part ~= nil then
		ringPart = nil
		part:Destroy()
	end
end

local function walkNote(): string
	if walkMode == "Manual" then
		return "Walk into the ring yourself: the shot stages around where you stand and face"
	end
	return ("Walk into the ring (walking there: a movement key takes over, %s stops)"):format(keys.releaseStage)
end

-- The staging asked for a walk into its ring (D-244).
local function startWalk(asked: CaptureLogic.Walk)
	phase = "Walking"
	walk = asked
	if walkMode ~= "Manual" then
		walkMode = "Auto"
	end
	-- No lock: a lock would turn the body to face it and walk it slow.
	TargetController.clear()
	showRing(asked)
	statusNote = walkNote()
	refreshPanel()
end

local function stopWalk()
	walk = nil
	removeRing()
end

-- Asks the server to stage `shot` and frames it, or walks into its ring when it says so.
local function runStaging(shot: Dev.Shot, token: number)
	task.spawn(function()
		local reply = ask("stage", shot.id)
		if not stillStaging(token) then
			return
		end
		local asked = if reply ~= nil and reply.ok ~= true then CaptureLogic.walkFrom(reply) else nil
		if asked ~= nil then
			startWalk(asked)
			return
		end
		if reply ~= nil and reply.ok ~= true then
			phase = "Idle"
			statusNote = ("Staging failed: %s"):format(tostring(reply.error))
			refreshPanel()
			return
		end
		if reply == nil then
			statusNote = "No staging here (Studio only): set the shot up by hand"
		end
		targetId = if reply ~= nil then reply.targetId else nil
		local record = waitForTarget(targetId)
		if not stillStaging(token) then
			return
		end
		frameShot(shot, record)
		beginCountdown()
	end)
end

local function startCountdown()
	if phase ~= "Idle" and phase ~= "Done" and phase ~= "Walking" then
		return
	end
	stopWalk()
	local shot = currentShot()
	phase = "Staging"
	statusNote = nil
	stageToken += 1
	walkMode = "Auto"
	walkElapsed = 0
	refreshPanel()
	runStaging(shot, stageToken)
end

-- ---------------------------------------------------------------------------------------------
-- Auto-perform: the shot's keys through the real input path
-- ---------------------------------------------------------------------------------------------

-- The enemy the lock is on now, by id.
local function lockedId(): number?
	local current = TargetController.current()
	return if current ~= nil then current.id else nil
end

local function press(action: string, down: boolean)
	-- A lock press in a staged take acts on the staged target alone (D-290); its key-up does nothing.
	if action == "LockOn" then
		local how = CaptureLogic.lockPress(targetId, lockedId())
		if how ~= "Key" then
			if down and how == "Lock" then
				TargetController.lockOn(targetId)
			elseif down then
				TargetController.clear()
			end
			return
		end
	end
	if down then
		heldKeys[action] = true
	else
		heldKeys[action] = nil
	end
	InputController.handle(action, if down then Enum.UserInputState.Begin else Enum.UserInputState.End, nil)
end

-- Lets go of every key auto-perform holds, none acting on the way up (D-290): a held Art's hold is
-- cancelled first, so its key's release launches nothing; the key still comes up through the input
-- path, so the hold there ends too.
local function releaseKeys()
	for _, key in CaptureLogic.letGo(heldKeys, InputData.artSlot) do
		if key.slot ~= nil then
			Siblings.call(CharacterController, "cancelArt", key.slot)
		end
		InputController.handle(key.action, Enum.UserInputState.End, nil)
	end
	table.clear(heldKeys)
end

local function armPerform(shot: Dev.Shot)
	performing = CaptureLogic.performs(autoOn, Steps[timeScaleIndex])
	presses = if performing then CaptureLogic.timedPresses(shot.perform) else {}
	parry = nil
	parryAt = nil
	if performing then
		for _, entry in shot.perform do
			if entry.onClip ~= nil then
				parry = entry
			end
		end
	end
end

local function stepPerform()
	if not performing then
		return
	end
	for _, due in CaptureLogic.due(presses, elapsed) do
		press(due.action, due.down)
	end
	local at = parryAt
	local entry = parry
	if at ~= nil and entry ~= nil and elapsed >= at then
		parryAt = nil
		parry = nil -- one parry a take
		press(entry.action, true)
		table.insert(presses, { at = elapsed + entry.hold, action = entry.action, down = false })
	end
end

-- The target's attack as this client draws it: the parry's guard goes down `lead` before its hit
-- window (heard from whichever event of the clip comes first).
Replication.clipEvent:Connect(function(record: any, clipId: string, event: any, jumped: boolean)
	local entry = parry
	if phase ~= "Recording" or entry == nil or parryAt ~= nil or jumped then
		return
	end
	if record == nil or record.id ~= targetId or clipId ~= entry.onClip then
		return
	end
	local ok, clip = pcall(ClipLibrary.get, clipId)
	if not ok or clip == nil then
		return
	end
	local delay = CaptureLogic.parryDelay(clip.events, event.time, entry.lead or 0)
	if delay ~= nil then
		parryAt = elapsed + delay
	end
end)

-- ---------------------------------------------------------------------------------------------
-- Shot flow
-- ---------------------------------------------------------------------------------------------

local function hideCursor()
	cursorBefore = UserInputService.MouseIconEnabled
	UserInputService.MouseIconEnabled = false
end

local function restoreCursor()
	if cursorBefore ~= nil then
		UserInputService.MouseIconEnabled = cursorBefore :: boolean
		cursorBefore = nil
	end
end

local function startRecording()
	local shot = currentShot()
	phase = "Recording"
	elapsed = 0
	frames = 0
	confirmUntil = nil
	armPerform(shot)
	countdownLabel.Visible = false
	setPanelVisible(false)
	-- The text first: the counter never shows a blank frame.
	writeCounter()
	counter.Visible = true
	writePrompt()
	hideCursor()
	-- The staged enemies the shot lets go start now.
	task.spawn(ask, "go")
end

-- Ends the take: marked done, or stopped short and unmarked.
local function finish(marked: boolean)
	if phase ~= "Recording" then
		return
	end
	local shot = currentShot()
	releaseKeys()
	performing = false
	presses = {}
	parry = nil
	parryAt = nil
	restoreCursor()
	prompt.Visible = false
	counter.Visible = false
	confirmUntil = nil
	CameraController.setStage(nil)
	if marked then
		done[shot.id] = true
		phase = "Done"
		doneTimer = Capture.doneHoldSeconds
		statusNote = nil
	else
		phase = "Idle"
		statusNote = ("Stopped at %.1f s, short of %g s: not marked done"):format(elapsed, shot.seconds)
	end
	setPanelVisible(true)
	refreshPanel()
end

local function markDone()
	if phase ~= "Recording" then
		return
	end
	local decision = CaptureLogic.markDecision(elapsed, currentShot().seconds, os.clock(), confirmUntil)
	if decision == "Done" then
		finish(true)
	elseif decision == "Stop" then
		finish(false)
	else
		confirmUntil = os.clock() + Capture.confirmSeconds
		writeCounter()
	end
end

local function moveShot(delta: number)
	if phase ~= "Idle" and phase ~= "Done" then
		return
	end
	shotIndex = (shotIndex - 1 + delta) % #Shots + 1
	phase = "Idle"
	statusNote = nil
	refreshPanel()
end

local function toggleAuto()
	autoOn = not autoOn
	refreshPanel()
end

-- Asks the server to give the field back until it does: it refuses while a staging still runs
-- (J pressed mid-staging; that staging then holds the field and spawns its enemies) and a request
-- faster than its rate, so a refusal is asked again at the rate, for up to stageTimeoutSeconds.
-- The panel says the field is back only when the server says so. A newer staging (P) owns the
-- field, and ends the asking.
local function giveBack(token: number)
	local deadline = os.clock() + Capture.stageTimeoutSeconds
	while true do
		local reply = ask("release")
		if token ~= stageToken then
			return
		end
		if reply == nil or reply.ok == true then
			statusNote = "Field given back"
			refreshPanel()
			return
		end
		if os.clock() >= deadline then
			statusNote = ("Field not given back: %s; press %s again"):format(tostring(reply.error), keys.releaseStage)
			refreshPanel()
			return
		end
		task.wait(1 / Capture.stage.requestsPerSecond)
		if token ~= stageToken then
			return
		end
	end
end

local function releaseStage()
	if phase == "Recording" or phase == "Countdown" then
		return
	end
	stageToken += 1 -- a staging still on its way is dropped
	stopWalk()
	phase = "Idle"
	CameraController.setStage(nil)
	statusNote = "Giving the field back"
	refreshPanel()
	task.spawn(giveBack, stageToken)
end

-- ---------------------------------------------------------------------------------------------
-- Input and the per-frame step
-- ---------------------------------------------------------------------------------------------

local function keyCode(name: string): Enum.KeyCode?
	local ok, result = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok then result else nil
end

local bindings: { [Enum.KeyCode]: () -> () } = {}
local function bind(name: string, fn: () -> ())
	local code = keyCode(name)
	if code ~= nil then
		bindings[code] = fn
	else
		warn(("[Capture] unknown key %s in dev.luau"):format(name))
	end
end

bind(keys.startCountdown, startCountdown)
bind(keys.nextShot, function()
	moveShot(1)
end)
bind(keys.previousShot, function()
	moveShot(-1)
end)
bind(keys.cycleTimeScale, cycleTimeScale)
bind(keys.togglePanel, function()
	setPanelVisible(not panelVisible)
end)
bind(keys.markDone, markDone)
bind(keys.autoPerform, toggleAuto)
bind(keys.releaseStage, releaseStage)

local walkKeys: { [Enum.KeyCode]: boolean } = {}
for _, name in WalkData.cancelKeys do
	local code = keyCode(name)
	if code ~= nil then
		walkKeys[code] = true
	else
		warn(("[Capture] unknown walk key %s in dev.luau"):format(name))
	end
end

-- A movement key hands the walk to the player: the ring stays and the shot is asked for once the
-- root stands in it at rest, with the whole timeout from now.
local function takeOver()
	if phase ~= "Walking" or walkMode == "Manual" then
		return
	end
	walkMode = "Manual"
	walkElapsed = 0
	statusNote = walkNote()
	refreshPanel()
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	-- The control script binds the movement keys through ContextActionService, so they come
	-- processed: heard before the processed check.
	if walkKeys[input.KeyCode] then
		takeOver()
	end
	if processed then
		return
	end
	local fn = bindings[input.KeyCode]
	if fn ~= nil then
		fn()
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	if phase == "Countdown" then
		countdownRemaining -= dt
		if countdownRemaining <= 0 then
			startRecording()
		else
			countdownLabel.Text = tostring(math.ceil(countdownRemaining))
		end
	elseif phase == "Recording" then
		elapsed += dt
		frames += 1
		if confirmUntil ~= nil and os.clock() > (confirmUntil :: number) then
			confirmUntil = nil
		end
		stepPerform()
		writeCounter()
		writePrompt()
		if elapsed >= currentShot().seconds then
			-- The take stops itself at its target length.
			finish(true)
		end
	elseif phase == "Done" then
		doneTimer -= dt
		if doneTimer <= 0 then
			phase = "Idle"
			moveShot(1)
		end
	end

	if Steps[timeScaleIndex] ~= Dev.timeScale.default then
		reapplyTimer += dt
		if reapplyTimer >= Capture.timeScaleReapplySeconds then
			reapplyTimer = 0
			applyTimeScale()
		end
	end
end)

-- The walk ends unstaged: the ring goes and the panel says what failed.
local function walkFailed(root: BasePart?)
	local current = walk
	stopWalk()
	phase = "Idle"
	local where = "no character to walk"
	if root ~= nil and current ~= nil then
		local at = root.Position
		where = ("%.1f studs from the spot"):format(Vector3.new(at.X - current.x, 0, at.Z - current.z).Magnitude)
	end
	statusNote = if walkMode == "Manual"
		then ("Walk failed: not in the ring after %g s (%s); press %s to stage again"):format(
			WalkData.timeoutSeconds,
			where,
			keys.startCountdown
		)
		else ("Walk failed: the auto-walk did not reach the ring in %g s (%s); press %s to stage again"):format(
			WalkData.timeoutSeconds,
			where,
			keys.startCountdown
		)
	refreshPanel()
end

-- The walk into the ring, each frame after the control script's Move and before the character
-- controller reads MoveDirection (WalkData.renderOrder).
local function walkStep(dt: number)
	local current = walk
	if phase ~= "Walking" or current == nil then
		return
	end
	walkElapsed += dt * Steps[timeScaleIndex]
	local character = player.Character
	local root = if character ~= nil then character.PrimaryPart else nil
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if walkElapsed >= WalkData.timeoutSeconds then
		walkFailed(root)
		return
	end
	if root == nil or humanoid == nil then
		return
	end
	local at = root.Position
	if walkMode == "Auto" then
		local dx, dz = CaptureLogic.steer(current, at.X, at.Z, WalkData.waypointStuds, WalkData.arriveStuds)
		if dx ~= nil and dz ~= nil then
			humanoid:Move(Vector3.new(dx, 0, dz), false)
			return
		end
		-- At the spot: let go, and the two-step stop brings the body to rest.
		walkMode = "Settle"
	end
	local velocity = root.AssemblyLinearVelocity
	if Vector3.new(velocity.X, 0, velocity.Z).Magnitude > WalkData.restSpeed then
		return
	end
	local feet = at.Y - (humanoid.HipHeight + root.Size.Y / 2 + World.spawn.groundEpsilon)
	if walkMode == "Manual" and not CaptureLogic.inRing(current, at.X, feet, at.Z) then
		return
	end
	if CaptureLogic.askWait(lastAskAt, os.clock(), Capture.stage.requestsPerSecond) > 0 then
		return
	end
	-- At rest in the ring (or where the auto-walk let go): the ring goes and the shot is asked for
	-- again; a root still outside it gets a new walk.
	stopWalk()
	phase = "Staging"
	statusNote = nil
	refreshPanel()
	runStaging(currentShot(), stageToken)
end

pcall(function()
	RunService:BindToRenderStep(WALK_STEP_NAME, FrameOrder.priority(WalkData.renderOrder), walkStep)
end)

player.CharacterAdded:Connect(function()
	task.defer(applyTimeScale)
end)

refreshPanel()
