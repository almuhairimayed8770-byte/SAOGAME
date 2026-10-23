--!strict
-- FlashBudget: full-screen flashes never exceed impact.flash.maxPerWindow in any rolling window
-- of impact.flash.windowSeconds. A refused request records nothing (the caller dims instead), a
-- cost expires exactly one window after its picture's last change (its finish: the request
-- time plus `seconds`, pushed later by `hold`), a claim can be raised by the difference only,
-- and the Reduce flashing setting comes from the local player's attribute. Times are passed in
-- by hand: the spec is the clock.
local FlashBudget = Harness.load("src/client/fx/FlashBudget")
local ImpactSequence = Harness.load("src/client/fx/ImpactSequence")
local impact = Harness.load("src/shared/data/impact")

local WINDOW = impact.flash.windowSeconds
local MAX = impact.flash.maxPerWindow

-- Runs `body` with a fresh budget and leaves a fresh one behind for the next spec.
local function fresh(body: () -> ())
	FlashBudget.reset()
	local ok, err = pcall(body)
	FlashBudget.reset()
	if not ok then
		error(err, 0)
	end
end

describe("FlashBudget window", function()
	it("allows costs up to the cap inside one window and refuses the one that would pass it", function()
		fresh(function()
			expect(FlashBudget.request(10, 2)).toBe(true)
			expect(FlashBudget.request(10.5, 1)).toBe(true)
			expect(FlashBudget.used(10.5)).toBe(MAX)
			expect(FlashBudget.request(10.6, 1)).toBe(false)
			-- The refusal recorded nothing.
			expect(FlashBudget.used(10.6)).toBe(MAX)
		end)
	end)

	it("keeps a cost until exactly one window after it was recorded", function()
		fresh(function()
			expect(FlashBudget.request(20, MAX)).toBe(true)
			expect(FlashBudget.request(20 + WINDOW - 1e-3, 1)).toBe(false)
			expect(FlashBudget.used(20 + WINDOW - 1e-3)).toBe(MAX)
			-- At the window's edge the old cost has expired and the full budget is back.
			expect(FlashBudget.used(20 + WINDOW)).toBe(0)
			expect(FlashBudget.request(20 + WINDOW, MAX)).toBe(true)
		end)
	end)

	it("rolls: only the costs inside the last window count", function()
		fresh(function()
			expect(FlashBudget.request(30, 2)).toBe(true)
			expect(FlashBudget.request(30.5, 1)).toBe(true)
			-- At 31 the first cost is gone; the one from 30.5 still counts.
			expect(FlashBudget.used(31)).toBe(1)
			expect(FlashBudget.request(31, 2)).toBe(true)
			expect(FlashBudget.request(31.2, 1)).toBe(false)
			expect(FlashBudget.used(31.5)).toBe(2)
		end)
	end)

	it("gives the second of two Kills inside a second the dim: 2 + 2 > 3", function()
		fresh(function()
			local kill = ImpactSequence.flashCost("Kill")
			expect(kill).toBe(2)
			expect(FlashBudget.request(40, kill)).toBe(true)
			expect(FlashBudget.request(40.9, kill)).toBe(false)
			-- A Final's single flash still fits beside the first Kill.
			expect(FlashBudget.request(40.9, ImpactSequence.flashCost("Final"))).toBe(true)
			expect(FlashBudget.used(40.9)).toBe(MAX)
		end)
	end)

	it("counts a cost until one window after its picture ends, not after it starts", function()
		fresh(function()
			local final = ImpactSequence.flashCost("Final")
			local seconds = ImpactSequence.seconds("Final")
			-- The checker's case: Finals one window apart from their starts, each drawn for its
			-- frames. With the window from the start the fourth fits, and seven changes land in
			-- under a second; from the end it waits.
			expect(FlashBudget.request(60, final, seconds)).toBe(true)
			expect(FlashBudget.request(60.33, final, seconds)).toBe(true)
			expect(FlashBudget.request(60.66, final, seconds)).toBe(true)
			expect(FlashBudget.request(61.0006, final, seconds)).toBe(false)
			expect(FlashBudget.used(60 + seconds + WINDOW - 1e-6)).toBe(MAX)
			expect(FlashBudget.request(60 + seconds + WINDOW, final, seconds)).toBe(true)
		end)
	end)

	it("holds a claim while its picture is still on screen", function()
		fresh(function()
			local claim = FlashBudget.claim(70, MAX, 0.1) :: FlashBudget.Claim
			expect(claim).never.toBeNil()
			-- The overlay ran long (a hitch): its last change was at 70.4.
			FlashBudget.hold(claim, 70.4)
			FlashBudget.hold(claim, 70.2) -- never earlier
			expect(claim.finish).toBeCloseTo(70.4, 1e-9)
			expect(FlashBudget.request(70.4 + WINDOW - 1e-3, 1)).toBe(false)
			expect(FlashBudget.request(70.4 + WINDOW, 1)).toBe(true)
		end)
	end)

	it("pins a claim on a frozen frame until settle names its last change", function()
		fresh(function()
			local claim = FlashBudget.claim(90, 2, 0.1) :: FlashBudget.Claim
			expect(claim).never.toBeNil()
			-- The window stopped rendering with the picture on its last frame: no end is known yet.
			FlashBudget.hold(claim, math.huge)
			-- Seconds later it still counts, through the prune of a request that sees it.
			expect(FlashBudget.request(95, 2)).toBe(false)
			expect(FlashBudget.used(95)).toBe(2)
			-- The next rendered frame (at 96) shows it gone: it counts until a window after that.
			FlashBudget.settle(claim, 96)
			expect(claim.finish).toBe(96)
			expect(FlashBudget.used(96 + WINDOW - 1e-3)).toBe(2)
			expect(FlashBudget.used(96 + WINDOW)).toBe(0)
			-- A bad time leaves the claim as it is.
			FlashBudget.settle(claim, 0 / 0)
			expect(claim.finish).toBe(96)
		end)
	end)

	it("raises a claim by the difference only, and refuses a raise past the cap", function()
		fresh(function()
			local final = FlashBudget.claim(80, 1, 0.05) :: FlashBudget.Claim
			expect(FlashBudget.raise(final, 80, 2)).toBe(true)
			expect(FlashBudget.used(80)).toBe(2)
			expect(FlashBudget.request(80, 1)).toBe(true)
			expect(FlashBudget.used(80)).toBe(MAX)
			-- The other cost leaves no room for this claim to grow; nothing changes.
			expect(FlashBudget.raise(final, 80, 3)).toBe(false)
			expect(final.cost).toBe(2)
			expect(FlashBudget.used(80)).toBe(MAX)
			-- Lowering is a no-op that succeeds.
			expect(FlashBudget.raise(final, 80, 1)).toBe(true)
			expect(final.cost).toBe(2)
		end)
	end)

	it("never lets a cost above the cap through, and rejects bad costs", function()
		fresh(function()
			expect(FlashBudget.request(50, MAX + 1)).toBe(false)
			expect(FlashBudget.used(50)).toBe(0)
			expect(FlashBudget.request(50, -1)).toBe(false)
			expect(FlashBudget.request(50, 0 / 0)).toBe(false)
			expect(FlashBudget.request(50, 0)).toBe(true)
			expect(FlashBudget.used(50)).toBe(0)
		end)
	end)
end)

