--!nonstrict
-- Minimap (top right), fullscreen map (M), compass (top centre) and pings. North is -Z.
-- Ping: T at the cursor, or left click on the fullscreen map; right click on the map clears yours.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local GameConfig = require(Medical.GameMode.Config)
local Remotes = require(Medical.Remotes)
local Ui = require(script.Parent.Ui)
local InteractionInput = require(script.Parent.InteractionInput)
local T = Ui.Theme

local MapHud = {}

local cfg = GameConfig.Map
local player = Players.LocalPlayer
local pingRemote
local pings = {}
local mapOpen = false
local mini, miniPool, miniLines, big, bigCanvas, bigPool, bigLines, compass, compassPool, bearingLabel
local billboards: { [number]: any } = {}
local bounds = { minX = -300, minZ = -300, maxX = 300, maxZ = 300 }
local spawns: { SpawnLocation } = {}

local PING_COLOR = Color3.fromRGB(255, 70, 60)
local SQUAD_COLOR = Color3.fromRGB(110, 230, 120)
local FRIEND_COLOR = Color3.fromRGB(90, 160, 255)
local NEUTRAL = Color3.fromRGB(170, 170, 170)

-- Pools of reused GUI objects --------------------------------------------------------------------------
local function pool(parent: Instance, className: string)
	return { parent = parent, className = className, items = {}, used = 0 }
end
local function begin(p)
	p.used = 0
end
local function finish(p)
	for i = p.used + 1, #p.items do
		p.items[i].Visible = false
	end
end
local function take(p)
	p.used += 1
	local m = p.items[p.used]
	if not m then
		m = Instance.new(p.className)
		m.BorderSizePixel = 0
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		if m:IsA("TextLabel") then
			m.Font = T.FontBold
			m.TextStrokeTransparency = 0.3
		end
		m.Parent = p.parent
		p.items[p.used] = m
	end
	m.Visible = true
	m.Rotation = 0
	return m
end

local function label(p, x: number, y: number, text: string, color: Color3, size: number, bg: Color3?)
	local m = take(p)
	m.Position = UDim2.fromOffset(x, y)
	m.Size = UDim2.fromOffset(size + 6, size + 4)
	m.Text = text
	m.TextSize = size
	m.TextColor3 = color
	m.BackgroundColor3 = bg or Color3.new()
	m.BackgroundTransparency = if bg then 0.15 else 1
	return m
end

local function line(p, x: number, y: number, w: number, h: number)
	local f = take(p)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 0.88
	return f
end

-- Helpers ----------------------------------------------------------------------------------------------
local function rootOf(plr: Player): BasePart?
	local char = plr.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function bearingOf(look: Vector3): number
	return (math.deg(math.atan2(look.X, -look.Z)) + 360) % 360
end

function MapHud.gridRef(pos: Vector3): string
	local col = math.floor((pos.X - bounds.minX) / cfg.Grid)
	local row = math.floor((pos.Z - bounds.minZ) / cfg.Grid) + 1
	local letter = if col >= 0 and col < 26 then string.char(65 + col) else "?"
	return letter .. tostring(math.max(row, 0))
end

local function objectives(): { BasePart }
	local found = {}
	for _, item in CollectionService:GetTagged("Objective") do
		if item:IsA("BasePart") and item:IsDescendantOf(workspace) then
			table.insert(found, item)
		end
	end
	table.sort(found, function(a, b)
		return (tonumber(a:GetAttribute("Order")) or math.huge) < (tonumber(b:GetAttribute("Order")) or math.huge)
	end)
	return found
end

local function refreshBounds()
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	local function addPoint(p: Vector3)
		minX, minZ = math.min(minX, p.X), math.min(minZ, p.Z)
		maxX, maxZ = math.max(maxX, p.X), math.max(maxZ, p.Z)
	end
	for _, zone in objectives() do
		addPoint(zone.Position)
	end
	spawns = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and d.Enabled and not d.Neutral then
			table.insert(spawns, d)
			addPoint(d.Position)
		end
	end
	if minX == math.huge then
		local root = rootOf(player)
		addPoint(if root then root.Position else Vector3.zero)
	end
	local m = cfg.Margin
	-- square, snapped to the grid so grid references stay put
	local size = math.max(maxX - minX, maxZ - minZ) + m * 2
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local g = cfg.Grid
	bounds.minX = math.floor((cx - size / 2) / g) * g
	bounds.minZ = math.floor((cz - size / 2) / g) * g
	local cells = math.ceil(size / g) + 1
	bounds.maxX = bounds.minX + cells * g
	bounds.maxZ = bounds.minZ + cells * g
