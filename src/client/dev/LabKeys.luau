--!strict
--[[
	LabKeys: the ClipLab's hotkeys (dev.luau clipLab.hotkeys), bound through ContextActionService
	at clipLab.actionPriority (D-413). The default character scripts bind the arrows and Space
	through ContextActionService (move and jump), so the lab's own keys read off UserInputService
	(the arrows pick a clip and orbit the camera, Space pauses) also walked or jumped the player's
	character on the PlayerR15 pedestal, stepping the rig off its mark under the review. Bound
	above them, every lab key runs its action and sinks the input.

		LabKeys.bind(ContextActionService, "ClipLab", priority, {
			[Enum.KeyCode.Space] = { pressed = togglePlaying },
			[Enum.KeyCode.Left] = { held = function(down) ... end },
		})
]]

export type Binding = {
	pressed: (() -> ())?, -- runs once when the key goes down
	held: ((down: boolean) -> ())?, -- true when it goes down, false when it comes up or is taken
}

local LabKeys = {}

--- Binds each key to its action at `priority`; every input on a bound key is sunk. Returns the
--- action names bound (`prefix` and the key's name), sorted.
function LabKeys.bind(cas: any, prefix: string, priority: number, bindings: { [Enum.KeyCode]: Binding }): { string }
	local names: { string } = {}
	for code, binding in bindings do
		local name = prefix .. code.Name
		cas:BindActionAtPriority(name, function(_action: string, state: Enum.UserInputState, _input: InputObject)
			if state == Enum.UserInputState.Begin then
				if binding.pressed ~= nil then
					binding.pressed()
				end
				if binding.held ~= nil then
					binding.held(true)
				end
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				if binding.held ~= nil then
					binding.held(false)
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, priority, code)
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return LabKeys
