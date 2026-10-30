--!strict
--[[
	The body review judges a tell from every view its rig lists (dev.luau review.audit.rigs.<rig>
	.views, D-402 amended as D-414). The gameplay camera sees the player from behind and an enemy
	from in front, where the player squares up to it; a player circling an enemy sees its tell from
	behind as well, and that view was not measured at all: the boar's Charge tusk is behind its own
	body from there for the whole anticipation, the kobold's axe for some of it. The tells the game
	shows from behind are the Telegraphs (the lit tell and the ground cone, section 9), not the
	pose, so the enemies list Front alone and the review records the Behind share beside it.

	- Every audited rig lists its views: at least one, each Behind or Front, none twice; the player
	  Behind, the enemies Front.
	- A strike's anticipation records its hidden share from every view (hiddenViews), and its
	  hidden share is the worst of the listed ones.
	- Given Behind as well, the boar's Charge anticipation reads hidden from behind (the share the
	  open issue names) while its Front share stays what the review passes.
]]

local Dev = Harness.load("src/shared/data/dev")
local ClipAudit = Harness.load("src/client/dev/ClipAudit")
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local RigBuilder = Harness.load("src/server/world/RigBuilder")

local Audit = Dev.review.audit

-- The boar standing on its field, as ClipAudit.spec stands it.
local function boarBody(): any
	return ClipAudit.standingBody(RigBuilder.build("Boar"), "Boar")
end

local function chargeStrike(body: any): any
	local clip = ClipLibrary.get("enemy/Boar/Charge")
	for _, plan in ClipAudit.plans(clip, ClipLibrary.get) do
		if plan.label == "Stand@0" or plan.label == "Lab" then
			local report = ClipAudit.run(body, clip, plan, 60)
			return report.strikes[1]
		end
	end
	return nil
end

describe("the body review judges a tell from every view its rig lists", function()
	it("lists the views of every audited rig: the player Behind, the enemies Front", function()
		for rigId, config in Audit.rigs do
			expect(typeof(config.views)).toBe("table")
			expect(#config.views >= 1).toBe(true)
			local seen: { [string]: boolean } = {}
			for _, view in config.views do
				expect(view == "Behind" or view == "Front").toBe(true)
				expect(seen[view]).toBeNil()
				seen[view] = true
			end
			expect(config.views[1]).toBe(if rigId == "PlayerR15" then "Behind" else "Front")
		end
	end)

	it("records the boar Charge's anticipation hidden from each view it is given", function()
		local body = boarBody()
		local front = chargeStrike(body)
		expect(front).never.toBeNil()
		expect(front.hiddenViews).never.toBeNil()
		expect(front.hiddenViews.Front).toBe(front.hidden)
		expect(front.hiddenViews.Behind).toBeNil()
		expect(front.hidden <= Audit.anticipation.maxHiddenShare).toBe(true)

		body.views = { "Front", "Behind" }
		local both = chargeStrike(body)
		expect(both.hiddenViews.Front).toBe(front.hidden)
		-- From behind, the tusk is behind the boar's own body for the whole beat.
		expect(both.hiddenViews.Behind > Audit.anticipation.maxHiddenShare).toBe(true)
		expect(both.hidden).toBe(math.max(both.hiddenViews.Front, both.hiddenViews.Behind))
	end)
end)
