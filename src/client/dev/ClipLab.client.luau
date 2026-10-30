--!strict
--[[
	ClipLab (section 10 "Review loop"). Runs only in a place whose Workspace carries the ClipLab
	attribute (places/ClipLab.project.json). The server script (src/server/dev/ClipLab.server.luau)
	stages one rig per pedestal; this client lists every clip from ClipLibrary.all() grouped by
	rig, plays the selected clip in a loop at 0.25x / 0.5x / 1x with a frame counter, draws the
	six beats, the hit windows, the trail / smear spans and the other events on a timeline bar
	under the stage (ReviewMarkers), previews the hit-stop on HitWindowOpen, forwards TrailOn /
	SmearOn to the fx modules so the blade reads as it will in the game, and offers an "A/B with
	rest pose" toggle that alternates the clip with every joint at rest.

	The hit-stop preview never skips a clip frame. In the game a swing freezes on the frame its
	clock reaches the window's strike key (the contact moment) and the hit-stop stands in for the
	authored Hold after it (D-154: the clock skips up to the hit-stop's length of that Hold), so the
	blade holds the key's pose for max(hit-stop, hold) once; previewed that way the frame counter
	jumped over the Hold after every pause. The lab pauses on the strike key for what the hit-stop
	has beyond the Hold and then plays the whole authored Hold (ReviewMarkers.hitStopPreview,
	D-412): the same one still of max(hit-stop, hold) on the same pose, every clip frame shown. (It
	paused at the Hold's end before, on the next key's pose: a still the game never holds.)
	Stepping single frames shows every frame and previews no hit-stop.

	Every play from a new clip time (a loop's restart, a clip picked, a step back) clears the
	blade's trail, so no ribbon joins the clip's last pose to its first.

	The sword sits where the clip time says (ReviewMarkers.mountAt, D-050): on its sheath across
	the back before a Draw's WeaponDraw, in a sheathed walk or idle, and after a WeaponSheathe; in
	the hand otherwise. The lab reads the time, not the events, so a scrub backwards puts the
	sword back where it was.

	The lab owns the clock: Choreo is configured with silent frame signals before the first
	animator exists, and every step comes from this script (speed, pause, single frames), so what
	the frame counter says is exactly what the rig shows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dev = require(Shared.data.dev)

if workspace:GetAttribute(Dev.attributes.clipLab) ~= true then
	return
end

local Types = require(Shared.types)
local Combat = require(Shared.data.combat)
local ChoreoData = require(Shared.data.choreo)
local Joints = require(Shared.choreo.Joints)
local Client = script.Parent.Parent
local El = require(Client.ui.lib.El)
local Siblings = require(Client.controllers.Siblings)
local Choreo = require(Client.choreo.Choreo)
local ClipLibrary = require(Client.choreo.ClipLibrary)
local WeaponMount = require(Client.choreo.WeaponMount)
local ReviewMarkers = require(script.Parent.ReviewMarkers)
local LabKeys = require(script.Parent.LabKeys)

local Trails, hasTrails = Siblings.load(Client, "fx.Trails")
local Smear, hasSmear = Siblings.load(Client, "fx.Smear")

local Lab = Dev.clipLab
local PanelData = Lab.panel
local TimelineData = Lab.timeline
local CameraData = Lab.camera
local FRAME = 1 / Dev.review.fps

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- The lab steps every animator itself: silence the engine's frame signals before any animator.
local silent = {
	Connect = function()
		return { Disconnect = function() end, Connected = false }
	end,
}
Choreo.configure({ renderStepped = silent, heartbeat = silent })

-- ---------------------------------------------------------------------------------------------
-- Rigs on stage
-- ---------------------------------------------------------------------------------------------

local rigModels: { [string]: Model } = {}

local stage = workspace:WaitForChild(Lab.stageFolderName, Lab.stageWaitSeconds)
if stage ~= nil then
	for _, child in stage:GetChildren() do
		local rig = child:GetAttribute(Lab.rigAttribute)
		if child:IsA("Model") and typeof(rig) == "string" then
			rigModels[rig] = child
		end
	end
	stage.ChildAdded:Connect(function(child: Instance)
		local rig = child:GetAttribute(Lab.rigAttribute)
		if child:IsA("Model") and typeof(rig) == "string" then
			rigModels[rig] = child
		end
	end)
else
	warn(("[ClipLab] %s did not appear; is ClipLab.server.luau in the build?"):format(Lab.stageFolderName))
end

local character = player.Character or player.CharacterAdded:Wait()
rigModels.PlayerR15 = character
Choreo.setLocalModel(character)
player.CharacterAdded:Connect(function(newCharacter: Model)
	rigModels.PlayerR15 = newCharacter
	Choreo.setLocalModel(newCharacter)
end)

-- ---------------------------------------------------------------------------------------------
-- Clip list grouped by rig
-- ---------------------------------------------------------------------------------------------

type Entry = { id: string, rig: string }

local entries: { Entry } = {}
do
	local byRig: { [string]: { string } } = {}
	local rigOrder: { string } = {}
	for _, id in ClipLibrary.all() do
		local ok, clip = pcall(ClipLibrary.get, id)
		if not ok then
			warn(("[ClipLab] %s failed to load: %s"):format(id, tostring(clip)))
			continue
		end
		local rig = (clip :: Types.ClipDef).rig
		if byRig[rig] == nil then
			byRig[rig] = {}
			table.insert(rigOrder, rig)
		end
		table.insert(byRig[rig], id)
	end
	-- Pedestal order first (player, boar, kobold), then any other rig alphabetically.
	local ordered: { string } = {}
	for _, pedestal in Lab.rigs do
		if byRig[pedestal.rig] ~= nil then
			table.insert(ordered, pedestal.rig)
		end
	end
	table.sort(rigOrder)
	for _, rig in rigOrder do
		if table.find(ordered, rig) == nil then
			table.insert(ordered, rig)
		end
	end
	for _, rig in ordered do
		for _, id in byRig[rig] do
			table.insert(entries, { id = id, rig = rig })
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Playback state
-- ---------------------------------------------------------------------------------------------

local selected = 0
local clip: Types.ClipDef? = nil
local animator: Choreo.Animator? = nil
local handle: Choreo.Handle? = nil
local mount: WeaponMount.WeaponMount? = nil -- the lab rig's sword: hand or back
local speed = Lab.defaultSpeed
local playing = true
local abEnabled = false
local abRest = false
local abTimer = 0
local hitStopEnabled = Lab.hitStopPreview
-- A hit-stop preview waiting for its strike key: the clip time it pauses at and the frames the
-- hit-stop has beyond the authored Hold after it.
local pendingStop: { at: number, frames: number }? = nil
-- Clip seconds the hit-stop preview still holds the rig. The lab owns the clock, so it holds by
-- not stepping: a Mixer hit-stop would also let its clock skip the authored Hold after the key.
local labHold = 0
local connectedAnimators: { [Choreo.Animator]: boolean } = {}
local yaw = CameraData.startYaw
local orbitDirection = 0
local cameraPosition: Vector3? = nil

-- ---------------------------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------------------------

local function text(props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		FontFace = El.font("system"),
		TextSize = PanelData.textSize,
		TextColor3 = El.color(PanelData.textToken),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}
	for key, value in props do
		merged[key] = value
	end
	return El.new("TextLabel", merged) :: TextLabel
end

local function button(label: string, order: number, onClick: () -> ()): TextButton
	local control = El.new("TextButton", {
		Size = UDim2.fromOffset(PanelData.buttonWidth, PanelData.controlsHeight - PanelData.buttonGap),
		BackgroundColor3 = El.color(PanelData.backgroundToken),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		FontFace = El.font("system", "Bold"),
		TextSize = PanelData.textSize,
		TextColor3 = El.color(PanelData.textToken),
		Text = label,
		LayoutOrder = order,
	}, {
		El.new("UICorner", { CornerRadius = UDim.new(0, PanelData.cornerRadius) }),
		El.new("UIStroke", { Color = El.color(PanelData.borderToken), Thickness = 1 }),
	}) :: TextButton
	control.Activated:Connect(onClick)
	return control
end

local gui = El.new("ScreenGui", {
	Name = PanelData.screenGuiName,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = PanelData.displayOrder,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}) :: ScreenGui

-- Left column: title, readout, controls, problems, the clip list.
local column = El.new("Frame", {
	Name = "Column",
	Position = UDim2.fromOffset(PanelData.margin, PanelData.margin),
	Size = UDim2.new(
		0,
		PanelData.listWidth,
		1,
		-(PanelData.margin * 2 + TimelineData.height + TimelineData.bottomMargin)
	),
	BackgroundColor3 = El.color(PanelData.backgroundToken),
	BackgroundTransparency = PanelData.backgroundTransparency,
	BorderSizePixel = 0,
}, {
	El.new("UICorner", { CornerRadius = UDim.new(0, PanelData.cornerRadius) }),
	El.new("UIStroke", { Color = El.color(PanelData.borderToken), Thickness = 1 }),
	El.new("UIPadding", {
		PaddingTop = UDim.new(0, PanelData.padding),
		PaddingBottom = UDim.new(0, PanelData.padding),
		PaddingLeft = UDim.new(0, PanelData.padding),
		PaddingRight = UDim.new(0, PanelData.padding),
	}),
	El.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, PanelData.buttonGap) }),
}) :: Frame

local title = text({
	Size = UDim2.new(1, 0, 0, PanelData.headerHeight),
	FontFace = El.font("system", "Bold"),
	TextSize = PanelData.titleTextSize,
	TextColor3 = El.color(PanelData.selectedToken),
	Text = "ClipLab",
	LayoutOrder = 1,
})
local readout = text({ Size = UDim2.new(1, 0, 0, PanelData.readoutHeight), LayoutOrder = 2 })
local controls = El.new("Frame", {
	Size = UDim2.new(1, 0, 0, PanelData.controlsHeight * PanelData.controlRows),
	BackgroundTransparency = 1,
	LayoutOrder = 3,
}, {
	El.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(PanelData.buttonWidth, PanelData.controlsHeight - PanelData.buttonGap),
		CellPadding = UDim2.fromOffset(PanelData.buttonGap, PanelData.buttonGap),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
}) :: Frame
local problems = text({
	Size = UDim2.new(1, 0, 0, PanelData.problemsHeight),
	TextColor3 = El.color(PanelData.dimToken),
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextTruncate = Enum.TextTruncate.None,
	LayoutOrder = 4,
})
local list = El.new("ScrollingFrame", {
	Size = UDim2.new(
		1,
		0,
		1,
		-(
				PanelData.headerHeight
				+ PanelData.readoutHeight
				+ PanelData.controlsHeight * PanelData.controlRows
				+ PanelData.problemsHeight
				+ PanelData.buttonGap * 4
			)
	),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = PanelData.buttonGap,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	LayoutOrder = 5,
}, {
	El.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
}) :: ScrollingFrame

title.Parent = column
readout.Parent = column
controls.Parent = column
problems.Parent = column
list.Parent = column
column.Parent = gui

-- Clip rows.
local rows: { TextButton } = {}
do
	local order = 0
	local lastRig: string? = nil
	for index, entry in entries do
		if entry.rig ~= lastRig then
			lastRig = entry.rig
			order += 1
			local header = text({
				Size = UDim2.new(1, 0, 0, PanelData.headerHeight),
				FontFace = El.font("system", "Bold"),
				TextColor3 = El.color(PanelData.dimToken),
				Text = entry.rig,
				LayoutOrder = order,
			})
			header.Parent = list
		end
		order += 1
		local row = El.new("TextButton", {
			Size = UDim2.new(1, 0, 0, PanelData.rowHeight),
			BackgroundColor3 = El.color(PanelData.selectedToken),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			FontFace = El.font("system"),
			TextSize = PanelData.textSize,
			TextColor3 = El.color(PanelData.textToken),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "  " .. (entry.id:match("[^/]+$") or entry.id),
			LayoutOrder = order,
		}) :: TextButton
		rows[index] = row
		row.Parent = list
	end
end

-- Timeline bar at the bottom.
local timeline = El.new("Frame", {
	Name = "Timeline",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -TimelineData.bottomMargin),
	Size = UDim2.new(1, -TimelineData.sideMargin * 2, 0, TimelineData.height),
	BackgroundColor3 = El.color(TimelineData.backgroundToken),
	BackgroundTransparency = TimelineData.backgroundTransparency,
	BorderSizePixel = 0,
}, {
	El.new("UICorner", { CornerRadius = UDim.new(0, PanelData.cornerRadius) }),
}) :: Frame
local lanes: { [string]: Frame } = {}
do
	local laneTop = (
		TimelineData.height
		- (#TimelineData.lanes * (TimelineData.laneHeight + TimelineData.laneGap) - TimelineData.laneGap)
	) / 2
	for index, laneName in TimelineData.lanes do
		local y = laneTop + (index - 1) * (TimelineData.laneHeight + TimelineData.laneGap)
		local laneLabel = text({
			Position = UDim2.fromOffset(PanelData.buttonGap, y),
			Size = UDim2.fromOffset(TimelineData.labelWidth - PanelData.buttonGap, TimelineData.laneHeight),
			TextSize = TimelineData.labelTextSize,
			TextColor3 = El.color(PanelData.dimToken),
			Text = laneName,
		})
		laneLabel.Parent = timeline
		local lane = El.new("Frame", {
			Name = laneName,
			Position = UDim2.fromOffset(TimelineData.labelWidth, y),
			Size = UDim2.new(1, -(TimelineData.labelWidth + PanelData.buttonGap), 0, TimelineData.laneHeight),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}) :: Frame
		lane.Parent = timeline
		lanes[laneName] = lane
	end
end
local playhead = El.new("Frame", {
	Name = "Playhead",
	Position = UDim2.fromOffset(TimelineData.labelWidth, 0),
	Size = UDim2.new(0, TimelineData.playheadWidth, 1, 0),
	BackgroundColor3 = El.color(TimelineData.playheadToken),
	BorderSizePixel = 0,
	ZIndex = 2,
}) :: Frame
playhead.Parent = timeline
local frameCounter = text({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(1, -TimelineData.sideMargin + PanelData.margin, 1, -TimelineData.bottomMargin),
	Size = UDim2.fromOffset(TimelineData.sideMargin - PanelData.margin * 2, TimelineData.height),
	FontFace = El.font("system", "Bold"),
	TextSize = PanelData.titleTextSize,
	TextColor3 = El.color(PanelData.selectedToken),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	TextWrapped = true,
	TextTruncate = Enum.TextTruncate.None,
})
frameCounter.Parent = gui
timeline.Parent = gui
gui.Parent = playerGui

local markerFrames: { Frame } = {}

local function clearMarkers()
	for _, frame in markerFrames do
		frame:Destroy()
	end
	table.clear(markerFrames)
end

-- Builds the marker frames for the selected clip (once per selection, not per frame).
local function drawMarkers(def: Types.ClipDef)
	clearMarkers()
	if def.duration <= 0 then
		return
	end
	for _, marker in ReviewMarkers.markers(def) do
		local lane = lanes[marker.lane]
		if lane == nil then
			continue
		end
		local startFraction = ReviewMarkers.fractionOf(marker.start, def.duration)
		local widthFraction = ReviewMarkers.fractionOf(marker.finish, def.duration) - startFraction
		local frame = El.new("Frame", {
			Name = marker.kind,
			Position = UDim2.fromScale(startFraction, 0),
			Size = UDim2.new(widthFraction, TimelineData.minMarkerWidth, 1, 0),
			BackgroundColor3 = El.color(marker.token),
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, {
			text({
				Size = UDim2.fromScale(1, 1),
				TextSize = TimelineData.labelTextSize,
				TextColor3 = El.color(TimelineData.backgroundToken),
				Text = marker.label,
			}),
		}) :: Frame
		frame.Parent = lane
		table.insert(markerFrames, frame)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Playback
-- ---------------------------------------------------------------------------------------------

local function modelFor(rig: string): Model?
	return rigModels[rig]
end

-- Every joint of the rig, Motor6D or AnimationConstraint (the player's own character carries
-- AnimationConstraints under the Avatar Joint Upgrade). Cleared on every clip selection.
local motorCache: { [Model]: { Joints.Joint } } = {}

local function motorsOf(model: Model): { Joints.Joint }
	local cached = motorCache[model]
	if cached ~= nil then
		return cached
	end
	local motors = Joints.list(model)
	motorCache[model] = motors
	return motors
end

local function restPose(model: Model)
	for _, motor in motorsOf(model) do
		Joints.setTransform(motor, CFrame.identity)
	end
end

-- clip id -> the kind its TrailOn named; TrailOff carries no kind and must turn the same one off.
local trailOnKinds: { [string]: string } = {}

local function trailKind(def: Types.ClipDef, event: Types.ClipEvent): string
	local data = event.data
	if data ~= nil and typeof(data.kind) == "string" then
		trailOnKinds[def.id] = data.kind
		return data.kind
	end
	local remembered = trailOnKinds[def.id]
	if remembered ~= nil then
		return remembered
	end
	return if def.id:find("Basic", 1, true) then "Basic" else "Art"
end

local function onClipEvent(target: Choreo.Animator, clipId: string, event: Types.ClipEvent)
	local def = clip
	if def == nil or target ~= animator or clipId ~= def.id then
		return
	end
	local model = target.model
	if event.kind == "TrailOn" and hasTrails then
		Trails.setActive(model, true, trailKind(def, event))
	elseif event.kind == "TrailOff" and hasTrails then
		Trails.setActive(model, false, trailKind(def, event))
	elseif event.kind == "SmearOn" then
		-- The smear frames run the trail at full width (section 10 beat 3), as Replication does.
		if hasTrails then
			Trails.setActive(model, true, "Smear")
		end
		if hasSmear then
			local axis = if event.data ~= nil then event.data.axis else nil
			Smear.apply(model, true, axis)
		end
	elseif event.kind == "SmearOff" then
		if hasTrails then
			Trails.setActive(model, false, "Smear")
		end
		if hasSmear then
			Smear.apply(model, false)
		end
	elseif event.kind == "HitWindowOpen" and hitStopEnabled and playing then
		local tier: Types.HitStopTier = def.hitStop or "Normal"
		local frames = Combat.hitStopFrames[tier]
		local current = handle
		-- Where the game holds it (ReviewMarkers.hitStopPreview): the strike key, for what the
		-- hit-stop has beyond the authored Hold after it.
		local at, held = ReviewMarkers.hitStopPreview(def, if current ~= nil then current.time else event.time, frames)
		if at == nil then
			pendingStop = nil
		elseif current ~= nil and at > current.time then
			pendingStop = { at = at, frames = held }
		else
			pendingStop = nil
			labHold = math.max(labHold, held * ChoreoData.frameSeconds)
		end
	end
end

local function animatorFor(model: Model): Choreo.Animator
	local target = Choreo.get(model)
	if not connectedAnimators[target] then
		connectedAnimators[target] = true
		target.events:Connect(function(clipId: string, event: Types.ClipEvent)
			onClipEvent(target, clipId, event)
		end)
		if hasTrails then
			Trails.attach(model)
		end
	end
	return target
end

local function quietFx(model: Model)
	if hasTrails then
		Trails.setActive(model, false, "Art")
		Trails.setActive(model, false, "Basic")
		Trails.setActive(model, false, "Smear")
	end
	if hasSmear then
		Smear.apply(model, false)
	end
end

-- Drops every segment of the blade's trail (the ribbon and the engine Trail), so a play from a
-- new clip time never draws a ribbon from the pose it left: Trails forgets the rig (its ribbon
-- released, its tip ring gone), the engine Trail's segments are cleared, and the rig is tracked
-- again from this pose.
local function clearTrail(model: Model)
	if not hasTrails then
		return
	end
	Trails.detach(model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Trail") then
			descendant:Clear()
		end
	end
	Trails.attach(model)
end

-- Puts the sword where the clip time says. When the place changes, the frame is posed again so
-- the Weapon joint is pinned (back) or free (hand) in the pose on screen.
local function syncMount()
	local def = clip
	local target = animator
	local current = handle
	local sword = mount
	if def == nil or target == nil or current == nil or sword == nil then
		return
	end
	local place: WeaponMount.Place = ReviewMarkers.mountAt(def, current.time)
	if sword:get() ~= place then
		sword:set(place)
		target:step(0)
	end
end

local function play(startTime: number)
	local def = clip
	local target = animator
	if def == nil or target == nil then
		return
	end
	quietFx(target.model)
	clearTrail(target.model)
	pendingStop = nil
	labHold = 0
	handle = target:play(def.id, { startTime = startTime, blendIn = 0, blendOut = 0 })
	target:step(0)
	syncMount()
end

local function refreshRows()
	for index, row in rows do
		local isSelected = index == selected
		row.BackgroundTransparency = if isSelected then 0 else 1
		row.TextColor3 = El.color(if isSelected then PanelData.backgroundToken else PanelData.textToken)
	end
end

local function selectClip(index: number)
	if #entries == 0 then
		return
	end
	index = (index - 1) % #entries + 1
	local previous = animator
	if previous ~= nil and handle ~= nil then
		previous:stop(handle, 0)
		quietFx(previous.model)
	end
	local oldMount = mount
	if oldMount ~= nil then
		oldMount:destroy()
		mount = nil
	end
	selected = index
	local entry = entries[index]
	local def = ClipLibrary.get(entry.id)
	clip = def
	local model = modelFor(def.rig)
	if model == nil then
		animator = nil
		handle = nil
		problems.Text = ("No %s rig on stage for %s"):format(def.rig, def.id)
		clearMarkers()
		refreshRows()
		return
	end
	animator = animatorFor(model)
	mount = WeaponMount.new(animator, model)
	motorCache[model] = nil
	abRest = false
	abTimer = 0
	play(0)
	drawMarkers(def)
	local found = ReviewMarkers.problems(def)
	problems.Text = if #found == 0 then "No problems found by the review rules." else table.concat(found, "\n")
	refreshRows()
	if selected <= #rows then
		local row = rows[selected]
		list.CanvasPosition = Vector2.new(
			0,
			math.max(
				0,
				row.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y - list.AbsoluteSize.Y / 2
			)
		)
	end
end

local function stepFrames(count: number)
	local target = animator
	local current = handle
	local def = clip
	if target == nil or current == nil or def == nil then
		return
	end
	if count >= 0 then
		-- Single frames show every clip frame: no hit-stop preview waits for them.
		pendingStop = nil
		labHold = 0
		for _ = 1, count do
			target:step(FRAME)
		end
		syncMount()
	else
		local time = current.time + count * FRAME
		if def.loop and def.duration > 0 then
			time = time % def.duration
		else
			time = math.max(0, time)
		end
		play(time)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------------------------------

local speedButtons: { [number]: TextButton } = {}
local playButton: TextButton
local abButton: TextButton
local hitStopButton: TextButton

local function refreshControls()
	for value, control in speedButtons do
		local active = value == speed
		control.BackgroundColor3 = El.color(if active then PanelData.selectedToken else PanelData.backgroundToken)
		control.TextColor3 = El.color(if active then PanelData.backgroundToken else PanelData.textToken)
	end
	playButton.Text = if playing then "Pause" else "Play"
	abButton.BackgroundColor3 = El.color(if abEnabled then PanelData.selectedToken else PanelData.backgroundToken)
	abButton.TextColor3 = El.color(if abEnabled then PanelData.backgroundToken else PanelData.textToken)
	hitStopButton.BackgroundColor3 =
		El.color(if hitStopEnabled then PanelData.selectedToken else PanelData.backgroundToken)
	hitStopButton.TextColor3 = El.color(if hitStopEnabled then PanelData.backgroundToken else PanelData.textToken)
end

local function setSpeed(value: number)
	speed = value
	refreshControls()
end

local function togglePlaying()
	playing = not playing
	refreshControls()
end

local function toggleAb()
	abEnabled = not abEnabled
	abTimer = 0
	if not abEnabled and abRest then
		abRest = false
		local target = animator
		if target ~= nil then
			target:step(0)
			syncMount()
		end
	end
	refreshControls()
end

local function toggleHitStop()
	hitStopEnabled = not hitStopEnabled
	refreshControls()
end

do
	local order = 0
	for _, value in Lab.speeds do
		order += 1
		local control = button(("%gx"):format(value), order, function()
			setSpeed(value)
		end)
		speedButtons[value] = control
		control.Parent = controls
	end
	order += 1
	playButton = button("Pause", order, togglePlaying)
	playButton.Parent = controls
	order += 1
	button("< frame", order, function()
		stepFrames(-1)
	end).Parent = controls
	order += 1
	button("frame >", order, function()
		stepFrames(1)
	end).Parent = controls
	order += 1
	button("Restart", order, function()
		play(0)
	end).Parent = controls
	order += 1
	abButton = button("A/B rest", order, toggleAb)
	abButton.Parent = controls
	order += 1
	hitStopButton = button("Hit-stop", order, toggleHitStop)
	hitStopButton.Parent = controls
end

for index, row in rows do
	row.Activated:Connect(function()
		selectClip(index)
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Hotkeys
-- ---------------------------------------------------------------------------------------------

local function keyCode(name: string): Enum.KeyCode?
	local ok, result = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return if ok then result else nil
end

local bindings: { [Enum.KeyCode]: LabKeys.Binding } = {}
local function bind(name: string, fn: () -> ())
	local code = keyCode(name)
	if code ~= nil then
		bindings[code] = { pressed = fn }
	else
		warn(("[ClipLab] unknown key %s in dev.luau"):format(name))
	end
end
local function bindHeld(name: string, fn: (down: boolean) -> ())
	local code = keyCode(name)
	if code ~= nil then
		bindings[code] = { held = fn }
	end
end

local keys = Lab.hotkeys
bind(keys.speedSlow, function()
	setSpeed(Lab.speeds[1])
end)
bind(keys.speedHalf, function()
	setSpeed(Lab.speeds[2])
end)
bind(keys.speedFull, function()
	setSpeed(Lab.speeds[#Lab.speeds])
end)
bind(keys.playPause, togglePlaying)
bind(keys.stepBack, function()
	stepFrames(-1)
end)
bind(keys.stepForward, function()
	stepFrames(1)
end)
bind(keys.restart, function()
	play(0)
end)
bind(keys.abToggle, toggleAb)
bind(keys.hitStopToggle, toggleHitStop)
bind(keys.previousClip, function()
	selectClip(selected - 1)
end)
bind(keys.nextClip, function()
	selectClip(selected + 1)
end)
bindHeld(keys.orbitLeft, function(down: boolean)
	orbitDirection = if down then -1 elseif orbitDirection < 0 then 0 else orbitDirection
end)
bindHeld(keys.orbitRight, function(down: boolean)
	orbitDirection = if down then 1 elseif orbitDirection > 0 then 0 else orbitDirection
end)

-- Above the default character scripts, which bind the arrows and Space too (LabKeys, D-413).
LabKeys.bind(ContextActionService, "ClipLab", (Enum.ContextActionPriority :: any)[Lab.actionPriority].Value, bindings)

-- ---------------------------------------------------------------------------------------------
-- Camera: an orbit around the selected rig's pedestal
-- ---------------------------------------------------------------------------------------------

local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = CameraData.fov

local function focusPoint(): Vector3
	local target = animator
	local model: Model? = if target ~= nil then target.model else modelFor("PlayerR15")
	local root: BasePart? = if model ~= nil
		then (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart"))
		else nil
	if root == nil then
		return Vector3.new(0, CameraData.focusHeight, 0)
	end
	local base = Vector3.new(root.Position.X, 0, root.Position.Z)
	return base + Vector3.new(0, CameraData.focusHeight, 0)
end

local function updateCamera(dt: number)
	yaw += orbitDirection * CameraData.orbitDegreesPerSecond * dt
	local focus = focusPoint()
	local radians = math.rad(yaw)
	-- Yaw 0 looks at the rig's face: the rig faces -Z, so the camera sits on its -Z side.
	local offset = Vector3.new(
		math.sin(radians) * CameraData.distance,
		CameraData.height,
		-math.cos(radians) * CameraData.distance
	)
	local wanted = focus + offset
	local current = cameraPosition
	if current == nil then
		current = wanted
	else
		local alpha = 1 - math.exp(-dt / CameraData.lag)
		current = current:Lerp(wanted, alpha)
	end
	cameraPosition = current
	camera.CFrame = CFrame.lookAt(current :: Vector3, focus)
end

-- ---------------------------------------------------------------------------------------------
-- The frame step
-- ---------------------------------------------------------------------------------------------

local function readoutText(): string
	local def = clip
	local current = handle
	if def == nil or current == nil then
		return "Select a clip"
	end
	local state = if abRest then "rest pose" elseif not playing then "paused" else "playing"
	local pauseNote = if labHold > 0 or (animator ~= nil and animator:isPaused()) then "  hit-stop" else ""
	return ("%s\n%gx  %s%s"):format(ReviewMarkers.frameLabel(current.time, def.duration), speed, state, pauseNote)
end

RunService.RenderStepped:Connect(function(dt: number)
	local def = clip
	local target = animator
	if def ~= nil and target ~= nil then
		if abEnabled then
			abTimer += dt
			if abTimer >= Lab.abInterval then
				abTimer -= Lab.abInterval
				abRest = not abRest
				if abRest then
					quietFx(target.model)
					restPose(target.model)
				else
					target:step(0)
					syncMount()
				end
			end
		end
		if abRest then
			restPose(target.model)
		elseif playing then
			local clipDt = dt * speed
			local pending = pendingStop
			local playingHandle = handle
			if labHold > 0 then
				local spent = math.min(labHold, clipDt)
				labHold -= spent
				clipDt -= spent
			end
			if pending ~= nil and playingHandle ~= nil and labHold <= 0 and clipDt > 0 then
				local reach = pending.at - playingHandle.time
				if reach < 0 then
					-- Already past the strike key (stepped there by hand): nothing left to preview.
					pendingStop = nil
				elseif reach <= clipDt then
					-- The strike key falls inside this frame: step to it, hold the excess there, and
					-- let the rest of the frame count toward that pause.
					if reach > 0 then
						Choreo.stepAll(reach)
					end
					pendingStop = nil
					clipDt -= reach
					labHold = pending.frames * ChoreoData.frameSeconds
					local spent = math.min(labHold, clipDt)
					labHold -= spent
					clipDt -= spent
				end
			end
			if clipDt > 0 then
				Choreo.stepAll(clipDt)
			end
			local current = handle
			if current ~= nil and (current.ended or current.done) then
				play(0)
			else
				syncMount()
			end
		end
		local current = handle
		if current ~= nil and def.duration > 0 then
			local fraction = ReviewMarkers.fractionOf(current.time, def.duration)
			playhead.Position = UDim2.new(
				fraction,
				TimelineData.labelWidth - fraction * (TimelineData.labelWidth + PanelData.buttonGap),
				0,
				0
			)
		end
		readout.Text = readoutText()
		frameCounter.Text = if current ~= nil
			then ("%s\n%s"):format(def.id, ReviewMarkers.frameLabel(current.time, def.duration))
			else def.id
	end
	updateCamera(dt)
end)

refreshControls()
if #entries > 0 then
	-- Open on the first attack clip so the six beats are on screen at once; else the first clip.
	local first = 1
	for index, entry in entries do
		local ok, def = pcall(ClipLibrary.get, entry.id)
		if ok and (def :: Types.ClipDef).attack then
			first = index
			break
		end
	end
	selectClip(first)
else
	problems.Text = "No clips under ReplicatedStorage.Shared.clips"
end
