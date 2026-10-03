local Models = {}

local METAL = Enum.Material.Metal
local POLYMER = Enum.Material.SmoothPlastic
local DARK = Color3.fromRGB(35, 39, 40)
local STEEL = Color3.fromRGB(66, 72, 75)
local EDGE = Color3.fromRGB(105, 112, 111)
local TAN = Color3.fromRGB(113, 103, 80)

local function addPart(tool, handle, name, size, offset, color, material, moving)
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Size = size
	piece.CFrame = handle.CFrame * offset
	piece.Color = color
	piece.Material = material
	piece.CanCollide = false
	piece.CanTouch = false
	piece.CanQuery = false
	piece.Massless = true
	piece.CastShadow = true
	piece.Parent = tool

	if moving then
		local motor = Instance.new("Motor6D")
		motor.Name = name .. "Motor"
		motor.Part0 = handle
		motor.Part1 = piece
		motor.C0 = offset
		motor.Parent = handle
	else
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = piece
		weld.Parent = piece
	end
	return piece
end

local function block(tool, handle, name, size, x, y, z, color, material, moving)
	return addPart(tool, handle, name, size, CFrame.new(x, y, z), color, material or METAL, moving)
end

local function sound(handle, name, id, volume, speed)
	local effect = Instance.new("Sound")
	effect.Name = name
	effect.SoundId = id or ""
	effect.Volume = volume
	effect.PlaybackSpeed = speed
	effect.RollOffMaxDistance = 170
	effect.Parent = handle
end

local function createTool(name, kind, ids)
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = "Visual and audio asset; no damage or ammunition logic"
	tool:SetAttribute("WeaponAsset", kind)
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -0.25, 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.32, 0.78, 0.32)
	handle.Color = DARK
	handle.Material = POLYMER
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Parent = handle

	sound(handle, "Fire", ids[kind .. "Fire"], kind == "carbine" and 1 or 0.85, 1)
	sound(handle, "Reload", ids.reload, 0.65, 1)
	sound(handle, "DryFire", ids.dryFire, 0.55, 1)
	sound(handle, "Equip", ids.equip, 0.45, 1)
	return tool, handle, muzzle
end

local function carbine(ids)
	local tool, handle, muzzle = createTool("FieldCarbine", "carbine", ids)
	tool.Grip = CFrame.new(0, -0.3, 0.15)
	block(tool, handle, "Receiver", Vector3.new(0.72, 0.55, 1.55), 0, 0.85, -0.28, STEEL)
	block(tool, handle, "UpperRail", Vector3.new(0.46, 0.09, 1.78), 0, 1.18, -0.34, DARK)
	block(tool, handle, "EjectionPort", Vector3.new(0.025, 0.15, 0.32), 0.38, 0.9, -0.35, DARK)
	block(tool, handle, "DustCover", Vector3.new(0.025, 0.1, 0.45), -0.38, 0.83, -0.28, EDGE)
	block(tool, handle, "Handguard", Vector3.new(0.55, 0.45, 1.25), 0, 0.87, -1.61, TAN, POLYMER)
	for _, z in { -1.19, -1.49, -1.79, -2.09 } do
		block(tool, handle, "GuardVent", Vector3.new(0.57, 0.085, 0.14), 0, 0.92, z, DARK)
	end
	block(tool, handle, "Barrel", Vector3.new(0.17, 0.17, 1.28), 0, 0.87, -2.48, DARK)
	block(tool, handle, "MuzzleBrake", Vector3.new(0.3, 0.26, 0.3), 0, 0.87, -3.16, STEEL)
	block(tool, handle, "MuzzleOpening", Vector3.new(0.15, 0.13, 0.012), 0, 0.87, -3.319, DARK)
	muzzle.Position = Vector3.new(0, 0.87, -3.34)
	block(tool, handle, "StockTube", Vector3.new(0.22, 0.23, 0.82), 0, 0.86, 0.88, STEEL)
	block(tool, handle, "Stock", Vector3.new(0.55, 0.5, 0.85), 0, 0.75, 1.56, TAN, POLYMER)
	block(tool, handle, "ButtPad", Vector3.new(0.6, 0.66, 0.11), 0, 0.72, 2.03, DARK, POLYMER)
	block(tool, handle, "TriggerGuard", Vector3.new(0.37, 0.07, 0.52), 0, 0.41, -0.06, STEEL)
	block(tool, handle, "Trigger", Vector3.new(0.07, 0.21, 0.08), 0, 0.48, -0.22, DARK, METAL, true)
	local magazine = block(tool, handle, "Magazine", Vector3.new(0.37, 0.8, 0.37), 0, 0.12, -0.71, TAN, POLYMER, true)
	block(tool, magazine, "MagazineBase", Vector3.new(0.42, 0.1, 0.43), 0, -0.46, 0, DARK)
	block(tool, handle, "ChargingBolt", Vector3.new(0.42, 0.11, 0.29), 0, 1.23, 0.25, DARK, METAL, true)
	block(tool, handle, "RearSight", Vector3.new(0.41, 0.26, 0.15), 0, 1.4, 0.33, DARK)
	block(tool, handle, "FrontSight", Vector3.new(0.35, 0.3, 0.13), 0, 1.23, -2.55, DARK)
	return tool
