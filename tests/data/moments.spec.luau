--!strict
-- moments.luau (what each combat moment fires) and its validator (tools/validators/moments.luau).
-- The real tables must be clean; each validator case breaks one rule on a copy and expects the
-- validator to name it.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local moments = Harness.load("src/shared/data/moments")
local combat = Harness.load("src/shared/data/combat")
local palette = Harness.load("src/shared/data/palette")

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Runs the validator with tables swapped by path; `missing` paths fail to load like absent files.
local function runValidator(overrides: { [string]: any }?, missing: { [string]: boolean }?): { string }
	local path = "tools/validators/moments.luau"
	local chunk = luau.load(
		fs.readFile(Harness.repoRoot() .. "/" .. path),
		{ debugName = path, environment = Harness.environment() :: any }
	)
	local validate = chunk()
	return validate({
		load = function(modulePath: string): any
			if missing ~= nil and missing[modulePath] then
				error("no " .. modulePath .. " in this case")
			end
			if overrides ~= nil and overrides[modulePath] ~= nil then
				return overrides[modulePath]
			end
			return Harness.load(modulePath)
		end,
		listFiles = Harness.listFiles,
		readFile = Harness.readFile,
		repoRoot = Harness.repoRoot(),
	})
end

local function mentions(problems: { string }, needle: string): boolean
	for _, problem in problems do
		if problem:find(needle, 1, true) then
			return true
		end
	end
	return false
end

-- A copy of moments.luau with `change` applied, through the validator.
local function broken(change: (any) -> ()): { string }
	local copy = deepCopy(moments)
	change(copy)
	return runValidator({ ["src/shared/data/moments"] = copy })
end

-- A copy of another builder's table with `change` applied, through the validator.
local function brokenOther(path: string, change: (any) -> ()): { string }
	local copy = deepCopy(Harness.load(path))
	change(copy)
	return runValidator({ [path] = copy })
end

