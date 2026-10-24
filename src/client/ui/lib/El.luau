--!strict
--[[
	El: the tiny component library (docs/DECISIONS.md D-007).

		local label = El.new("TextLabel", { Text = "Mira", TextSize = 20 }, { El.new("UIStroke", {}) })
		local hp = El.state(300)
		El.bind(label, "Text", hp, function(value) return tostring(value) end)
		hp.set(250)   -- the label updates; `hp.changed` fires

	Props are set after creation (Parent last, so a built tree is parented once); children are
	parented in order. State cells are plain tables with get / set / changed, and `El.computed`
	derives one cell from others. No TweenService here: limbs are never tweened (section 10) and
	panel motion steps on Heartbeat through springs; the HUD modules own those loops.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Signal = require(Shared.util.Signal)
local UI = require(Shared.data.ui)
local Palette = require(Shared.data.palette)

export type State<T> = {
	get: () -> T,
	set: (value: T) -> (),
	changed: Signal.Signal<T, T>, -- (new, old)
}

export type Connection = { Disconnect: (self: any) -> (), Connected: boolean }

local El = {}

--- Creates an Instance, sets `props` (Parent last), parents `children` in order, returns it.
function El.new(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local parent: Instance? = nil
	if props ~= nil then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children ~= nil then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent ~= nil then
		instance.Parent = parent
	end
	return instance
end

--- A state cell. `set` fires `changed(new, old)` only when the value actually changes.
function El.state<T>(initial: T): State<T>
	local value = initial
	local changed = Signal.new() :: Signal.Signal<T, T>
	local cell = {} :: State<T>
	cell.changed = changed
	function cell.get(): T
		return value
	end
	function cell.set(next: T)
		if next == value then
			return
		end
		local old = value
		value = next
		changed:Fire(next, old)
	end
	return cell
end

--- Binds an instance property to a state: sets it now and on every change, through `mapFn` when
--- given. Returns the connection so a destroyed element can unbind.
function El.bind<T>(instance: Instance, prop: string, state: State<T>, mapFn: ((T) -> any)?): Connection
	local function apply(value: T)
		(instance :: any)[prop] = if mapFn ~= nil then mapFn(value) else value
	end
	apply(state.get())
	return state.changed:Connect(function(value: T)
		apply(value)
	end) :: any
end

--- A read-only cell derived from other cells: recomputed whenever any input changes.
function El.computed<T>(inputs: { State<any> }, compute: () -> T): State<T>
	local cell = El.state(compute())
	for _, input in inputs do
		input.changed:Connect(function()
			cell.set(compute())
		end)
	end
	return cell
end

--- The system or lore Font (section 14: two fonts, never more). `weight` is "Regular", "Medium" or "Bold".
function El.font(kind: "system" | "lore", weight: string?): Font
	local def = if kind == "lore" then UI.fonts.lore else UI.fonts.system
	local weightName = weight or def.weight or "Regular"
	local ok, font = pcall(function()
		return Font.new(def.family, (Enum.FontWeight :: any)[weightName], Enum.FontStyle.Normal)
	end)
	if ok then
		return font
	end
	return Font.fromEnum((Enum.Font :: any)[def.enumName])
end

--- A Color3 for a palette token (the only colors UI may use).
function El.color(token: string): Color3
	return Palette.color3(token :: any)
end

--- Destroys an instance and disconnects the bindings listed with it.
function El.destroy(instance: Instance, connections: { Connection }?)
	if connections ~= nil then
		for _, connection in connections do
			if connection.Connected then
				connection:Disconnect()
			end
		end
	end
	instance:Destroy()
end

return El
