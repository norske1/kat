--!nonstrict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Medical = ReplicatedStorage:WaitForChild("Medical")
local Remotes = require(Medical.Remotes)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme
local VehicleCargoUi = {}

function VehicleCargoUi.init()
	local remote = Remotes.get("VehicleCargo")
	local state, quantity = nil, 100
	local gui = Ui.make("ScreenGui", {
		Name = "VehicleCargoUI",
		ResetOnSpawn = false,
		Enabled = false,
		DisplayOrder = 30,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Ui.make("TextButton", {
		Text = "",
		Modal = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.25,
		Parent = gui,
	})
	local window = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 490),
		BackgroundColor3 = T.Background,
		Parent = gui,
	}, { Ui.corner(3) })
	Ui.window(window, 760, 490)
	Ui.modal(window)
	local title = Ui.label({
		Text = "VEHICLE CARGO",
		Font = T.FontBold,
		TextSize = 26,
		Position = UDim2.fromOffset(24, 20),
		Size = UDim2.new(1, -90, 0, 34),
		Parent = window,
	})
	Ui.label({
		Text = "LOGISTICS  /  SUPPLY TRANSFER",
		TextColor3 = T.Accent,
		Font = T.FontMono,
		TextSize = 11,
		Position = UDim2.fromOffset(24, 58),
		Size = UDim2.fromOffset(600, 18),
		Parent = window,
	})
	local function close()
		gui.Enabled = false
		state = nil
		remote:FireServer("close")
	end
	Ui.button({
		Text = "X",
		Size = UDim2.fromOffset(34, 34),
		Position = UDim2.new(1, -58, 0, 22),
		Parent = window,
	}).Activated
		:Connect(close)
	local function storageCard(x, heading)
		local panel = Ui.make("Frame", {
			Position = UDim2.fromOffset(x, 94),
			Size = UDim2.fromOffset(348, 186),
			BackgroundColor3 = T.Panel,
			Parent = window,
		}, { Ui.corner(3) })
		Ui.stroke(panel)
		Ui.label({
			Text = heading,
			Font = T.FontMono,
			TextColor3 = T.TextDim,
			TextSize = 11,
			Position = UDim2.fromOffset(16, 14),
			Size = UDim2.fromOffset(316, 18),
			Parent = panel,
		})
		local value = Ui.label({
			Font = T.FontBold,
			TextSize = 38,
			Position = UDim2.fromOffset(16, 46),
			Size = UDim2.fromOffset(316, 48),
			Parent = panel,
		})
		local caption = Ui.label({
			TextColor3 = T.TextDim,
			TextSize = 12,
			Position = UDim2.fromOffset(16, 98),
			Size = UDim2.fromOffset(316, 34),
			Parent = panel,
		})
		local track = Ui.make("Frame", {
			BackgroundColor3 = T.Background,
			Position = UDim2.fromOffset(16, 152),
			Size = UDim2.fromOffset(316, 6),
			Parent = panel,
		})
		local fill = Ui.make("Frame", { BackgroundColor3 = T.Accent, Size = UDim2.fromScale(0, 1), Parent = track })
		return { value = value, caption = caption, fill = fill }
	end
	local depot = storageCard(24, "NEARBY DEPOT")
	local vehicle = storageCard(388, "ONBOARD INVENTORY")
	Ui.label({
		Text = "TRANSFER QUANTITY",
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.TextDim,
		Position = UDim2.fromOffset(24, 298),
		Size = UDim2.fromOffset(230, 18),
		Parent = window,
	})
	local status = Ui.label({
		Text = "",
		TextSize = 13,
		TextColor3 = T.TextDim,
		Position = UDim2.fromOffset(24, 408),
		Size = UDim2.new(1, -48, 0, 36),
		Parent = window,
	})
	Ui.label({
		Text = "V / ESC  Close    ·    Load or return supplies at main; transfer both ways at a friendly FOB",
		Font = T.FontMono,
		TextColor3 = T.TextDim,
		TextSize = 10,
		Position = UDim2.fromOffset(24, 454),
		Size = UDim2.new(1, -48, 0, 18),
		Parent = window,
	})
	local load = Ui.button({
		Text = "LOAD INTO VEHICLE  →",
		Font = T.FontBold,
		Size = UDim2.fromOffset(348, 48),
		Position = UDim2.fromOffset(24, 350),
		Parent = window,
	})
	local unload = Ui.button({
		Text = "←  UNLOAD TO DEPOT",
		Font = T.FontBold,
		Size = UDim2.fromOffset(348, 48),
		Position = UDim2.fromOffset(388, 350),
		Parent = window,
	})
	local choices = {}
	local function enabled(button, yes)
		button.Active = yes
		button.Selectable = yes
		button.BackgroundColor3 = if yes then T.Accent else T.PanelLight
		button.TextColor3 = if yes then T.Background else T.TextDim
	end
	local function render()
		if not state then
			return
		end
		title.Text = state.name:upper()
		vehicle.value.Text = tostring(state.cargo)
		vehicle.caption.Text =
			string.format("SUPPLIES  /  %d CAPACITY\n%d free", state.capacity, state.capacity - state.cargo)
		vehicle.fill.Size = UDim2.fromScale(math.clamp(state.cargo / math.max(1, state.capacity), 0, 1), 1)
		depot.value.Text = if state.source == "main"
			then "UNLIMITED"
			elseif state.source then tostring(state.stock)
			else "—"
		depot.caption.Text = state.sourceName
			.. (
				if state.source == "fob"
					then string.format("\n%d / %d supplies", state.stock, state.stockCapacity)
					else ""
			)
		depot.fill.Size = UDim2.fromScale(
			if state.source == "main"
				then 1
				elseif state.source then math.clamp(state.stock / math.max(1, state.stockCapacity), 0, 1)
				else 0,
			1
		)
		enabled(
			load,
			state.source ~= nil and state.cargo < state.capacity and (state.source == "main" or state.stock > 0)
		)
		enabled(
			unload,
			state.source ~= nil and state.cargo > 0 and (state.source == "main" or state.stock < state.stockCapacity)
		)
		for amount, button in choices do
			button.BackgroundColor3 = if amount == quantity then T.Accent else T.PanelLight
			button.TextColor3 = if amount == quantity then T.Background else T.Text
		end
	end
	for i, amount in { 50, 100, 250, 500, "all" } do
		local button = Ui.button({
			Text = if amount == "all" then "ALL" else tostring(amount),
			Font = T.FontBold,
			Size = UDim2.fromOffset(82, 30),
			Position = UDim2.fromOffset(278 + (i - 1) * 88, 291),
			Parent = window,
		})
		choices[amount] = button
		button.Activated:Connect(function()
			quantity = amount
			render()
		end)
	end
	local pending = false
	local function transfer(action, button)
		if state and button.Active and not pending then
			pending = true
			status.Text = "Transferring supplies…"
			remote:FireServer(action, state.model, quantity)
			task.delay(0.3, function()
				pending = false
			end)
		end
	end
	load.Activated:Connect(function()
		transfer("load", load)
	end)
	unload.Activated:Connect(function()
		transfer("unload", unload)
	end)
	Remotes.get("VehicleCargoState").OnClientEvent:Connect(function(snapshot, message, opened)
		if not snapshot then
			gui.Enabled = false
			state = nil
			return
		end
		if not opened and not gui.Enabled then
			return
		end
		state = snapshot
		if opened then
			status.Text = "Select a quantity. Transfers are limited by stock and available space."
		end
		gui.Enabled = true
		if message then
			status.Text = message
		end
		render()
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if
			not processed
			and gui.Enabled
			and not UserInputService:GetFocusedTextBox()
			and (input.KeyCode == Enum.KeyCode.V or input.KeyCode == Enum.KeyCode.Escape)
		then
			close()
		end
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(close)
end

return VehicleCargoUi
