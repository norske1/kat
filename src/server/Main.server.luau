--!nonstrict
-- Entry point for the KAT-style medical system.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Config)
local Remotes = require(Medical.Remotes)
Remotes.init()

local MedicalService = require(script.Parent.MedicalService)
local Inventory = require(script.Parent.Inventory)
local ActionRunner = require(script.Parent.ActionRunner)
local Carry = require(script.Parent.Carry)
local Dummies = require(script.Parent.Dummies)
local MedicalAPI = require(script.Parent.MedicalAPI)

local lastRequest: { [Player]: number } = {}
local function throttled(player: Player): boolean
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < Config.RemoteCooldown then
		return true
	end
	lastRequest[player] = now
	return false
end

-- Players ------------------------------------------------------------------
local function onCharacter(player: Player, character: Model)
	MedicalService.register(character, player)
	Inventory.clear(player)
	Inventory.restock(player, MedicalService.medicLevel(player))
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
	player:GetAttributeChangedSignal("MedicalLevel"):Connect(function()
		Inventory.sync(player)
	end)
end)
for _, player in Players:GetPlayers() do
	task.spawn(function()
		if player.Character then
			onCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end)
end
Players.PlayerRemoving:Connect(function(player)
	ActionRunner.cancel(player)
	Carry.drop(player)
	Inventory.remove(player)
	lastRequest[player] = nil
end)

-- Remotes ------------------------------------------------------------------
Remotes.get("OpenMenu").OnServerEvent:Connect(function(player, target)
	if throttled(player) then
		return
	end
	local record
	if target == nil then
		record = MedicalService.getByPlayer(player)
	else
		record = MedicalService.get(target)
	end
	if not record then
		return
	end
	local ok, reason = MedicalService.openView(player, record)
	if not ok then
		MedicalService.notify(player, reason or "Cannot open", "error")
	end
end)

Remotes.get("CloseMenu").OnServerEvent:Connect(function(player)
	MedicalService.closeView(player)
end)

Remotes.get("RequestAction").OnServerEvent:Connect(function(player, target, actionId, part)
	if throttled(player) then
		return
	end
	ActionRunner.request(player, target, actionId, part)
end)

Remotes.get("CancelAction").OnServerEvent:Connect(function(player)
	ActionRunner.cancel(player)
end)

Remotes.get("DropCarry").OnServerEvent:Connect(function(player)
	Carry.drop(player)
end)

-- Debug tools (Studio / admins) -----------------------------------------------
local debugCommands = {
	hurt = function(player, part, amount, damageType)
		local char = player.Character
		if char then
			MedicalAPI.damage(char, part, tonumber(amount) or 30, damageType or "Bullet")
		end
	end,
	heal = function(player)
		local viewing = MedicalService.viewingOf(player)
		local target = if viewing then viewing.model else player.Character
		if target then
			MedicalService.heal(target)
		end
	end,
	level = function(player, level)
		MedicalAPI.setMedicalLevel(player, tonumber(level) or 0)
		Inventory.restock(player, MedicalService.medicLevel(player))
	end,
	restock = function(player)
		MedicalAPI.restock(player)
	end,
	dummy = function(player, scenario)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			Dummies.spawn(root.CFrame * CFrame.new(0, 0, -6), scenario)
		end
	end,
}

Remotes.get("Debug").OnServerEvent:Connect(function(player, command, ...)
	if not MedicalService.debugAllowed(player) or typeof(command) ~= "string" then
		return
	end
	local fn = debugCommands[command]
	if fn then
		fn(player, ...)
	end
end)

-- Supply crates ----------------------------------------------------------------
local function setupSupply(part: Instance)
	if not part:IsA("BasePart") or part:FindFirstChild("MedicalSupplyPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MedicalSupplyPrompt"
	prompt.ActionText = "Restock medical supplies"
	prompt.ObjectText = "Medical Supplies"
	prompt.HoldDuration = 1
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		Inventory.restock(player, MedicalService.medicLevel(player))
		MedicalService.notify(player, "Medical supplies restocked", "result")
	end)
end
for _, part in CollectionService:GetTagged("MedicalSupply") do
	setupSupply(part)
end
CollectionService:GetInstanceAddedSignal("MedicalSupply"):Connect(setupSupply)

-- Start ------------------------------------------------------------------------
MedicalService.start()

if Config.SpawnTrainingDummies and (RunService:IsStudio() or Config.AllowDummiesInLive) then
	task.defer(function()
		local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
		local origin = if spawnLocation then spawnLocation.CFrame else CFrame.new(0, 3, 0)
		local scenarios = { "GunshotLeg", "Unconscious", "CardiacArrest", "Blast", "Overmedicated" }
		for i, scenario in scenarios do
			Dummies.spawn(origin * CFrame.new((i - 3) * 7, 3, -16), scenario)
		end
	end)
end

-- The game mode runs before the weapons so the lockers at its team bases exist when the locker system starts.
local gameOk, gameErr = pcall(function()
	require(script.Parent.GameMode.GameService).init()
end)
if not gameOk then
	warn("[KATMedical] game mode failed to start: " .. tostring(gameErr))
end

-- Guns are optional: a failure there must not take the medical system down with it.
local weaponsOk, weaponsErr = pcall(function()
	require(script.Parent.Weapons.WeaponService).init()
end)
if not weaponsOk then
	warn("[KATMedical] weapon system failed to start: " .. tostring(weaponsErr))
end
print("[KATMedical] server started" .. (if weaponsOk then "" else " (weapons disabled)"))
