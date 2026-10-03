--!strict
-- Converts a character's Motor6Ds into ball sockets while unconscious.
local Ragdoll = {}

local function isRootJoint(motor: Motor6D): boolean
	return motor.Name == "Root" or motor.Name == "RootJoint"
end

function Ragdoll.isEnabled(model: Model): boolean
	return model:GetAttribute("MedRagdoll") == true
end

function Ragdoll.set(model: Model, enabled: boolean)
	if Ragdoll.isEnabled(model) == enabled then
		return
	end
	local found = model:FindFirstChildOfClass("Humanoid")
	if not found then
		return
	end
	local humanoid = found :: Humanoid
	model:SetAttribute("MedRagdoll", enabled)
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and not isRootJoint(d) and d.Part0 and d.Part1 then
			if enabled then
				local a0 = Instance.new("Attachment")
				a0.Name = "RagdollAttachment"
				a0.CFrame = d.C0
				a0.Parent = d.Part0
				local a1 = Instance.new("Attachment")
				a1.Name = "RagdollAttachment"
				a1.CFrame = d.C1
				a1.Parent = d.Part1
				local socket = Instance.new("BallSocketConstraint")
				socket.Name = "RagdollSocket"
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.LimitsEnabled = true
				socket.TwistLimitsEnabled = true
				socket.UpperAngle = 50
				socket.TwistLowerAngle = -40
				socket.TwistUpperAngle = 40
				socket.Parent = d.Parent
				d.Enabled = false
			else
				d.Enabled = true
			end
		elseif d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			if enabled then
				d:SetAttribute("RagdollCollide", d.CanCollide)
				d.CanCollide = true
			else
				local original = d:GetAttribute("RagdollCollide")
				if original ~= nil then
					d.CanCollide = original :: boolean
					d:SetAttribute("RagdollCollide", nil)
				end
			end
		end
	end
	if not enabled then
		for _, d in model:GetDescendants() do
			if d.Name == "RagdollSocket" or d.Name == "RagdollAttachment" then
				d:Destroy()
			end
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.CanCollide = not enabled
	end
	humanoid.AutoRotate = not enabled
	-- Players' humanoid state is owned by their client (see MedicalCharacter.client); NPCs are handled here.
	local isPlayer = game:GetService("Players"):GetPlayerFromCharacter(model) ~= nil
	if not isPlayer then
		humanoid.PlatformStand = enabled
		humanoid:ChangeState(if enabled then Enum.HumanoidStateType.Physics else Enum.HumanoidStateType.GettingUp)
	end
end

return Ragdoll
