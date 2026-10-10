--!nonstrict
-- Hold Alt to select a world target, then click/hold its actions. Roblox owns the hold/trigger pipeline.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Interaction = require(ReplicatedStorage:WaitForChild("Medical").Interaction)
local InteractionInput = require(script.Parent.InteractionInput)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme
local InteractionUi = {}

function InteractionUi.init()
	local player = Players.LocalPlayer
	local registry: { [ProximityPrompt]: boolean } = {}
	local selected: { [ProximityPrompt]: boolean? } = {}
	local target: Instance? = nil
	ProximityPromptService.Enabled = false
	local gui = Ui.make("ScreenGui", {
		Name = "InteractionUI",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		IgnoreGuiInset = true,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local list = Ui.make("Frame", {
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	}, { Ui.list(6) })
	Ui.fit(list, 340, 180)
	Ui.label({
		Text = "INTERACT  /  RELEASE ALT TO CANCEL",
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.Accent,
		Size = UDim2.fromOffset(340, 20),
		LayoutOrder = 0,
		Parent = list,
	})
	local highlight = Instance.new("Highlight")
	highlight.Name = "InteractionTarget"
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = T.Accent
	highlight.FillTransparency = 0.9
	highlight.OutlineColor = T.Accent
	highlight.Enabled = false
	local highlightFolder = Instance.new("Folder")
	highlightFolder.Name = "InteractionFx"
	highlightFolder.Parent = workspace
	highlight.Parent = highlightFolder
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
		if (state.touching or state.holding) and prompt.Parent then
			prompt:InputHoldEnd()
		end
		for _, c in state.connections do
			c:Disconnect()
		end
		state.card:Destroy()
	end
	local function register(inst: Instance)
		if inst:IsA("ProximityPrompt") then
			registry[inst] = inst:GetAttribute("InteractionEnabled") ~= false and inst.Enabled
			inst.Enabled = false
			Interaction.configure(inst)
		end
	end
	workspace.DescendantAdded:Connect(register)
	workspace.DescendantRemoving:Connect(function(inst)
		if inst:IsA("ProximityPrompt") then
			registry[inst] = nil
			selected[inst] = nil
			hide(inst)
		end
	end)
	for _, inst in workspace:GetDescendants() do
		register(inst)
	end
	local function cancel()
		target = nil
		ProximityPromptService.Enabled = false
		for prompt in registry do
			hide(prompt)
			prompt.Enabled = false
		end
		table.clear(selected)
		list.Visible = false
		highlight.Enabled = false
	end
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt then
			cancel()
		end
	end)
	UserInputService.WindowFocusReleased:Connect(cancel)
	player.CharacterRemoving:Connect(cancel)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		hide(prompt)
		if not InteractionInput.isActive() or not selected[prompt] then
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
		local border = Ui.stroke(card)
		local stripe = Ui.make("Frame", {
			Name = "ActionStripe",
			Size = UDim2.new(0, 3, 1, 0),
			BackgroundColor3 = T.Accent,
			Parent = card,
		})
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
		local state: { [string]: any } = { card = card, connections = {}, touching = false, holding = false }
		visible[prompt] = state
		local function refresh()
			local shortcut = prompt:GetAttribute("InteractionKey")
			local style = prompt:GetAttribute("InteractionStyle")
			local color = if style == "build" then T.Good elseif style == "destructive" then T.Bad else T.Accent
			border.Color, stripe.BackgroundColor3, fill.BackgroundColor3 = color, color, color
			key.TextColor3 = color
			action.TextColor3 = if style then color else T.Text
			key.Text = shortcut or "LMB"
			object.Text = prompt.ObjectText:upper()
			local verb = if prompt.HoldDuration > 0 then "Hold" elseif shortcut then "Press" else "Click"
			action.Text = verb .. " · " .. prompt.ActionText
		end
		local function finish()
			if state.tween then
				state.tween:Cancel()
			end
			state.holding = false
			fill.Size = UDim2.fromOffset(0, 3)
		end
		table.insert(state.connections, prompt.Changed:Connect(refresh))
		table.insert(state.connections, prompt.AttributeChanged:Connect(refresh))
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
				state.holding = true
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
					if not InteractionInput.isActive() or not selected[prompt] or not Interaction.clickable(prompt) then
						return
					end
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
	local function promptPosition(prompt: ProximityPrompt): Vector3?
		local parent = prompt.Parent
		if parent and parent:IsA("Attachment") then
			return parent.WorldPosition
		elseif parent and parent:IsA("BasePart") then
			return parent.Position
		elseif parent and parent:IsA("Model") and parent.PrimaryPart then
			return parent.PrimaryPart.Position
		end
		return nil
	end
	local function available(prompt: ProximityPrompt): boolean
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local position = promptPosition(prompt)
		local enabled = prompt:GetAttribute("InteractionEnabled")
		return (if enabled == nil then registry[prompt] == true else enabled == true)
			and root ~= nil
			and root:IsA("BasePart")
			and position ~= nil
			and (root.Position - position).Magnitude <= prompt.MaxActivationDistance
			and not (character and prompt:IsDescendantOf(character))
	end
	local popupPoint = Vector2.zero
	RunService:BindToRenderStep("HellboundInteractions", Enum.RenderPriority.Last.Value, function()
		local active = InteractionInput.isActive()
		local point = UserInputService:GetMouseLocation()
		local overActions = list.Visible
			and point.X >= list.AbsolutePosition.X - 24
			and point.X <= list.AbsolutePosition.X + list.AbsoluteSize.X + 24
			and point.Y >= list.AbsolutePosition.Y - 24
			and point.Y <= list.AbsolutePosition.Y + list.AbsoluteSize.Y + 24
		local previousTarget = target
		if target and not target:IsDescendantOf(workspace) then
			target = nil
		end
		local holding = false
		for _, state in visible do
			holding = holding or state.touching or state.holding
		end
		if not active then
			target = nil
		elseif not target or not (overActions or holding) then
			target = nil
			local hit = InteractionInput.cast(80)
			if hit then
				local ancestor: Instance? = hit.Instance
				while ancestor and ancestor ~= workspace do
					for prompt in registry do
						local link = prompt:FindFirstChild("InteractionTarget")
						local owner = if link and link:IsA("ObjectValue")
							then link.Value
							else Interaction.target(prompt.Parent, false)
						if owner == ancestor and available(prompt) then
							target = owner
							break
						end
					end
					if target then
						break
					end
					ancestor = ancestor.Parent
				end
			end
		end
		if target ~= previousTarget or not target then
			popupPoint = point
		end
		for prompt in registry do
			Interaction.configure(prompt)
			local link = prompt:FindFirstChild("InteractionTarget")
			local owner = if link and link:IsA("ObjectValue")
				then link.Value
				else Interaction.target(prompt.Parent, false)
			local enabled = (active and owner == target and target ~= nil and available(prompt)) == true
			selected[prompt] = if enabled then true else nil
			if prompt.Enabled ~= enabled then
				if not enabled then
					hide(prompt)
				end
				prompt.Enabled = enabled
			end
		end
		ProximityPromptService.Enabled = active
		list.Visible = next(visible) ~= nil and active
		highlight.Adornee = if target and (target:IsA("Model") or target:IsA("BasePart")) then target else nil
		highlight.Enabled = active and highlight.Adornee ~= nil and next(selected) ~= nil
		if active then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			local prompts = {}
			for prompt in visible do
				table.insert(prompts, prompt)
			end
			for _, prompt in prompts do
				hide(prompt)
			end
		end
		local size = list.AbsoluteSize
		local viewport = gui.AbsoluteSize
		list.Position = UDim2.fromOffset(
			math.clamp(popupPoint.X + 18, 8, math.max(8, viewport.X - size.X - 8)),
			math.clamp(popupPoint.Y + 18, 8, math.max(8, viewport.Y - size.Y - 8))
		)
	end)
end

return InteractionUi
