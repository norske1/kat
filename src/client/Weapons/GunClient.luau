--!nonstrict
-- Local side of the gun system: input, ACS-style first-person viewmodel (or over-the-shoulder camera),
-- aiming down sights, sway, bob, recoil and shooting. Shots are simulated again on the server, which
-- applies medical damage; everything here is visual.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Weapons = Medical:WaitForChild("Weapons")
local WeaponConfig = require(Weapons.Config)
local Remotes = require(Medical.Remotes)
local Sounds = require(Medical.Sounds)
local Animator = require(script.Parent.Parent.Animator)
local Menu = require(script.Parent.Parent.Menu)
local Hud = require(script.Parent.Parent.Hud)
local GunFx = require(script.Parent.GunFx)
local Viewmodel = require(script.Parent.Viewmodel)
local Movement = require(script.Parent.Movement)
local GunHud = require(script.Parent.GunHud)
local LockerClient = require(script.Parent.LockerClient)

local GunClient = {}

local player = Players.LocalPlayer
local fireRemote, reloadRemote, stateRemote

local current = nil -- { tool, def, modeIndex, muzzle, conns, firstPerson }
local triggerDown = false
local aiming = false
local dryClicked = false
local lastShot = 0
local equipUntil = 0
local reloadPendingUntil = 0
local predictedAmmo = 0
local recoilPending = Vector2.zero
local lastSent = { t = 0, aim = false, pitch = 0 }
local medical = { pain = 0, armInjury = 0, conscious = true }
local defaultFov = 70
local baseSensitivity = 1
local savedCamera = nil -- { mode, minZoom, distance } restored when the gun is put away
local equipStart = 0
-- viewmodel motion
local aimBlend, sprintBlend, bobT = 0, 0, 0
local sway = Vector2.zero
local kick = { back = 0, pitch = 0, yaw = 0 }

local function character(): Model?
	return player.Character
end

local function humanoid(): Humanoid?
	local char = character()
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function mouseFree(): boolean
	return Menu.isOpen() or Hud.wantsMouse() or UserInputService:IsKeyDown(WeaponConfig.FreeMouseKey)
end

local function isReloading(): boolean
	return current ~= nil and (current.tool:GetAttribute("Reloading") == true or os.clock() < reloadPendingUntil)
end

local function refreshHud()
	if not current then
		GunHud.show(false)
		return
	end
	GunHud.show(true)
	GunHud.setAmmo(
		current.def.name,
		predictedAmmo,
		current.tool:GetAttribute("Reserve") or 0,
		current.def.modes[current.modeIndex],
		isReloading()
	)
end

local function unequip()
	if not current then
		return
	end
	for _, conn in current.conns do
		conn:Disconnect()
	end
	local wasFirstPerson = current.firstPerson
	local tool = current.tool
	current = nil
	triggerDown = false
	aiming = false
	recoilPending = Vector2.zero
	Movement.setShoulder(Vector3.zero)
	UserInputService.MouseDeltaSensitivity = baseSensitivity
	if wasFirstPerson then
		Viewmodel.destroy()
		for _, d in tool:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			end
		end
		if savedCamera then
			local saved = savedCamera
			savedCamera = nil
			player.CameraMode = saved.mode
			if saved.mode ~= Enum.CameraMode.LockFirstPerson and saved.distance > 2 then
				-- zoom back out to where the camera was before the gun came out
				player.CameraMinZoomDistance = math.max(saved.minZoom, saved.distance)
				task.delay(0.1, function()
					if not savedCamera then
						player.CameraMinZoomDistance = saved.minZoom
					end
				end)
			end
		end
	end
	local hum = humanoid()
	local char = character()
	if hum then
		if not (char and char:GetAttribute("MedRagdoll")) then
			hum.AutoRotate = true
		end
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	if workspace.CurrentCamera then
		workspace.CurrentCamera.FieldOfView = defaultFov
	end
	Animator.setLocalGun(nil)
	GunHud.show(false)
end

