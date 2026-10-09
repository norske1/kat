--!nonstrict
-- Treatment / assessment catalogue. Each action is validated and executed by the server.
--
-- ctx = { patient, part, medicLevel, isSelf, item, rng }
-- condition(ctx) -> (ok, reason?)  apply(ctx) -> result text
local Medical = script.Parent.Parent
local Config = require(Medical.Config)
local Wounds = require(Medical.Wounds)
local BodyParts = require(Medical.BodyParts)
local BloodTypes = require(Medical.BloodTypes)
local Medications = require(Medical.Medications)
local Items = require(Medical.Items)
local Patient = require(script.Parent.Patient)
local Pharmacy = require(script.Parent.Pharmacy)
local Circulation = require(script.Parent.Circulation)
local Breathing = require(script.Parent.Breathing)
local Cardiac = require(script.Parent.Cardiac)
local Simulation = require(script.Parent.Simulation)

local Actions = {}
Actions.List = {}
Actions.ById = {}
Actions.Categories = {
	"Examine",
	"Bandage",
	"Medication",
	"Airway",
	"Breathing",
	"Circulation",
	"Pharmacy",
	"Fluids",
	"Surgery",
	"Other",
}

local ARMS = { "LeftArm", "RightArm" }
local LIMBS = BodyParts.Limbs
local HEAD = { "Head" }
local TORSO = { "Torso" }
local ALL = BodyParts.List

local function define(def)
	def.parts = def.parts or ALL
	def.level = def.level or 0
	def.time = def.time or 3
	if def.allowSelf == nil then
		def.allowSelf = true
	end
	def.condition = def.condition or function()
		return true
	end
	if Config.ActionLevelOverrides[def.id] then
		def.level = Config.ActionLevelOverrides[def.id]
	end
	table.insert(Actions.List, def)
	Actions.ById[def.id] = def
	return def
end

local function check(p, key: string, value: any)
	p.checks = p.checks or {}
	p.checks[key] = { t = p.time, value = value }
end

local function partName(ctx): string
	return BodyParts.DisplayName[ctx.part]
end

local function unconscious(ctx)
	if ctx.patient.conscious then
		return false, "Patient is conscious"
	end
	return true
end

local function surgeryAllowed(ctx)
	local p = ctx.patient
	if Config.SurgeryConsciousness == "RequireAnesthesia" and p.conscious and p.effects.anesthesia < 0.2 then
		return false, "Patient needs sedation or anesthesia"
	end
	return true
end

local function surgeryPain(ctx)
	local p = ctx.patient
	if p.conscious and p.effects.anesthesia < 0.2 then
		p.painBurst = math.min(1, p.painBurst + 0.4 * (1 - p.effects.pain))
	end
end

---------------------------------------------------------------------------
-- Examine
---------------------------------------------------------------------------
local function describePulse(p, level: number): string
	local hr = math.floor(p.heartRate + 0.5)
	if hr <= 0 then
		return "No pulse"
	end
	local quality = if p.bpSys < 70 then "weak" elseif hr > 110 then "fast" elseif hr < 50 then "slow" else "normal"
	if level >= 1 then
		return string.format("Pulse %d bpm (%s)", hr, quality)
	end
	return "Pulse is " .. quality
end

define({
	id = "CheckPulse",
	name = "Check Pulse",
	category = "Examine",
	time = 2,
	condition = function(ctx)
		if ctx.patient.parts[ctx.part].tourniquet then
			return false, "Tourniquet on this limb"
		end
		return true
	end,
	apply = function(ctx)
		local p = ctx.patient
		local text = describePulse(p, ctx.medicLevel)
		check(p, "pulse", math.floor(p.heartRate + 0.5))
		return text
	end,
})

define({
	id = "CheckBloodPressure",
	name = "Check Blood Pressure",
	category = "Examine",
	parts = LIMBS,
	time = 3,
	apply = function(ctx)
		local p = ctx.patient
		local sys, dia = math.floor(p.bpSys + 0.5), math.floor(p.bpDia + 0.5)
		check(p, "bp", { sys, dia })
		if sys <= 20 then
			return "No blood pressure"
		end
		if ctx.medicLevel >= 1 then
			return string.format("Blood pressure %d/%d", sys, dia)
		end
		return if sys < 90
			then "Blood pressure is low"
			elseif sys > 150 then "Blood pressure is high"
			else "Blood pressure is normal"
	end,
})

define({
	id = "CheckResponse",
	name = "Check Response",
	category = "Examine",
	parts = HEAD,
	time = 1.5,
	allowSelf = false,
	apply = function(ctx)
		local p = ctx.patient
		if not p.alive then
			return "Patient is dead"
		elseif p.arrest then
			return "Patient is unresponsive and not breathing normally"
		elseif not p.conscious then
			return "Patient is unresponsive"
		end
		return "Patient is responsive"
	end,
})

define({
	id = "CheckAirway",
	name = "Check Airway",
	category = "Examine",
	parts = HEAD,
	time = 2.5,
	allowSelf = false,
	apply = function(ctx)
		local a = ctx.patient.airway
		a.known = true
		local found = {}
		if a.occluded then
			table.insert(found, "occluded (vomit/blood)")
		end
		if a.obstructed then
			table.insert(found, "obstructed (tongue)")
		end
		if #found == 0 then
			return "Airway is clear"
		end
		return "Airway is " .. table.concat(found, " and ")
	end,
})

