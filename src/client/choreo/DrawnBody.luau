--!strict
--[[
	DrawnBody: where a fighter's body is drawn, the one place every client reader asks (D-193).

	Choreo can draw a body away from its root part. A Charger's rush is drawn on the server's
	timeline (D-171, choreo/RushDraw) by an offset on the root joint (Animator.setBodyOffset), while
	the root part, hidden, keeps its physics and the place replication gives it: 0.2 to 0.3 s behind
	the server's body, 0.5 s on a first move after a long stand, so 7 to 14 studs behind the drawn
	boar at the rush speed. Everything the player sees or hears on a fighter follows the drawn body,
	never the root part: its plate and the SWITCH prompt (billboards adorned to the root that
	`follow` the body), the lock camera's framing, the lock key's and the soft assist's distances,
	the body's turn to the lock (D-112), and every sound or effect placed or ranked by a rig's
	position (fx/Engine.modelPosition).

	Choreo publishes the offset from the step that writes it into the root joint (`publish`), and a
	billboard that follows the rig moves in that same call, so the frame draws the plate exactly
	over the body. A reader later in the frame sees exactly what the frame draws; one that runs
	before the rig's step sees the last step's offset on the root as it stands now (at most a
	frame's change of the offset).

		DrawnBody.position(model)            -- Vector3?: the root part's position moved by the offset
		DrawnBody.cframe(model)              -- CFrame?: the root part's CFrame moved by the offset
		DrawnBody.offset(model)              -- CFrame? in the root part's space; nil on its root
		DrawnBody.follow(gui, model, base)   -- a billboard adorned to the root shows over the body
		DrawnBody.unfollow(gui)              -- back to `base` and no longer moved

	Nothing here moves the root part or decides anything the server owns. The local blade's contact
	prediction tests the drawn body's own parts (ContactPredictor, with the hidden root skipped by
	Replication.drawnAway), not these positions.
]]

local DrawnBody = {}

-- model -> the offset its body is drawn at, in the root part's space (absent: on its root).
local offsets: { [any]: CFrame? } = setmetatable({}, { __mode = "k" }) :: any
-- model -> the billboards following it and their own offsets; billboard -> the model it follows.
local followers: { [any]: { [any]: Vector3 } } = {}
local followed: { [any]: any } = {}

-- The root part of a rig model (a plain table with a PrimaryPart in specs), or nil.
local function rootOf(model: any): any
	if typeof(model) == "Instance" then
		return if (model :: Instance):IsA("Model") then (model :: Model).PrimaryPart else nil
	elseif typeof(model) == "table" then
		return model.PrimaryPart
	end
	return nil
end

-- Moves a following billboard over the body: its own offset, plus the way from the root part to
-- the drawn body in world space (StudsOffsetWorldSpace is world space, from the adornee).
local function place(gui: any, model: any, base: Vector3)
	local offset = offsets[model]
	local shift = Vector3.zero
	if offset ~= nil then
		local root = rootOf(model)
		if root ~= nil then
			shift = (root.CFrame :: CFrame):VectorToWorldSpace(offset.Position)
		end
	end
	gui.StudsOffsetWorldSpace = base + shift
end

--- The offset a rig's body is drawn at in its root part's space, or nil while it is on its root.
function DrawnBody.offset(model: any): CFrame?
	return offsets[model]
end

--- Where a rig's body is drawn: its root part's CFrame moved by the offset (the root part's own
--- while the body is on it), or nil without a root part.
function DrawnBody.cframe(model: any): CFrame?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local offset = offsets[model]
	return if offset ~= nil then (root.CFrame :: CFrame) * offset else root.CFrame
end

--- Where a rig's body is drawn: its root part's position moved by the offset (the root part's own
--- while the body is on it), or nil without a root part.
function DrawnBody.position(model: any): Vector3?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local offset = offsets[model]
	if offset == nil then
		return root.Position
	end
	return ((root.CFrame :: CFrame) * offset).Position
end

--- Choreo's step: the body of `model` is drawn at `offset` from its root part this frame (nil: on
--- its root again). Every billboard following it moves with it in this call.
function DrawnBody.publish(model: any, offset: CFrame?)
	if offset == nil and offsets[model] == nil then
		return
	end
	offsets[model] = offset
	local list = followers[model]
	if list ~= nil then
		for gui, base in list do
			place(gui, model, base)
		end
	end
end

--- A BillboardGui adorned to `model`'s root part shows over the drawn body: its
--- StudsOffsetWorldSpace becomes `base` plus the way to the body, now and whenever the body's
--- offset changes. A billboard follows one model at a time.
function DrawnBody.follow(gui: any, model: any, base: Vector3)
	DrawnBody.unfollow(gui, nil)
	local list = followers[model]
	if list == nil then
		list = {}
		followers[model] = list
	end
	(list :: { [any]: Vector3 })[gui] = base
	followed[gui] = model
	place(gui, model, base)
end

--- Stops moving a billboard; it goes back to `base` when one is given.
function DrawnBody.unfollow(gui: any, base: Vector3?)
	local model = followed[gui]
	if model ~= nil then
		followed[gui] = nil
		local list = followers[model]
		if list ~= nil then
			list[gui] = nil
			if next(list) == nil then
				followers[model] = nil
			end
		end
	end
	if base ~= nil then
		gui.StudsOffsetWorldSpace = base
	end
end

--- Forgets every offset and follower (specs).
function DrawnBody.reset()
	table.clear(offsets)
	table.clear(followers)
	table.clear(followed)
end

return DrawnBody
