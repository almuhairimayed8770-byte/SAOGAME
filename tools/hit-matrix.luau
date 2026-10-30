--!strict
--[[
	Server hit matrix (section 20 Phase 0 gate: "the server registered every hit").

		lune run tools/hit-matrix.luau [--check] [--real] [setup or attack id ...]

	Swings every Phase 0 player attack (the Playground loadout's Arts, then the basic chain), hit by
	hit, at the boar facing, the boar side-on and the kobold at the root distances in dev.luau
	hitMatrix.setups, and point-blank at either shoulder (fix F2), through the server's own
	CombatService and HitSweep over an engine-faithful fake world (tools/hitmatrix/HitMatrix.luau
	says how), and prints one table per setup with the blade sample that first registered each hit,
	or how far the true blade passed from the enemy when it did not. Each swing is also drawn the
	way the local client draws it (ContactPredictor over the frames a Mixer poses at
	hitMatrix.clientFps), and every hit the client draws must register, and every hit that
	registers must be drawn. It also re-derives each setup's real-fight range from the rigs and
	compares it with the data.

	--real swings only the real-fight placements. Any other argument narrows the run to those setup
	ids (BoarFacing, BoarSide, Kobold, KoboldRightShoulder, ...) and attack ids (OneHandedSword.Horizontal, Basic1, ...).
	--check exits 1 when a required placement (real fight, not point-blank) misses at any frame
	phase or lands only after its strike's snap (in the settle or the recovery), when the client
	and the server disagree on any hit at any placement, or a range in the data disagrees with the
	rigs (tests/server/HitMatrix.spec.luau asserts the same).
]]

local process = require("@lune/process")

local Harness = require("../tests/_harness/Harness")
local HitMatrix = require("./hitmatrix/HitMatrix")

local check = false
local realOnly = false
local setups: { string } = {}
local attacks: { string } = {}
for _, argument in process.args do
	if argument == "--check" then
		check = true
	elseif argument == "--real" then
		realOnly = true
	elseif argument:find("%.") or argument:match("^Basic") then
		table.insert(attacks, argument)
	else
		table.insert(setups, argument)
	end
end

local report = HitMatrix.run(Harness, {
	setups = if #setups > 0 then setups else nil,
	attacks = if #attacks > 0 then attacks else nil,
	realOnly = realOnly,
})
print(table.concat(HitMatrix.render(report), "\n"))

local problems = HitMatrix.misses(report)
for _, line in HitMatrix.lateHits(report) do
	table.insert(problems, line)
end
for _, line in HitMatrix.rangeProblems(report) do
	table.insert(problems, line)
end
for _, line in HitMatrix.drawnNotCounted(report) do
	table.insert(problems, line)
end
for _, line in HitMatrix.countedNotDrawn(report) do
	table.insert(problems, line)
end
print("")
if #problems == 0 then
	print("Every required placement registered on its strike at every frame phase, and the client drew")
	print("exactly the hits the server counted at every placement, frame rate and phase.")
else
	print(("%d problem(s):"):format(#problems))
	for _, line in problems do
		print("  - " .. line)
	end
end
if check and #problems > 0 then
	process.exit(1)
end