define({
	id = "CheckBreathing",
	name = "Listen to Chest",
	category = "Examine",
	parts = TORSO,
	items = { "Stethoscope" },
	time = 4,
	apply = function(ctx)
		local p = ctx.patient
		local b = p.breathing
		b.known = true
		check(p, "resp", math.floor(p.respRate + 0.5))
		local notes = {}
		if p.respRate <= 0 then
			table.insert(notes, "no breath sounds")
		else
			table.insert(notes, string.format("%d breaths/min", math.floor(p.respRate + 0.5)))
		end
		if b.tension then
			table.insert(notes, "absent breath sounds on one side, tracheal shift")
		elseif b.hemo then
			table.insert(notes, "dull, absent breath sounds on one side")
		elseif b.ptx > 0 then
			table.insert(notes, if b.ptx >= 3 then "greatly diminished breath sounds" else "diminished breath sounds")
		else
			table.insert(notes, "equal breath sounds")
		end
		if b.tamponade > 0.3 then
			table.insert(notes, "muffled heart sounds")
		end
		if p.arrest then
			table.insert(notes, "no heart sounds")
		end
		return table.concat(notes, ", ")
	end,
})

define({
	id = "CheckFracture",
	name = "Check Fracture",
	category = "Examine",
	parts = LIMBS,
	time = 3,
	apply = function(ctx)
		local part = ctx.patient.parts[ctx.part]
		part.fractureKnown = true
		if part.fracture > 0 then
			return string.format("%s: %s", partName(ctx), Wounds.Fractures[part.fracture])
		end
		return partName(ctx) .. ": no fracture"
	end,
})

define({
	id = "CheckDogTag",
	name = "Check Dog Tag (blood type)",
	category = "Examine",
	parts = HEAD,
	time = 1.5,
	apply = function(ctx)
		check(ctx.patient, "bloodType", ctx.patient.bloodType)
		return "Blood type " .. ctx.patient.bloodType
	end,
})

define({
	id = "AttachPulseOx",
	name = "Attach Pulse Oximeter",
	category = "Examine",
	parts = ARMS,
	items = { "PulseOximeter" },
	time = 2,
	condition = function(ctx)
		if ctx.patient.parts[ctx.part].pulseOx then
			return false, "Already attached"
		end
		return true
	end,
	apply = function(ctx)
		ctx.patient.parts[ctx.part].pulseOx = true
		return "Pulse oximeter attached"
	end,
})

define({
	id = "RemovePulseOx",
	name = "Remove Pulse Oximeter",
	category = "Examine",
	parts = ARMS,
	time = 1,
	refund = { "PulseOximeter" },
	condition = function(ctx)
		return ctx.patient.parts[ctx.part].pulseOx, "No pulse oximeter"
	end,
	apply = function(ctx)
		ctx.patient.parts[ctx.part].pulseOx = false
		return "Pulse oximeter removed"
	end,
})

define({
	id = "CheckCoagulation",
	name = "Test Coagulation",
	category = "Examine",
	parts = ARMS,
	items = { "ClotTester" },
	level = 1,
	time = 4,
	apply = function(ctx)
		local factors = math.floor(ctx.patient.coag.factors)
		check(ctx.patient, "coag", factors)
		return string.format("Coagulation factors: %d", factors)
	end,
})

define({
	id = "Ultrasound",
	name = "Ultrasound (eFAST)",
	category = "Examine",
	parts = TORSO,
	items = { "Ultrasound" },
	level = 2,
	time = 6,
	allowSelf = false,
	apply = function(ctx)
		local p = ctx.patient
		p.imaged = true
		p.breathing.known = true
		local notes = {}
		if p.breathing.tamponade > 0 then
			table.insert(notes, "pericardial effusion (tamponade)")
		elseif p.arrest then
			table.insert(
				notes,
				"no cardiac motion"
					.. (if p.arrest.rhythm == "VF" or p.arrest.rhythm == "VT" then " (fibrillating)" else "")
			)
		else
			table.insert(notes, "normal cardiac motion")
		end
		if p.breathing.hemo then
			table.insert(notes, "fluid in pleural space")
		end
		if p.breathing.ptx > 0 or p.breathing.tension then
			table.insert(notes, "no lung sliding")
		end
		if p.bloodVolume < Config.BloodClass2 then
			table.insert(notes, "collapsed IVC (hypovolemia)")
		end
		return "Ultrasound: " .. table.concat(notes, ", ")
	end,
})

---------------------------------------------------------------------------
-- Bandages / tourniquet / splint
---------------------------------------------------------------------------
local function biggestWound(part)
	local best, bestRate = nil, -1
	for i, w in part.wounds do
		local rate = Circulation.woundBleeding(w) + Wounds.Types[w.type].pain[w.size] * 0.001
		if rate > bestRate then
			best, bestRate = i, rate
		end
	end
	return best
end

