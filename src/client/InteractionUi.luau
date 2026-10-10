--!nonstrict
-- Roblox handles proximity, keyboard and gamepad input; only the presentation is custom.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Ui = require(script.Parent.Ui)
local T = Ui.Theme
local InteractionUi = {}

function InteractionUi.init()
	local player = Players.LocalPlayer
	local function hideSelfPrompt(inst: Instance)
		if inst:IsA("ProximityPrompt") and inst:GetAttribute("MedicalOwner") == player.UserId then
			inst.Enabled = false
		end
	end
	workspace.DescendantAdded:Connect(hideSelfPrompt)
	for _, inst in workspace:GetDescendants() do
		hideSelfPrompt(inst)
	end
	local gui = Ui.make("ScreenGui", {
		Name = "InteractionUI",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local list = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -160),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(6) })
	Ui.fit(list, 340, 180)
	local visible = {}
	local order = 0
	local function hide(prompt)
		local state = visible[prompt]
		if not state then
			return
		end
		visible[prompt] = nil
		if state.tween then
			state.tween:Cancel()
		end
		if state.touching and prompt.Parent then
			prompt:InputHoldEnd()
		end
		for _, c in state.connections do
			c:Disconnect()
		end
		state.card:Destroy()
	end
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType)
		hide(prompt)
		if Ui.isModalOpen() then
			return
		end
		order += 1
		local card = Ui.make("TextButton", {
			Name = "InteractionCard",
			Text = "",
			Size = UDim2.fromOffset(340, 68),
			BackgroundColor3 = T.Background,
			LayoutOrder = order,
			Parent = list,
		}, { Ui.corner(3) })
		Ui.stroke(card)
		local key = Ui.label({
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(44, 42),
			BackgroundTransparency = 0,
			BackgroundColor3 = T.PanelLight,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = T.FontBold,
			TextSize = 18,
			TextColor3 = T.Accent,
			Parent = card,
		})
		local object = Ui.label({
			Position = UDim2.fromOffset(68, 10),
			Size = UDim2.new(1, -80, 0, 16),
			TextColor3 = T.TextDim,
			TextSize = 11,
			Font = T.FontMono,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = card,
		})
		local action = Ui.label({
			Position = UDim2.fromOffset(68, 29),
			Size = UDim2.new(1, -80, 0, 22),
			TextSize = 14,
			Font = T.FontBold,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			Parent = card,
		})
		local fill = Ui.make("Frame", {
			Position = UDim2.new(0, 0, 1, -3),
			Size = UDim2.fromOffset(0, 3),
			BackgroundColor3 = T.Accent,
			Parent = card,
		})
		local state: { [string]: any } = { card = card, connections = {}, touching = false }
		visible[prompt] = state
		local function refresh()
			key.Text = if inputType == Enum.ProximityPromptInputType.Touch
				then "TAP"
				elseif inputType == Enum.ProximityPromptInputType.Gamepad then prompt.GamepadKeyCode.Name:gsub(
					"Button",
					""
				)
				else UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
			object.Text = prompt.ObjectText:upper()
			action.Text = (if prompt.HoldDuration > 0 then "Hold · " else "") .. prompt.ActionText
		end
		local function finish()
			if state.tween then
				state.tween:Cancel()
			end
			fill.Size = UDim2.fromOffset(0, 3)
		end
		table.insert(state.connections, prompt.Changed:Connect(refresh))
		table.insert(
			state.connections,
			prompt.Destroying:Connect(function()
				hide(prompt)
			end)
		)
		table.insert(
			state.connections,
			prompt.PromptButtonHoldBegan:Connect(function()
				finish()
				state.tween = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), {
					Size = UDim2.new(1, 0, 0, 3),
				})
				state.tween:Play()
			end)
		)
		table.insert(state.connections, prompt.PromptButtonHoldEnded:Connect(finish))
		table.insert(state.connections, prompt.Triggered:Connect(finish))
		table.insert(
			state.connections,
			card.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1
				then
					state.touching = true
					prompt:InputHoldBegin()
				end
			end)
		)
		table.insert(
			state.connections,
			UserInputService.InputEnded:Connect(function(input)
				if
					state.touching
					and (
						input.UserInputType == Enum.UserInputType.Touch
						or input.UserInputType == Enum.UserInputType.MouseButton1
					)
				then
					state.touching = false
					prompt:InputHoldEnd()
				end
			end)
		)
		refresh()
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	RunService.RenderStepped:Connect(function()
		local char = player.Character
		local enabled = not Ui.isModalOpen()
			and UserInputService:GetFocusedTextBox() == nil
			and char ~= nil
			and char:GetAttribute("MedConscious") ~= false
			and char:GetAttribute("MedAlive") ~= false
		if ProximityPromptService.Enabled ~= enabled then
			ProximityPromptService.Enabled = enabled
		end
		if not enabled then
			local prompts = {}
			for prompt in visible do
				table.insert(prompts, prompt)
			end
			for _, prompt in prompts do
				hide(prompt)
			end
		end
	end)
end

return InteractionUi
