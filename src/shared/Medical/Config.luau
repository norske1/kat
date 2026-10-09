--!strict
-- Every tunable of the medical system lives here, mirroring KAT/ACE addon options.

local Config = {}

-- General ------------------------------------------------------------------
Config.TickInterval = 1 -- seconds between simulation steps
Config.ViewInterval = 0.5 -- seconds between UI snapshots to viewers
Config.MaxTreatmentDistance = 10 -- studs
Config.CancelMoveDistance = 5 -- medic moving this far from start cancels the action
Config.SelfMenuKey = Enum.KeyCode.H
Config.DropCarryKey = Enum.KeyCode.G
Config.DebugToggleKey = Enum.KeyCode.F2
Config.BloodEffects = false -- true: red bleeding/hit particles (answer Roblox's maturity questionnaire accordingly)
Config.AllowGiveUp = true -- unconscious players get a Respawn button (costs their side a ticket in the game mode)
Config.Hardcore = false -- hides thorax injuries / fractures until diagnosed
Config.InfiniteSupplies = false
Config.SpawnTrainingDummies = true -- spawns five training casualties near spawn (Studio only unless AllowDummiesInLive)
Config.AllowDummiesInLive = false
Config.AdminUserIds = {} :: { number }
Config.InterceptHumanoidDamage = true -- convert Humanoid health loss into wounds
Config.HealthBuffer = 1000 -- Humanoid MaxHealth while managed; absorbs one-shot damage before conversion
Config.FallDamageEnabled = true
Config.FallDamageMinVelocity = 60 -- studs/s
Config.FallDamagePerVelocity = 0.9
Config.RemoteCooldown = 0.15
Config.HideDefaultHealthBar = true
Config.LogSize = 30

-- Medic levels (0 = anyone, 1 = medic, 2 = doctor). Player attribute "MedicalLevel" overrides.
Config.TeamMedicalLevels = {
	-- ["Medics"] = 1,
	-- ["Doctors"] = 2,
} :: { [string]: number }
Config.DefaultMedicalLevel = 0
Config.StudioMedicalLevel = 2 -- level used for everyone while play-testing in Studio
Config.DebugToolsInStudio = true -- debug panel (hurt / heal / spawn casualty / set level) in Studio
Config.ActionLevelOverrides = {} :: { [string]: number } -- e.g. { IV16 = 0 }

-- Blood --------------------------------------------------------------------
Config.DefaultBloodVolume = 6.0
Config.MaxBloodVolume = 6.6
Config.BloodClass1 = 5.1 -- "Lost some blood"
Config.BloodClass2 = 4.2 -- "Lost a lot of blood"
Config.BloodClass3 = 3.6 -- "Lost a large amount of blood" -> unconscious
Config.BloodClass4 = 3.0 -- "Lost a fatal amount of blood" -> cardiac arrest
Config.BleedoutVolume = 1.8 -- instant death
Config.BleedingMultiplier = 1.0
Config.StableBloodVolume = 5.1 -- required for spontaneous wake-up (KAT default)
Config.BloodTypes = { "O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+" }
Config.BloodTypeWeights = { 7, 38, 6, 34, 2, 9, 1, 3 }
Config.RequireIVForFluids = true
Config.FluidVolumes = { 250, 500, 1000 }

-- Vitals -------------------------------------------------------------------
Config.DefaultHeartRate = 80
Config.HeartRateChangePerSecond = 3
Config.DefaultResistance = 100
Config.StrokeVolume = 0.095 -- litres
Config.BPHighModifier = 9.4736842
Config.BPLowModifier = 6.3157894
Config.FatalHeartRateLow = 20
Config.FatalHeartRateHigh = 220
Config.LowHeartRateArrestChance = 0.1 -- per second while HR is 20-30
Config.StableHeartRate = 40
Config.StableBP = { 60, 50 } -- systolic, diastolic
Config.UnconsciousBPLimit = 50 -- systolic, when HR < 40

-- Pain ---------------------------------------------------------------------
Config.PainUnconsciousThreshold = 0.5
Config.PainUnconsciousChance = 0.15 -- per hit while perceived pain is above threshold
Config.HeadHitUnconsciousMultiplier = 2
Config.TourniquetPainDelay = 120
Config.TourniquetPainRate = 0.001
Config.PainBurstDecay = 0.01 -- per second

-- Breathing / oxygen -------------------------------------------------------
Config.SpO2Unconscious = 75
Config.SpO2CardiacArrest = 65
Config.SpO2Stable = 85
Config.SpO2DieEnabled = false
Config.SpO2DieValue = 50
Config.PaO2FallRate = 0.008 -- fraction of PaO2 deficit lost per second
Config.PaO2RiseRate = 0.05
Config.BVMOxygenMultiplier = 2
Config.CPRVentilation = 0.5 -- fraction of normal ventilation CPR alone provides
Config.PneumothoraxEnabled = true
Config.PneumothoraxChance = 5 -- percent, torso hits above threshold
Config.PneumothoraxDamageThreshold = 20 -- Roblox damage
Config.PneumothoraxDamageBonus = 30 -- extra percent at 3x threshold
Config.DeepPenetratingInjuryChance = 30
Config.TamponadeChance = 10
Config.PneumothoraxDeteriorateInterval = 60
Config.PneumothoraxDeteriorateChance = 50
Config.AdvancedPneumothoraxChance = 50 -- percent at stage 4+ to become tension or hemo
Config.HemothoraxBleeding = 0.003 -- L/s
Config.TamponadeGrowth = 1 / 300 -- effusion per second, arrest at 1
Config.PneumothoraxSpO2Penalty = 0.12 -- ventilation lost per stage

-- Airway -------------------------------------------------------------------
Config.AirwayEnabled = true
Config.AirwayCheckInterval = 60
Config.ObstructionChance = 15
Config.OcclusionChance = 10
Config.OcclusionCooldown = 6
Config.HeadTurnSuccessChance = 50
Config.HeadTiltRange = 6 -- medic must stay within this distance

-- Cardiac arrest -----------------------------------------------------------
Config.CardiacArrestTime = 300
Config.CardiacArrestTimeVariance = 0.1
Config.CPRTimerMultiplier = 0.5 -- timer runs at this speed during CPR
Config.PEAChance = 50
Config.VTChance = 50
Config.AsystoleBloodThreshold = 3.6
Config.RhythmDeteriorateMin = 20
Config.RhythmDeteriorateMax = 900
Config.RhythmDeteriorateWeight = 120
Config.CPRSuccessChance = { [0] = 0.35, [1] = 0.5, [2] = 0.65 } -- per completed CPR cycle, by medic level
Config.ROSCChance = 0.1 -- extra random chance any success becomes immediate ROSC
Config.AEDBaseChance = 0.5
Config.ROSCMinBloodVolume = 3.6
Config.ROSCMinSpO2 = 70
Config.AEDChargeTime = 5
Config.AEDDisarmTime = 30
Config.PostArrestBradycardiaChance = 0.33

-- Consciousness ------------------------------------------------------------
Config.WakeCheckInterval = 15
Config.WakeChance = 0.1
Config.AdrenalineWakeBonus = 0.3
Config.SmellingSaltsMaxChance = 0.5
Config.ReorientMaxChance = 0.5
Config.KnockoutDamage = 60 -- single hit damage that guarantees unconsciousness

-- Fluids / pharmacy --------------------------------------------------------
Config.IVFlowRate = 0.0041667 -- L/s at 1.0 flow (500 ml in two minutes)
Config.IOFlowMultiplier = 0.75
Config.IOInsertPain = 0.6
Config.CoagulationEnabled = true
Config.CoagulationFactors = 30
Config.CoagulationRegenInterval = 60
Config.CoagulationClotTime = { 60, 120, 240 } -- seconds to clot small/medium/large
Config.CoagulationCost = { 1, 2, 4 }
Config.KidneyEnabled = true
Config.KidneyCheckInterval = 20
Config.KidneyFailArrestChance = 0.5
Config.IncompatibleBloodArrestThreshold = 0.5 -- litres of hemolysis
Config.DrawBloodMinVolume = 3.6

-- Wounds / damage ----------------------------------------------------------
Config.DamageSmall = 15 -- damage below this makes small wounds
Config.DamageMedium = 35
Config.FractureChance = { Bullet = 15, Explosive = 35, Blunt = 30, Fall = 45, Melee = 10, Stab = 0, Generic = 10 }
Config.CompoundFractureChance = 25
Config.ComminutedFractureChance = 15
Config.BandageReopeningEnabled = true
Config.HeadshotKillDamage = 0 -- 0 disables instant death on head hits; otherwise damage threshold

-- Surgery ------------------------------------------------------------------
-- "RequireAnesthesia": patient must be unconscious or under etomidate/lorazepam.
-- "PainOnly": surgery always possible but causes heavy pain if awake.
Config.SurgeryConsciousness = "RequireAnesthesia"
Config.SplintedLegSpeed = 0.75
Config.FracturedLegSpeed = 0.5

-- Loadouts given on spawn, by medical level ----------------------------------
Config.Loadouts = {
	[0] = {
		PackingBandage = 4,
		ElasticBandage = 4,
		FieldDressing = 4,
		Tourniquet = 2,
		Splint = 1,
		PainRelief = 2,
		AdrenalineAuto = 1,
		AnalgesicAuto = 1,
	},
	[1] = {
		PackingBandage = 15,
		ElasticBandage = 10,
		FieldDressing = 10,
		HemostaticGauze = 10,
		Tourniquet = 4,
		Splint = 4,
		PainRelief = 4,
		AdrenalineAuto = 4,
		AnalgesicAuto = 4,
		ReversalSpray = 2,
		SmellingSalts = 2,
		CWMP = 2,
		PainInhaler = 2,
		IV16 = 6,
		FASTIO = 2,
		Saline500 = 4,
		Plasma500 = 2,
		BloodO_neg500 = 2,
		Adrenaline = 6,
		RhythmStabiliser = 4,
		MildRhythmStabiliser = 4,
		HeartRateBooster = 4,
		ClottingAgent = 3,
		FieldAnesthetic = 2,
		StrongAnalgesic = 1,
		PressureBooster = 2,
		PressureSupport = 2,
		PressureReducer = 2,
		ChestSeal = 3,
		AATKit = 2,
		Guedel = 2,
		AirwayTube = 2,
		Stethoscope = 1,
		PulseOximeter = 2,
		BVM = 1,
		OxygenTank = 1,
		NasalCannula = 2,
		SuctionPump = 1,
		AED = 1,
		AEDX = 1,
		ClotTester = 1,
		SurgicalKit = 1,
		BloodDrawKit = 2,
	},
	[2] = {
		PackingBandage = 20,
		ElasticBandage = 15,
		FieldDressing = 10,
		HemostaticGauze = 15,
		Tourniquet = 4,
		Splint = 6,
		PainRelief = 4,
		AdrenalineAuto = 4,
		AnalgesicAuto = 4,
		ReversalSpray = 4,
		SmellingSalts = 4,
		CWMP = 4,
		PainInhaler = 4,
		IV16 = 10,
		FASTIO = 4,
		Saline250 = 4,
		Saline500 = 6,
		Saline1000 = 2,
		Plasma500 = 4,
		BloodO_neg500 = 4,
		Adrenaline = 10,
		RhythmStabiliser = 6,
		MildRhythmStabiliser = 6,
		HeartRateBooster = 6,
		ClottingAgent = 6,
		StrongClottingAgent = 4,
		FieldAnesthetic = 4,
		StrongAnalgesic = 2,
		MildAnalgesic = 2,
		PressureBooster = 4,
		PressureSupport = 4,
		PressureReducer = 4,
		SurgicalSedative = 6,
		Sedative = 3,
		SedativeReversal = 3,
		ChestSeal = 4,
		AATKit = 4,
		Guedel = 4,
		AirwayTube = 4,
		Stethoscope = 1,
		PulseOximeter = 2,
		BVM = 1,
		OxygenTank = 1,
		NasalCannula = 4,
		SuctionPump = 1,
		AED = 1,
		AEDX = 1,
		ClotTester = 1,
		Ultrasound = 1,
		REBOA = 1,
		SurgicalKit = 1,
		Scalpel = 1,
		Retractor = 1,
		Clamp = 1,
		BonePlate = 4,
		NPWT = 4,
		BloodDrawKit = 2,
	},
} :: { [number]: { [string]: number } }

return Config
