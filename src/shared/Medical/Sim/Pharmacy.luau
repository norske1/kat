--!nonstrict
-- Medication absorption, effect curves, adverse reactions and IV/IO fluid flow.
local Medical = script.Parent.Parent
local Config = require(Medical.Config)
local Medications = require(Medical.Medications)
local BloodTypes = require(Medical.BloodTypes)
local Patient = require(script.Parent.Patient)

local Pharmacy = {}

-- Effect strength 0..1: linear ramp to peak, then linear decay to zero at duration.
function Pharmacy.effectFraction(def, age: number): number
	if age <= 0 then
		return 0
	elseif age < def.peak then
		return age / def.peak
	elseif age < def.duration then
		return 1 - (age - def.peak) / (def.duration - def.peak)
	end
	return 0
end

function Pharmacy.dosesInSystem(p, medId: string): number
	local n = 0
	for _, dose in p.meds do
		if dose.id == medId then
			n += 1
		end
	end
	return n
end

function Pharmacy.concentration(p, medId: string): number
	local def = Medications[medId]
	local total = 0
	for _, dose in p.meds do
		if dose.id == medId then
			total += Pharmacy.effectFraction(def, p.time - dose.t)
		end
	end
	return total
end

local function reaction(p, def, rng)
	local kind = def.reaction
	if not kind then
		return
	end
	Patient.log(p, def.name .. " adverse reaction")
	if kind == "Breathing" then
		p.breathing.respArrest = true
		Patient.event(p, "Overmedicated", def.name)
	elseif kind == "Tachy" then
		if rng:chance(0.5) then
			p.pendingArrest = { cause = def.name .. " adverse reaction", rhythm = "VT" }
		else
			p.bradycardia -= 0 -- no-op, keeps symmetry
			p.tachyReaction = (p.tachyReaction or 0) + 60
		end
	elseif kind == "Hypotension" then
		p.hypotensionReaction = (p.hypotensionReaction or 0) + 30
	elseif kind == "Sedation" then
		p.knockedOut = true
	end
end

function Pharmacy.administer(p, medId: string, rng)
	local def = Medications[medId]
	assert(def, "unknown medication " .. tostring(medId))
	local hr = 0
	if def.hr then
		hr = def.hr[1] + (def.hr[2] - def.hr[1]) * rng:next()
	end

	if medId == "ReversalSpray" then
		for i = #p.meds, 1, -1 do
			local m = Medications[p.meds[i].id]
			if m.respDepression and not m.sedative then
				table.remove(p.meds, i)
			end
		end
		p.breathing.respArrest = false
	elseif medId == "SedativeReversal" then
		for i = #p.meds, 1, -1 do
			if p.meds[i].id == "Sedative" then
				table.remove(p.meds, i)
			end
		end
	end

	table.insert(p.meds, { id = medId, t = p.time, hr = hr })

	if def.incompatible then
		for _, other in def.incompatible do
			if Pharmacy.dosesInSystem(p, other) > 0 then
				reaction(p, def, rng)
				break
			end
		end
	end
	local doses = Pharmacy.dosesInSystem(p, medId)
	if doses > def.maxDose then
		local excess = doses - def.maxDose
		if rng:chance(math.min(1, 0.35 * excess)) then
			reaction(p, def, rng)
		end
	end
end

