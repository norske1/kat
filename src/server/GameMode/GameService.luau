--!nonstrict
-- Squad-style game mode: two sides with tickets and a lane of objectives captured in order (see GameMode.Config).
-- State is replicated through attributes so late joiners and the HUD need no remote:
--   Team: Side ("A"/"B"), Tickets
--   workspace: GameObjectives (count), Obj<i>Owner ("A"/"B"/""), Obj<i>Progress (-100..100), Obj<i>A / Obj<i>B
--              (living players inside), GameWinner ("A"/"B"/""), GameResetAt (server time of the next round)
--   Player: InObjective (index of the zone the player stands in, 0 if none)
--   workspace: LobbyFocus (Vector3 the main menu camera circles)
-- Players join on the Lobby team without a character, pick a side from the client's team select menu (JoinTeam
-- remote, limited by GameConfig.MaxTeamGap) and are respawned by this service after dying.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local CharacterLook = require(script.Parent.Parent.CharacterLook)
local GameConfig = require(Medical.GameMode.Config)
local Rules = require(Medical.GameMode.Rules)
local MedicalService = require(script.Parent.Parent.MedicalService)
local Remotes = require(Medical.Remotes)
local CareerService = require(script.Parent.Parent.CareerService)
local SquadService = require(script.Parent.SquadService)

local GameService = {}
GameService.onNewRound = nil :: (() -> ())?

local state: Rules.State = Rules.new(0, GameConfig.StartTickets)
local zones: { BasePart } = {}
local visuals = {} -- [i] = { flag, ring, label, base, height }
local teams: { [string]: Team } = {}
local lobby: Team
local roundOver = false
local counted: { [Model]: boolean } = {} -- characters whose death already cost a ticket

local NEUTRAL = Color3.fromRGB(235, 235, 235)

local function sideColor(side: string?): Color3
	return if side then GameConfig.Sides[side].color else NEUTRAL
end

local function sideName(side: string): string
	return GameConfig.Sides[side].name
end

local function broadcast(text: string, kind: string?)
	for _, player in Players:GetPlayers() do
		MedicalService.notify(player, text, kind)
	end
end

function GameService.sideOf(player: Player): string?
	local team = player.Team
	return if team then team:GetAttribute("Side") else nil
end

-- Teams ------------------------------------------------------------------------
local function setupTeams()
	for key, side in GameConfig.Sides do
		local team
		for _, existing in Teams:GetTeams() do
			if existing:GetAttribute("Side") == key or existing.Name == side.name then
				team = existing
			end
		end
		if not team then
			team = Instance.new("Team")
			team.Name = side.name
			team.Parent = Teams
		end
		team.TeamColor = BrickColor.new(side.color)
		team.AutoAssignable = false
		team:SetAttribute("Side", key)
		teams[key] = team
	end
	local existing = Teams:FindFirstChild(GameConfig.Lobby.name)
	lobby = if existing and existing:IsA("Team") then existing else Instance.new("Team")
	lobby.Name = GameConfig.Lobby.name
	lobby.TeamColor = BrickColor.new(GameConfig.Lobby.color)
	lobby.AutoAssignable = true
	lobby:SetAttribute("Side", nil)
	lobby.Parent = Teams
end

-- Players on `side` and on the other side, not counting `player`.
local function countsFor(side: string, player: Player): (number, number)
	local joining, other = 0, 0
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local s = GameService.sideOf(p)
			if s == side then
				joining += 1
			elseif s == Rules.other(side) then
				other += 1
			end
		end
	end
	return joining, other
end

-- Map --------------------------------------------------------------------------
local function ground(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(position + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), params)
	return if hit then hit.Position else Vector3.new(position.X, 0, position.Z)
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	return p
end