end

-- Draws the map for the world square [x0, x0 + span] x [z0, z0 + span] into a canvas of `px` pixels.
local function draw(p, lines, x0: number, z0: number, span: number, px: number, full: boolean)
	begin(p)
	begin(lines)
	local k = px / span
	local function at(pos: Vector3): (number, number, boolean)
		local x, y = (pos.X - x0) * k, (pos.Z - z0) * k
		return x, y, x >= -4 and y >= -4 and x <= px + 4 and y <= px + 4
	end
	-- grid
	local g = cfg.Grid
	local gx = math.ceil(x0 / g) * g
	while gx <= x0 + span do
		line(lines, (gx - x0) * k, px / 2, 1, px)
		gx += g
	end
	local gz = math.ceil(z0 / g) * g
	while gz <= z0 + span do
		line(lines, px / 2, (gz - z0) * k, px, 1)
		gz += g
	end
	if full then
		for col = 0, math.floor((bounds.maxX - bounds.minX) / g) - 1 do
			local cx = (bounds.minX + (col + 0.5) * g - x0) * k
			label(p, cx, 10, string.char(65 + math.min(col, 25)), T.TextDim, 14)
		end
		for row = 0, math.floor((bounds.maxZ - bounds.minZ) / g) - 1 do
			local cy = (bounds.minZ + (row + 0.5) * g - z0) * k
			label(p, 10, cy, tostring(row + 1), T.TextDim, 14)
		end
	end
	-- bases
	for _, sp in spawns do
		if sp.Parent then
			local x, y, inside = at(sp.Position)
			if inside then
				label(
					p,
					x,
					y,
					if full then "MAIN" else "M",
					Color3.new(1, 1, 1),
					if full then 12 else 10,
					sp.TeamColor.Color
				)
			end
		end
	end
	-- objectives
	for i, zone in objectives() do
		local x, y, inside = at(zone.Position)
		if inside then
			local owner = workspace:GetAttribute("Obj" .. i .. "Owner")
			local side = owner and GameConfig.Sides[owner]
			label(
				p,
				x,
				y,
				tostring(i),
				Color3.new(1, 1, 1),
				if full then 18 else 13,
				if side then side.color else NEUTRAL
			)
		end
	end
	-- friendlies
	local mySquad = player:GetAttribute("SquadId") or 0
	for _, other in Players:GetPlayers() do
		local root = rootOf(other)
		if root and other ~= player and player.Team and other.Team == player.Team then
			local x, y, inside = at(root.Position)
			if inside then
				local squadmate = mySquad ~= 0 and other:GetAttribute("SquadId") == mySquad
				local m =
					label(p, x, y, "●", if squadmate then SQUAD_COLOR else FRIEND_COLOR, if full then 14 else 11)
				if full then
					m.Text = "● " .. other.DisplayName
					m.Size = UDim2.fromOffset(160, 18)
					m.TextXAlignment = Enum.TextXAlignment.Center
				end
			end
		end
	end
	-- FOBs and HABs
	local mySide = player.Team and player.Team:GetAttribute("Side")
	for _, tag in { "FOB", "HAB" } do
		for _, part in CollectionService:GetTagged(tag) do
			if part:IsA("BasePart") and part:GetAttribute("Side") == mySide then
				local x, y, inside = at(part.Position)
				if inside then
					local chosen = tag == "HAB" and player:GetAttribute("SpawnAt") == part:GetAttribute("HabId")
					local bg = if tag == "HAB" then Color3.fromRGB(40, 90, 140) else Color3.fromRGB(60, 110, 60)
					local m = label(p, x, y, tag .. (if chosen then " *" else ""), Color3.new(1, 1, 1), 11, bg)
					m.Size = UDim2.fromOffset(if chosen then 44 else 34, 16)
				end
			end
		end
	end
	-- pings
	for _, ping in pings do
		local x, y, inside = at(ping.pos)
		if inside then
			label(p, x, y, "◆", PING_COLOR, if full then 20 else 14)
		end
	end
	-- you
	local root = rootOf(player)
	if root then
		local x, y = at(root.Position)
		local m = label(p, x, y, "▲", Color3.new(1, 1, 0.3), if full then 18 else 14)
		m.Rotation = bearingOf(workspace.CurrentCamera.CFrame.LookVector)
	end
	finish(p)
	finish(lines)
