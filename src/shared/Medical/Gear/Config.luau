--!strict
-- Gear (ArmA-style inventory) settings: item weights, containers, class kits and weight -> movement.
-- Weights are in kg. Ammo is stored as rounds; `roundsPer` is the size of one magazine / box.
local GearConfig = {}

GearConfig.Enabled = true
GearConfig.InventoryKey = "I" -- Enum.KeyCode name
GearConfig.SourceRange = 12 -- studs to an arsenal / dropped items to use them
GearConfig.PileLifetime = 300 -- seconds dropped items stay on the ground
GearConfig.ClassSetsMedicalLevel = true -- Medic class = medical level 1, everyone else 0
GearConfig.SpawnMedicalLoadoutLevel = 0 -- basic supplies fit the uniform; restock larger kits after equipping storage

-- Movement: no slowdown up to FreeMass, then walk speed falls linearly to MinSpeed at MaxMass.
GearConfig.FreeMass = 25
GearConfig.MaxMass = 60
GearConfig.MinSpeed = 0.7
GearConfig.NoSprintMass = 50 -- can't sprint above this
-- Sprint stamina: seconds of sprint when carrying nothing / FreeMass, and when at NoSprintMass.
GearConfig.SprintSecondsLight = 30
GearConfig.SprintSecondsHeavy = 8
GearConfig.StaminaRegenSeconds = 12 -- empty to full while not sprinting
GearConfig.StaminaResume = 0.25 -- after running out, sprint again at this much stamina

export type GearDef = {
	name: string,
	kind: string, -- "weapon" | "container" | "ammo" | "item" | "medical"
	mass: number,
	slot: string?, -- weapons: primary / handgun / launcher; containers: uniform / vest / backpack
	capacity: number?, -- containers: kg they hold
	weaponId: string?,
	roundsPer: number?,
	arsenal: boolean?, -- offered by the arsenal (medical items are always offered)
	equipable: boolean?,
}

GearConfig.Items = {
	-- Weapons (dedicated slots)
	M4A1 = { name = "M4A1", kind = "weapon", slot = "primary", weaponId = "M4A1", mass = 3.4, arsenal = true },
	M870 = { name = "M870", kind = "weapon", slot = "primary", weaponId = "M870", mass = 3.6, arsenal = true },
	G17 = { name = "G17", kind = "weapon", slot = "handgun", weaponId = "G17", mass = 0.9, arsenal = true },
	-- Ammo (mass per round)
	Ammo556 = { name = "5.56mm Magazine", kind = "ammo", mass = 0.016, roundsPer = 30, arsenal = true },
	Ammo9mm = { name = "9mm Magazine", kind = "ammo", mass = 0.018, roundsPer = 17, arsenal = true },
	Ammo12g = { name = "12g Shells", kind = "ammo", mass = 0.05, roundsPer = 6, arsenal = true },
	-- Containers (placeholder models)
	Uniform = { name = "Combat Uniform", kind = "container", slot = "uniform", capacity = 8, mass = 2, arsenal = true },
	PlateCarrier = {
		name = "Plate Carrier",
		kind = "container",
		slot = "vest",
		capacity = 14,
		mass = 9,
		arsenal = true,
	},
	ChestRig = { name = "Chest Rig", kind = "container", slot = "vest", capacity = 10, mass = 1.5, arsenal = true },
	AssaultPack = {
		name = "Assault Pack",
		kind = "container",
		slot = "backpack",
		capacity = 14,
		mass = 1.5,
		arsenal = true,
	},
	FieldPack = {
		name = "Field Pack",
		kind = "container",
		slot = "backpack",
		capacity = 24,
		mass = 2.5,
		arsenal = true,
	},
	Carryall = { name = "Carryall", kind = "container", slot = "backpack", capacity = 36, mass = 3.5, arsenal = true },
	-- Equipment
	Radio = { name = "Radio", kind = "item", mass = 0.8, arsenal = true, equipable = true },
	Hammer = { name = "Hammer", kind = "item", mass = 1, arsenal = true, equipable = true },
} :: { [string]: GearDef }

-- Ammo item used by each weapon.
GearConfig.Ammo = { M4A1 = "Ammo556", G17 = "Ammo9mm", M870 = "Ammo12g" } :: { [string]: string }

-- Medical item weights by Items category, plus per-item overrides. Fluids weigh their volume (500ml = 0.5kg).
GearConfig.MedicalMass = {
	Bandages = 0.05,
	Medication = 0.05,
	Pharmacy = 0.03,
	Airway = 0.1,
	Breathing = 0.2,
	Circulation = 0.2,
	Examine = 0.2,
	Surgery = 0.3,
} :: { [string]: number }
GearConfig.MedicalMassOverride = {
	Splint = 0.15,
	Tourniquet = 0.1,
	AED = 1,
	AEDX = 1.5,
	OxygenTank = 1,
	SuctionPump = 0.5,
	Ultrasound = 1,
	SurgicalKit = 0.8,
	BVM = 0.4,
} :: { [string]: number }

-- Class kits. `items` go into uniform -> vest -> backpack in that order; medical items come from the
-- medical loadout for the player's medical level (Medical Config.Loadouts) and are added last.
export type Kit = {
	primary: string?,
	handgun: string?,
	uniform: string?,
	vest: string?,
	backpack: string?,
	items: { { any } }, -- { itemId, count }
}

local common: { { any } } = { { "Radio", 1 }, { "Hammer", 1 }, { "Ammo9mm", 17 * 3 } }
local function with(extra: { { any } }): { { any } }
	local list = table.clone(common)
	for _, entry in extra do
		table.insert(list, entry)
	end
	return list
end

GearConfig.Kits = {
	Rifleman = {
		primary = "M4A1",
		handgun = "G17",
		uniform = "Uniform",
		items = with({ { "Ammo556", 30 * 7 } }),
	},
	["Squad Commander"] = {
		primary = "M4A1",
		handgun = "G17",
		uniform = "Uniform",
		items = with({ { "Ammo556", 30 * 6 } }),
	},
	Commander = {
		primary = "M4A1",
		handgun = "G17",
		uniform = "Uniform",
		items = with({ { "Ammo556", 30 * 5 } }),
	},
	Medic = {
		primary = "M4A1",
		handgun = "G17",
		uniform = "Uniform",
		items = with({ { "Ammo556", 30 * 5 } }),
	},
	Engineer = {
		primary = "M4A1",
		handgun = "G17",
		uniform = "Uniform",
		items = with({ { "Ammo556", 30 * 5 } }),
	},
	["Machine Gunner"] = {
		primary = "M4A1",
		handgun = "G17",
		uniform = "Uniform",
		items = with({ { "Ammo556", 30 * 8 } }),
	},
} :: { [string]: Kit }

return GearConfig
