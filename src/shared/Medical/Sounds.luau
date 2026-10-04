--!strict
-- Sound library for treatments and weapons.
-- Defaults are free Creator Store sound effects (mostly the ProSoundEffects library) and
-- built-in rbxasset sounds. Swap any id for your own: "rbxassetid://<id>".
export type SoundDef = {
	ids: { string },
	volume: number?,
	pitch: number?,
	variance: number?, -- random +/- playback speed
	range: number?, -- RollOffMaxDistance
}

local Sounds = {}

Sounds.MasterVolume = 1

local function id(n: number): string
	return "rbxassetid://" .. tostring(n)
end

Sounds.Library = {
	-- Medical --------------------------------------------------------------
	Rustle = { ids = { id(9113837941), id(9113837381) }, volume = 0.5 },
	ClothRip = { ids = { id(9113836270), id(9113836714) }, volume = 0.6 },
	BandagePeel = { ids = { id(9113266339) }, volume = 0.6 },
	Velcro = { ids = { id(130090184642358) }, volume = 0.6 },
	Zipper = { ids = { id(9113260699) }, volume = 0.5 },
	Ratchet = { ids = { id(9118046636) }, volume = 0.6, pitch = 1.3 },
	SyringeCap = { ids = { id(9119521227) }, volume = 0.5, pitch = 1.4 },
	Injector = { ids = { id(9117895638) }, volume = 0.5, pitch = 1.3 },
	Pills = { ids = { id(9117268552) }, volume = 0.5 },
	FluidBag = { ids = { id(9117640552) }, volume = 0.5 },
	Suction = { ids = { id(9125892884) }, volume = 0.5 },
	Scissors = { ids = { id(9118831072) }, volume = 0.6 },
	SurgicalTools = { ids = { id(9116525717) }, volume = 0.45 },
	Compression = { ids = { id(9113524447) }, volume = 0.35, pitch = 1.2 },
	BvmSqueeze = { ids = { id(9117019334) }, volume = 0.5 },
	AedBeep = { ids = { id(9118777239) }, volume = 0.5 },
	AedCharge = { ids = { id(9125980435) }, volume = 0.6 },
	AedShock = { ids = { id(9114277757) }, volume = 0.8 },
	BodyFall = { ids = { id(9113480915) }, volume = 0.7, range = 80 },
	Hurt = { ids = { "rbxasset://sounds/ouch.ogg" }, volume = 0.6, variance = 0.15 },

	-- Weapons --------------------------------------------------------------
	RifleShot = { ids = { id(9116347612) }, volume = 1, variance = 0.05, range = 600 },
	PistolShot = { ids = { id(9117401411) }, volume = 0.9, variance = 0.05, range = 400 },
	ShotgunShot = { ids = { id(9112912106) }, volume = 1, variance = 0.04, range = 500 },
	ShotgunPump = { ids = { id(9112910245) }, volume = 0.7 },
	ShellInsert = { ids = { id(9113104176) }, volume = 0.6, pitch = 1.4 },
	MagOut = { ids = { id(9113104176) }, volume = 0.6 },
	MagIn = { ids = { id(9113104176) }, volume = 0.7, pitch = 1.15 },
	Bolt = { ids = { id(9114004212) }, volume = 0.7 },
	DryFire = { ids = { id(119356593086642) }, volume = 0.6 },
	FireMode = { ids = { id(9116723292) }, volume = 0.5, pitch = 1.3 },
	Equip = { ids = { id(9114701864) }, volume = 0.6 },
	ImpactSurface = { ids = { id(9113632114), id(9113632257), id(9113632506), id(9113632067) }, volume = 0.6 },
	ImpactFlesh = { ids = { id(9113524237), id(144884872) }, volume = 0.8, range = 100 },
	Whiz = { ids = { id(9113634444), id(9113634517) }, volume = 0.6 },
} :: { [string]: SoundDef }

-- Plays a named sound on a BasePart / Attachment. Works on the server (replicates) and client (local only).
function Sounds.play(name: string, parent: Instance?, volumeScale: number?): Sound?
	local def = Sounds.Library[name]
	if not def or not parent or #def.ids == 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = def.ids[math.random(1, #def.ids)]
	sound.Volume = (def.volume or 0.6) * Sounds.MasterVolume * (volumeScale or 1)
	local variance = def.variance or 0.08
	sound.PlaybackSpeed = (def.pitch or 1) * (1 + (math.random() * 2 - 1) * variance)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = def.range or 60
	sound.Parent = parent
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 8)
	return sound
end

-- Plays a sound at a world position using a temporary attachment on Terrain.
function Sounds.playAt(name: string, position: Vector3, volumeScale: number?): Sound?
	local attachment = Instance.new("Attachment")
	attachment.Name = "SfxPoint"
	attachment.Parent = workspace.Terrain
	attachment.WorldPosition = position
	game:GetService("Debris"):AddItem(attachment, 8)
	return Sounds.play(name, attachment, volumeScale)
end

return Sounds
