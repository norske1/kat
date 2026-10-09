--!nonstrict
-- Client entry point: builds the medical UI and handles input.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Config)
local Remotes = require(Medical.Remotes)
local Menu = require(script.Parent.Menu)
local Hud = require(script.Parent.Hud)
local Effects = require(script.Parent.Effects)

local player = Players.LocalPlayer

local screen = Instance.new("ScreenGui")
screen.Name = "MedicalUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = player:WaitForChild("PlayerGui")

Effects.init(screen)
Hud.init(screen)
Menu.init(screen)

-- Animations and guns are optional: if they fail, the medical UI keeps working.
local function optional(name: string, start: () -> any): any
	local ok, result = pcall(start)
	if not ok then
		warn("[KATMedical] " .. name .. " failed to start: " .. tostring(result))
		return nil
	end
	return result
end
optional("main menu", function()
	require(script.Parent.MainMenu).init()
end)
optional("animations", function()
	require(script.Parent.Animator).init()
end)
optional("game mode HUD", function()
	require(script.Parent.GameModeHud).init(screen)
end)
local GunClient = optional("weapons", function()
	local module = require(script.Parent.Weapons.GunClient)
	module.init(screen)
	return module
end)

if Config.HideDefaultHealthBar then
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
			end)
			if ok then
				break
			end
			task.wait(1)
		end
	end)
end

Remotes.get("View").OnClientEvent:Connect(function(view)
	Menu.setView(view)
end)
Remotes.get("Effects").OnClientEvent:Connect(function(data)
	Effects.update(data)
	if GunClient then
		GunClient.setMedical(data)
	end
end)
Remotes.get("Progress").OnClientEvent:Connect(function(data)
	Hud.setProgress(data)
end)
Remotes.get("Notify").OnClientEvent:Connect(function(text, kind)
	Hud.notify(text, kind)
end)
Remotes.get("Inventory").OnClientEvent:Connect(function(items, level, debugAllowed, infinite)
	Hud.setInventory(items, level, debugAllowed, infinite)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local key = input.KeyCode
	if key == Config.SelfMenuKey then
		if Menu.isOpen() then
			Menu.requestClose()
		else
			Remotes.get("OpenMenu"):FireServer(nil)
		end
	elseif key == Enum.KeyCode.X then
		Remotes.get("CancelAction"):FireServer()
	elseif key == Config.DropCarryKey then
		Remotes.get("DropCarry"):FireServer()
	elseif key == Enum.KeyCode.I then
		Hud.toggleBag()
	elseif key == Config.DebugToggleKey then
		Hud.toggleDebug()
	elseif key == Enum.KeyCode.Escape and Menu.isOpen() then
		Menu.requestClose()
	end
end)
