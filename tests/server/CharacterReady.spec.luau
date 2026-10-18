--!strict
--[[
	CharacterReady under Lune (D-046): a scripted engine clock stands in for task.wait, and a Lune
	Player instance for the player. CharacterAdded fires before the engine parents and dresses the
	character, so the wait must hold until both happen (appearance with a timeout), then one more
	frame; and it must give up on a character that was replaced or never parented.
]]

local CharacterReady = Harness.load("src/server/world/CharacterReady")

type Script = { [number]: () -> () }

-- An engine whose clock moves one 60 Hz frame per step and runs `script[n]` on the n-th step.
local function engineFor(script: Script, loaded: () -> boolean): (any, () -> number)
	local frame = 0
	local engine = {
		now = function(): number
			return frame / 60
		end,
		step = function()
			frame += 1
			local action = script[frame]
			if action ~= nil then
				action()
			end
		end,
		appearanceLoaded = function(): boolean
			return loaded()
		end,
	}
	return engine, function(): number
		return frame
	end
end

local function spawned(): (any, any, any)
	local player = Instance.new("Player")
	local model = Instance.new("Model")
	player.Character = model
	local world = Instance.new("Folder")
	return player, model, world
end

describe("CharacterReady.wait", function()
	it("holds a player's character until it is parented and dressed, then one more frame", function()
		local player, model, world = spawned()
		local dressed = false
		local engine, frames = engineFor({
			[3] = function()
				model.Parent = world
			end,
			[7] = function()
				dressed = true
			end,
		}, function()
			return dressed
		end)
		expect(CharacterReady.wait(player, model, 10, engine)).toBe(true)
		expect(frames()).toBe(8) -- parented on frame 3, dressed on frame 7, one frame for the rig build
	end)

	it("lets a stand-in that is not a Player through once it is parented", function()
		local standIn = { Name = "StandIn" }
		local model = Instance.new("Model")
		model.Parent = Instance.new("Folder")
		local engine, frames = engineFor({}, function()
			return false -- never asked for a stand-in
		end)
		expect(CharacterReady.wait(standIn, model, 10, engine)).toBe(true)
		expect(frames()).toBe(1)
	end)

	it("gives up on a character that is never parented in time", function()
		local player, model = spawned()
		local engine, frames = engineFor({}, function()
			return true
		end)
		expect(CharacterReady.wait(player, model, 0.5, engine)).toBe(false)
		expect(frames()).toBe(30)
	end)

	it("gives up on a character the player no longer wears", function()
		local player, model, world = spawned()
		local engine = engineFor({
			[2] = function()
				player.Character = Instance.new("Model") -- respawned before this one was parented
				model.Parent = world
			end,
		}, function()
			return true
		end)
		expect(CharacterReady.wait(player, model, 10, engine)).toBe(false)

		local player2, model2, world2 = spawned()
		model2.Parent = world2
		local engine2 = engineFor({
			[4] = function()
				player2.Character = Instance.new("Model") -- respawned while the appearance loaded
			end,
		}, function()
			return false
		end)
		expect(CharacterReady.wait(player2, model2, 10, engine2)).toBe(false)
	end)

	it("lets a parented player play when the appearance never loads", function()
		local player, model, world = spawned()
		model.Parent = world
		local engine, frames = engineFor({}, function()
			return false
		end)
		expect(CharacterReady.wait(player, model, 0.25, engine)).toBe(true)
		expect(frames()).toBe(16) -- 15 frames to the deadline, one for the rig build
	end)

	it("reports a character removed during the last frame as not ready", function()
		local player, model, world = spawned()
		model.Parent = world
		local engine = engineFor({
			[1] = function()
				model.Parent = nil
			end,
		}, function()
			return true
		end)
		expect(CharacterReady.wait(player, model, 10, engine)).toBe(false)
	end)
end)
