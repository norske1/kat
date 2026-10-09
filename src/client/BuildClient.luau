--!nonstrict
-- Build menu (B, Squad Commanders and the Commander): pick a structure, move the ghost with the mouse, R rotates,
-- left click places, right click / Escape cancels. Also shows the supplies of the FOB you're standing in.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Logistics.Config)
local Logistics = require(Medical.Logistics.Logistics)
local Remotes = require(Medical.Remotes)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

local BuildClient = {}

local player = Players.LocalPlayer
local menu, fobLabel
local ghost: Part? = nil
local ghostKind: string? = nil
local yaw = 0

local function isLeader(): boolean
	return Logistics.LEADERS[player:GetAttribute("Class") or ""] == true
end

local function cancel()
	if ghost then
		ghost:Destroy()
	end
	ghost, ghostKind = nil, nil
end

local function startGhost(kind: string)
	cancel()
	local def = Config.Structures[kind]
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = def.size
	p.Color = Color3.fromRGB(90, 200, 110)
	p.Transparency = 0.5
	p.Material = Enum.Material.ForceField
	p.Parent = workspace.CurrentCamera
	ghost, ghostKind = p, kind
	menu.Visible = false
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
end

local function ghostCFrame(): CFrame?
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, ghost }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * Config.PlaceRange * 2, params)
	if not hit then
		return nil
	end
	return CFrame.new(hit.Position) * CFrame.Angles(0, math.rad(yaw), 0)
end

function BuildClient.init(screen: ScreenGui)
	local remote = Remotes.get("Build")
	menu = Ui.make("Frame", {
		Name = "BuildMenu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(230, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = screen,
	}, {
		Ui.corner(6),
		Ui.make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.make("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	})
	Ui.label({
		Text = "BUILD  (B to close)",
		Font = T.FontBold,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 0,
		Parent = menu,
	})
	for kind, def in Config.Structures do
		local button = Ui.make("TextButton", {
			Text = string.format("%s   %s", def.name, if def.cost > 0 then def.cost .. " supplies" else "free"),
			Font = T.Font,
			TextSize = 14,
			TextColor3 = T.Text,
			BackgroundColor3 = T.PanelLight,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = def.order,
			Parent = menu,
		}, { Ui.corner(4) })
		button.MouseButton1Click:Connect(function()
			startGhost(kind)
		end)
	end
	fobLabel = Ui.label({
		Text = "",
		Font = T.FontBold,
		TextSize = 13,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 262),
		Size = UDim2.fromOffset(210, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = screen,
	})

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2 then
			if ghost then
				cancel()
			end
			return
		end
		if ghost and input.UserInputType == Enum.UserInputType.MouseButton1 then
			local cf = ghostCFrame()
			if cf then
				remote:FireServer("place", ghostKind, cf)
			end
			cancel()
			return
		end
		if processed then
			return
		end
		if input.KeyCode == Config.BuildKey and player.Character then
			if ghost then
				cancel()
			elseif isLeader() then
				menu.Visible = not menu.Visible
			end
		elseif input.KeyCode == Enum.KeyCode.R and ghost then
			yaw = (yaw + 45) % 360
		end
	end)
	player.CharacterRemoving:Connect(function()
		cancel()
		menu.Visible = false
	end)

	RunService.RenderStepped:Connect(function()
		if menu.Visible and not isLeader() then
			menu.Visible = false
		end
		if ghost then
			local cf = ghostCFrame()
			if cf then
				ghost.CFrame = cf * CFrame.new(0, ghost.Size.Y / 2, 0)
			end
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local mySide = player.Team and player.Team:GetAttribute("Side")
		local text = ""
		if root then
			for _, fob in CollectionService:GetTagged("FOB") do
				if fob:IsA("BasePart") and fob:GetAttribute("Side") == mySide then
					local d = Vector2.new(fob.Position.X - root.Position.X, fob.Position.Z - root.Position.Z).Magnitude
					if d <= Config.FobRadius then
						text = string.format("FOB  supplies %d", fob:GetAttribute("Stock") or 0)
						break
					end
				end
			end
		end
		fobLabel.Text = text
	end)
end

return BuildClient