for bandageId, displayName in Wounds.BandageNames do
	local def = Wounds.Bandages[bandageId]
	define({
		id = bandageId,
		name = displayName,
		category = "Bandage",
		items = { bandageId },
		level = if bandageId == "HemostaticGauze" then 1 else 0,
		time = if bandageId == "PackingBandage" then 4 elseif bandageId == "HemostaticGauze" then 3 else 5,
		condition = function(ctx)
			if #ctx.patient.parts[ctx.part].wounds == 0 then
				return false, "No open wounds"
			end
			return true
		end,
		apply = function(ctx)
			local p = ctx.patient
			local part = p.parts[ctx.part]
			local index = biggestWound(part)
			local w = part.wounds[index]
			local covered = math.min(w.amount, def.effectiveness[w.type] or 1)
			w.amount -= covered
			if w.amount <= 0.01 then
				table.remove(part.wounds, index)
			end
			local reopenAt = nil
			if ctx.rng:chance(def.reopenChance[w.type] or 0) then
				reopenAt = p.time + ctx.rng:range(def.reopenDelay[1], def.reopenDelay[2])
			end
			table.insert(
				part.bandaged,
				{ type = w.type, size = w.size, amount = covered, bandage = bandageId, reopenAt = reopenAt }
			)
			return string.format("Bandaged %s on %s", Wounds.describe(w.type, w.size), partName(ctx))
		end,
	})
end

define({
	id = "ApplyTourniquet",
	name = "Apply Tourniquet",
	category = "Bandage",
	parts = LIMBS,
	items = { "Tourniquet" },
	time = 3,
	condition = function(ctx)
		if ctx.patient.parts[ctx.part].tourniquet then
			return false, "Tourniquet already applied"
		end
		return true
	end,
	apply = function(ctx)
		ctx.patient.parts[ctx.part].tourniquet = ctx.patient.time
		return "Tourniquet applied to " .. partName(ctx)
	end,
})

define({
	id = "RemoveTourniquet",
	name = "Remove Tourniquet",
	category = "Bandage",
	parts = LIMBS,
	time = 2,
	refund = { "Tourniquet" },
	condition = function(ctx)
		return ctx.patient.parts[ctx.part].tourniquet ~= nil, "No tourniquet"
	end,
	apply = function(ctx)
		ctx.patient.parts[ctx.part].tourniquet = nil
		return "Tourniquet removed from " .. partName(ctx)
	end,
})

define({
	id = "ApplySplint",
	name = "Apply Splint",
	category = "Bandage",
	parts = LIMBS,
	items = { "Splint" },
	time = 5,
	condition = function(ctx)
		local part = ctx.patient.parts[ctx.part]
		if part.splint then
			return false, "Already splinted"
		end
		if part.fracture == 0 then
			return false, "No fracture"
		end
		return true
	end,
	apply = function(ctx)
		local part = ctx.patient.parts[ctx.part]
		part.splint = true
		if part.fracture == -1 then
			part.fracture = 0
		end
		return "Splint applied to " .. partName(ctx)
	end,
})

define({
	id = "RemoveSplint",
	name = "Remove Splint",
	category = "Bandage",
	parts = LIMBS,
	time = 3,
	refund = { "Splint" },
	condition = function(ctx)
		return ctx.patient.parts[ctx.part].splint, "No splint"
	end,
	apply = function(ctx)
		ctx.patient.parts[ctx.part].splint = false
		return "Splint removed"
	end,
})

---------------------------------------------------------------------------
-- Medication (autoinjectors / oral, no IV needed) and Pharmacy (IV/IO)
---------------------------------------------------------------------------
local function giveMed(medId: string)
	return function(ctx)
		Pharmacy.administer(ctx.patient, medId, ctx.rng)
		return Medications[medId].name .. " administered"
	end
end

local simpleMeds = {
	{ id = "AdrenalineAuto", med = "Adrenaline", name = "Adrenaline Autoinjector", parts = LIMBS },
	{ id = "AnalgesicAuto", med = "Analgesic", name = "Analgesic Autoinjector", parts = LIMBS },
	{ id = "ReversalSpray", med = "ReversalSpray", name = "Reversal Spray (nasal)", parts = HEAD },
	{ id = "PainRelief", med = "PainRelief", name = "Pain Relief Tablets", parts = HEAD, conscious = true },
	{ id = "CWMP", med = "CWMP", name = "Combat Med Pack", parts = HEAD, conscious = true },
	{ id = "PainInhaler", med = "PainInhaler", name = "Pain Relief Inhaler", parts = HEAD, conscious = true },
}

for _, m in simpleMeds do
	define({
		id = m.id,
		name = m.name,
		category = "Medication",
		parts = m.parts,
		items = { m.id },
		time = 2,
		condition = function(ctx)
			if m.conscious and not ctx.patient.conscious then
				return false, "Patient must be conscious"
			end
			return true
		end,
		apply = giveMed(m.med),
	})
end

define({
	id = "SmellingSalts",
	name = "Smelling Salts",
	category = "Medication",
	parts = HEAD,
	items = { "SmellingSalts" },
	time = 2,
	allowSelf = false,
	condition = unconscious,
	apply = function(ctx)
		local p = ctx.patient
		if Simulation.hasStableVitals(p) and #Simulation.unconsciousCauses(p) == 1 and p.knockedOut then
			if ctx.rng:chance(Config.SmellingSaltsMaxChance) then
				p.knockedOut = false
				return "Patient is coming around"
			end
		end
		return "No response"
	end,
})

