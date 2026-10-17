--!strict
--[[
	HudLogic: every numeric decision the HUD makes, with no Instances (section 14).

	HP fraction -> color token (green / yellow / red, colorblind-swapped), the flash rule (the HP
	bar is the only element that flashes, and only when HP goes down), the low-HP screen-edge tint
	alpha, the Art list fade, the Switch prompt fade, the smoothed bar fill and the HP text.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UI = require(Shared.data.ui)

local HudLogic = {}

--- HP as a 0..1 fraction (0 when max is unknown).
function HudLogic.fraction(hp: number, maxHp: number): number
	if maxHp <= 0 then
		return 0
	end
	return math.clamp(hp / maxHp, 0, 1)
end

--- The HP bar's palette token for a fraction: green above half, yellow to a quarter, red below.
function HudLogic.hpToken(fraction: number, colorblind: boolean): string
	local bar = UI.hud.hpBar
	local tokens = if colorblind then bar.colorblindTokens else bar.tokens
	if fraction > bar.yellowFraction then
		return tokens.green
	elseif fraction > bar.redFraction then
		return tokens.yellow
	end
	return tokens.red
end

--- The HP bar flashes only when HP drops (damage), never on heals, binds or respawns.
function HudLogic.shouldFlash(previousHp: number?, newHp: number): boolean
	if previousHp == nil then
		return false
	end
	return newHp < previousHp
end

--- Transparency of the white flash overlay `elapsed` seconds after a flash started (1 = gone).
function HudLogic.flashTransparency(elapsed: number): number
	local bar = UI.hud.hpBar
	if elapsed < 0 or elapsed >= bar.flashSeconds then
		return 1
	end
	local progress = elapsed / bar.flashSeconds
	return bar.flashTransparency + (1 - bar.flashTransparency) * progress * progress
end

--- Alpha of the low-HP screen-edge tint: zero at and above the red fraction, ramping to the max
--- at zero HP, breathing with a slow pulse so it reads as a pulse, not a static overlay.
function HudLogic.lowHpTintAlpha(fraction: number, time: number): number
	local tint = UI.hud.lowHpTint
	if fraction >= tint.rampStart then
		return 0
	end
	local depth = 1 - math.clamp(fraction / tint.rampStart, 0, 1)
	local pulse = 0.5 + 0.5 * math.sin(time * tint.pulseHz * 2 * math.pi)
	local breathing = 1 - tint.pulseDepth * (1 - pulse)
	return tint.maxAlpha * depth * breathing
end

--- Transparency of the bottom-center Art list after `idleSeconds` without a use.
function HudLogic.artListTransparency(idleSeconds: number): number
	local list = UI.hud.artList
	if idleSeconds <= list.idleFade then
		return list.restTransparency
	end
	local progress = math.clamp((idleSeconds - list.idleFade) / list.fadeSeconds, 0, 1)
	return list.restTransparency + (1 - list.restTransparency) * progress
end

--- Transparency of the SWITCH prompt `elapsed` seconds into a window of `duration`.
function HudLogic.switchPromptTransparency(elapsed: number, duration: number): number
	if duration <= 0 or elapsed < 0 or elapsed >= duration then
		return 1
	end
	local fadeFrom = duration * UI.hud.switchPrompt.fadeOutFraction
	if elapsed <= fadeFrom then
		return 0
	end
	return math.clamp((elapsed - fadeFrom) / math.max(1e-6, duration - fadeFrom), 0, 1)
end

--- One step of the bar fill toward the target fraction (exponential approach; never a linear tween).
function HudLogic.smoothFill(current: number, target: number, dt: number): number
	local rate = UI.hud.hpBar.smoothRate
	local alpha = 1 - math.exp(-rate * math.max(0, dt))
	local next = current + (target - current) * alpha
	if math.abs(next - target) < 1e-6 then
		return target
	end
	return next
end

--- The numeric HP line under the bar ("245 / 300").
function HudLogic.hpText(hp: number, maxHp: number): string
	return ("%d / %d"):format(math.floor(hp + 0.5), math.floor(maxHp + 0.5))
end

--- Whether a status icon takes the full row width (Paralysis does, because it kills).
function HudLogic.statusFullWidth(kind: string): boolean
	return UI.hud.statusRow.fullWidth[kind] == true
end

--- Clamps a UI scale setting into the allowed range (nil -> the default, or the mobile default).
function HudLogic.uiScale(setting: number?, touch: boolean): number
	if setting == nil then
		return if touch then UI.scale.mobile else UI.scale.default
	end
	return math.clamp(setting, UI.scale.min, UI.scale.max)
end

--- Clamps the telegraph intensity slider: the minimum is still visible (section 14).
function HudLogic.telegraphIntensity(setting: number?): number
	local range = UI.hud.telegraphIntensity
	if setting == nil then
		return range.default
	end
	return math.clamp(setting, range.min, range.max)
end

return HudLogic
