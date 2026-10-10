--!nonstrict
-- Vehicles: motor pool spawning with per-side caps and cooldowns, seats, driver network ownership, idle despawn,
-- damage and destruction, and server-validated mounted guns. Models are placeholder parts.
-- Map: Parts tagged "VehiclePad" with a string attribute Side ("A" / "B") are spawn pads; the auto-built map has one
-- next to each main base.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local GameConfig = require(Medical.GameMode.Config)
local Pool = require(Medical.Vehicles.Pool)
local Remotes = require(Medical.Remotes)
local VehicleConfig = require(Medical.Vehicles.Config)
local WeaponConfig = require(Medical.Weapons.Config)
local MedicalService = require(script.Parent.Parent.MedicalService)
local WeaponService = require(script.Parent.Parent.Weapons.WeaponService)

local VehicleService = {}
VehicleService.onSpawned = nil :: ((Model, any) -> ())?

type Record = {
	id: number,
	type: string,
	def: VehicleConfig.VehicleDef,
	side: string,
	model: Model,
	hull: BasePart,
	seats: { Seat | VehicleSeat },
	driver: VehicleSeat,
	gunner: Seat?,
	turretWeld: Weld?,
	turretBase: CFrame?,
	muzzle: Attachment?,
	idle: number,
	dead: boolean,
	lastShot: number,
}

local pools: { [string]: Pool.Pool } = {}
local vehicles: { [Model]: Record } = {}
local nextId = 0
local folder: Folder
local pads: { BasePart } = {}
local posts: { { label: TextLabel, side: string, type: string } } = {}

local DARK = Color3.fromRGB(35, 35, 35)

local function sideOf(player: Player): string?
	return if player.Team then player.Team:GetAttribute("Side") :: string? else nil
end

