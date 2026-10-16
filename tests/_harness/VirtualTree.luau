--!strict
--[[
	VirtualTree: a fake Roblox Instance tree built from the src/ directories, mirroring what
	Rojo would build (folder -> Folder, foo.luau -> ModuleScript, foo.server.luau -> Script,
	foo.client.luau -> LocalScript, dir/init.luau -> ModuleScript with children).

	Game modules reference each other with `script.Parent.x` and `game:GetService(...)`; this
	tree lets Lune resolve those paths without changing a line of game code (docs/DECISIONS.md D-002).
]]

local fs = require("@lune/fs")

export type Node = {
	Name: string,
	ClassName: string,
	Parent: Node?,
	[string]: any,
}

local VirtualTree = {}

local methods = {}
local NodeMeta = {}

local function rawChildren(node: any): { [string]: any }
	return rawget(node, "_children")
end

function methods.FindFirstChild(node: any, name: string, recursive: boolean?): any
	local child = rawChildren(node)[name]
	if child ~= nil then
		return child
	end
	if recursive then
		for _, candidate in rawChildren(node) do
			local found = methods.FindFirstChild(candidate, name, true)
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

function methods.WaitForChild(node: any, name: string, _timeout: number?): any
	local child = rawChildren(node)[name]
	if child == nil then
		error(("WaitForChild: '%s' is not a child of %s"):format(name, methods.GetFullName(node)), 2)
	end
	return child
end

function methods.GetChildren(node: any): { any }
	local list = {}
	for _, child in rawChildren(node) do
		table.insert(list, child)
	end
	table.sort(list, function(a, b)
		return rawget(a, "Name") < rawget(b, "Name")
	end)
	return list
end

function methods.GetDescendants(node: any): { any }
	local list = {}
	for _, child in methods.GetChildren(node) do
		table.insert(list, child)
		for _, grandchild in methods.GetDescendants(child) do
			table.insert(list, grandchild)
		end
	end
	return list
end

function methods.IsA(node: any, className: string): boolean
	local own = rawget(node, "ClassName")
	if own == className then
		return true
	end
	if className == "Instance" then
		return true
	end
	if className == "LuaSourceContainer" then
		return own == "ModuleScript" or own == "Script" or own == "LocalScript"
	end
	if className == "BaseScript" then
		return own == "Script" or own == "LocalScript"
	end
	return false
end

function methods.GetFullName(node: any): string
	local parent = rawget(node, "_parent")
	if parent == nil then
		return rawget(node, "Name")
	end
	return methods.GetFullName(parent) .. "." .. rawget(node, "Name")
end

function methods.FindFirstAncestor(node: any, name: string): any
	local parent = rawget(node, "_parent")
	while parent ~= nil do
		if rawget(parent, "Name") == name then
			return parent
		end
		parent = rawget(parent, "_parent")
	end
	return nil
end

function methods.FindFirstAncestorOfClass(node: any, className: string): any
	local parent = rawget(node, "_parent")
	while parent ~= nil do
		if rawget(parent, "ClassName") == className then
			return parent
		end
		parent = rawget(parent, "_parent")
	end
	return nil
end

function methods.IsDescendantOf(node: any, other: any): boolean
	local parent = rawget(node, "_parent")
	while parent ~= nil do
		if parent == other then
			return true
		end
		parent = rawget(parent, "_parent")
	end
	return false
end

function methods.GetAttribute(node: any, name: string): any
	return rawget(node, "_attributes")[name]
end

function methods.SetAttribute(node: any, name: string, value: any)
	rawget(node, "_attributes")[name] = value
end

function methods.GetAttributes(node: any): { [string]: any }
	return table.clone(rawget(node, "_attributes"))
end

function methods.GetService(node: any, name: string): any
	local service = rawChildren(node)[name]
	if service == nil then
		error(("GetService: no stub registered for service '%s' (use Harness.stubService)"):format(name), 2)
	end
	return service
end

function methods.Destroy(node: any)
	local parent = rawget(node, "_parent")
	if parent ~= nil then
		rawChildren(parent)[rawget(node, "Name")] = nil
		rawset(node, "_parent", nil)
	end
end

function NodeMeta.__index(node: any, key: any): any
	local method = methods[key]
	if method ~= nil then
		return method
	end
	if key == "Parent" then
		return rawget(node, "_parent")
	end
	local child = rawChildren(node)[key]
	if child ~= nil then
		return child
	end
	local extra = rawget(node, "_props")[key]
	if extra ~= nil then
		return extra
	end
	error(
		('%s is not a valid member of %s "%s"'):format(
			tostring(key),
			rawget(node, "ClassName"),
			methods.GetFullName(node)
		),
		2
	)
end

function NodeMeta.__newindex(node: any, key: any, value: any)
	if key == "Parent" then
		local old = rawget(node, "_parent")
		if old ~= nil then
			rawChildren(old)[rawget(node, "Name")] = nil
		end
		rawset(node, "_parent", value)
		if value ~= nil then
			rawChildren(value)[rawget(node, "Name")] = node
		end
		return
	end
	rawget(node, "_props")[key] = value
end

function NodeMeta.__tostring(node: any): string
	return rawget(node, "Name")
end

--- Creates a node; `path` is the source file for scripts, nil for folders and stubs.
function VirtualTree.newNode(name: string, className: string, path: string?): any
	local node = {
		Name = name,
		ClassName = className,
		_parent = nil,
		_children = {},
		_attributes = {},
		_props = {},
		_path = path,
		_isVirtualInstance = true,
	}
	return setmetatable(node, NodeMeta)
end

--- Adds `child` under `parent` and returns it.
function VirtualTree.adopt(parent: any, child: any): any
	rawset(child, "_parent", parent)
	rawChildren(parent)[rawget(child, "Name")] = child
	return child
end

function VirtualTree.isNode(value: any): boolean
	return typeof(value) == "table" and rawget(value, "_isVirtualInstance") == true
end

function VirtualTree.sourcePath(node: any): string?
	return rawget(node, "_path")
end

local function classify(fileName: string): (string?, string?)
	if fileName:match("%.spec%.luau$") then
		return nil, nil
	end
	local name = fileName:match("^(.-)%.server%.luau$")
	if name then
		return name, "Script"
	end
	name = fileName:match("^(.-)%.client%.luau$")
	if name then
		return name, "LocalScript"
	end
	name = fileName:match("^(.-)%.luau$")
	if name then
		return name, "ModuleScript"
	end
	return nil, nil
end

--- Builds a node tree from a directory the way Rojo would.
function VirtualTree.fromDirectory(directory: string, name: string): any
	local entries = fs.readDir(directory)
	local initPath = directory .. "/init.luau"
	local node
	if fs.isFile(initPath) then
		node = VirtualTree.newNode(name, "ModuleScript", initPath)
	else
		node = VirtualTree.newNode(name, "Folder", nil)
	end
	for _, entry in entries do
		local fullPath = directory .. "/" .. entry
		if fs.isDir(fullPath) then
			VirtualTree.adopt(node, VirtualTree.fromDirectory(fullPath, entry))
		elseif entry ~= "init.luau" then
			local childName, className = classify(entry)
			if childName and className then
				VirtualTree.adopt(node, VirtualTree.newNode(childName, className, fullPath))
			end
		end
	end
	return node
end

return VirtualTree
