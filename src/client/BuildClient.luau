--!nonstrict
-- Build menu (B, Squad Commanders and the Commander): pick a structure, move the ghost with the mouse, R rotates,
-- left click places, right click / Escape cancels. The menu and the ghost run the server's placement rules
-- (Logistics.canPlace) against replicated FOB stock, so a supply shortage is shown before anything is placed.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local UserInputService = game:GetService("UserInputService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Logistics.Config)
local Logistics = require(Medical.Logistics.Logistics)
local Remotes = require(Medical.Remotes)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

local BuildClient = {}

local player = Players.LocalPlayer
local menu, fobLabel, menuStatus, ghostStatus
local buttons: { [string]: TextButton } = {}
local spawns: { SpawnLocation } = {}
local ghost: Part? = nil
local ghostKind: string? = nil
local ghostOk = false
local yaw = 0

local function isLeader(): boolean
	return Logistics.LEADERS[player:GetAttribute("Class") or ""] == true
end

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function mySide()
	return player.Team and player.Team:GetAttribute("Side")
end

-- The friendly FOB whose radius contains pos (lowest id first, like the server).
local function fobAt(pos: Vector3): BasePart?
	local side = mySide()
	local best, bestId = nil, math.huge
	for _, fob in CollectionService:GetTagged("FOB") do
		if fob:IsA("BasePart") and fob:GetAttribute("Side") == side and flat(fob.Position, pos) <= Config.FobRadius then
			local id = fob:GetAttribute("FobId") or math.huge
			if best == nil or id < bestId then
				best, bestId = fob, id
			end
		end
	end
	return best
end

local function fobContext(fob: BasePart?): Logistics.FobContext?
	return if fob then { stock = fob:GetAttribute("Stock") or 0, habs = fob:GetAttribute("Habs") or 0 } else nil
end

local function mainDistance(pos: Vector3): number
	local d = math.huge
	for _, pad in CollectionService:GetTagged("VehiclePad") do
		if pad:IsA("BasePart") then
			d = math.min(d, flat(pad.Position, pos))
		end
	end
	for _, team in Teams:GetTeams() do
		if team:GetAttribute("Side") then
			for _, spawn in spawns do
				if spawn.Parent and not spawn.Neutral and spawn.TeamColor == team.TeamColor then
					d = math.min(d, flat(spawn.Position, pos))
				end
			end
		end
	end
	return d
end

local function evaluate(kind: string, cf: CFrame): (boolean, string?, BasePart?)
	local def = Config.Structures[kind]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "No character", nil
	end
	local pos = cf.Position
	local blocked = false
	local structures = workspace:FindFirstChild("Structures")
	if structures then
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = { structures }
		blocked = #workspace:GetPartBoundsInBox(cf * CFrame.new(0, def.size.Y / 2, 0), def.size, overlap) > 0
	end
	local fobDistance = math.huge
	for _, fob in CollectionService:GetTagged("FOB") do
		if fob:IsA("BasePart") then
			fobDistance = math.min(fobDistance, flat(fob.Position, pos))
		end
	end
	local fob = fobAt(pos)
	local ok, why = Logistics.canPlace(kind, def, {
		class = player:GetAttribute("Class") or "Rifleman",
		distance = (root.Position - pos).Magnitude,
		fob = fobContext(fob),
		mainDistance = mainDistance(pos),
		fobDistance = fobDistance,
		blocked = blocked,
	}, Config)
	return ok, why, fob
end

local function cancel()
	if ghost then
		ghost:Destroy()
	end
	ghost, ghostKind, ghostOk = nil, nil, false
	ghostStatus.Visible = false
end

local function startGhost(kind: string)
	cancel()
	local def = Config.Structures[kind]
	local p = Instance.new("Part")
	p.Name = "ConstructionPreview"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = def.size
	p.Color = T.Bad
	p.Transparency = 1
	p.Material = Enum.Material.ForceField
	p.Parent = workspace.CurrentCamera
	ghost, ghostKind = p, kind
	ghostStatus.Visible = true
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

local function updateGhost()
	local part, kind = ghost, ghostKind
	if not part or not kind then
		return
	end
	local def = Config.Structures[kind]
	local cf = ghostCFrame()
	local ok, why, fob = false, "Aim at the ground within " .. Config.PlaceRange .. " studs", nil
	if cf then
		ok, why, fob = evaluate(kind, cf)
		part.CFrame = cf * CFrame.new(0, part.Size.Y / 2, 0)
	end
	ghostOk = ok
	part.Transparency = if cf then 0.5 else 1
	part.Color = if ok then T.Good else T.Bad
	ghostStatus.TextColor3 = part.Color
	local detail
	if not ok then
		detail = why or "Can't place that here"
	elseif def.cost == 0 then
		detail = "Free"
	else
		detail = string.format(
			"Costs %d supplies · FOB has %d",
			def.cost,
			if fob then fob:GetAttribute("Stock") or 0 else 0
		)
	end
	ghostStatus.Text = string.format(
		"%s  ·  %s\n%s\nLMB place   R rotate   RMB cancel",
		def.name:upper(),
		if ok then "READY TO PLACE" else "CAN'T PLACE",
		detail
	)
end

local function updateMenu(fob: BasePart?)
	local context = fobContext(fob)
	menuStatus.Text = if context
		then string.format("FOB SUPPLIES  %d / %d", context.stock, Config.FobMaxStock)
		else "NO FRIENDLY FOB HERE  ·  ONLY A FOB RADIO CAN BE PLACED"
	menuStatus.TextColor3 = if context then T.Warn else T.TextDim
	for kind, button in buttons do
		local def = Config.Structures[kind]
		local available, why = Logistics.available(kind, def, context)
		local cost = if def.cost > 0 then def.cost .. " supplies" else "free"
		local text =
			string.format("%s  ·  %s\n%s", def.name, cost, if available then "AVAILABLE" else why or "Unavailable")
		if button.Text ~= text then
			button.Text = text
		end
		button.TextColor3 = if available then T.Text else T.Bad
		button.BackgroundColor3 = if available then T.PanelLight else T.Panel
		button.AutoButtonColor = available
		button:SetAttribute("Available", available)
	end
end

function BuildClient.init(screen: ScreenGui)
	local remote = Remotes.get("Build")
	for _, inst in workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") then
			table.insert(spawns, inst)
		end
	end
	workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("SpawnLocation") then
			table.insert(spawns, inst)
		end
	end)
	menu = Ui.make("Frame", {
		Name = "BuildMenu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(270, 0),
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
	Ui.stroke(menu)
	Ui.fit(menu, 310, 560)
	Ui.modal(menu)
	Ui.label({
		Text = "CONSTRUCTION  /  B",
		Font = T.FontBold,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 0,
		Parent = menu,
	})
	menuStatus = Ui.label({
		Name = "FobStock",
		Text = "",
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.Warn,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
		Parent = menu,
	})
	for kind, def in Config.Structures do
		local button = Ui.button({
			Name = kind,
			Text = "",
			Font = T.Font,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = T.Text,
			BackgroundColor3 = T.PanelLight,
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = def.order + 1,
			Parent = menu,
		})
		Ui.padding(6).Parent = button
		buttons[kind] = button
		button.MouseButton1Click:Connect(function()
			if button:GetAttribute("Available") then
				startGhost(kind)
			end
		end)
	end
	Ui.label({
		Text = "Red entries can't be placed from this FOB. Supplies are paid when the blueprint is placed; anyone with a Hammer can then build it.",
		TextSize = 11,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 100,
		Parent = menu,
	})
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
	ghostStatus = Ui.label({
		Name = "ConstructionStatus",
		Text = "",
		Visible = false,
		Font = T.FontBold,
		TextSize = 13,
		TextStrokeTransparency = 0.4,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 284),
		Size = UDim2.fromOffset(320, 60),
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
			updateGhost()
			if ghostOk then
				remote:FireServer("place", ghostKind, ghostCFrame())
				cancel()
			end
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
			updateGhost()
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local fob = if root then fobAt(root.Position) else nil
		fobLabel.Text = if fob then string.format("FOB  supplies %d", fob:GetAttribute("Stock") or 0) else ""
		if menu.Visible then
			updateMenu(fob)
		end
	end)
end

return BuildClient