local function equip(tool: Tool)
	local def = WeaponConfig.get(tool:GetAttribute("WeaponId"))
	if not def then
		return
	end
	unequip()
	current = {
		tool = tool,
		def = def,
		modeIndex = 1,
		muzzle = tool:FindFirstChild("Muzzle", true),
		conns = {},
		firstPerson = false,
	}
	predictedAmmo = tool:GetAttribute("Ammo") or 0
	for _, attribute in { "Ammo", "Reserve", "Reloading" } do
		table.insert(
			current.conns,
			tool:GetAttributeChangedSignal(attribute):Connect(function()
				if attribute == "Ammo" then
					predictedAmmo = tool:GetAttribute("Ammo") or 0
				elseif attribute == "Reloading" then
					reloadPendingUntil = 0
				end
				refreshHud()
			end)
		)
	end
	equipUntil = os.clock() + def.equipTime
	equipStart = os.clock()
	aimBlend, sprintBlend = 0, 0
	sway = Vector2.zero
	kick = { back = 0, pitch = 0, yaw = 0 }
	local camera = workspace.CurrentCamera
	if camera then
		defaultFov = camera.FieldOfView
	end
	baseSensitivity = UserInputService.MouseDeltaSensitivity
	if WeaponConfig.FirstPerson and Viewmodel.create(tool) then
		current.firstPerson = true
		local char = character()
		local head = char and char:FindFirstChild("Head")
		savedCamera = {
			mode = player.CameraMode,
			minZoom = player.CameraMinZoomDistance,
			distance = if camera and head then (camera.CFrame.Position - head.Position).Magnitude else 0,
		}
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		-- the real tool stays on the character for everyone else; hide it locally behind the viewmodel
		local function hide(d: Instance)
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end
		for _, d in tool:GetDescendants() do
			hide(d)
		end
		table.insert(current.conns, tool.DescendantAdded:Connect(hide))
	end
	local hum = humanoid()
	if hum then
		hum.AutoRotate = false
	end
	Animator.setLocalGun({ hold = def.hold, aiming = false, pitch = 0 })
	refreshHud()
end

local function randomCone(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local roll = math.random() * 2 * math.pi
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

local function currentSpread(): number
	local def = current.def
	local hum = humanoid()
	local moving = if hum and hum.MoveDirection.Magnitude > 0.1 then 1 else 0
	local airborne = if hum and hum.FloorMaterial == Enum.Material.Air then 1 else 0
	local base = if aiming then def.spreadAim else def.spreadHip
	return base
		* (1 + moving * def.spreadMove + airborne * 1.5)
		* WeaponConfig.medicalSpread(medical.armInjury, medical.pain)
end

local function rayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character(), GunFx.folder() }
	return params
end

local function canShoot(): boolean
	if not current or not medical.conscious or mouseFree() then
		return false
	end
	local char = character()
	if not char or char:GetAttribute("MedAnim") or char:GetAttribute("MedCarryAnim") then
		return false
	end
	return os.clock() >= equipUntil and not isReloading() and not Movement.isSprinting()
end

local function shoot()
	local def = current.def
	local now = os.clock()
	if now - lastShot < 60 / def.rpm then
		return
	end
	if predictedAmmo <= 0 then
		if not dryClicked then
			dryClicked = true
			Sounds.play("DryFire", current.tool:FindFirstChild("Handle"))
		end
		return
	end
	local char = character()
	local head = char and char:FindFirstChild("Head")
	local camera = workspace.CurrentCamera
	if not head or not camera then
		return
	end
	lastShot = now
	predictedAmmo -= 1

	local params = rayParams()
	local muzzle = current.muzzle
	local origin, aimDir
	local barrel = if current.firstPerson then Viewmodel.muzzleCFrame() else nil
	if barrel then
		-- first person: the bullet leaves the viewmodel barrel along the barrel (aim with the sights)
		muzzle = Viewmodel.muzzle()
		origin, aimDir = barrel.Position, barrel.LookVector
		local eye = camera.CFrame.Position
		if workspace:Raycast(eye, origin - eye, params) then
			origin = eye
		end
	else
		origin = if muzzle then muzzle.WorldPosition else head.Position
		if workspace:Raycast(head.Position, origin - head.Position, params) then
			origin = head.Position
		end
		-- aim at whatever is under the crosshair, starting the camera ray level with the character
		local viewport = camera.ViewportSize
		local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
		local skip = math.max((head.Position - ray.Origin):Dot(ray.Direction), 0)
		local rayStart = ray.Origin + ray.Direction * skip
		local camHit = workspace:Raycast(rayStart, ray.Direction * def.range, params)
		local target = if camHit then camHit.Position else rayStart + ray.Direction * def.range
		aimDir = target - origin
		aimDir = if aimDir.Magnitude > 0.5 then aimDir.Unit else ray.Direction
	end

	local center = randomCone(aimDir, currentSpread())
	local directions = {}
	for i = 1, def.pellets do
		directions[i] = if def.pellets > 1 then randomCone(center, def.pelletSpread or 0) else center
	end
	fireRemote:FireServer(current.tool, origin, directions)
	GunFx.fire(def, muzzle, origin, directions, char, true)

	local recoil = def.recoil
	local scale = (if aiming then 0.65 else 1) * (1 + medical.armInjury * 0.8)
	recoilPending += Vector2.new(recoil.vertical * scale, (math.random() * 2 - 1) * recoil.horizontal * scale)
	Animator.kick(char, recoil.kick)
	local fpScale = (if aiming then 0.6 else 1) * (1 + medical.armInjury * 0.8)
	kick.back = math.min(kick.back + 0.09 * recoil.kick * fpScale, 0.5)
	kick.pitch = math.min(kick.pitch + math.rad(3.5) * recoil.kick * fpScale, math.rad(25))
	kick.yaw += (math.random() * 2 - 1) * math.rad(1.5) * recoil.kick * fpScale
	if def.modes[current.modeIndex] ~= "Auto" then
		triggerDown = false
	end
	refreshHud()
