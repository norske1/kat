--!nonstrict
-- Training casualties for testing the system.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Medical = ReplicatedStorage:WaitForChild("Medical")
local Pharmacy = require(Medical.Sim.Pharmacy)
local Cardiac = require(Medical.Sim.Cardiac)
local Damage = require(Medical.Sim.Damage)
local Patient = require(Medical.Sim.Patient)
local MedicalService = require(script.Parent.MedicalService)

local Dummies = {}

local counter = 0

Dummies.Scenarios = {
	-- Arterial leg bleed with a pneumothorax: tourniquet, chest seal, IV fluids.
	GunshotLeg = function(state)
		Damage.apply(state, "LeftLeg", 45, "Bullet")
		Damage.apply(state, "Torso", 30, "Bullet")
		state.breathing.ptx = 2
	end,
	-- Unconscious, obstructed airway: airway management, BVM.
	Unconscious = function(state)
		Damage.apply(state, "Head", 25, "Blunt")
		state.knockedOut = true
		state.airway.obstructed = true
		state.airway.occluded = true
		state.parts.RightArm.fracture = 1
	end,
	-- Cardiac arrest in VF: CPR, AED, adrenaline/rhythm stabiliser.
	CardiacArrest = function(state)
		Damage.apply(state, "Torso", 20, "Bullet")
		state.bloodVolume = 4.8
		Cardiac.enterArrest(state, "Training", "VF")
	end,
	-- Explosion casualty: multiple wounds, comminuted fracture, tension pneumothorax.
	Blast = function(state)
		Damage.applySpread(state, 90, "Explosive")
		state.parts.RightLeg.fracture = 3
		state.breathing.ptx = 4
		state.breathing.tension = true
		state.bloodVolume = 4.6
	end,
	-- Respiratory depression with respiratory depression.
	Overmedicated = function(state)
		for _ = 1, 5 do
			Pharmacy.administer(state, "Analgesic", state.rng)
		end
		state.knockedOut = true
	end,
}

function Dummies.spawn(cframe: CFrame, scenario: string?): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not ok or not model then
		warn("[Medical] could not create casualty rig: " .. tostring(model))
		return nil
	end
	counter += 1
	model.Name = "Casualty " .. counter
	model:PivotTo(cframe)
	model.Parent = workspace
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	local record = MedicalService.register(model, nil)
	if record and scenario and Dummies.Scenarios[scenario] then
		Dummies.Scenarios[scenario](record.state)
		Patient.drainEvents(record.state)
		model:SetAttribute("MedScenario", scenario)
	end
	return model
end

return Dummies
