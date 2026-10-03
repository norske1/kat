--!nonstrict
-- Cardiac arrest: rhythms (VT/VF/PEA/Asystole), arrest timer, CPR, AED shocks and ROSC.
local Medical = script.Parent.Parent
local Config = require(Medical.Config)
local Patient = require(script.Parent.Patient)
local Pharmacy = require(script.Parent.Pharmacy)

local Cardiac = {}

Cardiac.RhythmNames = {
	Sinus = "Sinus rhythm",
	VT = "Ventricular tachycardia",
	VF = "Ventricular fibrillation",
	PEA = "Pulseless electrical activity",
	Asystole = "Asystole",
}

function Cardiac.isShockable(rhythm: string?): boolean
	return rhythm == "VT" or rhythm == "VF"
end

local function deteriorateDelay(rng): number
	local t = Config.RhythmDeteriorateWeight * -math.log(math.max(1e-4, rng:next()))
	return math.clamp(t, Config.RhythmDeteriorateMin, Config.RhythmDeteriorateMax)
end

function Cardiac.pickRhythm(p, forced: string?): string
	if forced then
		return forced
	end
	local rng = p.rng
	if p.bloodVolume < Config.AsystoleBloodThreshold then
		return "Asystole"
	end
	if p.breathing.tamponade > 0 or Pharmacy.concentration(p, "Nitroglycerin") > 0.1 then
		return "PEA"
	end
	if rng:chance(Config.PEAChance) then
		return "PEA"
	end
	return if rng:chance(Config.VTChance) then "VT" else "VF"
end

function Cardiac.enterArrest(p, cause: string, forcedRhythm: string?)
	if p.arrest or not p.alive then
		return
	end
	local rng = p.rng
	local variance = Config.CardiacArrestTime * Config.CardiacArrestTimeVariance
	local rhythm = Cardiac.pickRhythm(p, forcedRhythm)
	p.arrest = {
		rhythm = rhythm,
		cause = cause,
		elapsed = 0,
		duration = Config.CardiacArrestTime + rng:range(-variance, variance),
		nextDeteriorate = deteriorateDelay(rng),
		shocks = 0,
		started = p.time,
	}
	p.heartRate = 0
	p.conscious = false
	Patient.log(p, "Went into cardiac arrest (" .. cause .. ")")
	Patient.event(p, "CardiacArrest", cause)
end

-- Conditions that prevent ROSC until they are treated (the "Hs and Ts").
function Cardiac.reversibleCauses(p): { string }
	local causes = {}
	if p.bloodVolume < Config.ROSCMinBloodVolume then
		table.insert(causes, "Hypovolemia")
	end
	if p.breathing.tension then
		table.insert(causes, "Tension pneumothorax")
	end
	if p.breathing.hemo then
		table.insert(causes, "Hemothorax")
	end
	if p.breathing.tamponade > 0.5 then
		table.insert(causes, "Cardiac tamponade")
	end
	if p.spo2 < Config.ROSCMinSpO2 then
		table.insert(causes, "Hypoxia")
	end
	if p.hemolysis >= Config.IncompatibleBloodArrestThreshold then
		table.insert(causes, "Transfusion reaction")
	end
	if p.breathing.opioidArrest then
		table.insert(causes, "Opioid overdose")
	end
	return causes
end

function Cardiac.rosc(p, via: string)
	local arrest = p.arrest
	if not arrest then
		return
	end
	p.arrest = nil
	p.cpr = nil
	p.heartRate = 45 + p.rng:range(0, 20)
	if p.rng:chance(Config.PostArrestBradycardiaChance) then
		p.bradycardia = 30
	end
	p.knockedOut = true
	Patient.log(p, "Return of spontaneous circulation (" .. via .. ")")
	Patient.event(p, "ROSC", via)
end

local function bloodFactor(p): number
	return math.clamp(
		(p.bloodVolume - Config.ROSCMinBloodVolume) / (Config.DefaultBloodVolume - Config.ROSCMinBloodVolume),
		0,
		1
	)
end

