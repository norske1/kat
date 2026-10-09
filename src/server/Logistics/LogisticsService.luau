--!nonstrict
-- Base building: FOB radios, structures paid from FOB supplies, hammer construction, truck supply runs and HAB
-- spawns. Placement and building are validated here.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Logistics.Config)
local Logistics = require(Medical.Logistics.Logistics)
local Remotes = require(Medical.Remotes)
local MedicalService = require(script.Parent.Parent.MedicalService)
local GearService = require(script.Parent.Parent.Gear.GearService)

local LogisticsService = {}

type Fob = { id: number, side: string, part: BasePart, stock: number, structures: { any }, record: any? }
local fobs: { Fob } = {}
local folder: Folder
local nextId = 0
local lastRequest: { [Player]: number } = {}

local function sideOf(player: Player): string?
	return if player.Team then player.Team:GetAttribute("Side") :: string? else nil
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flat(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function notify(player: Player, text: string, kind: string?)
	MedicalService.notify(player, text, kind or "error")
end

-- Main bases: vehicle pads and team spawn locations.
local function mains(side: string?): { Vector3 }
	local list = {}
	for _, pad in CollectionService:GetTagged("VehiclePad") do
		if pad:IsA("BasePart") and (side == nil or pad:GetAttribute("Side") == side) then
			table.insert(list, pad.Position)
		end
	end
	for _, team in game:GetService("Teams"):GetTeams() do
		local s = team:GetAttribute("Side")
		if s and (side == nil or s == side) then
			for _, d in workspace:GetDescendants() do
				if d:IsA("SpawnLocation") and not d.Neutral and d.TeamColor == team.TeamColor then
					table.insert(list, d.Position)
				end
			end
		end
	end
	return list
end

local function fobAt(pos: Vector3, side: string?): Fob?
	for _, fob in fobs do
		if (side == nil or fob.side == side) and flat(fob.part.Position, pos) <= Config.FobRadius then
			return fob
		end
	end
	return nil
end

local function publish(fob: Fob)
	fob.part:SetAttribute("Stock", fob.stock)
end

-- Structures --------------------------------------------------------------------------------------------
local function setLook(model: Model, progress: number, done: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = if done then 0 else 0.75 - 0.45 * progress
			d.CanCollide = done
		end
	end
end

local function makeModel(kind: string, def, cf: CFrame): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = def.name
	local main = Instance.new("Part")
	main.Name = "Main"
	main.Anchored = true
	main.Size = def.size
	main.CFrame = cf * CFrame.new(0, def.size.Y / 2, 0)
	main.Color = def.color
	main.Material = if kind == "Sandbags" or kind == "HESCO" then Enum.Material.Fabric else Enum.Material.Concrete
	main.TopSurface = Enum.SurfaceType.Smooth
	main.Parent = model
	model.PrimaryPart = main
	if kind == "FOB" then
		local antenna = Instance.new("Part")
		antenna.Anchored = true
		antenna.Size = Vector3.new(0.3, 8, 0.3)
		antenna.CFrame = main.CFrame * CFrame.new(0.8, def.size.Y / 2 + 4, 0.8)
		antenna.Color = Color3.fromRGB(40, 40, 40)
		antenna.Parent = model
	elseif kind == "RazorWire" then
		main.Material = Enum.Material.DiamondPlate
	end
	model:SetAttribute("Structure", kind)
	return model, main
end

local function removeStructure(s, refund: boolean)
	if s.removed then
		return
	end
	s.removed = true
	if s.fob then
		local i = table.find(s.fob.structures, s)
		if i then
			table.remove(s.fob.structures, i)
		end
		if refund and fobs[table.find(fobs, s.fob) or 0] then
			s.fob.stock = math.min(Config.FobMaxStock, s.fob.stock + s.def.cost)
			publish(s.fob)
		end
	end
	s.model:Destroy()
end

local function removeFob(fob: Fob)
	local i = table.find(fobs, fob)
	if i then
		table.remove(fobs, i)
	end
	for _, s in table.clone(fob.structures) do
		removeStructure(s, false)
	end
	if fob.record then
		removeStructure(fob.record, false)
	end
end

local function complete(s)
	s.done = true
	setLook(s.model, 1, true)
	for _, d in s.model:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == "Build" then
			d:Destroy()
		end
	end
	if s.kind == "HAB" then
		s.main:SetAttribute("Side", s.side)
		s.main:SetAttribute("HabId", tostring(s.id))
		CollectionService:AddTag(s.main, "HAB")
	elseif s.kind == "AmmoCrate" then
		CollectionService:AddTag(s.main, "Arsenal")
	elseif s.kind == "FOB" and s.fobRef then
		s.main:SetAttribute("Built", true)
	end
end

local function hammerHit(player: Player, s)
	if s.done or s.removed or sideOf(player) ~= s.side or MedicalService.isIncapacitated(player) then
		return
	end
	if GearService.count(player, "Hammer") <= 0 then
		notify(player, "You need a Hammer in your inventory to build")
		return
	end
	s.points += 1
	s.prompt.ObjectText = string.format("%s  %d/%d", s.def.name, s.points, s.def.build)
	if s.points >= s.def.build then
		complete(s)
		notify(player, s.def.name .. " built", "result")
	else
		setLook(s.model, s.points / s.def.build, false)
	end
end

local function addPrompt(parent: BasePart, name: string, action: string, hold: number, fn)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.HoldDuration = hold
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.max(8, parent.Size.Magnitude / 2 + 4)
	prompt.KeyboardKeyCode = if name == "Build" then Enum.KeyCode.F else Enum.KeyCode.G
	prompt.Parent = parent
	prompt.Triggered:Connect(fn)
	return prompt
end

local function place(player: Player, kind: any, cf: any)
	local def = typeof(kind) == "string" and Config.Structures[kind]
	local side = sideOf(player)
	local root = rootOf(player)
	if not def or typeof(cf) ~= "CFrame" or not side or not root or MedicalService.isIncapacitated(player) then
		return
	end
	local pos = cf.Position
	if pos ~= pos or pos.Magnitude > 1e5 then
		return
	end
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.zAxis
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, player.Character or folder }
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params)
	if hit then
		pos = hit.Position
	end
	local placeCf = CFrame.lookAt(pos, pos + look)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { folder }
	local blocked = #workspace:GetPartBoundsInBox(placeCf * CFrame.new(0, def.size.Y / 2, 0), def.size, overlap) > 0
	local fob = fobAt(pos, side)
	local mainDistance, fobDistance = math.huge, math.huge
	for _, m in mains(nil) do
		mainDistance = math.min(mainDistance, flat(m, pos))
	end
	for _, f in fobs do
		fobDistance = math.min(fobDistance, flat(f.part.Position, pos))
	end
	local habs = 0
	if fob then
		for _, s in fob.structures do
			if s.kind == "HAB" then
				habs += 1
			end
		end
	end
	local ok, why = Logistics.canPlace(kind, def, {
		class = player:GetAttribute("Class") or "Rifleman",
		distance = (root.Position - pos).Magnitude,
		fob = if fob then { stock = fob.stock, habs = habs } else nil,
		mainDistance = mainDistance,
		fobDistance = fobDistance,
		blocked = blocked,
	}, Config)
	if not ok then
		notify(player, why or "Can't place that here")
		return
	end

	nextId += 1
	local model, main = makeModel(kind, def, placeCf)
	local s = {
		id = nextId,
		kind = kind,
		def = def,
		side = side,
		model = model,
		main = main,
		points = 0,
		done = false,
		removed = false,
	}
	model.Parent = folder
	setLook(model, 0, false)
	s.prompt = addPrompt(main, "Build", "Build (Hammer)", Config.BuildHold, function(p)
		hammerHit(p, s)
	end)
	s.prompt.ObjectText = string.format("%s  0/%d", def.name, def.build)
	if kind == "FOB" then
		local newFob: any = { id = nextId, side = side, part = main, stock = 0, structures = {}, record = s }
		s.fobRef = newFob
		table.insert(fobs, newFob)
		main:SetAttribute("Side", side)
		main:SetAttribute("Built", false)
		publish(newFob)
		CollectionService:AddTag(main, "FOB")
		addPrompt(main, "Dismantle", "Dismantle (enemy FOB)", Config.DismantleSeconds, function(p)
			local ps = sideOf(p)
			if ps and ps ~= side and not MedicalService.isIncapacitated(p) and table.find(fobs, newFob) then
				removeFob(newFob)
				notify(p, "Enemy FOB dismantled", "result")
			end
		end)
	else
		fob.stock -= def.cost
		publish(fob)
		s.fob = fob
		table.insert(fob.structures, s)
		addPrompt(main, "Remove", "Remove (leaders)", 2, function(p)
			if sideOf(p) == side and Logistics.LEADERS[p:GetAttribute("Class") or ""] then
				removeStructure(s, true)
			end
		end)
	end
	notify(player, def.name .. " placed. Build it up with a Hammer", "result")
