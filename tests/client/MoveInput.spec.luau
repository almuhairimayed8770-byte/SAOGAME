--!strict
--[[
	MoveInput: the stick as the control module reads it, in world space (D-474). The control
	module is faked as PlayerModule:GetControls() answers (GetMoveVector, GetActiveController);
	the camera turns it as the control module's calculateRawMoveVector does before its Move.
]]

local MoveInput = Harness.load("src/client/controllers/MoveInput")

local function controls(move: Vector3, relative: boolean?): any
	return {
		GetMoveVector = function(_self: any): Vector3
			return move
		end,
		GetActiveController = function(_self: any): any
			return {
				IsMoveVectorCameraRelative = function(_self: any): boolean
					return relative ~= false
				end,
			}
		end,
	}
end

local function humanoid(moveDirection: Vector3): any
	return { MoveDirection = moveDirection }
end

local function near(a: Vector3, b: Vector3)
	expect((a - b).Magnitude).toBeCloseTo(0, 1e-6)
end

describe("MoveInput.world", function()
	it("answers the Humanoid's MoveDirection where there is no control module", function()
		MoveInput.bind({
			controls = function(): any
				return nil
			end,
		})
		near(MoveInput.world(humanoid(Vector3.new(0, 0, -1))), Vector3.new(0, 0, -1))
	end)

	it("is zero with no active controller, whatever the Humanoid was last Moved along", function()
		-- The control module's GetMoveVector with no active controller: zero. The Humanoid still
		-- walks the stop's carry (its own last Move), which is not the stick.
		MoveInput.bind({
			controls = function(): any
				return controls(Vector3.zero)
			end,
			camera = function(): CFrame?
				return CFrame.identity
			end,
		})
		near(MoveInput.world(humanoid(Vector3.new(0, 0, -1))), Vector3.zero)
	end)

	it("reads a keyboard diagonal, a gamepad's half tilt and a thumbstick as their directions", function()
		for _, case in
			{
				{ move = Vector3.new(1, 0, -1), want = Vector3.new(1, 0, -1).Unit }, -- keyboard: length 1.41
				{ move = Vector3.new(0, 0, -0.5), want = Vector3.new(0, 0, -1) }, -- gamepad half tilt
				{ move = Vector3.new(-0.3, 0, 0.4), want = Vector3.new(-0.6, 0, 0.8) }, -- thumbstick
			}
		do
			MoveInput.bind({
				controls = function(): any
					return controls(case.move)
				end,
				camera = function(): CFrame?
					return CFrame.identity
				end,
			})
			near(MoveInput.world(humanoid(Vector3.zero)), case.want)
		end
	end)

	it("turns a camera-relative stick onto the camera's yaw, as the control module does", function()
		-- Yawed a quarter turn left the camera looks down -X: forward on the stick walks -X, right
		-- walks -Z. Pitched down 60 degrees, the yaw alone counts.
		for _, camera in
			{
				CFrame.Angles(0, math.pi / 2, 0),
				CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(-math.rad(60), 0, 0),
			}
		do
			MoveInput.bind({
				controls = function(): any
					return controls(Vector3.new(0, 0, -1))
				end,
				camera = function(): CFrame?
					return camera
				end,
			})
			near(MoveInput.world(humanoid(Vector3.zero)), Vector3.new(-1, 0, 0))
			MoveInput.bind({
				controls = function(): any
					return controls(Vector3.new(1, 0, 0))
				end,
				camera = function(): CFrame?
					return camera
				end,
			})
			near(MoveInput.world(humanoid(Vector3.zero)), Vector3.new(0, 0, -1))
		end
	end)

	it("takes forward from the camera's up vector while it looks straight down", function()
		local camera = CFrame.lookAt(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(1, 0, 0))
		MoveInput.bind({
			controls = function(): any
				return controls(Vector3.new(0, 0, -1))
			end,
			camera = function(): CFrame?
				return camera
			end,
		})
		near(MoveInput.world(humanoid(Vector3.zero)), Vector3.new(1, 0, 0))
	end)

	it("leaves a controller's world-space vector as it is, and bind(nil) restores the engine's", function()
		MoveInput.bind({
			controls = function(): any
				return controls(Vector3.new(0, 0, 2), false)
			end,
			camera = function(): CFrame?
				return CFrame.Angles(0, math.pi / 2, 0)
			end,
		})
		near(MoveInput.world(humanoid(Vector3.zero)), Vector3.new(0, 0, 1))
		-- The harness has no local player: the engine's reader finds no control module.
		MoveInput.bind(nil)
		near(MoveInput.world(humanoid(Vector3.new(1, 0, 0))), Vector3.new(1, 0, 0))
	end)
end)
