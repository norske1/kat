--!nonstrict
-- Client-side weapon visuals: muzzle flash, tracers, impacts, bullet holes, blood and whiz sounds.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Weapons = ReplicatedStorage:WaitForChild("Weapons")
local Sounds = require(Medical.Sounds)
local WeaponConfig = require(Weapons.Config)

local GunFx = {}

local folder: Folder
local holes: { BasePart } = {}

local function fxPart(props): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(part :: any)[k] = v
	end
	part.Parent = folder
	return part
end

function GunFx.init()
	folder = Instance.new("Folder")
	folder.Name = "WeaponFx"
	folder.Parent = workspace
end

function GunFx.folder(): Folder
	return folder
end

function GunFx.flash(muzzle: Attachment?)
	if not muzzle then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 100)
	light.Brightness = 6
	light.Range = 12
	light.Parent = muzzle
	Debris:AddItem(light, 0.05)
	local cf = (muzzle :: Attachment).WorldCFrame
	local ball = fxPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = cf,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 200, 110),
		Transparency = 0.15,
	})
	local cone = fxPart({
		Size = Vector3.new(0.16, 0.16, 0.8),
		CFrame = cf * CFrame.new(0, 0, -0.4) * CFrame.Angles(0, 0, math.random() * math.pi),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 170, 70),
		Transparency = 0.25,
	})
	Debris:AddItem(ball, 0.04)
	Debris:AddItem(cone, 0.04)
end

function GunFx.tracer(from: Vector3, to: Vector3)
	local distance = (to - from).Magnitude
	if distance < 3 then
		return
	end
	local length = math.min(10, distance * 0.4)
	local look = CFrame.lookAt(from, to)
	local tracer = fxPart({
		Size = Vector3.new(0.06, 0.06, length),
		CFrame = look * CFrame.new(0, 0, -length / 2),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 225, 150),
		Transparency = 0.2,
	})
	local tween = TweenService:Create(
		tracer,
		TweenInfo.new(distance / WeaponConfig.TracerSpeed, Enum.EasingStyle.Linear),
		{ CFrame = look * CFrame.new(0, 0, -(distance - length / 2)) }
	)
	tween.Completed:Connect(function()
		tracer:Destroy()
	end)
	tween:Play()
end

local function burst(position: Vector3, normal: Vector3, color: Color3, count: number, flesh: boolean)
	local attachment = Instance.new("Attachment")
	attachment.WorldCFrame = CFrame.lookAt(position, position + normal) * CFrame.Angles(-math.pi / 2, 0, 0)
	attachment.Parent = workspace.Terrain
	Debris:AddItem(attachment, 3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = if flesh
		then "rbxasset://textures/particles/smoke_main.dds"
		else "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.25, 0.5)
	emitter.Speed = NumberRange.new(if flesh then 4 else 8, if flesh then 9 else 16)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Size = NumberSequence.new(if flesh then 0.45 else 0.25, 0)
	emitter.Acceleration = Vector3.new(0, -35, 0)
	emitter.Drag = 3
	emitter.Parent = attachment
	emitter:Emit(count)
	return attachment
end

-- kind: 0 = nothing hit, 1 = surface, 2 = character
function GunFx.impact(position: Vector3, normal: Vector3?, kind: number, color: Color3?)
	if kind == 0 or not normal then
		return
	end
	local n = normal :: Vector3
	if kind == 2 then
		local point = burst(position, n, Color3.fromRGB(110, 0, 0), 14, true)
		Sounds.play("ImpactFlesh", point)
		return
	end
	local point = burst(position, n, color or Color3.fromRGB(140, 130, 115), 8, false)
	Sounds.play("ImpactSurface", point, 0.8)
	local hole = fxPart({
		Size = Vector3.new(0.22, 0.22, 0.03),
		CFrame = CFrame.lookAt(position + n * 0.012, position + n * 2),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(25, 22, 20),
	})
	table.insert(holes, hole)
	Debris:AddItem(hole, 25)
	while #holes > WeaponConfig.MaxBulletHoles do
		local old = table.remove(holes, 1)
		if old then
			old:Destroy()
		end
	end
end

local function closestPoint(a: Vector3, b: Vector3, p: Vector3): Vector3
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return a
	end
	return a + ab * math.clamp((p - a):Dot(ab) / len2, 0, 1)
end

-- Full shot: sound, flash, tracers and delayed impacts. hits = { { p, n?, k, c? } }
function GunFx.shot(def, muzzle: Attachment?, origin: Vector3, hits, isLocal: boolean)
	if muzzle then
		Sounds.play(def.fireSound, muzzle)
	else
		Sounds.playAt(def.fireSound, origin)
	end
	GunFx.flash(muzzle)
	local start = if muzzle then muzzle.WorldPosition else origin
	local camera = workspace.CurrentCamera
	local whizzed = isLocal
	for _, hit in hits do
		if typeof(hit) ~= "table" or typeof(hit.p) ~= "Vector3" then
			continue
		end
		GunFx.tracer(start, hit.p)
		local delay = (hit.p - start).Magnitude / WeaponConfig.TracerSpeed
		task.delay(delay, GunFx.impact, hit.p, hit.n, hit.k or 0, hit.c)
		if not whizzed and camera then
			local point = closestPoint(origin, hit.p, camera.CFrame.Position)
			local d = (point - camera.CFrame.Position).Magnitude
			if d < 7 and (point - origin).Magnitude > 10 then
				whizzed = true
				Sounds.playAt("Whiz", point)
			end
		end
	end
end

return GunFx
