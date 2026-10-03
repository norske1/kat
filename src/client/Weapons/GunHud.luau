--!nonstrict
-- Crosshair, hit marker and ammo counter.
local TweenService = game:GetService("TweenService")
local Ui = require(script.Parent.Parent.Ui)
local T = Ui.Theme

local GunHud = {}

local root, crosshair, dot, hitmarker
local bars = {}
local nameLabel, ammoLabel, modeLabel, panel

local function bar(size: UDim2): Frame
	return Ui.make("Frame", {
		Size = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = crosshair,
	}, {
		Ui.make("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.4 }),
	}) :: Frame
end

function GunHud.init(screen: ScreenGui)
	root = Ui.make("Frame", {
		Name = "Weapon",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = screen,
	})
	crosshair = Ui.make("Frame", {
		Size = UDim2.fromOffset(0, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = root,
	})
	bars.top = bar(UDim2.fromOffset(2, 10))
	bars.bottom = bar(UDim2.fromOffset(2, 10))
	bars.left = bar(UDim2.fromOffset(10, 2))
	bars.right = bar(UDim2.fromOffset(10, 2))
	dot = bar(UDim2.fromOffset(3, 3))

	hitmarker = Ui.make("Frame", {
		Size = UDim2.fromOffset(0, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 21,
		Parent = root,
	})
	for _, rotation in { 45, -45 } do
		Ui.make("Frame", {
			Size = UDim2.fromOffset(18, 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = rotation,
			BackgroundColor3 = T.Bad,
			BorderSizePixel = 0,
			ZIndex = 21,
			Parent = hitmarker,
		})
	end

	panel = Ui.make("Frame", {
		Size = UDim2.fromOffset(170, 64),
		Position = UDim2.new(1, -320, 1, -84),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.2,
		ZIndex = 20,
		Parent = root,
	}, { Ui.corner(6) })
	nameLabel = Ui.make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.fromOffset(8, 4),
		BackgroundTransparency = 1,
		Font = T.FontBold,
		TextSize = 13,
		TextColor3 = T.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
		Parent = panel,
	})
	ammoLabel = Ui.make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 28),
		Position = UDim2.fromOffset(8, 20),
		BackgroundTransparency = 1,
		Font = T.FontMono,
		TextSize = 24,
		TextColor3 = T.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
		Parent = panel,
	})
	modeLabel = Ui.make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 14),
		Position = UDim2.fromOffset(8, 46),
		BackgroundTransparency = 1,
		Font = T.Font,
		TextSize = 11,
		TextColor3 = T.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
		Parent = panel,
	})
end

function GunHud.show(visible: boolean)
	root.Visible = visible
end

-- spread in degrees -> crosshair gap in pixels
function GunHud.setSpread(spread: number, aiming: boolean)
	local camera = workspace.CurrentCamera
	local fov = if camera then camera.FieldOfView else 70
	local height = if camera then camera.ViewportSize.Y else 720
	local gap = math.clamp(math.tan(math.rad(spread)) / math.tan(math.rad(fov / 2)) * height / 2, 2, 120) + 4
	bars.top.Position = UDim2.fromOffset(0, -gap - 5)
	bars.bottom.Position = UDim2.fromOffset(0, gap + 5)
	bars.left.Position = UDim2.fromOffset(-gap - 5, 0)
	bars.right.Position = UDim2.fromOffset(gap + 5, 0)
	for _, b in bars do
		b.Visible = not aiming
	end
	dot.Visible = true
end

function GunHud.setAmmo(name: string, ammo: number, reserve: number, mode: string, reloading: boolean)
	nameLabel.Text = name
	ammoLabel.Text = string.format("%d / %d", ammo, reserve)
	ammoLabel.TextColor3 = if ammo == 0 then T.Bad elseif reloading then T.Warn else T.Text
	modeLabel.Text = if reloading then "RELOADING..." else string.upper(mode) .. "   [R] reload  [V] mode"
end

function GunHud.hit(kind: number)
	hitmarker.Visible = true
	for _, child in hitmarker:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundColor3 = if kind == 2 then T.Bad else T.Text
			child.BackgroundTransparency = 0
			TweenService:Create(child, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		end
	end
end

return GunHud