local function buildBase(folder: Instance, key: string, floor: Vector3, facing: Vector3)
	local base = CFrame.lookAt(floor, Vector3.new(facing.X, floor.Y, facing.Z))
	local model = Instance.new("Model")
	model.Name = sideName(key) .. " Main"
	model.Parent = folder
	part({
		Name = "Pad",
		Size = Vector3.new(36, 0.2, 36),
		CFrame = base * CFrame.new(0, 0.1, 0),
		Color = sideColor(key),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.6,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "Spawn"
	spawnLocation.Anchored = true
	spawnLocation.Size = Vector3.new(10, 1, 10)
	spawnLocation.CFrame = base * CFrame.new(0, 0.5, 0)
	spawnLocation.Neutral = false
	spawnLocation.TeamColor = teams[key].TeamColor
	spawnLocation.BrickColor = teams[key].TeamColor
	spawnLocation.AllowTeamChangeOnTouch = false
	spawnLocation.Duration = 3
	spawnLocation.Parent = model
	-- weapon locker (built by Weapons.Locker) on the left, medical crate on the right, both facing the spawn
	local lockerPos = (base * CFrame.new(-12, 0.5, 4)).Position
	local locker = part({
		Name = "WeaponLocker",
		Size = Vector3.new(4, 1, 1),
		CFrame = CFrame.lookAt(lockerPos, Vector3.new(floor.X, lockerPos.Y, floor.Z)),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	CollectionService:AddTag(locker, "WeaponLocker")
	local crate = part({
		Name = "MedicalSupplies",
		Size = Vector3.new(4, 3, 3),
		CFrame = base * CFrame.new(12, 1.5, 4),
		Color = Color3.fromRGB(85, 95, 60),
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	CollectionService:AddTag(crate, "MedicalSupply")
	local vehiclePad = part({
		Name = "VehiclePad",
		Size = Vector3.new(26, 0.2, 30),
		CFrame = base * CFrame.new(48, 0.1, 0),
		Color = Color3.fromRGB(70, 72, 76),
		Material = Enum.Material.Concrete,
		Parent = model,
	})
	vehiclePad:SetAttribute("Side", key)
	CollectionService:AddTag(vehiclePad, "VehiclePad")
end

local function buildMap()
	local folder = Instance.new("Folder")
	folder.Name = "GameModeMap"
	folder.Parent = workspace
	local spawnPart = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local center = if spawnPart then spawnPart.Position + Vector3.new(0, 0, -60) else Vector3.zero
	local count = GameConfig.AutoObjectiveCount
	local spacing = GameConfig.ObjectiveSpacing
	for i = 1, count do
		local floor = ground(center + Vector3.xAxis * (i - (count + 1) / 2) * spacing)
		local zone = part({
			Name = "Objective" .. i,
			Size = GameConfig.ZoneSize,
			CFrame = CFrame.new(floor + Vector3.new(0, GameConfig.ZoneSize.Y / 2, 0)),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Parent = folder,
		})
		zone:SetAttribute("Order", i)
		CollectionService:AddTag(zone, "Objective")
	end
	local reach = (count + 1) / 2 * spacing
	buildBase(folder, "A", ground(center - Vector3.xAxis * reach), center)
	buildBase(folder, "B", ground(center + Vector3.xAxis * reach), center)
	-- players must spawn at their main, not on the map's neutral spawn
	for _, item in workspace:GetDescendants() do
		if item:IsA("SpawnLocation") and item.Neutral then
			item.Enabled = false
		end
	end
end

local function collectZones(): { BasePart }
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

-- Flag pole, ground ring and number marker for each objective.
local function decorate(zone: BasePart, i: number)
	local model = Instance.new("Model")
	model.Name = "ObjectiveMarker" .. i
	model.Parent = zone.Parent
	local base = CFrame.new(ground(zone.Position))
	local diameter = math.min(zone.Size.X, zone.Size.Z)
	local ring = part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, diameter, diameter),
		CFrame = base * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Transparency = 0.85,
		CanCollide = false,
		CanQuery = false,
		Parent = model,
	})
	local height = 14
	local pole = part({
		Name = "Pole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 0.4, 0.4),
		CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 120, 125),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local flag = part({
		Name = "Flag",
		Size = Vector3.new(0.1, 2.4, 3.6),
		CanCollide = false,
		CanQuery = false,
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(36, 36)
	billboard.StudsOffset = Vector3.new(0, height / 2 + 3, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 2000
	billboard.Adornee = pole
	billboard.Parent = pole
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = tostring(i)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.BackgroundTransparency = 0.2
	label.Parent = billboard
	Instance.new("UICorner", label).CornerRadius = UDim.new(0.5, 0)
	visuals[i] = { flag = flag, ring = ring, label = label, base = base, height = height }
end

-- State ------------------------------------------------------------------------
local function publish(counts)
	for key, team in teams do
		team:SetAttribute("Tickets", state.tickets[key])
	end
	workspace:SetAttribute("GameObjectives", #state.points)
	for i, point in state.points do
		workspace:SetAttribute("Obj" .. i .. "Owner", point.owner or "")
		workspace:SetAttribute("Obj" .. i .. "Progress", math.floor(point.progress * 10 + 0.5) / 10)
		if counts then
			workspace:SetAttribute("Obj" .. i .. "A", counts[i].A)
			workspace:SetAttribute("Obj" .. i .. "B", counts[i].B)
		end
		local v = visuals[i]
		if v then
			local raised = math.abs(point.progress) / 100
			local towards = if point.progress > 0 then "A" elseif point.progress < 0 then "B" else nil
			v.flag.Color = sideColor(towards)
			v.flag.CFrame = v.base * CFrame.new(0, 1.4 + raised * (v.height - 2.6), 1.9)
			v.ring.Color = sideColor(point.owner)
			v.label.BackgroundColor3 = if point.owner then sideColor(point.owner) else Color3.fromRGB(60, 60, 65)
		end
	end
	workspace:SetAttribute("GameWinner", state.winner or "")
end

local function newRound()
	state = Rules.new(#zones, GameConfig.StartTickets)
	roundOver = false
	if GameService.onNewRound then
		task.spawn(GameService.onNewRound)
	end
	workspace:SetAttribute("GameResetAt", 0)
	publish()
end

local function checkWinner()
	if not state.winner or roundOver then
		return
	end
	local winner = state.winner :: string
	roundOver = true
	publish()
	broadcast(sideName(winner) .. " wins the round!", "result")
	workspace:SetAttribute("GameResetAt", workspace:GetServerTimeNow() + GameConfig.RoundEndSeconds)
	task.delay(GameConfig.RoundEndSeconds, function()
		newRound()
		broadcast("New round started", "info")
		for _, player in Players:GetPlayers() do
			if GameService.sideOf(player) then
				task.spawn(CharacterLook.load, player)
			end
		end
	end)
end

local function inside(zone: BasePart, position: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function step(dt: number)
	local counts = {}
	for i = 1, #zones do
		counts[i] = { A = 0, B = 0 }
	end
	for _, player in Players:GetPlayers() do
		local where = 0
		local side = GameService.sideOf(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local able = humanoid
			and humanoid.Health > 0
			and (GameConfig.CountIncapacitated or not MedicalService.isIncapacitated(player))
		if root and able then
			for i, zone in zones do
				if inside(zone, root.Position) then
					where = i
					if side then
						counts[i][side] += 1
					end
					break
				end
			end
		end
		if player:GetAttribute("InObjective") ~= where then
			player:SetAttribute("InObjective", where)
		end
	end
	for i in zones do
		for _, event in Rules.capture(state, i, counts[i].A, counts[i].B, dt, GameConfig) do
			if event.kind == "lost" then
				broadcast(
					("%s lost objective %d (-%d tickets)"):format(
						sideName(event.side),
						event.point,
						GameConfig.ObjectiveLossTickets
					),
					"error"
				)
			else
				broadcast(("%s captured objective %d"):format(sideName(event.side), event.point), "result")
			end
		end
	end
	publish(counts)
	checkWinner()
end

-- Players ----------------------------------------------------------------------
-- Costs `player`'s side a death ticket for `character`, once.
local function chargeDeath(player: Player, character: Model)
	if counted[character] then
		return
	end
	counted[character] = true
	character.Destroying:Once(function()
		counted[character] = nil
	end)
	local side = GameService.sideOf(player)
	if side and not roundOver then
		Rules.death(state, side, GameConfig)
		publish()
		checkWinner()
	end
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	humanoid.Died:Once(function()
		chargeDeath(player, character)
		task.delay(GameConfig.RespawnSeconds, function()
			if player.Parent and player.Character == character and GameService.sideOf(player) then
				CharacterLook.load(player)
			end
		end)
	end)
end

-- Unconscious player gave up: costs a death ticket (the caller respawns them).
function GameService.giveUp(player: Player)
	if GameConfig.Enabled and player.Character then
		chargeDeath(player, player.Character)
	end
end

local function result(player: Player, ok: boolean, message: string?)
	Remotes.get("TeamResult"):FireClient(player, ok, message)
end

function GameService.join(player: Player, side: any)
	if side ~= "A" and side ~= "B" then
		return
	end
	if GameService.sideOf(player) == side then
		result(player, true)
		return
	end
	local joining, other = countsFor(side, player)
	if not Rules.canJoin(joining, other, GameConfig.MaxTeamGap) then
		result(
			player,
			false,
			("%s has %d players and %s has %d: join %s"):format(
				sideName(side),
				joining,
				sideName(Rules.other(side)),
				other,
				sideName(Rules.other(side))
			)
		)
		return
	end
	-- switching sides while down counts as giving up
	if player.Character and GameService.sideOf(player) and MedicalService.isIncapacitated(player) then
		chargeDeath(player, player.Character)
		CareerService.recordDeath(player, player.Character)
	end
	player.Team = teams[side]
	result(player, true)
	CharacterLook.load(player)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	player.Team = lobby
	if player.Character then
		-- spawned before the game mode started (Studio play solo): wait in the lobby like everyone else
		local character = player.Character
		player.Character = nil
		character:Destroy()
	end
end

function GameService.init()
	if not GameConfig.Enabled then
		return
	end
	setupTeams()
	SquadService.init()
	zones = collectZones()
	if #zones == 0 and GameConfig.AutoBuildMap then
		buildMap()
		zones = collectZones()
	end
	if #zones < 2 then
		warn(
			"[GameMode] fewer than 2 objectives (tag Parts 'Objective' with an Order attribute); only deaths cost tickets"
		)
	end
	for i, zone in zones do
		decorate(zone, i)
	end
	local focus = if #zones > 0 then zones[math.ceil(#zones / 2)].Position else Vector3.new(0, 10, 0)
	workspace:SetAttribute("LobbyFocus", focus)
	local lastJoin: { [Player]: number } = {}
	Remotes.get("JoinTeam").OnServerEvent:Connect(function(player, side)
		local now = os.clock()
		if lastJoin[player] and now - lastJoin[player] < 1 then
			return
		end
		lastJoin[player] = now
		GameService.join(player, side)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastJoin[player] = nil
	end)
	newRound()
	Players.CharacterAutoLoads = false
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	task.spawn(function()
		while true do
			step(task.wait(GameConfig.TickRate))
		end
	end)
	print(("[GameMode] %d objectives, %d tickets per side"):format(#zones, GameConfig.StartTickets))
end

return GameService
