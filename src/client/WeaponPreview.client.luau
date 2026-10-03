-- Asset preview only: this does not create projectiles, consume ammo, or damage players.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Animations = require(game.ReplicatedStorage.Medical.WeaponAssets.Animations)
local player = Players.LocalPlayer
local registered = setmetatable({}, { __mode = "k" })
local active = nil

local function register(tool)
	if not tool:IsA("Tool") or not tool:GetAttribute("WeaponAsset") or registered[tool] then
		return
	end
	registered[tool] = true
	local controller = Animations.new(tool)
	tool.Equipped:Connect(function()
		if active and active ~= controller then
			active:unequip()
		end
		active = controller
		controller:equip()
	end)
	tool.Unequipped:Connect(function()
		controller:unequip()
		if active == controller then
			active = nil
		end
	end)
	tool.Activated:Connect(function()
		controller:fire()
	end)
	tool.Destroying:Connect(function()
		controller:destroy()
		if active == controller then
			active = nil
		end
	end)
end

local backpack = player:WaitForChild("Backpack")
backpack.ChildAdded:Connect(register)
for _, child in backpack:GetChildren() do
	register(child)
end

local function watchCharacter(character)
	character.ChildAdded:Connect(register)
	for _, child in character:GetChildren() do
		register(child)
	end
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not active then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		active:reload()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		active:setAiming(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if active and input.UserInputType == Enum.UserInputType.MouseButton2 then
		active:setAiming(false)
	end
end)
