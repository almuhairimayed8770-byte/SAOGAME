--!strict
--[[
	choreo/DrawnBody (D-193): the one place a client reader asks where a fighter's body is drawn.
	A rush draws a Charger's body ahead of its hidden root part (D-171); the offset Choreo publishes
	moves every reader's answer and every billboard that follows the rig, in the publish call.
]]

local DrawnBody = Harness.load("src/client/choreo/DrawnBody")
local Engine = Harness.load("src/client/fx/Engine")

-- Vector3 is single precision: positions some tens of studs out agree to about this.
local EPSILON = 1e-4

local function rig(at: CFrame): (Model, BasePart)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	-- Lune keeps a part's CFrame and Position apart: set both, as the engine shows them.
	root.CFrame = at
	root.Position = at.Position
	root.Parent = model
	model.PrimaryPart = root
	return model, root
end

local function near(a: Vector3?, b: Vector3)
	expect(a).never.toBeNil()
	expect(((a :: Vector3) - b).Magnitude).toBeLessThan(EPSILON)
end

-- The root part turned a quarter round, 10 studs out; a rush draws the body 7 studs ahead of it
-- and 0.5 to its right, in the root part's own space.
local ROOT = CFrame.new(10, 3, -20) * CFrame.Angles(0, math.rad(90), 0)
local OFFSET = CFrame.new(0.5, 0, -7)
local LIFT = Vector3.new(0, 3.5, 0)

