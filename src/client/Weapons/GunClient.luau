--!nonstrict
-- Local side of the gun system: input, over-the-shoulder camera, aiming, recoil, client hit prediction
-- (visual only - the server re-does every raycast and applies medical damage).
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
local GunHud = require(script.Parent.GunHud)
local LockerClient = require(script.Parent.LockerClient)

local GunClient = {}

local player = Players.LocalPlayer
local fireRemote, reloadRemote, stateRemote

local current = nil -- { tool, def, modeIndex, muzzle, conns }
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
	current = nil
	triggerDown = false
	aiming = false
	recoilPending = Vector2.zero
	local hum = humanoid()
	local char = character()
	if hum then
		hum.CameraOffset = Vector3.zero
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
	if workspace.CurrentCamera then
		defaultFov = workspace.CurrentCamera.FieldOfView
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
	return os.clock() >= equipUntil and not isReloading()
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
	local origin = if muzzle then muzzle.WorldPosition else head.Position
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
	local aimDir = target - origin
	aimDir = if aimDir.Magnitude > 0.5 then aimDir.Unit else ray.Direction

	local center = randomCone(aimDir, currentSpread())
	local directions, hits = {}, {}
	for i = 1, def.pellets do
		local dir = if def.pellets > 1 then randomCone(center, def.pelletSpread or 0) else center
		directions[i] = dir
		local result = workspace:Raycast(origin, dir * def.range, params)
		if result then
			local instance = result.Instance
			hits[i] = {
				p = result.Position,
				n = result.Normal,
				k = if isCharacterPart(instance) then 2 else 1,
				c = if instance:IsA("BasePart") and not instance:IsA("Terrain") then instance.Color else nil,
			}
		else
			hits[i] = { p = origin + dir * def.range, k = 0 }
		end
	end
	fireRemote:FireServer(current.tool, origin, directions)
	GunFx.shot(def, muzzle, origin, hits, true)

	local recoil = def.recoil
	local scale = (if aiming then 0.65 else 1) * (1 + medical.armInjury * 0.8)
	recoilPending += Vector2.new(recoil.vertical * scale, (math.random() * 2 - 1) * recoil.horizontal * scale)
	Animator.kick(char, recoil.kick)
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
	local firstPerson = head ~= nil and (camera.CFrame.Position - head.Position).Magnitude < 1.5
	local offset = if firstPerson
		then Vector3.zero
		elseif aiming then WeaponConfig.AimCameraOffset
		else WeaponConfig.CameraOffset
	hum.CameraOffset = hum.CameraOffset:Lerp(offset, math.min(1, dt * 10))

	local look = camera.CFrame.LookVector
	local root = char:FindFirstChild("HumanoidRootPart")
	local busy = char:GetAttribute("MedRagdoll") or char:GetAttribute("MedAnim") or char:GetAttribute("MedCarryAnim")
	if root and medical.conscious and not busy then
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end

	local fovTarget = if aiming then WeaponConfig.AimFov else defaultFov
	camera.FieldOfView += (fovTarget - camera.FieldOfView) * math.min(1, dt * 12)

	if recoilPending.Magnitude > 0.001 then
		local step = recoilPending * math.min(1, dt * 18)
		recoilPending -= step
		camera.CFrame *= CFrame.Angles(math.rad(step.X), math.rad(step.Y), 0)
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
	GunHud.setSpread(currentSpread(), aiming)
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

	Remotes.get("GunFx").OnClientEvent:Connect(function(shooter, weaponId, origin, hits)
		if shooter == player or typeof(origin) ~= "Vector3" or typeof(hits) ~= "table" then
			return
		end
		local def = WeaponConfig.get(weaponId)
		if not def then
			return
		end
		local char = typeof(shooter) == "Instance" and shooter:IsA("Player") and shooter.Character or nil
		local tool = char and char:FindFirstChildOfClass("Tool")
		local muzzle = tool and tool:FindFirstChild("Muzzle", true)
		GunFx.shot(def, muzzle, origin, hits, false)
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

	RunService:BindToRenderStep("KATGuns", Enum.RenderPriority.Camera.Value + 1, renderStep)
	player.CharacterAdded:Connect(function(char)
		unequip()
		watchCharacter(char)
	end)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return GunClient
