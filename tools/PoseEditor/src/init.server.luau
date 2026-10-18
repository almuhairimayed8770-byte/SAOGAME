--!strict
--[[
	Skyspire PoseEditor (section 10: "a Studio plugin that scrubs any clip, lets the user drag
	joints, and writes the data table back to the file").

	Build:  tools/build-plugin.sh  (rojo build tools/PoseEditor/PoseEditor.project.json -> .rbxm)
	Install: Studio > Plugins > Plugins Folder, drop the .rbxm in (docs/STUDIO_TASKS.md).

	With the Skyspire place open (Rojo synced so ReplicatedStorage.Shared exists) the toolbar button
	opens a dock widget. Type a clip id (player/OneHandedSword/Horizontal), Load, and the editor
	reads the module's Source through Serialize.parse (comments and joint order survive a save),
	drives the matching rig's Motor6D.Transform through ClipSampler while you scrub, attaches
	Handles / ArcHandles to the selected joint's part so drags move pos / rot in snapped steps,
	and lists keys (time, easing, note), events (time, kind, data) and beats as editable rows.
	Save posts the regenerated Luau source to tools/pose-server.luau, which writes the file, runs
	stylua and answers with the clip validator's verdict; "Write Source" edits the module in Studio
	instead (Rojo two-way sync then writes the file).

	Every number here comes from data/dev.luau (poseEditor); Serialize.luau and Session.luau hold
	the pure logic and are Lune-tested.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local Serialize = require(script.Serialize)
local Session = require(script.Session)
local Ui = require(script.Ui)

local function sharedModule(path: string): any?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Shared")
	for segment in path:gmatch("[^%.]+") do
		if node == nil then
			return nil
		end
		node = node:FindFirstChild(segment)
	end
	if node == nil or not node:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, node)
	if not ok then
		warn(("[PoseEditor] %s failed to load: %s"):format(path, tostring(result)))
		return nil
	end
	return result
end

local initialized = false

local function init()
	if initialized then
		return
	end
	local Dev = sharedModule("data.dev")
	local Palette = sharedModule("data.palette")
	local Rigs = sharedModule("data.rigs")
	local ClipSampler = sharedModule("choreo.ClipSampler")
	if Dev == nil or Palette == nil or Rigs == nil or ClipSampler == nil then
		return
	end
	-- Session edits that change a clip's structure drop ClipSampler's per-clip cache (D-003).
	Session.setInvalidator(ClipSampler.invalidate)
	initialized = true

	local Editor = Dev.poseEditor
	local tokens: { [string]: string } = Editor.tokens
	local function color(token: string): Color3
		return Palette.color3(token)
	end
	Ui.init({
		color = color,
		tokens = tokens,
		textSize = Editor.textSize,
		rowHeight = Editor.rowHeight,
		padding = Editor.padding,
	})

	local FRAME = 1 / Dev.review.fps
	local widgetSize = Editor.widgetSize
	local widgetMin = Editor.widgetMinSize
	local wide = widgetSize.width - Editor.padding * 2
	local narrow = (wide - Editor.padding * (Editor.layoutColumns - 1)) / Editor.layoutColumns
	local half = (wide - Editor.padding) / 2

	-- -----------------------------------------------------------------------------------------
	-- Widget
	-- -----------------------------------------------------------------------------------------

	local toolbar = plugin:CreateToolbar(Editor.toolbarName)
	local button = toolbar:CreateButton(Editor.buttonName, Editor.buttonTooltip, "")
	local widget = plugin:CreateDockWidgetPluginGui(
		Editor.widgetName,
		DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Right,
			false,
			false,
			widgetSize.width,
			widgetSize.height,
			widgetMin.width,
			widgetMin.height
		)
	)
	widget.Title = Editor.widgetTitle
	widget.Name = Editor.widgetName

	local scroller = Instance.new("ScrollingFrame")
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.BackgroundColor3 = color(tokens.background)
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = Editor.padding
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.Parent = widget
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Editor.padding)
	padding.PaddingLeft = UDim.new(0, Editor.padding)
	padding.PaddingRight = UDim.new(0, Editor.padding)
	padding.PaddingBottom = UDim.new(0, Editor.padding)
	padding.Parent = scroller
	local root = Ui.column(scroller)

	-- -----------------------------------------------------------------------------------------
	-- State
	-- -----------------------------------------------------------------------------------------

	local session: Session.Session? = nil
	local module: ModuleScript? = nil
	local rigModel: Model? = nil
	local status = ""
	local saveResult = ""

	local handles = Instance.new("Handles")
	handles.Style = Enum.HandlesStyle.Movement
	handles.Color3 = color(tokens.accent)
	handles.Visible = false
	handles.Parent = CoreGui
	local arcHandles = Instance.new("ArcHandles")
	arcHandles.Color3 = color(tokens.warn)
	arcHandles.Visible = false
	arcHandles.Parent = CoreGui
	local dragBase: Session.Offset? = nil

	local render: () -> ()

	local function clipModule(id: string): ModuleScript?
		local node: Instance? = ReplicatedStorage:FindFirstChild("Shared")
		node = if node then node:FindFirstChild("clips") else nil
		for segment in id:gmatch("[^/]+") do
			if node == nil then
				return nil
			end
			node = node:FindFirstChild(segment)
		end
		return if node ~= nil and node:IsA("ModuleScript") then node else nil
	end

	local function rigDef(): any?
		local current = session
		return if current then Rigs[current.clip.rig] else nil
	end

	local function rigJointOrder(): { string }?
		local def = rigDef()
		if def == nil then
			return nil
		end
		local names = {}
		for _, joint in def.joints do
			table.insert(names, joint.name)
		end
		return names
	end

	local function findRigModel(rig: string): Model?
		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("Model") and descendant:GetAttribute(Dev.clipLab.rigAttribute) == rig then
				return descendant
			end
		end
		if rig == "PlayerR15" then
			for _, descendant in workspace:GetDescendants() do
				if descendant:IsA("Model") and descendant:FindFirstChildOfClass("Humanoid") then
					return descendant
				end
			end
		end
		return nil
	end

	-- Animatable joints by name: Motor6Ds (enemy rigs, the Weapon joint) and AnimationConstraints
	-- (player avatars under the Avatar Joint Upgrade); Transform means the same on both.
	local function motors(): { [string]: Motor6D | AnimationConstraint }
		local found: { [string]: Motor6D | AnimationConstraint } = {}
		local model = rigModel
		if model ~= nil then
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
					found[descendant.Name] = descendant :: any
				end
			end
		end
		return found
	end

	local function clearPose()
		for _, motor in motors() do
			motor.Transform = CFrame.identity
		end
		local model = rigModel
		if model ~= nil then
			model:SetAttribute(Editor.previewAttribute, nil)
		end
	end

	local function applyPose()
		local current = session
		local model = rigModel
		if current == nil or model == nil then
			return
		end
		model:SetAttribute(Editor.previewAttribute, true)
		local offsets = ClipSampler.sample(current.clip, current.time)
		for name, motor in motors() do
			local offset = offsets[name]
			motor.Transform = if offset ~= nil then ClipSampler.toCFrame(offset) else CFrame.identity
		end
	end

	local function frameLabel(): string
		local current = session
		if current == nil then
			return ""
		end
		return ("f %d / %d   %.3f s"):format(
			math.floor(current.time / FRAME + 0.5),
			math.floor(current.clip.duration / FRAME + 0.5),
			current.time
		)
	end

	local function setTime(time: number)
		local current = session
		if current == nil then
			return
		end
		Session.scrub(current, time, Editor.keyTimeTolerance)
		applyPose()
		render()
	end

	local function selectedKeyIndex(): number?
		local current = session
		return if current then current.selectedKey else nil
	end

	local function formatOffset(offset: Session.Offset?): string
		if offset == nil then
			return "rest"
		end
		local parts = {}
		if offset.pos then
			table.insert(
				parts,
				("pos %s"):format(table.concat({
					("%." .. Editor.positionDecimals .. "f"):format(offset.pos[1]),
					("%." .. Editor.positionDecimals .. "f"):format(offset.pos[2]),
					("%." .. Editor.positionDecimals .. "f"):format(offset.pos[3]),
				}, ", "))
			)
		end
		if offset.rot then
			table.insert(
				parts,
				("rot %s"):format(table.concat({
					("%." .. Editor.rotationDecimals .. "f"):format(offset.rot[1]),
					("%." .. Editor.rotationDecimals .. "f"):format(offset.rot[2]),
					("%." .. Editor.rotationDecimals .. "f"):format(offset.rot[3]),
				}, ", "))
			)
		end
		return if #parts == 0 then "rest" else table.concat(parts, "  ")
	end

	local function parseNumbers(text: string, count: number): { number }?
		local values = {}
		for piece in text:gmatch("[^,%s]+") do
			local value = tonumber(piece)
			if value == nil then
				return nil
			end
			table.insert(values, value)
		end
		return if #values == count then values else nil
	end

	-- "kind=Art, hit=1" -> { kind = "Art", hit = 1 }; empty text -> nil
	local function parseData(text: string): { [string]: any }?
		local data: { [string]: any } = {}
		local any = false
		for key, value in text:gmatch("(%w+)%s*=%s*([^,]+)") do
			local trimmed = value:match("^%s*(.-)%s*$")
			local number = tonumber(trimmed)
			if number ~= nil then
				data[key] = number
			elseif trimmed == "true" or trimmed == "false" then
				data[key] = trimmed == "true"
			else
				data[key] = trimmed
			end
			any = true
		end
		return if any then data else nil
	end

	local function formatData(data: { [string]: any }?): string
		if data == nil then
			return ""
		end
		local keys = {}
		for key in data do
			table.insert(keys, key)
		end
		table.sort(keys)
		local parts = {}
		for _, key in keys do
			table.insert(parts, ("%s=%s"):format(key, tostring(data[key])))
		end
		return table.concat(parts, ", ")
	end

	local function cycle(list: { string }, current: string?): string
		local index = if current then table.find(list, current) else nil
		return list[(index or 0) % #list + 1]
	end

	-- -----------------------------------------------------------------------------------------
	-- Handles: drag the selected joint's part
	-- -----------------------------------------------------------------------------------------

	local function attachHandles()
		local current = session
		local joint = if current then current.selectedJoint else nil
		local part: BasePart? = nil
		if joint ~= nil then
			local motor = motors()[joint]
			part = if motor then motor.Part1 else nil
		end
		handles.Adornee = part
		arcHandles.Adornee = part
		handles.Visible = part ~= nil
		arcHandles.Visible = part ~= nil
	end

	local function beginDrag()
		local current = session
		local key = selectedKeyIndex()
		local joint = if current then current.selectedJoint else nil
		if current == nil or key == nil or joint == nil then
			return
		end
		local existing = current.clip.keys[key].joints[joint]
		dragBase = if existing then Serialize.clone(existing) else {}
		-- One undo entry per drag: the snapshot comes from this no-op write.
		Session.setJoint(current, key, joint, if existing then Serialize.clone(existing) else nil)
	end

	local function writeDrag(deltaPos: { number }?, deltaRot: { number }?)
		local current = session
		local key = selectedKeyIndex()
		local joint = if current then current.selectedJoint else nil
		local base = dragBase
		if current == nil or key == nil or joint == nil or base == nil then
			return
		end
		local offset: Session.Offset = {}
		if deltaPos or base.pos then
			local pos = base.pos or { 0, 0, 0 }
			local delta = deltaPos or { 0, 0, 0 }
			offset.pos = { pos[1] + delta[1], pos[2] + delta[2], pos[3] + delta[3] }
		end
		if deltaRot or base.rot then
			local rot = base.rot or { 0, 0, 0 }
			local delta = deltaRot or { 0, 0, 0 }
			offset.rot = { rot[1] + delta[1], rot[2] + delta[2], rot[3] + delta[3] }
		end
		-- Written in place while the mouse moves; the undo snapshot was taken on MouseButton1Down.
		current.clip.keys[key].joints[joint] = offset
		ClipSampler.invalidate(current.clip)
		current.dirty = true
		applyPose()
	end

	local function snap(value: number, step: number): number
		return math.floor(value / step + 0.5) * step
	end

	handles.MouseButton1Down:Connect(beginDrag)
	arcHandles.MouseButton1Down:Connect(beginDrag)
	handles.MouseButton1Up:Connect(function()
		dragBase = nil
		render()
	end)
	arcHandles.MouseButton1Up:Connect(function()
		dragBase = nil
		render()
	end)
	handles.MouseDrag:Connect(function(face: Enum.NormalId, distance: number)
		local axis = Vector3.FromNormalId(face)
		local moved = snap(distance, Editor.positionHandleStuds)
		writeDrag({ axis.X * moved, axis.Y * moved, axis.Z * moved }, nil)
	end)
	arcHandles.MouseDrag:Connect(function(axis: Enum.Axis, relativeAngle: number, _deltaRadius: number)
		local degrees = snap(math.deg(relativeAngle), Editor.rotationHandleDegrees)
		local delta = { 0, 0, 0 }
		if axis == Enum.Axis.X then
			delta[1] = degrees
		elseif axis == Enum.Axis.Y then
			delta[2] = degrees
		else
			delta[3] = degrees -- index: Z
		end
		writeDrag(nil, delta)
	end)

	-- -----------------------------------------------------------------------------------------
	-- Loading and saving
	-- -----------------------------------------------------------------------------------------

	local function loadClip(id: string)
		local target = clipModule(id)
		if target == nil then
			status = ("No module for %s under ReplicatedStorage.Shared.clips"):format(id)
			render()
			return
		end
		clearPose()
		local ok, clip, meta = pcall(Serialize.parse, target.Source)
		if not ok then
			status = ("Serialize.parse failed (%s); loaded through require, comments will be lost"):format(
				tostring(clip)
			)
			local required, result = pcall(require, target)
			if not required then
				status = ("Cannot load %s: %s"):format(id, tostring(result))
				render()
				return
			end
			clip = Serialize.clone(result)
			meta = { keyNotes = {}, jointOrder = {} }
		end
		-- A module under clips/ that is not a clip (no keys table, wrong shapes) must not reach Session.new.
		local shape = Serialize.shapeProblems(clip)
		if #shape > 0 then
			status = ("%s is not a clip: %s"):format(id, table.concat(shape, "; "))
			render()
			return
		end
		if ok then
			status = ("Loaded %s (%d keys, %d events)"):format(id, #clip.keys, #clip.events)
		end
		module = target
		session = Session.new(clip, meta)
		saveResult = ""
		local model = rigModel
		if model == nil or model:GetAttribute(Dev.clipLab.rigAttribute) ~= clip.rig then
			rigModel = findRigModel(clip.rig)
		end
		applyPose()
		render()
	end

	local function useSelectionAsRig()
		local picked = Selection:Get()[1]
		if picked ~= nil and picked:IsA("Model") then
			clearPose()
			rigModel = picked
			status = ("Rig model: %s"):format(picked:GetFullName())
			applyPose()
		else
			status = "Select a rig Model in the Explorer first"
		end
		render()
	end

	local function sourceNow(): string?
		local current = session
		if current == nil then
			return nil
		end
		local ok, result = pcall(Session.source, current, rigJointOrder())
		if not ok then
			saveResult = ("Serialize failed: %s"):format(tostring(result))
			render()
			return nil
		end
		return result
	end

	local function saveToServer()
		local current = session
		local source = sourceNow()
		if current == nil or source == nil then
			return
		end
		local url = Dev.clipUrl(current.clip.id)
		local ok, response = pcall(function()
			return HttpService:PostAsync(url, source, Enum.HttpContentType.TextPlain)
		end)
		if not ok then
			saveResult = ("POST %s failed: %s\nRun `lune run tools/pose-server.luau` and allow HTTP requests in Game Settings > Security."):format(
				url,
				tostring(response)
			)
			render()
			return
		end
		local decoded, body = pcall(HttpService.JSONDecode, HttpService, response)
		if not decoded or typeof(body) ~= "table" then
			saveResult = ("Server answered: %s"):format(tostring(response))
			render()
			return
		end
		local lines = { if body.ok then ("Saved %s"):format(tostring(body.path)) else "Saved with problems" }
		if typeof(body.problems) == "table" then
			for _, problem in body.problems do
				table.insert(lines, "- " .. tostring(problem))
			end
		end
		if body.stylua ~= nil then
			table.insert(lines, ("stylua: %s"):format(tostring(body.stylua)))
		end
		saveResult = table.concat(lines, "\n")
		if body.ok then
			Session.markSaved(current)
		end
		render()
	end

	local function writeSource()
		local current = session
		local target = module
		local source = sourceNow()
		if current == nil or target == nil or source == nil then
			return
		end
		local recording = ChangeHistoryService:TryBeginRecording("PoseEditor " .. current.clip.id)
		target.Source = source
		if recording ~= nil then
			ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
		end
		Session.markSaved(current)
		saveResult = ("Wrote %s.Source (%d bytes); Rojo two-way sync writes the file"):format(
			target:GetFullName(),
			#source
		)
		render()
	end

	-- -----------------------------------------------------------------------------------------
	-- Rendering
	-- -----------------------------------------------------------------------------------------

	local idText = ""

	render = function()
		Ui.clear(root)
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end

		-- Load row
		local loadRow = Ui.row(root, nextOrder())
		local idBox = Ui.textBox(loadRow, 1, idText, wide - narrow * 2 - Editor.padding, function(value)
			idText = value
			loadClip(value)
		end)
		idBox.PlaceholderText = "player/OneHandedSword/Horizontal"
		idBox:GetPropertyChangedSignal("Text"):Connect(function()
			idText = idBox.Text
		end)
		Ui.button(loadRow, 2, "Load", narrow, function()
			loadClip(idText)
		end)
		Ui.button(loadRow, 3, "Use selection", narrow, useSelectionAsRig)
		Ui.paragraph(root, nextOrder(), status, tokens.dim)

		local current = session
		if current == nil then
			Ui.paragraph(
				root,
				nextOrder(),
				"Type a clip id and press Load. The rig on stage with a matching Rig attribute is posed; "
					.. "or select a Model and press Use selection.",
				tokens.dim
			)
			attachHandles()
			return
		end
		local clip = current.clip
		local model = rigModel
		Ui.label(
			root,
			nextOrder(),
			("%s   rig %s   model %s%s"):format(
				clip.id,
				clip.rig,
				if model then model.Name else "(none)",
				if current.dirty then "   *unsaved*" else ""
			)
		)

		-- Transport
		Ui.header(root, nextOrder(), "Scrub")
		local transport = Ui.row(root, nextOrder())
		Ui.button(transport, 1, "|<", narrow / 2, function()
			setTime(0)
		end)
		Ui.button(transport, 2, "<", narrow / 2, function()
			setTime(current.time - FRAME * Editor.scrubStepFrames)
		end)
		Ui.label(transport, 3, frameLabel(), half)
		Ui.button(transport, 4, ">", narrow / 2, function()
			setTime(current.time + FRAME * Editor.scrubStepFrames)
		end)
		Ui.button(transport, 5, ">|", narrow / 2, function()
			setTime(clip.duration)
		end)
		local slider = Ui.slider(root, nextOrder(), Editor.rowHeight, function(fraction: number)
			setTime(fraction * clip.duration)
		end)
		Ui.setSlider(slider, if clip.duration > 0 then current.time / clip.duration else 0)

		-- Keys
		Ui.header(root, nextOrder(), ("Keys (%d)"):format(#clip.keys))
		local keyActions = Ui.row(root, nextOrder())
		Ui.button(keyActions, 1, "+ key here", half, function()
			local offsets = ClipSampler.sample(clip, current.time)
			offsets[ClipSampler.ROOT_KEY] = nil
			Session.insertKey(current, current.time, Editor.defaultNewKeyEasing, offsets, Editor.keyTimeTolerance)
			render()
		end)
		Ui.button(keyActions, 2, "delete key", half, function()
			local index = current.selectedKey
			if index ~= nil and Session.deleteKey(current, index) then
				applyPose()
				render()
			end
		end)
		for index, key in clip.keys do
			local note = current.meta.keyNotes[index]
			local line = ("%d   %.3f s   %s%s"):format(
				index,
				key.time,
				key.easing,
				if note then "   -- " .. note else ""
			)
			Ui.listRow(root, nextOrder(), line, index == current.selectedKey, function()
				Session.selectKey(current, index)
				current.time = key.time
				applyPose()
				render()
			end)
		end
		local selectedKey = current.selectedKey
		if selectedKey ~= nil then
			local key = clip.keys[selectedKey]
			local fields = Ui.row(root, nextOrder())
			Ui.label(fields, 1, "time", narrow / 2, tokens.dim)
			Ui.textBox(fields, 2, ("%.3f"):format(key.time), narrow, function(value)
				local time = tonumber(value)
				if time ~= nil then
					local moved = Session.setKeyTime(current, selectedKey, time)
					current.time = clip.keys[moved].time
					applyPose()
				end
				render()
			end)
			Ui.button(fields, 3, key.easing, narrow * 2, function()
				Session.setEasing(current, selectedKey, cycle(Editor.easings, key.easing))
				applyPose()
				render()
			end)
			local noteRow = Ui.row(root, nextOrder())
			Ui.label(noteRow, 1, "note", narrow / 2, tokens.dim)
			Ui.textBox(
				noteRow,
				2,
				current.meta.keyNotes[selectedKey] or "",
				wide - narrow / 2 - Editor.padding,
				function(value)
					Session.setKeyNote(current, selectedKey, value)
					render()
				end
			)

			-- Joints of the selected key
			Ui.header(root, nextOrder(), "Joints (select one to drag its handles)")
			local names = Session.jointNames(current, rigJointOrder())
			for _, name in names do
				local offset = key.joints[name]
				local line = ("%s   %s"):format(name, formatOffset(offset))
				Ui.listRow(root, nextOrder(), line, name == current.selectedJoint, function()
					current.selectedJoint = name
					render()
				end)
			end
			local joint = current.selectedJoint
			if joint ~= nil then
				local offset = key.joints[joint] or {}
				local posRow = Ui.row(root, nextOrder())
				Ui.label(posRow, 1, "pos", narrow / 2, tokens.dim)
				Ui.textBox(posRow, 2, if offset.pos then table.concat(offset.pos, ", ") else "", half, function(value)
					local pos = if value:match("%S") then parseNumbers(value, 3) else nil
					if value:match("%S") and pos == nil then
						status = "pos needs three numbers: x, y, z"
					else
						Session.setJoint(current, selectedKey, joint, { pos = pos, rot = offset.rot })
						applyPose()
					end
					render()
				end)
				Ui.button(posRow, 3, "clear joint", narrow, function()
					Session.setJoint(current, selectedKey, joint, nil)
					applyPose()
					render()
				end)
				local rotRow = Ui.row(root, nextOrder())
				Ui.label(rotRow, 1, "rot", narrow / 2, tokens.dim)
				Ui.textBox(rotRow, 2, if offset.rot then table.concat(offset.rot, ", ") else "", half, function(value)
					local rot = if value:match("%S") then parseNumbers(value, 3) else nil
					if value:match("%S") and rot == nil then
						status = "rot needs three numbers: x, y, z degrees"
					else
						Session.setJoint(current, selectedKey, joint, { pos = offset.pos, rot = rot })
						applyPose()
					end
					render()
				end)
			end
			local rootRow = Ui.row(root, nextOrder())
			Ui.label(rootRow, 1, "root", narrow / 2, tokens.dim)
			Ui.textBox(
				rootRow,
				2,
				if key.root and key.root.pos then table.concat(key.root.pos, ", ") else "",
				half,
				function(value)
					local pos = if value:match("%S") then parseNumbers(value, 3) else nil
					Session.setRoot(current, selectedKey, if pos then { pos = pos } else nil)
					render()
				end
			)
			Ui.label(rootRow, 3, "studs, root motion", narrow, tokens.dim)
		end

		-- Events
		Ui.header(root, nextOrder(), ("Events (%d)"):format(#clip.events))
		local eventActions = Ui.row(root, nextOrder())
		Ui.button(eventActions, 1, "+ event here", half, function()
			Session.addEvent(current, current.time, Editor.eventKinds[1])
			render()
		end)
		for index, event in clip.events do
			local eventRow = Ui.row(root, nextOrder())
			Ui.textBox(eventRow, 1, ("%.3f"):format(event.time), narrow, function(value)
				local time = tonumber(value)
				if time ~= nil then
					Session.setEvent(current, index, { time = time })
				end
				render()
			end)
			Ui.button(eventRow, 2, event.kind, narrow * 2, function()
				Session.setEvent(current, index, { kind = cycle(Editor.eventKinds, event.kind) })
				render()
			end)
			Ui.textBox(
				eventRow,
				3,
				formatData(event.data),
				wide - (narrow + narrow * 2 + narrow / 2) - Editor.padding * 2 - Editor.padding,
				function(value)
					local data = parseData(value)
					Session.setEvent(current, index, { data = if data then data else false })
					render()
				end
			)
			Ui.button(eventRow, 4, "x", narrow / 2, function()
				Session.removeEvent(current, index)
				render()
			end)
		end

		-- Beats
		if clip.attack or clip.beats ~= nil then
			Ui.header(root, nextOrder(), "Beats (start, finish in seconds)")
			for _, beat in Dev.review.beats do
				local span = if clip.beats then clip.beats[beat] else nil
				local beatRow = Ui.row(root, nextOrder())
				Ui.label(beatRow, 1, beat, narrow * 2, tokens.dim)
				local startBox: TextBox
				local finishBox: TextBox
				local function commit()
					local start = tonumber(startBox.Text)
					local finish = tonumber(finishBox.Text)
					if start ~= nil and finish ~= nil then
						Session.setBeat(current, beat, start, finish)
					end
					render()
				end
				startBox = Ui.textBox(beatRow, 2, if span then ("%.3f"):format(span.start) else "", narrow, function()
					commit()
				end)
				finishBox = Ui.textBox(beatRow, 3, if span then ("%.3f"):format(span.finish) else "", narrow, function()
					commit()
				end)
			end
		end

		-- Fields
		Ui.header(root, nextOrder(), "Clip")
		local fieldRow = Ui.row(root, nextOrder())
		Ui.label(fieldRow, 1, "duration", narrow, tokens.dim)
		Ui.textBox(fieldRow, 2, ("%.3f"):format(clip.duration), narrow, function(value)
			local duration = tonumber(value)
			if duration ~= nil and duration > 0 then
				Session.setField(current, "duration", duration)
			end
			render()
		end)
		Ui.button(fieldRow, 3, ("hitStop %s"):format(clip.hitStop or "-"), narrow * 2, function()
			local tiers = { "Normal", "Final", "Kill" }
			Session.setField(current, "hitStop", cycle(tiers, clip.hitStop))
			render()
		end)
		Ui.button(fieldRow, 4, if clip.loop then "loop" else "one-shot", narrow, function()
			Session.setField(current, "loop", not clip.loop)
			render()
		end)

		-- Save
		Ui.header(root, nextOrder(), "Save")
		local saveRow = Ui.row(root, nextOrder())
		Ui.button(saveRow, 1, "Undo", narrow, function()
			if Session.undo(current) then
				applyPose()
				render()
			end
		end)
		Ui.button(saveRow, 2, "Redo", narrow, function()
			if Session.redo(current) then
				applyPose()
				render()
			end
		end)
		Ui.button(saveRow, 3, "Save (server)", narrow * 2, saveToServer)
		Ui.button(saveRow, 4, "Write Source", narrow * 2, writeSource)
		local problems = Serialize.shapeProblems(clip)
		if #problems > 0 then
			Ui.paragraph(root, nextOrder(), table.concat(problems, "\n"), tokens.warn)
		end
		if saveResult ~= "" then
			Ui.paragraph(
				root,
				nextOrder(),
				saveResult,
				if saveResult:find("fail", 1, true) then tokens.bad else tokens.ok
			)
		end
		attachHandles()
	end

	button.Click:Connect(function()
		widget.Enabled = not widget.Enabled
	end)
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		button:SetActive(widget.Enabled)
		if not widget.Enabled then
			clearPose()
			handles.Visible = false
			arcHandles.Visible = false
		elseif session ~= nil then
			applyPose()
			attachHandles()
		end
	end)
	plugin.Unloading:Connect(function()
		clearPose()
		handles:Destroy()
		arcHandles:Destroy()
	end)

	render()
end

init()
if not initialized then
	warn("[PoseEditor] ReplicatedStorage.Shared is not here yet; waiting for the Rojo sync")
	local connection: RBXScriptConnection
	connection = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Shared" then
			task.defer(function()
				init()
				if initialized then
					connection:Disconnect()
				end
			end)
		end
	end)
end