define({
	id = "Reorient",
	name = "Reorient / Shake",
	category = "Medication",
	parts = HEAD,
	time = 2,
	allowSelf = false,
	condition = unconscious,
	apply = function(ctx)
		local p = ctx.patient
		if p.knockedOut and Simulation.hasStableVitals(p) and ctx.rng:chance(Config.ReorientMaxChance * 0.5) then
			p.knockedOut = false
			return "Patient is coming around"
		end
		return "No response"
	end,
})

local function needsAccess(ctx)
	if not Pharmacy.hasAccess(ctx.patient) then
		return false, "No working IV/IO access"
	end
	return true
end

local ivMeds = {
	Adrenaline = 1,
	RhythmStabiliser = 1,
	MildRhythmStabiliser = 1,
	HeartRateBooster = 1,
	ClottingAgent = 1,
	StrongClottingAgent = 2,
	FieldAnesthetic = 1,
	StrongAnalgesic = 2,
	MildAnalgesic = 1,
	PressureBooster = 1,
	PressureSupport = 1,
	PressureReducer = 1,
	SurgicalSedative = 2,
	Sedative = 2,
	SedativeReversal = 2,
}
local ivOrder = {}
for medId in ivMeds do
	table.insert(ivOrder, medId)
end
table.sort(ivOrder)

for _, medId in ivOrder do
	define({
		id = "Push" .. medId,
		name = "Push " .. Items[medId].name,
		category = "Pharmacy",
		parts = TORSO,
		items = { medId },
		level = ivMeds[medId],
		time = 3,
		allowSelf = medId ~= "SurgicalSedative" and medId ~= "Sedative",
		condition = needsAccess,
		apply = giveMed(medId),
	})
end

define({
	id = "IV16",
	name = "Insert 16g IV",
	category = "Pharmacy",
	parts = LIMBS,
	items = { "IV16" },
	level = 1,
	time = 5,
	condition = function(ctx)
		if ctx.patient.parts[ctx.part].access then
			return false, "Already has access"
		end
		return true
	end,
	apply = function(ctx)
		ctx.patient.parts[ctx.part].access = { kind = "IV", fluids = {} }
		return "16g IV placed in " .. partName(ctx)
	end,
})

define({
	id = "FASTIO",
	name = "Insert FAST IO (sternal)",
	category = "Pharmacy",
	parts = TORSO,
	items = { "FASTIO" },
	level = 1,
	time = 4,
	allowSelf = false,
	condition = function(ctx)
		if ctx.patient.parts.Torso.access then
			return false, "Already has access"
		end
		return true
	end,
	apply = function(ctx)
		local p = ctx.patient
		p.parts.Torso.access = { kind = "IO", fluids = {} }
		if p.conscious then
			p.painBurst = math.min(1, p.painBurst + Config.IOInsertPain * (1 - p.effects.pain))
		end
		return "FAST IO placed"
	end,
})

define({
	id = "RemoveAccess",
	name = "Remove IV/IO",
	category = "Pharmacy",
	time = 2,
	condition = function(ctx)
		return ctx.patient.parts[ctx.part].access ~= nil, "No IV/IO here"
	end,
	apply = function(ctx)
		ctx.patient.parts[ctx.part].access = nil
		return "Access removed from " .. partName(ctx)
	end,
})

---------------------------------------------------------------------------
-- Fluids (each bag is its own action; the UI only lists bags you carry)
---------------------------------------------------------------------------
local function fluidAction(itemId: string, kind: string, volume: number, bloodType: string?)
	define({
		id = "Give" .. itemId,
		name = Items[itemId].name,
		category = "Fluids",
		items = { itemId },
		level = 1,
		time = 3,
		condition = function(ctx)
			if not ctx.patient.parts[ctx.part].access then
				return false, "Needs IV/IO on this body part"
			end
			return true
		end,
		apply = function(ctx)
			Pharmacy.attachFluid(ctx.patient, ctx.part, kind, volume, bloodType)
			return string.format("%s hung on %s", Items[itemId].name, partName(ctx))
		end,
	})
end

for _, volume in Config.FluidVolumes do
	fluidAction("Saline" .. volume, "Saline", volume)
	fluidAction("Plasma" .. volume, "Plasma", volume)
	for _, bloodType in Config.BloodTypes do
		fluidAction("Blood" .. BloodTypes.toKey(bloodType) .. volume, "Blood", volume, bloodType)
	end
end

define({
	id = "DrawBlood",
	name = "Draw Blood (500ml)",
	category = "Fluids",
	parts = ARMS,
	items = { "BloodDrawKit" },
	level = 1,
	time = 15,
	allowSelf = false,
	condition = function(ctx)
		if ctx.patient.bloodVolume - 0.5 < Config.DrawBloodMinVolume then
			return false, "Patient cannot spare blood"
		end
		return true
	end,
	apply = function(ctx)
		local p = ctx.patient
		p.bloodVolume -= 0.5
		ctx.grant = { ["Blood" .. BloodTypes.toKey(p.bloodType) .. "500"] = 1 }
		return string.format("Drew 500ml of %s blood", p.bloodType)
	end,
})

