--!nonstrict
-- Builds the serialisable view of a patient that is sent to the medic UI.
-- Only information the viewer could plausibly know (from monitors / recent checks) is exposed.
local Medical = script.Parent.Parent
local Config = require(Medical.Config)
local Wounds = require(Medical.Wounds)
local BodyParts = require(Medical.BodyParts)
local Medications = require(Medical.Medications)
local Circulation = require(script.Parent.Circulation)
local Cardiac = require(script.Parent.Cardiac)
local Pharmacy = require(script.Parent.Pharmacy)
local Actions = require(script.Parent.Actions)
local Patient = require(script.Parent.Patient)

local Snapshot = {}

local CHECK_TTL = 60

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function bleedLevel(rate: number): number
	if rate <= 0 then
		return 0
	elseif rate < 0.002 then
		return 1
	elseif rate < 0.006 then
		return 2
	end
	return 3
end

local bloodText = {
	[0] = nil,
	[1] = "Lost some blood",
	[2] = "Lost a lot of blood",
	[3] = "Lost a large amount of blood",
	[4] = "Lost a fatal amount of blood",
}

local function painText(pain: number): string?
	if pain > 0.7 then
		return "In severe pain"
	elseif pain > 0.4 then
		return "In pain"
	elseif pain > 0.1 then
		return "In mild pain"
	end
	return nil
end

local function recentCheck(p, key)
	local c = p.checks and p.checks[key]
	if c and p.time - c.t <= CHECK_TTL then
		return c.value
	end
	return nil
end

local function partView(p, name: string)
	local part = p.parts[name]
	local wounds = {}
	local bleeding = 0
	for _, w in part.wounds do
		local rate = Circulation.woundBleeding(w)
		bleeding += rate
		table.insert(wounds, {
			text = string.format(
				"%s%s",
				Wounds.describe(w.type, w.size),
				if w.amount > 1.05 then string.format(" x%d", math.ceil(w.amount)) else ""
			),
			bleed = bleedLevel(rate),
		})
	end
	local bandaged = {}
	for _, b in part.bandaged do
		table.insert(
			bandaged,
			string.format("%s (%s)", Wounds.describe(b.type, b.size), Wounds.BandageNames[b.bandage] or b.bandage)
		)
	end
	local fracture = nil
	if part.fracture > 0 then
		if part.fractureKnown then
			fracture = Wounds.Fractures[part.fracture]
		elseif not Config.Hardcore then
			fracture = "Possible fracture (swelling, deformity)"
		end
	elseif part.fracture == -1 then
		fracture = "Reduced fracture - needs splint"
	end
	local access = nil
	if part.access then
		local bags = {}
		for _, bag in part.access.fluids do
			table.insert(
				bags,
				string.format(
					"%s %dml",
					bag.kind .. (if bag.bloodType then " " .. bag.bloodType else ""),
					round(bag.remaining * 1000)
				)
			)
		end
		access = {
			kind = if part.access.kind == "IO" then "FAST IO" else "16g IV",
			flowing = Pharmacy.accessFlows(p, name),
			bags = bags,
		}
	end
	return {
		wounds = wounds,
		bandaged = bandaged,
		stitched = round(part.stitched),
		bleed = bleedLevel(if part.tourniquet then 0 else bleeding),
		tourniquet = if part.tourniquet then round(p.time - part.tourniquet) else nil,
		fracture = fracture,
		splint = part.splint,
		surgery = part.surgery,
		access = access,
		pulseOx = part.pulseOx,
	}
end

function Snapshot.vitals(p, opts)
	local monitor = p.aedx
	local pulseOx = p.parts.LeftArm.pulseOx or p.parts.RightArm.pulseOx
	local v = { source = "none" }
	if monitor then
		v.source = "monitor"
		v.hr = round(p.heartRate)
		v.bp = { round(p.bpSys), round(p.bpDia) }
		v.spo2 = if p.arrest and not p.cpr then nil else round(p.spo2)
		v.rr = round(p.respRate)
		v.etco2 = round(p.etco2)
		local rhythm = if p.arrest then p.arrest.rhythm else "Sinus"
		if p.breathing.tamponade > 0.5 then
			rhythm = "Tamponade"
		end
		v.rhythm = rhythm
		v.rhythmName = Cardiac.RhythmNames[rhythm] or "Low-voltage complexes (tamponade)"
		v.shockable = p.arrest ~= nil and Cardiac.isShockable(p.arrest.rhythm)
	else
		if pulseOx then
			v.source = "pulseox"
			if p.cardiacOutput > 0.15 or p.cpr then
				v.hr = round(p.heartRate)
				v.spo2 = round(p.spo2)
			end
		end
		v.hr = v.hr or recentCheck(p, "pulse")
		v.bp = recentCheck(p, "bp")
		v.rr = recentCheck(p, "resp")
	end
	if opts.viewerLevel < 1 and v.source == "none" then
		v.hr = nil
		v.bp = nil
	end
	return v
