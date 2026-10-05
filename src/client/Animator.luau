--!nonstrict
-- Plays the procedural animations from Medical.Animations on every character by writing Motor6D.Transform
-- after the default Animator has run (PreSimulation). State comes from character attributes set by the
-- server, so everyone sees the same treatment / weapon poses without uploaded animation assets.
--   MedAnim / MedAnimT          treatment clip ("Kneel.Cpr") and its server start time
--   MedCarryAnim                carry / drag hold pose
--   GunHold, GunAim, GunPitch   weapon hold type, aiming and aim pitch
--   GunAction, GunActionT, GunActionDur   reload / pump / equip
--   MoveCrouch, MoveSprint, MoveLean        stance (crouch legs, lowered gun, upper-body lean)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Animations = require(Medical.Animations)

local Animator = {}

local JOINTS = {
	[Enum.HumanoidRigType.R15] = {
		Root = { "LowerTorso", "Root" },
		Waist = { "UpperTorso", "Waist" },
		Neck = { "Head", "Neck" },
		RightShoulder = { "RightUpperArm", "RightShoulder" },
		RightElbow = { "RightLowerArm", "RightElbow" },
		RightWrist = { "RightHand", "RightWrist" },
		LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
		LeftElbow = { "LeftLowerArm", "LeftElbow" },
		LeftWrist = { "LeftHand", "LeftWrist" },
		RightHip = { "RightUpperLeg", "RightHip" },
		RightKnee = { "RightLowerLeg", "RightKnee" },
		LeftHip = { "LeftUpperLeg", "LeftHip" },
		LeftKnee = { "LeftLowerLeg", "LeftKnee" },
	},
	[Enum.HumanoidRigType.R6] = {
		Root = { "HumanoidRootPart", "RootJoint" },
		Neck = { "Torso", "Neck" },
		RightShoulder = { "Torso", "Right Shoulder" },
		LeftShoulder = { "Torso", "Left Shoulder" },
		RightHip = { "Torso", "Right Hip" },
		LeftHip = { "Torso", "Left Hip" },
	},
}

type CharState = {
	motors: { [string]: Motor6D },
	rotations: { [Motor6D]: CFrame },
	weight: number,
	aim: number,
	pitch: number,
	kick: number,
	crouch: number,
	sprint: number,
	lean: number,
	lastPose: any,
}

local states: { [Model]: CharState } = {}
local localGun = nil -- { hold, aiming, pitch } for the local player (no network delay)
local localMove = nil -- { crouch, sprint, lean } for the local player

local function findMotors(character: Model, humanoid: Humanoid)
	local motors = {}
	local map = JOINTS[humanoid.RigType]
	if not map then
		return motors
	end
	for joint, path in map do
		local part = character:FindFirstChild(path[1])
		local motor = part and part:FindFirstChild(path[2])
		if motor and motor:IsA("Motor6D") then
			motors[joint] = motor
		end
	end
	return motors
end

local function stateFor(character: Model, humanoid: Humanoid): CharState
	local st = states[character]
	if not st then
		st = {
			motors = findMotors(character, humanoid),
			rotations = {},
			weight = 0,
			aim = 0,
			pitch = 0,
			kick = 0,
			crouch = 0,
			sprint = 0,
			lean = 0,
			lastPose = nil,
		}
		states[character] = st
		character.Destroying:Connect(function()
			states[character] = nil
		end)
	end
	return st
end

local function jointTransform(st: CharState, motor: Motor6D, values): CFrame
	local c0r = st.rotations[motor]
	if not c0r then
		c0r = motor.C0.Rotation
		st.rotations[motor] = c0r
	end
	local local_ = CFrame.new(values[4] or 0, values[5] or 0, values[6] or 0)
		* CFrame.fromEulerAnglesYXZ(math.rad(values[1] or 0), math.rad(values[2] or 0), math.rad(values[3] or 0))
	-- express the rotation in Part0 space regardless of how the rig's C0 is oriented (R6 vs R15)
	return c0r:Inverse() * local_ * c0r
