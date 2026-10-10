--!nonstrict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Gear = require(ReplicatedStorage:WaitForChild("Medical").Gear.Gear)
local GearTools = {}
local provider

local function allowed(player, id)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil
		and hum.Health > 0
		and hum.SeatPart == nil
		and provider ~= nil
		and provider.canUse(player)
		and Gear.equipment(provider.get(player))[id] == true
end

local function create(player, id)
	local tool = Instance.new("Tool")
	tool.Name = Gear.def(id).name
	tool.ToolTip = if id == "Hammer" then "Equip to build using Alt + Build" else "Team / Squad / Command radio"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("GearItemId", id)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = if id == "Hammer" then Vector3.new(0.15, 1, 0.15) else Vector3.new(0.45, 0.7, 0.25)
	handle.Material = if id == "Hammer" then Enum.Material.Wood else Enum.Material.SmoothPlastic
	handle.Color = if id == "Hammer" then Color3.fromRGB(113, 85, 53) else Color3.fromRGB(45, 57, 48)
	handle.CanCollide, handle.CanTouch, handle.Massless = false, false, true
	handle.CanQuery = false
	handle.Parent = tool
	local function part(name, size, offset, color)
		local p = Instance.new("Part")
		p.Name, p.Size, p.Color = name, size, color
		p.CFrame = handle.CFrame * CFrame.new(offset)
		p.CanCollide, p.CanTouch, p.Massless = false, false, true
		p.CanQuery = false
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = handle, p
		weld.Parent = p
	end
	if id == "Hammer" then
		part("Head", Vector3.new(0.7, 0.24, 0.3), Vector3.new(0, 0.5, 0), Color3.fromRGB(93, 100, 104))
		tool.Grip = CFrame.new(0, -0.3, 0)
	else
		part("Antenna", Vector3.new(0.06, 0.55, 0.06), Vector3.new(0.15, 0.6, 0), Color3.fromRGB(25, 27, 27))
		part("Display", Vector3.new(0.3, 0.18, 0.03), Vector3.new(0, 0.12, -0.14), Color3.fromRGB(126, 181, 146))
	end
	tool.Equipped:Connect(function()
		local char = player.Character
		if not allowed(player, id) then
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:UnequipTools()
			end
			return
		end
		char:SetAttribute("GearHeldItem", id)
	end)
	local function clear()
		local char = player.Character
		if char and char:GetAttribute("GearHeldItem") == id then
			char:SetAttribute("GearHeldItem", nil)
		end
	end
	tool.Unequipped:Connect(clear)
	tool.Destroying:Connect(clear)
	return tool
end

function GearTools.sync(player, state)
	if not provider then
		return
	end
	local wanted, seen = Gear.equipment(state), {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in { backpack, player.Character } do
		if container then
			for _, tool in container:GetChildren() do
				local id = tool:IsA("Tool") and tool:GetAttribute("GearItemId")
				if id then
					if not wanted[id] or seen[id] then
						tool:Destroy()
					else
						seen[id] = true
					end
				end
			end
		end
	end
	if backpack then
		for id in wanted do
			if not seen[id] then
				create(player, id).Parent = backpack
			end
		end
	end
end

function GearTools.equip(player, id)
	if typeof(id) ~= "string" or not allowed(player, id) then
		return
	end
	local char = player.Character
	local hum = char:FindFirstChildOfClass("Humanoid")
	if GearTools.held(player, id) then
		hum:UnequipTools()
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, tool in backpack:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("GearItemId") == id then
				hum:EquipTool(tool)
				return
			end
		end
	end
end

function GearTools.held(player, id): boolean
	local char = player.Character
	if char and allowed(player, id) then
		for _, tool in char:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("GearItemId") == id then
				return true
			end
		end
	end
	return false
end

function GearTools.init(hooks)
	provider = hooks
end

return GearTools