describe("moments data", function()
	it("passes its validator against the other builders' tables", function()
		local problems = runValidator()
		if #problems > 0 then
			error(table.concat(problems, "\n"), 0)
		end
	end)

	it("has a row for every moment the director plays, with the brief's keys", function()
		local rows = moments.rows
		expect(rows.Hit.glint.size).toBe("Small")
		expect(rows.Hit.cue).toBe("HitNormal")
		expect(rows.Crit.glint.size).toBe("Medium")
		expect(rows.Crit.cue).toBe("HitCrit")
		expect(rows.Guarded.cue).toBe("Block")
		expect(rows.FinalHit.glint.size).toBe("Large")
		expect(rows.FinalHit.glint.trailTint).toBe(true)
		expect(rows.FinalHit.slashArc.size).toBe("Medium")
		expect(rows.FinalHit.slashLine).never.toBeNil()
		expect(rows.FinalHit.impactSequence).toBe("Final")
		expect(rows.FinalHit.cue).toBe("HitFinal")
		expect(rows.FinalHit.contour).toBe("FinalHit")
		expect(rows.FinalHit.punch).toBe("Final")
		-- Section 10 beat 4 and section 11: the hit flash is white, on the final hit and the kill.
		expect(rows.FinalHit.highlight.token).toBe("SystemWhite")
		expect(rows.FinalHit.highlight.frames).toBe(combat.highlightFlashFrames)
		expect(rows.Kill.highlight.token).toBe("SystemWhite")
		expect(rows.Kill.highlight.frames).toBe(combat.highlightFlashFrames)
		expect(rows.Kill.glint.size).toBe("Large")
		expect(rows.Kill.slashArc.size).toBe("Large")
		expect(rows.Kill.slashLine).never.toBeNil()
		expect(rows.Kill.impactSequence).toBe("Kill")
		expect(rows.Kill.cue).toBe("HitKill")
		expect(rows.Kill.contour).toBe("KillCut")
		expect(rows.Kill.punch).toBe("Kill")
		expect(rows.Parry.glint.size).toBe("Parry")
		expect(rows.Parry.impactSequence).toBe("Parry")
		expect(rows.Parry.cue).toBe("Parry")
		expect(rows.Parry.contour).toBe("ParryRing")
		expect(rows.Switch.glint.size).toBe("Medium")
		expect(rows.Switch.trailFlash.partner).toBe(true)
		expect(rows.Activation.riser.sound).toBe("whoosh.Riser")
		expect(rows.Activation.contour).toBe("WindUp")
		expect(rows.Activation.releaseContour).toBe("WindUpRelease")
		expect(rows.Dodge.speedLines.kind).toBe("Dodge")
		expect(rows.Dodge.cue).toBe("Dodge")
		expect(rows.Death.shatterCue).toBe("Shatter")
		expect(rows.BossDeath.shatterCue).toBe("BossShatter")
		expect(rows.Death.contour).toBe("ShatterBloom")
		-- A player's basic swing: its own 4-layer hit, a Normal moment even on the third swing.
		expect(rows.BasicHit.cue).toBe("HitBasic")
		expect(rows.BasicHit.hitStop).toBe("Normal")
		expect(rows.BasicHit.glint.size).toBe("Small")
		expect(rows.GuardBreak.cue).toBe("GuardBreak")
		expect(rows.GuardRaise.sound).toBe("guard.GuardRaise")
		expect(rows.HeavyDeath.shatterCue).toBe("ShatterHeavy")
		expect(rows.HeavyDeath.contour).toBe("ShatterBloom")
	end)

	it(
		"picks a hit's moment parried, killed, Kill tier, guarded, an Art's Final, crit, Switch, basic, else Hit",
		function()
			local order = {}
			for _, rule in moments.select do
				table.insert(order, rule.moment)
			end
			expect(order).toEqual({ "Parry", "Kill", "Kill", "Guarded", "FinalHit", "Crit", "Switch", "BasicHit" })
			expect(moments.fallback).toBe("Hit")
			expect(moments.selectFor({ parried = true, guarded = true })).toBe("Parry")
			-- A death through a guard is still a death.
			expect(moments.selectFor({ guarded = true, killed = true, tier = "Kill" })).toBe("Kill")
			expect(moments.selectFor({ killed = true, tier = "Final" })).toBe("Kill")
			expect(moments.selectFor({ guarded = true, tier = "Final", art = true })).toBe("Guarded")
			expect(moments.selectFor({ tier = "Final", art = true, crit = true })).toBe("FinalHit")
			-- A basic chain's last swing rides the Final hit-stop and stays a basic hit.
			expect(moments.selectFor({ tier = "Final", crit = true })).toBe("Crit")
			expect(moments.selectFor({ tier = "Final" })).toBe("Hit")
			expect(moments.selectFor({ crit = true, isSwitch = true })).toBe("Crit")
			expect(moments.selectFor({ isSwitch = true })).toBe("Switch")
			expect(moments.selectFor({ tier = "Normal" })).toBe("Hit")
			-- A player's basic swing (art false) plays BasicHit, its third swing's Final hit-stop too;
			-- a parry, a kill, a guard and a crit still win. An enemy's strike (art nil) stays Hit.
			expect(moments.selectFor({ tier = "Normal", art = false })).toBe("BasicHit")
			expect(moments.selectFor({ tier = "Final", art = false })).toBe("BasicHit")
			expect(moments.selectFor({ art = false, parried = true })).toBe("Parry")
			expect(moments.selectFor({ art = false, killed = true, tier = "Kill" })).toBe("Kill")
			expect(moments.selectFor({ art = false, guarded = true })).toBe("Guarded")
			expect(moments.selectFor({ art = false, crit = true, tier = "Final" })).toBe("Crit")
			expect(moments.selectFor({ tier = "Normal", art = true })).toBe("Hit")
			expect(moments.matches({ when = { tier = "Final", art = true }, moment = "FinalHit" }, { tier = "Final" })).toBe(
				false
			)
		end
	)

	it("keeps impact frames, the punch and a hit's contour for the people in the fight", function()
		for _, name in moments.list() do
			expect(moments.audienceOf(name, "ImpactFrames")).toBe("Involved")
			expect(moments.audienceOf(name, "Punch")).toBe("Involved")
		end
		expect(moments.audienceOf("FinalHit", "Contour")).toBe("Involved")
		expect(moments.audienceOf("Death", "Contour")).toBe("Range")
		expect(moments.audienceOf("Dodge", "Cue")).toBe("Range")
		expect(moments.audienceOf("Hit", "Cue")).toBe("Always")
		-- The white hit flash reaches everyone, as Replication's did.
		expect(moments.audienceOf("FinalHit", "Highlight")).toBe("Always")
		expect(moments.audienceOf("Kill", "Highlight")).toBe("Always")
	end)

	it("ranges: a row's own, else the accent range", function()
		expect(moments.rangeOf("FinalHit")).toBe(moments.accentRange)
		expect(moments.rangeOf("Hit")).toBe(moments.rows.Hit.range)
		expect(moments.rangeOf("Hit")).toBeLessThan(moments.rangeOf("Kill"))
	end)

	it("the death silence waits for the kill's hit-stop", function()
		expect(moments.deathDuckDelay()).toBeCloseTo(combat.hitStopFrames.Kill * combat.hitStopFrameSeconds, 1e-12)
	end)

	it("picks the death row: a boss's, a player's or an Elite's heavy one, else the plain one", function()
		expect(moments.deathFor(true)).toBe("BossDeath")
		expect(moments.deathFor(true, true)).toBe("BossDeath")
		expect(moments.deathFor(false, true)).toBe("HeavyDeath")
		expect(moments.deathFor(false, false)).toBe("Death")
		expect(moments.deathFor(false)).toBe("Death")
	end)

	it("merges one sweep's hits inside a short window", function()
		-- Up to 12 confirmations of one swing land over about 3 server frames and arrive with a
		-- frame or two of jitter: the window spans at least 5 frames. An Art's next hit is a damage
		-- window later (the validator holds the window under the closest pair).
		local frames = moments.sweep.mergeSeconds / combat.hitStopFrameSeconds
		expect(frames).toBeGreaterThanOrEqual(5)
		expect(moments.sweep.mergeSeconds).toBeLessThan(combat.hitStopFrames.Kill * combat.hitStopFrameSeconds * 2)
	end)

	it("names only palette tokens", function()
		expect(palette.tokens[moments.rows.Guarded.glint.token]).never.toBeNil()
	end)

	it("errors on an unknown moment and lists the rows sorted", function()
		expect(function()
			moments.byId("Nope")
		end).toThrow("unknown moment 'Nope'")
		local names = moments.list()
		local sorted = table.clone(names)
		table.sort(sorted)
		expect(names).toEqual(sorted)
		expect(#names).toBe(15)
	end)
end)

describe("moments validator", function()
	it("reports a builder's file that is not there yet", function()
		local problems = runValidator(nil, { ["src/shared/data/sfx"] = true })
		expect(mentions(problems, "src/shared/data/sfx.luau is not there yet (the SOUND builder's table)")).toBe(true)
		local noImpact = runValidator(nil, { ["src/shared/data/impact"] = true })
		expect(mentions(noImpact, "src/shared/data/impact.luau is not there yet (the FRAMES builder's table)")).toBe(
			true
		)
	end)

	it("reports a table a builder has not added yet, once", function()
		local problems = brokenOther("src/shared/data/sfx", function(sfx)
			sfx.cues = nil
		end)
		local count = 0
		for _, problem in problems do
			if problem:find("sfx.cues is missing", 1, true) then
				count += 1
			end
		end
		expect(count).toBe(1)
	end)

	it("catches keys the other tables do not have", function()
		local problems = broken(function(copy)
			copy.rows.Hit.glint.size = "Enormous"
			copy.rows.Kill.slashArc.size = "Tiny"
			copy.rows.FinalHit.slashLine.size = "Wide"
			copy.rows.Dodge.speedLines.kind = "Roll"
			copy.rows.Parry.impactSequence = "Flashbang"
			copy.rows.Crit.cue = "HitHuge"
			copy.rows.Death.shatterCue = "Explode"
			copy.rows.Kill.contour = "Wobble"
			copy.rows.Switch.sound = "ui.Nope"
			copy.rows.Activation.riser.sound = "whoosh"
		end)
		expect(mentions(problems, "rows.Hit.glint names glint size 'Enormous'")).toBe(true)
		expect(mentions(problems, "rows.Kill.slashArc names slash crescent size 'Tiny'")).toBe(true)
		expect(mentions(problems, "rows.FinalHit.slashLine names slash line size 'Wide'")).toBe(true)
		expect(mentions(problems, "rows.Dodge.speedLines names speed-line kind 'Roll'")).toBe(true)
		expect(mentions(problems, "rows.Parry.impactSequence names impact sequence 'Flashbang'")).toBe(true)
		expect(mentions(problems, "rows.Crit.cue names cue 'HitHuge'")).toBe(true)
		expect(mentions(problems, "rows.Death.shatterCue names cue 'Explode'")).toBe(true)
		expect(mentions(problems, "rows.Kill.contour names contour 'Wobble'")).toBe(true)
		expect(mentions(problems, "rows.Switch.sound names sound 'ui.Nope'")).toBe(true)
		expect(mentions(problems, "rows.Activation.riser.sound 'whoosh' is not 'family.Name'")).toBe(true)
	end)

	it("catches a key another builder renamed", function()
		local problems = brokenOther("src/shared/data/camera", function(camera)
			camera.punch.Kill = nil
		end)
		expect(mentions(problems, "rows.Kill.punch names camera punch 'Kill', which camera.luau does not have")).toBe(
			true
		)
		local noContour = brokenOther("src/shared/data/sfx", function(sfx)
			sfx.contours.ParryRing = nil
		end)
		expect(mentions(noContour, "rows.Parry.contour names contour 'ParryRing'")).toBe(true)
		-- The shatter plays sfx.shatterCues; the death rows must name the same cues.
		local otherShatter = brokenOther("src/shared/data/sfx", function(sfx)
			sfx.shatterCues.boss = "Shatter"
		end)
		expect(
			mentions(otherShatter, "rows.BossDeath.shatterCue 'BossShatter' must be sfx.shatterCues.boss ('Shatter')")
		).toBe(true)
		expect(mentions(otherShatter, "rows.Death.shatterCue")).toBe(false)
	end)

	it("catches a sequence or a punch on another tier than the moment's hit-stop", function()
		local problems = broken(function(copy)
			copy.rows.FinalHit.impactSequence = "Kill"
			copy.rows.Kill.punch = "Final"
		end)
		expect(mentions(problems, "rows.FinalHit plays impact sequence 'Kill', which rides on the Kill hit-stop")).toBe(
			true
		)
		expect(mentions(problems, "rows.Kill punch 'Final' must be its hitStop tier 'Kill'")).toBe(true)
	end)

	it("catches tokens that are not in the palette and a highlight with no color", function()
		local problems = broken(function(copy)
			copy.rows.Guarded.glint.token = "#888888"
			copy.rows.FinalHit.highlight.token = nil
		end)
		expect(mentions(problems, "rows.Guarded.glint.token '#888888' is not a palette token")).toBe(true)
		expect(mentions(problems, "rows.FinalHit.highlight needs exactly one of token and trailTint")).toBe(true)
	end)

	it("never lets impact frames, the punch or a hit's contour reach bystanders", function()
		local defaults = broken(function(copy)
			copy.audience.ImpactFrames = "Range"
			copy.audience.Punch = "Always"
		end)
		expect(mentions(defaults, "audience.ImpactFrames must be Involved")).toBe(true)
		expect(mentions(defaults, "audience.Punch must be Involved")).toBe(true)
		local override = broken(function(copy)
			copy.rows.Kill.audience = { ImpactFrames = "Always", Contour = "Range" }
			copy.rows.Hit.audience = { Glow = "Range", Cue = "Loud" }
		end)
		expect(mentions(override, "rows.Kill.audience.ImpactFrames must stay Involved")).toBe(true)
		expect(mentions(override, "rows.Kill.audience.Contour must stay Involved")).toBe(true)
		expect(mentions(override, "rows.Hit.audience.Glow is not an effect the director fires")).toBe(true)
		expect(mentions(override, "rows.Hit.audience.Cue 'Loud' must be Always, Range or Involved")).toBe(true)
	end)

	it("catches a broken selection, a missing row and a range past the glint's reach", function()
		local problems = broken(function(copy)
			table.insert(copy.select, { when = { lucky = true }, moment = "Hit" })
			table.insert(copy.select, { when = { crit = "yes" }, moment = "Crit" })
			table.insert(copy.select, { when = { tier = "Huge" }, moment = "Kill" })
			table.insert(copy.select, { when = { crit = true }, moment = "Ghost" })
			table.insert(copy.select, { when = {}, moment = "Hit" })
			copy.fallback = "Nothing"
			copy.rows.Switch = nil
			copy.rows.Kill.range = 10000
		end)
		expect(mentions(problems, "tests 'lucky', which is not a hit field")).toBe(true)
		expect(mentions(problems, "compares crit to a string, not a boolean")).toBe(true)
		expect(mentions(problems, "tier 'Huge' is not a hit-stop tier")).toBe(true)
		expect(mentions(problems, "names moment 'Ghost', which has no row")).toBe(true)
		expect(mentions(problems, "select[13] must be { when = { field = value, ... }, moment }")).toBe(true)
		expect(mentions(problems, "fallback must name a moment with a row")).toBe(true)
		expect(mentions(problems, "the director plays 'Switch', which has no row")).toBe(true)
		expect(mentions(problems, "rows.Kill range 10000 is past the glint's draw distance")).toBe(true)
	end)

	it("sends every death to a Kill moment, even through a guard", function()
		local problems = broken(function(copy)
			-- The old order: guarded before killed.
			local guarded = table.remove(copy.select, 4)
			table.insert(copy.select, 2, guarded)
		end)
		expect(mentions(problems, "select plays 'Guarded' (hitStop Normal) for a hit (tier Kill, guarded)")).toBe(true)
		expect(mentions(problems, "a death plays the Kill moment, even through a guard")).toBe(true)
	end)

	it("gives an Art's final hit a Final moment and keeps a basic chain's last swing a basic hit", function()
		local basic = broken(function(copy)
			copy.select[5].when.art = nil
		end)
		expect(mentions(basic, "select plays 'FinalHit' (hitStop Final) for a hit (tier Final)")).toBe(true)
		expect(mentions(basic, "stays a Normal moment (basics are weak)")).toBe(true)
		local noFinal = broken(function(copy)
			table.remove(copy.select, 5)
		end)
		expect(mentions(noFinal, "select plays 'Hit' (hitStop Normal) for a hit (tier Final, art)")).toBe(true)
		expect(mentions(noFinal, "an Art's final hit plays a Final-tier moment")).toBe(true)
	end)

	it("needs the bass back before a sub layer thumps", function()
		-- The old FinalHit contour: the SFX bass only starts back as HitFinal's sub plays.
		local problems = brokenOther("src/shared/data/sfx", function(sfx)
			local hold = combat.hitStopFrames.Final * combat.hitStopFrameSeconds
			sfx.contours.FinalHit[3] = { at = hold, group = "SFX", low = 0, ramp = 0.04 }
		end)
		expect(mentions(problems, "rows.FinalHit: cue HitFinal layer 5 (impact.Sub) starts at 0.100 s")).toBe(true)
		expect(mentions(problems, "SFX low band at -36.0 dB under contour FinalHit")).toBe(true)
		-- A sub that waits for the ramp is fine too.
		local later = brokenOther("src/shared/data/sfx", function(sfx)
			local hold = combat.hitStopFrames.Final * combat.hitStopFrameSeconds
			sfx.contours.FinalHit[3] = { at = hold, group = "SFX", low = 0, ramp = 0.04 }
			sfx.cues.HitFinal[5].delay = hold + 0.04
		end)
		expect(mentions(later, "the bass must be back")).toBe(false)
	end)

	it("checks the activation's release contour", function()
		local problems = broken(function(copy)
			copy.rows.Activation.releaseContour = "Unwind"
			copy.rows.Dodge.releaseContour = "WindUpRelease"
		end)
		expect(mentions(problems, "rows.Activation.releaseContour names contour 'Unwind'")).toBe(true)
		expect(mentions(problems, "rows.Dodge has a releaseContour but no contour for it to end")).toBe(true)
	end)

	it("keeps the heavy death on the heavy shatter cue", function()
		local problems = broken(function(copy)
			copy.rows.HeavyDeath.shatterCue = "Shatter"
		end)
		expect(
			mentions(problems, "rows.HeavyDeath.shatterCue 'Shatter' must be sfx.shatterCues.heavy ('ShatterHeavy')")
		).toBe(true)
		local noRow = broken(function(copy)
			copy.rows.HeavyDeath = nil
			copy.rows.GuardRaise = nil
		end)
		expect(mentions(noRow, "the director plays 'HeavyDeath', which has no row")).toBe(true)
		expect(mentions(noRow, "the director plays 'GuardRaise', which has no row")).toBe(true)
	end)

	it("keeps the sweep merge positive and short of an Art's next damage window", function()
		local zero = broken(function(copy)
			copy.sweep.mergeSeconds = 0
		end)
		expect(mentions(zero, "sweep.mergeSeconds must be a positive number of seconds")).toBe(true)
		local missing = broken(function(copy)
			copy.sweep = nil
		end)
		expect(mentions(missing, "sweep.mergeSeconds must be a positive number of seconds")).toBe(true)
		-- A merge as long as a whole swing would swallow a multi-hit Art's second hit.
		local long = broken(function(copy)
			copy.sweep.mergeSeconds = 10
		end)
		expect(mentions(long, "sweep.mergeSeconds 10.000 s must be shorter than player/")).toBe(true)
		expect(mentions(long, "between two damage windows")).toBe(true)
	end)

	it("keeps the death silence after the kill's hit-stop", function()
		local problems = broken(function(copy)
			copy.death.duckDelayFrames = combat.hitStopFrames.Kill - 1
		end)
		expect(mentions(problems, "death.duckDelayFrames must be at least the kill's hit-stop")).toBe(true)
	end)
end)