end

local function requestReload()
	if not current or isReloading() or not medical.conscious then
		return
	end
	if predictedAmmo >= current.def.magazine or (current.tool:GetAttribute("Reserve") or 0) <= 0 then
		return
	end
	reloadPendingUntil = os.clock() + 0.6
	triggerDown = false
	reloadRemote:FireServer(current.tool)
	refreshHud()
end

local function smoothstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Keyframed CFrame track: keys = { { t, CFrame } } sorted by t.
local function track(keys, t: number): CFrame
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			return a[2]:Lerp(b[2], smoothstep((t - a[1]) / math.max(b[1] - a[1], 1e-3)))
		end
	end
	return keys[#keys][2]
end

-- 0 -> 1 over [0, fadeIn], hold, 1 -> 0 over [fadeOut, 1]
local function envelope(t: number, fadeIn: number, fadeOut: number): number
	return smoothstep(t / fadeIn) * (1 - smoothstep((t - fadeOut) / (1 - fadeOut)))
end

-- Places the first-person gun and arms for this frame.
local function updateViewmodel(dt: number, camera: Camera, char: Model)
	local def = current.def
	local cfg = WeaponConfig.Viewmodel[def.hold] or WeaponConfig.Viewmodel.Rifle
	local cam = camera.CFrame
	local reloading = isReloading()
	aimBlend += ((if aiming and not reloading then 1 else 0) - aimBlend) * math.min(1, dt * 12)
	sprintBlend += ((if Movement.isSprinting() then 1 else 0) - sprintBlend) * math.min(1, dt * 8)
	local aim = smoothstep(aimBlend)

	-- hip: grip low-right, barrel converging on the screen centre 60 studs out. aim: sights on the eye line.
	local hip = CFrame.lookAt(cam * cfg.hip, cam * Vector3.new(0, 0, -60), cam.UpVector)
	local sights = cam * CFrame.new(0, 0, -cfg.aimDistance) * Viewmodel.aimOffset():Inverse()
	local gun = hip:Lerp(sights, aim)

	-- sway (gun lags behind mouse movement), walk bob, breathing and pain tremor, in camera space
	local delta = if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		then UserInputService:GetMouseDelta()
		else Vector2.zero
	local target = Vector2.new(math.clamp(-delta.Y * 0.003, -0.12, 0.12), math.clamp(-delta.X * 0.003, -0.12, 0.12))
	sway += (target - sway) * math.min(1, dt * 9)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local velocity = if root then root.AssemblyLinearVelocity else Vector3.zero
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	bobT += dt * speed * 0.55
	local moving = math.min(speed / 16, 1.5)
	local bobAmp = 0.035 * moving * (1 - 0.8 * aim) * (1 + sprintBlend * 1.2)
	local clock = os.clock()
	local steady = 1 - 0.7 * aim
	local tremor = medical.pain * 0.006 + medical.armInjury * 0.004
	local swayAmount = 1 - 0.7 * aim
	local motion = CFrame.new(
		math.sin(bobT) * bobAmp + math.sin(clock * 7.3) * tremor,
		-math.abs(math.cos(bobT)) * bobAmp + math.sin(clock * 1.6) * 0.006 * steady + math.sin(clock * 8.1) * tremor,
		0
	) * CFrame.Angles(
		sway.X * swayAmount,
		sway.Y * swayAmount,
		sway.Y * swayAmount * 0.8 + math.sin(bobT) * bobAmp * 0.5
	)
	gun = cam * motion * cam:ToObjectSpace(gun)

	-- sprinting: gun lowered and canted across the chest
	if sprintBlend > 0.001 then
		local lowered = if def.hold == "Pistol"
			then CFrame.new(0, -0.25, 0.2) * CFrame.Angles(math.rad(-55), math.rad(15), 0)
			else CFrame.new(0.1, -0.2, 0.15) * CFrame.Angles(math.rad(-25), math.rad(45), math.rad(-20))
		gun = gun:Lerp(gun * lowered, smoothstep(sprintBlend))
	end

	-- equip: raise from below
	local raise = 1 - smoothstep((clock - equipStart) / math.max(def.equipTime, 0.05))
	if raise > 0.001 then
		gun *= CFrame.new(0, -0.6 * raise, 0.25 * raise) * CFrame.Angles(math.rad(-60) * raise, 0, math.rad(25) * raise)
	end

	-- reload / pump (timed by the server's GunAction attributes)
	local leftHand = nil
	local action = char:GetAttribute("GunAction")
	if action and action ~= "Equip" then
		local started = char:GetAttribute("GunActionT") or workspace:GetServerTimeNow()
		local duration = math.max((char:GetAttribute("GunActionDur") :: number?) or 1, 0.05)
		local elapsed = workspace:GetServerTimeNow() - started
		local t = math.clamp(elapsed / duration, 0, 1)
		local support = Viewmodel.supportOffset()
		if action == "Reload" then
			local tilt = envelope(t, 0.15, 0.85)
			gun *= CFrame.new(-0.05 * tilt, 0.1 * tilt, 0) * CFrame.Angles(
				math.rad(12) * tilt,
				math.rad(-10) * tilt,
				math.rad(30) * tilt
			)
			local magWell = gun * CFrame.new(cfg.magWell)
			local pouch = cam * CFrame.new(-0.5, -2.3, -0.6)
			local held = gun * support
			leftHand = track({
				{ 0, held },
				{ 0.18, magWell },
				{ 0.38, pouch },
				{ 0.55, pouch },
				{ 0.72, magWell },
				{ 0.88, held },
			}, t)
		elseif action == "ReloadShells" then
			local tilt = envelope(t, 0.1, 0.92)
			gun *= CFrame.Angles(math.rad(8) * tilt, 0, math.rad(25) * tilt)
			local phase = (elapsed % 0.5) / 0.5
			local port = gun * CFrame.new(0, 0, -0.35)
			local belt = cam * CFrame.new(-0.3, -1.7, -0.7)
			if t < 0.95 then
				leftHand = track({ { 0, belt }, { 0.5, port }, { 1, belt } }, phase)
			end
		elseif action == "Pump" then
			local pull = math.sin(math.pi * t)
			gun *= CFrame.new(0, 0, 0.04 * pull)
			leftHand = gun * support * CFrame.new(0, 0, 0.3 * pull)
		end
	end

	-- recoil spring: kick back and muzzle climb, recovering quickly
	local decay = math.exp(-dt * 14)
	kick.back *= decay
	kick.pitch *= decay
	kick.yaw *= decay
	gun *= CFrame.new(0, 0, kick.back) * CFrame.Angles(kick.pitch, kick.yaw, kick.yaw * 0.5)

	Viewmodel.update(cam, gun, leftHand)
end

local function renderStep(dt: number)
	if not current then
		return
	end
	local char = character()
	local hum = humanoid()
	local camera = workspace.CurrentCamera
	if not char or current.tool.Parent ~= char or not hum or not camera then
		unequip()
		return
	end
	local free = mouseFree()
	UserInputService.MouseBehavior = if free then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = free

	local head = char:FindFirstChild("Head")
	local nearHead = head ~= nil and (camera.CFrame.Position - head.Position).Magnitude < 1.5
	Movement.setShoulder(
		if current.firstPerson or nearHead
			then Vector3.zero
			elseif aiming then WeaponConfig.AimCameraOffset
			else WeaponConfig.CameraOffset
	)
	if Movement.isSprinting() then
		triggerDown = false
	end

	local look = camera.CFrame.LookVector
	local root = char:FindFirstChild("HumanoidRootPart")
	local busy = char:GetAttribute("MedRagdoll") or char:GetAttribute("MedAnim") or char:GetAttribute("MedCarryAnim")
	if root and medical.conscious and not busy then
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end

	local cfg = WeaponConfig.Viewmodel[current.def.hold] or WeaponConfig.Viewmodel.Rifle
	local aimFov = if current.firstPerson then cfg.fov else WeaponConfig.AimFov
	local fovTarget = if aiming and not Movement.isSprinting() then aimFov else defaultFov
	camera.FieldOfView += (fovTarget - camera.FieldOfView) * math.min(1, dt * 12)
	UserInputService.MouseDeltaSensitivity = if aiming
		then baseSensitivity * WeaponConfig.AimSensitivity
		else baseSensitivity

	if recoilPending.Magnitude > 0.001 then
		local step = recoilPending * math.min(1, dt * 18)
		recoilPending -= step
		camera.CFrame *= CFrame.Angles(math.rad(step.X), math.rad(step.Y), 0)
	end

	if current.firstPerson then
		updateViewmodel(dt, camera, char)
	end
	if triggerDown and canShoot() then
		shoot()
	end

	local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
	Animator.setLocalGun({ hold = current.def.hold, aiming = aiming, pitch = pitch })
	local now = os.clock()
	if now - lastSent.t > 0.1 and (aiming ~= lastSent.aim or math.abs(pitch - lastSent.pitch) > 2) then
		lastSent = { t = now, aim = aiming, pitch = pitch }
		stateRemote:FireServer(current.tool, aiming, pitch)
	end
	local crosshair = not current.firstPerson or (WeaponConfig.ShowHipCrosshair and aimBlend < 0.5)
	GunHud.setSpread(currentSpread(), aiming, crosshair)
end

local function watchCharacter(char: Model)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("WeaponId") then
			equip(child)
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if current and child == current.tool then
			unequip()
		end
	end)
	for _, child in char:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("WeaponId") then
			equip(child)
		end
	end
end

function GunClient.setMedical(data)
	if typeof(data) ~= "table" then
		return
	end
	medical.pain = data.pain or 0
	medical.armInjury = data.armInjury or 0
	medical.conscious = data.alive ~= false and data.conscious ~= false
	Movement.setBlocked(not medical.conscious)
	if not medical.conscious then
		triggerDown = false
		aiming = false
	end
end

function GunClient.isEquipped(): boolean
	return current ~= nil
end

function GunClient.init(screen: ScreenGui)
	fireRemote = Remotes.get("GunFire")
	reloadRemote = Remotes.get("GunReload")
	stateRemote = Remotes.get("GunState")
	GunFx.init()
	GunHud.init(screen)
	LockerClient.init(screen)
	Movement.init()
	Movement.setAimingProvider(function()
		return aiming and current ~= nil
	end)

	Remotes.get("GunFx").OnClientEvent:Connect(function(shooter, weaponId, origin, directions)
		if shooter == player or typeof(origin) ~= "Vector3" or typeof(directions) ~= "table" then
			return
		end
		local def = WeaponConfig.get(weaponId)
		if not def then
			return
		end
		local char = typeof(shooter) == "Instance" and shooter:IsA("Player") and shooter.Character or nil
		local tool = char and char:FindFirstChildOfClass("Tool")
		local muzzle = tool and tool:FindFirstChild("Muzzle", true)
		GunFx.fire(def, muzzle, origin, directions, char, false)
		Animator.kick(char, def.recoil.kick)
	end)
	Remotes.get("GunHit").OnClientEvent:Connect(function(kind)
		GunHud.hit(if typeof(kind) == "number" then kind else 1)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not current or processed then
			return
		end
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			if LockerClient.hovering() then
				return -- clicking a locker item, not shooting
			end
			triggerDown = true
			dryClicked = false
		elseif inputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
			aiming = true
		elseif input.KeyCode == WeaponConfig.ReloadKey or input.KeyCode == Enum.KeyCode.ButtonX then
			requestReload()
		elseif input.KeyCode == WeaponConfig.FireModeKey and #current.def.modes > 1 then
			current.modeIndex = current.modeIndex % #current.def.modes + 1
			Sounds.play("FireMode", current.tool:FindFirstChild("Handle"))
			refreshHud()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			triggerDown = false
		elseif inputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
			aiming = false
		end
	end)

	RunService:BindToRenderStep("KATGuns", Enum.RenderPriority.Camera.Value + 2, renderStep)
	player.CharacterAdded:Connect(function(char)
		unequip()
		watchCharacter(char)
	end)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return GunClient
