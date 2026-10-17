--!strict
--[[
	Ui: the PoseEditor's widget furniture (rows, buttons, text boxes, section headers), themed from
	data/dev.luau poseEditor tokens through the palette. Roblox-only; the pure editor logic lives
	in Serialize.luau and Session.luau so it can be tested under Lune without this file.
]]

export type Theme = {
	color: (token: string) -> Color3,
	tokens: { [string]: string }, -- background, text, dim, accent, ok, warn, bad
	textSize: number,
	rowHeight: number,
	padding: number,
}

local Ui = {}

local theme: Theme? = nil

local function current(): Theme
	local value = theme
	if value == nil then
		error("Ui.init must run before building widgets")
	end
	return value
end

--- Stores the theme every later call draws from.
function Ui.init(value: Theme)
	theme = value
end

local function apply(instance: Instance, props: { [string]: any })
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if props.Parent ~= nil then
		instance.Parent = props.Parent
	end
end

--- A vertical list container that grows with its children.
function Ui.column(parent: Instance, props: { [string]: any }?): Frame
	local t = current()
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, t.padding / 2)
	layout.Parent = frame
	if props then
		apply(frame, props)
	end
	frame.Parent = parent
	return frame
end

--- A horizontal row of fixed height; children lay out left to right.
function Ui.row(parent: Instance, order: number, height: number?): Frame
	local t = current()
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height or t.rowHeight)
	frame.LayoutOrder = order
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, t.padding / 2)
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

--- A section header line in the accent color.
function Ui.header(parent: Instance, order: number, text: string): TextLabel
	local t = current()
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, t.rowHeight)
	label.Font = Enum.Font.GothamBold
	label.TextSize = t.textSize
	label.TextColor3 = t.color(t.tokens.accent)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

--- A plain label; `width` in pixels, or nil for a label that fills the row's remaining width.
function Ui.label(parent: Instance, order: number, text: string, width: number?, token: string?): TextLabel
	local t = current()
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = if width then UDim2.new(0, width, 1, 0) else UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.Gotham
	label.TextSize = t.textSize
	label.TextColor3 = t.color(token or t.tokens.text)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

--- A wrapped multi-line label that grows with its text.
function Ui.paragraph(parent: Instance, order: number, text: string, token: string?): TextLabel
	local t = current()
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, t.rowHeight)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.Gotham
	label.TextSize = t.textSize
	label.TextColor3 = t.color(token or t.tokens.dim)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = text
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

--- A button; `onClick` runs on Activated.
function Ui.button(parent: Instance, order: number, text: string, width: number, onClick: () -> ()): TextButton
	local t = current()
	local control = Instance.new("TextButton")
	control.Size = UDim2.new(0, width, 1, 0)
	control.BackgroundColor3 = t.color(t.tokens.background)
	control.BorderSizePixel = 0
	control.AutoButtonColor = true
	control.Font = Enum.Font.GothamBold
	control.TextSize = t.textSize
	control.TextColor3 = t.color(t.tokens.text)
	control.Text = text
	control.LayoutOrder = order
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, t.padding / 2)
	corner.Parent = control
	local stroke = Instance.new("UIStroke")
	stroke.Color = t.color(t.tokens.accent)
	stroke.Thickness = 1
	stroke.Parent = control
	control.Activated:Connect(onClick)
	control.Parent = parent
	return control
end

--- Colors a button as active (accent fill) or idle.
function Ui.setActive(control: TextButton, active: boolean)
	local t = current()
	control.BackgroundColor3 = t.color(if active then t.tokens.accent else t.tokens.background)
	control.TextColor3 = t.color(if active then t.tokens.background else t.tokens.text)
end

--- A single-line text box; `onCommit(text)` runs when focus is lost with Enter.
function Ui.textBox(parent: Instance, order: number, text: string, width: number, onCommit: (string) -> ()): TextBox
	local t = current()
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, width, 1, 0)
	box.BackgroundColor3 = t.color(t.tokens.background)
	box.BorderSizePixel = 0
	box.Font = Enum.Font.Gotham
	box.TextSize = t.textSize
	box.TextColor3 = t.color(t.tokens.text)
	box.PlaceholderColor3 = t.color(t.tokens.dim)
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Text = text
	box.LayoutOrder = order
	local stroke = Instance.new("UIStroke")
	stroke.Color = t.color(t.tokens.dim)
	stroke.Thickness = 1
	stroke.Parent = box
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			onCommit(box.Text)
		end
	end)
	box.Parent = parent
	return box
end

--- A selectable list row (a full-width button); `selected` paints it in the accent color.
function Ui.listRow(parent: Instance, order: number, text: string, selected: boolean, onClick: () -> ()): TextButton
	local t = current()
	local control = Instance.new("TextButton")
	control.Size = UDim2.new(1, 0, 0, t.rowHeight)
	control.BackgroundColor3 = t.color(t.tokens.accent)
	control.BackgroundTransparency = if selected then 0 else 1
	control.BorderSizePixel = 0
	control.AutoButtonColor = false
	control.Font = Enum.Font.Gotham
	control.TextSize = t.textSize
	control.TextColor3 = t.color(if selected then t.tokens.background else t.tokens.text)
	control.TextXAlignment = Enum.TextXAlignment.Left
	control.TextTruncate = Enum.TextTruncate.AtEnd
	control.Text = text
	control.LayoutOrder = order
	control.Activated:Connect(onClick)
	control.Parent = parent
	return control
end

--- A scrub bar: a full-width frame whose horizontal drag position (0..1) is reported to `onScrub`.
function Ui.slider(parent: Instance, order: number, height: number, onScrub: (fraction: number) -> ()): Frame
	local t = current()
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, height)
	bar.BackgroundColor3 = t.color(t.tokens.background)
	bar.BorderSizePixel = 0
	bar.LayoutOrder = order
	bar.Active = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = t.color(t.tokens.dim)
	stroke.Thickness = 1
	stroke.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Playhead"
	fill.Size = UDim2.new(0, 2, 1, 0)
	fill.BackgroundColor3 = t.color(t.tokens.accent)
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local dragging = false
	local function report(x: number)
		local width = bar.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local fraction = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
		onScrub(fraction)
	end
	bar.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			report(input.Position.X)
		end
	end)
	bar.InputChanged:Connect(function(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			report(input.Position.X)
		end
	end)
	bar.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	bar.Parent = parent
	return bar
end

--- Moves a slider's playhead to a fraction of its width.
function Ui.setSlider(bar: Frame, fraction: number)
	local fill = bar:FindFirstChild("Playhead")
	if fill ~= nil and fill:IsA("Frame") then
		fill.Position = UDim2.fromScale(math.clamp(fraction, 0, 1), 0)
	end
end

--- Destroys every child of a container except its layout.
function Ui.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UILayout") then
			child:Destroy()
		end
	end
end

return Ui
