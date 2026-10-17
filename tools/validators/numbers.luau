--!strict
--[[
	Magic-number lint (section 19, ARCHITECTURE "Rules every module follows"). Every tunable
	lives in src/shared/data/; a numeric literal in a gameplay script is a defect.

	Scanned: every .luau under src/server/services, src/server/ai, src/server/combat,
	src/server/world, src/server/anticheat, src/client/controllers, src/client/camera,
	src/client/fx, src/client/ui, src/client/choreo, src/client/audio. Dev tooling (src/*/dev) is
	not gameplay and is not scanned.

	Allowed literals (the sign is an operator, so -0.5 is as allowed as 0.5):
	  0, 1, -1, 2          identity, halving, doubling, the empty case
	  0.5                  halves and midpoints
	  10, 20, 30, 45, 90, 180, 360   degrees and the common angle fractions
	  60                   frames per second
	  100                  percent
	  255                  color channel
	  1e-6, 1e6            epsilon and "a big number"

	Exemptions: a line whose trailing comment starts with "-- unit:" (a unit conversion) or
	"-- index:" (a fixed table index). The three components of a plain Vec3 ({x, y, z}) are
	exempt without a comment: a literal 1..3 directly inside brackets (`v[3]`) or as the upper
	bound of `for axis = 1, 3`. Skipped: comment lines and block comments, the contents of string
	literals, and lines that call require. Type annotations never hold a numeric literal in Luau
	(Vector3 / UDim2 are identifiers), so the identifier boundary check covers them. The
	heuristic is simple on purpose: a false positive is fixed by moving the number to a data
	table, which is the point.
]]

type Context = {
	load: (path: string) -> any,
	listFiles: (directory: string, pattern: string?) -> { string },
	readFile: (path: string) -> string,
	repoRoot: string,
}

local DIRECTORIES = {
	"src/server/services",
	"src/server/ai",
	"src/server/combat",
	"src/server/world",
	"src/server/anticheat",
	"src/client/controllers",
	"src/client/camera",
	"src/client/fx",
	"src/client/ui",
	"src/client/choreo",
	"src/client/audio",
}

local ALLOWED = { 0, 1, 2, 0.5, 10, 20, 30, 45, 60, 90, 100, 180, 255, 360, 1e-6, 1e6 }

local allowedSet: { [number]: boolean } = {}
for _, value in ALLOWED do
	allowedSet[value] = true
end

local VEC3_COMPONENTS = 3

local function isAllowed(value: number): boolean
	return allowedSet[value] == true or allowedSet[-value] == true
end

-- `v[3]` and `for axis = 1, 3 do`: the components of a Vec3, not tunables.
local function isVec3Component(code: string, start: number, stop: number, value: number): boolean
	if value < 1 or value > VEC3_COMPONENTS or value % 1 ~= 0 then
		return false
	end
	local before = code:sub(1, start - 1)
	local after = code:sub(stop + 1)
	if before:match("%[%s*$") and after:match("^%s*%]") then
		return true
	end
	if before:match("for%s+[%w_]+%s*=%s*1%s*,%s*$") and after:match("^%s*do") then
		return true
	end
	return false
end

-- Replaces string literal contents with nothing, keeping the quotes so the line shape survives.
local function stripStrings(line: string): string
	local result = {}
	local index = 1
	local length = #line
	while index <= length do
		local char = line:sub(index, index)
		if char == '"' or char == "'" then
			table.insert(result, char)
			index += 1
			while index <= length do
				local inner = line:sub(index, index)
				if inner == "\\" then
					index += 2
				elseif inner == char then
					break
				else
					index += 1
				end
			end
			table.insert(result, char)
			index += 1
		elseif line:sub(index, index + 1) == "[[" then
			local close = line:find("]]", index + 2, true)
			if close == nil then
				table.insert(result, "[[")
				return table.concat(result) -- the rest is a long string (handled by the caller's state)
			end
			table.insert(result, "[[]]")
			index = close + 2
		else
			table.insert(result, char)
			index += 1
		end
	end
	return table.concat(result)
end

-- Every numeric literal in a line of code (strings and comments already removed). A digit run
-- preceded by an identifier character is part of a name (Vector3, UDim2, foo1) and is skipped.
type Literal = { text: string, start: number, stop: number }

local function findLiterals(code: string): { Literal }
	local literals: { Literal } = {}
	local position = 1
	while true do
		local start, stop = code:find("%d[%d%._]*", position)
		if start == nil or stop == nil then
			break
		end
		position = stop + 1
		local before = if start > 1 then code:sub(start - 1, start - 1) else ""
		if before:match("[%w_]") then
			continue
		end
		local literalStart = start
		if before == "." then
			-- `"a" .. 5` is a concatenation (the literal is the digits); `t.5` is a member access and
			-- never a literal; anything else is a bare `.5`.
			local beforeDot = if start > 2 then code:sub(start - 2, start - 2) else ""
			if beforeDot:match("[%w_%)%]]") then
				continue
			elseif beforeDot ~= "." then
				literalStart = start - 1
			end
		end
		local _, hexStop = code:find("^0[xX]%x+", start)
		if hexStop then
			stop = hexStop
		else
			local _, exponentStop = code:find("^[eE][%+%-]?%d+", stop + 1)
			if exponentStop then
				stop = exponentStop
			end
		end
		position = stop + 1
		local text = code:sub(literalStart, stop):gsub("_", ""):gsub("%.$", "")
		table.insert(literals, { text = text, start = literalStart, stop = stop })
	end
	return literals
end

return function(ctx: Context): { string }
	local problems = {}
	for _, directory in DIRECTORIES do
		local ok, files = pcall(ctx.listFiles, directory, "%.luau$")
		if not ok then
			continue -- the package has not landed yet
		end
		for _, path in files :: { string } do
			local content = ctx.readFile(path)
			local inBlockComment = false
			local inLongString = false
			local lineNumber = 0
			for line in (content .. "\n"):gmatch("(.-)\n") do
				lineNumber += 1
				if inBlockComment then
					if line:find("]]", 1, true) then
						inBlockComment = false
					end
					continue
				end
				if inLongString then
					if line:find("]]", 1, true) then
						inLongString = false
					end
					continue
				end
				local trimmed = line:match("^%s*(.-)%s*$") or ""
				if trimmed == "" or trimmed:sub(1, 2) == "--" then
					if trimmed:sub(1, 4) == "--[[" and not trimmed:find("]]", 1, true) then
						inBlockComment = true
					end
					continue
				end
				if trimmed:find("require%s*%(") then
					continue
				end
				local code = stripStrings(line)
				if code:sub(-2) == "[[" then
					inLongString = true
					code = code:sub(1, -3)
				end
				local commentStart = code:find("--", 1, true)
				if commentStart then
					local comment = code:sub(commentStart + 2):match("^%s*(.-)%s*$") or ""
					if comment:sub(1, 5) == "unit:" or comment:sub(1, 6) == "index:" then
						continue
					end
					if comment:sub(1, 2) == "[[" and not comment:find("]]", 1, true) then
						inBlockComment = true
					end
					code = code:sub(1, commentStart - 1)
				end
				for _, literal in findLiterals(code) do
					local value = tonumber(literal.text)
					if value == nil then
						continue
					end
					if isVec3Component(code, literal.start, literal.stop, value) then
						continue
					end
					if not isAllowed(value) then
						table.insert(
							problems,
							("%s:%d: magic number %s (move it to src/shared/data/, or end the line with -- unit: / -- index:)"):format(
								path,
								lineNumber,
								literal.text
							)
						)
					end
				end
			end
		end
	end
	return problems
end