end

-- Compass --------------------------------------------------------------------------------------------
local NAMES = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
local COMPASS_W, PX_PER_DEG = 420, 3

local function drawCompass(bearing: number)
	begin(compassPool)
	for deg = 0, 355, 15 do
		local d = ((deg - bearing + 540) % 360) - 180
		if math.abs(d) * PX_PER_DEG < COMPASS_W / 2 then
			local x = COMPASS_W / 2 + d * PX_PER_DEG
			local name = NAMES[deg]
			label(
				compassPool,
				x,
				12,
				name or tostring(deg),
				if name then T.Text else T.TextDim,
				if name then 15 else 11
			)
		end
	end
	local root = rootOf(player)
	if root then
		for _, ping in pings do
			local offset = ping.pos - root.Position
			if Vector2.new(offset.X, offset.Z).Magnitude > 1 then
				local d = ((bearingOf(offset) - bearing + 540) % 360) - 180
				if math.abs(d) * PX_PER_DEG < COMPASS_W / 2 then
					label(compassPool, COMPASS_W / 2 + d * PX_PER_DEG, 30, "◆", PING_COLOR, 12)
				end
			end
		end
	end
	finish(compassPool)
	local ref = if root then "   " .. MapHud.gridRef(root.Position) else ""
	bearingLabel.Text = string.format("%03d°%s", math.floor(bearing + 0.5) % 360, ref)
end

-- World markers ----------------------------------------------------------------------------------------
local function syncBillboards()
	local seen = {}
	for _, ping in pings do
		seen[ping.id] = true
		local b = billboards[ping.id]
		if not b then
			local att = Instance.new("Attachment")
			att.WorldPosition = ping.pos
			att.Parent = workspace.Terrain
			local gui = Instance.new("BillboardGui")
			gui.AlwaysOnTop = true
			gui.Size = UDim2.fromOffset(120, 46)
			gui.LightInfluence = 0
			gui.Adornee = att
			gui.Parent = att
			local icon = Ui.label({
				Text = "◆",
				Font = T.FontBold,
				TextSize = 22,
				TextColor3 = PING_COLOR,
				TextStrokeTransparency = 0.3,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 24),
				Parent = gui,
			})
			local text = Ui.label({
				Text = "",
				TextSize = 12,
				TextStrokeTransparency = 0.3,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 24),
				Size = UDim2.new(1, 0, 0, 18),
				Parent = gui,
			})
			b = { att = att, icon = icon, text = text, ping = ping }
			billboards[ping.id] = b
		end
		b.ping = ping
	end
	for id, b in billboards do
		if not seen[id] then
			b.att:Destroy()
			billboards[id] = nil
		end
	end
end

local function updateBillboards()
	local root = rootOf(player)
	for _, b in billboards do
		local dist = if root then (b.ping.pos - root.Position).Magnitude else 0
		b.text.Text = string.format("%s  %dm", b.ping.author or "", math.floor(dist * 0.28 + 0.5))
	end
end

