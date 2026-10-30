--!strict
--[[
	Animation review report (section 10 "Review loop", section 21 gate line 2).

		lune run tools/animation-review.luau [--check]

	Regenerates docs/ANIMATION_REVIEW.md: one table line per clip under src/shared/clips with the
	columns ReviewMarkers derives from the data (the six beats present / frame counts at 60 fps,
	hit-stop tier, hit count, trail timing against the hit windows, root motion in studs, duration,
	problems the review rules found: ReviewMarkers' rules on the data, then for every clip
	dev.luau review.audit.clips lists the worst ClipAudit finding of each kind, the clip played
	through the real Mixer on the real rigs) followed by the three hand-filled columns from data/dev.luau
	review.humanColumns ("Watched at 0.25x", "Problems seen", "Fixed"). Hand-filled cells of an
	existing report are carried over by clip id, so regenerating after a clip edit never loses a
	review note.

	--check writes nothing and exits 1 when the file would change (CI: the report is stale).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local Harness = require("../tests/_harness/Harness")

local root = Harness.repoRoot()
local Dev = Harness.load("src/shared/data/dev")
local Rigs = Harness.load("src/shared/data/rigs")
local ReviewMarkers = Harness.load("src/client/dev/ReviewMarkers")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local RigBuilder = Harness.load("src/server/world/RigBuilder")

-- The hit matrix's player (the character the game builds) is a tool module, loaded with Lune
-- libraries only (as tests/choreo/GroundClearance.spec.luau loads it).
local function loadTool(path: string): any
	local source = fs.readFile(root .. "/" .. path .. ".luau")
	local env = {
		require = function(target: string): any
			assert(target:sub(1, 6) == "@lune/", path .. " may require only Lune libraries")
			return require(target) :: any
		end,
	}
	return luau.load(source, { debugName = path, environment = env :: any })()
end

local Review = Dev.review
local outputPath = root .. "/" .. Review.outputPath
local check = table.find(process.args, "--check") ~= nil

-- -----------------------------------------------------------------------------------------
-- Load every clip
-- -----------------------------------------------------------------------------------------

type Loaded = { id: string, path: string, clip: any?, err: string? }

local loaded: { Loaded } = {}
for _, file in Harness.listFiles(Review.clipsDirectory, "%.luau$") do
	local id = file:match("^" .. Review.clipsDirectory:gsub("%p", "%%%0") .. "/(.-)%.luau$")
	if id == nil then
		continue
	end
	local ok, clip = pcall(Harness.load, (file:gsub("%.luau$", "")))
	if ok then
		table.insert(loaded, { id = id, path = file, clip = clip })
	else
		table.insert(loaded, { id = id, path = file, err = tostring(clip) })
	end
end

-- Pedestal order (player, boar, kobold) then any other rig; attacks first inside a rig.
local rigRank: { [string]: number } = {}
for index, entry in Dev.clipLab.rigs do
	rigRank[entry.rig] = index
end
table.sort(loaded, function(a, b)
	local rigA = if a.clip then a.clip.rig else ""
	local rigB = if b.clip then b.clip.rig else ""
	local rankA = rigRank[rigA] or (#Dev.clipLab.rigs + 1)
	local rankB = rigRank[rigB] or (#Dev.clipLab.rigs + 1)
	if rankA ~= rankB then
		return rankA < rankB
	end
	if rigA ~= rigB then
		return rigA < rigB
	end
	local attackA = a.clip ~= nil and a.clip.attack == true
	local attackB = b.clip ~= nil and b.clip.attack == true
	if attackA ~= attackB then
		return attackA
	end
	return a.id < b.id
end)

-- -----------------------------------------------------------------------------------------
-- The clip audit (dev.luau review.audit.clips)
-- -----------------------------------------------------------------------------------------

local auditLines: { [string]: { string } } = {}
do
	local HitMatrix = loadTool("tools/hitmatrix/HitMatrix")
	local avatar, field = HitMatrix.standing(Harness)
	local bodies: { [string]: any } = {
		PlayerR15 = ClipAudit.body(avatar.model, "PlayerR15", avatar.base, ClipAudit.topOf(field.CFrame, field.Size)),
	}
	for _, id in Review.audit.clips do
		local clip = ClipLibrary.get(id)
		if bodies[clip.rig] == nil then
			bodies[clip.rig] = ClipAudit.standingBody(RigBuilder.build(clip.rig), clip.rig)
		end
		local _, findings = ClipAudit.audit(bodies[clip.rig], clip, ClipLibrary.get)
		auditLines[id] = ClipAudit.problemLines(findings)
	end
end

-- -----------------------------------------------------------------------------------------
-- Carry hand-filled cells over from the existing report
-- -----------------------------------------------------------------------------------------

local header = ReviewMarkers.markdownHeader()
local columnCount = #ReviewMarkers.splitMarkdownLine(header[1])
local humanCount = #Review.humanColumns

local carried: { [string]: { string } } = {}
if fs.isFile(outputPath) then
	for line in fs.readFile(outputPath):gmatch("[^\n]+") do
		local cells = ReviewMarkers.splitMarkdownLine(line)
		local id = cells[1] and cells[1]:match("^`(.-)`$")
		if id ~= nil and #cells == columnCount then
			local hand = {}
			for index = 1, humanCount do
				hand[index] = cells[columnCount - humanCount + index]
			end
			carried[id] = hand
		end
	end
end

-- -----------------------------------------------------------------------------------------
-- Build the document
-- -----------------------------------------------------------------------------------------

local lines: { string } = {}
local function add(line: string)
	table.insert(lines, line)
end

local fps: number = Review.fps
local attackCount = 0
local problemCount = 0
local brokenCount = 0

add("# Animation review")
add("")
add(
	("Generated by `lune run tools/animation-review.luau` from the clip data under `%s`. Do not edit the"):format(
		Review.clipsDirectory
	)
)
add("generated columns by hand; fix the clip and regenerate. The last three columns are filled in by")
add("the reviewer after watching the clip in the ClipLab at 0.25x (section 10 review loop) and survive a")
add("regeneration, matched by clip id.")
add("")
add("## Columns")
add("")
add(
	("- **Clip / Rig / Kind / Duration**: the clip id, its rig, attack / loop / one-shot, seconds and frames at %d fps."):format(
		fps
	)
)
add(
	("- **%s**: for an attack, `Y <frames>` when the beat is defined, `N` when it is missing. Section 10 budgets:"):format(
		table.concat(Review.beats, " / ")
	)
)
add(
	("  Anticipation %d..%d frames, Snap %d..%d, Smear %d, Settle %d..%d (enemies may hold Anticipation longer: the wind-up)."):format(
		Review.anticipationFrames.min,
		Review.anticipationFrames.max,
		Review.snapFrames.min,
		Review.snapFrames.max,
		Review.smearFrames,
		Review.settleFrames.min,
		Review.settleFrames.max
	)
)
add("- **Hit-stop**: the clip's tier (Normal 3 / Final 6 / Kill 10 frames, section 6) or `-`.")
add("- **Hits**: HitWindowOpen / HitWindowClose pairs.")
add(
	"- **Trail vs windows**: how many frames before the first hit window the trail ignites and how many after the last it goes"
)
add(
	("  off (allowed: %d early, %d late); `uncovered` names a window with no trail, `stray` a trail span outside every window."):format(
		Review.trailLeadFramesMax,
		Review.trailLagFramesMax
	)
)
add("- **Root motion**: studs between the first and last root key.")
add("- **Problems found**: everything the review rules (`src/client/dev/ReviewMarkers.luau`) flag, then for an audited")
add(
	"  clip the worst finding of each kind the body audit (`src/client/dev/ClipAudit.luau`, played through the Mixer on"
)
add("  the real rigs at 60 and 240 Hz) reports, with the clip frame and the context; `none` is the goal.")
add(
	("- **%s**: hand-filled; `yes <date>` once the clip was watched frame by frame in the ClipLab."):format(
		Review.humanColumns[1]
	)
)
add(
	("- **%s**: hand-filled; what looked wrong against section 2 / section 10 while watching."):format(
		Review.humanColumns[2]
	)
)
add(("- **%s**: hand-filled; the clip edit or commit that fixed it, or `open`."):format(Review.humanColumns[3]))
add("")
add("## Clips")
add("")
for _, line in header do
	add(line)
end
for _, item in loaded do
	if item.clip == nil then
		brokenCount += 1
		local cells = { ("`%s`"):format(item.id), "-", "broken", "-" }
		for _ in Review.beats do
			table.insert(cells, "-")
		end
		for _, value in { "-", "-", "-", "-", ("does not load: %s"):format((item.err or ""):gsub("|", "/")) } do
			table.insert(cells, value)
		end
		local hand = carried[item.id] or {}
		for index = 1, humanCount do
			table.insert(cells, hand[index] or "")
		end
		add("| " .. table.concat(cells, " | ") .. " |")
		continue
	end
	local row = ReviewMarkers.row(item.clip)
	for _, line in auditLines[item.id] or {} do
		table.insert(row.problems, line)
	end
	if row.attack then
		attackCount += 1
	end
	if #row.problems > 0 then
		problemCount += 1
	end
	add(ReviewMarkers.markdownLine(row, carried[item.id]))
end
add("")
add("## Summary")
add("")
add(
	("- %d clips (%d attacks) across %d rigs; %d with problems found by the rules; %d that do not load."):format(
		#loaded,
		attackCount,
		(function(): number
			local seen: { [string]: boolean } = {}
			local count = 0
			for _, item in loaded do
				if item.clip ~= nil and not seen[item.clip.rig] then
					seen[item.clip.rig] = true
					count += 1
				end
			end
			return count
		end)(),
		problemCount,
		brokenCount
	)
)
do
	local missing = {}
	for _, item in loaded do
		if item.clip ~= nil and Rigs[item.clip.rig] == nil then
			table.insert(missing, item.id)
		end
	end
	if #missing > 0 then
		add(("- Clips whose rig is not in rigs.luau: %s."):format(table.concat(missing, ", ")))
	end
end
add("- Watch every attack at 0.25x in `places/ClipLab.rbxl` before a gate and fill the last three columns.")
add("")

local content = table.concat(lines, "\n")

if check then
	local existing = if fs.isFile(outputPath) then fs.readFile(outputPath) else ""
	if existing ~= content then
		stdio.ewrite(("%s is stale: run `lune run tools/animation-review.luau`\n"):format(Review.outputPath))
		process.exit(1)
	end
	stdio.write(("%s is current (%d clips)\n"):format(Review.outputPath, #loaded))
	return
end

local directory = outputPath:match("^(.*)/[^/]+$")
if directory ~= nil and not fs.isDir(directory) then
	fs.writeDir(directory)
end
fs.writeFile(outputPath, content)
stdio.write(
	("wrote %s: %d clips, %d attacks, %d with problems, %d broken\n"):format(
		Review.outputPath,
		#loaded,
		attackCount,
		problemCount,
		brokenCount
	)
)
