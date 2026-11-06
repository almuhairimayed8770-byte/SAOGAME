--!strict
--[[
	The damage numbers' pool (item 430(c), D-536): each new number takes the digit freed longest
	ago, never the one that just faded. At the 30 fps cap Sharp Nail's third hit lands 0.600 to
	0.637 s after its first, right after the first number's combat.digitFadeTime (0.6 s) ends, and
	the pool handed it that same anchor on the next frame: the number showed, but a logger that
	counts the anchors that light up (or a viewer's eye on one spot) saw two numbers for three hits.
]]

local Fx = Harness.load("src/shared/data/fx")
local Engine = Harness.load("src/client/fx/Engine")
local Digits = Harness.load("src/client/fx/Digits")

local clock = 0
Engine.setClock(function(): number
	return clock
end)

-- The anchor part each lit number rides on, and how many anchors are lit.
local function lit(): ({ [Instance]: string }, number)
	local list: { [Instance]: string } = {}
	local count = 0
	for _, part in Engine.folder(workspace, "FxDigits"):GetChildren() do
		local gui = part:FindFirstChild("DigitGui") :: BillboardGui?
		local label = if gui ~= nil then gui:FindFirstChild("Digit") :: TextLabel? else nil
		if gui ~= nil and label ~= nil and gui.Enabled then
			list[part] = label.Text
			count += 1
		end
	end
	return list, count
end

local function anchorOf(text: string): Instance?
	local list = lit()
	for part, shown in list do
		if shown == text then
			return part
		end
	end
	return nil
end

describe("the damage numbers' pool (item 430(c), D-536)", function()
	it("gives a new number the digit freed longest ago, not the one that just faded", function()
		Digits.start()
		local fade: number = Fx.digits.fadeTime
		local frame = 1 / 30
		-- Sharp Nail at the 30 fps cap: hits at 0, 0.267 and just past the first number's fade.
		clock = 100
		Digits.show(Vector3.new(0, 3, 0), 11, "Normal")
		local first = anchorOf("11")
		expect(first).never.toBeNil()
		clock += 0.267
		Digits.step()
		Digits.show(Vector3.new(0, 3, 0), 12, "Normal")
		local second = anchorOf("12")
		expect(second).never.toBeNil()
		-- The first fades out on the frame its fade ends; the third hit comes on the next.
		clock = 100 + fade + 0.001
		Digits.step()
		local _, during = lit()
		expect(during).toBe(1)
		clock += frame
		Digits.step()
		Digits.show(Vector3.new(0, 3, 0), 13, "Normal")
		local third = anchorOf("13")
		expect(third).never.toBeNil()
		expect(third ~= first).toBe(true)
		expect(third ~= second).toBe(true)
		-- Three numbers, three anchors lit one after another.
		local _, now = lit()
		expect(now).toBe(2)
		-- Once every number has faded, the pool still hands out each digit in turn.
		clock += 5
		Digits.step()
		local _, after = lit()
		expect(after).toBe(0)
		local seen: { [Instance]: boolean } = {}
		for index = 1, Fx.digits.poolSize do
			clock += fade + frame
			Digits.step()
			Digits.show(Vector3.new(0, 3, 0), index, "Normal")
			local part = anchorOf(tostring(index)) :: Instance
			expect(seen[part]).toBeNil()
			seen[part] = true
		end
	end)
end)