-- Called when a medic completes one CPR cycle.
function Cardiac.cprCycle(p, medicLevel: number): (boolean, string)
	local arrest = p.arrest
	if not arrest then
		return false, "Patient has a pulse"
	end
	local causes = Cardiac.reversibleCauses(p)
	if #causes > 0 then
		return false, "No ROSC - " .. causes[1]
	end
	local chance = (Config.CPRSuccessChance[medicLevel] or Config.CPRSuccessChance[0]) * (0.4 + 0.6 * bloodFactor(p))
	local epi = math.min(1, Pharmacy.concentration(p, "Epinephrine"))
	if Cardiac.isShockable(arrest.rhythm) then
		chance *= 0.15
	elseif arrest.rhythm == "Asystole" then
		chance *= 0.1 + 0.5 * epi
	else
		chance *= 0.25 + 0.6 * epi
	end
	if p.rng:chance(chance) then
		Cardiac.rosc(p, "CPR")
		return true, "ROSC achieved"
	end
	return false, "No pulse"
end

function Cardiac.analyze(p): (string, boolean)
	if not p.arrest then
		return "Sinus", false
	end
	return p.arrest.rhythm, Cardiac.isShockable(p.arrest.rhythm)
end

-- Delivers a shock. Returns result text.
function Cardiac.shock(p, manual: boolean): (boolean, string)
	local arrest = p.arrest
	if not arrest then
		if manual and p.rng:chance(0.5) then
			Cardiac.enterArrest(p, "Shocked with a pulse", "VF")
			return false, "Patient went into VF"
		end
		return false, "No shock advised"
	end
	if not Cardiac.isShockable(arrest.rhythm) then
		return false, "No shock advised - " .. arrest.rhythm
	end
	arrest.shocks += 1
	local chance = Config.AEDBaseChance * (0.4 + 0.6 * bloodFactor(p))
	chance += math.min(1, p.effects.antiarrhythmic) * 0.25
	chance += math.min(1, Pharmacy.concentration(p, "Epinephrine")) * 0.1
	if arrest.shocks >= 3 and p.effects.antiarrhythmic < 0.2 then
		chance *= 0.5 -- refractory VF without amiodarone/lidocaine
	end
	if p.cpr == nil and arrest.elapsed > 60 then
		chance *= 0.8
	end
	if p.rng:chance(chance) then
		local causes = Cardiac.reversibleCauses(p)
		if #causes > 0 then
			arrest.rhythm = "PEA"
			return false, "Converted to PEA - " .. causes[1]
		end
		Cardiac.rosc(p, "Defibrillation")
		return true, "ROSC achieved"
	end
	return false, "Shock delivered - no change"
end

function Cardiac.update(p, dt: number)
	if not p.alive then
		return
	end
	if not p.arrest then
		local pending = p.pendingArrest
		p.pendingArrest = nil
		if pending then
			Cardiac.enterArrest(p, pending.cause, pending.rhythm)
		elseif p.hemolysis >= Config.IncompatibleBloodArrestThreshold then
			Cardiac.enterArrest(p, "Transfusion reaction")
		elseif p.bloodVolume < Config.BloodClass4 then
			Cardiac.enterArrest(p, "Hemorrhage")
		elseif
			p.heartRate < Config.FatalHeartRateLow
			or (p.heartRate < 30 and p.rng:chance(Config.LowHeartRateArrestChance * dt))
		then
			Cardiac.enterArrest(p, "Bradycardia")
		elseif p.heartRate > Config.FatalHeartRateHigh then
			Cardiac.enterArrest(p, "Tachycardia", "VT")
		elseif p.spo2 < Config.SpO2CardiacArrest then
			Cardiac.enterArrest(p, "Hypoxia")
		elseif p.breathing.opioidArrest and p.spo2 < 80 then
			Cardiac.enterArrest(p, "Respiratory arrest")
		end
		return
	end
	p.pendingArrest = nil

	local arrest = p.arrest
	arrest.elapsed += dt * (if p.cpr then Config.CPRTimerMultiplier else 1)
	if arrest.elapsed >= arrest.duration then
		Patient.kill(p, "Cardiac arrest")
		return
	end
	arrest.nextDeteriorate -= dt
	if arrest.nextDeteriorate <= 0 then
		arrest.nextDeteriorate = deteriorateDelay(p.rng)
		local nextRhythm = ({ VT = "VF", VF = "Asystole", PEA = "Asystole" })[arrest.rhythm]
		if nextRhythm then
			arrest.rhythm = nextRhythm
			Patient.event(p, "RhythmChanged", nextRhythm)
		end
	end
end

return Cardiac
