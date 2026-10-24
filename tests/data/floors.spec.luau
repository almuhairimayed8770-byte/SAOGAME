--!strict
local Floors = Harness.load("src/shared/data/floors")

describe("floors data", function()
	it("holds floors 1 to 25 in order", function()
		expect(#Floors.list).toBe(25)
		for index, def in ipairs(Floors.list) do
			expect(def.number).toBe(index)
			expect(Floors.get(index)).toBe(def)
		end
	end)

	it("matches the section 5 table", function()
		expect(Floors.get(1).name).toBe("Firstlight Plains")
		expect(Floors.get(1).town).toBe("Firstlight")
		expect(Floors.get(1).boss).toBe("Grolak")
		expect(Floors.get(1).bossName).toBe("Grolak, Kobold Warlord")
		expect(Floors.get(5).name).toBe("Vaelric Highlands")
		expect(Floors.get(10).town).toBe("Highwall")
		expect(Floors.get(10).boss).toBe("WardensKnight")
		expect(Floors.get(22).name).toBe("Mirrorlake")
		expect(Floors.get(22).boss).toBe("Lakewarden")
		expect(Floors.get(25).name).toBe("Argent Crown")
		expect(Floors.get(25).boss).toBe("SilverSovereign")
	end)

	it("flags every fifth floor as a Haven and Mirrorlake as a settlement", function()
		for _, def in Floors.list do
			expect(def.haven).toBe(def.number % 5 == 0)
			expect(def.settlement).toBe(def.number % 5 == 0 or def.number == 22)
		end
		expect(Floors.isHaven(5)).toBe(true)
		expect(Floors.isHaven(100)).toBe(true)
		expect(Floors.isHaven(22)).toBe(false)
		expect(Floors.isSettlement(22)).toBe(true)
		expect(Floors.isSettlement(23)).toBe(false)
		expect(Floors.isSettlement(30)).toBe(true)
	end)

	it("boss ids are PascalCase and unique", function()
		local seen = {}
		for _, def in Floors.list do
			expect(def.boss:match("^%u[%w]*$")).toBeTruthy()
			expect(seen[def.boss]).toBeNil()
			seen[def.boss] = true
		end
	end)

	it("every floor uses one of the twelve generator kits", function()
		expect(#Floors.biomeKits).toBe(12)
		for _, def in Floors.list do
			expect(Floors.isBiomeKit(def.biome)).toBe(true)
		end
		expect(Floors.isBiomeKit("citadel")).toBe(false)
	end)

	it("holds the floor anatomy numbers", function()
		local anatomy = Floors.anatomy
		expect(anatomy.discDiameterMin).toBe(2000)
		expect(anatomy.discDiameterMax).toBe(4000)
		expect(anatomy.floor1DiscDiameter).toBe(3000)
		expect(anatomy.ceilingHeight).toBe(350)
		expect(anatomy.dayLengthMinutes).toBe(48)
		expect(anatomy.nightSpawnMultiplier).toBe(1.5)
		expect(anatomy.bloodMoonChancePerNight).toBeCloseTo(0.005)
		expect(anatomy.fieldBossRespawnMinutes).toBe(90)
		expect(anatomy.packRespawnMinutes).toBe(6)
		expect(anatomy.labyrinthLevelsMin).toBe(8)
		expect(anatomy.labyrinthLevelsMax).toBe(12)
	end)

	it("knows which floors are hand-authored", function()
		expect(Floors.isHandAuthored(25)).toBe(true)
		expect(Floors.isHandAuthored(26)).toBe(false)
		expect(Floors.isHandAuthored(30)).toBe(true)
		expect(Floors.isHandAuthored(74)).toBe(true)
		expect(Floors.isHandAuthored(73)).toBe(false)
	end)

	it("errors on a floor without a row and returns nil from find", function()
		expect(function()
			Floors.get(26)
		end).toThrow("no row for floor 26")
		expect(Floors.find(26)).toBeNil()
		expect(Floors.find(3)).toBe(Floors.get(3))
	end)
end)
