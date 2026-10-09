--!nonstrict
-- Server side of the ArmA-style inventory: owns every player's gear (worn slots + container contents),
-- class kits on spawn, arsenals (weapon lockers / parts tagged "Arsenal") and items dropped on the
-- ground. Weight is published as character attributes (GearMass, GearSpeed, GearNoSprint).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Config)
local Items = require(Medical.Items)
local GearConfig = require(Medical.Gear.Config)
local Gear = require(Medical.Gear.Gear)
local Remotes = require(Medical.Remotes)

local GearService = {}

-- Hooks set by Main.server (kept as hooks so this module doesn't depend on MedicalService).
GearService.levelOf = function(_player: Player): number
	return 0
end
GearService.canUse = function(_player: Player): boolean
	return true
end

local states: { [Player]: Gear.State } = {}
local listeners: { (Player) -> () } = {}
local piles: { [BasePart]: { [string]: number } } = {}
local lastAction: { [Player]: number } = {}
local weapons = nil -- WeaponService, when guns are running
local stateRemote = nil

function GearService.onChanged(fn: (Player) -> ())
	table.insert(listeners, fn)
end

function GearService.get(player: Player): Gear.State
	local s = states[player]
	if not s then
		s = Gear.new()
		states[player] = s
	end
	return s
end

-- Arsenal contents ----------------------------------------------------------------------------------
local KIND_ORDER = { weapon = 1, container = 2, ammo = 3, item = 4, medical = 5 }
local arsenalIds: { string }? = nil
local function arsenalList(): { string }
	if arsenalIds then
		return arsenalIds
	end
	local list = {}
	for id, def in GearConfig.Items do
		if def.arsenal then
			table.insert(list, id)
		end
	end
	for id in Items do
		table.insert(list, id)
	end
	table.sort(list, function(a, b)
		local da, db = Gear.def(a), Gear.def(b)
		local ka, kb = KIND_ORDER[da.kind] or 9, KIND_ORDER[db.kind] or 9
		if ka ~= kb then
			return ka < kb
		end
		if da.category ~= db.category then
			return (da.category or "") < (db.category or "")
		end
		return da.name < db.name
	end)
	arsenalIds = list
	return list
end

-- Medics (medical level 1+) get every medical item; others only what the level-0 loadout has.
local function offered(player: Player, id: string): boolean
	local def = Gear.def(id)
	if not def then
		return false
	end
	if def.kind ~= "medical" then
		return def.arsenal == true
	end
	local basic = Config.Loadouts[0]
	return GearService.levelOf(player) >= 1 or (basic ~= nil and basic[id] ~= nil)
end

local function arsenalFor(player: Player): { string }
	local list = {}
	for _, id in arsenalList() do
		if offered(player, id) then
			table.insert(list, id)
		end
	end
	return list
end

-- Sources (arsenal / ground) ------------------------------------------------------------------------
local function rootOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function positionOf(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

local function nearestSource(player: Player): (string?, Instance?)
	local root = rootOf(player)
	if not root then
		return nil, nil
	end
	local best, bestKind, bestDist = nil, nil, GearConfig.SourceRange
	for _, inst in CollectionService:GetTagged("Arsenal") do
		local pos = inst:IsDescendantOf(workspace) and positionOf(inst)
		if pos and (pos - root.Position).Magnitude <= bestDist then
			best, bestKind, bestDist = inst, "arsenal", (pos - root.Position).Magnitude
		end
	end
	if best then
		return bestKind, best
	end
	for part in piles do
		local d = (part.Position - root.Position).Magnitude
		if part.Parent and d <= bestDist then
			best, bestKind, bestDist = part, "ground", d
		end
	end
	return bestKind, best
end

local function sourceInfo(player: Player)
	local kind, inst = nearestSource(player)
	if kind == "arsenal" then
		return { kind = "arsenal", items = arsenalFor(player) }
	elseif kind == "ground" then
		return { kind = "ground", items = table.clone(piles[inst :: BasePart]) }
	end
	return { kind = "ground", items = {} }
end

local function makePile(player: Player): BasePart?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local params = RaycastParams.new()
	local char = player.Character
	params.FilterDescendantsInstances = if char then { char } else {}
	local origin = (root.CFrame * CFrame.new(0, 0, -2.5)).Position
	local hit = workspace:Raycast(origin, Vector3.new(0, -12, 0), params)
	local floor = if hit then hit.Position else origin - Vector3.new(0, 3, 0)
	local part = Instance.new("Part")
	part.Name = "DroppedGear"
	part.Size = Vector3.new(1.6, 0.8, 1.2)
	part.CFrame = CFrame.new(floor + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Color = Color3.fromRGB(88, 82, 62)
	part.Material = Enum.Material.Fabric
	local folder = workspace:FindFirstChild("DroppedGear")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DroppedGear"
		folder.Parent = workspace
	end
	part.Parent = folder
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open inventory"
	prompt.ObjectText = "Dropped gear"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(p)
		GearService.changed(p, true)
	end)
	piles[part] = {}
	part.Destroying:Connect(function()
		piles[part] = nil
	end)
	task.delay(GearConfig.PileLifetime, function()
		if part.Parent then
			part:Destroy()
		end
	end)
	return part
end

-- Puts items into the source: an arsenal takes them back, otherwise they go in a pile on the ground.
local function toSource(player: Player, kind: string?, inst: Instance?, items: { [string]: number })
	if kind == "arsenal" or next(items) == nil then
		return
	end
	local part = if kind == "ground" then inst :: BasePart else makePile(player)
	local pile = part and piles[part]
	if not pile then
		return
	end
	for id, n in items do
		if n > 0 then
			pile[id] = (pile[id] or 0) + n
		end
	end
end

local function takeFromPile(part: BasePart, id: string, n: number): number
	local pile = piles[part]
	local have = pile and pile[id] or 0
	local take = math.min(have, n)
	if take > 0 then
		pile[id] = if have - take > 0 then have - take else nil
		if next(pile) == nil then
			part:Destroy()
		end
	end
	return take
end

-- Sync --------------------------------------------------------------------------------------------
function GearService.changed(player: Player, openUi: boolean?)
	local s = GearService.get(player)
	local mass = Gear.mass(s)
	local char = player.Character
	if char then
		char:SetAttribute("GearMass", math.floor(mass * 10 + 0.5) / 10)
		char:SetAttribute("GearSpeed", Gear.speed(mass))
		char:SetAttribute("GearNoSprint", not Gear.canSprint(mass))
	end
	if weapons then
		local wanted = {}
		for _, slot in Gear.WEAPON_SLOTS do
			local def = s.slots[slot] and Gear.def(s.slots[slot])
			if def and def.weaponId then
				wanted[def.weaponId] = true
			end
		end
		weapons.syncTools(player, wanted)
	end
	if stateRemote and player.Parent then
		stateRemote:FireClient(player, Gear.snapshot(s), sourceInfo(player), openUi == true)
	end
	for _, fn in listeners do
		task.spawn(fn, player)
	end
end

function GearService.count(player: Player, id: string): number
	return Gear.count(GearService.get(player), id)
end

function GearService.addItem(player: Player, id: string, n: number): number
	local added = Gear.add(GearService.get(player), id, n)
	GearService.changed(player)
	return added
end

function GearService.removeItem(player: Player, id: string, n: number): number
	local removed = Gear.remove(GearService.get(player), id, n)
	if removed > 0 then
		GearService.changed(player)
	end
	return removed
end

-- Spawn kits ----------------------------------------------------------------------------------------
local function kitFor(player: Player)
	local class = player:GetAttribute("Class")
	return GearConfig.Kits[class] or GearConfig.Kits.Rifleman
end

function GearService.spawn(player: Player)
	if GearConfig.ClassSetsMedicalLevel then
		player:SetAttribute("MedicalLevel", if player:GetAttribute("Class") == "Medic" then 1 else 0)
	end
	local level = GearService.levelOf(player)
	local s = Gear.fromKit(kitFor(player), Config.Loadouts[level] or Config.Loadouts[0])
	states[player] = s
	GearService.changed(player)
end

-- Tops each carried weapon's ammo up to the class kit amount (or 4 magazines), as far as it fits.
function GearService.resupply(player: Player)
	local s = GearService.get(player)
	local kitAmmo = {}
	for _, entry in kitFor(player).items do
		kitAmmo[entry[1]] = entry[2]
	end
	for _, slot in Gear.WEAPON_SLOTS do
		local def = s.slots[slot] and Gear.def(s.slots[slot])
		local ammoId = def and def.weaponId and GearConfig.Ammo[def.weaponId]
		if ammoId then
			local per = Gear.def(ammoId).roundsPer or 1
			local want = kitAmmo[ammoId] or per * 4
			local need = want - Gear.count(s, ammoId)
			if need > 0 then
				Gear.add(s, ammoId, need)
			end
		end
	end
	GearService.changed(player)
end

-- Weapon locker: puts the weapon in its slot (the old one goes back) and adds ammo for it.
function GearService.takeWeapon(player: Player, weaponId: string): boolean
	local s = GearService.get(player)
	for _, slot in Gear.WEAPON_SLOTS do
		if s.slots[slot] == weaponId then
			GearService.resupply(player)
			return false
		end
	end
	if not Gear.wear(s, weaponId) then
		return false
	end
	GearService.resupply(player)
	return true
end

-- Remote --------------------------------------------------------------------------------------------
local function count(v: any): number
	local n = tonumber(v) or 1
	return math.clamp(math.floor(n), 1, 10000)
end

local function container(v: any): string?
	return if typeof(v) == "string" and Gear.isContainer(v) then v else nil
end

local function wearFrom(player: Player, s, id: string, kind: string?, inst: Instance?)
	if kind == "ground" then
		if takeFromPile(inst :: BasePart, id, 1) < 1 then
			return
		end
	elseif kind ~= "arsenal" or not offered(player, id) then
		return
	end
	local ok, old, overflow = Gear.wear(s, id)
	if not ok then
		return
	end
	local back = overflow or {}
	if old then
		back[old] = (back[old] or 0) + 1
	end
	-- arsenal swaps go back to the arsenal, but overflow from a smaller container lands on the ground
	if kind == "arsenal" and overflow and next(overflow) then
		toSource(player, nil, nil, overflow)
	else
		toSource(player, kind, inst, back)
	end
end

local actions = {}

function actions.open() end

function actions.take(player, s, kind, inst, id, n, to)
	local def = Gear.def(id)
	if not def then
		return
	end
	if def.slot then
		wearFrom(player, s, id, kind, inst)
		return
	end
	n = count(n)
	to = container(to)
	if kind == "arsenal" then
		if offered(player, id) then
			Gear.add(s, id, n, to)
		end
	elseif kind == "ground" then
		local fit = 0
		for _, c in (if to then { to } else Gear.CONTAINERS) do
			fit += Gear.room(s, c, id)
		end
		local taken = takeFromPile(inst, id, math.min(n, fit))
		local added = Gear.add(s, id, taken, to)
		if added < taken then
			toSource(player, kind, inst, { [id] = taken - added })
		end
	end
end

function actions.drop(player, s, kind, inst, id, n, from)
	local c = container(from)
	if not Gear.def(id) or not c then
		return
	end
	local removed = Gear.remove(s, id, count(n), c)
	if removed > 0 then
		toSource(player, kind, inst, { [id] = removed })
	end
end

function actions.move(_player, s, _kind, _inst, id, n, from, to)
	local a, b = container(from), container(to)
	if Gear.def(id) and a and b then
		Gear.move(s, id, count(n), a, b)
	end
end

function actions.unwear(player, s, kind, inst, slot)
	if typeof(slot) ~= "string" or not table.find(Gear.SLOTS, slot) then
		return
	end
	local id, contents = Gear.unwear(s, slot)
	if not id then
		return
	end
	local back = contents or {}
	if kind == "arsenal" then
		toSource(player, nil, nil, back) -- the arsenal takes the gear, the contents land on the ground
	else
		back[id] = (back[id] or 0) + 1
		toSource(player, kind, inst, back)
	end
end

local function onGear(player: Player, action: any, ...)
	local fn = typeof(action) == "string" and actions[action]
	if not fn then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.06 then
		return
	end
	lastAction[player] = now
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	if action ~= "open" and not GearService.canUse(player) then
		return
	end
	local kind, inst = nearestSource(player)
	fn(player, GearService.get(player), kind, inst, ...)
	GearService.changed(player, action == "open")
end

-- Arsenal prompts -------------------------------------------------------------------------------------
local function setupArsenal(inst: Instance)
	local part = if inst:IsA("BasePart")
		then inst
		elseif inst:IsA("Model") then inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		else nil
	if not part or part:FindFirstChild("ArsenalPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ArsenalPrompt"
	prompt.ActionText = "Open arsenal"
	prompt.ObjectText = "Arsenal"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		GearService.changed(player, true)
	end)
end

-- Ammo provider for the weapon system: ammo is stored in the inventory as rounds.
local function ammoProvider()
	return {
		count = function(player: Player, weaponId: string): number
			local ammoId = GearConfig.Ammo[weaponId]
			return if ammoId then Gear.count(GearService.get(player), ammoId) else 0
		end,
		take = function(player: Player, weaponId: string, n: number): number
			local ammoId = GearConfig.Ammo[weaponId]
			if not ammoId or n <= 0 then
				return 0
			end
			local removed = Gear.remove(GearService.get(player), ammoId, n)
			task.defer(GearService.changed, player)
			return removed
		end,
	}
end

function GearService.init(weaponService)
	stateRemote = Remotes.get("GearState")
	Remotes.get("Gear").OnServerEvent:Connect(onGear)
	if weaponService then
		weapons = weaponService
		weaponService.ammo = ammoProvider()
		weaponService.hooks.take = GearService.takeWeapon
		weaponService.hooks.refill = GearService.resupply
	end
	for _, inst in CollectionService:GetTagged("Arsenal") do
		setupArsenal(inst)
	end
	CollectionService:GetInstanceAddedSignal("Arsenal"):Connect(setupArsenal)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		lastAction[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if player.Character and not states[player] then
			task.spawn(GearService.spawn, player)
		end
	end
end

return GearService
