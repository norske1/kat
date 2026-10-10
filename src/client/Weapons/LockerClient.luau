--!nonstrict
-- Hold Alt to select a locker item with the cursor; the server validates every take.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local WeaponConfig = require(Medical:WaitForChild("Weapons").Config)
local Remotes = require(Medical.Remotes)
local Ui = require(script.Parent.Parent.Ui)
local InteractionInput = require(script.Parent.Parent.InteractionInput)

local LockerClient = {}

local player = Players.LocalPlayer
local remote
local hovered: BasePart? = nil
local highlight: Highlight
local tip: TextLabel

local function pick(ray: Ray?): BasePart?
	local camera = workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not camera or not root then
		return nil
	end
	local cast: Ray
	if ray then
		cast = ray
	else
		local cursor = InteractionInput.cursorRay()
		if not cursor then
			return nil
		end
		cast = cursor
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local result = workspace:Raycast(cast.Origin, cast.Direction * 80, params)
	if not result or not result.Instance:GetAttribute("LockerItem") then
		return nil
	end
	if (result.Position - root.Position).Magnitude > WeaponConfig.LockerReach then
		return nil
	end
	return result.Instance :: BasePart
end

local function setHovered(slot: BasePart?)
	if slot == hovered then
		return
	end
	hovered = slot
	local link = slot and slot:FindFirstChild("Display")
	highlight.Adornee = if link and link:IsA("ObjectValue") then link.Value else nil
	highlight.Enabled = slot ~= nil
	tip.Visible = slot ~= nil
	if slot then
		tip.Text = "[Click] " .. tostring(slot:GetAttribute("LockerLabel") or "Take")
	end
end

-- True while the cursor / crosshair is on a locker item (guns don't fire then).
function LockerClient.hovering(): boolean
	return hovered ~= nil
end

local function take(slot: BasePart?)
	if slot and InteractionInput.isActive() then
		remote:FireServer(slot)
	end
end

function LockerClient.init(screen: ScreenGui)
	remote = Remotes.get("LockerTake")
	highlight = Instance.new("Highlight")
	highlight.Name = "LockerHighlight"
	highlight.FillColor = Color3.fromRGB(255, 220, 120)
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = Color3.fromRGB(255, 230, 150)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	-- with no Adornee a Highlight outlines its parent, so keep it in an empty folder
	local holder = Instance.new("Folder")
	holder.Name = "LockerFx"
	holder.Parent = workspace
	highlight.Parent = holder
	tip = Ui.label({
		Name = "LockerTip",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(220, 26),
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.fromRGB(20, 22, 24),
		TextColor3 = Color3.fromRGB(255, 235, 180),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 30,
		Parent = screen,
	})

	RunService.RenderStepped:Connect(function()
		if not UserInputService.MouseEnabled and not UserInputService.GamepadEnabled then
			return -- touch only: picked on tap
		end
		setHovered(if InteractionInput.isActive() then pick(nil) else nil)
		if hovered then
			local point = UserInputService:GetMouseLocation()
			tip.Position = UDim2.fromOffset(point.X + 18, math.max(16, point.Y - 36))
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			take(hovered)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			local camera = workspace.CurrentCamera
			if camera then
				take(pick(camera:ScreenPointToRay(input.Position.X, input.Position.Y)))
			end
		end
	end)
end

return LockerClient