end

-- Trucks ------------------------------------------------------------------------------------------------
function LogisticsService.onVehicle(model: Model, def)
	if (def.supplies or 0) <= 0 or not model.PrimaryPart then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Supplies"
	prompt.ActionText = "Load / unload supplies"
	prompt.ObjectText = def.name
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.HoldDuration = 1
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = def.size.Z / 2 + 6
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		local side = model:GetAttribute("Side")
		if sideOf(player) ~= side or model:GetAttribute("Health") == 0 then
			return
		end
		local primary = model.PrimaryPart
		if not primary then
			return
		end
		local pos = primary.Position
		local cargo = model:GetAttribute("Supplies") or 0
		local cap = model:GetAttribute("SupplyCap") or 0
		for _, m in mains(side) do
			if flat(m, pos) <= Config.MainRadius then
				local n = Logistics.transfer(math.huge, cargo, cap)
				model:SetAttribute("Supplies", cargo + n)
				notify(player, string.format("Loaded %d supplies", n), "result")
				return
			end
		end
		local fob = fobAt(pos, side)
		if fob then
			local n = Logistics.transfer(cargo, fob.stock, Config.FobMaxStock)
			model:SetAttribute("Supplies", cargo - n)
			fob.stock += n
			publish(fob)
			notify(player, string.format("Unloaded %d supplies (FOB has %d)", n, fob.stock), "result")
			return
		end
		notify(player, "Load supplies at your main base, unload them inside a friendly FOB's radius")
	end)
