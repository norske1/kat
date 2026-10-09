--!strict
-- Logistics and base building. Trucks load supplies at main and unload them at a FOB; Squad Commanders and the
-- Commander place structures inside a FOB's radius (paid from its supplies); anyone with a Hammer builds them up.
local LogisticsConfig = {}

LogisticsConfig.Enabled = true
LogisticsConfig.BuildKey = Enum.KeyCode.B
LogisticsConfig.FobRadius = 150 -- studs; structures must be placed inside it
LogisticsConfig.FobMinFromMain = 300 -- FOBs can't be placed this close to a main base
LogisticsConfig.FobSpacing = 250 -- or this close to another FOB
LogisticsConfig.FobMaxStock = 3000
LogisticsConfig.MainRadius = 90 -- trucks load supplies within this range of their main's vehicle pad / spawn
LogisticsConfig.PlaceRange = 40 -- how far from yourself you can place
LogisticsConfig.HabBlockRadius = 40 -- can't spawn at a HAB with a conscious enemy this close
LogisticsConfig.DismantleSeconds = 6 -- enemies dismantling a FOB radio
LogisticsConfig.BuildHold = 1 -- seconds per hammer hit (one build point)

export type StructureDef = { name: string, cost: number, build: number, size: Vector3, color: Color3, order: number }

LogisticsConfig.Structures = {
	FOB = {
		name = "FOB Radio",
		cost = 0,
		build = 10,
		size = Vector3.new(3, 4, 3),
		color = Color3.fromRGB(70, 90, 60),
		order = 1,
	},
	HAB = {
		name = "HAB",
		cost = 300,
		build = 40,
		size = Vector3.new(16, 8, 12),
		color = Color3.fromRGB(110, 105, 85),
		order = 2,
	},
	AmmoCrate = {
		name = "Ammo Crate",
		cost = 150,
		build = 10,
		size = Vector3.new(4, 3, 3),
		color = Color3.fromRGB(85, 95, 60),
		order = 3,
	},
	Sandbags = {
		name = "Sandbags",
		cost = 20,
		build = 4,
		size = Vector3.new(8, 3, 2),
		color = Color3.fromRGB(165, 145, 105),
		order = 4,
	},
	HESCO = {
		name = "HESCO",
		cost = 60,
		build = 8,
		size = Vector3.new(10, 6, 3),
		color = Color3.fromRGB(150, 135, 100),
		order = 5,
	},
	RazorWire = {
		name = "Razor Wire",
		cost = 15,
		build = 3,
		size = Vector3.new(10, 2, 2),
		color = Color3.fromRGB(120, 120, 125),
		order = 6,
	},
	Bunker = {
		name = "Bunker",
		cost = 250,
		build = 30,
		size = Vector3.new(12, 6, 12),
		color = Color3.fromRGB(125, 120, 110),
		order = 7,
	},
} :: { [string]: StructureDef }

return LogisticsConfig