local function humanoidOf(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function recordOf(part: Instance): Record?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local rec = vehicles[model]
		if rec then
			return rec
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Model ------------------------------------------------------------------------------------------------
local function newPart(props): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Metal
	for k, v in props do
		p[k] = v
	end
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function build(typeId: string, def: VehicleConfig.VehicleDef, cf: CFrame): Record
	local s = def.size
	local model = Instance.new("Model")
	model.Name = def.name
	local hull = newPart({
		Name = "Hull",
		Size = s,
		CFrame = cf,
		Color = def.color,
		CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1),
	})
	hull.Parent = model
	model.PrimaryPart = hull
	local function deco(name: string, size: Vector3, offset: CFrame, color: Color3?, shape: Enum.PartType?): Part
		local p = newPart({
			Name = name,
			Size = size,
			CFrame = hull.CFrame * offset,
			Color = color or def.color,
			CanCollide = false,
			Massless = true,
		})
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		weld(hull, p)
		return p
	end

	if def.kind == "car" then
		deco("Nose", Vector3.new(s.X - 0.5, 1.6, 2), CFrame.new(0, s.Y / 2 + 0.8, -s.Z / 2 + 1), DARK)
		local axles = if s.Z >= 20 then { -0.35, 0, 0.35 } else { -0.32, 0.32 }
		for _, z in axles do
			for _, x in { -1, 1 } do
				deco(
					"Wheel",
					Vector3.new(1.2, 3.6, 3.6),
					CFrame.new(x * (s.X / 2 + 0.3), -s.Y / 2 + 1.8, z * s.Z),
					DARK,
					Enum.PartType.Cylinder
				)
			end
		end
		if def.supplies > 0 then
			deco("CargoBed", Vector3.new(s.X - 1, 0.6, s.Z * 0.55), CFrame.new(0, s.Y / 2 + 0.3, s.Z * 0.2), DARK)
		end
	else
		deco("Tail", Vector3.new(1.5, 1.5, 12), CFrame.new(0, 1, s.Z / 2 + 5))
		deco("TailRotor", Vector3.new(0.3, 5, 0.8), CFrame.new(1, 1.5, s.Z / 2 + 10.5), DARK)
		deco("Mast", Vector3.new(0.8, 4, 0.8), CFrame.new(0, s.Y / 2 + 2, 0), DARK)
		deco("Rotor", Vector3.new(32, 0.3, 1.4), CFrame.new(0, s.Y / 2 + 4.2, 0), DARK)
		deco("Rotor", Vector3.new(1.4, 0.3, 32), CFrame.new(0, s.Y / 2 + 4.2, 0), DARK)
		for _, x in { -1, 1 } do
			deco("Skid", Vector3.new(0.5, 0.5, s.Z), CFrame.new(x * (s.X / 2 - 0.5), -s.Y / 2 - 0.25, 0), DARK)
		end
	end

	local rec: any = {
		type = typeId,
		def = def,
		model = model,
		hull = hull,
		seats = {},
		idle = 0,
		dead = false,
		lastShot = 0,
	}

	if def.turret then
		local base = CFrame.new(0, s.Y / 2 + 0.8, -1)
		local ring = newPart({ Name = "Turret", Size = Vector3.new(3.5, 1.6, 3.5), Color = DARK, Massless = true })
		ring.CanCollide = false
		ring.CFrame = hull.CFrame * base
		ring.Parent = model
		local w = Instance.new("Weld")
		w.Name = "TurretWeld"
		w.Part0 = hull
		w.Part1 = ring
		w.C0 = base
		w.Parent = hull
		local barrelLength = if def.turret.antiArmor >= 2 then 6 else 4
		local barrel = newPart({
			Name = "Barrel",
			Size = Vector3.new(0.45, 0.45, barrelLength),
			CFrame = ring.CFrame * CFrame.new(0, 0.2, -1.75 - barrelLength / 2),
			Color = DARK,
			CanCollide = false,
			Massless = true,
		})
		barrel.Parent = model
		weld(ring, barrel)
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.Position = Vector3.new(0, 0, -barrelLength / 2)
		muzzle.Parent = barrel
		rec.turretWeld = w
		rec.turretBase = base
		rec.muzzle = muzzle
	end

	-- seats on the deck
	local top = s.Y / 2 + 0.5
	local function seat(role: string, offset: Vector3, vehicleSeat: boolean?)
		local p = Instance.new(if vehicleSeat then "VehicleSeat" else "Seat")
		p.Name = role
		p.Size = Vector3.new(2, 1, 2)
		p.Color = DARK
		p.TopSurface = Enum.SurfaceType.Smooth
		p.Massless = true
		p.CFrame = hull.CFrame * CFrame.new(offset)
		if vehicleSeat then
			local vs = p :: VehicleSeat
			vs.MaxSpeed = 0
			vs.Torque = 0
			vs.HeadsUpDisplay = false
		end
		p:SetAttribute("Role", role)
		p.Parent = model
		weld(hull, p)
		table.insert(rec.seats, p)
		return p
	end
	rec.driver = seat("driver", Vector3.new(-s.X / 4, top, -s.Z / 2 + 3.5), true)
	if def.turret then
		rec.gunner = seat("gunner", Vector3.new(0, top, 1.5))
	end
	local cols = if s.X >= 9 then 3 else 2
	local rows = math.max(1, math.ceil(def.passengers / cols))
	local z0 = if def.turret then 4 else 0
	local spacing = if rows > 1 then math.min(3, (s.Z / 2 - 1.5 - z0) / (rows - 1)) else 0
	for i = 1, def.passengers do
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		local x = (col - (cols - 1) / 2) * (s.X / cols)
		if def.turret == nil and def.passengers == 1 then
			x = s.X / 4
			z0 = -s.Z / 2 + 3.5
		end
		seat("passenger", Vector3.new(x, top, z0 + row * spacing))
	end

	-- physics: arcade drive/fly constraints, driven by the driver's client (it owns the assembly)
	local att = Instance.new("Attachment")
	att.Name = "Center"
	att.Parent = hull
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Drive"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	if def.kind == "car" then
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		lv.PrimaryTangentAxis = Vector3.xAxis
		lv.SecondaryTangentAxis = Vector3.zAxis
		lv.PlaneVelocity = Vector2.zero
	else
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.VectorVelocity = Vector3.zero
		lv.Enabled = false
		local align = Instance.new("AlignOrientation")
		align.Name = "Upright"
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.AlignType = Enum.AlignType.PrimaryAxisParallel
		align.PrimaryAxis = Vector3.yAxis
		align.Responsiveness = 15
		align.Attachment0 = att
		align.Parent = hull
	end
	lv.Parent = hull
	local av = Instance.new("AngularVelocity")
	av.Name = "Turn"
	av.Attachment0 = att
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.AngularVelocity = Vector3.zero
	av.Enabled = def.kind == "car"
	av.Parent = hull

	model:SetAttribute("Vehicle", typeId)
	model:SetAttribute("Health", def.health)
	model:SetAttribute("MaxHealth", def.health)
	model:SetAttribute("SupplyCap", def.supplies)
	model:SetAttribute("Supplies", 0)
	return rec
