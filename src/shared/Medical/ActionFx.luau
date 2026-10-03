--!strict
-- Which animation and sounds each treatment uses.
--   motion   = animation motion (see Animations.Motions)
--   start    = sound when the action starts
--   loop     = sound repeated every `interval` seconds while working
--   finish   = sound when the action completes
local ActionFx = {}

export type Fx = {
	motion: string,
	start: string?,
	loop: string?,
	interval: number?,
	finish: string?,
	base: string?, -- force a base pose (e.g. CPR always kneels)
}

local DEFAULT: Fx = { motion = "Work", start = "Rustle" }

ActionFx.ByCategory = {
	Examine = { motion = "Examine", start = "Rustle" },
	Bandage = { motion = "Wrap", start = "BandagePeel", loop = "Rustle", interval = 1.2, finish = "ClothRip" },
	Medication = { motion = "Inject", start = "SyringeCap", finish = "Injector" },
	Pharmacy = { motion = "Inject", start = "SyringeCap", finish = "Injector" },
	Fluids = { motion = "Fluids", start = "FluidBag", finish = "FluidBag" },
	Airway = { motion = "Airway", start = "Rustle" },
	Breathing = { motion = "Work", start = "Rustle" },
	Circulation = { motion = "Work", start = "Rustle" },
	Surgery = {
		motion = "Surgery",
		start = "SurgicalTools",
		loop = "Scissors",
		interval = 1.6,
		finish = "SurgicalTools",
	},
	Other = { motion = "Work", start = "Rustle" },
} :: { [string]: Fx }

ActionFx.ById = {
	ApplyTourniquet = { motion = "Tighten", start = "BandagePeel", loop = "Ratchet", interval = 0.8 },
	RemoveTourniquet = { motion = "Tighten", start = "Ratchet" },
	ApplySplint = { motion = "Work", start = "Velcro", loop = "Rustle", interval = 1.2, finish = "Velcro" },
	RemoveSplint = { motion = "Work", start = "Velcro" },
	Painkillers = { motion = "Mouth", start = "Pills" },
	CWMP = { motion = "Mouth", start = "Pills" },
	Penthrox = { motion = "Mouth", start = "Rustle" },
	Naloxone = { motion = "Mouth", start = "SyringeCap", finish = "Injector" },
	CheckPulse = { motion = "Examine" },
	AttachPulseOx = { motion = "Work", start = "Rustle", finish = "AedBeep" },
	CPR = { motion = "Cpr", loop = "Compression", interval = 0.55, base = "Kneel" },
	UseAED = { motion = "Work", start = "AedBeep", loop = "AedBeep", interval = 1.5 },
	AttachAEDX = { motion = "Work", start = "Rustle", finish = "AedBeep" },
	AEDXShock = { motion = "Work", start = "AedCharge" },
	UseBVM = { motion = "Squeeze", loop = "BvmSqueeze", interval = 1.5 },
	Suction = { motion = "Airway", start = "Suction", loop = "Suction", interval = 1.4 },
	ManualSweep = { motion = "Airway", start = "Rustle" },
	ChestSeal = { motion = "Work", start = "BandagePeel", finish = "ClothRip" },
	NeedleDecompression = { motion = "Inject", start = "SyringeCap", finish = "Injector" },
	IV16 = { motion = "Inject", start = "SyringeCap", finish = "BandagePeel" },
	FASTIO = { motion = "Inject", start = "SyringeCap", finish = "Injector" },
	DrawBlood = { motion = "Inject", start = "SyringeCap", finish = "FluidBag" },
	StitchWounds = { motion = "Surgery", start = "SurgicalTools", loop = "Scissors", interval = 1.2 },
	NPWT = { motion = "Surgery", start = "BandagePeel", loop = "Suction", interval = 2 },
	RecoveryPosition = { motion = "Lift", start = "Rustle", finish = "BodyFall" },
	Carry = { motion = "Lift", start = "Rustle" },
	Drag = { motion = "Lift", start = "Rustle" },
} :: { [string]: Fx }

function ActionFx.get(def: { id: string, category: string? }): Fx
	return ActionFx.ById[def.id] or (def.category and ActionFx.ByCategory[def.category]) or DEFAULT
end

-- True when the action result means a defibrillator shock was delivered.
function ActionFx.isShock(actionId: string, result: string?): boolean
	if (actionId ~= "UseAED" and actionId ~= "AEDXShock") or not result then
		return false
	end
	local lower = string.lower(result :: string)
	return string.find(lower, "shock", 1, true) ~= nil and string.find(lower, "no shock", 1, true) == nil
end

-- Picks the body base pose for the medic: self-treatment, standing patient or kneeling over a downed one.
function ActionFx.base(fx: Fx, isSelf: boolean, patientDown: boolean): string
	if fx.base then
		return fx.base
	end
	if isSelf then
		return "Self"
	end
	return if patientDown then "Kneel" else "Stand"
end

return ActionFx
