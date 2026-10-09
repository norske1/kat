--!nonstrict
-- Local stance: sprint (hold Shift), crouch (C, toggle) and lean (Q / E, toggle). Works with or without a
-- gun. The server applies walk speed and crouch height (so the hitbox really lowers) and replicates the
-- poses; this module moves and rolls the camera for leaning and owns Humanoid.CameraOffset.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local WeaponConfig = require(Medical:WaitForChild("Weapons").Config)
local Remotes = require(Medical.Remotes)
local Gear = require(Medical:WaitForChild("Gear").Gear)
local GearConfig = require(Medical.Gear.Config)
local Animator = require(script.Parent.Parent.Animator)

local Movement = {}

local player = Players.LocalPlayer
local stanceRemote
local state = { crouch = false, sprint = false, lean = 0 }
local blocked = false
local aimingFn: () -> boolean = function()
	return false
end
local shoulder = Vector3.zero
local smoothShoulder = Vector3.zero
local lean = 0 -- smoothed, after wall checks
local lastSent = ""
local stamina = 1
local exhausted = false

local function character(): Model?
	return player.Character
end

local function send()
	local key = string.format("%s|%s|%d", tostring(state.crouch), tostring(state.sprint), state.lean)
	if key == lastSent then
		return
	end
	lastSent = key
	Animator.setLocalMove({ crouch = state.crouch, sprint = state.sprint, lean = state.lean })
	if stanceRemote then
		stanceRemote:FireServer(state.crouch, state.sprint, state.lean)
	end
end

local function busy(): boolean
	local char = character()
	return blocked
		or not char
		or char:GetAttribute("MedRagdoll") == true
		or char:GetAttribute("MedAnim") ~= nil
		or char:GetAttribute("MedCarryAnim") ~= nil
end

local function reset()
	state.crouch, state.sprint, state.lean = false, false, 0
	send()
end

local function wantsSprint(): boolean
	if busy() or aimingFn() or not UserInputService:IsKeyDown(WeaponConfig.SprintKey) then
		return false
	end
	local char = character()
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.MoveDirection.Magnitude < 0.1 then
		return false
	end
	if exhausted or (char :: Model):GetAttribute("GearNoSprint") then
		return false
	end
	-- forwards (or forwards-diagonal) only
	return hum.MoveDirection:Dot((root :: BasePart).CFrame.LookVector) > 0.3
end

-- Before the camera updates: sprint state and camera offset (shoulder + lean).
local function updateStamina(dt: number)
	local char = character()
	local mass = char and char:GetAttribute("GearMass") or 0
	if state.sprint then
		stamina = math.max(0, stamina - dt / Gear.sprintSeconds(mass))
		if stamina <= 0 then
			exhausted = true
		end
	else
		stamina = math.min(1, stamina + dt / GearConfig.StaminaRegenSeconds)
		if exhausted and stamina >= GearConfig.StaminaResume then
			exhausted = false
		end
	end
end

local function beforeCamera(dt: number)
	updateStamina(dt)
	if busy() then
		if state.crouch or state.sprint or state.lean ~= 0 then
			reset()
		end
	else
		local sprint = wantsSprint()
		if sprint ~= state.sprint then
			state.sprint = sprint
			if sprint then
				state.crouch = false
				state.lean = 0
			end
			send()
		end
	end

	local char = character()
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum then
		return
	end
	local target = state.lean
	if target ~= 0 and head and root then
		-- don't lean the camera into a wall
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char }
		local side = (root :: BasePart).CFrame.RightVector * target * (WeaponConfig.LeanOffset + 0.4)
		local hit = workspace:Raycast((head :: BasePart).Position, side, params)
		if hit then
			target *= math.clamp((hit.Distance - 0.4) / WeaponConfig.LeanOffset, 0, 1)
		end
	end
	lean += (target - lean) * math.min(1, dt * 10)
	smoothShoulder = smoothShoulder:Lerp(shoulder, math.min(1, dt * 10))
	hum.CameraOffset = smoothShoulder + Vector3.new(lean * WeaponConfig.LeanOffset, 0, 0)
end

-- After the camera updates: roll for leaning.
local function afterCamera()
	local camera = workspace.CurrentCamera
	if camera and math.abs(lean) > 0.001 then
		camera.CFrame *= CFrame.Angles(0, 0, -lean * math.rad(WeaponConfig.LeanAngle))
	end
end

function Movement.setShoulder(offset: Vector3)
	shoulder = offset
end

function Movement.setBlocked(value: boolean)
	blocked = value
end

function Movement.setAimingProvider(fn: () -> boolean)
	aimingFn = fn
end

function Movement.isSprinting(): boolean
	return state.sprint
end

-- 0..1, and whether the player ran out (can't sprint until it recovers).
function Movement.stamina(): (number, boolean)
	return stamina, exhausted
end

function Movement.isCrouched(): boolean
	return state.crouch
end

function Movement.init()
	stanceRemote = Remotes.get("Stance")
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or busy() then
			return
		end
		local key = input.KeyCode
		if key == WeaponConfig.CrouchKey then
			state.crouch = not state.crouch
			if state.crouch then
				state.sprint = false
			end
			send()
		elseif key == WeaponConfig.LeanLeftKey or key == WeaponConfig.LeanRightKey then
			local dir = if key == WeaponConfig.LeanLeftKey then -1 else 1
			state.lean = if state.lean == dir then 0 else dir
			state.sprint = false
			send()
		end
	end)
	RunService:BindToRenderStep("KATMoveOffset", Enum.RenderPriority.Camera.Value - 1, beforeCamera)
	RunService:BindToRenderStep("KATMoveRoll", Enum.RenderPriority.Camera.Value + 1, afterCamera)
	player.CharacterAdded:Connect(function()
		stamina, exhausted = 1, false
		lean = 0
		lastSent = ""
		state.crouch, state.sprint, state.lean = false, false, 0
		Animator.setLocalMove(nil)
	end)
end

return Movement