function Pharmacy.updateMeds(p)
	local e = p.effects
	e.pain, e.hr, e.resistance, e.respDepression, e.coagulation = 0, 0, 0, 0, 0
	e.sedation, e.anesthesia, e.antiarrhythmic, e.vasopressor = 0, 0, 0, 0
	for i = #p.meds, 1, -1 do
		local dose = p.meds[i]
		local def = Medications[dose.id]
		local age = p.time - dose.t
		if age >= def.duration then
			table.remove(p.meds, i)
		else
			local f = Pharmacy.effectFraction(def, age)
			e.pain += (def.pain or 0) * f
			e.hr += dose.hr * f
			e.resistance += (def.resistance or 0) * f
			e.respDepression += (def.respDepression or 0) * f
			e.coagulation += (def.coagulation or 0) * f
			if def.antiarrhythmic then
				e.antiarrhythmic += f
			end
			if def.vasopressor then
				e.vasopressor += f
			end
			if dose.id == "Sedative" and f > 0.2 then
				e.sedation = math.max(e.sedation, f)
			elseif dose.id == "SurgicalSedative" and f > 0.2 then
				e.anesthesia = math.max(e.anesthesia, f)
			elseif dose.id == "FieldAnesthetic" then
				e.anesthesia = math.max(e.anesthesia, f * 0.5)
			end
		end
	end
	e.pain = math.min(e.pain, 1)
	e.respDepression = math.min(e.respDepression, 1)
	e.coagulation = math.min(e.coagulation, 0.8)
	if p.tachyReaction and p.tachyReaction > 0 then
		e.hr += 60
		p.tachyReaction -= 1
	end
	if p.hypotensionReaction and p.hypotensionReaction > 0 then
		e.resistance -= 40
		p.hypotensionReaction -= 1
	end
end

-- Returns the body part with usable vascular access, preferring unobstructed sites.
function Pharmacy.findAccess(p): string?
	for _, name in { "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Head" } do
		local part = p.parts[name]
		if part.access and Pharmacy.accessFlows(p, name) then
			return name
		end
	end
	return nil
end

function Pharmacy.accessFlows(p, partName: string): boolean
	local part = p.parts[partName]
	if not part.access then
		return false
	end
	if part.tourniquet then
		return false
	end
	if p.reboa and (partName == "LeftLeg" or partName == "RightLeg") then
		return false
	end
	return true
end

function Pharmacy.hasAccess(p): boolean
	return Pharmacy.findAccess(p) ~= nil
end

-- bag = { kind = "Saline" | "Plasma" | "Blood", volume = litres, remaining = litres, bloodType = string? }
function Pharmacy.attachFluid(p, partName: string, kind: string, volumeMl: number, bloodType: string?)
	local part = p.parts[partName]
	assert(part.access, "no access")
	local litres = volumeMl / 1000
	table.insert(part.access.fluids, { kind = kind, volume = litres, remaining = litres, bloodType = bloodType })
end

local gain = { Blood = 0.8, Plasma = 0.5, Saline = 0.3 }
local coagPerLitre = { Blood = 16, Plasma = 20, Saline = 0 }

function Pharmacy.updateFluids(p, dt: number)
	local cardiacFlow = if p.arrest and not p.cpr then 0.2 else 1
	for partName, part in p.parts do
		local access = part.access
		if access and #access.fluids > 0 and Pharmacy.accessFlows(p, partName) then
			local rate = Config.IVFlowRate * (if access.kind == "IO" then Config.IOFlowMultiplier else 1) * cardiacFlow
			local budget = rate * dt
			while budget > 0 and #access.fluids > 0 do
				local bag = access.fluids[1]
				local amount = math.min(budget, bag.remaining)
				bag.remaining -= amount
				budget -= amount
				if
					bag.kind == "Blood"
					and bag.bloodType
					and not BloodTypes.isCompatible(p.bloodType, bag.bloodType)
				then
					p.hemolysis += amount
					p.kidneyDamage += amount * 0.5
				else
					p.bloodVolume = math.min(Config.MaxBloodVolume, p.bloodVolume + amount * gain[bag.kind])
					p.coag.factors =
						math.min(Config.CoagulationFactors * 2, p.coag.factors + amount * coagPerLitre[bag.kind])
				end
				if bag.remaining <= 1e-6 then
					table.remove(access.fluids, 1)
					Patient.log(p, string.format("%s %dml finished", bag.kind, math.floor(bag.volume * 1000 + 0.5)))
				end
			end
		end
	end
end

function Pharmacy.totalFluidsQueued(p): number
	local total = 0
	for _, part in p.parts do
		if part.access then
			for _, bag in part.access.fluids do
				total += bag.remaining
			end
		end
	end
	return total
end

return Pharmacy
