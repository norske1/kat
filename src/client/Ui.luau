--!nonstrict
-- Tiny helpers for building UI from code.
local Ui = {}
local TweenService = game:GetService("TweenService")

Ui.Theme = {
	Background = Color3.fromRGB(14, 18, 21),
	Panel = Color3.fromRGB(23, 29, 32),
	PanelLight = Color3.fromRGB(35, 43, 46),
	Border = Color3.fromRGB(62, 73, 76),
	Accent = Color3.fromRGB(179, 133, 69),
	Text = Color3.fromRGB(235, 235, 223),
	TextDim = Color3.fromRGB(152, 166, 168),
	Good = Color3.fromRGB(126, 181, 146),
	Warn = Color3.fromRGB(223, 177, 89),
	Bad = Color3.fromRGB(208, 105, 94),
	Monitor = Color3.fromRGB(8, 12, 10),
	Font = Enum.Font.Gotham,
	FontBold = Enum.Font.GothamBold,
	FontMono = Enum.Font.RobotoMono,
}

function Ui.make(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(radius: number?): UICorner
	return Ui.make("UICorner", { CornerRadius = UDim.new(0, math.min(radius or 3, 3)) }) :: UICorner
end

function Ui.stroke(parent: Instance)
	return Ui.make("UIStroke", {
		Color = Ui.Theme.Border,
		Transparency = 0.35,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Ui.window(frame: GuiObject, width: number, height: number)
	Ui.stroke(frame)
	Ui.make("Frame", {
		Name = "AccentRule",
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Ui.Theme.Accent,
		Parent = frame,
	})
	Ui.fit(frame, width, height)
end

function Ui.fit(frame: GuiObject, width: number, height: number)
	local scale = Ui.make("UIScale", { Parent = frame }) :: UIScale
	local connection
	local function resize()
		local camera = workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			scale.Scale = math.min(1, math.max(0.1, (size.X - 32) / width), math.max(0.1, (size.Y - 80) / height))
		end
	end
	local function bind()
		if connection then
			connection:Disconnect()
		end
		local camera = workspace.CurrentCamera
		if camera then
			connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
		end
		resize()
	end
	local changed = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bind)
	frame.Destroying:Connect(function()
		changed:Disconnect()
		if connection then
			connection:Disconnect()
		end
	end)
	bind()
end

local modals: { [GuiObject]: boolean } = {}

function Ui.modal(frame: GuiObject)
	modals[frame] = true
	frame.Destroying:Once(function()
		modals[frame] = nil
	end)
end

function Ui.isModalOpen(): boolean
	for frame in modals do
		if Ui.isVisible(frame) then
			return true
		end
	end
	return false
end

function Ui.isVisible(object: Instance): boolean
	if not object:IsDescendantOf(game) then
		return false
	end
	local node: Instance? = object
	while node do
		if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
			return false
		elseif node:IsA("LayerCollector") and not (node :: LayerCollector).Enabled then
			return false
		end
		node = node.Parent
	end
	return true
end

function Ui.padding(px: number): UIPadding
	return Ui.make("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	}) :: UIPadding
end

function Ui.list(padding: number?, horizontal: boolean?): UIListLayout
	return Ui.make("UIListLayout", {
		Padding = UDim.new(0, padding or 4),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) :: UIListLayout
end

function Ui.label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = Ui.Theme.Text,
		Font = Ui.Theme.Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 18),
	}
	for k, v in props do
		defaults[k] = v
	end
	return Ui.make("TextLabel", defaults) :: TextLabel
end

function Ui.button(props: { [string]: any }): TextButton
	local defaults = {
		BackgroundColor3 = Ui.Theme.PanelLight,
		TextColor3 = Ui.Theme.Text,
		Font = Ui.Theme.Font,
		TextSize = 14,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 28),
	}
	for k, v in props do
		defaults[k] = v
	end
	local b = Ui.make("TextButton", defaults) :: TextButton
	Ui.corner(4).Parent = b
	b.AutoButtonColor = false
	local stroke = Ui.stroke(b)
	b.MouseEnter:Connect(function()
		if b.Active then
			TweenService:Create(stroke, TweenInfo.new(0.12), { Color = Ui.Theme.Accent, Transparency = 0 }):Play()
		end
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.12), { Color = Ui.Theme.Border, Transparency = 0.35 }):Play()
	end)
	return b
end

function Ui.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

function Ui.scroll(props: { [string]: any }): ScrollingFrame
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Ui.Theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}
	for k, v in props do
		defaults[k] = v
	end
	return Ui.make("ScrollingFrame", defaults) :: ScrollingFrame
end

return Ui
