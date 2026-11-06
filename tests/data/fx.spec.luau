--!strict
-- fx.luau outline: the Highlight budget and the ranks that spend it (section 11, D-476). A rig
-- showing a hit's flash or a telegraph's tint ranks at signalRank: after Boss, Lock and Party,
-- before a resting Normal outline, and the budget never passes the engine's cap.
local Fx = Harness.load("src/shared/data/fx")
local OutlineRanking = Harness.load("src/client/fx/OutlineRanking")

describe("fx.outline (D-476)", function()
	it("spends at most the engine's 31 Highlights", function()
		expect(Fx.budgets.highlights).toBe(31)
		expect(Fx.outline.budget <= Fx.budgets.highlights).toBe(true)
	end)

	it("ranks a signal after every always-on importance and before a resting outline", function()
		local ranks = Fx.outline.importanceRank
		expect(typeof(Fx.outline.signalRank)).toBe("number")
		for importance in Fx.outline.alwaysOn do
			expect(ranks[importance] < Fx.outline.signalRank).toBe(true)
		end
		expect(Fx.outline.signalRank < ranks.Normal).toBe(true)
	end)

	it("OutlineRanking reads it: a flashing Normal rig at signalRank, a flashing boss keeps its own", function()
		local ranks = Fx.outline.importanceRank
		local key = {}
		expect(OutlineRanking.rank({ key = key, importance = "Normal", distance = 1, signal = true })).toBe(
			Fx.outline.signalRank
		)
		expect(OutlineRanking.rank({ key = key, importance = "Normal", distance = 1 })).toBe(ranks.Normal)
		expect(OutlineRanking.rank({ key = key, importance = "Boss", distance = 1, signal = true })).toBe(ranks.Boss)
		-- A signal past the outline distance is still eligible; a resting one is not.
		local _, set = OutlineRanking.select({
			{ key = "far-flash", importance = "Normal", distance = 1000, signal = true },
			{ key = "far-rest", importance = "Normal", distance = 1000 },
		}, Fx.outline.budget, Fx.outline.distance)
		expect(set["far-flash"]).toBe(true)
		expect(set["far-rest"]).toBeNil()
	end)
end)

describe("fx.audio.airFloorStates (D-636)", function()
	it("keeps a walking character's last floor on an Air read: the walking states, no airborne one", function()
		-- AS 518(i): a copy that read Air while Running for 30 s on grass played the stone set.
		local states = Fx.audio.airFloorStates
		expect(table.find(states, "Running") ~= nil).toBe(true)
		for _, airborne in { "Freefall", "Jumping", "FallingDown", "Ragdoll", "Flying", "Landed" } do
			expect(table.find(states, airborne)).toBeNil()
		end
		-- Air itself is no floor: it maps to no surface, so it never becomes the floor kept.
		expect((Fx.audio.materialSurface :: any).Air).toBeNil()
	end)
end)
