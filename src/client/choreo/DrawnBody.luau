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

	While Choreo draws the body's Torso itself, off the root part's move at physics (D-531), it
	publishes that part and where the body is drawn: a following billboard is adorned to that part
	instead, its offset keeping it over the drawn body, so the root part's own move never carries
	it off the body; it goes back to its owner's adornee once the body is back on its root
	(D-533). `position` and `cframe` then answer where the step drew the body too, not the root
	part moved by the offset: the root part moves at physics and the drawn Torso does not, so that
	answer sat off the drawn body by the root's move of the frame (D-552).

		DrawnBody.position(model)            -- Vector3?: where the body is drawn (the carrier's, else
		                                     -- the root part's position moved by the offset)
		DrawnBody.cframe(model)              -- CFrame?: the same as a CFrame
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
-- model -> the part its body is drawn on off the root part, and where the body is drawn (world).
type Carrier = { part: any, at: CFrame }
local carriers: { [any]: Carrier } = setmetatable({}, { __mode = "k" }) :: any
-- billboard -> its owner's adornee while it is adorned to a carrier part instead (and that part).
local homes: { [any]: { adornee: any, part: any } } = {}

-- The root part of a rig model (a plain table with a PrimaryPart in specs), or nil.
local function rootOf(model: any): any
	if typeof(model) == "Instance" then
		return if (model :: Instance):IsA("Model") then (model :: Model).PrimaryPart else nil
	elseif typeof(model) == "table" then
		return model.PrimaryPart
	end
	return nil
end

-- Gives a billboard back its owner's adornee, unless the owner has adorned it anew meanwhile.
local function goHome(gui: any)
	local home = homes[gui]
	if home ~= nil then
		homes[gui] = nil
		if gui.Adornee == home.part then
			gui.Adornee = home.adornee
		end
	end
end

-- Moves a following billboard over the body: its own offset, plus the way from the root part to
-- the drawn body in world space (StudsOffsetWorldSpace is world space, from the adornee). While
-- the body is drawn on a carrier part, it is adorned to that part, the way from the part to the
-- drawn body added.
local function place(gui: any, model: any, base: Vector3)
	local carrier = carriers[model]
	if carrier ~= nil then
		local part = carrier.part
		local home = homes[gui]
		if home == nil or home.part ~= part then
			goHome(gui)
			homes[gui] = { adornee = gui.Adornee, part = part }
			gui.Adornee = part
		end
		gui.StudsOffsetWorldSpace = base + (carrier.at.Position - (part.CFrame :: CFrame).Position)
		return
	end
	goHome(gui)
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

--- Where a rig's body is drawn: while Choreo draws it on a carrier part, off the root part's move
--- at physics, where the step drew it (D-552); otherwise its root part's CFrame moved by the
--- offset (the root part's own while the body is on it). Nil without a root part.
function DrawnBody.cframe(model: any): CFrame?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local carrier = carriers[model]
	if carrier ~= nil then
		return carrier.at
	end
	local offset = offsets[model]
	return if offset ~= nil then (root.CFrame :: CFrame) * offset else root.CFrame
end

--- Where a rig's body is drawn: DrawnBody.cframe's position, or nil without a root part.
function DrawnBody.position(model: any): Vector3?
	local root = rootOf(model)
	if root == nil then
		return nil
	end
	local carrier = carriers[model]
	if carrier ~= nil then
		return carrier.at.Position
	end
	local offset = offsets[model]
	if offset == nil then
		return root.Position
	end
	return ((root.CFrame :: CFrame) * offset).Position
end

--- Choreo's step: the body of `model` is drawn at `offset` from its root part this frame (nil: on
--- its root again). Every billboard following it moves with it in this call. With `carrier`, the
--- part the step drew off the root part, and `at`, where it drew the body (world), every follower
--- is adorned to that part and kept over `at` (D-533).
function DrawnBody.publish(model: any, offset: CFrame?, carrier: any?, at: CFrame?)
	if offset == nil and offsets[model] == nil then
		return
	end
	offsets[model] = offset
	carriers[model] = if offset ~= nil and carrier ~= nil and at ~= nil then { part = carrier, at = at } else nil
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

--- Stops moving a billboard; it goes back to `base` when one is given, and to its owner's
--- adornee.
function DrawnBody.unfollow(gui: any, base: Vector3?)
	goHome(gui)
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
	table.clear(carriers)
	table.clear(homes)
end

return DrawnBody
