--!nonstrict
-- Server side of the gun system: tools, ammo, validated hitscan shots and reloads.
-- Hits are turned into medical wounds on the body part that was hit (MedicalService.applyDamage).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Weapons = ReplicatedStorage:WaitForChild("Weapons")
local WeaponConfig = require(Weapons.Config)
local Models = require(Weapons.Models)
local Remotes = require(Medical.Remotes)
local Sounds = require(Medical.Sounds)
local Patient = require(Medical.Sim.Patient)
local MedicalService = require(script.Parent.Parent.MedicalService)
local ActionRunner = require(script.Parent.Parent.ActionRunner)
local Carry = require(script.Parent.Parent.Carry)

local WeaponService = {}

type ToolState = {
	def: any,
	owner: Player,
	ammo: number,
	reserve: number,
	reloading: boolean,
	token: number,
	nextShot: number,
	character: Model?,
}

local tools: { [Tool]: ToolState } = {}
local actionTokens: { [Model]: number } = {}

local fxRemote = Remotes.get("GunFx")
local hitRemote = Remotes.get("GunHit")

local GUN_ATTRIBUTES = { "GunHold", "GunWeapon", "GunAim", "GunPitch", "GunAction", "GunActionT", "GunActionDur" }

local function sync(tool: Tool, st: ToolState)
	tool:SetAttribute("Ammo", st.ammo)
	tool:SetAttribute("Reserve", st.reserve)
	tool:SetAttribute("Reloading", st.reloading)
end

