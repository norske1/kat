--!nonstrict
-- Pure medical state for one casualty. Contains no Roblox instances so it can be simulated anywhere.
local Medical = script.Parent.Parent
local Config = require(Medical.Config)
local BodyParts = require(Medical.BodyParts)
local Rng = require(Medical.Rng)

local Patient = {}

local function newPart()
	return {
		wounds = {}, -- open wounds { type, size, amount, clot }
		bandaged = {}, -- bandaged wounds { type, size, amount, bandage, reopenAt }
		stitched = 0,
		tourniquet = nil, -- time applied
		fracture = 0, -- 0 none, 1 simple, 2 compound, 3 comminuted, -1 repaired/splint needed
		fractureKnown = false,
		splint = false,
		surgery = 0, -- 0 none, 1 incised, 2 exposed, 3 prepared
		access = nil, -- { kind = "IV" | "IO", fluids = { bag } }
		pulseOx = false,
	}
end

function Patient.new(options: { bloodType: string?, seed: number? }?)
	local opts = options or {}
	local rng = Rng.new(opts.seed)
	local bloodType = opts.bloodType
	if not bloodType then
		local weights = {}
		for i, t in Config.BloodTypes do
			weights[t] = Config.BloodTypeWeights[i]
		end
		bloodType = rng:pickWeighted(weights)
	end

	local parts = {}
	for _, name in BodyParts.List do
		parts[name] = newPart()
	end

	return {
		time = 0,
		alive = true,
		deathReason = nil,
		bloodType = bloodType,
		bloodVolume = Config.DefaultBloodVolume,
		heartRate = Config.DefaultHeartRate,
		bpSys = 120,
		bpDia = 80,
		resistance = Config.DefaultResistance,
		cardiacOutput = 1,
		pao2 = 95,
		spo2 = 98,
		respRate = 16,
		etco2 = 37,
		bleedRate = 0,
		pain = 0,
		painPerceived = 0,
		painBurst = 0,
		conscious = true,
		knockedOut = false,
		unconsciousCauses = {},
		arrest = nil,
		cpr = nil,
		bradycardia = 0,
		airway = {
			obstructed = false,
			occluded = false,
			headTilt = false,
			recovery = false,
			device = nil, -- "Guedel" | "KingLT"
			nextCheck = Config.AirwayCheckInterval,
		},
		breathing = {
			ptx = 0,
			tension = false,
			hemo = false,
			dpi = false,
			chestSeal = false,
			tamponade = 0,
			nextDeteriorate = Config.PneumothoraxDeteriorateInterval,
			bvmUntil = 0,
			oxygen = nil, -- "Cannula" | "Tank"
			ventilation = 1,
		},
		meds = {},
		effects = {
			pain = 0,
			hr = 0,
			resistance = 0,
			opioid = 0,
			coagulation = 0,
			sedation = 0,
			anesthesia = 0,
			antiarrhythmic = 0,
			vasopressor = 0,
		},
		coag = { factors = Config.CoagulationFactors, regen = 0 },
		hemolysis = 0,
		kidneyDamage = 0,
		nextKidneyCheck = Config.KidneyCheckInterval,
		nextWakeCheck = Config.WakeCheckInterval,
		imaged = false,
		reboa = nil, -- "III" | "I"
		aedx = false,
		triage = "None",
		parts = parts,
		log = {},
		events = {},
		rng = rng,
	}
end

function Patient.log(p, text: string)
	table.insert(p.log, 1, { t = p.time, text = text })
	while #p.log > Config.LogSize do
		table.remove(p.log)
	end
end

function Patient.event(p, name: string, data: any?)
	table.insert(p.events, { name = name, data = data })
end

function Patient.drainEvents(p)
	local events = p.events
	p.events = {}
	return events
end

function Patient.kill(p, reason: string)
	if not p.alive then
		return
	end
	p.alive = false
	p.deathReason = reason
	p.conscious = false
	p.heartRate = 0
	p.bpSys, p.bpDia = 0, 0
	p.respRate = 0
	p.cpr = nil
	Patient.log(p, "Died: " .. reason)
	Patient.event(p, "Died", reason)
end

function Patient.inArrest(p): boolean
	return p.arrest ~= nil
end

function Patient.openWoundCount(p): number
	local n = 0
	for _, part in p.parts do
		for _, w in part.wounds do
			n += w.amount
		end
	end
	return n
end

function Patient.isBleeding(p): boolean
	return p.bleedRate > 0.00001
end

-- Fully restores a patient (admin heal / respawn).
function Patient.fullHeal(p)
	local fresh = Patient.new({ bloodType = p.bloodType, seed = p.rng.state })
	for k, v in fresh do
		if k ~= "rng" and k ~= "log" and k ~= "events" then
			p[k] = v
		end
	end
	Patient.log(p, "Fully healed")
	Patient.event(p, "Healed")
end

return Patient
