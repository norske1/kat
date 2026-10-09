--!strict
-- Vehicles: per-side caps and cooldowns, handling and armour. Models are placeholder parts built in code.
-- Cooldown: every deployed vehicle starts its slot's timer when it spawns. A new one can only spawn while fewer
-- than `cap` are alive and a free slot's timer has run out.
local VehicleConfig = {}

VehicleConfig.Enabled = true
VehicleConfig.IdleDespawn = 120 -- seconds a vehicle can sit empty before it despawns
VehicleConfig.WreckSeconds = 30 -- how long a destroyed wreck stays
VehicleConfig.OccupantBlastDamage = 60 -- medical damage to everyone inside when a vehicle is destroyed
VehicleConfig.ClimbUp = Enum.KeyCode.E -- helicopter climb / descend
VehicleConfig.ClimbDown = Enum.KeyCode.Q

export type Turret = { damage: number, rpm: number, range: number, antiArmor: number, spread: number }
export type VehicleDef = {
	name: string,
	cap: number,
	cooldown: number,
	kind: string, -- "car" | "heli"
	health: number,
	armor: number, -- share of small-arms damage that gets through
	speed: number, -- studs/s
	reverse: number,
	accel: number,
	turn: number, -- rad/s
	climb: number?,
	size: Vector3,
	color: Color3,
	passengers: number,
	turret: Turret?,
	supplies: number, -- logistics capacity (0 = can't carry supplies)
	order: number,
}

VehicleConfig.Types = {
	MRAP = {
		name = "MRAP",
		cap = 5,
		cooldown = 180,
		kind = "car",
		health = 900,
		armor = 0.2,
		speed = 75,
		reverse = 25,
		accel = 30,
		turn = 1.6,
		size = Vector3.new(8, 5, 16),
		color = Color3.fromRGB(110, 115, 85),
		passengers = 4,
		turret = { damage = 30, rpm = 500, range = 900, antiArmor = 1, spread = 0.6 },
		supplies = 0,
		order = 1,
	},
	Truck = {
		name = "Logistics Truck",
		cap = 4, -- not specified yet
		cooldown = 120, -- not specified yet
		kind = "car",
		health = 600,
		armor = 0.5,
		speed = 65,
		reverse = 20,
		accel = 22,
		turn = 1.2,
		size = Vector3.new(8, 6, 22),
		color = Color3.fromRGB(95, 105, 75),
		passengers = 1,
		supplies = 1000,
		order = 2,
	},
	APC = {
		name = "APC",
		cap = 3,
		cooldown = 300,
		kind = "car",
		health = 1800,
		armor = 0.04,
		speed = 55,
		reverse = 20,
		accel = 20,
		turn = 1.1,
		size = Vector3.new(10, 6, 20),
		color = Color3.fromRGB(90, 100, 80),
		passengers = 8,
		turret = { damage = 40, rpm = 450, range = 1000, antiArmor = 1.5, spread = 0.5 },
		supplies = 0,
		order = 3,
	},
	IFV = {
		name = "IFV",
		cap = 2,
		cooldown = 360,
		kind = "car",
		health = 2400,
		armor = 0.03,
		speed = 50,
		reverse = 18,
		accel = 18,
		turn = 1,
		size = Vector3.new(10, 6, 20),
		color = Color3.fromRGB(80, 92, 70),
		passengers = 6,
		turret = { damage = 150, rpm = 150, range = 1200, antiArmor = 2, spread = 0.3 },
		supplies = 0,
		order = 4,
	},
	Helicopter = {
		name = "Helicopter",
		cap = 2,
		cooldown = 480,
		kind = "heli",
		health = 800,
		armor = 0.3,
		speed = 110,
		reverse = 30,
		accel = 25,
		turn = 1.4,
		climb = 35,
		size = Vector3.new(7, 6, 18),
		color = Color3.fromRGB(70, 80, 65),
		passengers = 6,
		supplies = 0,
		order = 5,
	},
} :: { [string]: VehicleDef }

return VehicleConfig
