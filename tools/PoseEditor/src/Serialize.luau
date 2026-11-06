--!strict
--[[
	Serialize: Choreo clip data <-> Luau source, without executing anything.

	The PoseEditor reads a clip module's Source through `parse` (so a freshly synced file is read
	as it is on disk, not as `require`'s cached table), edits the table, and writes it back with
	`toSource` in the same style as the hand-written clips under src/shared/clips: the --!strict
	header, the header comment, the `rot` / `posRot` helpers, one key per block with its comment,
	one event per line, the six beats in order. tools/pose-server.luau parses a posted body the
	same way before it writes a file, so a payload that is not a clip never reaches the repo.

	The parser understands the subset the serializer emits plus what the hand-written clips use:
	`local Types = require(...)`, `local function ... end` (skipped), one `local <name>[: type] = {
	... }` table of strings, numbers, booleans, nested tables and `rot(...)` / `posRot(...)` /
	`pos(...)` helper calls, then `return <name>`. Anything else is an error that names the line.

	No requires: this module runs inside the Studio plugin and under Lune unchanged.
]]

local Serialize = {}

export type Meta = {
	header: string?, -- the header block comment's text (without the --[[ ]])
	keyNotes: { [number]: string }, -- comment above key N inside `keys`
	jointOrder: { [number]: { string } }, -- joint names of key N in source order
}

export type ToSourceOptions = {
	meta: Meta?,
	jointOrder: { string }?, -- the rig's joint order, used for keys without a recorded order
	header: string?, -- overrides meta.header
}

type Comment = { text: string, block: boolean }

type Token = {
	kind: "name" | "number" | "string" | "punct" | "eof",
	value: string,
	line: number,
	comments: { Comment }, -- comments that preceded this token
}

local TOP_FIELDS =
	{ "id", "rig", "duration", "loop", "sheathed", "layer", "priority", "attack", "hitStop", "blendIn", "blendOut" }
local BEATS = { "Anticipation", "Snap", "Smear", "Hold", "Settle", "Recovery" }
local HELPERS: { [string]: boolean } = { rot = true, posRot = true, pos = true }
local INDENT = "\t"

-- ---------------------------------------------------------------------------------------------
-- Tokenizer
-- ---------------------------------------------------------------------------------------------

