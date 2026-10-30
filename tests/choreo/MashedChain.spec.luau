--!strict
--[[
	The mashed basic chain (D-399): the client starts the next basic one BasicAttackRequest refill
	after the swing (1/6 s), the earliest the game starts it, so Basic2 starts while Basic1 still
	holds its cut (Basic1's Hold runs 0.15-0.18) and Basic3 while Basic2 does. Each next basic's
	anticipation must read from there (section 10 beat 1: the weapon pulls the opposite way): on the
	anim pass Basic2's pull out of Basic1 is behind the body from the gameplay camera for the whole
	beat, travels 0.38 (60 Hz) to 0.59 (240 Hz) of the 1 asked, runs cos +0.65 with the cut at 240 Hz
	and pops 26 to 27 degrees; Basic3's out of Basic2 runs cos -0.49 to -0.38, drifts the right foot
	0.33 and pops 22 degrees. The basic before it faded out over the next one's blendOut and was
	mixed with it in one priority group, so the next pull showed through the last cut's snap.

	The next basic cuts the one before it (D-408): it takes the body as a snap (choreo.luau
	handOver) and the cut clip holds its pose while it hands over, as every cancel does.

	- Basic3 mashed one refill after Basic2 passes the body review in its "Mash after" plan
	  (ClipAudit.plans): no finding of any kind.
	- Basic2 mashed one refill after Basic1 pulls against the cut: no finding but the
	  anticipation's, and at every review.audit.sampleHz its first strike's pull runs at most
	  anticipation.maxCosine with the cut and travels at least minTravel. Its key 0 stays the ready
	  stance (Basic1's cut there turns the run's hand-off behind the body for the whole beat), so at
	  240 Hz the hand-over's own frames still read in its beat: the speed and hidden shares
	  ClipAudit.spec keeps pending for "Mash after Basic1".
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Dev = Harness.load("src/shared/data/dev")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")

local Audit = Dev.review.audit
local root = Harness.repoRoot()

local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", "HitMatrix may require only Lune libraries")
			return require(target)
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
local avatar, field = HitMatrix.standing(Harness)
local body = ClipAudit.body(avatar.model, "PlayerR15", avatar.base, ClipAudit.topOf(field.CFrame, field.Size))

describe("the mashed basic chain reads its anticipation", function()
	local function mashFindings(name: string, before: string): ({ any }, { any })
		local clip = ClipLibrary.get("player/OneHandedSword/" .. name)
		local reports, findings = ClipAudit.audit(body, clip, ClipLibrary.get)
		local label = "Mash after " .. before
		local mine, mashReports = {}, {}
		for _, finding in ClipAudit.worst(findings) do
			if finding.plan == label then
				table.insert(mine, finding)
			end
		end
		for _, report in reports do
			if report.label == label then
				table.insert(mashReports, report)
			end
		end
		return mine, mashReports
	end

	it("Basic3 mashed one refill after Basic2 passes the body review", function()
		local findings = mashFindings("Basic3", "Basic2")
		local lines = {}
		for _, finding in findings do
			table.insert(lines, finding.text)
		end
		expect(table.concat(lines, "\n")).toBe("")
	end)

	it("Basic2 mashed one refill after Basic1 pulls against the cut and nothing pops", function()
		local findings, reports = mashFindings("Basic2", "Basic1")
		local lines = {}
		for _, finding in findings do
			if finding.kind ~= "Anticipation" then
				table.insert(lines, finding.text)
			end
		end
		expect(#reports).toBe(#Audit.sampleHz)
		for _, report in reports do
			for _, strike in report.strikes do
				if strike.index == 1 then
					if strike.cosine > Audit.anticipation.maxCosine then
						table.insert(
							lines,
							("%d Hz: the pull runs cos %.2f with the cut"):format(report.hz, strike.cosine)
						)
					end
					if strike.travel < Audit.anticipation.minTravel then
						table.insert(lines, ("%d Hz: the pull travels %.2f"):format(report.hz, strike.travel))
					end
				end
			end
		end
		expect(table.concat(lines, "\n")).toBe("")
	end)
end)