---------------------------------------------------------------------------
-- Airway
---------------------------------------------------------------------------
define({
	id = "HeadTilt",
	name = "Head Tilt / Chin Lift (hold)",
	category = "Airway",
	parts = HEAD,
	time = 2,
	allowSelf = false,
	hold = true,
	condition = function(ctx)
		if ctx.patient.airway.headTilt then
			return false, "Already holding"
		end
		return unconscious(ctx)
	end,
	apply = function(ctx)
		ctx.patient.airway.headTilt = true
		return "Holding head tilt - stay close to the patient"
	end,
})

define({
	id = "ReleaseHeadTilt",
	name = "Release Head Tilt",
	category = "Airway",
	parts = HEAD,
	time = 0.5,
	allowSelf = false,
	condition = function(ctx)
		return ctx.patient.airway.headTilt, "Not holding"
	end,
	apply = function(ctx)
		ctx.patient.airway.headTilt = false
		return "Released head tilt"
	end,
})

define({
	id = "RecoveryPosition",
	name = "Recovery Position",
	category = "Airway",
	parts = HEAD,
	time = 4,
	allowSelf = false,
	condition = function(ctx)
		local p = ctx.patient
		if p.airway.recovery then
			return false, "Already in recovery position"
		end
		if p.cpr then
			return false, "CPR in progress"
		end
		return unconscious(ctx)
	end,
	apply = function(ctx)
		ctx.patient.airway.recovery = true
		return "Placed in recovery position"
	end,
})

define({
	id = "CancelRecovery",
	name = "Roll onto Back",
	category = "Airway",
	parts = HEAD,
	time = 2,
	allowSelf = false,
	condition = function(ctx)
		return ctx.patient.airway.recovery, "Not in recovery position"
	end,
	apply = function(ctx)
		ctx.patient.airway.recovery = false
		return "Rolled onto back"
	end,
})

local function airwayDevice(id: string, label: string, level: number)
	define({
		id = "Insert" .. id,
		name = "Insert " .. label,
		category = "Airway",
		parts = HEAD,
		items = { id },
		level = level,
		time = if id == "AirwayTube" then 6 else 3,
		allowSelf = false,
		condition = function(ctx)
			local a = ctx.patient.airway
			if a.device then
				return false, a.device .. " already inserted"
			end
			if a.occluded then
				return false, "Airway is occluded - suction first"
			end
			return unconscious(ctx)
		end,
		apply = function(ctx)
			local a = ctx.patient.airway
			a.device = id
			a.obstructed = false
			return label .. " inserted"
		end,
	})
end
airwayDevice("Guedel", "Guedel Tube", 0)
airwayDevice("AirwayTube", "Airway Tube", 1)

define({
	id = "RemoveAirwayDevice",
	name = "Remove Airway Device",
	category = "Airway",
	parts = HEAD,
	time = 2,
	allowSelf = false,
	condition = function(ctx)
		return ctx.patient.airway.device ~= nil, "No airway device"
	end,
	apply = function(ctx)
		local a = ctx.patient.airway
		local device = a.device
		a.device = nil
		return device .. " removed"
	end,
})

define({
	id = "Suction",
	name = "Suction Airway",
	category = "Airway",
	parts = HEAD,
	items = { "SuctionPump" },
	level = 1,
	time = 6,
	allowSelf = false,
	condition = function(ctx)
		if ctx.patient.airway.device == "AirwayTube" then
			return false, "Remove the airway tube first"
		end
		return true
	end,
	apply = function(ctx)
		local a = ctx.patient.airway
		local had = a.occluded
		a.occluded = false
		return if had then "Airway suctioned clear" else "Nothing to suction"
	end,
})

define({
	id = "ManualSweep",
	name = "Finger Sweep / Clear Airway",
	category = "Airway",
	parts = HEAD,
	time = 8,
	allowSelf = false,
	condition = unconscious,
	apply = function(ctx)
		local a = ctx.patient.airway
		if a.occluded and ctx.rng:chance(Config.HeadTurnSuccessChance) then
			a.occluded = false
			return "Cleared the airway"
		end
		return if a.occluded then "Could not clear the airway" else "Airway looks clear"
	end,
})

---------------------------------------------------------------------------
-- Breathing
---------------------------------------------------------------------------
define({
	id = "ChestSeal",
	name = "Apply Chest Seal",
	category = "Breathing",
	parts = TORSO,
	items = { "ChestSeal" },
	time = 5,
	condition = function(ctx)
		if ctx.patient.breathing.chestSeal then
			return false, "Chest seal already applied"
		end
		return true
	end,
	apply = function(ctx)
		local b = ctx.patient.breathing
		b.chestSeal = true
		b.dpi = false
		local had = b.ptx
		b.ptx = 0
		if had > 0 then
			return "Chest seal applied - breathing improves"
		end
		return "Chest seal applied"
	end,
})

define({
	id = "NeedleDecompression",
	name = "Needle Decompression (AAT)",
	category = "Breathing",
	parts = TORSO,
	items = { "AATKit" },
	level = 1,
	time = 7,
	allowSelf = false,
	condition = function(ctx)
		if not ctx.patient.breathing.chestSeal then
			return false, "Apply a chest seal first"
		end
		return true
	end,
	apply = function(ctx)
		local b = ctx.patient.breathing
		if b.tension then
			b.tension = false
			return "Rush of air - tension pneumothorax relieved"
		end
		return "No change"
	end,
})

