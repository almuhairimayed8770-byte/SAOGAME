--!strict
--[[
	Gait clip generator: the locomotion loops under src/shared/clips/player/OneHandedSword/
	(WalkForward, WalkBack, WalkLeft, WalkRight, Run, Sprint and their Drawn twins; D-054, D-128,
	D-134, D-135).

		lune run tools/gaitgen.luau [--check] [Gait ...]

	Run it from the repo root. With no gait named it rewrites every clip it owns except the
	DRIFTED ones in tools/gaitgen/GaitGen.luau (Run and Sprint, whose upper bodies were re-keyed by
	hand after generation); name gaits (WalkForward RunDrawn ...) to rewrite only those. The files it
	writes are already StyLua-formatted. --check writes nothing: it regenerates every clip it checks
	(or the named ones) in memory and exits 1 when any differs from the committed file, byte for
	byte; tests/tools/gaitgen.spec.luau runs the same check so a hand edit that drifts from the
	generator fails CI.

	Both sets' legs are twins (D-134): every drawn clip has its sheathed twin's plans, key times,
	Footsteps and pelvis height, so the drawn feet plant exactly where the sheathed ones do. Change
	a gait's feet, keys or sheathed upper body in tools/gaitgen/Gaits.luau, and a drawn upper body
	(or WalkForward's arm swing) in its pinned source clip in tools/gaitgen/sources/, then
	regenerate both sets together. After a change that moves the feet, re-measure
	locomotion.stride.groundSpeed and touchdown in src/shared/data/choreo.luau
	(tests/choreo/Stride.spec.luau checks them) and regenerate docs/ANIMATION_REVIEW.md
	(lune run tools/animation-review.luau).
]]

local process = require("@lune/process")

local Harness = require("../tests/_harness/Harness")
local GaitGen = require("./gaitgen/GaitGen")

local check = false
local named: { string } = {}
for _, argument in process.args do
	if argument == "--check" then
		check = true
	else
		table.insert(named, argument)
	end
end

if check then
	local names = if #named > 0 then named else GaitGen.checked()
	local drifts = GaitGen.check(Harness, names)
	if #named == 0 then
		for _, name in GaitGen.NAMES do
			local reason = GaitGen.DRIFTED[name]
			if reason then
				print(("skipped %s: %s"):format(name, reason))
			end
		end
	end
	if #drifts == 0 then
		print(("%d gait clip(s) match the generator."):format(#names))
		return
	end
	for _, drift in drifts do
		print(GaitGen.describe(drift))
	end
	print(
		("%d of %d gait clip(s) differ from the generator (lune run tools/gaitgen.luau <Gait> rewrites one)."):format(
			#drifts,
			#names
		)
	)
	process.exit(1)
end

local names: { string } = named
if #names == 0 then
	names = GaitGen.checked()
	for _, name in GaitGen.NAMES do
		local reason = GaitGen.DRIFTED[name]
		if reason then
			print(("left %s alone: %s (name it to rewrite it)"):format(name, reason))
		end
	end
end
for _, name in names do
	local reason = GaitGen.DRIFTED[name]
	if reason then
		print(("warning: rewriting %s loses its hand edits: %s"):format(name, reason))
	end
	local result = GaitGen.generate(Harness, name)
	for _, miss in result.misses do
		print("  " .. miss)
	end
	print(("%s: worst foot error %.4f studs"):format(name, result.worstError))
	GaitGen.write(Harness, result)
	print("wrote " .. result.path)
end
