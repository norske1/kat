--!nonstrict
-- Tiny helpers for building UI from code.
local Ui = {}

Ui.Theme = {
	Background = Color3.fromRGB(22, 25, 30),
	Panel = Color3.fromRGB(32, 36, 43),
	PanelLight = Color3.fromRGB(45, 50, 59),
	Accent = Color3.fromRGB(200, 40, 45),
	Text = Color3.fromRGB(230, 232, 235),
	TextDim = Color3.fromRGB(150, 155, 165),
	Good = Color3.fromRGB(70, 200, 110),
	Warn = Color3.fromRGB(240, 180, 50),
	Bad = Color3.fromRGB(235, 70, 70),
	Monitor = Color3.fromRGB(8, 12, 10),
	Font = Enum.Font.Gotham,
	FontBold = Enum.Font.GothamBold,
	FontMono = Enum.Font.RobotoMono,
}

function Ui.make(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	local inst = Instance.new(className)
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
	return Ui.make("UICorner", { CornerRadius = UDim.new(0, radius or 6) }) :: UICorner
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
	return b
end

function Ui.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
end

function Ui.scroll(props: { [string]: any }): ScrollingFrame
	local defaults = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
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
