--!strict
-- Wound catalogue (ACE/KAT style). Bleeding is litres per second for one wound at full cardiac output.

export type WoundDef = {
	name: string,
	bleeding: { number }, -- small, medium, large
	pain: { number },
	causesFracture: boolean,
}

local Wounds = {}

Wounds.Sizes = { "Minor", "Medium", "Large" }

Wounds.Types = {
	Abrasion = {
		name = "Abrasion",
		bleeding = { 0.0002, 0.0005, 0.001 },
		pain = { 0.05, 0.1, 0.15 },
		causesFracture = false,
	},
	Avulsion = {
		name = "Avulsion",
		bleeding = { 0.004, 0.009, 0.016 },
		pain = { 0.3, 0.45, 0.6 },
		causesFracture = true,
	},
	Contusion = { name = "Contusion", bleeding = { 0, 0, 0 }, pain = { 0.05, 0.1, 0.2 }, causesFracture = true },
	Crush = {
		name = "Crushed tissue",
		bleeding = { 0.0005, 0.0015, 0.003 },
		pain = { 0.15, 0.3, 0.45 },
		causesFracture = true,
	},
	Cut = { name = "Cut", bleeding = { 0.001, 0.003, 0.006 }, pain = { 0.1, 0.2, 0.3 }, causesFracture = false },
	Laceration = {
		name = "Laceration",
		bleeding = { 0.0015, 0.004, 0.008 },
		pain = { 0.15, 0.25, 0.35 },
		causesFracture = false,
	},
	Velocity = {
		name = "Velocity wound",
		bleeding = { 0.003, 0.007, 0.013 },
		pain = { 0.25, 0.4, 0.55 },
		causesFracture = true,
	},
	Puncture = {
		name = "Puncture wound",
		bleeding = { 0.002, 0.005, 0.009 },
		pain = { 0.15, 0.3, 0.4 },
		causesFracture = false,
	},
} :: { [string]: WoundDef }

-- Damage type -> weighted wound types
Wounds.DamageTypes = {
	Bullet = { Velocity = 80, Avulsion = 8, Laceration = 7, Contusion = 5 },
	Explosive = { Avulsion = 30, Laceration = 25, Crush = 20, Abrasion = 15, Velocity = 10 },
	Blunt = { Contusion = 50, Crush = 25, Abrasion = 25 },
	Fall = { Contusion = 45, Crush = 25, Abrasion = 30 },
	Melee = { Cut = 45, Laceration = 30, Contusion = 25 },
	Stab = { Puncture = 70, Cut = 30 },
	Generic = { Laceration = 40, Abrasion = 30, Contusion = 30 },
} :: { [string]: { [string]: number } }

export type BandageDef = {
	effectiveness: { [string]: number }, -- how many wounds of a type one bandage covers
	reopenChance: { [string]: number }, -- percent
	reopenDelay: { number }, -- min, max seconds
}

-- Bandage behaviour mirrors ACE: packing is strong but reopens, elastic is weak but holds,
-- HemostaticGauze is good everywhere and almost never reopens.
Wounds.Bandages = {
	FieldDressing = {
		effectiveness = {
			Abrasion = 1,
			Avulsion = 0.5,
			Contusion = 1,
			Crush = 0.6,
			Cut = 1,
			Laceration = 0.8,
			Velocity = 0.6,
			Puncture = 0.7,
		},
		reopenChance = {
			Abrasion = 10,
			Avulsion = 40,
			Contusion = 0,
			Crush = 30,
			Cut = 15,
			Laceration = 20,
			Velocity = 35,
			Puncture = 25,
		},
		reopenDelay = { 300, 600 },
	},
	PackingBandage = {
		effectiveness = {
			Abrasion = 1,
			Avulsion = 1.5,
			Contusion = 1,
			Crush = 1,
			Cut = 1,
			Laceration = 1,
			Velocity = 1.5,
			Puncture = 1.5,
		},
		reopenChance = {
			Abrasion = 30,
			Avulsion = 60,
			Contusion = 0,
			Crush = 50,
			Cut = 40,
			Laceration = 45,
			Velocity = 60,
			Puncture = 50,
		},
		reopenDelay = { 120, 400 },
	},
	ElasticBandage = {
		effectiveness = {
			Abrasion = 1.5,
			Avulsion = 0.4,
			Contusion = 1.5,
			Crush = 0.8,
			Cut = 1.5,
			Laceration = 1.2,
			Velocity = 0.4,
			Puncture = 0.5,
		},
		reopenChance = {
			Abrasion = 0,
			Avulsion = 10,
			Contusion = 0,
			Crush = 5,
			Cut = 0,
			Laceration = 5,
			Velocity = 10,
			Puncture = 5,
		},
		reopenDelay = { 600, 1200 },
	},
	HemostaticGauze = {
		effectiveness = {
			Abrasion = 1,
			Avulsion = 1.2,
			Contusion = 1,
			Crush = 1,
			Cut = 1,
			Laceration = 1.2,
			Velocity = 1.2,
			Puncture = 1.2,
		},
		reopenChance = {
			Abrasion = 5,
			Avulsion = 10,
			Contusion = 0,
			Crush = 10,
			Cut = 5,
			Laceration = 5,
			Velocity = 10,
			Puncture = 10,
		},
		reopenDelay = { 600, 1200 },
	},
} :: { [string]: BandageDef }

Wounds.BandageNames = {
	FieldDressing = "Basic Bandage",
	PackingBandage = "Packing Bandage",
	ElasticBandage = "Elastic Bandage",
	HemostaticGauze = "Hemostatic gauze",
} :: { [string]: string }

Wounds.Fractures = {
	[1] = "Simple fracture",
	[2] = "Compound fracture",
	[3] = "Comminuted fracture",
} :: { [number]: string }

function Wounds.describe(woundType: string, size: number): string
	local def = Wounds.Types[woundType]
	return string.format("%s %s", Wounds.Sizes[size] or "?", if def then def.name:lower() else woundType)
end

return Wounds
