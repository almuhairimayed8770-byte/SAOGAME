--!strict
--[[
	Check: a small runtime schema checker for remote payloads and data tables.

	Every checker is a function (value) -> (ok, message?). Checkers compose, so a remote schema
	reads like its type. The server runs a schema on every payload before any handler sees it.
]]

export type Checker = (value: any) -> (boolean, string?)

local Check = {}

local function fail(message: string): (boolean, string?)
	return false, message
end

--- Accepts any value.
function Check.any(_value: any): (boolean, string?)
	return true
end

--- Accepts a finite number; optional inclusive bounds.
function Check.number(min: number?, max: number?): Checker
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return fail("expected a finite number, got " .. typeof(value))
		end
		if min ~= nil and value < min then
			return fail(("number %s is below the minimum %s"):format(tostring(value), tostring(min)))
		end
		if max ~= nil and value > max then
			return fail(("number %s is above the maximum %s"):format(tostring(value), tostring(max)))
		end
		return true
	end
end

--- Accepts an integer; optional inclusive bounds.
function Check.integer(min: number?, max: number?): Checker
	local inner = Check.number(min, max)
	return function(value: any): (boolean, string?)
		local ok, message = inner(value)
		if not ok then
			return false, message
		end
		if value % 1 ~= 0 then
			return fail(("expected an integer, got %s"):format(tostring(value)))
		end
		return true
	end
end

--- Accepts a string; optional maximum length.
function Check.string(maxLength: number?): Checker
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "string" then
			return fail("expected a string, got " .. typeof(value))
		end
		if maxLength ~= nil and #value > maxLength then
			return fail(("string of length %d exceeds %d"):format(#value, maxLength))
		end
		return true
	end
end

--- Accepts a boolean.
function Check.boolean(value: any): (boolean, string?)
	if typeof(value) ~= "boolean" then
		return fail("expected a boolean, got " .. typeof(value))
	end
	return true
end

--- Accepts one of a fixed set of literal values.
function Check.literal(...: any): Checker
	local allowed = { ... }
	return function(value: any): (boolean, string?)
		for _, candidate in allowed do
			if candidate == value then
				return true
			end
		end
		return fail(("value %s is not one of the allowed literals"):format(tostring(value)))
	end
end

--- Accepts nil or a value that passes the inner checker.
function Check.optional(inner: Checker): Checker
	return function(value: any): (boolean, string?)
		if value == nil then
			return true
		end
		return inner(value)
	end
end

--- Accepts a table whose keys are exactly the schema's keys (extra keys are rejected).
function Check.strictInterface(schema: { [string]: Checker }): Checker
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "table" then
			return fail("expected a table, got " .. typeof(value))
		end
		for key, checker in schema do
			local ok, message = checker(value[key])
			if not ok then
				return fail(("field '%s': %s"):format(key, message or "invalid"))
			end
		end
		for key in value do
			if typeof(key) ~= "string" or schema[key] == nil then
				return fail(("unexpected field '%s'"):format(tostring(key)))
			end
		end
		return true
	end
end

--- Accepts a table whose listed keys pass; extra keys are allowed.
function Check.interface(schema: { [string]: Checker }): Checker
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "table" then
			return fail("expected a table, got " .. typeof(value))
		end
		for key, checker in schema do
			local ok, message = checker(value[key])
			if not ok then
				return fail(("field '%s': %s"):format(key, message or "invalid"))
			end
		end
		return true
	end
end

--- Accepts an array whose every element passes; optional maximum length.
function Check.array(inner: Checker, maxLength: number?): Checker
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "table" then
			return fail("expected an array, got " .. typeof(value))
		end
		local count = 0
		for key, element in value do
			count += 1
			if typeof(key) ~= "number" or key % 1 ~= 0 or key < 1 then
				return fail("array has a non-integer key")
			end
			local ok, message = inner(element)
			if not ok then
				return fail(("element %d: %s"):format(key, message or "invalid"))
			end
		end
		if count ~= #value then
			return fail("array has holes")
		end
		if maxLength ~= nil and count > maxLength then
			return fail(("array of length %d exceeds %d"):format(count, maxLength))
		end
		return true
	end
end

--- Accepts a map with checked keys and values.
function Check.map(keyChecker: Checker, valueChecker: Checker): Checker
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "table" then
			return fail("expected a map, got " .. typeof(value))
		end
		for key, element in value do
			local okKey, keyMessage = keyChecker(key)
			if not okKey then
				return fail(("key %s: %s"):format(tostring(key), keyMessage or "invalid"))
			end
			local ok, message = valueChecker(element)
			if not ok then
				return fail(("value at %s: %s"):format(tostring(key), message or "invalid"))
			end
		end
		return true
	end
end

--- Accepts a value that passes any of the given checkers.
function Check.union(...: Checker): Checker
	local options = { ... }
	return function(value: any): (boolean, string?)
		local messages = {}
		for _, checker in options do
			local ok, message = checker(value)
			if ok then
				return true
			end
			table.insert(messages, message or "invalid")
		end
		return fail("no union member matched: " .. table.concat(messages, "; "))
	end
end

--- Accepts a plain-number Vec3 ({x, y, z}) with finite components.
function Check.vec3(maxMagnitude: number?): Checker
	local component = Check.number(if maxMagnitude then -maxMagnitude else nil, maxMagnitude)
	return function(value: any): (boolean, string?)
		if typeof(value) ~= "table" or #value ~= 3 then
			return fail("expected a {x, y, z} table")
		end
		for index = 1, 3 do
			local ok, message = component(value[index])
			if not ok then
				return fail(("component %d: %s"):format(index, message or "invalid"))
			end
		end
		return true
	end
end

--- Runs a checker and raises if it fails; for data validators, not for remotes.
function Check.assert(checker: Checker, value: any, context: string)
	local ok, message = checker(value)
	if not ok then
		error(("%s: %s"):format(context, message or "invalid"), 2)
	end
end

return Check
