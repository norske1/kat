--!strict
-- Builds weapon models from parts (no meshes needed). Model space: the grip is at the origin,
-- the barrel points along -Z and +Y is up. The root part is named "Handle" so it can be used as a
-- Tool handle; the "Muzzle" attachment marks where shots and flashes come from.
-- To use your own meshes, return a Model with the same layout (Handle at the grip + a Muzzle attachment).
local Models = {}

local METAL = Color3.fromRGB(38, 39, 42)
local POLYMER = Color3.fromRGB(28, 29, 31)
local TAN = Color3.fromRGB(150, 128, 95)

type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
}

local function makePart(spec: PartSpec, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = spec.name
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Color = spec.color or METAL
	part.Material = spec.material or Enum.Material.Metal
	part.Shape = spec.shape or Enum.PartType.Block
	part.Transparency = spec.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Anchored = false
	part.Parent = parent
	return part
end

-- Cylinder parts run along X, so rotate them to lie along Z.
local function alongZ(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(90), 0)
end

local function tilt(x: number, y: number, z: number, degrees: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(degrees), 0, 0)
end

local BUILDERS: { [string]: { PartSpec } } = {
	Rifle = {
		{ name = "Receiver", size = Vector3.new(0.22, 0.3, 1.1), cframe = CFrame.new(0, 0.22, -0.3) },
		{
			name = "Handguard",
			size = Vector3.new(0.24, 0.24, 0.85),
			cframe = CFrame.new(0, 0.23, -1.25),
			color = POLYMER,
		},
		{
			name = "Barrel",
			size = Vector3.new(0.75, 0.08, 0.08),
			cframe = alongZ(0, 0.25, -1.95),
			shape = Enum.PartType.Cylinder,
		},
		{ name = "FlashHider", size = Vector3.new(0.12, 0.12, 0.16), cframe = CFrame.new(0, 0.25, -2.38) },
		{ name = "FrontSight", size = Vector3.new(0.05, 0.16, 0.05), cframe = CFrame.new(0, 0.4, -1.75) },
		{ name = "BufferTube", size = Vector3.new(0.1, 0.1, 0.45), cframe = CFrame.new(0, 0.28, 0.45) },
		{ name = "Stock", size = Vector3.new(0.16, 0.32, 0.5), cframe = CFrame.new(0, 0.18, 0.75), color = POLYMER },
		{
			name = "PistolGrip",
			size = Vector3.new(0.15, 0.42, 0.2),
			cframe = tilt(0, -0.08, 0.02, -20),
			color = POLYMER,
			material = Enum.Material.SmoothPlastic,
		},
		{
			name = "Magazine",
			size = Vector3.new(0.14, 0.5, 0.24),
			cframe = tilt(0, -0.14, -0.5, 10),
			color = TAN,
			material = Enum.Material.SmoothPlastic,
		},
		{ name = "Optic", size = Vector3.new(0.13, 0.15, 0.28), cframe = CFrame.new(0, 0.45, -0.3), color = POLYMER },
		{
			name = "OpticLens",
			size = Vector3.new(0.09, 0.09, 0.02),
			cframe = CFrame.new(0, 0.46, -0.15),
			color = Color3.fromRGB(255, 40, 40),
			material = Enum.Material.Neon,
			transparency = 0.3,
		},
	},
	Pistol = {
		{ name = "Slide", size = Vector3.new(0.15, 0.2, 0.78), cframe = CFrame.new(0, 0.2, -0.28) },
		{
			name = "Frame",
			size = Vector3.new(0.14, 0.12, 0.62),
			cframe = CFrame.new(0, 0.06, -0.26),
			color = POLYMER,
			material = Enum.Material.SmoothPlastic,
		},
		{
			name = "Grip",
			size = Vector3.new(0.14, 0.45, 0.22),
			cframe = tilt(0, -0.12, 0.03, -15),
			color = POLYMER,
			material = Enum.Material.SmoothPlastic,
		},
		{ name = "RearSight", size = Vector3.new(0.1, 0.04, 0.04), cframe = CFrame.new(0, 0.32, 0.05) },
		{ name = "FrontSight", size = Vector3.new(0.03, 0.04, 0.03), cframe = CFrame.new(0, 0.32, -0.62) },
		{
			name = "Barrel",
			size = Vector3.new(0.05, 0.07, 0.07),
			cframe = alongZ(0, 0.2, -0.68),
			shape = Enum.PartType.Cylinder,
		},
	},
	Shotgun = {
		{ name = "Receiver", size = Vector3.new(0.22, 0.3, 0.9), cframe = CFrame.new(0, 0.2, -0.25) },
		{
			name = "Barrel",
			size = Vector3.new(1.6, 0.11, 0.11),
			cframe = alongZ(0, 0.3, -1.5),
			shape = Enum.PartType.Cylinder,
		},
		{
			name = "Tube",
			size = Vector3.new(1.2, 0.1, 0.1),
			cframe = alongZ(0, 0.15, -1.3),
			shape = Enum.PartType.Cylinder,
		},
		{
			name = "Pump",
			size = Vector3.new(0.2, 0.18, 0.6),
			cframe = CFrame.new(0, 0.15, -1.05),
			color = Color3.fromRGB(90, 60, 35),
			material = Enum.Material.Wood,
		},
		{
			name = "Stock",
			size = Vector3.new(0.17, 0.34, 0.85),
			cframe = tilt(0, 0.1, 0.62, 8),
			color = Color3.fromRGB(90, 60, 35),
			material = Enum.Material.Wood,
		},
		{
			name = "PistolGrip",
			size = Vector3.new(0.15, 0.36, 0.2),
			cframe = tilt(0, -0.06, 0.05, -25),
			color = Color3.fromRGB(90, 60, 35),
			material = Enum.Material.Wood,
		},
		{ name = "Bead", size = Vector3.new(0.04, 0.04, 0.04), cframe = CFrame.new(0, 0.38, -2.25) },
	},
}

local MUZZLE: { [string]: Vector3 } = {
	Rifle = Vector3.new(0, 0.25, -2.48),
	Pistol = Vector3.new(0, 0.2, -0.72),
	Shotgun = Vector3.new(0, 0.3, -2.32),
}

function Models.kinds(): { string }
	local list = {}
	for kind in BUILDERS do
		table.insert(list, kind)
	end
	return list
end

-- Returns a Model whose PrimaryPart "Handle" sits at the grip. Parts are welded, unanchored and massless.
function Models.build(kind: string): Model
	local specs = BUILDERS[kind] or BUILDERS.Rifle
	local model = Instance.new("Model")
	model.Name = kind
	local handle = makePart({
		name = "Handle",
		size = Vector3.new(0.2, 0.2, 0.2),
		cframe = CFrame.new(),
		transparency = 1,
	}, model)
	model.PrimaryPart = handle
	for _, spec in specs do
		local part = makePart(spec, model)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = MUZZLE[kind] or MUZZLE.Rifle
	muzzle.Parent = handle
	return model
end

-- Anchored copy for display on racks.
function Models.display(kind: string, cframe: CFrame): Model
	local model = Models.build(kind)
	model:PivotTo(cframe)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanQuery = false
		end
	end
	return model
end

return Models
