--!nonstrict
-- Airway and breathing: obstruction/occlusion, pneumothorax progression, ventilation and oxygenation.
local Medical = script.Parent.Parent
local Config = require(Medical.Config)
local Patient = require(script.Parent.Patient)

local Breathing = {}

function Breathing.airwayBlocked(p): boolean
	local a = p.airway
	if not (a.obstructed or a.occluded) then
		return false
	end
	if a.recovery or a.headTilt then
		return false
	end
	if a.obstructed and not a.occluded and a.device then
		return false
	end
	return true
end

function Breathing.updateAirway(p, dt: number)
	if not Config.AirwayEnabled then
		return
	end
	local a = p.airway
	if p.conscious then
		if a.obstructed or a.occluded then
			a.obstructed = false
			if a.occluded then
				a.occluded = false
				Patient.log(p, "Coughed up airway occlusion")
			end
		end
		a.nextCheck = Config.AirwayCheckInterval
		return
	end
	a.nextCheck -= dt
	if a.nextCheck > 0 then
		return
	end
	a.nextCheck = Config.AirwayCheckInterval
	local rng = p.rng
	if not a.obstructed and not a.device and not a.recovery and rng:chance(Config.ObstructionChance) then
		a.obstructed = true
		Patient.event(p, "AirwayObstructed")
	end
	local protected = a.device == "AirwayTube" or a.recovery
	if not a.occluded and not protected and rng:chance(Config.OcclusionChance) then
		a.occluded = true
		Patient.event(p, "AirwayOccluded")
	end
end

function Breathing.updateThorax(p, dt: number)
	local b = p.breathing
	if b.tamponade > 0 then
		b.tamponade = math.min(1.2, b.tamponade + Config.TamponadeGrowth * dt)
		if b.tamponade >= 1 and not p.arrest then
			p.pendingArrest = { cause = "Cardiac tamponade", rhythm = "PEA" }
		end
	end
	if b.ptx <= 0 or b.tension or b.hemo then
		b.nextDeteriorate = Config.PneumothoraxDeteriorateInterval
		return
	end
	b.nextDeteriorate -= dt
	if b.nextDeteriorate > 0 then
		return
	end
	b.nextDeteriorate = Config.PneumothoraxDeteriorateInterval
	local rng = p.rng
	if rng:chance(Config.PneumothoraxDeteriorateChance) then
		if b.ptx < 4 then
			b.ptx += 1
			Patient.event(p, "PneumothoraxWorse", b.ptx)
		elseif rng:chance(Config.AdvancedPneumothoraxChance) then
			if rng:chance(0.5) then
				b.tension = true
			else
				b.hemo = true
			end
			Patient.event(p, "AdvancedPneumothorax")
		end
	end
end

-- Ventilation 0..~1.5 relative to a healthy breathing patient.
function Breathing.computeVentilation(p): number
	local b = p.breathing
	local bvm = p.time < b.bvmUntil
	local spontaneous = not p.arrest and not b.respArrest
	local v = 0
	if spontaneous then
		v = 1 - p.effects.respDepression * 0.8
		if Breathing.airwayBlocked(p) then
			v = 0
		end
	end
	if bvm then
		local bvmV = if p.airway.occluded and not p.airway.recovery then 0.1 else 0.9
		v = math.max(v, bvmV)
	elseif p.arrest and p.cpr then
		if not Breathing.airwayBlocked(p) then
			v = math.max(v, Config.CPRVentilation)
		end
	end
	v *= 1 - b.ptx * Config.PneumothoraxSpO2Penalty
	if b.dpi then
		v *= 0.9
	end
	if b.tension or b.hemo then
		v *= 0.35
	end
	return math.max(0, v)
end

function Breathing.fio2(p): number
	local b = p.breathing
	if b.oxygen == "Tank" then
		return if p.time < b.bvmUntil then 1 else 0.6
	elseif b.oxygen == "Cannula" then
		return 0.4
	end
	return 0.21
end

function Breathing.spo2FromPaO2(pao2: number): number
	if pao2 <= 0 then
		return 0
	end
	return 100 / (1 + (26.8 / pao2) ^ 2.7)
end

function Breathing.updateOxygen(p, dt: number)
	local v = Breathing.computeVentilation(p)
	p.breathing.ventilation = v
	local oxygenBoost = (Breathing.fio2(p) / 0.21) ^ 0.5
	local demand = 1 + math.max(0, p.heartRate - 100) / 200
	local delivery = v * oxygenBoost / demand
	local target = 95 * math.min(delivery, 1.6)
	if delivery < 1 then
		target = 95 * delivery ^ 1.2
	end
	local k = if target < p.pao2 then Config.PaO2FallRate else Config.PaO2RiseRate
	p.pao2 += (target - p.pao2) * math.min(1, k * dt)
	p.pao2 = math.clamp(p.pao2, 0, 150)
	p.spo2 = Breathing.spo2FromPaO2(p.pao2)

	if p.arrest or v <= 0.05 and not (p.time < p.breathing.bvmUntil) then
		p.respRate = 0
	else
		local rr = 14 * math.sqrt(math.max(p.heartRate, 40) / 80) * (1 - p.effects.respDepression * 0.6)
		rr += p.breathing.ptx * 2 + (if p.breathing.tension or p.breathing.hemo then 8 else 0)
		if p.spo2 < 90 then
			rr += (90 - p.spo2) * 0.3
		end
		p.respRate = math.clamp(rr, 4, 40)
	end
	if p.respRate <= 0 then
		p.etco2 = if p.cpr then 15 else 0
	else
		p.etco2 = math.clamp(37 * (14 / p.respRate) ^ 0.5 * math.min(1, p.cardiacOutput + 0.2), 5, 60)
	end
end

return Breathing
