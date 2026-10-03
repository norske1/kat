-- Minimal Roblox-like module loader so shared modules can run under Lune.
-- The source tree is scanned eagerly (Lune fs calls cannot run inside metamethods).
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Enum = setmetatable({}, {
	__index = function(_, enumName)
		return setmetatable({}, {
			__index = function(_, item)
				return { Name = item, EnumType = enumName }
			end,
		})
	end,
})

local function build(path: string, name: string, parent)
	local n = { Name = name, Parent = parent, __path = path, __children = {} }
	setmetatable(n, {
		__index = function(self, key)
			local child = rawget(self, "__children")[key]
			if child == nil then
				error("child " .. tostring(key) .. " not found in " .. rawget(self, "__path"), 2)
			end
			return child
		end,
	})
	if fs.isDir(path) then
		for _, entry in fs.readDir(path) do
			local childPath = path .. "/" .. entry
			local childName = string.gsub(entry, "%.luau$", "")
			if fs.isDir(childPath) or string.match(entry, "%.luau$") then
				n.__children[childName] = build(childPath, childName, n)
			end
		end
	end
	return n
end

local sources = {}
local cache = {}

local function collect(n)
	local path = rawget(n, "__path")
	if string.match(path, "%.luau$") then
		sources[path] = fs.readFile(path)
	end
	for _, child in rawget(n, "__children") do
		collect(child)
	end
end

local root = build("src/shared/Medical", "Medical", nil)
collect(root)

local function rbxRequire(target)
	local path = rawget(target, "__path")
	if cache[path] ~= nil then
		return cache[path]
	end
	local env = setmetatable({ script = target, require = rbxRequire, Enum = Enum }, { __index = getfenv() })
	local fn = luau.load(sources[path], { debugName = path, environment = env })
	local result = fn()
	cache[path] = result
	return result
end

local Harness = {}

function Harness.require(relative: string)
	local n = root
	for segment in string.gmatch(relative, "[^/]+") do
		n = n[segment]
	end
	return rbxRequire(n)
end

return Harness
