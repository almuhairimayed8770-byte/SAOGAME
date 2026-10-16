--!strict
--[[
	Test: a minimal describe / it / expect framework for Lune.
	The runner (tests/run.luau) injects `describe`, `it`, `expect` and `Harness` into each spec.

		expect(value).toBe(other)            expect(value).toEqual(deepOther)
		expect(number).toBeCloseTo(x, eps)   expect(fn).toThrow("substring")
		expect(value).never.toBe(other)
]]

export type Result = { suite: string, name: string, ok: boolean, message: string? }

local Test = {}

local results: { Result } = {}
local suiteStack: { string } = {}

local function suiteName(): string
	return table.concat(suiteStack, " > ")
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function describeValue(value: any): string
	if typeof(value) == "table" then
		local parts = {}
		local count = 0
		for key, element in value do
			count += 1
			if count > 8 then
				table.insert(parts, "...")
				break
			end
			table.insert(parts, tostring(key) .. "=" .. describeValue(element))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	if typeof(value) == "string" then
		return ("%q"):format(value)
	end
	return tostring(value)
end

function Test.describe(name: string, body: () -> ())
	table.insert(suiteStack, name)
	local ok, err = pcall(body)
	if not ok then
		table.insert(results, { suite = suiteName(), name = "(describe body)", ok = false, message = tostring(err) })
	end
	table.remove(suiteStack)
end

function Test.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	table.insert(results, {
		suite = suiteName(),
		name = name,
		ok = ok,
		message = if ok then nil else tostring(err),
	})
end

local function buildMatchers(value: any, negated: boolean): any
	local matchers = {}

	local function check(passed: boolean, message: string)
		if negated then
			passed = not passed
			message = "not " .. message
		end
		if not passed then
			error(message, 3)
		end
	end

	function matchers.toBe(expected: any)
		check(value == expected, ("expected %s to be %s"):format(describeValue(value), describeValue(expected)))
	end

	function matchers.toEqual(expected: any)
		check(
			deepEqual(value, expected),
			("expected %s to equal %s"):format(describeValue(value), describeValue(expected))
		)
	end

	function matchers.toBeCloseTo(expected: number, epsilon: number?)
		local tolerance = epsilon or 1e-6
		check(
			typeof(value) == "number" and math.abs(value - expected) <= tolerance,
			("expected %s to be within %s of %s"):format(describeValue(value), tostring(tolerance), tostring(expected))
		)
	end

	function matchers.toBeTruthy()
		check(value and true or false, ("expected %s to be truthy"):format(describeValue(value)))
	end

	function matchers.toBeFalsy()
		check(not value, ("expected %s to be falsy"):format(describeValue(value)))
	end

	function matchers.toBeNil()
		check(value == nil, ("expected %s to be nil"):format(describeValue(value)))
	end

	function matchers.toBeGreaterThan(other: number)
		check(value > other, ("expected %s > %s"):format(describeValue(value), tostring(other)))
	end

	function matchers.toBeGreaterThanOrEqual(other: number)
		check(value >= other, ("expected %s >= %s"):format(describeValue(value), tostring(other)))
	end

	function matchers.toBeLessThan(other: number)
		check(value < other, ("expected %s < %s"):format(describeValue(value), tostring(other)))
	end

	function matchers.toBeLessThanOrEqual(other: number)
		check(value <= other, ("expected %s <= %s"):format(describeValue(value), tostring(other)))
	end

	function matchers.toContain(element: any)
		local found = false
		if typeof(value) == "string" then
			found = string.find(value, element, 1, true) ~= nil
		elseif typeof(value) == "table" then
			for _, candidate in value do
				if deepEqual(candidate, element) then
					found = true
					break
				end
			end
		end
		check(found, ("expected %s to contain %s"):format(describeValue(value), describeValue(element)))
	end

	function matchers.toHaveLength(length: number)
		local actual = if typeof(value) == "string" or typeof(value) == "table" then #value else -1
		check(actual == length, ("expected length %d, got %d"):format(length, actual))
	end

	function matchers.toThrow(pattern: string?)
		local ok, err = pcall(value)
		local matched = not ok and (pattern == nil or string.find(tostring(err), pattern, 1, true) ~= nil)
		check(
			matched,
			if ok
				then "expected function to throw"
				else ("expected error to contain %s, got %s"):format(tostring(pattern), tostring(err))
		)
	end

	if not negated then
		matchers.never = buildMatchers(value, true)
	end
	return matchers
end

function Test.expect(value: any): any
	return buildMatchers(value, false)
end

function Test.results(): { Result }
	return results
end

function Test.reset()
	table.clear(results)
	table.clear(suiteStack)
end

return Test
