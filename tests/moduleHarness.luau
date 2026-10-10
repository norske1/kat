local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Harness = {}

function Harness.signal()
	local callbacks = {}
	return {
		Connect = function(_, fn)
			callbacks[fn] = true
			return {
				Disconnect = function()
					callbacks[fn] = nil
				end,
			}
		end,
		Once = function(self, fn)
			local connection
			connection = self:Connect(function(...)
				connection:Disconnect()
				fn(...)
			end)
			return connection
		end,
		Fire = function(_, ...)
			for fn in table.clone(callbacks) do
				fn(...)
			end
		end,
	}
end

local methods = {}
function methods:IsA(class)
	return self.ClassName == class
		or (class == "GuiObject" and table.find(
			{ "Frame", "TextLabel", "TextButton", "ScrollingFrame" },
			self.ClassName
		) ~= nil)
		or (class == "GuiButton" and self.ClassName == "TextButton")
		or (class == "LayerCollector" and self.ClassName == "ScreenGui")
		or (class == "UIComponent" and string.sub(self.ClassName, 1, 2) == "UI")
end
function methods:GetChildren()
	return table.clone(self._children)
end
function methods:FindFirstChild(name)
	for _, child in self._children do
		if child.Name == name then
			return child
		end
	end
end
function methods:FindFirstChildOfClass(class)
	for _, child in self._children do
		if child:IsA(class) then
			return child
		end
	end
end
methods.WaitForChild = methods.FindFirstChild
function methods:SetAttribute(name, value)
	self._attributes[name] = value
end
function methods:GetAttribute(name)
	return self._attributes[name]
end
function methods:GetPropertyChangedSignal(name)
	self._signals[name] = self._signals[name] or Harness.signal()
	return self._signals[name]
end
function methods:IsDescendantOf(ancestor)
	local node = self.Parent
	while node do
		if node == ancestor then
			return true
		end
		node = node.Parent
	end
	return false
end
function methods:Destroy()
	self.Destroying:Fire()
	for _, child in self:GetChildren() do
		child:Destroy()
	end
	self.Parent = nil
end

function Harness.node(class)
	local data = {
		ClassName = class,
		Name = class,
		_children = {},
		_attributes = {},
		_signals = {},
		Visible = true,
		Enabled = true,
		Active = true,
		ZIndex = 1,
		Health = 100,
		AbsolutePosition = roblox.Vector2.zero,
		AbsoluteSize = roblox.Vector2.new(500, 500),
		CFrame = roblox.CFrame.new(),
		ViewportSize = roblox.Vector2.new(1920, 1080),
	}
	for _, name in
		{
			"Equipped",
			"Unequipped",
			"Destroying",
			"MouseEnter",
			"MouseLeave",
			"Activated",
			"MouseButton2Click",
			"InputBegan",
			"InputChanged",
			"InputEnded",
			"WindowFocusReleased",
			"CharacterRemoving",
			"CharacterAdded",
			"ChildAdded",
			"RenderStepped",
		}
	do
		data[name] = Harness.signal()
	end
	local node = setmetatable({}, {
		__index = function(_, key)
			return if data[key] ~= nil then data[key] else methods[key]
		end,
		__newindex = function(self, key, value)
			if key == "Parent" then
				assert(value == nil or (type(value) == "table" and value.IsA), "Parent must be an Instance")
				if data.Parent then
					table.remove(data.Parent._children, table.find(data.Parent._children, self))
				end
				if value then
					table.insert(value._children, self)
				end
			end
			data[key] = value
		end,
	})
	return node
end

function Harness.load(path, env)
	for _, name in { "Color3", "Vector2", "Vector3", "CFrame", "UDim", "UDim2", "Enum" } do
		env[name] = env[name] or roblox[name]
	end
	env.Instance = env.Instance or { new = Harness.node }
	return luau.load(fs.readFile("src/" .. path .. ".luau"), {
		debugName = path,
		environment = setmetatable(env, { __index = getfenv() }),
	})()
end

return Harness