local function humanoidOf(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function setAction(character: Model, action: string, duration: number)
	local token = (actionTokens[character] or 0) + 1
	actionTokens[character] = token
	character:SetAttribute("GunAction", action)
	character:SetAttribute("GunActionT", workspace:GetServerTimeNow())
	character:SetAttribute("GunActionDur", duration)
	task.delay(duration, function()
		if actionTokens[character] == token then
			actionTokens[character] = nil
			character:SetAttribute("GunAction", nil)
		end
	end)
end

local function clearCharacter(character: Model?)
	if not character then
		return
	end
	local model = character :: Model
	actionTokens[model] = nil
	for _, name in GUN_ATTRIBUTES do
		model:SetAttribute(name, nil)
	end
end

local function characterFromPart(part: Instance): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Accessories (hats, vests) count as the body part they are attached to.
local function bodyPartName(part: Instance): string
	local parent = part.Parent
	if parent and parent:IsA("Accessory") then
		local weld = part:FindFirstChild("AccessoryWeld")
		if weld and weld:IsA("Weld") and weld.Part1 then
			return weld.Part1.Name
		end
		return "Head"
	end
	return part.Name
end

local function isFriendly(shooter: Player, model: Model): boolean
	if WeaponConfig.FriendlyFire then
		return false
	end
	local other = Players:GetPlayerFromCharacter(model)
	return other ~= nil
		and other ~= shooter
		and not shooter.Neutral
		and shooter.Team ~= nil
		and other.Team == shooter.Team
end

local function applyHit(shooter: Player, model: Model, part: Instance, damage: number, def)
	if isFriendly(shooter, model) then
		return
	end
	if MedicalService.get(model) then
		MedicalService.applyDamage(model, bodyPartName(part), damage, def.damageType)
	elseif WeaponConfig.DamageNonMedical then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:TakeDamage(damage)
		end
	end
end

local function canUse(player: Player): boolean
	return not MedicalService.isIncapacitated(player)
		and not ActionRunner.isBusy(player)
		and not Carry.isCarrying(player)
end

-- Tools ------------------------------------------------------------------------------------------
function WeaponService.createTool(player: Player, weaponId: string): Tool?
	local def = WeaponConfig.get(weaponId)
	if not def then
		warn("[Weapons] unknown weapon " .. tostring(weaponId))
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.ToolTip = def.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new()
	tool:SetAttribute("WeaponId", def.id)
	local model = Models.build(def.model)
	model.Name = "GunModel"
	local handle = model.PrimaryPart :: BasePart
	handle.Parent = tool
	model.Parent = tool

	local st: ToolState = {
		def = def,
		owner = player,
		ammo = def.magazine,
		reserve = def.reserve,
		reloading = false,
		token = 0,
		nextShot = 0,
		character = nil,
	}
	tools[tool] = st
	sync(tool, st)

	tool.Equipped:Connect(function()
		local character = tool.Parent
		if not character or not character:IsA("Model") then
			return
		end
		if not canUse(player) then
			task.defer(function()
				local humanoid = humanoidOf(player)
				if humanoid then
					humanoid:UnequipTools()
				end
			end)
			return
		end
		st.character = character
		character:SetAttribute("GunHold", def.hold)
		character:SetAttribute("GunWeapon", def.id)
		setAction(character, "Equip", def.equipTime)
		st.nextShot = os.clock() + def.equipTime * WeaponConfig.RateTolerance
		Sounds.play("Equip", handle)
	end)
	tool.Unequipped:Connect(function()
		st.token += 1
		st.reloading = false
		sync(tool, st)
		clearCharacter(st.character)
		st.character = nil
	end)
	tool.Destroying:Connect(function()
		tools[tool] = nil
	end)
	return tool
end

local function ownedTool(player: Player, weaponId: string): Tool?
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("WeaponId") == weaponId then
					return child
				end
			end
		end
	end
	return nil
end

local function refillTool(tool: Tool)
	local st = tools[tool]
	if st then
		st.reserve = st.def.reserve
		sync(tool, st)
	end
end

-- Gives a weapon (or refills it if the player already has one). Returns true if a new tool was given.
function WeaponService.give(player: Player, weaponId: string): boolean
	local existing = ownedTool(player, weaponId)
	if existing then
		refillTool(existing)
		return false
	end
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	local tool = WeaponService.createTool(player, weaponId)
	if tool and backpack then
		tool.Parent = backpack
		return true
	end
	return false
end

function WeaponService.giveLoadout(player: Player)
	for _, weaponId in WeaponConfig.Loadout do
		WeaponService.give(player, weaponId)
	end
end

function WeaponService.refill(player: Player)
	for tool, st in tools do
		if st.owner == player then
			refillTool(tool)
		end
	end
end

function WeaponService.unequip(player: Player)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid:UnequipTools()
	end
end

-- Remotes ------------------------------------------------------------------------------------------
local function equippedState(player: Player, tool: any): ToolState?
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return nil
	end
	local st = tools[tool]
	local character = player.Character
	if not st or st.owner ~= player or not character or tool.Parent ~= character then
		return nil
	end
	return st
end

local function onFire(player: Player, tool: any, origin: any, directions: any)
	local st = equippedState(player, tool)
	if not st or typeof(origin) ~= "Vector3" or typeof(directions) ~= "table" then
		return
	end
	local def = st.def
	if not canUse(player) or st.reloading or st.ammo <= 0 or #directions ~= def.pellets then
		return
	end
	local now = os.clock()
	if now < st.nextShot then
		return
	end
	local character = player.Character
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	if (origin - head.Position).Magnitude > WeaponConfig.MaxOriginDistance then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	if workspace:Raycast(head.Position, origin - head.Position, params) then
		origin = head.Position -- muzzle poking through a wall: shoot from the head instead
	end

	st.ammo -= 1
	st.nextShot = now + (60 / def.rpm) * WeaponConfig.RateTolerance
	sync(tool, st)

	local hits = {}
	local hitFlesh = false
	for i = 1, def.pellets do
		local dir = directions[i]
		if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.5 then
			hits[i] = { p = origin, k = 0 }
			continue
		end
		dir = dir.Unit
		local result = workspace:Raycast(origin, dir * def.range, params)
		if result then
			local model = characterFromPart(result.Instance)
			local kind = 1
			if model and model ~= character then
				kind = 2
				hitFlesh = true
				applyHit(player, model, result.Instance, WeaponConfig.damageAt(def, result.Distance), def)
			end
			local color = if result.Instance:IsA("BasePart") and not result.Instance:IsA("Terrain")
				then result.Instance.Color
				else nil
			hits[i] = { p = result.Position, n = result.Normal, k = kind, c = color }
		else
			hits[i] = { p = origin + dir * def.range, k = 0 }
		end
	end
	fxRemote:FireAllClients(player, def.id, origin, hits)
	if hitFlesh then
		hitRemote:FireClient(player, 2)
	end
	if def.pumpTime then
		task.delay(0.15, function()
			if st.character == character and tool.Parent == character then
				setAction(character, "Pump", def.pumpTime)
				Sounds.play("ShotgunPump", tool:FindFirstChild("Handle"))
			end
		end)
	end
end

local function onReload(player: Player, tool: any)
	local st = equippedState(player, tool)
	if not st or st.reloading or not canUse(player) then
		return
	end
	local def = st.def
	if st.ammo >= def.magazine or st.reserve <= 0 then
		return
	end
	local record = MedicalService.getByPlayer(player)
	local armInjury = if record then Patient.armImpairment(record.state) else 0
	local pain = if record then record.state.painPerceived or 0 else 0
	local duration = WeaponConfig.reloadDuration(def, st.ammo, st.reserve, armInjury, pain)
	local character = player.Character
	local handle = tool:FindFirstChild("Handle")
	st.reloading = true
	st.token += 1
	local token = st.token
	sync(tool, st)
	local function valid(): boolean
		return st.token == token and tool.Parent == character
	end

	if def.reloadPerShell then
		local shells = math.min(def.magazine - st.ammo, st.reserve)
		local interval = (duration - 0.3) / math.max(shells, 1)
		setAction(character, "ReloadShells", duration)
		for i = 1, shells do
			task.delay(interval * i, function()
				if valid() and st.reserve > 0 and st.ammo < def.magazine then
					st.ammo += 1
					st.reserve -= 1
					sync(tool, st)
					Sounds.play("ShellInsert", handle)
				end
			end)
		end
		task.delay(duration, function()
			if valid() then
				st.reloading = false
				sync(tool, st)
				Sounds.play("ShotgunPump", handle)
			end
		end)
	else
		setAction(character, "Reload", duration)
		task.delay(duration * 0.15, function()
			if valid() then
				Sounds.play("MagOut", handle)
			end
		end)
		task.delay(duration * 0.6, function()
			if valid() then
				Sounds.play("MagIn", handle)
			end
		end)
		task.delay(duration * 0.85, function()
			if valid() then
				Sounds.play("Bolt", handle)
			end
		end)
		task.delay(duration, function()
			if valid() then
				local take = math.min(def.magazine - st.ammo, st.reserve)
				st.ammo += take
				st.reserve -= take
				st.reloading = false
				sync(tool, st)
			end
		end)
	end
end

local function onState(player: Player, tool: any, aiming: any, pitch: any)
	local st = equippedState(player, tool)
	if not st or typeof(pitch) ~= "number" or pitch ~= pitch then
		return
	end
	local character = player.Character
	character:SetAttribute("GunAim", aiming == true)
	character:SetAttribute("GunPitch", math.floor(math.clamp(pitch, -80, 80) + 0.5))
end

-- Racks / ammo crates ------------------------------------------------------------------------------
local function setupRack(part: Instance)
	if not part:IsA("BasePart") or part:FindFirstChild("WeaponRackPrompt") then
		return
	end
	local def = WeaponConfig.get(part:GetAttribute("WeaponId"))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WeaponRackPrompt"
	prompt.ActionText = if def then "Take " .. def.name else "Resupply ammo"
	prompt.ObjectText = if def then "Weapon Rack" else "Ammo Crate"
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	if def then
		local rack = part :: BasePart
		local display = Models.display(
			def.model,
			rack.CFrame * CFrame.new(0, rack.Size.Y / 2 + 0.15, 0) * CFrame.Angles(0, math.rad(90), math.rad(90))
		)
		display.Name = "Display"
		display.Parent = part
	end
	prompt.Triggered:Connect(function(player)
		if def then
			local given = WeaponService.give(player, def.id)
			MedicalService.notify(
				player,
				if given then def.name .. " taken" else def.name .. " ammo refilled",
				"result"
			)
		else
			WeaponService.refill(player)
			MedicalService.notify(player, "Ammo resupplied", "result")
		end
	end)
end

-- Init -----------------------------------------------------------------------------------------------
function WeaponService.init()
	Remotes.get("GunFire").OnServerEvent:Connect(onFire)
	Remotes.get("GunReload").OnServerEvent:Connect(onReload)
	Remotes.get("GunState").OnServerEvent:Connect(onState)

	local previous = MedicalService.onIncapacitated
	MedicalService.onIncapacitated = function(player: Player)
		if previous then
			previous(player)
		end
		WeaponService.unequip(player)
	end

	local function onCharacter(player: Player)
		if WeaponConfig.GiveOnSpawn then
			task.defer(WeaponService.giveLoadout, player)
		end
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		if player.Character then
			onCharacter(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		for tool, st in tools do
			if st.owner == player then
				tools[tool] = nil
			end
		end
	end)

	for _, part in CollectionService:GetTagged("WeaponRack") do
		setupRack(part)
	end
	CollectionService:GetInstanceAddedSignal("WeaponRack"):Connect(setupRack)
end

return WeaponService