end

local function setForces(rec: Record)
	local mass = rec.hull.AssemblyMass
	local lv = rec.hull:FindFirstChild("Drive") :: LinearVelocity
	local av = rec.hull:FindFirstChild("Turn") :: AngularVelocity
	lv.MaxForce = mass * 400
	av.MaxTorque = mass * 4000
	local align = rec.hull:FindFirstChild("Upright") :: AlignOrientation?
	if align then
		align.MaxTorque = mass * 4000
	end
end

-- Occupants --------------------------------------------------------------------------------------------
local function occupants(rec: Record): { Humanoid }
	local list = {}
	for _, seat in rec.seats do
		if seat.Occupant then
			table.insert(list, seat.Occupant)
		end
	end
	return list
end

local function eject(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	local w = seat and seat:FindFirstChild("SeatWeld")
	if w then
		w:Destroy()
	end
	humanoid.Sit = false
end

local function onDriver(rec: Record)
	local occ = rec.driver.Occupant
	local pilot = occ and Players:GetPlayerFromCharacter(occ.Parent)
	local lv = rec.hull:FindFirstChild("Drive") :: LinearVelocity
	local av = rec.hull:FindFirstChild("Turn") :: AngularVelocity
	if rec.dead or not lv or not av then
		return
	end
	if rec.def.kind == "heli" then
		lv.VectorVelocity = Vector3.zero
		lv.Enabled = pilot ~= nil
		av.Enabled = pilot ~= nil
	else
		lv.PlaneVelocity = Vector2.zero
	end
	av.AngularVelocity = Vector3.zero
	pcall(function()
		rec.hull:SetNetworkOwner(pilot)
	end)
end

local function enter(player: Player, rec: Record)
	local humanoid = humanoidOf(player)
	if not humanoid or humanoid.Health <= 0 or rec.dead then
		return
	end
	if sideOf(player) ~= rec.side then
		MedicalService.notify(player, "That's an enemy vehicle", "error")
		return
	end
	if MedicalService.isIncapacitated(player) then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if
		not root
		or not root:IsA("BasePart")
		or (root.Position - rec.hull.Position).Magnitude > rec.def.size.Z / 2 + 6
	then
		return
	end
	-- first free seat after the current one (driver, gunner, then passengers)
	local current = table.find(rec.seats, humanoid.SeatPart)
	local n = #rec.seats
	for step = 1, n do
		local seat = rec.seats[((current or 0) + step - 1) % n + 1]
		if not seat.Occupant then
			if humanoid.SeatPart then
				eject(humanoid)
				task.wait()
			end
			seat:Sit(humanoid)
			return
		end
	end
	MedicalService.notify(player, "No free seats", "error")
end

-- Lifecycle --------------------------------------------------------------------------------------------
local function release(rec: Record)
	local pool = pools[rec.side]
	if pool then
		Pool.release(pool, rec.type, rec.id)
	end
end

local function despawn(rec: Record)
	if rec.dead then
		return
	end
	rec.dead = true
	release(rec)
	for _, humanoid in occupants(rec) do
		eject(humanoid)
	end
	vehicles[rec.model] = nil
	rec.model:Destroy()
end

local function destroy(rec: Record)
	if rec.dead then
		return
	end
	rec.dead = true
	release(rec)
	local explosion = Instance.new("Explosion")
	explosion.Position = rec.hull.Position
	explosion.BlastRadius = 14
	explosion.BlastPressure = 0
	explosion.DestroyJointPercentage = 0
	explosion.Parent = workspace
	for _, humanoid in occupants(rec) do
		local char = humanoid.Parent
		eject(humanoid)
		if char and MedicalService.get(char) then
			MedicalService.applyDamage(char, nil, VehicleConfig.OccupantBlastDamage, "Explosive")
		end
	end
	for _, d in rec.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = Color3.fromRGB(30, 28, 26)
			d.Material = Enum.Material.CorrodedMetal
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				d.Disabled = true
			end
		elseif d:IsA("ProximityPrompt") or d:IsA("Constraint") then
			d:Destroy()
		end
	end
	rec.model:SetAttribute("Health", 0)
	rec.hull.Anchored = true
	task.delay(VehicleConfig.WreckSeconds, function()
		vehicles[rec.model] = nil
		rec.model:Destroy()
	end)
end

function VehicleService.damage(model: Model, amount: number)
	local rec = vehicles[model]
	if not rec or rec.dead or amount <= 0 then
		return
	end
	local hp = ((model:GetAttribute("Health") :: number?) or 0) - amount
	model:SetAttribute("Health", math.max(0, hp))
	if hp <= 0 then
		destroy(rec)
	end
end

local function friendly(shooter: Player, rec: Record): boolean
	return not WeaponConfig.FriendlyFire and sideOf(shooter) == rec.side
end

local function addPrompt(rec: Record)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Get in / switch seat"
	prompt.ObjectText = rec.def.name
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = rec.def.size.Z / 2 + 6
	prompt.Parent = rec.hull
	prompt.Triggered:Connect(function(player)
		enter(player, rec)
	end)
end

local function padBlocked(pad: BasePart): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local box = pad.CFrame * CFrame.new(0, 7, 0)
	return #workspace:GetPartBoundsInBox(box, Vector3.new(pad.Size.X, 12, pad.Size.Z), params) > 0
end

local function spawnVehicle(player: Player, pad: BasePart, typeId: string)
	local def = VehicleConfig.Types[typeId]
	local side = pad:GetAttribute("Side")
	if not def or not player.Character or sideOf(player) ~= side or MedicalService.isIncapacitated(player) then
		return
	end
	if padBlocked(pad) then
		MedicalService.notify(player, "Move the vehicle off the pad first", "error")
		return
	end
	nextId += 1
	local ok, why = Pool.claim(pools[side], typeId, nextId, os.clock(), def.cooldown)
	if not ok then
		MedicalService.notify(player, def.name .. ": " .. (why or "not available"), "error")
		return
	end
	local cf = pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + def.size.Y / 2 + 0.3, 0)
	local rec = build(typeId, def, cf)
	rec.id = nextId
	rec.side = side
	rec.model:SetAttribute("Side", side)
	rec.model.Parent = folder
	setForces(rec)
	vehicles[rec.model] = rec
	addPrompt(rec)
	for _, seat in rec.seats do
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			rec.idle = 0
			local occ = seat.Occupant
			if occ then
				occ:UnequipTools()
			end
			if seat == rec.driver then
				onDriver(rec)
			end
		end)
	end
	if VehicleService.onSpawned then
		VehicleService.onSpawned(rec.model, def)
	end
	MedicalService.notify(player, def.name .. " deployed", "result")
