-- Client side of ragdoll / death for the local character (the client owns its humanoid state).
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid

humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)

local function update()
	local alive = character:GetAttribute("MedAlive")
	local ragdoll = character:GetAttribute("MedRagdoll") == true
	if alive == false then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
		humanoid:ChangeState(Enum.HumanoidStateType.Dead)
		return
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, not ragdoll)
	if ragdoll then
		humanoid.PlatformStand = true
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	elseif humanoid:GetState() == Enum.HumanoidStateType.Physics then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

character:GetAttributeChangedSignal("MedRagdoll"):Connect(update)
character:GetAttributeChangedSignal("MedAlive"):Connect(update)
update()

-- Hide our own treatment prompt; self-treatment uses the H menu.
task.spawn(function()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local prompt = root and root:WaitForChild("MedicalPrompt", 10)
	if prompt then
		(prompt :: ProximityPrompt).Enabled = false
	end
end)
