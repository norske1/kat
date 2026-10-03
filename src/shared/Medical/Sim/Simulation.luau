--!nonstrict
-- Orchestrates one simulation step for a patient.
local Medical = script.Parent.Parent
local Config = require(Medical.Config)
local Patient = require(script.Parent.Patient)
local Pharmacy = require(script.Parent.Pharmacy)
local Circulation = require(script.Parent.Circulation)
local Breathing = require(script.Parent.Breathing)
local Cardiac = require(script.Parent.Cardiac)

local Simulation = {}

function Simulation.hasStableVitals(p): boolean
	if not p.alive or p.arrest then
		return false
	end
	if p.bloodVolume < Config.StableBloodVolume then
		return false
	end
	if p.effects.sedation > 0 or p.effects.anesthesia > 0.2 then
		return false
	end
	if p.bpSys < Config.StableBP[1] or p.bpDia < Config.StableBP[2] then
		return false
	end
	if p.heartRate < Config.StableHeartRate then
		return false
	end
	if p.spo2 < Config.SpO2Stable then
		return false
	end
	if p.reboa then
		return false
	end
	return true
end

-- Hard conditions that force unconsciousness regardless of wake checks.
function Simulation.unconsciousCauses(p): { string }
	local causes = {}
	if p.arrest then
		table.insert(causes, "Cardiac arrest")
	end
	if p.bloodVolume < Config.BloodClass3 then
		table.insert(causes, "Blood loss")
	end
	if p.spo2 < Config.SpO2Unconscious then
		table.insert(causes, "Hypoxia")
	end
	if p.bpSys < Config.UnconsciousBPLimit and p.heartRate < 40 then
		table.insert(causes, "Low blood pressure")
	end
	if p.effects.sedation > 0 then
		table.insert(causes, "Sedated")
	end
	if p.effects.anesthesia > 0.2 then
		table.insert(causes, "Anesthesia")
	end
	if p.knockedOut then
		table.insert(causes, "Trauma")
	end
	return causes
end

function Simulation.tryWake(p, bonus: number): boolean
	if not p.knockedOut then
		return true
	end
	if not Simulation.hasStableVitals(p) then
		return false
	end
	if p.rng:chance(math.min(1, Config.WakeChance + bonus)) then
		p.knockedOut = false
		return true
	end
	return false
end

local function updateConsciousness(p, dt: number)
	p.nextWakeCheck -= dt
	if p.nextWakeCheck <= 0 then
		p.nextWakeCheck = Config.WakeCheckInterval
		if p.knockedOut then
			local epi = math.min(1, p.effects.vasopressor)
			Simulation.tryWake(p, epi * Config.EpinephrineWakeBonus)
		end
	end
	local causes = Simulation.unconsciousCauses(p)
	p.unconsciousCauses = causes
	local conscious = #causes == 0
	if conscious ~= p.conscious then
		p.conscious = conscious
		if conscious then
			Patient.log(p, "Regained consciousness")
			Patient.event(p, "Woke")
			local a = p.airway
			if a.device then
				Patient.log(p, a.device .. " removed (gag reflex)")
				a.device = nil
			end
			a.recovery = false
			a.headTilt = false
		else
			Patient.log(p, "Lost consciousness (" .. causes[1] .. ")")
			Patient.event(p, "Unconscious", causes[1])
		end
	end
end

local function updateKidneys(p, dt: number)
	if not Config.KidneyEnabled then
		return
	end
	p.nextKidneyCheck -= dt
	if p.nextKidneyCheck > 0 then
		return
	end
	p.nextKidneyCheck = Config.KidneyCheckInterval
	if p.kidneyDamage >= 1 and not p.arrest and p.rng:chance(Config.KidneyFailArrestChance) then
		p.pendingArrest = { cause = "Kidney failure", rhythm = "Asystole" }
	end
	p.kidneyDamage = math.max(0, p.kidneyDamage - 0.01)
	p.hemolysis = math.max(0, p.hemolysis - 0.002)
end

function Simulation.step(p, dt: number)
	if not p.alive then
		return
	end
	p.time += dt

	Pharmacy.updateMeds(p)
	Pharmacy.updateFluids(p, dt)
	Circulation.updateReopening(p)
	Circulation.updateCoagulation(p, dt)
	Circulation.bleed(p, dt)
	Breathing.updateThorax(p, dt)
	Breathing.updateAirway(p, dt)
	Circulation.updatePain(p, dt)
	Circulation.updateHemodynamics(p, dt)
	Breathing.updateOxygen(p, dt)
	updateKidneys(p, dt)
	Cardiac.update(p, dt)
	if not p.alive then
		return
	end
	updateConsciousness(p, dt)

	if p.bloodVolume <= Config.BleedoutVolume then
		Patient.kill(p, "Exsanguination")
	elseif Config.SpO2DieEnabled and p.spo2 < Config.SpO2DieValue then
		Patient.kill(p, "Hypoxia")
	end
end

return Simulation
