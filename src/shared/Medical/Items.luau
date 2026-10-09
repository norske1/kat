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
	HemostaticGauze = { name = "Hemostatic Gauze", category = "Bandages" },
	Tourniquet = { name = "Tourniquet", category = "Bandages" },
	Splint = { name = "Splint", category = "Bandages" },
	PainRelief = { name = "Pain Relief Tablets", category = "Medication" },
	CWMP = { name = "Combat Med Pack", category = "Medication" },
	PainInhaler = { name = "Pain Relief Inhaler", category = "Medication" },
	AdrenalineAuto = { name = "Adrenaline Autoinjector", category = "Medication" },
	AnalgesicAuto = { name = "Analgesic Autoinjector", category = "Medication" },
	ReversalSpray = { name = "Reversal Spray", category = "Medication" },
	SmellingSalts = { name = "Smelling Salts", category = "Medication" },
	Adrenaline = { name = "Adrenaline Vial", category = "Pharmacy" },
	RhythmStabiliser = { name = "Rhythm Stabiliser Vial", category = "Pharmacy" },
	MildRhythmStabiliser = { name = "Mild Rhythm Stabiliser Vial", category = "Pharmacy" },
	HeartRateBooster = { name = "Heart Rate Booster Vial", category = "Pharmacy" },
	ClottingAgent = { name = "Clotting Agent Vial", category = "Pharmacy" },
	StrongClottingAgent = { name = "Strong Clotting Agent Vial", category = "Pharmacy" },
	FieldAnesthetic = { name = "Field Anesthetic Vial", category = "Pharmacy" },
	StrongAnalgesic = { name = "Strong Analgesic Vial", category = "Pharmacy" },
	MildAnalgesic = { name = "Mild Analgesic Vial", category = "Pharmacy" },
	PressureBooster = { name = "Pressure Booster Vial", category = "Pharmacy" },
	PressureSupport = { name = "Pressure Support Vial", category = "Pharmacy" },
	PressureReducer = { name = "Pressure Reducer Vial", category = "Pharmacy" },
	SurgicalSedative = { name = "Surgical Sedative Vial", category = "Pharmacy" },
	Sedative = { name = "Sedative Vial", category = "Pharmacy" },
	SedativeReversal = { name = "Sedative Reversal Vial", category = "Pharmacy" },
	IV16 = { name = "16g IV", category = "Pharmacy" },
	FASTIO = { name = "FAST IO", category = "Pharmacy" },
	ChestSeal = { name = "Chest Seal", category = "Breathing" },
	AATKit = { name = "AAT Kit (needle/chest tube)", category = "Breathing" },
	Guedel = { name = "Guedel Tube", category = "Airway" },
	AirwayTube = { name = "Airway Tube", category = "Airway" },
	SuctionPump = { name = "Suction Pump", category = "Airway", reusable = true },
	Stethoscope = { name = "Stethoscope", category = "Examine", reusable = true },
	PulseOximeter = { name = "Pulse Oximeter", category = "Examine" },
	BVM = { name = "Bag Valve Mask", category = "Breathing", reusable = true },
	OxygenTank = { name = "Oxygen Tank (portable)", category = "Breathing", reusable = true },
	NasalCannula = { name = "Nasal Cannula", category = "Breathing" },
	AED = { name = "AED", category = "Circulation", reusable = true },
	AEDX = { name = "AED-X Monitor", category = "Circulation", reusable = true },
	ClotTester = { name = "Clot Tester", category = "Examine", reusable = true },
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