end

local function pistol(ids)
	local tool, handle, muzzle = createTool("ServicePistol", "pistol", ids)
	block(tool, handle, "GripPanelLeft", Vector3.new(0.03, 0.6, 0.3), -0.18, -0.07, 0, TAN, POLYMER)
	block(tool, handle, "GripPanelRight", Vector3.new(0.03, 0.6, 0.3), 0.18, -0.07, 0, TAN, POLYMER)
	block(tool, handle, "Frame", Vector3.new(0.45, 0.25, 1.42), 0, 0.41, -0.47, DARK, POLYMER)
	local slide = block(tool, handle, "Slide", Vector3.new(0.51, 0.27, 1.38), 0, 0.68, -0.48, STEEL, METAL, true)
	block(tool, slide, "SlideTop", Vector3.new(0.4, 0.045, 1.15), 0, 0.16, 0, DARK)
	block(tool, slide, "MuzzleFace", Vector3.new(0.39, 0.2, 0.07), 0, -0.02, -0.71, DARK)
	block(tool, slide, "Bore", Vector3.new(0.13, 0.13, 0.012), 0, 0, -0.75, EDGE)
	muzzle.Position = Vector3.new(0, 0.68, -1.26)
	block(tool, slide, "RearSight", Vector3.new(0.35, 0.12, 0.11), 0, 0.27, 0.56, DARK)
	block(tool, slide, "FrontSight", Vector3.new(0.18, 0.1, 0.09), 0, 0.25, -0.56, DARK)
	block(tool, handle, "TriggerGuardFront", Vector3.new(0.4, 0.24, 0.07), 0, 0.13, -0.42, DARK)
	block(tool, handle, "TriggerGuardBottom", Vector3.new(0.4, 0.07, 0.38), 0, 0.02, -0.24, DARK)
	block(tool, handle, "Trigger", Vector3.new(0.08, 0.18, 0.07), 0, 0.22, -0.22, STEEL, METAL, true)
	local magazine = block(tool, handle, "Magazine", Vector3.new(0.25, 0.67, 0.24), 0, -0.12, 0, STEEL, METAL, true)
	block(tool, magazine, "MagazineBase", Vector3.new(0.36, 0.09, 0.34), 0, -0.37, 0, DARK)
	return tool
end

local builders = { carbine = carbine, pistol = pistol }
local names = { carbine = "FieldCarbine", pistol = "ServicePistol" }

function Models.create(kind, parent, soundIds)
	assert(builders[kind], "Unknown weapon kind: " .. tostring(kind))
	assert(parent and parent:IsA("Instance"), "A Roblox parent instance is required")
	local existing = parent:FindFirstChild(names[kind])
	if existing then
		assert(
			existing:IsA("Tool") and existing:GetAttribute("WeaponAsset") == kind,
			"Name already in use: " .. names[kind]
		)
		return existing
	end
	local tool = builders[kind](soundIds or {})
	tool.Parent = parent
	return tool
end

function Models.createAll(parent, soundIds)
	return Models.create("carbine", parent, soundIds), Models.create("pistol", parent, soundIds)
end

return Models
