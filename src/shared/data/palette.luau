--!strict
--[[
	Color tokens (section 11). The only colors UI and FX may use. Values are {r, g, b} in 0..1
	so this table loads in Lune; `Palette.color3(token)` converts at runtime.
]]

export type Token =
	"SystemCyan"
	| "SystemWhite"
	| "HPGreen"
	| "HPYellow"
	| "HPRed"
	| "CursorOrange"
	| "CursorRed"
	| "CursorGreen"
	| "TorchWarm"
	| "WardedPurple"
	| "ShardBlue"
	| "ApexEdge"
	| "TelegraphWhite"
	| "TelegraphYellow"
	| "TelegraphRed"
	| "TrailCyanWhite"
	| "TrailPaleGold"
	| "TrailCrimson"
	| "TrailSilverBlue"
	| "TrailViolet"
	| "TrailJade"
	| "TrailOrange"
	| "TrailAmber"
	| "TrailWhite"
	| "TrailRose"
	| "TrailIvory"
	| "ShatterSilver"
	| "ShatterGreenGold"
	| "OutlineInk"
	| "DigitWhite"
	| "DigitYellow"
	| "DigitCyan"
	| "DigitRed"
	| "PlaceholderBoar"
	| "PlaceholderKobold"
	| "PlaceholderSteel"
	| "PlaceholderWood"

local function hex(code: string): { number }
	local r = tonumber(code:sub(2, 3), 16) or 0
	local g = tonumber(code:sub(4, 5), 16) or 0
	local b = tonumber(code:sub(6, 7), 16) or 0
	return { r / 255, g / 255, b / 255 }
end

local Palette = {
	tokens = {
		-- Section 11 table
		SystemCyan = hex("#7FE8FF"),
		SystemWhite = hex("#F4FBFF"),
		HPGreen = hex("#4FE36B"),
		HPYellow = hex("#FFD23F"),
		HPRed = hex("#FF3B3B"),
		CursorOrange = hex("#FF8C1A"),
		CursorRed = hex("#E01B1B"),
		TorchWarm = hex("#FFA347"),
		WardedPurple = hex("#B57BFF"),
		ShardBlue = hex("#9ADCFF"),
		ApexEdge = hex("#FFFFFF"),
		-- Derived tokens (section 6 cursor and telegraphs, section 8 trails, section 9 shatters)
		CursorGreen = hex("#4FE36B"),
		TelegraphWhite = hex("#F4FBFF"),
		TelegraphYellow = hex("#FFD23F"),
		TelegraphRed = hex("#FF3B3B"),
		TrailCyanWhite = hex("#B8F4FF"),
		TrailPaleGold = hex("#FFE9A3"),
		TrailCrimson = hex("#E8213F"),
		TrailSilverBlue = hex("#B7CFF2"),
		TrailViolet = hex("#A86BFF"),
		TrailJade = hex("#4FE3B0"),
		TrailOrange = hex("#FF8C1A"),
		TrailAmber = hex("#FFC14F"),
		TrailWhite = hex("#FFFFFF"),
		TrailRose = hex("#FF7FB5"),
		TrailIvory = hex("#FFF6E0"),
		ShatterSilver = hex("#D7DEE8"),
		ShatterGreenGold = hex("#B7E86B"),
		OutlineInk = hex("#0B0F14"),
		DigitWhite = hex("#F4FBFF"),
		DigitYellow = hex("#FFD23F"),
		DigitCyan = hex("#7FE8FF"),
		DigitRed = hex("#FF3B3B"),
		PlaceholderBoar = hex("#4A6FB5"),
		PlaceholderKobold = hex("#8A6A3E"),
		PlaceholderSteel = hex("#AEB6C2"),
		PlaceholderWood = hex("#6B4A2B"),
	} :: { [Token]: { number } },
}

--- Returns the {r, g, b} triple for a token; errors on an unknown token so FX never silently go gray.
function Palette.rgb(token: Token): { number }
	local value = Palette.tokens[token]
	if value == nil then
		error(("unknown palette token '%s'"):format(tostring(token)))
	end
	return value
end

--- Converts a token to a Color3 (Roblox runtime only).
function Palette.color3(token: Token): Color3
	local rgb = Palette.rgb(token)
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

return Palette
