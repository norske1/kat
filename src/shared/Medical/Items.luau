--!strict
-- Item catalogue. Inventories store item ids -> counts.
local Config = require(script.Parent.Config)
local BloodTypes = require(script.Parent.BloodTypes)

export type ItemDef = {
	name: string,
	category: string,
	reusable: boolean?,
}

local Items: { [string]: ItemDef } = {
	FieldDressing = { name = "Basic Bandage", category = "Bandages" },
	PackingBandage = { name = "Packing Bandage", category = "Bandages" },
	ElasticBandage = { name = "Elastic Bandage", category = "Bandages" },
	QuikClot = { name = "QuikClot", category = "Bandages" },
	Tourniquet = { name = "Tourniquet (CAT)", category = "Bandages" },
	Splint = { name = "Splint", category = "Bandages" },
	Painkillers = { name = "Painkillers", category = "Medication" },
	CWMP = { name = "Combat Wound Med Pack", category = "Medication" },
	Penthrox = { name = "Penthrox", category = "Medication" },
	EpinephrineAuto = { name = "Epinephrine autoinjector", category = "Medication" },
	MorphineAuto = { name = "Morphine autoinjector", category = "Medication" },
	Naloxone = { name = "Naloxone", category = "Medication" },
	Carbonate = { name = "Ammonium carbonate", category = "Medication" },
	Epinephrine = { name = "Epinephrine 1mg", category = "Pharmacy" },
	Amiodarone = { name = "Amiodarone 300mg", category = "Pharmacy" },
	Lidocaine = { name = "Lidocaine 100mg", category = "Pharmacy" },
	Atropine = { name = "Atropine 1mg", category = "Pharmacy" },
	TXA = { name = "TXA 1g", category = "Pharmacy" },
	EACA = { name = "EACA 5g", category = "Pharmacy" },
	Ketamine = { name = "Ketamine 50mg", category = "Pharmacy" },
	Fentanyl = { name = "Fentanyl 100mcg", category = "Pharmacy" },
	Nalbuphine = { name = "Nalbuphine 10mg", category = "Pharmacy" },
	Norepinephrine = { name = "Norepinephrine", category = "Pharmacy" },
	Phenylephrine = { name = "Phenylephrine", category = "Pharmacy" },
	Nitroglycerin = { name = "Nitroglycerin", category = "Pharmacy" },
	Etomidate = { name = "Etomidate 20mg", category = "Pharmacy" },
	Lorazepam = { name = "Lorazepam 4mg", category = "Pharmacy" },
	Flumazenil = { name = "Flumazenil 0.5mg", category = "Pharmacy" },
	IV16 = { name = "16g IV", category = "Pharmacy" },
	FASTIO = { name = "FAST IO", category = "Pharmacy" },
	ChestSeal = { name = "Chest Seal", category = "Breathing" },
	AATKit = { name = "AAT Kit (needle/chest tube)", category = "Breathing" },
	Guedel = { name = "Guedel Tube", category = "Airway" },
	KingLT = { name = "KingLT", category = "Airway" },
	Accuvac = { name = "Accuvac", category = "Airway", reusable = true },
	Stethoscope = { name = "Stethoscope", category = "Examine", reusable = true },
	PulseOximeter = { name = "Pulse Oximeter", category = "Examine" },
	BVM = { name = "Bag Valve Mask", category = "Breathing", reusable = true },
	OxygenTank = { name = "Oxygen Tank (portable)", category = "Breathing", reusable = true },
	NasalCannula = { name = "Nasal Cannula", category = "Breathing" },
	AED = { name = "AED", category = "Circulation", reusable = true },
	AEDX = { name = "AED-X Monitor", category = "Circulation", reusable = true },
	CoagSense = { name = "CoagSense", category = "Examine", reusable = true },
	Ultrasound = { name = "Ultrasound", category = "Examine", reusable = true },
	REBOA = { name = "REBOA kit", category = "Surgery" },
	SurgicalKit = { name = "Surgical Kit", category = "Surgery", reusable = true },
	Scalpel = { name = "Scalpel", category = "Surgery", reusable = true },
	Retractor = { name = "Retractor", category = "Surgery", reusable = true },
	Clamp = { name = "Clamp", category = "Surgery", reusable = true },
	BonePlate = { name = "Bone Plate", category = "Surgery" },
	NPWT = { name = "NPWT dressing vacuum", category = "Surgery" },
	BloodDrawKit = { name = "Blood draw kit", category = "Circulation" },
	SyringeNeedle = { name = "Pericardiocentesis needle", category = "Surgery" },
}

for _, volume in Config.FluidVolumes do
	Items["Saline" .. volume] = { name = string.format("Saline %dml", volume), category = "Fluids" }
	Items["Plasma" .. volume] = { name = string.format("Plasma %dml", volume), category = "Fluids" }
	for _, bloodType in Config.BloodTypes do
		local key = BloodTypes.toKey(bloodType)
		Items["Blood" .. key .. volume] =
			{ name = string.format("Blood %s %dml", bloodType, volume), category = "Fluids" }
	end
end

return Items