end

-- Motor pool posts next to each pad, one per vehicle type.
local function setupPad(pad: BasePart)
	if table.find(pads, pad) then
		return
	end
	table.insert(pads, pad)
	local side = pad:GetAttribute("Side")
	if not pools[side] then
		warn("[Vehicles] VehiclePad " .. pad:GetFullName() .. " needs a Side attribute (A or B)")
		return
	end
	local ids = {}
	for id in VehicleConfig.Types do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return VehicleConfig.Types[a].order < VehicleConfig.Types[b].order
	end)
	local spacing = pad.Size.Z / #ids
	for i, id in ids do
		local def = VehicleConfig.Types[id]
		local post = newPart({
			Name = "MotorPool" .. id,
			Anchored = true,
			Size = Vector3.new(1.2, 4, 1.2),
			Color = Color3.fromRGB(60, 62, 66),
			CFrame = pad.CFrame
				* CFrame.new(-pad.Size.X / 2 - 3, 2 + pad.Size.Y / 2, -pad.Size.Z / 2 + (i - 0.5) * spacing),
		})
		post.Parent = pad.Parent
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Deploy " .. def.name
		prompt.ObjectText = "Motor pool"
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 6
		prompt.RequiresLineOfSight = false
		prompt.Parent = post
		prompt.Triggered:Connect(function(player)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if
				root
				and root:IsA("BasePart")
				and (root.Position - post.Position).Magnitude <= prompt.MaxActivationDistance
			then
				spawnVehicle(player, pad, id)
			end
		end)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(170, 40)
		gui.StudsOffset = Vector3.new(0, 3.5, 0)
		gui.MaxDistance = 60
		gui.Parent = post
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.3
		label.Parent = gui
		table.insert(posts, { label = label, side = side, type = id })
	end
end

