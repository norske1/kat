--!nonstrict
-- Weapon lockers: an open cabinet with one gun per shelf. Click a gun to take and equip it, click the ammo
-- box to resupply. Tag any part "WeaponLocker" to build one there (its front faces the part's LookVector);
-- with WeaponConfig.AutoSpawnLocker a locker is built next to the spawn if none is tagged.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Weapons = Medical:WaitForChild("Weapons")
local WeaponConfig = require(Weapons.Config)
local Models = require(Weapons.Models)
local Remotes = require(Medical.Remotes)
local Sounds = require(Medical.Sounds)
local MedicalService = require(script.Parent.Parent.MedicalService)

local Locker = {}

local WIDTH, HEIGHT, DEPTH = 5, 7, 2
local BODY = Color3.fromRGB(62, 70, 56)
local TRIM = Color3.fromRGB(40, 44, 38)
local SHELVES = { 2.3, 4.6 } -- shelf heights; compartments are [0.3, 2.3], [2.3, 4.6], [4.6, 6.9]
local COMPARTMENTS = { { 4.6, 6.9 }, { 2.3, 4.6 }, { 0.3, 2.3 } } -- top to bottom

local slots: { [BasePart]: string } = {}
local lastTake: { [Player]: number } = {}

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?
)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color or BODY
	part.Material = material or Enum.Material.DiamondPlate
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function label(part: BasePart, text: string, textSize: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.3
	gui.Parent = part
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Font = Enum.Font.GothamBold
	text_.TextColor3 = Color3.fromRGB(235, 230, 200)
	text_.TextSize = textSize or 14
	text_.Text = text
	text_.Parent = gui
end

-- Centres a display model on a point (its grip is not its middle).
local function centre(model: Model, at: Vector3)
	local box = model:GetBoundingBox()
	model:PivotTo(CFrame.new(at - box.Position) * model:GetPivot())
end

local function addSlot(locker: Model, base: CFrame, item: string, x: number, width: number, range: { number })
	local def = WeaponConfig.get(item)
	local bottom, top = range[1], range[2]
	local middle = base * CFrame.new(x, (bottom + top) / 2, 0.15)
	local slot = Instance.new("Model")
	slot.Name = "Slot_" .. item
	slot.Parent = locker

	local display
	if def then
		-- barrel pointing to the locker's right, gun upright as if hung on the back panel
		display = Models.display(def.model, middle * CFrame.Angles(0, math.rad(-90), 0), def.mesh)
		centre(display, middle.Position)
	else
		display = Instance.new("Model")
		local box = block(
			display,
			"AmmoBox",
			Vector3.new(1.4, 0.8, 1),
			base * CFrame.new(x, bottom + 0.4, 0.1),
			Color3.fromRGB(70, 82, 48),
			Enum.Material.Metal
		)
		box.CanQuery = false
		local lid = block(
			display,
			"Lid",
			Vector3.new(1.45, 0.1, 1.05),
			box.CFrame * CFrame.new(0, 0.45, 0),
			Color3.fromRGB(56, 66, 38),
			Enum.Material.Metal
		)
		lid.CanQuery = false
		local stencil = block(
			display,
			"Stencil",
			Vector3.new(1, 0.35, 0.02),
			box.CFrame * CFrame.new(0, 0, -0.51),
			Color3.fromRGB(70, 82, 48),
			Enum.Material.Metal
		)
		stencil.CanQuery = false
		label(stencil, "AMMO", 16)
	end
	display.Name = "Display"
	display.Parent = slot

	local hitbox = block(
		slot,
		"Hitbox",
		Vector3.new(width, top - bottom - 0.1, DEPTH - 0.4),
		middle,
		nil,
		Enum.Material.SmoothPlastic
	)
	hitbox.Transparency = 1
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CastShadow = false
	hitbox:SetAttribute("LockerItem", item)
	hitbox:SetAttribute("LockerLabel", if def then "Equip " .. def.name else "Resupply ammo")
	local link = Instance.new("ObjectValue")
	link.Name = "Display"
	link.Value = display
	link.Parent = hitbox
	slots[hitbox] = item

	local plate = block(
		slot,
		"Label",
		Vector3.new(math.min(width - 0.4, 1.6), 0.28, 0.05),
		base * CFrame.new(x, bottom + 0.16, -DEPTH / 2 + 0.12),
		TRIM,
		Enum.Material.Metal
	)
	plate.CanQuery = false
	label(plate, if def then def.name else "AMMO", 12)
end

function Locker.build(base: CFrame, parent: Instance): Model
	local locker = Instance.new("Model")
	locker.Name = "WeaponLocker"
	CollectionService:AddTag(locker, "Arsenal")
	block(locker, "Back", Vector3.new(WIDTH, HEIGHT, 0.2), base * CFrame.new(0, HEIGHT / 2, DEPTH / 2 - 0.1))
	block(locker, "Left", Vector3.new(0.2, HEIGHT, DEPTH), base * CFrame.new(-WIDTH / 2 + 0.1, HEIGHT / 2, 0))
	block(locker, "Right", Vector3.new(0.2, HEIGHT, DEPTH), base * CFrame.new(WIDTH / 2 - 0.1, HEIGHT / 2, 0))
	block(locker, "Top", Vector3.new(WIDTH, 0.2, DEPTH), base * CFrame.new(0, HEIGHT - 0.1, 0))
	block(locker, "Bottom", Vector3.new(WIDTH, 0.3, DEPTH), base * CFrame.new(0, 0.15, 0), TRIM)
	for i, y in SHELVES do
		block(
			locker,
			"Shelf" .. i,
			Vector3.new(WIDTH - 0.4, 0.12, DEPTH - 0.2),
			base * CFrame.new(0, y, 0.1),
			TRIM,
			Enum.Material.Metal
		)
	end
	-- doors swung open
	for _, side in { -1, 1 } do
		local hinge = base * CFrame.new(side * WIDTH / 2, HEIGHT / 2, -DEPTH / 2)
		local door = block(
			locker,
			"Door",
			Vector3.new(WIDTH / 2, HEIGHT - 0.1, 0.12),
			hinge * CFrame.Angles(0, math.rad(-side * 115), 0) * CFrame.new(-side * WIDTH / 4, 0, -0.06)
		)
		for v = 0, 2 do
			local vent = block(
				locker,
				"Vent",
				Vector3.new(WIDTH / 2 - 0.8, 0.08, 0.02),
				door.CFrame * CFrame.new(0, HEIGHT / 2 - 0.8 - v * 0.25, -0.07),
				TRIM,
				Enum.Material.Metal
			)
			vent.CanQuery = false
		end
	end
	local sign = block(
		locker,
		"Sign",
		Vector3.new(WIDTH * 0.8, 0.55, 0.1),
		base * CFrame.new(0, HEIGHT + 0.3, DEPTH / 2 - 0.3),
		TRIM,
		Enum.Material.Metal
	)
	label(sign, "WEAPON LOCKER - CLICK TO EQUIP", 14)

	local compartment = 0
	local bottomRow = {}
	for _, item in WeaponConfig.LockerItems do
		local def = WeaponConfig.get(item)
		if def and def.hold == "Rifle" and compartment < #COMPARTMENTS - 1 then
			compartment += 1
			addSlot(locker, base, item, 0, WIDTH - 0.6, COMPARTMENTS[compartment])
		else
			table.insert(bottomRow, item)
		end
	end
	-- pistols and the ammo box share the bottom compartment
	local count = #bottomRow
	local cell = (WIDTH - 0.6) / math.max(count, 1)
	for i, item in bottomRow do
		addSlot(locker, base, item, -(WIDTH - 0.6) / 2 + cell * (i - 0.5), cell, COMPARTMENTS[#COMPARTMENTS])
	end
	locker.Parent = parent
	return locker
end

local function fromAnchor(anchor: Instance)
	if not anchor:IsA("BasePart") or anchor:GetAttribute("LockerBuilt") then
		return
	end
	local part = anchor :: BasePart
	part:SetAttribute("LockerBuilt", true)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	Locker.build(part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0), part)
end

local function autoSpawn()
	local spawnPart = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = if spawnPart then spawnPart.CFrame else CFrame.new(0, 0.5, 0)
	local offset = if spawnPart then spawnPart.Size.X / 2 + 6 else 10
	local spot = (origin * CFrame.new(-offset, 0, 0)).Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(spot + Vector3.new(0, 25, 0), Vector3.new(0, -60, 0), params)
	local floor = if hit then hit.Position else Vector3.new(spot.X, origin.Position.Y - 0.5, spot.Z)
	local facing = Vector3.new(origin.Position.X, floor.Y, origin.Position.Z)
	local base = if (facing - floor).Magnitude > 0.1 then CFrame.lookAt(floor, facing) else CFrame.new(floor)
	Locker.build(base, workspace)
end

local function onTake(WeaponService, player: Player, slot: any)
	if
		typeof(slot) ~= "Instance"
		or not slot:IsA("BasePart")
		or not slots[slot]
		or not slot:IsDescendantOf(workspace)
	then
		return
	end
	local now = os.clock()
	if now - (lastTake[player] or 0) < 0.4 then
		return
	end
	lastTake[player] = now
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - slot.Position).Magnitude > WeaponConfig.LockerReach + 3 then
		return
	end
	local item = slots[slot]
	if item == "Ammo" then
		WeaponService.refill(player)
		Sounds.play("MagIn", slot)
		MedicalService.notify(player, "Ammo resupplied", "result")
		return
	end
	if not WeaponService.canUse(player) then
		MedicalService.notify(player, "You can't take a weapon right now", "error")
		return
	end
	local def = WeaponConfig.get(item)
	if not def then
		return
	end
	local given = WeaponService.equip(player, item)
	MedicalService.notify(
		player,
		if given then def.name .. " equipped" else def.name .. " equipped, ammo refilled",
		"result"
	)
end

function Locker.init(WeaponService)
	Remotes.get("LockerTake").OnServerEvent:Connect(function(player, slot)
		onTake(WeaponService, player, slot)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTake[player] = nil
	end)
	local anchors = CollectionService:GetTagged("WeaponLocker")
	for _, anchor in anchors do
		fromAnchor(anchor)
	end
	CollectionService:GetInstanceAddedSignal("WeaponLocker"):Connect(fromAnchor)
	if #anchors == 0 and WeaponConfig.AutoSpawnLocker then
		task.defer(autoSpawn)
	end
end

return Locker
