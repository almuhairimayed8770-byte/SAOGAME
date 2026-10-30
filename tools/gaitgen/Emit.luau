--!strict
--[[
	Clip source text for the gait generator. The text it writes is already what StyLua writes
	(stylua.toml: tabs, 120 columns), so a regenerated clip compares byte for byte with the
	committed file. Angles are written to 0.1 degree, positions to 0.0001 stud.
]]

local Keys = require("./Keys")

export type ClipKey = { time: number, easing: string, joints: Keys.Joints, comment: string? }

local Emit = {}

-- The joint order of every gait clip's keys.
local ORDER = {
	"Root",
	"Waist",
	"Neck",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"Weapon",
}

local ANGLE_STEP = 0.1 -- degrees
local POSITION_STEP = 0.0001 -- studs
local ZERO_ANGLE = 1e-9
local ZERO_POSITION = 1e-12
local MOVED = 1e-9 -- a position component past this writes posRot

local function round(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

--- An angle as the clip writes it ("12.3", "-4", "0").
function Emit.angle(value: number): string
	local rounded = round(value, ANGLE_STEP)
	if math.abs(rounded) < ZERO_ANGLE then
		rounded = 0
	end
	local text = ("%.1f"):format(rounded)
	text = text:gsub("%.0$", "")
	if text == "-0" then
		text = "0"
	end
	return text
end

--- A position as the clip writes it ("-0.0812", "0.03", "0").
function Emit.position(value: number): string
	local rounded = round(value, POSITION_STEP)
	if math.abs(rounded) < ZERO_POSITION then
		rounded = 0
	end
	local text = ("%.4f"):format(rounded)
	text = text:gsub("0+$", "")
	text = text:gsub("%.$", "")
	if text == "-0" then
		text = "0"
	end
	return text
end

--- One joint line of a key ("Waist = rot(-14, 10, 2),").
function Emit.jointLine(name: string, key: Keys.JointKey): string
	local pos = key.pos
	local rot = key.rot
	if pos and (math.abs(pos[1]) > MOVED or math.abs(pos[2]) > MOVED or math.abs(pos[3]) > MOVED) then
		return ("%s = posRot(%s, %s, %s, %s, %s, %s),"):format(
			name,
			Emit.position(pos[1]),
			Emit.position(pos[2]),
			Emit.position(pos[3]),
			Emit.angle(rot[1]),
			Emit.angle(rot[2]),
			Emit.angle(rot[3])
		)
	end
	return ("%s = rot(%s, %s, %s),"):format(name, Emit.angle(rot[1]), Emit.angle(rot[2]), Emit.angle(rot[3]))
end

--- The whole clip file for gait `name`.
function Emit.clip(name: string, gait: Keys.Gait, keys: { ClipKey }): string
	local lines: { string } = {}
	local function out(line: string)
		table.insert(lines, line)
	end
	out("--!strict")
	out("--[[")
	for _, line in gait.header do
		out("\t" .. line)
	end
	out("]]")
	out("")
	out("local Types = require(script.Parent.Parent.Parent.Parent.types)")
	out("")
	out("local function rot(x: number, y: number, z: number): Types.JointKey")
	out("\treturn { rot = { x, y, z } }")
	out("end")
	out("")
	out("local function posRot(px: number, py: number, pz: number, rx: number, ry: number, rz: number): Types.JointKey")
	out("\treturn { pos = { px, py, pz }, rot = { rx, ry, rz } }")
	out("end")
	out("")
	out("local clip: Types.ClipDef = {")
	out(('\tid = "player/OneHandedSword/%s",'):format(name))
	out('\trig = "PlayerR15",')
	out(("\tduration = %s,"):format(tostring(gait.duration)))
	out("\tloop = true,")
	if gait.sheathed then
		out("\tsheathed = true,")
	end
	out('\tlayer = "Base",')
	out("\tpriority = 0,")
	out("\tblendIn = 0.15,")
	out("\tblendOut = 0.15,")
	out("\tkeys = {")
	for _, key in keys do
		out("\t\t{")
		if key.comment then
			out("\t\t\t-- " .. key.comment)
		end
		out(("\t\t\ttime = %s,"):format(tostring(key.time)))
		out(('\t\t\teasing = "%s",'):format(key.easing))
		out("\t\t\tjoints = {")
		for _, joint in ORDER do
			local jointKey = key.joints[joint]
			if jointKey then
				out("\t\t\t\t" .. Emit.jointLine(joint, jointKey))
			end
		end
		out("\t\t\t},")
		out("\t\t},")
	end
	out("\t},")
	out("\tevents = {")
	for _, step in gait.events do
		out(('\t\t{ time = %s, kind = "Footstep", data = { foot = "%s" } },'):format(tostring(step.time), step.foot))
	end
	out("\t},")
	out("}")
	out("")
	out("return clip")
	return table.concat(lines, "\n") .. "\n"
end

return Emit
