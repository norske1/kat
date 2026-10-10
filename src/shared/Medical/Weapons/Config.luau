--!strict
-- Weapon definitions and settings. Guns deal damage through the medical system, so hits create wounds
-- (bleeding, fractures, pneumothorax...) on the exact body part that was hit.
local WeaponConfig = {}

WeaponConfig.GiveOnSpawn = false -- true: give WeaponConfig.Loadout to every player when they spawn
WeaponConfig.Loadout = { "M4A1", "G17" }
WeaponConfig.AutoSpawnLocker = true -- build a weapon locker next to the spawn if no part is tagged "WeaponLocker"
WeaponConfig.LockerReach = 10 -- studs: how close you must be to click a locker item
WeaponConfig.LockerItems = { "M4A1", "M870", "G17", "Ammo" } -- top shelf to bottom; "Ammo" is a resupply box
WeaponConfig.FriendlyFire = true -- false: players on the same (non-neutral) team can't hurt each other
WeaponConfig.DamageNonMedical = true -- also damage humanoids not managed by the medical system
WeaponConfig.MaxOriginDistance = 8 -- anti-cheat: shot origin must be this close to the shooter's head
WeaponConfig.RateTolerance = 0.8 -- anti-cheat: accept shots at 80% of the fire interval (network jitter)

WeaponConfig.ReloadKey = Enum.KeyCode.R
WeaponConfig.FireModeKey = Enum.KeyCode.V
WeaponConfig.FreeMouseKey = Enum.KeyCode.LeftAlt -- hold to unlock the mouse while a gun is out
WeaponConfig.SprintKey = Enum.KeyCode.LeftShift -- hold
WeaponConfig.CrouchKey = Enum.KeyCode.C -- toggle
WeaponConfig.LeanLeftKey = Enum.KeyCode.Q -- toggle
WeaponConfig.LeanRightKey = Enum.KeyCode.E -- toggle

-- First person (ACS style): the camera locks to first person while a gun is out and you see arms holding
-- the gun. Shots leave the barrel, so aim with the sights (right mouse). false = over-the-shoulder camera.
WeaponConfig.FirstPerson = true
WeaponConfig.ShowHipCrosshair = false -- first person only; the third-person camera always has one
WeaponConfig.AimSensitivity = 0.55 -- mouse sensitivity while aiming down sights
WeaponConfig.SleeveColor = Color3.fromRGB(78, 84, 62)
WeaponConfig.GloveColor = Color3.fromRGB(34, 34, 36)
-- Per hold type: where the grip sits at the hip (camera space), how far in front of the eye the sights sit
-- when aiming, the aim field of view, and where the support hand goes to change magazines (gun space).
WeaponConfig.Viewmodel = {
	Rifle = { hip = Vector3.new(0.5, -0.7, -0.9), aimDistance = 0.6, fov = 50, magWell = Vector3.new(0, -0.1, -0.55) },
	Pistol = { hip = Vector3.new(0.4, -0.62, -1.4), aimDistance = 1.3, fov = 58, magWell = Vector3.new(0, -0.42, 0.04) },
}

-- Movement (works with or without a gun): speed multipliers and lean / crouch sizes.
WeaponConfig.SprintSpeed = 1.45
WeaponConfig.CrouchSpeed = 0.55
WeaponConfig.AimSpeed = 0.75
WeaponConfig.CrouchDrop = 1 -- studs the character (and its hitbox) is lowered when crouched
WeaponConfig.LeanOffset = 1.1 -- studs the camera moves sideways when leaning
WeaponConfig.LeanAngle = 14 -- degrees of camera roll when leaning

-- Over-the-shoulder camera (FirstPerson = false)
WeaponConfig.CameraOffset = Vector3.new(1.8, 0.5, 0)
WeaponConfig.AimCameraOffset = Vector3.new(1.4, 0.6, 0)
WeaponConfig.AimFov = 45

-- Ballistics: bullets fly at the weapon's `velocity` and drop under gravity. 1 stud = 0.28 m.
WeaponConfig.BulletGravity = 35 -- studs/s² (9.81 m/s²)
WeaponConfig.DefaultVelocity = 2500 -- studs/s when a weapon has no `velocity`
WeaponConfig.SpeedOfSound = 1225 -- studs/s: far-away gunshots are heard late
WeaponConfig.CrackDistance = 8 -- studs: bullets passing closer than this crack past you
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
	velocity: number?, -- muzzle velocity in studs/s
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
			aim = Vector3.new(0.0816, 0.9607, 0.3388), -- rear sight aperture
			support = Vector3.new(0.0816, 0.216, -0.317), -- under the handguard
		},
		damage = 32,
		velocity = 3000,
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
	G17 = {
		id = "G17",
		name = "G17",
		hold = "Pistol",
		model = "Pistol",
		-- assets/weapons/roblox/G17.obj (or the original Blender export) imported as WeaponModels.G17
		mesh = {
			name = "G17",
			aliases = { "M17" }, -- older name of the imported model
			length = 0.93,
			grip = Vector3.new(0, -0.2421, 0.6115),
			muzzle = Vector3.new(0, 0.6685, -0.9991),
			aim = Vector3.new(0, 0.9388, 0.7403), -- rear sight dots
			support = Vector3.new(-1.12, -0.534, 0.74), -- left hand wrapped around the right
		},
		damage = 22,
		velocity = 1300,
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
		velocity = 1400,
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