local function updatePosts()
	local now = os.clock()
	for _, p in posts do
		local def = VehicleConfig.Types[p.type]
		local alive, ready, wait = Pool.status(pools[p.side], p.type, now)
		local status = if ready > 0
			then "READY"
			elseif alive >= def.cap then "ALL DEPLOYED"
			else string.format("%d:%02d", (wait or 0) // 60, math.ceil(wait or 0) % 60)
		p.label.Text = string.format("%s  %d/%d\n%s", def.name, alive, def.cap, status)
		p.label.TextColor3 = if ready > 0 then Color3.fromRGB(120, 230, 130) else Color3.fromRGB(230, 200, 120)
	end
end

-- Mounted guns -----------------------------------------------------------------------------------------
local function tracer(from: Vector3, to: Vector3)
	local len = (to - from).Magnitude
	if len < 0.5 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 200, 120)
	p.Size = Vector3.new(0.12, 0.12, len)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = folder
	Debris:AddItem(p, 0.05)
end

local function onGun(player: Player, action: any, model: any, dir: any)
	local rec = if typeof(model) == "Instance" then vehicles[model :: any] else nil
	if not rec or rec.dead or not rec.def.turret or not rec.gunner then
		return
	end
	local humanoid = humanoidOf(player)
	if not humanoid or humanoid.SeatPart ~= rec.gunner or MedicalService.isIncapacitated(player) then
		return
	end
	if typeof(dir) ~= "Vector3" or dir ~= dir or dir.Magnitude < 0.5 then
		return
	end
	dir = dir.Unit
	local rel = rec.hull.CFrame:VectorToObjectSpace(dir)
	if rec.turretWeld then
		rec.turretWeld.C0 = rec.turretBase * CFrame.Angles(0, math.atan2(-rel.X, -rel.Z), 0)
	end
	if action ~= "fire" then
		return
	end
	local t = rec.def.turret
	local now = os.clock()
	if now - rec.lastShot < 60 / t.rpm * 0.85 then
		return
	end
	rec.lastShot = now
	if rel.Y < -0.4 or rel.Y > 0.75 then
		return -- outside the gun's elevation limits
	end
	local spread = math.rad(t.spread)
	local shot = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(
		(math.random() - 0.5) * 2 * spread,
		(math.random() - 0.5) * 2 * spread,
		0
	)).LookVector
	local origin = if rec.muzzle then rec.muzzle.WorldPosition else rec.hull.Position
	local exclude: { Instance } = { rec.model }
	for _, h in occupants(rec) do
		if h.Parent then
			table.insert(exclude, h.Parent)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(origin, shot * t.range, params)
	tracer(origin, if hit then hit.Position else origin + shot * t.range)
	if not hit then
		return
	end
	local char = WeaponService.characterFromPart(hit.Instance)
	if char then
		WeaponService.applyHit(player, char, hit.Instance, t.damage, { damageType = "Bullet" })
		return
	end
	local target = recordOf(hit.Instance)
	if target and not friendly(player, target) then
		VehicleService.damage(target.model, t.damage * t.antiArmor)
	end
end

-- Init -------------------------------------------------------------------------------------------------
function VehicleService.reset()
	for _, rec in vehicles do
		despawn(rec)
	end
	for _, pool in pools do
		Pool.reset(pool)
	end
end

function VehicleService.init()
	if not VehicleConfig.Enabled then
		return
	end
	for key in GameConfig.Sides do
		pools[key] = Pool.new(VehicleConfig.Types)
	end
	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace

	WeaponService.hooks.vehicleHit = function(shooter: Player, part: Instance, damage: number): boolean
		local rec = recordOf(part)
		if not rec then
			return false
		end
		if not friendly(shooter, rec) then
			VehicleService.damage(rec.model, damage * rec.def.armor)
		end
		return true
	end
	Remotes.get("Vehicle").OnServerEvent:Connect(onGun)

	for _, pad in CollectionService:GetTagged("VehiclePad") do
		if pad:IsA("BasePart") then
			setupPad(pad)
		end
	end
	CollectionService:GetInstanceAddedSignal("VehiclePad"):Connect(function(pad)
		if pad:IsA("BasePart") then
			setupPad(pad)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			updatePosts()
			for model, rec in vehicles do
				if rec.dead then
					continue
				end
				if not model.Parent or not rec.hull.Parent then
					rec.dead = true
					release(rec)
					vehicles[model] = nil
				elseif #occupants(rec) > 0 then
					rec.idle = 0
				else
					rec.idle += 1
					if rec.idle >= VehicleConfig.IdleDespawn then
						despawn(rec)
					end
				end
			end
		end
	end)
end

return VehicleService
