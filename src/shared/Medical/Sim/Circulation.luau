--!nonstrict
-- Bleeding, coagulation, bandage reopening, pain and haemodynamics (HR / BP / cardiac output).
local Medical = script.Parent.Parent
local Config = require(Medical.Config)
local Wounds = require(Medical.Wounds)
local BodyParts = require(Medical.BodyParts)
local Patient = require(script.Parent.Patient)

local Circulation = {}

function Circulation.hemorrhageClass(bloodVolume: number): number
	if bloodVolume < Config.BloodClass4 then
		return 4
	elseif bloodVolume < Config.BloodClass3 then
		return 3
	elseif bloodVolume < Config.BloodClass2 then
		return 2
	elseif bloodVolume < Config.BloodClass1 then
		return 1
	end
	return 0
end

local function partBleeds(p, name: string, part): boolean
	if part.tourniquet then
		return false
	end
	if p.reboa then
		if BodyParts.isLeg(name) then
			return false
		end
		if p.reboa == "I" and name == "Torso" then
			return false
		end
	end
	return true
end

function Circulation.woundBleeding(w): number
	local def = Wounds.Types[w.type]
	return def.bleeding[w.size] * w.amount
end

-- External + internal bleeding rate in L/s at current perfusion.
function Circulation.computeBleedRate(p): number
	local external = 0
	for name, part in p.parts do
		if partBleeds(p, name, part) then
			for _, w in part.wounds do
				external += Circulation.woundBleeding(w)
			end
		end
	end
	local internal = 0
	if p.breathing.hemo and not (p.reboa == "I") then
		internal += Config.HemothoraxBleeding
	end
	for name, part in p.parts do
		if part.fracture == 3 and partBleeds(p, name, part) then
			internal += 0.0008
		end
	end

	local perfusion = math.clamp(p.cardiacOutput, 0, 1.2)
	if p.arrest then
		perfusion = if p.cpr then 0.25 else 0.05
	end
	local coagulation = 1 - p.effects.coagulation
	return (external + internal) * perfusion * coagulation * Config.BleedingMultiplier
end

function Circulation.updateCoagulation(p, dt: number)
	if not Config.CoagulationEnabled then
		return
	end
	local coag = p.coag
	coag.regen += dt
	if coag.regen >= Config.CoagulationRegenInterval then
		coag.regen = 0
		if coag.factors < Config.CoagulationFactors then
			coag.factors += 1
		end
	end
	local speed = 1 + p.effects.coagulation * 3
	for _, part in p.parts do
		for i = #part.wounds, 1, -1 do
			local w = part.wounds[i]
			if Wounds.Types[w.type].bleeding[w.size] > 0 then
				w.clot = (w.clot or 0) + dt * speed
				local cost = Config.CoagulationCost[w.size]
				if w.clot >= Config.CoagulationClotTime[w.size] and coag.factors >= cost then
					coag.factors -= cost
					w.clot = 0
					w.amount -= 1
					if w.amount <= 0.01 then
						table.remove(part.wounds, i)
					end
				end
			end
		end
	end
end

local function addWound(list, w)
	for _, existing in list do
		if existing.type == w.type and existing.size == w.size then
			existing.amount += w.amount
			return
		end
	end
	table.insert(list, w)
end
Circulation.addWound = addWound

function Circulation.updateReopening(p)
	if not Config.BandageReopeningEnabled then
		return
	end
	for name, part in p.parts do
		for i = #part.bandaged, 1, -1 do
			local b = part.bandaged[i]
			if b.reopenAt and p.time >= b.reopenAt then
				table.remove(part.bandaged, i)
				addWound(part.wounds, { type = b.type, size = b.size, amount = b.amount, clot = 0 })
				Patient.log(p, string.format("Bandage on %s came loose", BodyParts.DisplayName[name]))
				Patient.event(p, "Reopened", name)
			end
		end
	end
end

function Circulation.updatePain(p, dt: number)
	local pain = 0
	for name, part in p.parts do
		for _, w in part.wounds do
			pain += Wounds.Types[w.type].pain[w.size] * w.amount * 0.5
		end
		for _, b in part.bandaged do
			pain += Wounds.Types[b.type].pain[b.size] * b.amount * 0.25
		end
		if part.fracture > 0 then
			pain += if part.splint then 0.1 else 0.15 + 0.1 * part.fracture
		end
		if part.surgery > 0 then
			pain += 0.2
		end
		if part.tourniquet then
			local held = p.time - part.tourniquet
			pain += 0.05
			if held > Config.TourniquetPainDelay then
				pain += math.min(0.4, (held - Config.TourniquetPainDelay) * Config.TourniquetPainRate)
			end
		end
		if part.access and part.access.kind == "IO" then
			pain += 0.05
		end
		local _ = name
	end
	p.painBurst = math.max(0, p.painBurst - Config.PainBurstDecay * dt)
	p.pain = math.clamp(pain + p.painBurst, 0, 1)
	p.painPerceived = math.clamp(p.pain - p.effects.pain, 0, 1)
end

function Circulation.updateHemodynamics(p, dt: number)
	local volumeRatio = p.bloodVolume / Config.DefaultBloodVolume
	local strokeFactor = math.clamp(volumeRatio, 0, 1.1) ^ 1.5
	local b = p.breathing
	if b.tension then
		strokeFactor *= 0.6
	end
	if b.tamponade > 0 then
		strokeFactor *= 1 - math.min(b.tamponade, 1) * 0.6
	end

	if p.arrest then
		p.heartRate = if p.cpr then 100 + p.rng:range(-5, 15) else 0
		p.cardiacOutput = if p.cpr then 0.25 else 0
	else
		local compensation = 1 + (1 - math.min(volumeRatio, 1)) * 1.5
		local target = Config.DefaultHeartRate * compensation
		target += p.painPerceived * 40
		target += p.effects.hr
		target -= p.bradycardia
		if p.spo2 < 90 then
			target += (90 - p.spo2) * 0.8
		end
		if p.spo2 < 70 then
			target -= (70 - p.spo2) * 4
		end
		if p.hemolysis > 0 then
			target -= math.min(50, p.hemolysis * 80)
		end
		if not p.conscious then
			target -= 5
		end
		local step = Config.HeartRateChangePerSecond * dt
		local diff = target - p.heartRate
		p.heartRate += math.clamp(diff, -step, step)
		p.heartRate = math.max(0, p.heartRate)
		p.cardiacOutput = strokeFactor * p.heartRate / Config.DefaultHeartRate
		if p.bradycardia > 0 then
			p.bradycardia = math.max(0, p.bradycardia - dt * 0.05)
		end
	end

	p.resistance = math.max(30, Config.DefaultResistance + p.effects.resistance)
	-- ACE style: BP = cardiac output (L/s) * resistance
	local flow = p.cardiacOutput * Config.DefaultHeartRate / 60 * Config.StrokeVolume
	local bp = flow * p.resistance
	p.bpSys = math.max(0, bp * Config.BPHighModifier)
	p.bpDia = math.max(0, bp * Config.BPLowModifier)
end

-- Returns the volume lost this step.
function Circulation.bleed(p, dt: number): number
	p.bleedRate = Circulation.computeBleedRate(p)
	local lost = p.bleedRate * dt
	p.bloodVolume = math.max(0, p.bloodVolume - lost)
	return lost
end

return Circulation
