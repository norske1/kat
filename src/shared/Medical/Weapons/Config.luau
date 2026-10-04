--!strict
-- Weapon definitions and settings. Guns deal damage through the medical system, so hits create wounds
-- (bleeding, fractures, pneumothorax...) on the exact body part that was hit.
local WeaponConfig = {}

WeaponConfig.GiveOnSpawn = false -- true: give WeaponConfig.Loadout to every player when they spawn
WeaponConfig.Loadout = { "M4A1", "M17" }
WeaponConfig.AutoSpawnLocker = true -- build a weapon locker next to the spawn if no part is tagged "WeaponLocker"
WeaponConfig.LockerReach = 10 -- studs: how close you must be to click a locker item
WeaponConfig.LockerItems = { "M4A1", "M870", "M17", "Ammo" } -- top shelf to bottom; "Ammo" is a resupply box
WeaponConfig.FriendlyFire = true -- false: players on the same (non-neutral) team can't hurt each other
WeaponConfig.DamageNonMedical = true -- also damage humanoids not managed by the medical system
WeaponConfig.MaxOriginDistance = 8 -- anti-cheat: shot origin must be this close to the shooter's head
WeaponConfig.RateTolerance = 0.8 -- anti-cheat: accept shots at 80% of the fire interval (network jitter)

WeaponConfig.ReloadKey = Enum.KeyCode.R
WeaponConfig.FireModeKey = Enum.KeyCode.V
WeaponConfig.FreeMouseKey = Enum.KeyCode.LeftAlt -- hold to unlock the mouse while a gun is out
WeaponConfig.CameraOffset = Vector3.new(1.8, 0.5, 0) -- over-the-shoulder camera while a gun is equipped
WeaponConfig.AimCameraOffset = Vector3.new(1.4, 0.6, 0)
WeaponConfig.AimFov = 45
WeaponConfig.TracerSpeed = 1400 -- studs per second (visual only)
WeaponConfig.MaxBulletHoles = 80

export type Recoil = { vertical: number, horizontal: number, kick: number }
export type Weapon = {
	id: string,
	name: string,
	hold: string, -- animation set: "Rifle" or "Pistol"
	model: string, -- Models builder: "Rifle", "Pistol", "Shotgun"
	mesh: any?, -- Models.MeshSpec: imported mesh in a WeaponModels folder (falls back to `model`)
	damage: number, -- per projectile, before range falloff
	damageType: string, -- medical damage type
	pellets: number,
	rpm: number,
	modes: { string }, -- "Auto", "Semi"
	magazine: number,
	reserve: number, -- spare rounds
	reloadTime: number, -- full magazine reload, or per shell if reloadPerShell
	reloadPerShell: boolean?,
	pumpTime: number?, -- pump-action cycle after each shot
	equipTime: number,
	range: number,
	falloffStart: number,
	falloffEnd: number,
	minDamageScale: number,
	spreadHip: number, -- degrees
	spreadAim: number,
	spreadMove: number, -- multiplier added while moving
	pelletSpread: number?, -- extra cone for shotgun pellets
	recoil: Recoil,
	fireSound: string,
}

WeaponConfig.Weapons = {
	M4A1 = {
		id = "M4A1",
		name = "M4A1",
		hold = "Rifle",
		model = "Rifle",
		-- assets/weapons/roblox/M4A1.obj (or the original Blender export) imported as WeaponModels.M4A1
		mesh = {
			name = "M4A1",
			length = 3.66,
			grip = Vector3.new(0.0805, -0.1772, 0.3387),
			muzzle = Vector3.new(0.0805, 0.4559, -1),
		},
		damage = 32,
		damageType = "Bullet",
		pellets = 1,
		rpm = 750,
		modes = { "Auto", "Semi" },
		magazine = 30,
		reserve = 150,
		reloadTime = 2.4,
		equipTime = 0.6,
		range = 1000,
		falloffStart = 200,
		falloffEnd = 700,
		minDamageScale = 0.65,
		spreadHip = 2.2,
		spreadAim = 0.3,
		spreadMove = 1.2,
		recoil = { vertical = 0.9, horizontal = 0.35, kick = 0.6 },
		fireSound = "RifleShot",
	},
	M17 = {
		id = "M17",
		name = "M17",
		hold = "Pistol",
		model = "Pistol",
		-- assets/weapons/roblox/M17.obj (or the original Blender export) imported as WeaponModels.M17
		mesh = {
			name = "M17",
			length = 0.93,
			grip = Vector3.new(0, -0.2421, 0.6115),
			muzzle = Vector3.new(0, 0.6685, -0.9991),
		},
		damage = 22,
		damageType = "Bullet",
		pellets = 1,
		rpm = 420,
		modes = { "Semi" },
		magazine = 17,
		reserve = 68,
		reloadTime = 1.7,
		equipTime = 0.4,
		range = 400,
		falloffStart = 50,
		falloffEnd = 200,
		minDamageScale = 0.55,
		spreadHip = 2.6,
		spreadAim = 0.7,
		spreadMove = 0.8,
		recoil = { vertical = 1.6, horizontal = 0.5, kick = 1 },
		fireSound = "PistolShot",
	},
	M870 = {
		id = "M870",
		name = "M870",
		hold = "Rifle",
		model = "Shotgun",
		damage = 10,
		damageType = "Bullet",
		pellets = 8,
		rpm = 70,
		modes = { "Semi" },
		magazine = 6,
		reserve = 30,
		reloadTime = 0.5,
		reloadPerShell = true,
		pumpTime = 0.6,
		equipTime = 0.6,
		range = 250,
		falloffStart = 15,
		falloffEnd = 70,
		minDamageScale = 0.25,
		spreadHip = 2.5,
		spreadAim = 1.2,
		spreadMove = 0.6,
		pelletSpread = 3.5,
		recoil = { vertical = 4, horizontal = 1, kick = 2 },
		fireSound = "ShotgunShot",
	},
} :: { [string]: Weapon }

function WeaponConfig.get(id: any): Weapon?
	if typeof(id) ~= "string" then
		return nil
	end
	return WeaponConfig.Weapons[id]
end

-- Damage after range falloff.
function WeaponConfig.damageAt(weapon: Weapon, distance: number): number
	if distance <= weapon.falloffStart then
		return weapon.damage
	end
	local f = math.clamp((distance - weapon.falloffStart) / math.max(weapon.falloffEnd - weapon.falloffStart, 1), 0, 1)
	return weapon.damage * (1 - f * (1 - weapon.minDamageScale))
end

-- Reload duration. Arm injuries (0..1 from the medical system) and pain slow reloading down.
function WeaponConfig.reloadDuration(
	weapon: Weapon,
	ammo: number,
	reserve: number,
	armInjury: number,
	pain: number
): number
	local base = weapon.reloadTime
	if weapon.reloadPerShell then
		local shells = math.min(weapon.magazine - ammo, reserve)
		base = weapon.reloadTime * math.max(shells, 1) + 0.3
	end
	return base * (1 + armInjury * 0.8 + pain * 0.3)
end

-- Spread multiplier from the shooter's medical state.
function WeaponConfig.medicalSpread(armInjury: number, pain: number): number
	return 1 + armInjury * 1.5 + pain * 0.8
end

return WeaponConfig