define({
	id = "ChestDrain",
	name = "Chest Tube Drainage (AAT)",
	category = "Breathing",
	parts = TORSO,
	items = { "AATKit" },
	level = 1,
	time = 12,
	allowSelf = false,
	condition = function(ctx)
		if not ctx.patient.breathing.chestSeal then
			return false, "Apply a chest seal first"
		end
		return true
	end,
	apply = function(ctx)
		local b = ctx.patient.breathing
		if b.hemo or b.tension then
			b.hemo = false
			b.tension = false
			return "Chest drained - hemothorax resolved"
		end
		return "Little drainage"
	end,
})

define({
	id = "UseBVM",
	name = "Ventilate with BVM",
	category = "Breathing",
	parts = HEAD,
	items = { "BVM" },
	time = 6,
	allowSelf = false,
	condition = unconscious,
	apply = function(ctx)
		local b = ctx.patient.breathing
		b.bvmUntil = ctx.patient.time + 20
		if ctx.patient.airway.occluded then
			return "Resistance felt - airway occluded"
		end
		return "Ventilating" .. (if b.oxygen == "Tank" then " with oxygen" else "")
	end,
})

define({
	id = "ConnectOxygen",
	name = "Connect Oxygen Tank",
	category = "Breathing",
	parts = HEAD,
	items = { "OxygenTank" },
	level = 1,
	time = 4,
	condition = function(ctx)
		if ctx.patient.breathing.oxygen == "Tank" then
			return false, "Oxygen already connected"
		end
		return true
	end,
	apply = function(ctx)
		ctx.patient.breathing.oxygen = "Tank"
		return "Oxygen tank connected"
	end,
})

define({
	id = "NasalCannula",
	name = "Nasal Cannula",
	category = "Breathing",
	parts = HEAD,
	items = { "NasalCannula" },
	level = 1,
	time = 3,
	condition = function(ctx)
		if ctx.patient.breathing.oxygen then
			return false, "Oxygen already applied"
		end
		return true
	end,
	apply = function(ctx)
		ctx.patient.breathing.oxygen = "Cannula"
		return "Nasal cannula applied"
	end,
})

define({
	id = "RemoveOxygen",
	name = "Remove Oxygen",
	category = "Breathing",
	parts = HEAD,
	time = 2,
	condition = function(ctx)
		return ctx.patient.breathing.oxygen ~= nil, "No oxygen applied"
	end,
	apply = function(ctx)
		local b = ctx.patient.breathing
		if b.oxygen == "Tank" then
			ctx.grant = { OxygenTank = 1 }
		end
		b.oxygen = nil
		return "Oxygen removed"
	end,
})

---------------------------------------------------------------------------
-- Circulation
---------------------------------------------------------------------------
define({
	id = "CPR",
	name = "CPR (one cycle)",
	category = "Circulation",
	parts = TORSO,
	time = 15,
	allowSelf = false,
	cpr = true,
	condition = function(ctx)
		local p = ctx.patient
		if p.airway.recovery then
			return false, "Roll patient onto back first"
		end
		if not p.alive then
			return false, "Patient is dead"
		end
		return unconscious(ctx)
	end,
	apply = function(ctx)
		local p = ctx.patient
		if not p.arrest then
			p.painBurst = math.min(1, p.painBurst + 0.1)
			return "Patient has a pulse"
		end
		local _, text = Cardiac.cprCycle(p, ctx.medicLevel)
		return text
	end,
})

define({
	id = "UseAED",
	name = "Use AED (analyse & shock)",
	category = "Circulation",
	parts = TORSO,
	items = { "AED" },
	time = 8,
	allowSelf = false,
	condition = unconscious,
	apply = function(ctx)
		local p = ctx.patient
		local rhythm, shockable = Cardiac.analyze(p)
		if not shockable then
			return "AED: no shock advised"
		end
		local _, text = Cardiac.shock(p, false)
		local _ = rhythm
		return "AED: " .. text
	end,
})

define({
	id = "AttachAEDX",
	name = "Attach AED-X Monitor",
	category = "Circulation",
	parts = TORSO,
	items = { "AEDX" },
	level = 1,
	time = 4,
	allowSelf = false,
	condition = function(ctx)
		return not ctx.patient.aedx, "Monitor already attached"
	end,
	apply = function(ctx)
		ctx.patient.aedx = true
		return "AED-X monitor attached"
	end,
})

define({
	id = "DetachAEDX",
	name = "Detach AED-X Monitor",
	category = "Circulation",
	parts = TORSO,
	time = 2,
	allowSelf = false,
	condition = function(ctx)
		return ctx.patient.aedx, "No monitor attached"
	end,
	apply = function(ctx)
		ctx.patient.aedx = false
		return "AED-X monitor detached"
	end,
})

define({
	id = "AEDXShock",
	name = "AED-X Manual Shock (200J)",
	category = "Circulation",
	parts = TORSO,
	level = 1,
	time = Config.AEDChargeTime,
	allowSelf = false,
	condition = function(ctx)
		if not ctx.patient.aedx then
			return false, "Attach the AED-X first"
		end
		return true
	end,
	apply = function(ctx)
		local _, text = Cardiac.shock(ctx.patient, true)
		return "Shock: " .. text
	end,
})