local function tokenize(source: string): { Token }
	local tokens: { Token } = {}
	local index = 1
	local length = #source
	local line = 1
	local pending: { Comment } = {}

	local function push(kind: "name" | "number" | "string" | "punct" | "eof", value: string)
		table.insert(tokens, { kind = kind, value = value, line = line, comments = pending })
		pending = {}
	end

	local function countLines(text: string)
		for _ in text:gmatch("\n") do
			line += 1
		end
	end

	while index <= length do
		local char = source:sub(index, index)
		if char == "\n" then
			line += 1
			index += 1
		elseif char:match("%s") then
			index += 1
		elseif source:sub(index, index + 1) == "--" then
			local blockOpen = source:match("^%-%-%[(=*)%[", index)
			if blockOpen ~= nil then
				local closeToken = "]" .. blockOpen .. "]"
				local close = source:find(closeToken, index, true)
				if close == nil then
					error(("Serialize.parse: unterminated block comment at line %d"):format(line))
				end
				local contentStart = index + 4 + #blockOpen
				local text = source:sub(contentStart, close - 1)
				countLines(source:sub(index, close + #closeToken - 1))
				table.insert(pending, { text = text, block = true })
				index = close + #closeToken
			else
				local lineEnd = source:find("\n", index, true) or (length + 1)
				local text = source:sub(index + 2, lineEnd - 1)
				if text:sub(1, 1) ~= "!" then -- `--!strict` is a directive, not a note
					table.insert(pending, { text = (text:match("^%s*(.-)%s*$")), block = false })
				end
				index = lineEnd
			end
		elseif char:match("[%a_]") then
			local word = source:match("^[%w_]+", index) :: string
			push("name", word)
			index += #word
		elseif char:match("%d") or (char == "." and source:sub(index + 1, index + 1):match("%d")) then
			local text = source:match("^0[xX]%x+", index)
			if text == nil then
				text = source:match("^%d*%.?%d*", index) :: string
				local exponent = source:match("^[eE][%+%-]?%d+", index + #text)
				if exponent then
					text ..= exponent
				end
			end
			push("number", text :: string)
			index += #(text :: string)
		elseif char == '"' or char == "'" then
			local buffer = {}
			local cursor = index + 1
			while true do
				if cursor > length then
					error(("Serialize.parse: unterminated string at line %d"):format(line))
				end
				local current = source:sub(cursor, cursor)
				if current == "\\" then
					local following = source:sub(cursor + 1, cursor + 1)
					local escapes = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }
					table.insert(buffer, escapes[following] or following)
					cursor += 2
				elseif current == char then
					break
				elseif current == "\n" then
					error(("Serialize.parse: newline inside a string at line %d"):format(line))
				else
					table.insert(buffer, current)
					cursor += 1
				end
			end
			push("string", table.concat(buffer))
			index = cursor + 1
		elseif source:sub(index, index + 1) == "[[" then
			error(("Serialize.parse: long strings are not supported (line %d)"):format(line))
		else
			local two = source:sub(index, index + 1)
			if two == "==" or two == "~=" or two == "<=" or two == ">=" or two == ".." or two == "->" then
				push("punct", two)
				index += 2
			else
				push("punct", char)
				index += 1
			end
		end
	end
	push("eof", "")
	return tokens
end

-- ---------------------------------------------------------------------------------------------
-- Parser
-- ---------------------------------------------------------------------------------------------

type Helper = { params: { string }, bodyIndex: number, line: number }

type Env = { [string]: any }

type Parser = {
	tokens: { Token },
	index: number,
	meta: Meta,
	keyIndex: number,
	helpers: { [string]: Helper },
	depth: number, -- helper evaluation depth (guards runaway recursion)
}

local MAX_HELPER_DEPTH = 8

-- Binary operator precedence (Luau order); the clip subset needs them only inside helpers.
local BINARY: { [string]: number } = {
	["or"] = 1,
	["and"] = 2,
	["<"] = 3,
	[">"] = 3,
	["<="] = 3,
	[">="] = 3,
	["=="] = 3,
	["~="] = 3,
	[".."] = 4,
	["+"] = 5,
	["-"] = 5,
	["*"] = 6,
	["/"] = 6,
	["%"] = 6,
	["^"] = 8,
}
local UNARY_PRECEDENCE = 7

local function lineNotes(comments: { Comment }): string?
	local parts = {}
	for _, comment in comments do
		if not comment.block and comment.text ~= "" then
			table.insert(parts, comment.text)
		end
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " ")
end

local function addKeyNote(parser: Parser, note: string?)
	if note == nil then
		return
	end
	local existing = parser.meta.keyNotes[parser.keyIndex]
	parser.meta.keyNotes[parser.keyIndex] = if existing then existing .. " " .. note else note
end

local function peek(parser: Parser, offset: number?): Token
	return parser.tokens[parser.index + (offset or 0)] or parser.tokens[#parser.tokens]
end

local function advance(parser: Parser): Token
	local token = peek(parser)
	parser.index += 1
	return token
end

local function fail(token: Token, message: string): never
	error(("Serialize.parse: %s at line %d (near '%s')"):format(message, token.line, token.value))
end

local function expect(parser: Parser, kind: string, value: string?): Token
	local token = advance(parser)
	if token.kind ~= kind or (value ~= nil and token.value ~= value) then
		fail(token, ("expected %s"):format(value or kind))
	end
	return token
end

local function isPunct(token: Token, value: string): boolean
	return token.kind == "punct" and token.value == value
end

local function isName(token: Token, value: string): boolean
	return token.kind == "name" and token.value == value
end

local function toNumber(token: Token): number
	local value = tonumber(token.value)
	if value == nil then
		fail(token, "malformed number")
	end
	return value :: number
end

local parseExpression: (parser: Parser, context: string, env: Env, minPrecedence: number?) -> any

-- Built-in helper shapes for files that call rot / posRot / pos without defining them.
local function builtinHelper(token: Token, name: string, args: { any }): any
	local function num(position: number): number
		local value = args[position]
		if typeof(value) ~= "number" then
			fail(token, ("%s expects numbers"):format(name))
		end
		return value :: number
	end
	if name == "rot" then
		return { rot = { num(1), num(2), num(3) } }
	elseif name == "pos" then
		return { pos = { num(1), num(2), num(3) } }
	end
	return { pos = { num(1), num(2), num(3) }, rot = { num(4), num(5), num(6) } }
end

-- Evaluates a helper defined in the file by parsing its `return <expr>` with the arguments bound.
local function callHelper(parser: Parser, token: Token, name: string, args: { any }): any
	local helper = parser.helpers[name]
	if helper == nil then
		if HELPERS[name] then
			return builtinHelper(token, name, args)
		end
		fail(
			token,
			("unsupported identifier '%s' (only rot, posRot, pos and helpers defined in the file are allowed)"):format(
				name
			)
		)
	end
	if parser.depth >= MAX_HELPER_DEPTH then
		fail(token, "helpers nest too deep")
	end
	local env: Env = {}
	for position, param in (helper :: Helper).params do
		env[param] = args[position]
	end
	local saved = parser.index
	parser.index = (helper :: Helper).bodyIndex
	parser.depth += 1
	local value = parseExpression(parser, "helper", env)
	parser.depth -= 1
	parser.index = saved
	return value
end

local function parseArguments(parser: Parser, context: string, env: Env): { any }
	expect(parser, "punct", "(")
	local args = {}
	if isPunct(peek(parser), ")") then
		advance(parser)
		return args
	end
	while true do
		local value = parseExpression(parser, context, env)
		table.insert(args, value)
		local separator = advance(parser)
		if isPunct(separator, ")") then
			break
		elseif not isPunct(separator, ",") then
			fail(separator, "expected ',' or ')'")
		end
	end
	return args
end

-- Parses `{ ... }`. `context` names the table ("keys", "joints" ...) so key notes are recorded.
local function parseTable(parser: Parser, context: string, env: Env): any
	local open = expect(parser, "punct", "{")
	local result: { [any]: any } = {}
	local position = 0
	local entries = 0
	local jointOrder: { string }? = if context == "joints" then {} else nil
	while true do
		local token = peek(parser)
		if isPunct(token, "}") then
			advance(parser)
			break
		end
		if token.kind == "eof" then
			fail(open, "unterminated table")
		end
		entries += 1
		if context == "key" and entries == 1 then
			addKeyNote(parser, lineNotes(token.comments)) -- `{` newline `-- note` newline `time = ...`
		end
		local key: any = nil
		local valueContext = context
		if isPunct(token, "[") then
			advance(parser)
			key = parseExpression(parser, context, env)
			expect(parser, "punct", "]")
			expect(parser, "punct", "=")
		elseif token.kind == "name" and isPunct(peek(parser, 1), "=") then
			advance(parser)
			advance(parser)
			key = token.value
			valueContext = token.value
			if jointOrder ~= nil then
				table.insert(jointOrder, token.value)
			end
		else
			position += 1
			key = position
			if context == "keys" then
				parser.keyIndex = position
				addKeyNote(parser, lineNotes(token.comments)) -- `-- note` newline `{`
			end
			valueContext = if context == "keys" then "key" else context
		end
		local value = parseExpression(parser, valueContext, env)
		if value == nil then
			fail(token, "nil values are not allowed in clip data")
		end
		result[key] = value
		local separator = peek(parser)
		if isPunct(separator, ",") or isPunct(separator, ";") then
			advance(parser)
		elseif not isPunct(separator, "}") then
			fail(separator, "expected ',' or '}'")
		end
	end
	if jointOrder ~= nil then
		(result :: any).__jointOrder = jointOrder
	end
	return result
end

local function parseIfExpression(parser: Parser, context: string, env: Env): any
	expect(parser, "name", "if")
	local condition = parseExpression(parser, context, env)
	expect(parser, "name", "then")
	local whenTrue = parseExpression(parser, context, env)
	local chosen: any = nil
	local decided = false
	if condition then
		chosen = whenTrue
		decided = true
	end
	while isName(peek(parser), "elseif") do
		advance(parser)
		local other = parseExpression(parser, context, env)
		expect(parser, "name", "then")
		local value = parseExpression(parser, context, env)
		if not decided and other then
			chosen = value
			decided = true
		end
	end
	expect(parser, "name", "else")
	local fallback = parseExpression(parser, context, env)
	if not decided then
		chosen = fallback
	end
	return chosen
end

local function parsePrimary(parser: Parser, context: string, env: Env): any
	local token = peek(parser)
	if isPunct(token, "{") then
		return parseTable(parser, context, env)
	elseif isPunct(token, "(") then
		advance(parser)
		local value = parseExpression(parser, context, env)
		expect(parser, "punct", ")")
		return value
	elseif token.kind == "string" then
		advance(parser)
		return token.value
	elseif token.kind == "number" then
		advance(parser)
		return toNumber(token)
	elseif token.kind == "name" then
		if token.value == "true" then
			advance(parser)
			return true
		elseif token.value == "false" then
			advance(parser)
			return false
		elseif token.value == "nil" then
			advance(parser)
			return nil
		elseif token.value == "if" then
			return parseIfExpression(parser, context, env)
		elseif isPunct(peek(parser, 1), "(") then
			advance(parser)
			local args = parseArguments(parser, context, env)
			return callHelper(parser, token, token.value, args)
		elseif env[token.value] ~= nil or (parser.depth > 0 and token.value:match("^[%a_][%w_]*$")) then
			advance(parser)
			return env[token.value]
		end
		fail(
			token,
			("unsupported identifier '%s' (only rot, posRot, pos and helpers defined in the file are allowed)"):format(
				token.value
			)
		)
	end
	return fail(token, "unexpected token")
end

local function parseUnary(parser: Parser, context: string, env: Env): any
	local token = peek(parser)
	if isPunct(token, "-") then
		advance(parser)
		local value = parseExpression(parser, context, env, UNARY_PRECEDENCE)
		if typeof(value) ~= "number" then
			fail(token, "unary minus on a non-number")
		end
		return -value
	elseif isName(token, "not") then
		advance(parser)
		return not parseExpression(parser, context, env, UNARY_PRECEDENCE)
	end
	return parsePrimary(parser, context, env)
end

local function applyBinary(token: Token, op: string, left: any, right: any): any
	if op == "and" then
		return if left then right else left
	elseif op == "or" then
		return if left then left else right
	elseif op == "==" then
		return left == right
	elseif op == "~=" then
		return left ~= right
	elseif op == ".." then
		return tostring(left) .. tostring(right)
	end
	if typeof(left) ~= "number" or typeof(right) ~= "number" then
		fail(token, ("operator %s needs numbers"):format(op))
	end
	local a = left :: number
	local b = right :: number
	if op == "+" then
		return a + b
	elseif op == "-" then
		return a - b
	elseif op == "*" then
		return a * b
	elseif op == "/" then
		return a / b
	elseif op == "%" then
		return a % b
	elseif op == "^" then
		return a ^ b
	elseif op == "<" then
		return a < b
	elseif op == ">" then
		return a > b
	elseif op == "<=" then
		return a <= b
	end
	return a >= b
end

parseExpression = function(parser: Parser, context: string, env: Env, minPrecedence: number?): any
	local floor = minPrecedence or 0
	local left = parseUnary(parser, context, env)
	while true do
		local token = peek(parser)
		local op = if token.kind == "punct" or token.kind == "name" then token.value else ""
		local precedence = BINARY[op]
		if precedence == nil or precedence < floor then
			break
		end
		advance(parser)
		-- `^` is right-associative; the rest bind left.
		local right = parseExpression(parser, context, env, if op == "^" then precedence else precedence + 1)
		left = applyBinary(token, op, left, right)
	end
	return left
end

-- Is this `if` token the start of a statement (which ends with `end`) rather than an if-expression?
-- An expression follows `=`, `(`, `,`, `{`, `return`, `and`, `or` or `not`.
local function startsStatement(parser: Parser, index: number): boolean
	local previous = parser.tokens[index - 1]
	if previous == nil then
		return true
	end
	if previous.kind == "punct" then
		return previous.value == ")" or previous.value == "}" or previous.value == "]" or previous.value == ";"
	end
	if previous.kind == "name" then
		local value = previous.value
		return not (value == "return" or value == "and" or value == "or" or value == "not")
	end
	return true
end

-- Skips from a `function` token to its matching `end`, counting the blocks in between.
local function skipFunction(parser: Parser)
	local depth = 0
	while true do
		local index = parser.index
		local token = advance(parser)
		if token.kind == "eof" then
			fail(token, "unterminated function")
		end
		if token.kind == "name" then
			if
				token.value == "function"
				or token.value == "do"
				or (token.value == "if" and startsStatement(parser, index))
			then
				depth += 1
			elseif token.value == "end" then
				depth -= 1
				if depth == 0 then
					return
				end
			end
		end
	end
end

-- Skips a balanced `( ... )`.
local function skipParens(parser: Parser)
	expect(parser, "punct", "(")
	local depth = 1
	while depth > 0 do
		local token = advance(parser)
		if token.kind == "eof" then
			fail(token, "unterminated call")
		end
		if isPunct(token, "(") then
			depth += 1
		elseif isPunct(token, ")") then
			depth -= 1
		end
	end
end

-- Skips a type annotation (`: T` or a return type) up to `=` or the body keyword at depth 0.
local function skipTypeAnnotation(parser: Parser, stopAt: { [string]: boolean })
	local depth = 0
	while true do
		local token = peek(parser)
		if token.kind == "eof" then
			fail(token, "unterminated type annotation")
		end
		if
			depth == 0
			and ((token.kind == "punct" and stopAt[token.value]) or (token.kind == "name" and stopAt[token.value]))
		then
			return
		end
		if isPunct(token, "{") or isPunct(token, "(") or isPunct(token, "<") then
			depth += 1
		elseif isPunct(token, "}") or isPunct(token, ")") or isPunct(token, ">") then
			depth -= 1
		end
		advance(parser)
	end
end

-- Records `local function name(params): T return <expr> end` as a helper and skips its body.
local function parseHelperDefinition(parser: Parser)
	local functionIndex = parser.index
	expect(parser, "name", "function")
	local nameToken = expect(parser, "name")
	expect(parser, "punct", "(")
	local params = {}
	while not isPunct(peek(parser), ")") do
		local param = expect(parser, "name")
		table.insert(params, param.value)
		if isPunct(peek(parser), ":") then
			advance(parser)
			skipTypeAnnotation(parser, { [","] = true, [")"] = true })
		end
		if isPunct(peek(parser), ",") then
			advance(parser)
		end
	end
	expect(parser, "punct", ")")
	if isPunct(peek(parser), ":") then
		advance(parser)
		skipTypeAnnotation(
			parser,
			{ ["return"] = true, ["end"] = true, ["local"] = true, ["if"] = true, ["for"] = true }
		)
	end
	local bodyIndex: number? = nil
	if isName(peek(parser), "return") then
		bodyIndex = parser.index + 1
	end
	-- Rewind to the `function` token and skip the whole definition.
	parser.index = functionIndex
	skipFunction(parser)
	if bodyIndex ~= nil then
		parser.helpers[nameToken.value] = { params = params, bodyIndex = bodyIndex, line = nameToken.line }
	end
end

-- Moves recorded joint orders out of the parsed keys into meta and strips the marker fields.
local function liftJointOrder(clip: any, meta: Meta)
	if typeof(clip.keys) ~= "table" then
		return
	end
	for index, key in ipairs(clip.keys) do
		if typeof(key) == "table" and typeof(key.joints) == "table" then
			local order = key.joints.__jointOrder
			if order ~= nil then
				meta.jointOrder[index] = order
				key.joints.__jointOrder = nil
			end
		end
	end
end

--- Parses a clip module's source into its table and the comments the serializer keeps.
function Serialize.parse(source: string): (any, Meta)
	local meta: Meta = { header = nil, keyNotes = {}, jointOrder = {} }
	local parser: Parser = {
		tokens = tokenize(source),
		index = 1,
		meta = meta,
		keyIndex = 0,
		helpers = {},
		depth = 0,
	}
	local clip: any = nil
	local clipName: string? = nil

	for _, comment in peek(parser).comments do
		if comment.block then
			meta.header = comment.text:match("^%s*(.-)%s*$")
			break
		end
	end

	while true do
		local token = peek(parser)
		if token.kind == "eof" then
			break
		end
		if isName(token, "local") then
			advance(parser)
			local nameToken = peek(parser)
			if isName(nameToken, "function") then
				parseHelperDefinition(parser)
			elseif nameToken.kind == "name" then
				advance(parser)
				if isPunct(peek(parser), ":") then
					advance(parser)
					skipTypeAnnotation(parser, { ["="] = true })
				end
				expect(parser, "punct", "=")
				local valueToken = peek(parser)
				if isName(valueToken, "require") then
					advance(parser)
					skipParens(parser)
				elseif isPunct(valueToken, "{") then
					if clip ~= nil then
						fail(valueToken, "a clip module holds exactly one table")
					end
					clip = parseTable(parser, "clip", {})
					clipName = nameToken.value
				else
					fail(valueToken, "unsupported local value")
				end
			else
				fail(nameToken, "expected a name after 'local'")
			end
		elseif isName(token, "return") then
			advance(parser)
			local returned = advance(parser)
			if returned.kind ~= "name" or returned.value ~= clipName then
				fail(returned, ("expected 'return %s'"):format(clipName or "<clip>"))
			end
			break
		else
			fail(token, "unsupported statement")
		end
	end
	if clip == nil then
		error("Serialize.parse: no clip table found")
	end
	liftJointOrder(clip, meta)
	return clip, meta
end

-- ---------------------------------------------------------------------------------------------
-- Serializer
-- ---------------------------------------------------------------------------------------------

local function number(value: number): string
	if value ~= value or value == math.huge or value == -math.huge then
		error("Serialize: clip data holds a non-finite number")
	end
	if value == math.floor(value) and math.abs(value) < 1e15 then
		if value == 0 then
			return "0"
		end
		return ("%d"):format(value)
	end
	return tostring(value)
end

local function quote(value: string): string
	local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", "\\r")
	return '"' .. escaped .. '"'
end

local function isArray(value: { [any]: any }): boolean
	local count = 0
	for _ in value do
		count += 1
	end
	return count == #value
end

local function sortedKeys(value: { [any]: any }): { any }
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function keyText(key: any): string
	if typeof(key) == "string" and key:match("^[%a_][%w_]*$") then
		return key
	end
	if typeof(key) == "string" then
		return "[" .. quote(key) .. "]"
	end
	return "[" .. number(key) .. "]"
end

-- Inline value: numbers, strings, booleans and small tables on one line.
local function inlineValue(value: any): string
	local kind = typeof(value)
	if kind == "number" then
		return number(value)
	elseif kind == "string" then
		return quote(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "table" then
		local parts = {}
		if isArray(value) then
			for _, item in ipairs(value) do
				table.insert(parts, inlineValue(item))
			end
		else
			for _, key in sortedKeys(value) do
				table.insert(parts, keyText(key) .. " = " .. inlineValue(value[key]))
			end
		end
		if #parts == 0 then
			return "{}"
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	error(("Serialize: cannot serialize a %s"):format(kind))
end

local function vec3Text(vec: { number }): string
	return ("{ %s, %s, %s }"):format(number(vec[1]), number(vec[2]), number(vec[3]))
end

local function jointText(joint: any): string
	local pos = joint.pos
	local rot = joint.rot
	if pos ~= nil and rot ~= nil then
		return ("posRot(%s, %s, %s, %s, %s, %s)"):format(
			number(pos[1]),
			number(pos[2]),
			number(pos[3]),
			number(rot[1]),
			number(rot[2]),
			number(rot[3])
		)
	elseif rot ~= nil then
		return ("rot(%s, %s, %s)"):format(number(rot[1]), number(rot[2]), number(rot[3]))
	elseif pos ~= nil then
		return ("{ pos = %s }"):format(vec3Text(pos))
	end
	return "{}"
end

local function rootText(root: any): string
	local parts = {}
	if root.pos ~= nil then
		table.insert(parts, "pos = " .. vec3Text(root.pos))
	end
	if root.rot ~= nil then
		table.insert(parts, "rot = " .. vec3Text(root.rot))
	end
	if #parts == 0 then
		return "{}"
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function orderedJointNames(joints: { [string]: any }, recorded: { string }?, rigOrder: { string }?): { string }
	local names = {}
	local seen: { [string]: boolean } = {}
	local function take(name: string)
		if joints[name] ~= nil and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	if recorded ~= nil then
		for _, name in recorded do
			take(name)
		end
	end
	if rigOrder ~= nil then
		for _, name in rigOrder do
			take(name)
		end
	end
	local rest = {}
	for name in joints do
		if not seen[name] then
			table.insert(rest, name)
		end
	end
	table.sort(rest)
	for _, name in rest do
		take(name)
	end
	return names
end

local function requirePath(id: string): string
	local depth = 0
	for _ in id:gmatch("[^/]+") do
		depth += 1
	end
	local parts = { "script" }
	for _ = 1, depth + 1 do
		table.insert(parts, "Parent")
	end
	return table.concat(parts, ".") .. ".types"
end

--- Writes a clip table as a module in the hand-written style; `options.meta` carries comments.
function Serialize.toSource(clip: any, options: ToSourceOptions?): string
	local opts: ToSourceOptions = options or {}
	local meta = opts.meta
	local header = opts.header or (if meta then meta.header else nil)
	if header == nil or header == "" then
		header = ("%s: written by the PoseEditor."):format(tostring(clip.id))
	end
	local lines = {}
	local function line(text: string)
		table.insert(lines, text)
	end

	line("--!strict")
	line("--[[")
	for headerLine in (header .. "\n"):gmatch("(.-)\n") do
		if headerLine == "" then
			line("")
		elseif headerLine:sub(1, 1) == "\t" then
			line(headerLine)
		else
			line(INDENT .. headerLine)
		end
	end
	line("]]")
	line("")
	line(("local Types = require(%s)"):format(requirePath(tostring(clip.id))))
	line("")
	line("local function rot(x: number, y: number, z: number): Types.JointKey")
	line(INDENT .. "return { rot = { x, y, z } }")
	line("end")
	line("")
	line(
		"local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey"
	)
	line(INDENT .. "return { pos = { px, py, pz }, rot = { rx, ry, rz } }")
	line("end")
	line("")
	line("local clip: Types.ClipDef = {")

	local emitted: { [string]: boolean } = {}
	for _, field in TOP_FIELDS do
		local value = clip[field]
		if value ~= nil then
			line(INDENT .. field .. " = " .. inlineValue(value) .. ",")
		end
		emitted[field] = true
	end

	-- keys
	line(INDENT .. "keys = {")
	for index, key in ipairs(clip.keys or {}) do
		line(INDENT .. INDENT .. "{")
		local note = if meta then meta.keyNotes[index] else nil
		if note ~= nil and note ~= "" then
			line(INDENT .. INDENT .. INDENT .. "-- " .. note)
		end
		line(INDENT .. INDENT .. INDENT .. "time = " .. number(key.time) .. ",")
		line(INDENT .. INDENT .. INDENT .. "easing = " .. quote(tostring(key.easing)) .. ",")
		local joints = key.joints or {}
		local recorded = if meta then meta.jointOrder[index] else nil
		local names = orderedJointNames(joints, recorded, opts.jointOrder)
		if #names == 0 then
			line(INDENT .. INDENT .. INDENT .. "joints = {},")
		else
			line(INDENT .. INDENT .. INDENT .. "joints = {")
			for _, name in names do
				line(INDENT .. INDENT .. INDENT .. INDENT .. keyText(name) .. " = " .. jointText(joints[name]) .. ",")
			end
			line(INDENT .. INDENT .. INDENT .. "},")
		end
		if key.root ~= nil then
			line(INDENT .. INDENT .. INDENT .. "root = " .. rootText(key.root) .. ",")
		end
		for _, extra in sortedKeys(key) do
			if extra ~= "time" and extra ~= "easing" and extra ~= "joints" and extra ~= "root" then
				line(INDENT .. INDENT .. INDENT .. keyText(extra) .. " = " .. inlineValue(key[extra]) .. ",")
			end
		end
		line(INDENT .. INDENT .. "},")
	end
	line(INDENT .. "},")
	emitted.keys = true

	-- events
	local events = clip.events or {}
	if #events == 0 then
		line(INDENT .. "events = {},")
	else
		line(INDENT .. "events = {")
		for _, event in ipairs(events) do
			local parts = { "time = " .. number(event.time), "kind = " .. quote(tostring(event.kind)) }
			if event.data ~= nil then
				table.insert(parts, "data = " .. inlineValue(event.data))
			end
			for _, extra in sortedKeys(event) do
				if extra ~= "time" and extra ~= "kind" and extra ~= "data" then
					table.insert(parts, keyText(extra) .. " = " .. inlineValue(event[extra]))
				end
			end
			line(INDENT .. INDENT .. "{ " .. table.concat(parts, ", ") .. " },")
		end
		line(INDENT .. "},")
	end
	emitted.events = true

	-- beats
	if clip.beats ~= nil then
		line(INDENT .. "beats = {")
		local seen: { [string]: boolean } = {}
		for _, beat in BEATS do
			local span = clip.beats[beat]
			seen[beat] = true
			if span ~= nil then
				line(
					INDENT
						.. INDENT
						.. beat
						.. " = { start = "
						.. number(span.start)
						.. ", finish = "
						.. number(span.finish)
						.. " },"
				)
			end
		end
		for _, extra in sortedKeys(clip.beats) do
			if not seen[extra] then
				line(INDENT .. INDENT .. keyText(extra) .. " = " .. inlineValue(clip.beats[extra]) .. ",")
			end
		end
		line(INDENT .. "},")
	end
	emitted.beats = true

	-- anything else, so no data is ever dropped
	for _, extra in sortedKeys(clip) do
		if not emitted[extra] then
			line(INDENT .. keyText(extra) .. " = " .. inlineValue(clip[extra]) .. ",")
		end
	end

	line("}")
	line("")
	line("return clip")
	line("")
	return table.concat(lines, "\n")
end

--- Cheap shape checks before a write: the fields every clip needs, with the right types.
function Serialize.shapeProblems(clip: any): { string }
	local problems = {}
	if typeof(clip) ~= "table" then
		return { "clip is not a table" }
	end
	if typeof(clip.id) ~= "string" or clip.id == "" then
		table.insert(problems, "id must be a string")
	end
	if typeof(clip.rig) ~= "string" then
		table.insert(problems, "rig must be a string")
	end
	if typeof(clip.duration) ~= "number" or clip.duration <= 0 then
		table.insert(problems, "duration must be a positive number")
	end
	if typeof(clip.loop) ~= "boolean" then
		table.insert(problems, "loop must be a boolean")
	end
	if typeof(clip.layer) ~= "string" then
		table.insert(problems, "layer must be a string")
	end
	if typeof(clip.keys) ~= "table" or #clip.keys == 0 then
		table.insert(problems, "keys must be a non-empty array")
	else
		for index, key in ipairs(clip.keys) do
			if typeof(key) ~= "table" or typeof(key.time) ~= "number" or typeof(key.easing) ~= "string" then
				table.insert(problems, ("key %d needs time and easing"):format(index))
			elseif typeof(key.joints) ~= "table" then
				table.insert(problems, ("key %d needs a joints table"):format(index))
			end
		end
	end
	if typeof(clip.events) ~= "table" then
		table.insert(problems, "events must be an array")
	else
		for index, event in ipairs(clip.events) do
			if typeof(event) ~= "table" or typeof(event.time) ~= "number" or typeof(event.kind) ~= "string" then
				table.insert(problems, ("event %d needs time and kind"):format(index))
			end
		end
	end
	return problems
end

--- Deep copy of plain clip data (tables, numbers, strings, booleans).
function Serialize.clone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = Serialize.clone(item)
	end
	return copy
end

return Serialize
