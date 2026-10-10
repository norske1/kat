--!nonstrict
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Medical = ReplicatedStorage:WaitForChild("Medical")
local Layout = require(Medical.Weapons.Hotbar)
local Gear = require(Medical.Gear.Gear)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme
local HotbarUi = {}

function HotbarUi.init(screen: ScreenGui, inventory)
	local player = Players.LocalPlayer
	local slots, cards = {}, {}
	local root = Ui.make("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(478, 68),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	local scale = Ui.make("UIScale", { Parent = root })
	local list = Ui.list(6, true)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = root
	local function usable()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		return hum ~= nil
			and hum.Health > 0
			and char:GetAttribute("MedAlive") ~= false
			and char:GetAttribute("MedConscious") ~= false
	end
	local function canEquip()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		return usable()
			and hum ~= nil
			and hum.SeatPart == nil
			and not Ui.isModalOpen()
			and not UserInputService:GetFocusedTextBox()
	end
	local function collect()
		local entries = {}
		for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
			if container then
				for _, tool in container:GetChildren() do
					if tool:IsA("Tool") then
						table.insert(entries, {
							tool = tool,
							name = tool.Name,
							weaponId = tool:GetAttribute("WeaponId"),
							itemId = tool:GetAttribute("GearItemId"),
						})
					end
				end
			end
		end
		slots = Layout.layout(entries)
	end
	local function selectSlot(index)
		if not canEquip() then
			return
		end
		collect()
		local entry = slots[index]
		if not entry then
			return
		end
		local tool = entry.tool
		local char = player.Character
		local hum = char:FindFirstChildOfClass("Humanoid")
		local backpack = player:FindFirstChildOfClass("Backpack")
		if tool.Parent == char then
			hum:UnequipTools()
		elseif tool.Parent == backpack then
			hum:EquipTool(tool)
		end
	end
	local function card(key, name, width, order)
		local button = Ui.button({
			Text = "",
			Size = UDim2.fromOffset(width, 68),
			LayoutOrder = order,
			BackgroundColor3 = T.Background,
			Parent = root,
		})
		local border = button:FindFirstChildOfClass("UIStroke") or Ui.stroke(button)
		Ui.label({
			Text = key,
			Font = T.FontMono,
			TextColor3 = T.Accent,
			TextSize = 12,
			Position = UDim2.fromOffset(10, 5),
			Size = UDim2.new(1, -20, 0, 16),
			Parent = button,
		})
		local title = Ui.label({
			Text = name,
			Font = T.FontBold,
			TextSize = 13,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(10, 23),
			Size = UDim2.new(1, -20, 0, 20),
			Parent = button,
		})
		local status = Ui.label({
			Text = "",
			TextColor3 = T.TextDim,
			Font = T.FontMono,
			TextSize = 10,
			Position = UDim2.fromOffset(10, 46),
			Size = UDim2.new(1, -20, 0, 16),
			Parent = button,
		})
		return { button = button, title = title, status = status, border = border }
	end
	for i, key in Layout.Keys do
		cards[i] = card(tostring(i), "", 88, i)
		cards[i].button.Activated:Connect(function()
			selectSlot(i)
		end)
		ContextActionService:BindActionAtPriority("HellboundSlot" .. i, function(_, inputState)
			if not canEquip() then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then
				selectSlot(i)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode[key])
	end
	local holster = card("0", "HOLSTER", 88, 10)
	holster.status.Text = "HANDS FREE"
	local function putAway()
		if canEquip() then
			player.Character:FindFirstChildOfClass("Humanoid"):UnequipTools()
		end
	end
	holster.button.Activated:Connect(putAway)
	ContextActionService:BindActionAtPriority("HellboundHolster", function(_, inputState)
		if not canEquip() then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			putAway()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.Zero)
	local bag = card("I", "INVENTORY", 108, 11)
	bag.status.Text = "FIELD GEAR"
	bag.button.Activated:Connect(function()
		if inventory then
			inventory.toggle()
		end
	end)
	local elapsed = 1
	local function refresh()
		collect()
		local count, equipped = 0, false
		for i, box in cards do
			local entry = slots[i]
			box.button.Visible = i <= 3 or entry ~= nil
			if box.button.Visible then
				count += 1
			end
			local active = entry and entry.tool.Parent == player.Character
			equipped = equipped or active == true
			local def = entry and entry.weaponId and Gear.def(entry.weaponId)
			box.title.Text = if entry then (if def then def.name else entry.name) else "EMPTY"
			box.status.Text = if entry
				then (if active then "EQUIPPED" else "READY")
				else ({ "PRIMARY", "HANDGUN", "LAUNCHER" })[i] or ""
			box.border.Color = if active then T.Accent else T.Border
		end
		holster.border.Color = if equipped then T.Border else T.Accent
		root.Size = UDim2.fromOffset(count * 94 + 202, 68)
	end
	RunService.RenderStepped:Connect(function(dt)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		root.Visible = usable() and not Ui.isModalOpen() and hum ~= nil and hum.SeatPart == nil
		elapsed += dt
		if elapsed >= 0.1 then
			elapsed = 0
			refresh()
		end
		local camera = workspace.CurrentCamera
		if camera then
			scale.Scale = math.min(1, math.max(0.1, (camera.ViewportSize.X - 32) / root.Size.X.Offset))
		end
	end)
	refresh()
	task.spawn(function()
		for _ = 1, 10 do
			if pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end) then
				return
			end
			task.wait(1)
		end
		warn("[Hellbound] Could not hide the default backpack UI")
	end)
end

return HotbarUi