define({
	id = "PericardialTap",
	name = "Pericardial Tap",
	category = "Circulation",
	parts = TORSO,
	level = 2,
	time = 8,
	allowSelf = false,
	condition = function(ctx)
		if not ctx.patient.imaged then
			return false, "Image the patient with ultrasound first"
		end
		return true
	end,
	apply = function(ctx)
		local p = ctx.patient
		p.imaged = false
		if p.breathing.tamponade > 0 then
			p.breathing.tamponade = 0
			return "Effusion drained"
		end
		return "Dry tap"
	end,
})

define({
	id = "PlaceREBOA",
	name = "Place REBOA (Zone III)",
	category = "Circulation",
	parts = { "RightLeg" },
	items = { "REBOA" },
	level = 2,
	time = 10,
	allowSelf = false,
	condition = function(ctx)
		local p = ctx.patient
		if p.reboa then
			return false, "REBOA already placed"
		end
		if not p.imaged then
			return false, "Image the patient with ultrasound first"
		end
		return true
	end,
	apply = function(ctx)
		ctx.patient.reboa = "III"
		ctx.patient.imaged = false
		return "REBOA inflated in zone III - leg bleeding stopped"
	end,
})

define({
	id = "AdvanceREBOA",
	name = "Advance REBOA (Zone I)",
	category = "Circulation",
	parts = { "RightLeg" },
	level = 2,
	time = 5,
	allowSelf = false,
	condition = function(ctx)
		return ctx.patient.reboa == "III", "REBOA not in zone III"
	end,
	apply = function(ctx)
		ctx.patient.reboa = "I"
		return "REBOA advanced to zone I"
	end,
})

define({
	id = "RemoveREBOA",
	name = "Remove REBOA",
	category = "Circulation",
	parts = { "RightLeg" },
	level = 2,
	time = 5,
	allowSelf = false,
	condition = function(ctx)
		return ctx.patient.reboa ~= nil, "No REBOA placed"
	end,
	apply = function(ctx)
		ctx.patient.reboa = nil
		return "REBOA removed"
	end,
})

---------------------------------------------------------------------------
-- Surgery
---------------------------------------------------------------------------
define({
	id = "ClosedReduction",
	name = "Closed Reduction",
	category = "Surgery",
	parts = LIMBS,
	level = 1,
	time = 6,
	allowSelf = false,
	condition = function(ctx)
		local part = ctx.patient.parts[ctx.part]
		if part.fracture ~= 1 or not part.fractureKnown then
			return false, "Needs a diagnosed simple fracture"
		end
		return true
	end,
	apply = function(ctx)
		local p = ctx.patient
		local part = p.parts[ctx.part]
		if p.conscious then
			p.painBurst = math.min(1, p.painBurst + 0.5 * (1 - p.effects.pain))
		end
		part.fracture = if part.splint then 0 else -1
		return "Bone set - apply a splint"
	end,
})

local function surgeryStep(def)
	local base = def.condition
	def.category = "Surgery"
	def.parts = LIMBS
	def.allowSelf = false
	def.condition = function(ctx)
		local part = ctx.patient.parts[ctx.part]
		if part.fracture < 2 or not part.fractureKnown then
			return false, "Needs a diagnosed compound/comminuted fracture"
		end
		local ok, reason = surgeryAllowed(ctx)
		if not ok then
			return ok, reason
		end
		return base(ctx, part)
	end
	local apply = def.apply
	def.apply = function(ctx)
		surgeryPain(ctx)
		return apply(ctx, ctx.patient.parts[ctx.part])
	end
	define(def)
end

surgeryStep({
	id = "Incision",
	name = "Incision (scalpel)",
	items = { "Scalpel" },
	level = 2,
	time = 6,
	condition = function(_, part)
		return part.surgery == 0, "Already incised"
	end,
	apply = function(ctx, part)
		part.surgery = 1
		Circulation.addWound(part.wounds, { type = "Cut", size = 1, amount = 1, clot = 0 })
		return "Incision made on " .. partName(ctx)
	end,
})

surgeryStep({
	id = "ExposeFracture",
	name = "Expose Fracture (retractor)",
	items = { "Retractor" },
	level = 2,
	time = 5,
	condition = function(_, part)
		return part.surgery == 1, "Make an incision first"
	end,
	apply = function(_, part)
		part.surgery = 2
		return "Fracture exposed"
	end,
})

surgeryStep({
	id = "IrrigateWound",
	name = "Irrigate (250ml saline)",
	items = { "Saline250", "Saline500", "Saline1000" },
	level = 2,
	time = 6,
	condition = function(_, part)
		if part.fracture ~= 2 then
			return false, "Only for compound fractures"
		end
		return part.surgery == 2, "Expose the fracture first"
	end,
	apply = function(_, part)
		part.surgery = 3
		return "Wound irrigated - ready for open reduction"
	end,
})

surgeryStep({
	id = "ClampWound",
	name = "Clamp Wound",
	items = { "Clamp" },
	level = 2,
	time = 5,
	condition = function(_, part)
		if part.fracture ~= 3 then
			return false, "Only for comminuted fractures"
		end
		return part.surgery == 2, "Expose the fracture first"
	end,
	apply = function(_, part)
		part.surgery = 3
		return "Bleeders clamped - ready for open reduction"
	end,
})