end

-- HAB spawns ----------------------------------------------------------------------------------------------
local function habFor(player: Player): BasePart?
	local id = player:GetAttribute("SpawnAt")
	if not id then
		return nil
	end
	for _, hab in CollectionService:GetTagged("HAB") do
		if hab:IsA("BasePart") and hab:GetAttribute("HabId") == id and hab:GetAttribute("Side") == sideOf(player) then
			return hab
		end
	end
	return nil
end

local function onCharacter(player: Player, character: Model)
	local hab = habFor(player)
	if not hab then
		return
	end
	for _, other in Players:GetPlayers() do
		local root = rootOf(other)
		local os = sideOf(other)
		if root and os and os ~= sideOf(player) and not MedicalService.isIncapacitated(other) then
			if (root.Position - hab.Position).Magnitude <= Config.HabBlockRadius then
				notify(player, "Enemies near the HAB, spawned at main")
				return
			end
		end
	end
	task.defer(function()
		character:WaitForChild("HumanoidRootPart", 5)
		if character.Parent then
			character:PivotTo(hab.CFrame * CFrame.new(0, 0, -hab.Size.Z / 2 - 4) + Vector3.new(0, 1, 0))
		end
	end)
end

local function onRequest(player: Player, action: any, a: any, b: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.3 then
		return
	end
	lastRequest[player] = now
	if action == "place" then
		place(player, a, b)
	elseif action == "spawnAt" then
		player:SetAttribute("SpawnAt", if typeof(a) == "string" and #a < 20 then a else nil)
		notify(
			player,
			if player:GetAttribute("SpawnAt") then "You'll respawn at that HAB" else "Spawning at main",
			"info"
		)
	end
end

function LogisticsService.reset()
	for _, fob in table.clone(fobs) do
		removeFob(fob)
	end
	folder:ClearAllChildren()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("SpawnAt", nil)
	end
end

function LogisticsService.init()
	if not Config.Enabled then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "Structures"
	folder.Parent = workspace
	Remotes.get("Build").OnServerEvent:Connect(onRequest)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		player:GetPropertyChangedSignal("Team"):Connect(function()
			player:SetAttribute("SpawnAt", nil)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return LogisticsService