describe("DrawnBody", function()
	it("answers the root part while the body is on it, and nil without a root part", function()
		DrawnBody.reset()
		local model = rig(ROOT)
		expect(DrawnBody.offset(model)).toBeNil()
		near(DrawnBody.position(model), ROOT.Position)
		local frame = DrawnBody.cframe(model) :: CFrame
		near(frame.Position, ROOT.Position)
		near(frame.LookVector, ROOT.LookVector)
		expect(DrawnBody.position(Instance.new("Model"))).toBeNil()
		expect(DrawnBody.position(nil)).toBeNil()
		expect(DrawnBody.cframe(Instance.new("Folder"))).toBeNil()
	end)

	it("answers the body a published offset draws, in the root part's space, until it is cleared", function()
		DrawnBody.reset()
		local model, root = rig(ROOT)
		DrawnBody.publish(model, OFFSET)
		local drawn = ROOT * OFFSET
		near(DrawnBody.position(model), drawn.Position)
		near((DrawnBody.cframe(model) :: CFrame).Position, drawn.Position)
		-- The root part moves on (replication) while the offset stands: the answer moves with it.
		local moved = ROOT + Vector3.new(0, 0, 3)
		root.CFrame = moved
		root.Position = moved.Position
		near(DrawnBody.position(model), (moved * OFFSET).Position)
		DrawnBody.publish(model, nil)
		expect(DrawnBody.offset(model)).toBeNil()
		near(DrawnBody.position(model), moved.Position)
	end)

	it("moves a following billboard over the body in the publish call and back onto its root", function()
		DrawnBody.reset()
		local model = rig(ROOT)
		local gui = Instance.new("BillboardGui")
		DrawnBody.follow(gui, model, LIFT)
		near(gui.StudsOffsetWorldSpace, LIFT)
		DrawnBody.publish(model, OFFSET)
		-- StudsOffsetWorldSpace is world space from the adornee (the root part).
		near(gui.StudsOffsetWorldSpace, LIFT + ROOT:VectorToWorldSpace(OFFSET.Position))
		DrawnBody.publish(model, nil)
		near(gui.StudsOffsetWorldSpace, LIFT)
	end)

	it("puts a billboard over a body already drawn away when it starts following", function()
		DrawnBody.reset()
		local model = rig(ROOT)
		DrawnBody.publish(model, OFFSET)
		local gui = Instance.new("BillboardGui")
		DrawnBody.follow(gui, model, LIFT)
		near(gui.StudsOffsetWorldSpace, LIFT + ROOT:VectorToWorldSpace(OFFSET.Position))
	end)

	it("lets a billboard go back to its base on unfollow and follow one rig at a time", function()
		DrawnBody.reset()
		local model = rig(ROOT)
		local other = rig(CFrame.new(-5, 3, 0))
		local gui = Instance.new("BillboardGui")
		DrawnBody.follow(gui, model, LIFT)
		DrawnBody.publish(model, OFFSET)
		-- Following another rig leaves the first: its offsets no longer move the billboard.
		DrawnBody.follow(gui, other, LIFT)
		near(gui.StudsOffsetWorldSpace, LIFT)
		DrawnBody.publish(model, CFrame.new(0, 0, -12))
		near(gui.StudsOffsetWorldSpace, LIFT)
		DrawnBody.unfollow(gui, LIFT)
		DrawnBody.publish(other, OFFSET)
		near(gui.StudsOffsetWorldSpace, LIFT)
	end)

	it("adorns a following billboard to the part a step draws off the root, over the body, and back (D-533)", function()
		DrawnBody.reset()
		local model, root = rig(ROOT)
		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Parent = model
		local drawnAt = ROOT * OFFSET
		-- The Torso the step drew a little off the drawn root (the clip's own key there).
		torso.CFrame = drawnAt * CFrame.new(0, 0.4, 0.2)
		local gui = Instance.new("BillboardGui")
		gui.Adornee = root
		DrawnBody.follow(gui, model, LIFT)
		DrawnBody.publish(model, OFFSET, torso, drawnAt)
		expect(gui.Adornee).toBe(torso)
		near(torso.CFrame.Position + gui.StudsOffsetWorldSpace, drawnAt.Position + LIFT)
		-- The root part's move after the step carries nothing of it, nor of the answer to where the
		-- body is drawn (D-552; f446653 answered the root moved by the offset, 1.7 off here).
		root.CFrame = ROOT + Vector3.new(0, 0, 1.7)
		root.Position = root.CFrame.Position
		near(torso.CFrame.Position + gui.StudsOffsetWorldSpace, drawnAt.Position + LIFT)
		near(DrawnBody.position(model), drawnAt.Position)
		near((DrawnBody.cframe(model) :: CFrame).Position, drawnAt.Position)
		near((DrawnBody.cframe(model) :: CFrame).LookVector, drawnAt.LookVector)
		root.CFrame = ROOT
		root.Position = ROOT.Position
		-- Drawn on the joint again (no carrier), then back on its root: the owner's adornee.
		DrawnBody.publish(model, OFFSET)
		expect(gui.Adornee).toBe(root)
		DrawnBody.publish(model, OFFSET, torso, drawnAt)
		DrawnBody.publish(model, nil)
		expect(gui.Adornee).toBe(root)
		near(gui.StudsOffsetWorldSpace, LIFT)
		near(DrawnBody.position(model), ROOT.Position)
		-- An owner that adorns it anew meanwhile keeps its own adornee; unfollow gives the owner's back.
		DrawnBody.publish(model, OFFSET, torso, drawnAt)
		local other = Instance.new("Part")
		gui.Adornee = other
		DrawnBody.publish(model, nil)
		expect(gui.Adornee).toBe(other)
		gui.Adornee = root
		DrawnBody.publish(model, OFFSET, torso, drawnAt)
		DrawnBody.unfollow(gui, LIFT)
		expect(gui.Adornee).toBe(root)
		near(gui.StudsOffsetWorldSpace, LIFT)
		DrawnBody.reset()
	end)

	it("sets a billboard's own adornee at once, or for the hand-back while a carrier part holds it (D-571)", function()
		DrawnBody.reset()
		local model, root = rig(ROOT)
		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Parent = model
		local drawnAt = ROOT * OFFSET
		torso.CFrame = drawnAt
		local gui = Instance.new("BillboardGui")
		gui.Adornee = model
		DrawnBody.follow(gui, model, LIFT)
		DrawnBody.adorn(gui, root)
		expect(gui.Adornee).toBe(root)
		gui.Adornee = model
		DrawnBody.publish(model, OFFSET, torso, drawnAt)
		DrawnBody.adorn(gui, root)
		expect(gui.Adornee).toBe(torso)
		near(torso.CFrame.Position + gui.StudsOffsetWorldSpace, drawnAt.Position + LIFT)
		DrawnBody.publish(model, nil)
		expect(gui.Adornee).toBe(root)
		near(gui.StudsOffsetWorldSpace, LIFT)
		DrawnBody.unfollow(gui, LIFT)
		DrawnBody.reset()
	end)

	it("is where Engine.modelPosition places sounds and effects on a rig", function()
		DrawnBody.reset()
		local model = rig(ROOT)
		near(Engine.modelPosition(model), ROOT.Position)
		DrawnBody.publish(model, OFFSET)
		near(Engine.modelPosition(model), (ROOT * OFFSET).Position)
		DrawnBody.publish(model, nil)
		near(Engine.modelPosition(model), ROOT.Position)
		DrawnBody.reset()
	end)
end)