-- Input ------------------------------------------------------------------------------------------------
local function groundAt(x: number, z: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return if hit then hit.Position else Vector3.new(x, 0, z)
end

local function pingAtCursor()
	if Ui.isModalOpen() or UserInputService:GetFocusedTextBox() then
		return
	end
	local hit = InteractionInput.cast(1500)
	if hit then
		pingRemote:FireServer("enemy", hit.Position)
	end
end

function MapHud.isOpen(): boolean
	return mapOpen
end

function MapHud.setOpen(value: boolean)
	mapOpen = value
	big.Visible = value
	mini.Visible = not value
	if value then
		refreshBounds()
	end
end

-- Build ------------------------------------------------------------------------------------------------
function MapHud.init(screen: ScreenGui)
	pingRemote = Remotes.get("Ping")
	Remotes.get("PingState").OnClientEvent:Connect(function(list)
		pings = list or {}
		syncBillboards()
	end)

	mini = Ui.make("Frame", {
		Name = "Minimap",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 48),
		Size = UDim2.fromOffset(cfg.MiniSize, cfg.MiniSize),
		BackgroundColor3 = Color3.fromRGB(30, 38, 30),
		BackgroundTransparency = 0.25,
		ClipsDescendants = true,
		Parent = screen,
	}, { Ui.corner(6), Ui.make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.3 }) })
	miniLines = pool(mini, "Frame")
	miniPool = pool(mini, "TextLabel")

	big = Ui.make("Frame", {
		Name = "Map",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Visible = false,
		Parent = screen,
	})
	Ui.modal(big)
	bigCanvas = Ui.make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(32, 42, 32),
		ClipsDescendants = true,
		Parent = big,
	}, { Ui.corner(6) })
	bigLines = pool(bigCanvas, "Frame")
	bigPool = pool(bigCanvas, "TextLabel")
	Ui.label({
		Text = "MAP  -  left click: ping (click a HAB to spawn there)   right click: clear your pings   M: close",
		Font = T.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = big,
	})
	local function worldFromClick(input: InputObject): Vector3
		local rel = Vector2.new(input.Position.X, input.Position.Y) - bigCanvas.AbsolutePosition
		local span = bounds.maxX - bounds.minX
		local k = span / bigCanvas.AbsoluteSize.X
		return groundAt(bounds.minX + rel.X * k, bounds.minZ + rel.Y * k)
	end
	bigCanvas.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local rel = Vector2.new(input.Position.X, input.Position.Y) - bigCanvas.AbsolutePosition
			local k = (bounds.maxX - bounds.minX) / bigCanvas.AbsoluteSize.X
			local wx, wz = bounds.minX + rel.X * k, bounds.minZ + rel.Y * k
			local mySide = player.Team and player.Team:GetAttribute("Side")
			for _, hab in CollectionService:GetTagged("HAB") do
				if hab:IsA("BasePart") and hab:GetAttribute("Side") == mySide then
					if Vector2.new(hab.Position.X - wx, hab.Position.Z - wz).Magnitude <= 16 * k then
						local id = hab:GetAttribute("HabId")
						Remotes.get("Build")
							:FireServer("spawnAt", if player:GetAttribute("SpawnAt") == id then nil else id)
						return
					end
				end
			end
			pingRemote:FireServer("enemy", worldFromClick(input))
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			pingRemote:FireServer("clear")
		end
	end)

	compass = Ui.make("Frame", {
		Name = "Compass",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 86),
		Size = UDim2.fromOffset(COMPASS_W, 40),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		ClipsDescendants = true,
		Parent = screen,
	}, { Ui.corner(4) })
	Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(2, 6),
		BackgroundColor3 = Color3.new(1, 1, 0.3),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = compass,
	})
	compassPool = pool(compass, "TextLabel")
	bearingLabel = Ui.label({
		Text = "",
		Font = T.FontBold,
		TextSize = 13,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(160, 18),
		Parent = screen,
	})

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == cfg.Key and player.Character then
			MapHud.setOpen(not mapOpen)
		elseif input.KeyCode == cfg.PingKey and player.Character then
			pingAtCursor()
		elseif input.KeyCode == Enum.KeyCode.Escape and mapOpen then
			MapHud.setOpen(false)
		end
	end)
	player.CharacterRemoving:Connect(function()
		MapHud.setOpen(false)
	end)

	task.spawn(function()
		while true do
			refreshBounds()
			task.wait(5)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local hasChar = rootOf(player) ~= nil and player.Team ~= nil and player.Team:GetAttribute("Side") ~= nil
		mini.Visible = hasChar and not mapOpen
		compass.Visible = hasChar
		bearingLabel.Visible = hasChar
		if not hasChar then
			return
		end
		local bearing = bearingOf(workspace.CurrentCamera.CFrame.LookVector)
		drawCompass(bearing)
		updateBillboards()
		if mapOpen then
			local px = math.min(screen.AbsoluteSize.X, screen.AbsoluteSize.Y) - 80
			bigCanvas.Size = UDim2.fromOffset(px, px)
			draw(bigPool, bigLines, bounds.minX, bounds.minZ, bounds.maxX - bounds.minX, px, true)
		else
			local root = rootOf(player) :: BasePart
			local span = cfg.MiniStuds
			draw(miniPool, miniLines, root.Position.X - span / 2, root.Position.Z - span / 2, span, cfg.MiniSize, false)
		end
	end)
end

return MapHud