describe("FlashBudget Reduce flashing setting", function()
	it("starts off, follows set, and fires changed only on a change", function()
		fresh(function()
			expect(FlashBudget.reduced()).toBe(impact.reduceFlashingDefault)
			local seen = {}
			local connection = FlashBudget.changed:Connect(function(value: boolean)
				table.insert(seen, value)
			end)
			FlashBudget.set(true)
			FlashBudget.set(true)
			expect(FlashBudget.reduced()).toBe(true)
			FlashBudget.set(false)
			connection:Disconnect()
			expect(seen).toEqual({ true, false })
		end)
	end)

	it("reads the local player's boolean attribute and ignores anything else", function()
		local Players = Harness.game():GetService("Players")
		local player = Instance.new("Folder")
		Harness.stubService("Players", { LocalPlayer = player })
		local ok, err = pcall(function()
			fresh(function()
				player:SetAttribute(impact.reduceFlashingAttribute, true)
				FlashBudget.reset()
				expect(FlashBudget.reduced()).toBe(true)
				player:SetAttribute(impact.reduceFlashingAttribute, "yes")
				FlashBudget.reset()
				expect(FlashBudget.reduced()).toBe(impact.reduceFlashingDefault)
			end)
		end)
		Players.LocalPlayer = nil
		if not ok then
			error(err, 0)
		end
	end)
end)
