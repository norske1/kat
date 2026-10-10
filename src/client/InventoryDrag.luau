--!nonstrict
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Drag = require(ReplicatedStorage:WaitForChild("Medical").Gear.Drag)
local Gear = require(ReplicatedStorage.Medical.Gear.Gear)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme
local InventoryDrag = {}

local function inside(node, point)
	local p, s = node.AbsolutePosition, node.AbsoluteSize
	return point.X >= p.X and point.Y >= p.Y and point.X <= p.X + s.X and point.Y <= p.Y + s.Y
end

function InventoryDrag.new(screen, hooks)
	local controller = { gesture = nil, targets = {}, suppressUntil = 0 }
	local function pointOf(input)
		return if input.UserInputType == Enum.UserInputType.Touch
			then Vector2.new(input.Position.X, input.Position.Y)
			else UserInputService:GetMouseLocation()
	end
	local function destination(point)
		local found, priority = nil, 0
		for node, target in controller.targets do
			if Ui.isVisible(node) and inside(node, point) and target.priority > priority then
				found, priority = target.data(), target.priority
			end
		end
		return found
	end
	function controller:busy()
		return self.gesture ~= nil
	end
	function controller:clicked()
		return os.clock() >= self.suppressUntil and not (self.gesture and self.gesture.active)
	end
	function controller:cancel()
		local g = self.gesture
		if g and g.ghost then
			g.ghost:Destroy()
		end
		if g and g.active then
			self.suppressUntil = os.clock() + 0.2
		end
		self.gesture = nil
		for _, target in self.targets do
			target.outline.Visible = false
		end
	end
	function controller:target(node, data, priority)
		local outline = Ui.make("Frame", {
			Name = "DropTarget",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = node.ZIndex + 1,
			Parent = node,
		}, { Ui.corner(4) })
		local stroke = Ui.stroke(outline)
		stroke.Color, stroke.Thickness = T.Good, 2
		self.targets[node] = { data = data, priority = priority or 1, outline = outline, stroke = stroke }
	end
	function controller:origin(node, data)
		node.InputBegan:Connect(function(input)
			if
				not hooks.isOpen()
				or self.gesture
				or (
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				)
			then
				return
			end
			local point = pointOf(input)
			for _, child in node:GetChildren() do
				if child:IsA("GuiButton") and child.Visible and inside(child, point) then
					return
				end
			end
			local origin = data(
				UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			)
			if origin then
				self.gesture = { origin = origin, input = input, start = point, active = false }
			end
		end)
	end
	UserInputService.InputChanged:Connect(function(input)
		local g = controller.gesture
		if not g then
			return
		end
		local touch = g.input.UserInputType == Enum.UserInputType.Touch
		if (touch and input ~= g.input) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then
			return
		end
		local point = pointOf(input)
		if not g.active and Drag.started(g.start, point) then
			g.active = true
			g.ghost = Ui.label({
				Text = Gear.def(g.origin.id).name,
				TextSize = 14,
				TextColor3 = T.Text,
				Size = UDim2.fromOffset(240, 34),
				BackgroundColor3 = T.Panel,
				BackgroundTransparency = 0.05,
				ZIndex = 1000,
				Parent = screen,
			})
			Ui.corner(4).Parent = g.ghost
		end
		if g.active then
			g.ghost.Position = UDim2.fromOffset(point.X + 16, point.Y + 12)
			local request = Drag.request(g.origin, destination(point), hooks.state(), hooks.source())
			g.ghost.TextColor3 = if request then T.Good else T.Bad
			for node, target in controller.targets do
				target.outline.Visible = Drag.request(g.origin, target.data(), hooks.state(), hooks.source()) ~= nil
				target.stroke.Color = if inside(node, point) then T.Accent else T.Good
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local g = controller.gesture
		if not g then
			return
		end
		local touch = g.input.UserInputType == Enum.UserInputType.Touch
		if (touch and input ~= g.input) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseButton1) then
			return
		end
		local request = if g.active
			then Drag.request(g.origin, destination(pointOf(input)), hooks.state(), hooks.source())
			else nil
		controller:cancel()
		if request then
			hooks.send(table.unpack(request, 1, request.n))
		end
		if hooks.isOpen() then
			task.defer(hooks.render)
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and controller:busy() then
			controller:cancel()
			controller.suppressUntil = os.clock() + 0.2
			if hooks.isOpen() then
				hooks.render()
			end
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		controller:cancel()
		if hooks.isOpen() then
			hooks.render()
		end
	end)
	return controller
end

return InventoryDrag
