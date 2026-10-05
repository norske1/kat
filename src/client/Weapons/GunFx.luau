--!nonstrict
-- Client-side weapon visuals: muzzle flash, simulated bullets with tracers (same ballistics as the server),
-- impacts, bullet holes, blood, supersonic cracks and gunshots delayed by the speed of sound.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Weapons = Medical:WaitForChild("Weapons")
local Sounds = require(Medical.Sounds)
local WeaponConfig = require(Weapons.Config)
local Ballistics = require(Weapons.Ballistics)

local GunFx = {}

local folder: Folder
local holes: { BasePart } = {}
local active = {} -- bullets in flight (visual)
local stepBullets: (number) -> ()

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
	RunService.RenderStepped:Connect(stepBullets)
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

local function isCharacterPart(instance: Instance): boolean
	local model = instance:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- A shot: sound (delayed by distance for other players' shots), flash and one simulated bullet per pellet.
function GunFx.fire(def, muzzle: Attachment?, origin: Vector3, directions, shooter: Model?, isLocal: boolean)
	local camera = workspace.CurrentCamera
	local listener = if camera then camera.CFrame.Position else origin
	local delay = if isLocal then 0 else (origin - listener).Magnitude / WeaponConfig.SpeedOfSound
	if delay < 0.03 and muzzle then
		Sounds.play(def.fireSound, muzzle)
	elseif delay < 0.03 then
		Sounds.playAt(def.fireSound, origin)
	else
		task.delay(delay, Sounds.playAt, def.fireSound, origin)
	end
	GunFx.flash(muzzle)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder }
	if shooter then
		table.insert(ignore, shooter)
	end
	if camera then
		table.insert(ignore, camera)
	end
	params.FilterDescendantsInstances = ignore
	local start = if muzzle then muzzle.WorldPosition else origin
	local speed = def.velocity or WeaponConfig.DefaultVelocity
	for _, dir in directions do
		if typeof(dir) == "Vector3" and dir.Magnitude > 0.5 then
			table.insert(active, {
				bullet = Ballistics.new(origin, dir.Unit, speed, def.range),
				start = start,
				params = params,
				cracked = isLocal,
				tracer = nil,
			})
		end
	end
end

local function remove(i: number)
	local v = active[i]
	if v.tracer then
		v.tracer:Destroy()
	end
	active[i] = active[#active]
	active[#active] = nil
end

function stepBullets(dt: number)
	if #active == 0 then
		return
	end
	local gravity = Vector3.new(0, -WeaponConfig.BulletGravity, 0)
	local camera = workspace.CurrentCamera
	local listener = if camera then camera.CFrame.Position else nil
	for i = #active, 1, -1 do
		local v = active[i]
		local b = v.bullet
		local from = if b.traveled == 0 then v.start else b.position
		local hit, done = Ballistics.step(b, gravity, dt, function(f, d)
			return workspace:Raycast(f, d, v.params)
		end)
		local to = b.position
		local seg = to - from
		local length = math.min(seg.Magnitude, 12)
		if length > 0.05 then
			if not v.tracer then
				v.tracer = fxPart({
					Size = Vector3.new(0.06, 0.06, length),
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(255, 225, 150),
					Transparency = 0.2,
				})
			end
			v.tracer.Size = Vector3.new(0.06, 0.06, length)
			v.tracer.CFrame = CFrame.lookAt(to - seg.Unit * length, to) * CFrame.new(0, 0, -length / 2)
		end
		if not v.cracked and listener and b.traveled > 10 then
			local point = closestPoint(from, to, listener)
			if (point - listener).Magnitude < WeaponConfig.CrackDistance then
				v.cracked = true
				Sounds.playAt("Whiz", point)
			end
		end
		if hit then
			local instance = hit.Instance
			local color = if instance:IsA("BasePart") and not instance:IsA("Terrain") then instance.Color else nil
			GunFx.impact(hit.Position, hit.Normal, if isCharacterPart(instance) then 2 else 1, color)
		end
		if done or b.age > 4 then
			remove(i)
		end
	end
end

return GunFx
