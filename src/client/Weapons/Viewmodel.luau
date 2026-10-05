--!nonstrict
-- First-person viewmodel: a local copy of the equipped gun plus gloved arms (two-bone IK from fixed
-- shoulders to the grip and the support hand), drawn in front of the camera. Only the local player sees it;
-- everyone else sees the real Tool on the character with the third-person poses.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local WeaponConfig = require(Medical:WaitForChild("Weapons").Config)

local Viewmodel = {}

local UPPER, FORE = 1.25, 1.3 -- arm segment lengths (studs)
local RIGHT_SHOULDER = Vector3.new(0.8, -1.35, 0.55) -- camera space
local LEFT_SHOULDER = Vector3.new(-0.8, -1.35, 0.55)
local GRIP = CFrame.new(0, -0.1, 0.06) -- right palm relative to the gun's grip point

type State = {
	model: Model,
	parts: { BasePart },
	offsets: { CFrame },
	arms: { BasePart },
	aim: CFrame,
	support: CFrame,
	muzzleOffset: CFrame,
	muzzle: Attachment?,
	gun: CFrame,
}

local vm: State? = nil

local function prepare(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.LocalTransparencyModifier = 0
end

local function armPart(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	prepare(part)
	part.Parent = model
	return part
end

local function attachmentCFrame(handle: BasePart, name: string, fallback: CFrame): CFrame
	local attachment = handle:FindFirstChild(name)
	return if attachment and attachment:IsA("Attachment") then attachment.CFrame else fallback
end

function Viewmodel.destroy()
	if vm then
		vm.model:Destroy()
		vm = nil
	end
end

-- Builds the viewmodel from the equipped tool. Returns false if the tool has no gun model.
function Viewmodel.create(tool: Tool): boolean
	Viewmodel.destroy()
	local handle = tool:FindFirstChild("Handle")
	local gun = tool:FindFirstChild("GunModel")
	if not handle or not handle:IsA("BasePart") or not gun then
		return false
	end
	local model = Instance.new("Model")
	model.Name = "KATViewmodel"
	local parts, offsets = {}, {}

	local handleCopy = handle:Clone()
	for _, child in handleCopy:GetChildren() do
		if not child:IsA("Attachment") then
			child:Destroy()
		end
	end
	prepare(handleCopy)
	handleCopy.Transparency = 1
	handleCopy.Parent = model
	table.insert(parts, handleCopy)
	table.insert(offsets, CFrame.identity)

	local gunCopy = gun:Clone()
	for _, d in gunCopy:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	for _, d in gunCopy:GetDescendants() do
		if d:IsA("BasePart") then
			prepare(d)
			table.insert(parts, d)
			table.insert(offsets, handle.CFrame:ToObjectSpace(d.CFrame))
		end
	end
	gunCopy.Parent = model

	local sleeve, glove = WeaponConfig.SleeveColor, WeaponConfig.GloveColor
	local arms = {
		armPart(model, "RightUpperArm", Vector3.new(0.4, 0.4, UPPER), sleeve, Enum.Material.Fabric),
		armPart(model, "RightLowerArm", Vector3.new(0.34, 0.34, FORE), sleeve, Enum.Material.Fabric),
		armPart(model, "RightHand", Vector3.new(0.28, 0.32, 0.4), glove, Enum.Material.SmoothPlastic),
		armPart(model, "LeftUpperArm", Vector3.new(0.4, 0.4, UPPER), sleeve, Enum.Material.Fabric),
		armPart(model, "LeftLowerArm", Vector3.new(0.34, 0.34, FORE), sleeve, Enum.Material.Fabric),
		armPart(model, "LeftHand", Vector3.new(0.28, 0.32, 0.4), glove, Enum.Material.SmoothPlastic),
	}

	local muzzle = handleCopy:FindFirstChild("Muzzle")
	vm = {
		model = model,
		parts = parts,
		offsets = offsets,
		arms = arms,
		aim = attachmentCFrame(handle, "Aim", CFrame.new(0, 0.4, 0)),
		support = attachmentCFrame(handle, "Support", CFrame.new(0, 0.1, -1)),
		muzzleOffset = attachmentCFrame(handle, "Muzzle", CFrame.new(0, 0.25, -2)),
		muzzle = if muzzle and muzzle:IsA("Attachment") then muzzle else nil,
		gun = CFrame.identity,
	}
	model.Parent = workspace.CurrentCamera
	return true
end

function Viewmodel.active(): boolean
	return vm ~= nil
end

-- Handle-relative CFrames of the sight line and the support hand.
function Viewmodel.aimOffset(): CFrame
	return if vm then vm.aim else CFrame.identity
end

function Viewmodel.supportOffset(): CFrame
	return if vm then vm.support else CFrame.identity
end

-- Muzzle attachment on the viewmodel (for flash / sound) and its current world CFrame (barrel = LookVector).
function Viewmodel.muzzle(): Attachment?
	return if vm then vm.muzzle else nil
end

function Viewmodel.muzzleCFrame(): CFrame?
	return if vm then vm.gun * vm.muzzleOffset else nil
end

-- Two-bone IK: returns the elbow and the reachable hand position.
local function solve(shoulder: Vector3, target: Vector3, pole: Vector3): (Vector3, Vector3)
	local toTarget = target - shoulder
	local distance = math.clamp(toTarget.Magnitude, 0.05, UPPER + FORE - 0.001)
	local dir = if toTarget.Magnitude > 1e-4 then toTarget.Unit else -Vector3.zAxis
	local along = (UPPER * UPPER - FORE * FORE + distance * distance) / (2 * distance)
	local height = math.sqrt(math.max(UPPER * UPPER - along * along, 0))
	local bend = pole - dir * pole:Dot(dir)
	bend = if bend.Magnitude > 1e-4 then bend.Unit else -Vector3.yAxis
	return shoulder + dir * along + bend * height, shoulder + dir * distance
end

local function segment(a: Vector3, b: Vector3, up: Vector3): CFrame
	return CFrame.lookAt(a, b, up) * CFrame.new(0, 0, -(b - a).Magnitude / 2)
end

-- Places the gun (handle at gunCF) and the arms. leftHand overrides the support hand (reloads, pumping).
function Viewmodel.update(camera: CFrame, gunCF: CFrame, leftHand: CFrame?)
	local state = vm
	if not state then
		return
	end
	state.gun = gunCF
	local parts = table.clone(state.parts)
	local cframes = table.create(#parts + 6)
	for i, offset in state.offsets do
		cframes[i] = gunCF * offset
	end

	local up = camera.UpVector
	local right = camera.RightVector
	local rightShoulder = camera * RIGHT_SHOULDER
	local leftShoulder = camera * LEFT_SHOULDER
	local rightTarget = (gunCF * GRIP).Position
	local leftTarget = (leftHand or gunCF * state.support).Position
	local rElbow, rHand = solve(rightShoulder, rightTarget, right * 0.7 - up)
	local lElbow, lHand = solve(leftShoulder, leftTarget, -right * 0.7 - up)
	local armCFrames = {
		segment(rightShoulder, rElbow, up),
		segment(rElbow, rHand, up),
		CFrame.lookAt(rElbow, rHand, up) * CFrame.new(0, 0, -(rHand - rElbow).Magnitude - 0.1),
		segment(leftShoulder, lElbow, up),
		segment(lElbow, lHand, up),
		CFrame.lookAt(lElbow, lHand, up) * CFrame.new(0, 0, -(lHand - lElbow).Magnitude - 0.1),
	}
	for i, part in state.arms do
		table.insert(parts, part)
		table.insert(cframes, armCFrames[i])
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

return Viewmodel
