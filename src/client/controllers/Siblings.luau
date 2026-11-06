--!strict
--[[
	Siblings: loads modules from the other client packages (choreo, fx, ui, audio) that may not
	exist in this build yet. A missing or failing module logs once and is replaced by a stub whose
	every member is a callable no-op that returns another stub, so a controller can call
	`Trails.setActive(model, true, "Art")` or `Choreo.get(model):play(...)` without crashing while
	a sibling package is still being written. Callers that need a real value check `typeof`.
]]

local Siblings = {}

local stubMeta = {}
local function newStub(): any
	return setmetatable({}, stubMeta)
end
stubMeta.__index = function(_self: any, _key: any): any
	return newStub()
end
stubMeta.__call = function(_self: any): any
	return newStub()
end

--- A universal no-op stub: every field is callable and returns another stub.
function Siblings.stub(): any
	return newStub()
end

--- True when `value` is one of the stubs this module hands out.
function Siblings.isStub(value: any): boolean
	return typeof(value) == "table" and getmetatable(value) == stubMeta
end

--- Walks `parent` along a dotted path ("fx.Trails") and requires the module there; on any miss or
--- error it warns once and returns a stub. The second value says whether the real module loaded.
function Siblings.load(parent: Instance, path: string): (any, boolean)
	local node: Instance? = parent
	for segment in path:gmatch("[^%.]+") do
		if node == nil then
			break
		end
		node = node:FindFirstChild(segment)
	end
	if node == nil or not node:IsA("ModuleScript") then
		warn(("[Siblings] %s is not available yet; using a no-op stub"):format(path))
		return newStub(), false
	end
	local ok, result = pcall(require, node :: ModuleScript)
	if not ok then
		warn(("[Siblings] %s failed to load (%s); using a no-op stub"):format(path, tostring(result)))
		return newStub(), false
	end
	return result, true
end

--- Calls `module[fnName](...)` when it is a real function; returns nil otherwise.
function Siblings.call(module: any, fnName: string, ...: any): any
	if typeof(module) ~= "table" then
		return nil
	end
	local fn = rawget(module, fnName)
	if typeof(fn) == "function" then
		return fn(...)
	end
	return nil
end

return Siblings
