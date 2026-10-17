--!strict
local ClipLibrary = Harness.load("src/client/choreo/ClipLibrary")
local Rigs = Harness.load("src/shared/data/rigs")
local ChoreoData = Harness.load("src/shared/data/choreo")

local REQUIRED_PLAYER = {
	"Idle",
	"IdleDrawn",
	"WalkForward",
	"WalkBack",
	"WalkLeft",
	"WalkRight",
	"Run",
	"Sprint",
	"Jump",
	"Fall",
	"Land",
	"TurnLeft",
	"TurnRight",
	"Skid",
	"Guard",
	"GuardHit",
	"GuardBreak",
	"Parry",
	"DodgeForward",
	"DodgeBack",
	"DodgeLeft",
	"DodgeRight",
	"FlinchFront",
	"FlinchBack",
	"FlinchLeft",
	"FlinchRight",
	"Stagger",
	"DeathFreeze",
	"Basic1",
	"Basic2",
	"Basic3",
	"Horizontal",
	"Vertical",
	"RisingArc",
	"SharpNail",
}

local REQUIRED_ENEMY = {
	Boar = {
		"Idle",
		"Walk",
		"Charge",
		"FlinchFront",
		"FlinchBack",
		"FlinchLeft",
		"FlinchRight",
		"Stagger",
		"Break",
		"DeathFreeze",
	},
	Kobold = {
		"Idle",
		"Walk",
		"Overhead",
		"FlinchFront",
		"FlinchBack",
		"FlinchLeft",
		"FlinchRight",
		"Stagger",
		"Break",
		"DeathFreeze",
	},
}

local function jointSet(rigId)
	local set = {}
	for _, joint in Rigs[rigId].joints do
		set[joint.name] = true
	end
	return set
end

describe("ClipLibrary", function()
	it("has every required Phase 0 player clip and loads it", function()
		for _, name in REQUIRED_PLAYER do
			local id = "player/OneHandedSword/" .. name
			expect(ClipLibrary.has(id)).toBe(true)
			local clip = ClipLibrary.get(id)
			expect(clip.id).toBe(id)
			expect(clip.rig).toBe("PlayerR15")
		end
	end)

	it("has every required enemy clip and loads it", function()
		for rigId, names in REQUIRED_ENEMY do
			for _, name in names do
				local id = ("enemy/%s/%s"):format(rigId, name)
				expect(ClipLibrary.has(id)).toBe(true)
				local clip = ClipLibrary.get(id)
				expect(clip.id).toBe(id)
				expect(clip.rig).toBe(rigId)
			end
		end
	end)

	it("every clip's joint names exist in its rig and every clip starts posed at time 0", function()
		for _, id in ClipLibrary.all() do
			local clip = ClipLibrary.get(id)
			local joints = jointSet(clip.rig)
			expect(clip.keys[1].time).toBe(0)
			for index, key in clip.keys do
				for name in key.joints do
					if not joints[name] then
						error(("%s key %d moves unknown joint %s"):format(id, index, name))
					end
				end
			end
		end
	end)

	it("lists every clip under the clips folder with ids that match their paths", function()
		local all = ClipLibrary.all()
		expect(#all).toBeGreaterThanOrEqual(#REQUIRED_PLAYER + 20)
		for _, id in all do
			expect(ClipLibrary.get(id).id).toBe(id)
		end
		expect(all).toContain("player/OneHandedSword/SharpNail")
		expect(all).toContain("enemy/Boar/Charge")
		expect(all).toContain("enemy/Kobold/Overhead")
	end)

	it("errors on an unknown id and caches loaded clips", function()
		expect(function()
			ClipLibrary.get("player/OneHandedSword/DoesNotExist")
		end).toThrow("no clip")
		expect(ClipLibrary.has("player/OneHandedSword/DoesNotExist")).toBe(false)
		expect(ClipLibrary.get("player/OneHandedSword/Idle")).toBe(ClipLibrary.get("player/OneHandedSword/Idle"))
	end)

	it("the idle and breathing clips the animator auto-plays exist for every rig in the data", function()
		for rigId, clips in ChoreoData.rigs do
			local idle = ClipLibrary.get(clips.idle)
			expect(idle.rig).toBe(rigId)
			expect(idle.layer).toBe("Base")
			expect(idle.loop).toBe(true)
			if clips.breathing then
				local breathing = ClipLibrary.get(clips.breathing)
				expect(breathing.layer).toBe("Additive")
				expect(breathing.loop).toBe(true)
			end
		end
		for _, name in ChoreoData.locomotion.clips do
			expect(ClipLibrary.has(ChoreoData.locomotion.clipPrefix .. name)).toBe(true)
		end
	end)

	it("forRig groups clips by rig", function()
		local boar = ClipLibrary.forRig("Boar")
		expect(#boar).toBe(#REQUIRED_ENEMY.Boar)
		for _, id in boar do
			expect(id:sub(1, #"enemy/Boar/")).toBe("enemy/Boar/")
		end
	end)
end)