end

local function gunPose(character: Model, st: CharState, dt: number, isLocal: boolean, now: number)
	local hold, aiming, pitch
	if isLocal and localGun then
		hold, aiming, pitch = localGun.hold, localGun.aiming, localGun.pitch
	else
		hold = character:GetAttribute("GunHold")
		aiming = character:GetAttribute("GunAim") == true
		pitch = character:GetAttribute("GunPitch") or 0
	end
	if not hold then
		return nil
	end
	st.aim += ((if aiming then 1 else 0) - st.aim) * math.min(1, dt * 12)
	st.pitch += (pitch - st.pitch) * math.min(1, dt * (if isLocal then 30 else 10))
	local action = character:GetAttribute("GunAction")
	local actionT = nil
	if action then
		local started = character:GetAttribute("GunActionT") or now
		local duration = character:GetAttribute("GunActionDur") or 1
		local def = Animations.GunActions[action]
		if def and def.normalized then
			actionT = (now - started) / math.max(duration, 0.05)
		else
			actionT = now - started
		end
	end
	return Animations.gun(hold, st.aim, st.pitch, action, actionT, st.kick, st.sprint)
end

local function updateMove(character: Model, st: CharState, dt: number, isLocal: boolean)
	local crouch, sprint, lean
	if isLocal and localMove then
		crouch, sprint, lean = localMove.crouch, localMove.sprint, localMove.lean
	else
		crouch = character:GetAttribute("MoveCrouch") == true
		sprint = character:GetAttribute("MoveSprint") == true
		lean = character:GetAttribute("MoveLean") or 0
	end
	local f = math.min(1, dt * 10)
	st.crouch += ((if crouch then 1 else 0) - st.crouch) * f
	st.sprint += ((if sprint then 1 else 0) - st.sprint) * f
	st.lean += (lean - st.lean) * f
end

local function step(dt: number)
	local now = workspace:GetServerTimeNow()
	local me = Players.LocalPlayer
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or not character.Parent then
			continue
		end
		local st = stateFor(character, humanoid)
		st.kick *= math.exp(-dt * 12)
		updateMove(character, st, dt, player == me)
		local pose = nil
		local ragdolled = character:GetAttribute("MedRagdoll") == true or humanoid.Health <= 0
		if not ragdolled then
			local clip = character:GetAttribute("MedAnim") or character:GetAttribute("MedCarryAnim")
			if clip then
				local started = character:GetAttribute("MedAnimT") or now
				pose = Animations.medical(clip, now - started)
			else
				pose = gunPose(character, st, dt, player == me, now)
				local crouch = if humanoid.RigType == Enum.HumanoidRigType.R15 then st.crouch else 0
				local move = Animations.movement(crouch, st.lean)
				if move then
					if not st.motors.Waist and move.Waist then
						move.Root = move.Waist -- R6 has no waist: lean the whole torso
						move.Waist = nil
					end
					pose = if pose then Animations.add(pose, move) else move
				end
			end
		end
		if ragdolled then
			st.weight = 0
			continue
		end
		local target = if pose then 1 else 0
		st.weight += (target - st.weight) * math.min(1, dt * 8)
		if pose then
			st.lastPose = pose
		end
		local use = pose or st.lastPose
		if not use or st.weight < 0.01 then
			continue
		end
		for joint, values in use do
			local motor = st.motors[joint]
			if motor and motor.Parent and motor.Enabled then
				motor.Transform = motor.Transform:Lerp(jointTransform(st, motor, values), st.weight)
			end
		end
	end
end

function Animator.setLocalGun(state)
	localGun = state
end

function Animator.setLocalMove(state)
	localMove = state
end

function Animator.kick(character: Model?, amount: number)
	local st = character and states[character]
	if st then
		st.kick = math.min(st.kick + amount, 2.5)
	end
end

function Animator.init()
	local event = RunService.PreSimulation
	event:Connect(step)
end

return Animator
