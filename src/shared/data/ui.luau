--!strict
--[[
	HUD and UI numbers (section 14). Layout is in pixels at UI scale 1 and scales through a
	UIScale; colors are palette tokens; times are seconds. The HP thresholds point at combat.luau
	so there is one source for "yellow at half, red at a quarter".

	Fonts (section 14): two, never more. The system font is Roblox's Gotham family until the user
	uploads one (assets.luau SystemFont); the lore font is a narrow serif.
]]

local Combat = require(script.Parent.combat)

local SYSTEM_FAMILY = "rbxasset://fonts/families/GothamSSm.json"
local LORE_FAMILY = "rbxasset://fonts/families/Garamond.json"

local UI = {
	scale = {
		default = 1,
		min = 0.8,
		max = 1.4,
		mobile = 1.15,
	},

	-- Player attributes the settings menu writes; the HUD reads them and listens for changes.
	settings = {
		colorblindAttribute = "SettingColorblind",
		uiScaleAttribute = "SettingUiScale",
		telegraphIntensityAttribute = "SettingTelegraphIntensity",
	},

	fonts = {
		-- Font family ids plus the Enum.Font names used as a fallback when Font.new is unavailable.
		system = { family = SYSTEM_FAMILY, enumName = "Gotham" },
		systemMedium = { family = SYSTEM_FAMILY, enumName = "GothamMedium", weight = "Medium" },
		systemBold = { family = SYSTEM_FAMILY, enumName = "GothamBold", weight = "Bold" },
		lore = { family = LORE_FAMILY, enumName = "Garamond" },
		assetKeys = { system = "SystemFont", lore = "SerifFont" }, -- assets.luau entries that replace these
	},

	hud = {
		screenGuiName = "SkyspireHud",
		displayOrder = 10,
		margin = 24, -- pixels from the top-left corner
		textStrokeTransparency = 0.6, -- every HUD label's dark stroke
		name = { textSize = 20, token = "SystemWhite" },
		level = { textSize = 14, token = "SystemCyan", gap = 8 },
		hpBar = {
			width = 320,
			height = 18,
			cornerRadius = 4,
			backgroundToken = "OutlineInk",
			backgroundTransparency = 0.45,
			yellowFraction = Combat.hpYellowFraction,
			redFraction = Combat.hpRedFraction,
			tokens = { green = "HPGreen", yellow = "HPYellow", red = "HPRed" },
			-- Colorblind mode (section 14) swaps the hues and adds a pattern overlay flag.
			colorblindTokens = { green = "SystemCyan", yellow = "TrailIvory", red = "CursorOrange" },
			flashToken = "SystemWhite",
			flashSeconds = 0.12, -- the only HUD element that flashes (section 2)
			flashTransparency = 0.15,
			smoothRate = 14, -- per second; the fill approaches the real fraction exponentially
			patternStripeWidth = 6, -- pixels; colorblind pattern overlay stripes
			patternTransparency = 0.7,
		},
		hpText = { textSize = 14, token = "SystemWhite", gap = 2 },
		guardGauge = { width = 320, height = 4, gap = 4, token = "SystemCyan", backgroundTransparency = 0.6 },
		statusRow = {
			iconSize = 22,
			gap = 4,
			topGap = 8,
			textSize = 11,
			tokens = {
				Bleed = "HPRed",
				Poison = "WardedPurple",
				Paralysis = "HPRed",
				Stun = "HPYellow",
				Burn = "TorchWarm",
				Freeze = "SystemCyan",
			},
			fullWidth = { Paralysis = true }, -- Paralysis is a full-width red icon because it kills
			fullWidthHeight = 26,
		},
		party = {
			topGap = 14,
			width = 220,
			rowHeight = 30,
			gap = 6,
			barHeight = 8,
			nameTextSize = 13,
			maxRows = 7,
			iconSize = 14,
			skullToken = "HPYellow", -- the Lucid skull beside a member in yellow
		},
		artList = {
			bottomMargin = 36,
			rowHeight = 22,
			gap = 14,
			keyTextSize = 13,
			nameTextSize = 15,
			keyToken = "SystemCyan",
			nameToken = "SystemWhite",
			idleFade = 5, -- seconds of no use before the list fades (section 14)
			fadeSeconds = 0.4,
			restTransparency = 0.25,
		},
		lowHpTint = {
			token = "HPRed",
			maxAlpha = 0.38,
			rampStart = Combat.hpRedFraction, -- tint begins below this HP fraction
			pulseHz = 1.1,
			pulseDepth = 0.3, -- fraction of the alpha that breathes
			edgeFraction = 0.22, -- of the screen each edge gradient covers
		},
		switchPrompt = {
			text = "SWITCH",
			textSize = 30,
			token = "SystemCyan",
			duration = Combat.switchWindow,
			heightStuds = 4.5, -- above the target when a model is given
			fadeOutFraction = 0.7,
			callerTextSize = 16,
			screenYFraction = 0.3, -- fallback position when no target model is known
			billboardSize = { width = 300, height = 60 }, -- pixels
		},
		telegraphIntensity = { default = 1, min = 0.5, max = 1 },
	},

	nameplates = {
		distance = 90, -- studs; plates fade out past this
		fadeBand = 15, -- studs over which the fade happens
		hoverRadiusPixels = 36, -- a player's name shows when the cursor is this close to the plate
		strokeTransparency = 0.5, -- the name's dark stroke; fades with the plate
		player = {
			width = 160,
			height = 44,
			offsetStuds = 3.2,
			diamondSize = 10,
			nameTextSize = 14,
			nameToken = "SystemWhite",
			cursorTokens = { Green = "CursorGreen", Orange = "CursorOrange", Red = "CursorRed" },
			defaultCursor = "Green",
		},
		enemy = {
			width = 180,
			height = 56,
			offsetStuds = 3.6,
			diamondSize = 10,
			diamondToken = "CursorRed",
			nameTextSize = 14,
			nameToken = "SystemWhite",
			hpBar = { width = 120, height = 6, backgroundTransparency = 0.5 },
			gaugeBar = { width = 120, height = 3, token = "SystemCyan", backgroundTransparency = 0.6 },
			gap = 3,
		},
		bossBars = { -- Phase 3 (section 14): a stack under the name card at the top of the screen
			top = 36,
			width = 620,
			barHeight = 9,
			gap = 3,
			nameTextSize = 22,
			nameToken = "CursorRed",
		},
		bossAttribute = "Boss", -- entity models the server marks as bosses get no plate
		poolSize = 40,
		lightInfluence = 0,
		folderName = "SkyspireNameplates", -- the PlayerGui folder the pooled plates live in
	},

	systemLine = {
		screenGuiName = "SkyspireSystem",
		displayOrder = 20,
		textSize = 26,
		largeTextSize = 40, -- the Architect's lines (CursorRed token)
		yFraction = 0.26,
		fadeIn = 0.15,
		hold = 2.4,
		fadeOut = 0.5,
		gap = 0.2, -- seconds between queued lines
		maxQueue = 8,
		strokeTransparency = 0.55,
		defaultToken = "SystemWhite",
		largeTokens = { CursorRed = true },
		chimes = { default = "ui.SystemLine", WardedPurple = "ui.SystemLineWarded" },
	},

	mobile = {
		margin = 16,
		hpBarWidth = 240,
		partyHidden = false,
		artListHidden = true, -- touch buttons carry the Art keys
	},
}

return UI