surgeryStep({
	id = "OpenReduction",
	name = "Open Reduction (bone plate)",
	items = { "BonePlate" },
	level = 2,
	time = 12,
	condition = function(_, part)
		return part.surgery == 3, "Prepare the fracture first"
	end,
	apply = function(_, part)
		part.surgery = 0
		part.fracture = 0
		for i = #part.wounds, 1, -1 do
			if part.wounds[i].type == "Cut" and part.wounds[i].size == 1 then
				table.insert(
					part.bandaged,
					{ type = "Cut", size = 1, amount = part.wounds[i].amount, bandage = "Stitch" }
				)
				table.remove(part.wounds, i)
				break
			end
		end
		return "Bone plated and closed"
	end,
})

define({
	id = "StitchWounds",
	name = "Stitch Bandaged Wounds",
	category = "Surgery",
	items = { "SurgicalKit" },
	level = 1,
	time = 3,
	allowSelf = false,
	scaleTime = function(ctx)
		local n = 0
		for _, b in ctx.patient.parts[ctx.part].bandaged do
			n += math.ceil(b.amount)
		end
		return math.max(1, n)
	end,
	condition = function(ctx)
		if #ctx.patient.parts[ctx.part].bandaged == 0 then
			return false, "No bandaged wounds"
		end
		return true
	end,
	apply = function(ctx)
		local part = ctx.patient.parts[ctx.part]
		local n = 0
		for _, b in part.bandaged do
			n += b.amount
		end
		part.bandaged = {}
		part.stitched += n
		return string.format("Stitched %d wound(s)", math.ceil(n))
	end,
})

define({
	id = "NPWT",
	name = "NPWT Dressing (bandage + stitch all)",
	category = "Surgery",
	items = { "NPWT" },
	level = 1,
	time = 10,
	allowSelf = false,
	condition = function(ctx)
		local part = ctx.patient.parts[ctx.part]
		if #part.wounds == 0 and #part.bandaged == 0 then
			return false, "No wounds"
		end
		return true
	end,
	apply = function(ctx)
		surgeryPain(ctx)
		local part = ctx.patient.parts[ctx.part]
		local n = 0
		for _, w in part.wounds do
			n += w.amount
		end
		for _, b in part.bandaged do
			n += b.amount
		end
		part.wounds = {}
		part.bandaged = {}
		part.stitched += n
		return string.format("NPWT closed %d wound(s)", math.ceil(n))
	end,
})

---------------------------------------------------------------------------
-- Other
---------------------------------------------------------------------------
for _, tag in { "Minimal", "Delayed", "Immediate", "Deceased", "None" } do
	define({
		id = "Triage" .. tag,
		name = if tag == "None" then "Remove Triage Tag" else "Triage: " .. tag,
		category = "Other",
		parts = TORSO,
		time = 0.5,
		allowSelf = false,
		condition = function(ctx)
			return ctx.patient.triage ~= tag, "Already tagged"
		end,
		apply = function(ctx)
			ctx.patient.triage = tag
			return if tag == "None" then "Triage tag removed" else "Tagged " .. tag
		end,
	})
end

define({
	id = "Carry",
	name = "Carry Patient",
	category = "Other",
	parts = TORSO,
	time = 3,
	allowSelf = false,
	server = "Carry",
	condition = unconscious,
	apply = function()
		return "Carrying patient (press G to drop)"
	end,
})

define({
	id = "Drag",
	name = "Drag Patient",
	category = "Other",
	parts = TORSO,
	time = 1.5,
	allowSelf = false,
	server = "Drag",
	condition = unconscious,
	apply = function()
		return "Dragging patient (press G to drop)"
	end,
})

---------------------------------------------------------------------------
-- Validation helpers
---------------------------------------------------------------------------
function Actions.appliesToPart(def, part: string): boolean
	return table.find(def.parts, part) ~= nil
end

-- inventoryHas(itemId) -> bool, used to pick the first matching item
function Actions.pickItem(def, inventoryHas: (string) -> boolean): (boolean, string?)
	if not def.items then
		return true, nil
	end
	for _, itemId in def.items do
		if inventoryHas(itemId) then
			return true, itemId
		end
	end
	return false, nil
end

-- Returns ok, reason. Does not check items or distance.
function Actions.validate(def, ctx): (boolean, string?)
	local p = ctx.patient
	if not Actions.appliesToPart(def, ctx.part) then
		return false, "Wrong body part"
	end
	if not p.alive and def.category ~= "Examine" and def.server == nil then
		return false, "Patient is dead"
	end
	if ctx.isSelf and not def.allowSelf then
		return false, "Cannot do this to yourself"
	end
	if ctx.medicLevel < def.level then
		return false, if def.level >= 2 then "Requires doctor" else "Requires medic"
	end
	local ok, reason = def.condition(ctx)
	if not ok then
		return false, reason or "Not possible"
	end
	return true
end

function Actions.duration(def, ctx): number
	local t = def.time
	if def.scaleTime then
		t *= def.scaleTime(ctx)
	end
	if ctx.isSelf then
		t *= 1.25
	end
	return t
end

function Actions.execute(def, ctx): string
	local text = def.apply(ctx)
	if text then
		Patient.log(ctx.patient, string.format("%s: %s", ctx.medicName or "Medic", text))
	end
	return text
end

-- Exposed for tests and adapters
Actions._breathing = Breathing

return Actions
