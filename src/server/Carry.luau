--!nonstrict
-- Carrying (fireman's carry) and dragging of incapacitated patients.
local MedicalService = require(script.Parent.MedicalService)

local Carry = {}

local active: { [Player]: { record: any, weld: WeldConstraint, mode: string } } = {}

local CARRY_SPEED = 0.7
local DRAG_SPEED = 0.5

local function setPatientPhysics(model: Model, carried: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if carried then
				d:SetAttribute("CarryCollide", d.CanCollide)
				d.CanCollide = false
				d.Massless = true
			else
				local original = d:GetAttribute("CarryCollide")
				if original ~= nil then
					d.CanCollide = original
					d:SetAttribute("CarryCollide", nil)
				end
				d.Massless = false
			end
		end
	end
end

function Carry.isCarrying(player: Player): boolean
	return active[player] ~= nil
end

function Carry.start(medic: Player, record, mode: string): (boolean, string?)
	if active[medic] then
		return false, "Already carrying someone"
	end
	if record.carrier then
		return false, "Someone else is moving this patient"
	end
	local medicChar = medic.Character
	local medicRoot = medicChar and medicChar:FindFirstChild("HumanoidRootPart")
	local patientRoot = MedicalService.rootOf(record)
	if not medicRoot or not patientRoot then
		return false, "Cannot reach patient"
	end
	local offset = if mode == "Carry"
		then CFrame.new(0, 1.6, 0.3) * CFrame.Angles(0, 0, math.rad(90))
		else CFrame.new(0, -1.6, 3.2) * CFrame.Angles(math.rad(-75), 0, 0)
	patientRoot.CFrame = medicRoot.CFrame * offset
	setPatientPhysics(record.model, true)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "MedicalCarryWeld"
	weld.Part0 = medicRoot
	weld.Part1 = patientRoot
	weld.Parent = medicRoot
	pcall(function()
		patientRoot:SetNetworkOwner(medic)
	end)
	record.carrier = medic
	active[medic] = { record = record, weld = weld, mode = mode }
	if medicChar then
		medicChar:SetAttribute("MedCarryMultiplier", if mode == "Carry" then CARRY_SPEED else DRAG_SPEED)
	end
	return true
end

function Carry.drop(medic: Player)
	local entry = active[medic]
	if not entry then
		return
	end
	active[medic] = nil
	if entry.weld then
		entry.weld:Destroy()
	end
	local record = entry.record
	record.carrier = nil
	if record.model.Parent then
		setPatientPhysics(record.model, false)
		local root = MedicalService.rootOf(record)
		local medicRoot = medic.Character and medic.Character:FindFirstChild("HumanoidRootPart")
		if root and medicRoot then
			root.CFrame = medicRoot.CFrame * CFrame.new(0, -1.5, -3) * CFrame.Angles(math.rad(-90), 0, 0)
		end
		pcall(function()
			if root then
				if record.player then
					root:SetNetworkOwner(record.player)
				else
					root:SetNetworkOwnershipAuto()
				end
			end
		end)
	end
	if medic.Character then
		medic.Character:SetAttribute("MedCarryMultiplier", nil)
	end
end

function Carry.dropRecord(record)
	for medic, entry in active do
		if entry.record == record then
			Carry.drop(medic)
		end
	end
end

return Carry