end

-- opts = { viewerLevel, isSelf, inventoryHas = fn(itemId)->bool, infinite = bool }
function Snapshot.build(p, opts)
	local parts = {}
	for _, name in BodyParts.List do
		parts[name] = partView(p, name)
	end

	local status = {}
	local blood = bloodText[Circulation.hemorrhageClass(p.bloodVolume)]
	if blood then
		table.insert(status, blood)
	end
	local pain = painText(p.painPerceived)
	if pain then
		table.insert(status, pain)
	end
	if not p.alive then
		table.insert(status, 1, "Dead (" .. tostring(p.deathReason) .. ")")
	elseif p.arrest then
		table.insert(status, 1, "No pulse - not breathing")
	elseif not p.conscious then
		table.insert(status, 1, "Unconscious")
	end
	if p.cpr then
		table.insert(status, "CPR in progress")
	end
	local b = p.breathing
	if b.dpi then
		table.insert(status, "Sucking chest wound")
	end
	if b.chestSeal then
		table.insert(status, "Chest seal applied")
	end
	if p.breathing.known or not Config.Hardcore then
		if b.tension then
			table.insert(status, "Tension pneumothorax")
		elseif b.hemo then
			table.insert(status, "Hemopneumothorax")
		elseif b.ptx > 0 then
			table.insert(
				status,
				if p.breathing.known then "Pneumothorax (stage " .. b.ptx .. ")" else "Short of breath"
			)
		end
	end
	if p.imaged then
		table.insert(status, "Imaged (ultrasound)")
	end
	if p.reboa then
		table.insert(status, "REBOA zone " .. p.reboa)
	end
	if b.oxygen then
		table.insert(status, if b.oxygen == "Tank" then "Oxygen connected" else "Nasal cannula")
	end
	if p.time < b.bvmUntil then
		table.insert(status, "Being ventilated (BVM)")
	end

	local a = p.airway
	local airway = {
		device = a.device,
		recovery = a.recovery,
		headTilt = a.headTilt,
		known = a.known == true,
		obstructed = if a.known then a.obstructed else nil,
		occluded = if a.known then a.occluded else nil,
	}

	local meds = {}
	if opts.viewerLevel >= 1 or opts.isSelf then
		local counts = {}
		for _, dose in p.meds do
			counts[dose.id] = (counts[dose.id] or 0) + 1
		end
		for id, n in counts do
			table.insert(meds, string.format("%s x%d", Medications[id].name, n))
		end
		table.sort(meds)
	end

	local log = {}
	for i, entry in p.log do
		if i > 15 then
			break
		end
		table.insert(log, { ago = round(p.time - entry.t), text = entry.text })
	end

	local actions = {}
	for _, def in Actions.List do
		local hasItem = true
		if def.items and not opts.infinite then
			hasItem = Actions.pickItem(def, opts.inventoryHas)
		end
		if hasItem and (def.level <= opts.viewerLevel or def.category == "Examine") then
			for _, name in def.parts do
				local ctx =
					{ patient = p, part = name, medicLevel = opts.viewerLevel, isSelf = opts.isSelf, rng = p.rng }
				local ok, reason = Actions.validate(def, ctx)
				local show = ok
				if
					not ok
					and (def.category :: string) ~= "Fluids"
					and reason ~= "Wrong body part"
					and reason ~= "Cannot do this to yourself"
				then
					show = def.items ~= nil or def.category == "Examine"
				end
				if show then
					actions[name] = actions[name] or {}
					table.insert(actions[name], {
						id = def.id,
						name = def.name,
						category = def.category,
						time = Actions.duration(def, ctx),
						enabled = ok,
						reason = if ok then nil else reason,
					})
				end
			end
		end
	end

	return {
		alive = p.alive,
		conscious = p.conscious,
		inArrest = p.arrest ~= nil,
		status = status,
		parts = parts,
		vitals = Snapshot.vitals(p, opts),
		airway = airway,
		meds = meds,
		triage = p.triage,
		bloodType = recentCheck(p, "bloodType") or (p.checks and p.checks.bloodType and p.checks.bloodType.value),
		log = log,
		actions = actions,
	}
end

-- Data driving the patient's own screen effects.
function Snapshot.selfEffects(p)
	return {
		alive = p.alive,
		conscious = p.conscious,
		pain = p.painPerceived,
		bloodLoss = math.clamp(
			(Config.DefaultBloodVolume - p.bloodVolume) / (Config.DefaultBloodVolume - Config.BloodClass3),
			0,
			1
		),
		hypoxia = math.clamp((95 - p.spo2) / 25, 0, 1),
		heartRate = p.heartRate,
		arrest = p.arrest ~= nil,
		causes = p.unconsciousCauses,
		respDepression = p.effects.respDepression,
		armInjury = Patient.armImpairment(p),
	}
end

return Snapshot
