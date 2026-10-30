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
	prompt naming the move and its moment. f counts the take's frames the game moves on: it holds
	on the frames that draw the local rig frozen (a hit-stop, as drawn: a frame after its flag,
	D-465, 327(a)). Beside f the
	counter shows r, the RenderStepped frames
	since the take started (never paused), and a small square in the bottom-right corner swaps
	between two colors of one brightness every rendered frame (capture.frameTick, D-336), so a
	recording shows each frame the engine drew. The take stops itself at its target length and is marked
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
	the two-step stop run as they do under the keys. It holds the sprint (walk.sprintAction, through
	InputController.handle as the key's binding does), so its stop is the Skid's: past the two-step
	stop's top speed the body carries nothing (D-059). The route's last leg runs along the spot's
	facing and the walk follows that line, so it turns the body the shot's way; it lets go when the
	spot is the stop's carry ahead (none at the sprint, the two-step stop's middle carry below it,
	or the carry the last sprint stop was seen to make where the engine slides one on). At rest more
	than walk.restStuds off the spot or walk.restDegrees off its facing, it corrects
	(walk.secondWalks times at most), never at the sprint (CW): on a part-pushed stick it walks to
	walk.correctBackStuds behind the spot along the approach, then creeps in along it ever slower
	and lets go as good as stopped. Once the body has stood at rest walk.askSettleSeconds (the
	server reads the root as it last replicated, which trails it: asked the moment it stopped, it
	was read mid-slide), the ring goes and the shot is asked for again (no faster than the server's
	rate): a root in the ring stages, one outside gets a new walk, which a root still beside the
	spot never runs from the route's first point (in the ring it starts at the rest check, the
	server having read it before it came to rest there; outside, it is a correction from where it
	stands). On the spot but off its facing alone (the Humanoid's turn trails the walk's move), it
	turns the root there at walk.faceDegreesPerSecond and stands walk.faceSettleSeconds instead. A
	movement key pressed after P, or held as the walk would steer, hands the walk to the
	player until P: the sprint lets go, the walk never moves the body again, the ring stays and the
	ask comes once the root stands in it at rest (a key during an ask between walks hands it over
	too); that ask stays until then, with no timeout (317(a)). A walk the world stops (its push has
	not moved the root walk.blockedStuds in walk.blockedSeconds: a wall across its leg) lets go of
	the sprint and the stick at once and tells the player to walk in; the ring and the ask stay,
	and it is never staged outside the ring (316(b)). J ends it with the field given back (the body
	stops as a let-go key stops it), P stages afresh, and walk.timeoutSeconds on the capture's clock
	ends a walk nobody walks (the auto-walk's, a blocked one the player never took) with a note
	naming what failed.
	No ask goes before the root has stood at rest walk.askSettleSeconds, unpushed by the walk: P
	pressed mid-walk lets the sprint go and asks once the body has stopped (asked at once, the
	server read it in the ring mid-skid and staged it as it slid on out, CW); a body that has not
	come to rest in capture.stageTimeoutSeconds is not asked for.

	A take that ends (at its length or by K) asks the server to hold its enemies where they stand
	(D-297), so nothing of the take acts between takes; the next staging clears them first.

	Auto-perform (U, off by default) plays the shot's perform list (dev.luau Perform, CF) through
	the real input path (InputController.handle, as a key's binding does), only at 1x:
	- a timed press (`at`): a key held `hold` seconds; a Move press holds the stick instead
	  (capture.perform.moveAction: Humanoid:Move on the camera's frame from this script's render
	  step, after the control script's, half pushed to walk), with the sprint key when it sprints;
	- a reaction (`onClip`): the press `lead` seconds before the hit window of a staged enemy's
	  attack clip as this client draws it (Replication.clipEvent; each later event of the clip sets
	  it again, and its attacker's hit-stop, HitConfirmed attackPause, moves it on as the client
	  holds the clip as long), a guard the client's latency lead earlier still, as the glint comes
	  (Telegraphs.glintLead, D-289), so it reaches the server as a press with no latency would;
	  on each play when it repeats, never past its `to` (nor its chain's steps, D-320); it may
	  lock that enemy on hearing it,
	  and a chain of presses follows it, each `delay` after the one before (the next Art of a cycle,
	  the lock on another enemy, a sprint that lets go in a basic's reach of the lock's target);
	- a standing rule (`every`): a basic on the lock's target in reach, or the lock back on an
	  enemy when it is off, every so often, never while a reaction waits or its chain runs.
	A lock press in a staged take acts on the staged enemy it names alone (D-290: it locks it, or
	lets it go when the lock is on it), never the lock key's cycle, which could step on to a field
	enemy nearer than it. A take that stops lets go of every key and the stick without acting: a
	held Art is cancelled before its key comes up, so the release launches nothing.

	Every key the panel presses goes through InputController.handle as the panel's own source
	(INPUT_SOURCE, D-338): the sprint is held per source, so the player's Shift tap during the
	walk's or the perform's sprint never lets go of the panel's.

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
local Telegraphs = require(Client.fx.Telegraphs)
local World = require(Shared.data.world)
local ChoreoData = require(Shared.data.choreo)
local ImpactData = require(Shared.data.impact)

local Choreo, hasChoreo = Siblings.load(Client, "choreo.Choreo")
local CharacterController = Siblings.load(Client, "controllers.CharacterController")

local Capture = Dev.capture
local PanelData = Capture.panel
local CounterData = Capture.counter
local TickData = Capture.frameTick
local PromptData = Capture.prompt
local WalkData = Capture.walk
local RingData = WalkData.ring
local Shots = Capture.shots
local Steps = Dev.timeScale.steps

type Phase = "Idle" | "Staging" | "Walking" | "Countdown" | "Recording" | "Done"
-- The walk into the stand ring: the auto-walk steering, a correction walking back onto the spot
-- (never at a sprint, CW), its let-go (waiting for the body to come to rest and stay so), the
-- walk the world stopped (it lets go and waits for the player), or the player walking it after a
-- movement key.
type WalkMode = "Auto" | "Correct" | "Face" | "Settle" | "Blocked" | "Manual"

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
-- RenderStepped frames since the take started, never paused (D-336): on from the first take's
-- start, set back to 0 at each take's start.
local rendered = 0
-- Whether this frame draws the local rig held (a hit-stop, or a hold waiting for its word): the
-- rig's step of the frame before froze it (D-465). Read in the walk's render step, before
-- every rig steps (327(a)): f counts only the frames the game moves on, so it holds through a
-- freeze while r counts on.
local rigFrozen = false
-- The local rig's animator and its running count of frozen steps (Choreo heldCount, D-354) at
-- each of the last impact.luau poseLagFrames + 1 walk steps, oldest first; a new animator (a
-- respawn) starts over.
local POSE_LAG: number = ImpactData.poseLagFrames
local frozenOf: any = nil
local frozenCounts: { number } = table.create(POSE_LAG + 1)
local ticking = false
local doneTimer = 0
local timeScaleIndex = 1
local panelVisible = true
local reapplyTimer = 0
local statusNote: string? = nil
-- The take reached its target length on the frame just counted (FK3): that frame is drawn with its
-- counter like every counted one, and the take ends on the next RenderStepped, so the panel never
-- shows on a counted frame.
local lastCounted = false
-- The staging this panel asked for last (a reply to an older one is ignored) and its target.
local stageToken = 0
local targetId: number? = nil
-- K short of the target: a second K before this clock ends the take unmarked.
local confirmUntil: number? = nil
-- Auto-perform: on or off, the take's timed presses left, the keys it holds down, its reactions
-- (clip-timed entries) and standing rules, the reaction's chain running (the step it is on, when
-- that goes down, and its Move while held), how often each cycling step has pressed, the chain's
-- Art key down and not yet up (EF) and the entry or step whose stick the walk's render step holds
-- (CF).
local autoOn = Capture.perform.defaultOn
local performing = false
local presses: { CaptureLogic.Press } = {}
local heldKeys: { [string]: boolean } = {}
local reactions: { CaptureLogic.Reaction } = {}
local standing: { CaptureLogic.Standing } = {}
type Chain = { steps: { CaptureLogic.PerformStep }, index: number, at: number?, entry: CaptureLogic.PerformEntry }
local chain: Chain? = nil
local chainMove: CaptureLogic.PerformStep? = nil
local chainMoveUntil = 0
local stepCounts: { [CaptureLogic.PerformStep]: number } = {}
type ChainArt = { action: string, step: CaptureLogic.PerformStep }
local chainArt: ChainArt? = nil
type Stick = { stick: { number }?, sprint: boolean? }
local stickHeld: Stick? = nil
local MOVE_ACTION = Capture.perform.moveAction
-- The source the panel's presses hold the sprint as (InputController.handle, D-338).
local INPUT_SOURCE = "CapturePanel"
-- Every staged enemy by stage.enemies index (the staging reply's ids), the target first.
local stagedIds: { number }? = nil
-- The mouse cursor as it was before the take hid it.
local cursorBefore: boolean? = nil
-- The walk into the stand ring a staging asked for, who walks it, how long it has run (on the
-- capture's clock), the ring's disc, and when this panel last asked the server anything.
local walk: CaptureLogic.Walk? = nil
local walkMode: WalkMode = "Auto"
local walkElapsed = 0
local ringPart: BasePart? = nil
local lastAskAt: number? = nil
-- The way up this staging's asks read (EF, CaptureLogic.wayUp): the least, nil until one was read.
local wayUp: number? = nil
-- Whether the auto-walk holds the sprint now, the corrections it has left this staging, how far
-- the spot was ahead when it let go and whether that let-go was a sprint's, the carry the last
-- sprint stop was seen to make (nil until one was: an engine that slides a stop on), and how
-- long (real seconds) the body has stood at rest.
local walkSprint = false
local secondWalksLeft = 0
local letGoAhead: number? = nil
local letGoSprint = false
local learnedCarry: number? = nil
local restFor = 0
-- When (os.clock) the root last moved or the walk last pushed it: no ask goes before it has stood
-- at rest walk.askSettleSeconds since. At rest here is slower than walk.restSpeed and than the
-- controller's standing speed too: let go in a correction's creep (P, J or a key), the two-step
-- stop carries the root on a step slower than restSpeed.
local movedAt = -math.huge
local STILL_SPEED = math.min(WalkData.restSpeed, ChoreoData.locomotion.idleSpeedThreshold)

-- The turn on the spot (walkMode "Face"): whether the root has reached the spot's facing, and the
-- real seconds it has stood there since.
local faceReached = false
local faceStood = 0

-- The blocked rule (walk.blockedSeconds, walk.blockedStuds): where the root stood when the walk's
-- push last moved it walk.blockedStuds (flat), and how long (on the capture's clock) the walk has
-- pushed since; nil while the walk does not push (a let-go, a turn on the spot, the player's walk).
local blockedFrom: Vector3? = nil
local blockedFor = 0

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
-- The render-frame tick (D-336): a square in the bottom-right corner, shown with the counter, its
-- color swapped every rendered frame (CaptureLogic.tickToken).
local tickColors: { [string]: Color3 } = {}
for _, token in TickData.tokens do
	tickColors[token] = El.color(token)
end
local frameTick = El.new("Frame", {
	Name = "FrameTick",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -TickData.margin, 1, -TickData.margin),
	Size = UDim2.fromOffset(TickData.size, TickData.size),
	BackgroundColor3 = tickColors[CaptureLogic.tickToken(0, TickData.tokens)],
	BorderSizePixel = 0,
	Visible = false,
}) :: Frame
frameTick.Parent = gui
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
		rendered = rendered,
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

-- This client's server clock (workspace:GetServerTimeNow, the clock a request's clientTime is
-- read on); nil where there is none.
local function serverNow(): number?
	local ok, now = pcall(function(): number
		return workspace:GetServerTimeNow()
	end)
	return if ok and typeof(now) == "number" then now else nil
end

-- Asks the staging remote; nil when this place has none (outside Studio). Each reply says when the
-- server got the ask (DevStage receivedAt): the least way up of a staging's asks (a new staging
-- starts afresh, so a slower link shows at once) is the lead the auto guard takes (EF).
local function ask(action: string, shotId: string?): any
	local remote = ReplicatedStorage:FindFirstChild(Capture.stage.remoteName)
	if remote == nil or not remote:IsA("RemoteFunction") then
		return nil
	end
	lastAskAt = os.clock()
	if action == "stage" then
		wayUp = nil
	end
	local sentAt = serverNow()
	local ok, reply = pcall(function(): any
		return (remote :: RemoteFunction):InvokeServer(action, shotId)
	end)
	if not ok then
		return { ok = false, error = tostring(reply) }
	end
	local sample = CaptureLogic.wayUp(sentAt, reply, Capture.perform.wayUpMax)
	if sample ~= nil then
		wayUp = math.min(wayUp or sample, sample)
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
	if walkMode == "Blocked" then
		local current = walk
		local character = player.Character
		local root = if character ~= nil then character.PrimaryPart else nil
		local where = ""
		if current ~= nil and root ~= nil then
			local at = root.Position
			where = (" %.1f studs from the spot"):format(Vector3.new(at.X - current.x, 0, at.Z - current.z).Magnitude)
		end
		return ("The walk is blocked%s: walk into the ring yourself (a movement key takes over, %s stages again, %s stops)"):format(
			where,
			keys.startCountdown,
			keys.releaseStage
		)
	end
	return ("Walk into the ring (walking there: a movement key takes over, %s stops)"):format(keys.releaseStage)
end

-- The feet's floor height under a root (the server's rule, DevStage).
local function feetOf(root: BasePart, humanoid: Humanoid): number
	return root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2 + World.spawn.groundEpsilon)
end

-- The staging asked for a walk into its ring (D-244). A root already beside the spot never runs
-- the route from its first point (that turned a body on the spot round to sprint back to the
-- approach, CW): in the ring (the server read it before it came to rest there) it starts at the
-- rest check, and outside it the walk is a correction from where it stands.
local function startWalk(asked: CaptureLogic.Walk)
	phase = "Walking"
	walk = asked
	restFor = 0
	blockedFrom = nil
	if walkMode ~= "Manual" then
		walkMode = "Auto"
		local character = player.Character
		local root = if character ~= nil then character.PrimaryPart else nil
		local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
		if root ~= nil and humanoid ~= nil then
			local at = root.Position
			local feet = feetOf(root, humanoid)
			if CaptureLogic.near(asked, at.X, feet, at.Z, WalkData.correctWithinStuds) then
				letGoAhead = nil
				asked.backed = false
				walkMode = if CaptureLogic.inRing(asked, at.X, feet, at.Z) then "Settle" else "Correct"
			end
		end
	end
	-- No lock: a lock would turn the body to face it and walk it slow.
	TargetController.clear()
	showRing(asked)
	statusNote = walkNote()
	refreshPanel()
end

-- Holds or lets go of the walk's sprint through the input path (as the sprint key's binding does).
local function holdSprint(on: boolean)
	if walkSprint == on then
		return
	end
	walkSprint = on
	InputController.handle(
		WalkData.sprintAction,
		if on then Enum.UserInputState.Begin else Enum.UserInputState.End,
		nil,
		INPUT_SOURCE
	)
end

local function stopWalk()
	walk = nil
	holdSprint(false)
	removeRing()
end

-- Asks the server to stage `shot` and frames it, or walks into its ring when it says so.
local function runStaging(shot: Dev.Shot, token: number)
	task.spawn(function()
		-- Never asked while the body moves, nor before the server's view of it has come to rest too
		-- (it reads the root as it last replicated): P pressed mid-walk asks once the stop is over.
		local deadline = os.clock() + Capture.stageTimeoutSeconds
		while os.clock() - movedAt < WalkData.askSettleSeconds do
			if os.clock() >= deadline then
				phase = "Idle"
				statusNote = ("Staging failed: the body did not come to rest in %g s; press %s again"):format(
					Capture.stageTimeoutSeconds,
					keys.startCountdown
				)
				refreshPanel()
				return
			end
			task.wait()
			if not stillStaging(token) then
				return
			end
		end
		-- No faster than the server's rate: P straight after a take (its hold just asked) stages,
		-- never "too many requests".
		local wait = CaptureLogic.askWait(lastAskAt, os.clock(), Capture.stage.requestsPerSecond)
		if wait > 0 then
			task.wait(wait)
			if not stillStaging(token) then
				return
			end
		end
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
		stagedIds = if reply ~= nil and typeof(reply.ids) == "table" then reply.ids else nil
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
	secondWalksLeft = WalkData.secondWalks
	letGoAhead = nil
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

-- How far (studs, flat) the lock's target stands from the local root, or nil with no lock.
local function lockDistance(): number?
	local id = lockedId()
	local record: any = if id ~= nil then EntityTracker.get(id) else nil
	local model = if record ~= nil then record.model else nil
	local part = if model ~= nil then model.PrimaryPart else nil
	local character = player.Character
	local root = if character ~= nil then character.PrimaryPart else nil
	if part == nil or root == nil then
		return nil
	end
	local offset = part.Position - root.Position
	return math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
end

-- Whether the lock's target stands within `studs` (flat); no limit is anywhere.
local function lockWithin(studs: number?): boolean
	if studs == nil then
		return true
	end
	local distance = lockDistance()
	return distance ~= nil and distance <= studs
end

-- One key down or up through the input path, as its binding does. The move action is the stick:
-- `stick` is the entry or step it holds (its sprint held with it). A lock press in a staged take
-- acts on staged enemy `enemy` alone (D-290: it locks it, or lets it go when the lock is on it,
-- never with `keep`); its key-up does nothing.
local function press(action: string, down: boolean, stick: Stick?, enemy: number?, keep: boolean?)
	if action == MOVE_ACTION then
		if down then
			stickHeld = stick
			if stick ~= nil and stick.sprint == true then
				press(WalkData.sprintAction, true)
			end
		elseif stickHeld == stick then
			stickHeld = nil
			if stick ~= nil and stick.sprint == true then
				press(WalkData.sprintAction, false)
			end
		end
		return
	end
	if action == "LockOn" then
		local id = CaptureLogic.enemyId(stagedIds, targetId, enemy)
		if id == nil and targetId ~= nil then
			return -- staged, but not that enemy
		end
		local how = CaptureLogic.lockPress(id, lockedId())
		if how ~= "Key" then
			if down and how == "Lock" then
				TargetController.lockOn(id)
			elseif down and keep ~= true then
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
	InputController.handle(
		action,
		if down then Enum.UserInputState.Begin else Enum.UserInputState.End,
		nil,
		INPUT_SOURCE
	)
end

-- Lets go of every key auto-perform holds, none acting on the way up (D-290): a held Art's hold is
-- cancelled first, so its key's release launches nothing; the key still comes up through the input
-- path, so the hold there ends too. The stick lets go with them.
local function releaseKeys()
	stickHeld = nil
	chain = nil
	chainMove = nil
	chainArt = nil
	for _, key in CaptureLogic.letGo(heldKeys, InputData.artSlot) do
		if key.slot ~= nil then
			Siblings.call(CharacterController, "cancelArt", key.slot)
		end
		InputController.handle(key.action, Enum.UserInputState.End, nil, INPUT_SOURCE)
	end
	table.clear(heldKeys)
end

local function armPerform(shot: Dev.Shot)
	performing = CaptureLogic.performs(autoOn, Steps[timeScaleIndex])
	presses = if performing then CaptureLogic.timedPresses(shot.perform) else {}
	reactions = if performing then CaptureLogic.reactions(shot.perform) else {}
	standing = if performing then CaptureLogic.standing(shot.perform) else {}
	chain = nil
	chainMove = nil
	chainArt = nil
	stickHeld = nil
	table.clear(stepCounts)
end

-- A reaction heard drops the chain running: the stick it holds lets go, and an Art key it holds
-- is cancelled and comes up at once, launching nothing (as a stopped take's, D-290), its turn of
-- the cycle given back, so the next chain presses it (EF: in Studio the boar's crouch was heard
-- with the third parry's Sharp Nail held; the dodge cleared the hold, Sharp Nail never came and
-- every later parry pressed the Art after the one meant). Its other keys come up at their time.
local function dropChain()
	local move = chainMove
	if move ~= nil then
		chainMove = nil
		press(MOVE_ACTION, false, move)
	end
	local held = chainArt
	chainArt = nil
	if held ~= nil and heldKeys[held.action] then
		local slot = InputData.artSlot(held.action)
		if slot ~= nil then
			Siblings.call(CharacterController, "cancelArt", slot)
		end
		heldKeys[held.action] = nil
		InputController.handle(held.action, Enum.UserInputState.End, nil)
		CaptureLogic.unqueue(presses, held.action)
		stepCounts[held.step] = math.max((stepCounts[held.step] or 1) - 1, 0)
	end
	chain = nil
end

-- The lead a guard reaction takes (CaptureLogic.hear): the way up this staging's asks read, else
-- the glint lead (Telegraphs.glintLead, D-289). The glint lead is the way down less this client's
-- clock lag, the least of the last few tells: a press needs the way up plus that lag, and after
-- the link slows the least is still the faster link's for a few tells (EF: at 0.1 s the parry
-- shot's guard reached the server after the hit).
local function guardLead(): number
	return if wayUp ~= nil then wayUp else Telegraphs.glintLead()
end

-- Whether the body could start a standing rule's action now (CaptureLogic.standingFree, EF).
local function bodyFree(action: string): boolean
	return CaptureLogic.standingFree(action, Siblings.call(CharacterController, "state"))
end

-- Whether a reaction waits for its moment or a chain runs: the standing rules wait.
local function busy(): boolean
	if chain ~= nil then
		return true
	end
	for _, reaction in reactions do
		if reaction.at ~= nil then
			return true
		end
	end
	return false
end

-- A key down now and up `hold` from now.
local function tap(action: string, hold: number, enemy: number?, keep: boolean?)
	press(action, true, nil, enemy, keep)
	if action ~= "LockOn" then
		CaptureLogic.enqueue(presses, { at = elapsed + hold, action = action, down = false })
	end
end

-- The chain on to its next step `delay` after now, or done.
local function nextStep(running: Chain)
	running.index += 1
	local step = running.steps[running.index]
	if step == nil then
		chain = nil
	else
		running.at = elapsed + step.delay
	end
end

local function stepChain()
	local running = chain
	if running == nil then
		return
	end
	local move = chainMove
	if move ~= nil then
		if elapsed >= chainMoveUntil or (move.within ~= nil and lockWithin(move.within)) then
			chainMove = nil
			press(MOVE_ACTION, false, move)
			nextStep(running)
		end
		return
	end
	local at = running.at
	if at == nil or elapsed < at then
		return
	end
	-- Nothing of the reaction goes down past its `to` (D-320), nor a step past its own (EF): the
	-- rest of the chain is dropped.
	local step = running.steps[running.index]
	if not CaptureLogic.inside(running.entry, elapsed) or not CaptureLogic.inside(step, elapsed) then
		dropChain()
		return
	end
	if step.action == MOVE_ACTION then
		chainMove = step
		chainMoveUntil = elapsed + step.hold
		running.at = nil
		press(MOVE_ACTION, true, step)
		return
	end
	local count = (stepCounts[step] or 0) + 1
	stepCounts[step] = count
	local action = CaptureLogic.cycleAction(step, count)
	tap(action, step.hold, step.enemy, true)
	if InputData.artSlot(action) ~= nil then
		chainArt = { action = action, step = step }
	end
	-- The next step counts its delay from this key's let-go.
	running.index += 1
	local following = running.steps[running.index]
	if following == nil then
		-- Done once the key is up: the standing rules wait for it.
		running.at = elapsed + step.hold
		running.steps = {}
	else
		running.at = elapsed + step.hold + following.delay
	end
end

local function stepPerform()
	if not performing then
		return
	end
	for _, due in CaptureLogic.due(presses, elapsed) do
		local held = chainArt
		if held ~= nil and not due.down and due.action == held.action then
			chainArt = nil
		end
		press(due.action, due.down, due.entry)
	end
	local running = chain
	if running ~= nil and #running.steps == 0 and elapsed >= (running.at or 0) then
		chain = nil
	end
	for _, reaction in reactions do
		local at = reaction.at
		if at ~= nil and elapsed >= at then
			local entry = reaction.entry
			if not CaptureLogic.inside(entry, elapsed) then
				-- Moved past its `to` by its attacker's hit-stop: it waits no more.
				reaction.at = nil
				continue
			end
			CaptureLogic.pressed(reaction)
			dropChain()
			tap(entry.action, entry.hold, entry.enemy, true)
			local steps = entry.chain
			if steps ~= nil and #steps > 0 then
				chain = { steps = steps, index = 1, at = elapsed + entry.hold + steps[1].delay, entry = entry }
			end
		end
	end
	stepChain()
	if busy() then
		return
	end
	for _, rule in standing do
		if not CaptureLogic.standingDue(rule, elapsed) then
			continue
		end
		local entry = rule.entry
		if entry.action == "LockOn" then
			-- The lock back on its enemy once it is lost; a lock that is on stays.
			if lockedId() == nil then
				rule.last = elapsed
				tap("LockOn", entry.hold, entry.enemy, true)
			end
		elseif lockWithin(entry.within) and bodyFree(entry.action) then
			-- Only a press the body can take spends the rule's beat (EF).
			rule.last = elapsed
			tap(entry.action, entry.hold)
		end
	end
end

-- The stick auto-perform holds, each frame of the take from the walk's render step: after the
-- control script's Move and before the character controller reads MoveDirection, as a held key's.
local function stickStep()
	local held = stickHeld
	local stick = if held ~= nil then held.stick else nil
	if not performing or stick == nil then
		return
	end
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return
	end
	local x, z = CaptureLogic.stickMove(stick)
	humanoid:Move(Vector3.new(x, 0, z), true)
end

-- What this client draws: each reaction hears its clip on its staged enemy, and sets its key
-- `lead` before the clip's hit window from whichever event comes (each later one moves it on),
-- a guard the way up earlier still (guardLead: the staging replies' way up, else the glint lead,
-- D-289, EF): it reaches the server that long after it leaves. One heard drops the chain running;
-- with `lock` the lock goes to its enemy.
Replication.clipEvent:Connect(function(record: any, clipId: string, event: any, jumped: boolean)
	if phase ~= "Recording" or not performing or jumped or record == nil then
		return
	end
	local clip: any = nil
	for _, reaction in reactions do
		local entry = reaction.entry
		if entry.onClip ~= clipId or record.id ~= CaptureLogic.enemyId(stagedIds, targetId, entry.enemy) then
			continue
		end
		if clip == nil then
			local ok, found = pcall(ClipLibrary.get, clipId)
			if not ok or found == nil then
				return
			end
			clip = found
		end
		if CaptureLogic.hear(reaction, clip.events, event.time, elapsed, guardLead()) then
			dropChain()
			if entry.lock == true and lockedId() ~= record.id then
				TargetController.lockOn(record.id)
			end
		end
	end
end)

-- A hit on a reaction's enemy mid-attack: the server paused its attack (attackPause) and this
-- client holds its clip as long, so the press waiting for it moves on with it.
Replication.hit:Connect(function(payload: any)
	if phase ~= "Recording" or not performing or typeof(payload) ~= "table" then
		return
	end
	local pause = payload.attackPause
	if typeof(pause) ~= "number" or pause <= 0 then
		return
	end
	for _, reaction in reactions do
		if payload.targetId == CaptureLogic.enemyId(stagedIds, targetId, reaction.entry.enemy) then
			CaptureLogic.pause(reaction, pause)
		end
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
	rendered = 0
	ticking = true
	frameTick.BackgroundColor3 = tickColors[CaptureLogic.tickToken(rendered, TickData.tokens)]
	confirmUntil = nil
	armPerform(shot)
	countdownLabel.Visible = false
	setPanelVisible(false)
	-- The text first: the counter never shows a blank frame.
	writeCounter()
	counter.Visible = true
	frameTick.Visible = true
	writePrompt()
	hideCursor()
	-- The staged enemies the shot lets go start now.
	task.spawn(ask, "go")
end

-- The take is over: the server holds its enemies where they stand (D-297), so nothing of it acts
-- between takes. A refusal (the rate, right after the "go") is asked again at the rate, for up to
-- stageTimeoutSeconds; a newer staging (P) or J owns the field from then and ends the asking.
local function holdTake(token: number)
	local deadline = os.clock() + Capture.stageTimeoutSeconds
	while true do
		local reply = ask("hold")
		if token ~= stageToken or reply == nil or reply.ok == true then
			return
		end
		if os.clock() >= deadline then
			statusNote = ("The take's enemies were not held: %s; press %s to clear them"):format(
				tostring(reply.error),
				keys.releaseStage
			)
			refreshPanel()
			return
		end
		task.wait(1 / Capture.stage.requestsPerSecond)
		if token ~= stageToken then
			return
		end
	end
end

-- Ends the take: marked done, or stopped short and unmarked. Its enemies stop at once (D-297).
local function finish(marked: boolean)
	if phase ~= "Recording" then
		return
	end
	lastCounted = false
	local shot = currentShot()
	releaseKeys()
	performing = false
	presses = {}
	reactions = {}
	standing = {}
	restoreCursor()
	prompt.Visible = false
	counter.Visible = false
	frameTick.Visible = false
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
	task.spawn(holdTake, stageToken)
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

-- A movement key hands the walk to the player until P: the sprint lets go, the ring stays and the
-- shot is asked for once the root stands in it at rest, with the whole timeout from now. A key
-- during an ask (P's, or one between walks) hands over the walk its reply asks for.
local function takeOver()
	if (phase ~= "Walking" and phase ~= "Staging") or walkMode == "Manual" then
		return
	end
	walkMode = "Manual"
	walkElapsed = 0
	restFor = 0
	holdSprint(false)
	if phase == "Walking" then
		statusNote = walkNote()
		refreshPanel()
	end
end

-- Whether a movement key is down now (one held from before the walk began hands it over too).
local function walkKeyDown(): boolean
	for code in walkKeys do
		if UserInputService:IsKeyDown(code) then
			return true
		end
	end
	return false
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
	-- Every rendered frame since the take started, whatever the phase (D-336).
	if ticking then
		rendered += 1
		frameTick.BackgroundColor3 = tickColors[CaptureLogic.tickToken(rendered, TickData.tokens)]
	end
	if phase == "Countdown" then
		countdownRemaining -= dt
		if countdownRemaining <= 0 then
			startRecording()
		else
			countdownLabel.Text = tostring(math.ceil(countdownRemaining))
		end
	elseif phase == "Recording" and lastCounted then
		-- The frame after the take's last counted frame (FK3): that one was drawn with its counter up
		-- and the panel hidden; the panel comes back on this one.
		finish(true)
	elseif phase == "Recording" then
		elapsed += dt
		if not rigFrozen then
			frames += 1
		end
		if confirmUntil ~= nil and os.clock() > (confirmUntil :: number) then
			confirmUntil = nil
		end
		stepPerform()
		writeCounter()
		writePrompt()
		if elapsed >= currentShot().seconds then
			-- The take stops itself at its target length: this frame is its last counted one, drawn
			-- like the others, and the next frame ends it (FK3).
			lastCounted = true
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
	statusNote = if walkMode == "Blocked"
		then ("Walk failed: the auto-walk was blocked and nobody walked in within %g s (%s); press %s to stage again"):format(
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

-- The blocked rule: the walk pushed the root this frame. True once it has pushed for
-- walk.blockedSeconds (on the capture's clock, as the walk's own clock runs) without the root
-- getting walk.blockedStuds (flat) from where it stood when the count began: the world holds it.
local function pushBlocked(at: Vector3, dt: number): boolean
	local from = blockedFrom
	if from == nil or Vector3.new(at.X - from.X, 0, at.Z - from.Z).Magnitude >= WalkData.blockedStuds then
		blockedFrom = at
		blockedFor = 0
		return false
	end
	blockedFor += dt * Steps[timeScaleIndex]
	return blockedFor >= WalkData.blockedSeconds
end

-- The world stopped the walk (a wall across its leg): it lets go of the sprint and the stick, the
-- body stops as a let-go key stops it, and the ring and the ask stay for the player to walk in.
local function walkBlocked()
	holdSprint(false)
	walkMode = "Blocked"
	blockedFrom = nil
	restFor = 0
	statusNote = walkNote()
	refreshPanel()
end

-- The walk into the ring, each frame after the control script's Move and before the character
-- controller reads MoveDirection (WalkData.renderOrder).
local function walkStep(dt: number)
	local current = walk
	if phase ~= "Walking" or current == nil then
		return
	end
	local scale = Steps[timeScaleIndex]
	walkElapsed += dt * scale
	local character = player.Character
	local root = if character ~= nil then character.PrimaryPart else nil
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	-- The timeout ends a walk nobody walks (D-244); one the player took over is theirs until they
	-- stand in the ring at rest, P or J (D-304, item 317(a)).
	if walkMode ~= "Manual" and walkElapsed >= WalkData.timeoutSeconds then
		walkFailed(root)
		return
	end
	if root == nil or humanoid == nil then
		return
	end
	if walkMode ~= "Manual" and walkKeyDown() then
		takeOver()
	end
	local at = root.Position
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if walkMode == "Auto" then
		-- The stop's carry at the walk's speed (in 1x terms: the slowed body stops as far), and half
		-- of this frame's step, so the body comes to rest within half a step of the spot.
		local skid = ChoreoData.locomotion.skidSpeedThreshold
		local sprint = speed / scale > skid
		local carry = if sprint and learnedCarry ~= nil
			then learnedCarry :: number
			else CaptureLogic.stopCarry(speed / scale, skid, WalkData.carrySeconds)
		local dx, dz = CaptureLogic.steer(
			current,
			at.X,
			at.Z,
			WalkData.waypointStuds,
			carry + speed * dt / 2,
			WalkData.lookaheadStuds
		)
		if dx ~= nil and dz ~= nil then
			if pushBlocked(at, dt) then
				walkBlocked()
				return
			end
			holdSprint(true)
			humanoid:Move(Vector3.new(dx, 0, dz), false)
			movedAt = os.clock()
			return
		end
		blockedFrom = nil
		-- The spot is the stop's carry ahead: let go, and the stop brings the body to rest.
		letGoAhead = CaptureLogic.ahead(current, at.X, at.Z)
		letGoSprint = sprint
		holdSprint(false)
		walkMode = "Settle"
		restFor = 0
	elseif walkMode == "Correct" then
		-- Back behind the spot and in along the approach at a walk, a stick pushed part way for the
		-- pace (the Humanoid walks at its WalkSpeed x the push).
		local dx, dz, pace = CaptureLogic.correctStep(
			current,
			at.X,
			at.Z,
			WalkData.correctBackStuds,
			WalkData.waypointStuds,
			WalkData.lookaheadStuds,
			WalkData.correctSpeed,
			WalkData.creepSeconds,
			WalkData.creepEndSpeed
		)
		if dx ~= nil and dz ~= nil and pace ~= nil then
			if pushBlocked(at, dt) then
				walkBlocked()
				return
			end
			local push = math.clamp(pace * scale / math.max(humanoid.WalkSpeed, 1e-3), 0, 1)
			humanoid:Move(Vector3.new(dx * push, 0, dz * push), false)
			movedAt = os.clock()
			return
		end
		blockedFrom = nil
		-- As good as stopped on the spot: let go (the two-step stop has nothing to carry).
		walkMode = "Settle"
		restFor = 0
	end
	if walkMode == "Face" then
		-- On the spot, short of its facing: the root turns there (in 1x terms, slowed with the
		-- capture), then stands so the server's view of it has the turn before the ask.
		if not faceReached then
			local look = root.CFrame.LookVector
			local turn, reached = CaptureLogic.faceTurn(
				current,
				look.X,
				look.Z,
				WalkData.faceDegreesPerSecond * Steps[timeScaleIndex] * dt
			)
			local frame = root.CFrame
			root.CFrame = CFrame.new(frame.Position) * CFrame.Angles(0, math.rad(turn), 0) * frame.Rotation
			faceReached = reached
			faceStood = 0
			return
		end
		faceStood += dt
		if faceStood < WalkData.faceSettleSeconds then
			return
		end
		walkMode = "Settle"
	end
	if speed > WalkData.restSpeed then
		restFor = 0
		return
	end
	if
		(walkMode == "Manual" or walkMode == "Blocked")
		and not CaptureLogic.inRing(current, at.X, feetOf(root, humanoid), at.Z)
	then
		restFor = 0
		return
	end
	if walkMode == "Settle" and restFor == 0 then
		-- Come to rest: judged where it stands.
		local seen = letGoAhead
		letGoAhead = nil
		if seen ~= nil and letGoSprint then
			-- How far this sprint stop carried the body on (none but the engine's own slide): the
			-- next let-go allows for it, up to the ring's radius.
			learnedCarry = math.clamp(seen - CaptureLogic.ahead(current, at.X, at.Z), 0, current.radius)
		end
		local look = root.CFrame.LookVector
		local studs, degrees = CaptureLogic.restOff(current, at.X, at.Z, look.X, look.Z)
		if degrees > WalkData.restDegrees and (studs <= WalkData.restStuds or secondWalksLeft == 0) then
			-- Off the facing alone (or with no walk left): a turn on the spot, never a walk. The
			-- Humanoid's own turn trails the walk's move, so a walk would leave the same again.
			faceReached = false
			faceStood = 0
			walkMode = "Face"
			return
		end
		if (studs > WalkData.restStuds or degrees > WalkData.restDegrees) and secondWalksLeft > 0 then
			-- Off the spot or its facing: a correction, walked (never the sprint and its turn-round).
			secondWalksLeft -= 1
			current.backed = false
			walkMode = "Correct"
			return
		end
	end
	-- Kept at rest long enough for the server's view of the root to have caught up with it before
	-- the ask (real seconds: the replication's lag does not slow with the capture's clock).
	restFor += dt
	if restFor < WalkData.askSettleSeconds then
		return
	end
	if CaptureLogic.askWait(lastAskAt, os.clock(), Capture.stage.requestsPerSecond) > 0 then
		return
	end
	-- At rest in the ring (or where the walk let go): the ring goes and the shot is asked for
	-- again; a root still outside it gets a new walk.
	stopWalk()
	phase = "Staging"
	statusNote = nil
	refreshPanel()
	runStaging(currentShot(), stageToken)
end

-- Notes when the root moves (faster than STILL_SPEED, flat), or is not there to stand.
local function trackRest()
	local character = player.Character
	local root = if character ~= nil then character.PrimaryPart else nil
	local velocity = if root ~= nil then root.AssemblyLinearVelocity else nil
	if velocity == nil or Vector3.new(velocity.X, 0, velocity.Z).Magnitude > STILL_SPEED then
		movedAt = os.clock()
	end
end

-- Whether this frame draws the local rig held (D-465). A frame draws the pose its rig's step of
-- impact.luau poseLagFrames frames ago wrote (D-353), so the hold as drawn runs that far behind
-- isPaused, which rises on the contact's own step (its picture still shows the swing arriving)
-- and falls a frame before the last still frame. Read before every rig steps, the step this
-- frame draws held the rig exactly when the count of frozen steps (heldCount) rose across it:
-- between the walk step poseLagFrames frames back and the one after it.
local function localFrozen(): boolean
	local character = player.Character
	local animator = if hasChoreo and character ~= nil then Choreo.find(character) else nil
	if animator ~= frozenOf then
		frozenOf = animator
		table.clear(frozenCounts)
	end
	if animator == nil then
		return false
	end
	table.insert(frozenCounts, animator:heldCount())
	if #frozenCounts > POSE_LAG + 1 then
		table.remove(frozenCounts, 1)
	end
	return #frozenCounts == POSE_LAG + 1 and frozenCounts[2] > frozenCounts[1]
end

-- The walk's render step: the walk into the ring, or auto-perform's stick while a take records.
-- It runs before every rig's step (walk.renderOrder), so the steps it reads are the ones this
-- frame draws.
local function inputStep(dt: number)
	rigFrozen = localFrozen()
	trackRest()
	if phase == "Recording" then
		stickStep()
	else
		walkStep(dt)
	end
end

pcall(function()
	RunService:BindToRenderStep(WALK_STEP_NAME, FrameOrder.priority(WalkData.renderOrder), inputStep)
end)

player.CharacterAdded:Connect(function()
	task.defer(applyTimeScale)
end)

refreshPanel()
