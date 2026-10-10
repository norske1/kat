-- Usage: lune run tests/run.luau
local Harness = require("./harness")
local ModuleHarness = require("./moduleHarness")
local Roblox = require("@lune/roblox")

local Patient = Harness.require("Sim/Patient")
local Simulation = Harness.require("Sim/Simulation")
local Damage = Harness.require("Sim/Damage")
local Actions = Harness.require("Sim/Actions")
local Pharmacy = Harness.require("Sim/Pharmacy")
local Cardiac = Harness.require("Sim/Cardiac")
local Snapshot = Harness.require("Sim/Snapshot")
local Breathing = Harness.require("Sim/Breathing")
local BloodTypes = Harness.require("BloodTypes")
local Config = Harness.require("Config")
local Rng = Harness.require("Rng")

local passed, failed = 0, 0
local verbose = table.find(require("@lune/process").args, "-v") ~= nil

local function test(name: string, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

local function expect(cond: any, msg: string?)
	if not cond then
		error(msg or "expectation failed", 2)
	end
end

test("interaction mode requires Alt and a usable, focused character", function()
	local Interaction = Harness.require("Interaction")
	local context = {
		held = true,
		focused = true,
		modal = false,
		typing = false,
		hasCharacter = true,
		alive = true,
		conscious = true,
	}
	expect(Interaction.active(context))
	for _, key in { "held", "focused", "hasCharacter", "alive", "conscious" } do
		local changed = table.clone(context)
		changed[key] = false
		expect(not Interaction.active(changed), key .. " must cancel interactions")
	end
	for _, key in { "modal", "typing" } do
		local changed = table.clone(context)
		changed[key] = true
		expect(not Interaction.active(changed), key .. " blocks world input")
	end
end)

test("cursor rays use raw viewport coordinates without an extra top-bar offset", function()
	local Interaction = Harness.require("Interaction")
	local calls = {}
	local expectedRay = { Origin = "cursor origin", Direction = "cursor direction" }
	local camera = {
		ViewportSize = { X = 1920, Y = 1080 },
		CFrame = { LookVector = "centre direction" },
		ScreenPointToRay = function()
			error("GetMouseLocation is already viewport-relative; screen conversion would offset the ping")
		end,
		ViewportPointToRay = function(_, x, y)
			table.insert(calls, { x, y })
			return expectedRay
		end,
	}
	expect(Interaction.cursorRay(camera, { X = 1417, Y = 283 }) == expectedRay)
	expect(calls[1][1] == 1417 and calls[1][2] == 283, "off-centre cursor preserved without adding GUI inset")
	expect(Interaction.cursorRay(camera, { X = 72, Y = 811 }) == expectedRay)
	expect(calls[2][1] == 72 and calls[2][2] == 811, "a different cursor changes the ray")
	expect(Interaction.cursorRay(nil, { X = 0, Y = 0 }) == nil, "camera replacement is safe")
end)

test("interaction targets group actors and vehicles but not neighbouring base objects", function()
	local Interaction = Harness.require("Interaction")
	local Instance = require("@lune/roblox").Instance
	local base = Instance.new("Model")
	local first = Instance.new("Part")
	first.Parent = base
	local second = Instance.new("Part")
	second.Parent = base
	expect(Interaction.target(first, false) == first, "deployment posts stay separate")
	expect(Interaction.target(second, false) == second)
	local vehicle = Instance.new("Model")
	local hull = Instance.new("Part")
	hull.Parent = vehicle
	vehicle.PrimaryPart = hull
	expect(Interaction.target(hull, false) == vehicle, "vehicle seat and cargo share a target")
	local attachment = Instance.new("Attachment")
	attachment.Parent = hull
	expect(Interaction.target(attachment, false) == vehicle)
	local actor = Instance.new("Model")
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = actor
	local root = Instance.new("Part")
	root.Parent = actor
	expect(Interaction.target(root, false) == actor, "all body parts select the patient")
	expect(Interaction.target(first, true) == base, "arsenal shelves share their tagged model")
	expect(Interaction.target(vehicle, false) == vehicle)
	expect(Interaction.target(nil, false) == nil)
	base:Destroy()
	vehicle:Destroy()
	actor:Destroy()
end)

local function run(p, seconds: number, each: ((number) -> boolean?)?)
	for t = 1, seconds do
		Simulation.step(p, 1)
		if each and each(t) then
			return t
		end
		if not p.alive then
			return t
		end
	end
	return seconds
end

local function act(p, id: string, part: string, level: number?)
	local def = Actions.ById[id]
	assert(def, "no action " .. id)
	local ctx = { patient = p, part = part, medicLevel = level or 2, isSelf = false, rng = p.rng, medicName = "Test" }
	local ok, reason = Actions.validate(def, ctx)
	if not ok then
		return false, reason
	end
	return true, Actions.execute(def, ctx), ctx
end

local function fresh(seed: number?)
	return Patient.new({ seed = seed or 1234, bloodType = "A+" })
end

print("KAT medical simulation tests")

test("healthy patient keeps normal vitals", function()
	local p = fresh()
	run(p, 600)
	expect(p.alive and p.conscious, "should be fine")
	expect(math.abs(p.heartRate - 80) < 3, "hr " .. p.heartRate)
	expect(math.abs(p.bpSys - 120) < 5 and math.abs(p.bpDia - 80) < 5, ("bp %d/%d"):format(p.bpSys, p.bpDia))
	expect(p.spo2 > 95, "spo2 " .. p.spo2)
end)

test("oxygen dissociation curve", function()
	expect(math.abs(Breathing.spo2FromPaO2(95) - 97.4) < 1)
	expect(math.abs(Breathing.spo2FromPaO2(40) - 75) < 2)
end)

test("blood compatibility table", function()
	expect(BloodTypes.isCompatible("AB+", "O-"))
	expect(BloodTypes.isCompatible("A+", "O+"))
	expect(not BloodTypes.isCompatible("O-", "O+"))
	expect(not BloodTypes.isCompatible("A-", "B-"))
	expect(BloodTypes.fromKey(BloodTypes.toKey("AB-")) == "AB-")
end)

test("untreated large leg wound bleeds into arrest then death", function()
	local p = fresh()
	Damage.apply(p, "LeftLeg", 50, "Bullet")
	local unconsciousAt, arrestAt
	local died = run(p, 3600, function(t)
		if not unconsciousAt and not p.conscious then
			unconsciousAt = t
		end
		if not arrestAt and p.arrest then
			arrestAt = t
		end
		return false
	end)
	if verbose then
		print(
			("       unconscious %ss, arrest %ss, death %ss (%s)"):format(
				tostring(unconsciousAt),
				tostring(arrestAt),
				died,
				tostring(p.deathReason)
			)
		)
	end
	expect(arrestAt and arrestAt > 120 and arrestAt < 1200, "arrest at " .. tostring(arrestAt))
	expect(not p.alive, "should die")
end)

test("tourniquet stops limb bleeding", function()
	local p = fresh()
	Damage.apply(p, "RightArm", 50, "Bullet")
	run(p, 5)
	expect(p.bleedRate > 0)
	act(p, "ApplyTourniquet", "RightArm")
	run(p, 1)
	expect(p.bleedRate == 0, "bleed " .. p.bleedRate)
	run(p, 200)
	expect(p.painPerceived > 0.2, "tourniquet pain " .. p.painPerceived)
end)

test("bandages close wounds and can reopen", function()
	local p = fresh(77)
	Damage.apply(p, "Torso", 30, "Bullet")
	local before = Pharmacy and #p.parts.Torso.wounds
	local ok = act(p, "PackingBandage", "Torso")
	expect(ok, "bandage")
	expect(#p.parts.Torso.wounds < before or p.parts.Torso.wounds[1].amount < 1)
	expect(#p.parts.Torso.bandaged == 1)
	local ok2, reason = act(p, "PackingBandage", "Torso")
	expect(not ok2 and reason == "No open wounds", tostring(reason))
end)

test("airway obstruction while unconscious causes hypoxia; head tilt prevents", function()
	local p = fresh()
	p.knockedOut = true
	p.nextWakeCheck = math.huge
	run(p, 2)
	p.airway.obstructed = true
	run(p, 120)
	expect(p.spo2 < 85, "spo2 " .. p.spo2)
	local q = fresh()
	q.knockedOut = true
	q.nextWakeCheck = math.huge
	run(q, 2)
	q.airway.obstructed = true
	act(q, "HeadTilt", "Head")
	run(q, 120)
	expect(q.spo2 > 95, "headtilt spo2 " .. q.spo2)
	local r = fresh()
	r.knockedOut = true
	r.nextWakeCheck = math.huge
	run(r, 2)
	r.airway.nextCheck = math.huge
	r.airway.obstructed = true
	expect(act(r, "InsertGuedel", "Head"))
	run(r, 120)
	expect(r.spo2 > 95, "guedel spo2 " .. r.spo2)
end)

test("occlusion blocks devices until suctioned", function()
	local p = fresh()
	p.knockedOut = true
	run(p, 2)
	p.airway.occluded = true
	local ok, reason = act(p, "InsertAirwayTube", "Head")
	expect(not ok and reason:find("occluded"), tostring(reason))
	expect(act(p, "Suction", "Head"))
	expect(act(p, "InsertAirwayTube", "Head"))
end)

test("tension pneumothorax needs seal + decompression", function()
	local p = fresh()
	p.breathing.ptx = 4
	p.breathing.tension = true
	run(p, 90)
	expect(p.spo2 < 90, "spo2 " .. p.spo2)
	local ok, reason = act(p, "NeedleDecompression", "Torso")
	expect(not ok and reason:find("chest seal"), tostring(reason))
	expect(act(p, "ChestSeal", "Torso"))
	expect(p.breathing.ptx == 0)
	local _, text = act(p, "NeedleDecompression", "Torso")
	expect(text:find("relieved"), text)
	run(p, 120)
	expect(p.spo2 > 93, "after spo2 " .. p.spo2)
end)

test("pneumothorax deteriorates if untreated", function()
	local p = fresh(9)
	p.breathing.ptx = 1
	run(p, 900)
	expect(p.breathing.ptx > 1 or p.breathing.tension or p.breathing.hemo, "ptx " .. p.breathing.ptx)
end)

test("VF arrest: AED converts with repeated shocks", function()
	local successes = 0
	for seed = 1, 20 do
		local p = fresh(seed)
		Cardiac.enterArrest(p, "Test", "VF")
		for _ = 1, 6 do
			p.cpr = { level = 1 }
			run(p, 15)
			p.cpr = nil
			act(p, "UseAED", "Torso")
			if not p.arrest then
				successes += 1
				break
			end
		end
	end
	if verbose then
		print("       VF ROSC with AED+CPR: " .. successes .. "/20")
	end
	expect(successes >= 12, "successes " .. successes)
end)

test("AED refuses non-shockable rhythms", function()
	local p = fresh()
	Cardiac.enterArrest(p, "Test", "Asystole")
	local _, text = act(p, "UseAED", "Torso")
	expect(text:find("no shock"), text)
end)

test("hemorrhagic arrest needs volume before ROSC", function()
	local p = fresh(5)
	Damage.apply(p, "LeftLeg", 60, "Bullet")
	run(p, 2000, function()
		return p.arrest ~= nil
	end)
	expect(p.arrest, "arrest")
	act(p, "ApplyTourniquet", "LeftLeg")
	p.cpr = { level = 2 }
	local _, text = act(p, "CPR", "Torso")
	expect(text:find("Hypovolemia"), text)
	act(p, "FASTIO", "Torso")
	act(p, "GiveBloodO_neg1000", "Torso")
	act(p, "GivePlasma1000", "Torso")
	local rosc = false
	local lastText = ""
	for _ = 1, 20 do
		p.cpr = { level = 2 }
		act(p, "Suction", "Head")
		act(p, "InsertAirwayTube", "Head")
		act(p, "UseBVM", "Head")
		run(p, 15)
		if Pharmacy.concentration(p, "Adrenaline") < 0.3 then
			act(p, "PushAdrenaline", "Torso")
		end
		local _, cprText = act(p, "CPR", "Torso")
		lastText = cprText
		if not p.arrest then
			rosc = true
			break
		end
		if not p.alive then
			break
		end
	end
	p.cpr = nil
	if verbose then
		print(("       rosc=%s alive=%s blood=%.2f"):format(tostring(rosc), tostring(p.alive), p.bloodVolume))
	end
	expect(rosc, ("expected ROSC; blood %.2f spo2 %.0f last %s"):format(p.bloodVolume, p.spo2, tostring(lastText)))
end)

test("arrest without CPR is fatal after ~5 minutes", function()
	local p = fresh()
	Cardiac.enterArrest(p, "Test", "PEA")
	local t = run(p, 1000)
	expect(not p.alive and t > 250 and t < 350, "died at " .. t)
end)

test("CPR slows the arrest timer", function()
	local p = fresh()
	Cardiac.enterArrest(p, "Test", "Asystole")
	p.cpr = { level = 0 }
	run(p, 400)
	expect(p.alive, "should still be alive with CPR")
end)

test("respiratory depression depresses breathing; reversal spray reverses", function()
	local p = fresh(3)
	for _ = 1, 6 do
		Pharmacy.administer(p, "Analgesic", p.rng)
	end
	run(p, 120)
	expect(p.breathing.respArrest or p.respRate < 10, "rr " .. p.respRate)
	Pharmacy.administer(p, "ReversalSpray", p.rng)
	run(p, 5)
	expect(not p.breathing.respArrest)
	expect(Pharmacy.dosesInSystem(p, "Analgesic") == 0)
end)

test("medication ramps to peak then decays", function()
	local p = fresh()
	Pharmacy.administer(p, "Adrenaline", Rng.new(1))
	run(p, 5)
	local early = p.effects.hr
	run(p, 6)
	local peak = p.effects.hr
	run(p, 200)
	expect(early > 0 and peak > early, ("%f %f"):format(early, peak))
	expect(#p.meds == 0 and p.effects.hr == 0)
end)

test("saline adds less volume than blood", function()
	local p = fresh()
	p.bloodVolume = 4.5
	act(p, "IV16", "LeftArm")
	act(p, "GiveSaline500", "LeftArm")
	run(p, 200)
	local afterSaline = p.bloodVolume
	expect(math.abs(afterSaline - 4.65) < 0.02, "saline " .. afterSaline)
	act(p, "GiveBloodA_pos500", "LeftArm")
	run(p, 200)
	expect(math.abs(p.bloodVolume - afterSaline - 0.4) < 0.02, "blood " .. p.bloodVolume)
end)

test("tourniquet blocks IV flow on that limb", function()
	local p = fresh()
	act(p, "IV16", "LeftArm")
	act(p, "ApplyTourniquet", "LeftArm")
	local ok, reason = act(p, "PushAdrenaline", "Torso")
	expect(not ok and reason:find("access"), tostring(reason))
end)

test("incompatible blood causes transfusion reaction arrest", function()
	local p = Patient.new({ seed = 1, bloodType = "O-" })
	act(p, "IV16", "LeftArm")
	act(p, "GiveBloodAB_pos1000", "LeftArm")
	run(p, 400, function()
		return p.arrest ~= nil
	end)
	expect(p.arrest and p.arrest.cause == "Transfusion reaction", p.arrest and p.arrest.cause or "no arrest")
end)

test("compound fracture surgical pathway", function()
	local p = fresh()
	p.parts.LeftLeg.fracture = 2
	local ok, reason = act(p, "Incision", "LeftLeg")
	expect(not ok and reason:find("diagnosed"), tostring(reason))
	act(p, "CheckFracture", "LeftLeg")
	ok, reason = act(p, "Incision", "LeftLeg")
	expect(not ok and reason:find("anesthesia"), tostring(reason))
	act(p, "IV16", "RightArm")
	act(p, "PushSurgicalSedative", "Torso")
	run(p, 6)
	expect(not p.conscious, "should be anesthetised")
	for _, id in { "Incision", "ExposeFracture", "IrrigateWound", "OpenReduction" } do
		local done, why = act(p, id, "LeftLeg")
		expect(done, id .. ": " .. tostring(why))
	end
	expect(p.parts.LeftLeg.fracture == 0)
end)

test("simple fracture: closed reduction then splint", function()
	local p = fresh()
	p.parts.RightLeg.fracture = 1
	act(p, "CheckFracture", "RightLeg")
	expect(act(p, "ClosedReduction", "RightLeg"))
	expect(p.parts.RightLeg.fracture == -1)
	expect(act(p, "ApplySplint", "RightLeg"))
	expect(p.parts.RightLeg.fracture == 0)
end)

test("medic levels gate actions", function()
	local p = fresh()
	local ok, reason = act(p, "IV16", "LeftArm", 0)
	expect(not ok and reason == "Requires medic", tostring(reason))
end)

test("knocked out patient with stable vitals wakes up", function()
	local p = fresh()
	p.knockedOut = true
	run(p, 600)
	expect(p.conscious, "should wake")
end)

test("snapshot builds and lists actions", function()
	local p = fresh()
	Damage.apply(p, "LeftArm", 30, "Bullet")
	run(p, 3)
	local snap = Snapshot.build(p, {
		viewerLevel = 1,
		isSelf = false,
		inventoryHas = function(id)
			return id == "PackingBandage"
		end,
	})
	expect(#snap.parts.LeftArm.wounds >= 1)
	local found = false
	for _, a in snap.actions.LeftArm do
		if a.id == "PackingBandage" then
			found = a.enabled
		end
		expect(a.id ~= "ElasticBandage", "should hide items not carried")
	end
	expect(found, "packing bandage listed")
	local eff = Snapshot.selfEffects(p)
	expect(eff.pain >= 0)
end)

test("random damage soak never errors", function()
	local rng = Rng.new(42)
	local types = { "Bullet", "Explosive", "Blunt", "Fall", "Melee", "Stab", "Generic" }
	for seed = 1, 30 do
		local p = fresh(seed)
		for _ = 1, 8 do
			Damage.applySpread(p, rng:range(5, 60), types[math.floor(rng:range(1, #types + 0.999))])
			run(p, 30)
		end
		Snapshot.build(p, {
			viewerLevel = 2,
			isSelf = false,
			inventoryHas = function()
				return true
			end,
		})
	end
end)

test("arm injuries impair weapon handling", function()
	local p = Patient.new({ seed = 5 })
	expect(Patient.armImpairment(p) == 0, "healthy arms")
	p.parts.RightArm.fracture = 2
	local broken = Patient.armImpairment(p)
	expect(broken > 0.5, "fracture impairs: " .. broken)
	p.parts.RightArm.splint = true
	expect(Patient.armImpairment(p) < broken, "splint helps")
	p.parts.LeftArm.tourniquet = 0
	expect(Patient.armImpairment(p) <= 1, "clamped")
	local snap = Snapshot.selfEffects(p)
	expect(snap.armInjury == Patient.armImpairment(p), "exposed to client effects")
end)

test("every action has animation and sound fx", function()
	local ActionFx = Harness.require("ActionFx")
	local Animations = Harness.require("Animations")
	local Sounds = Harness.require("Sounds")
	for _, def in Actions.List do
		local fx = ActionFx.get(def)
		expect(Animations.Motions[fx.motion], def.id .. " motion " .. fx.motion)
		for _, base in
			{ ActionFx.base(fx, true, false), ActionFx.base(fx, false, true), ActionFx.base(fx, false, false) }
		do
			local pose = Animations.medical(base .. "." .. fx.motion, 0.37)
			expect(pose, def.id .. " clip " .. base .. "." .. fx.motion)
		end
		for _, key in { "start", "loop", "finish" } do
			local name = (fx :: any)[key]
			expect(name == nil or Sounds.Library[name], def.id .. " sound " .. tostring(name))
		end
	end
	expect(ActionFx.isShock("UseAED", "Shock delivered"), "shock detected")
	expect(not ActionFx.isShock("UseAED", "No shock advised"), "no shock")
end)

test("animation sampling and weapon poses", function()
	local Animations = Harness.require("Animations")
	local cpr = Animations.Motions.Cpr
	local a = Animations.sample(cpr, 0)
	local b = Animations.sample(cpr, cpr.period)
	expect(math.abs(a.Waist[1] - b.Waist[1]) < 1e-6, "loops seamlessly")
	local mid = Animations.sample(cpr, 0.25)
	expect(mid.Waist[1] < a.Waist[1], "compression leans down")
	local _, full = Animations.medical("Kneel.Cpr", 0)
	expect(full, "kneel is full body")
	local _, upper = Animations.medical("Stand.Work", 0)
	expect(not upper, "stand is upper body")
	expect(Animations.medical("Nope.Work", 0) == nil, "unknown clip")
	for hold, set in Animations.Gun do
		local hip = Animations.gun(hold, 0, 0)
		local aim = Animations.gun(hold, 1, 0)
		expect(hip and math.abs(hip.RightShoulder[1] - set.hip.RightShoulder[1]) < 1e-6, hold .. " hip")
		expect(aim and math.abs(aim.RightShoulder[1] - set.aim.RightShoulder[1]) < 1e-6, hold .. " aim")
		local up = Animations.gun(hold, 1, 30)
		expect(up and up.RightShoulder[1] > aim.RightShoulder[1], hold .. " pitch raises arms")
		for action in Animations.GunActions do
			expect(Animations.gun(hold, 0.5, -10, action, 0.5, 1), hold .. " " .. action)
		end
	end
end)

test("stance poses and sprint blend", function()
	local Animations = Harness.require("Animations")
	expect(Animations.movement(0, 0) == nil, "standing straight has no pose")
	local crouch = Animations.movement(1, 0)
	expect(crouch and crouch.RightKnee[1] < -90, "crouch bends knees")
	local left = Animations.movement(0, -1)
	local right = Animations.movement(0, 1)
	expect(left and right and left.Waist[3] > 0 and right.Waist[3] < 0, "lean rolls opposite ways")
	for hold, sprintPose in Animations.GunSprint do
		local run = Animations.gun(hold, 0, 0, nil, nil, 0, 1)
		expect(run and math.abs(run.RightElbow[1] - sprintPose.RightElbow[1]) < 1e-6, hold .. " sprint pose")
		local aimed = Animations.gun(hold, 1, 0, nil, nil, 0, 1)
		local set = Animations.Gun[hold]
		expect(
			aimed and math.abs(aimed.RightShoulder[1] - set.aim.RightShoulder[1]) < 1e-6,
			hold .. " aim beats sprint"
		)
	end
end)

test("ballistics drop and weapon velocities", function()
	local Ballistics = Harness.require("Weapons/Ballistics")
	expect(math.abs(Ballistics.dropAt(1000, 3000, 35) - 0.5 * 35 * (1 / 3) ^ 2) < 1e-9, "drop formula")
	expect(Ballistics.dropAt(500, 1300, 35) > Ballistics.dropAt(500, 3000, 35), "slower bullets drop more")
end)

local GAME = {
	CaptureSeconds = 10,
	ExtraCapperBonus = 0.5,
	MaxCaptureMultiplier = 3,
	RegenSeconds = 20,
	DeathTickets = 1,
	ObjectiveLossTickets = 50,
}

local function hold(rules, state, i: number, a: number, b: number, seconds: number)
	local events = {}
	for _ = 1, seconds * 10 do
		for _, e in rules.capture(state, i, a, b, 0.1, GAME) do
			table.insert(events, e)
		end
	end
	return events
end

test("game mode: objectives are captured in order 1 -> 2 -> 3", function()
	local Rules = Harness.require("GameMode/Rules")
	local s = Rules.new(3, 250)
	expect(s.points[1].owner == "A" and s.points[3].owner == "B" and s.points[2].owner == nil, "start owners")
	expect(Rules.attackable(s.points, "A") == 2 and Rules.attackable(s.points, "B") == 2, "both attack 2")
	hold(Rules, s, 3, 1, 0, 30)
	expect(s.points[3].owner == "B" and s.points[3].progress == -100, "A can't touch 3 before 2")
	hold(Rules, s, 1, 0, 1, 30)
	expect(s.points[1].owner == "A" and s.points[1].progress == 100, "B can't touch 1 before 2")
	local events = hold(Rules, s, 2, 1, 0, 11)
	expect(s.points[2].owner == "A" and events[1] and events[1].kind == "captured", "A captures 2")
	expect(s.tickets.A == 250 and s.tickets.B == 250, "capturing neutral costs nobody tickets")
	-- A holds 1 and 2: B must retake 2 before 1, A may now attack 3
	expect(Rules.attackable(s.points, "B") == 2 and Rules.attackable(s.points, "A") == 3, "lane moved")
	hold(Rules, s, 1, 0, 3, 30)
	expect(s.points[1].owner == "A", "1 locked for B while A holds 2")
	events = hold(Rules, s, 2, 0, 1, 11)
	expect(s.points[2].owner == nil and s.tickets.A == 200, "B neutralises 2: A -50")
	expect(events[1] and events[1].kind == "lost" and events[1].side == "A", "lost event")
	hold(Rules, s, 2, 0, 1, 11)
	expect(s.points[2].owner == "B" and Rules.attackable(s.points, "B") == 1, "B owns 2, now attacks 1")
end)

test("game mode: contest, more players, regen and tickets", function()
	local Rules = Harness.require("GameMode/Rules")
	local s = Rules.new(3, 250)
	hold(Rules, s, 2, 2, 2, 5)
	expect(s.points[2].progress == 0, "equal numbers contest")
	hold(Rules, s, 2, 3, 1, 2.5)
	expect(math.abs(s.points[2].progress - 37.5) < 1e-6, "2 extra attackers capture 1.5x faster")
	hold(Rules, s, 2, 0, 0, 5)
	expect(math.abs(s.points[2].progress - 12.5) < 1e-6, "empty neutral objective drifts back")
	for _ = 1, 249 do
		Rules.death(s, "B", GAME)
	end
	expect(s.tickets.B == 1 and s.winner == nil, "deaths cost one ticket")
	Rules.death(s, "B", GAME)
	expect(s.tickets.B == 0 and s.winner == "A", "0 tickets loses")
	hold(Rules, s, 2, 0, 5, 30)
	expect(math.abs(s.points[2].progress - 12.5) < 1e-6, "nothing changes after the round ends")
end)

test("career stats", function()
	local Career = Harness.require("GameMode/Career")
	expect(Career.formatKd(10, 4) == "2.50" and Career.formatKd(3, 0) == "3.00", "k/d")
	expect(
		Career.formatTime(45) == "45s" and Career.formatTime(750) == "12m" and Career.formatTime(11100) == "3h 05m",
		"time"
	)
	expect(Career.mostUsedClass({}) == "Rifleman", "default class")
	expect(Career.mostUsedClass({ Rifleman = 10, Medic = 30 }) == "Medic", "most used class")
	local d = Career.sanitize({ kills = 5, deaths = -2, seconds = "x", classSeconds = { Medic = 3 } })
	expect(d.kills == 5 and d.deaths == 0 and d.seconds == 0 and d.classSeconds.Medic == 3, "sanitize")
	Career.merge(d, { kills = 1, deaths = 2, seconds = 10, classSeconds = { Medic = 1 } })
	expect(d.kills == 6 and d.deaths == 2 and d.seconds == 10 and d.classSeconds.Medic == 4, "merge")
	expect(Career.sanitize(nil).kills == 0, "no saved data")
end)

test("squads and classes", function()
	local Squads = Harness.require("GameMode/Squads")
	local config = {
		SquadSize = 3,
		DefaultClass = "Rifleman",
		Classes = {
			{ name = "Commander", perSide = true },
			{ name = "Squad Commander", cap = 1, leader = true },
			{ name = "Rifleman" },
			{ name = "Medic", cap = 1 },
		},
	}
	local s = Squads.new(config)
	expect(Squads.classOf(s, 1) == "Rifleman", "no squad = rifleman")
	expect(not Squads.setClass(s, 1, "Medic", "A"), "needs a squad for medic")
	Squads.create(s, 1, "A")
	local squad = Squads.squadOf(s, 1)
	expect(squad and squad.number == 1 and Squads.classOf(s, 1) == "Squad Commander", "creator leads")
	expect(Squads.join(s, 2, squad.id, "A") and Squads.join(s, 3, squad.id, "A"), "join")
	expect(not Squads.join(s, 4, squad.id, "A"), "squad cap")
	expect(not Squads.join(s, 5, squad.id, "B"), "other side")
	expect(Squads.setClass(s, 2, "Medic", "A") and not Squads.setClass(s, 3, "Medic", "A"), "medic cap")
	expect(not Squads.setClass(s, 2, "Squad Commander", "A"), "only leader is squad commander")
	expect(not Squads.setClass(s, 1, "Medic", "A"), "leader keeps class")
	expect(Squads.setPublic(s, 1, false) and not Squads.setPublic(s, 2, true), "only leader sets private")
	Squads.kick(s, 1, 3)
	expect(not Squads.squadOf(s, 3) and not Squads.join(s, 3, squad.id, "A"), "kicked, private")
	expect(not Squads.kick(s, 2, 1), "members can't kick")
	Squads.leave(s, 1)
	expect(squad.leader == 2 and Squads.classOf(s, 2) == "Squad Commander", "leadership passes on")
	expect(Squads.setClass(s, 6, "Commander", "A") and Squads.classOf(s, 6) == "Commander", "commander")
	expect(not Squads.setClass(s, 7, "Commander", "A") and Squads.setClass(s, 7, "Commander", "B"), "1 per side")
	Squads.setClass(s, 2, "Commander", "A") -- taken: stays in squad
	expect(Squads.squadOf(s, 2) ~= nil, "failed commander keeps squad")
	Squads.create(s, 8, "A")
	expect(Squads.squadOf(s, 8).number == 2, "squad numbers")
	Squads.remove(s, 2)
	expect(s.squads[squad.id] == nil, "empty squad removed")
	Squads.create(s, 9, "A")
	expect(Squads.squadOf(s, 9).number == 1, "numbers reused")
	local data = Squads.serialize(s)
	expect(#data.squads == 2 and data.commanders.A == 6 and data.commanders.B == 7, "serialize")
end)

test("game mode: team gap limit", function()
	local Rules = Harness.require("GameMode/Rules")
	expect(not Rules.canJoin(8, 5, 3), "5 vs 8: can't join the team with 8")
	expect(Rules.canJoin(5, 8, 3), "5 vs 8: can join the team with 5")
	expect(Rules.canJoin(7, 5, 3), "7 vs 5: joining makes 8 vs 5, gap 3 is allowed")
	expect(Rules.canJoin(0, 0, 3) and Rules.canJoin(2, 0, 3) and not Rules.canJoin(3, 0, 3), "small teams")
end)

test("gear: weights, containers and kits", function()
	local Gear = Harness.require("Gear/Gear")
	local GearConfig = Harness.require("Gear/Config")
	local Config = Harness.require("Config")
	local s = Gear.new()
	expect(Gear.add(s, "Ammo556", 30) == 0, "nothing fits without containers")
	Gear.wear(s, "Uniform")
	local fit = Gear.add(s, "Ammo556", 10000)
	expect(fit == math.floor(8 / 0.016 + 1e-6) and Gear.load(s, "uniform") <= 8 + 1e-6, "uniform capacity")
	Gear.wear(s, "AssaultPack")
	expect(Gear.move(s, "Ammo556", 100, "uniform", "backpack") == 100, "move between containers")
	local _, old, overflow = Gear.wear(s, "Uniform")
	expect(old == "Uniform" and next(overflow) == nil, "swapping keeps contents")
	local id, contents = Gear.unwear(s, "backpack")
	expect(id == "AssaultPack" and contents.Ammo556 == 100 and Gear.count(s, "Ammo556") == fit - 100, "unwear")
	expect(Gear.remove(s, "Ammo556", 50) == 50 and Gear.count(s, "Ammo556") == fit - 150, "remove")
	expect(Gear.add(s, "M4A1", 1) == 0, "weapons only go in slots")
	expect(Gear.speed(10) == 1 and math.abs(Gear.speed(GearConfig.MaxMass) - GearConfig.MinSpeed) < 1e-6, "speed")
	expect(not Gear.canSprint(GearConfig.NoSprintMass + 1), "too heavy to sprint")
	expect(Gear.def("Saline500").mass == 0.5 and Gear.def("FieldDressing").kind == "medical", "medical weights")
	for class, kit in GearConfig.Kits do
		local st, missing = Gear.fromKit(kit, Config.Loadouts[GearConfig.SpawnMedicalLoadoutLevel])
		expect(next(missing) == nil, class .. " kit doesn't fit: " .. tostring(next(missing)))
		expect(st.slots.vest == nil and st.slots.backpack == nil, class .. " must spawn without a vest or backpack")
		expect(
			Gear.capacity(st, "vest") == 0 and Gear.capacity(st, "backpack") == 0,
			"unequipped containers have no capacity"
		)
		expect(Gear.load(st, "uniform") <= Gear.capacity(st, "uniform"), "starter supplies fit the uniform")
		expect(Gear.count(st, "Radio") == 1 and Gear.count(st, "Hammer") == 1, "basic equipment is retained")
		local mass = Gear.mass(st)
		print(("    %s kit %.1f kg"):format(class, mass))
		expect(Gear.canSprint(mass) and Gear.speed(mass) >= 0.9, class .. " kit too heavy")
		expect(Gear.def(st.slots.primary).weaponId ~= nil, "primary weapon")
	end
end)

test("personal inventory opens without a locker but respects character and UI state", function()
	local Gear = Harness.require("Gear/Gear")
	local ctx =
		{ hasCharacter = true, alive = true, conscious = true, typing = false, modal = false, alreadyOpen = false }
	expect(Gear.canOpen(ctx), "no source or locker is required")
	for _, field in { "hasCharacter", "alive", "conscious" } do
		local blocked = table.clone(ctx)
		blocked[field] = false
		expect(not Gear.canOpen(blocked), field .. " gate")
	end
	ctx.typing = true
	expect(not Gear.canOpen(ctx), "typing must not open inventory")
	ctx.typing = false
	ctx.modal = true
	expect(not Gear.canOpen(ctx), "don't stack inventory onto another modal")
	ctx.alreadyOpen = true
	expect(Gear.canOpen(ctx), "refreshing an existing inventory is allowed")
end)

test("hotbar weapon slots stay stable across equip, respawn and acquisition order", function()
	local Hotbar = Harness.require("Weapons/Hotbar")
	local primary = { weaponId = "M4A1", name = "Rifle", tool = "rifle" }
	local sidearm = { weaponId = "G17", name = "Pistol", tool = "pistol" }
	local first = Hotbar.layout({ sidearm, primary })
	local second = Hotbar.layout({ primary, sidearm })
	expect(first[1] == primary and first[2] == sidearm and first[3] == nil)
	expect(second[1] == first[1] and second[2] == first[2], "Backpack versus Character order cannot swap keys")
	local pistolOnly = Hotbar.layout({ sidearm })
	expect(pistolOnly[1] == nil and pistolOnly[2] == sidearm, "dropping the rifle doesn't change the pistol key")
	local replacement = { weaponId = "M870", name = "Shotgun", tool = "replacement" }
	expect(Hotbar.layout({ replacement, sidearm })[1] == replacement, "primary replacements use slot 1")
	expect(next(Hotbar.layout({})) == nil, "no stale tools after death")
	expect(#Hotbar.Keys == 9 and Hotbar.Keys[1] == "One" and Hotbar.Keys[9] == "Nine")
end)

test("hotbar extras are deterministic and never overwrite the weapon slots", function()
	local Hotbar = Harness.require("Weapons/Hotbar")
	local a = { name = "Hammer", itemId = "Hammer" }
	local b = { name = "Radio", itemId = "Radio" }
	local slots = Hotbar.layout({ b, a })
	expect(slots[1] == nil and slots[2] == nil and slots[3] == nil)
	expect(slots[4] == a and slots[5] == b)
	expect(Hotbar.layout({ b })[5] == b, "dropping the hammer never moves the radio key")
	local many = {}
	for i = 1, 12 do
		table.insert(many, { name = string.format("Tool %02d", i) })
	end
	local full = Hotbar.layout(many)
	expect(full[9] ~= nil and full[10] == nil, "extras obey the nine-slot limit")
end)

test("driver stance blocks vehicle seats and tagged driver seats but not passengers", function()
	local Stance = Harness.require("Weapons/Stance")
	local function hum(kind, role)
		return {
			SeatPart = {
				IsA = function(_, name)
					return name == kind
				end,
				GetAttribute = function(_, name)
					return if name == "Role" then role else nil
				end,
			},
		}
	end
	expect(Stance.isDriving(hum("VehicleSeat", nil)), "native driver seat")
	expect(Stance.isDriving(hum("Seat", "driver")), "tagged custom driver seat")
	expect(not Stance.isDriving(hum("Seat", "passenger")))
	expect(not Stance.isDriving(hum("Seat", "gunner")))
	expect(not Stance.isDriving({}) and not Stance.isDriving(nil), "on foot / no character")
end)

test("chat: local range and radio channels", function()
	local Comms = Harness.require("GameMode/Comms")
	local cfg = { LocalRange = 40, UnconsciousCanTalk = false }
	local function p(uid, side, squad, class, radio, x, conscious)
		return {
			uid = uid,
			side = side,
			squad = squad,
			class = class,
			radio = radio,
			conscious = conscious ~= false,
			pos = if x then { X = x, Y = 0, Z = 0 } else nil,
		}
	end
	local a = p(1, "A", 1, "Rifleman", true, 0)
	local near = p(2, "B", 0, "Rifleman", false, 30)
	local far = p(3, "A", 1, "Rifleman", true, 500)
	local farOther = p(4, "A", 2, "Squad Commander", true, 500)
	local lead = p(5, "A", 1, "Squad Commander", true, 900)
	local cmdr = p(6, "A", 0, "Commander", true, 900)
	local noRadio = p(7, "A", 1, "Rifleman", false, 900)
	expect(Comms.canHear("local", a, near, cfg) and not Comms.canHear("local", a, far, cfg), "local range")
	expect(Comms.canHear("local", p(8, nil, 0, "Rifleman", false), p(9, nil, 0, "Rifleman", false), cfg), "lobby")
	expect(Comms.canHear("team", a, farOther, cfg) and not Comms.canHear("team", a, near, cfg), "team radio")
	expect(not Comms.canHear("team", a, noRadio, cfg), "listener needs a radio")
	expect(not Comms.canHear("team", noRadio, a, cfg) and Comms.blocked("team", noRadio, cfg) ~= nil, "sender radio")
	expect(Comms.canHear("squad", a, far, cfg) and not Comms.canHear("squad", a, farOther, cfg), "squad radio")
	expect(Comms.blocked("command", a, cfg) ~= nil, "riflemen can't use command")
	expect(Comms.canHear("command", lead, cmdr, cfg) and Comms.canHear("command", cmdr, farOther, cfg), "command")
	expect(not Comms.canHear("command", lead, far, cfg), "command is leaders only")
	local down = p(10, "A", 1, "Rifleman", true, 0, false)
	expect(not Comms.canHear("local", down, near, cfg) and not Comms.canHear("squad", a, down, cfg), "unconscious")
	expect(Comms.canHear("squad", down, down, cfg), "always see your own message")
end)

test("pings: who sees them and limits", function()
	local Pings = Harness.require("GameMode/Pings")
	local function ping(uid, class, squad, side)
		return {
			id = uid,
			uid = uid,
			side = side or "A",
			squad = squad,
			class = class,
			scope = Pings.scope(class, squad),
			expires = 100,
		}
	end
	local function viewer(uid, class, squad, side)
		return { uid = uid, class = class, squad = squad, side = side or "A" }
	end
	local member, leader, cmdr = ping(1, "Rifleman", 1), ping(2, "Squad Commander", 1), ping(3, "Commander", 0)
	local mate, other, loner = viewer(4, "Rifleman", 1), viewer(5, "Medic", 2), viewer(6, "Rifleman", 0)
	local enemy = viewer(7, "Rifleman", 1, "B")
	expect(Pings.visible(member, mate) and not Pings.visible(member, other), "member pings: own squad only")
	expect(Pings.visible(leader, mate) and Pings.visible(leader, other), "squad commander pings: every squad")
	expect(Pings.visible(cmdr, loner) and Pings.visible(cmdr, other), "commander pings: everyone")
	expect(not Pings.visible(cmdr, enemy) and not Pings.visible(leader, enemy), "never the enemy")
	expect(Pings.visible(member, viewer(1, "Rifleman", 1)), "you see your own")
	local list = {}
	local limits = { Commander = 5, ["Squad Commander"] = 3, default = 2 }
	for i = 1, 4 do
		local p = ping(1, "Rifleman", 1)
		p.id = i
		Pings.add(list, p, 0, limits)
	end
	expect(#list == 2 and list[1].id == 3 and list[2].id == 4, "oldest pings dropped past the limit")
	expect(Pings.prune(list, 200) and #list == 0, "expired pings removed")
end)

test("vehicles: caps and cooldowns", function()
	local Pool = Harness.require("Vehicles/Pool")
	local pool = Pool.new({ MRAP = { cap = 5 }, Helicopter = { cap = 2 } })
	for i = 1, 5 do
		expect(Pool.claim(pool, "MRAP", i, 0, 180), "MRAP " .. i)
	end
	local ok, why = Pool.claim(pool, "MRAP", 6, 500, 180)
	expect(not ok and why == "All 5 are deployed", "all 5 alive blocks spawning: " .. tostring(why))
	Pool.release(pool, "MRAP", 2)
	expect(Pool.claim(pool, "MRAP", 7, 200, 180), "slot ready again after its cooldown")
	Pool.release(pool, "MRAP", 7)
	ok, why = Pool.claim(pool, "MRAP", 8, 260, 180)
	expect(not ok and why == "Next one ready in 2:00", "cooldown runs from the last spawn: " .. tostring(why))
	local alive, ready, wait = Pool.status(pool, "MRAP", 260)
	expect(alive == 4 and ready == 0 and wait == 120, "status")
	expect(Pool.claim(pool, "MRAP", 9, 380, 180), "ready at 380")
	expect(Pool.claim(pool, "Helicopter", 10, 0, 480) and Pool.claim(pool, "Helicopter", 11, 0, 480), "2 helis")
	expect(not Pool.claim(pool, "Helicopter", 12, 1000, 480), "heli cap 2")
end)

test("logistics: placement rules and supplies", function()
	local Logistics = Harness.require("Logistics/Logistics")
	local cfg = { PlaceRange = 40, FobMinFromMain = 300, FobSpacing = 250 }
	local function ctx(over)
		local c = {
			class = "Squad Commander",
			distance = 10,
			fob = { stock = 500, habs = 0 },
			mainDistance = 1000,
			fobDistance = 1000,
			blocked = false,
		}
		for k, v in over or {} do
			c[k] = v
		end
		return c
	end
	local hab = { cost = 300 }
	expect(Logistics.canPlace("HAB", hab, ctx(), cfg), "leader in FOB with supplies")
	expect(not Logistics.canPlace("HAB", hab, ctx({ class = "Rifleman" }), cfg), "riflemen can't place")
	expect(Logistics.canPlace("HAB", hab, ctx({ class = "Commander" }), cfg), "commander can place")
	expect(not Logistics.canPlace("HAB", hab, ctx({ fob = { stock = 100, habs = 0 } }), cfg), "needs supplies")
	expect(not Logistics.canPlace("HAB", hab, ctx({ fob = { stock = 900, habs = 1 } }), cfg), "one HAB per FOB")
	local noFob = ctx()
	noFob.fob = nil
	expect(not Logistics.canPlace("Sandbags", { cost = 20 }, noFob, cfg), "needs a FOB")
	expect(Logistics.canPlace("FOB", { cost = 0 }, noFob, cfg), "FOB radio needs no FOB")
	expect(not Logistics.canPlace("FOB", { cost = 0 }, ctx({ mainDistance = 100 }), cfg), "not near main")
	expect(not Logistics.canPlace("FOB", { cost = 0 }, ctx({ fobDistance = 100 }), cfg), "FOB spacing")
	expect(not Logistics.canPlace("Sandbags", { cost = 20 }, ctx({ blocked = true }), cfg), "blocked")
	expect(Logistics.transfer(math.huge, 200, 1000) == 800, "load a truck to capacity")
	expect(Logistics.transfer(1000, 2500, 3000) == 500, "FOB stock cap")
end)

test("construction menu shows exact supply shortages before placement", function()
	local Logistics = Harness.require("Logistics/Logistics")
	local hab = { cost = 300 }
	local ok, why = Logistics.available("HAB", hab, { stock = 100, habs = 0 })
	expect(not ok and why == "Missing 200 supplies (100/300 available)", tostring(why))
	ok, why = Logistics.available("HAB", hab, { stock = 300, habs = 0 })
	expect(ok and why == nil, "exact stock is enough")
	ok, why = Logistics.available("HAB", hab, { stock = 900, habs = 1 })
	expect(not ok and why == "This FOB already has a HAB")
	ok, why = Logistics.available("Sandbags", { cost = 20 }, nil)
	expect(not ok and why == "Must be inside a friendly FOB's radius")
	expect(Logistics.available("FOB", { cost = 0 }, nil), "FOB radios never need stock")
	local cfg = { PlaceRange = 40, FobMinFromMain = 300, FobSpacing = 250 }
	local placed, reason = Logistics.canPlace("HAB", hab, {
		class = "Commander",
		distance = 10,
		fob = { stock = 299, habs = 0 },
		mainDistance = 1000,
		fobDistance = 1000,
		blocked = false,
	}, cfg)
	expect(not placed and reason == "Missing 1 supplies (299/300 available)", "server rejects with the same text")
end)

test("interaction prompts: F/G/V shortcuts, no bare-click triggers, V card is key-only", function()
	local Interaction = ModuleHarness.load("shared/Medical/Interaction", {})
	local Instance = Roblox.Instance
	local function prompt(key, hold)
		local p = Instance.new("ProximityPrompt")
		p.ClickablePrompt = true
		p.HoldDuration = hold
		p.KeyboardKeyCode = Roblox.Enum.KeyCode.F
		if key then
			p:SetAttribute("InteractionKey", key)
		end
		Interaction.configure(p)
		return p
	end
	local seat = prompt(nil, 0)
	expect(seat.KeyboardKeyCode == Interaction.NoKeyboard, "cards without a shortcut are click-only")
	expect(seat.ClickablePrompt == false, "Roblox must not trigger prompts on a bare click")
	expect(seat.Style == Roblox.Enum.ProximityPromptStyle.Custom)
	expect(Interaction.clickable(seat))
	local cargo = prompt("V", 0)
	expect(cargo.KeyboardKeyCode == Roblox.Enum.KeyCode.V and cargo.ClickablePrompt == false)
	expect(not Interaction.clickable(cargo), "cargo opens with V only, never with the seat click")
	local build, dismantle = prompt("F", 1), prompt("G", 6)
	expect(build.KeyboardKeyCode == Roblox.Enum.KeyCode.F and dismantle.KeyboardKeyCode == Roblox.Enum.KeyCode.G)
	expect(build.KeyboardKeyCode ~= dismantle.KeyboardKeyCode, "build and dismantle use different keys")
	expect(
		Interaction.clickable(build) and Interaction.clickable(dismantle),
		"held actions may also be held on the card"
	)
	expect(prompt("Q", 0).KeyboardKeyCode == Interaction.NoKeyboard, "unknown shortcuts are ignored")
	-- Mouse/touch InputObjects carry KeyCode Unknown, so Unknown on either slot means "any click triggers me".
	local unknown = Roblox.Enum.KeyCode.Unknown
	for _, p in { seat, cargo, build, dismantle } do
		expect(p.KeyboardKeyCode ~= unknown and p.GamepadKeyCode ~= unknown, "no prompt may match a mouse click")
	end
	expect(Interaction.NoKeyboard ~= Interaction.NoGamepad and Interaction.NoKeyboard.EnumType == Roblox.Enum.KeyCode)
end)

local Cargo = Harness.require("Logistics/Cargo")

test("R6 hit zones and crouch use the real six-part rig", function()
	local BodyParts = Harness.require("BodyParts")
	local Animations = Harness.require("Animations")
	for name, part in
		{
			Head = "Head",
			Torso = "Torso",
			["Left Arm"] = "LeftArm",
			["Right Arm"] = "RightArm",
			["Left Leg"] = "LeftLeg",
			["Right Leg"] = "RightLeg",
		}
	do
		expect(BodyParts.fromInstanceName(name) == part)
	end
	local pose = Animations.movement(1, 0.5, true)
	expect(pose ~= nil and pose.Root ~= nil and pose.Root[1] > 0, "R6 bends at the root")
	expect(pose.RightHip ~= nil and pose.LeftHip ~= nil, "R6 hips")
	expect(pose.Waist == nil and pose.RightKnee == nil and pose.LeftKnee == nil, "no R15-only joints")
	expect(Animations.movement(0, 0, true) == nil, "standing has no override")
end)

test("cargo access requires a conscious living teammate within vehicle range", function()
	local good = { side = "A", vehicleSide = "A", alive = true, conscious = true, distance = 12, range = 19 }
	expect(Cargo.canAccess(good))
	for key, value in { side = "B", vehicleSide = "B", alive = false, conscious = false, distance = 20 } do
		local ctx = table.clone(good)
		ctx[key] = value
		expect(not Cargo.canAccess(ctx), key .. " should deny cargo access")
	end
	for _, distance in { -1, math.huge, 0 / 0 } do
		local ctx = table.clone(good)
		ctx.distance = distance
		expect(not Cargo.canAccess(ctx), "invalid distance")
	end
	local lobby = table.clone(good)
	lobby.side, lobby.vehicleSide = nil, nil
	expect(not Cargo.canAccess(lobby), "lobby is not a logistics side")
end)

test("cargo loading and returning to main keeps unlimited source stock unchanged", function()
	local state = { cargo = 200, capacity = 1000, stock = 0, stockCapacity = 3000, unlimited = true }
	local cargo, stock, moved, why = Cargo.move(state, true, 100)
	expect(cargo == 300 and stock == 0 and moved == 100 and why == nil)
	cargo, stock, moved = Cargo.move(state, true, "all")
	expect(cargo == 1000 and stock == 0 and moved == 800, "load only available space")
	cargo, stock, moved = Cargo.move(state, false, "all")
	expect(cargo == 0 and stock == 0 and moved == 200, "return cargo to main")
end)

test("cargo FOB transfers conserve supplies in both directions", function()
	local state = { cargo = 250, capacity = 1000, stock = 600, stockCapacity = 3000, unlimited = false }
	local cargo, stock, moved = Cargo.move(state, true, "all")
	expect(cargo == 850 and stock == 0 and moved == 600, "cannot load nonexistent supplies")
	state = { cargo = 1000, capacity = 1000, stock = 2750, stockCapacity = 3000, unlimited = false }
	cargo, stock, moved = Cargo.move(state, false, "all")
	expect(cargo == 750 and stock == 3000 and moved == 250, "cannot overflow a FOB")
	state.cargo, state.stock = cargo, stock
	cargo, stock, moved = Cargo.move(state, true, 100)
	expect(cargo == 850 and stock == 2900 and moved == 100, "reload a partial quantity")
	expect(cargo + stock == state.cargo + state.stock, "supplies conserved")
end)

test("cargo rejects noninteger, negative, infinite and malformed quantities without mutation", function()
	local state = { cargo = 250, capacity = 1000, stock = 600, stockCapacity = 3000, unlimited = false }
	for _, amount in { 0, -50, 1.5, math.huge, -math.huge, 0 / 0, "100", "", {}, true } do
		local cargo, stock, moved, why = Cargo.move(state, true, amount)
		expect(cargo == 250 and stock == 600 and moved == 0 and why ~= nil, "invalid quantity")
	end
	local cargo, stock, moved, why = Cargo.move(state, true, nil)
	expect(cargo == 250 and stock == 600 and moved == 0 and why ~= nil, "missing quantity")
end)

test("cargo empty and full destinations never duplicate or discard supplies", function()
	for _, loading in { true, false } do
		local state = {
			cargo = if loading then 1000 else 0,
			capacity = 1000,
			stock = 3000,
			stockCapacity = 3000,
			unlimited = false,
		}
		local cargo, stock, moved, why = Cargo.move(state, loading, "all")
		expect(cargo == state.cargo and stock == state.stock and moved == 0 and why ~= nil)
	end
	-- Repeated concurrent requests are serialized by the server; each uses the latest balances.
	local state = { cargo = 950, capacity = 1000, stock = 100, stockCapacity = 3000, unlimited = false }
	local cargo, stock, moved = Cargo.move(state, true, 100)
	expect(moved == 50)
	state.cargo, state.stock = cargo, stock
	cargo, stock, moved = Cargo.move(state, true, 100)
	expect(moved == 0 and cargo == 1000 and stock == 50)
end)

local function uiFixture()
	local game = ModuleHarness.node("DataModel")
	local workspace = ModuleHarness.node("Workspace")
	local services = {}
	for _, name in
		{
			"Players",
			"UserInputService",
			"RunService",
			"ContextActionService",
			"GuiService",
			"ReplicatedStorage",
			"TweenService",
			"CollectionService",
		}
	do
		services[name] = ModuleHarness.node(name)
	end
	game.GetService = function(_, name)
		return assert(services[name], name)
	end
	local player = ModuleHarness.node("Player")
	player.Character = ModuleHarness.node("Model")
	player.Character.Parent = workspace
	ModuleHarness.node("Humanoid").Parent = player.Character
	local root = ModuleHarness.node("Part")
	root.Name, root.Parent = "HumanoidRootPart", player.Character
	services.Players.LocalPlayer = player
	local input = services.UserInputService
	input.GetFocusedTextBox = function()
		return input.Focus
	end
	input.IsKeyDown = function()
		return false
	end
	input.GetMouseLocation = function()
		return input.MouseLocation or Roblox.Vector2.zero
	end
	local bindings = {}
	services.ContextActionService.BindActionAtPriority = function(_, name, fn)
		bindings[name] = fn
	end
	services.GuiService.MenuIsOpen = false
	local medical = {
		Gear = { Gear = "gear", Config = "gearConfig", Drag = "drag" },
		Remotes = "remotes",
		GameMode = { Config = "gameConfig" },
	}
	medical.WaitForChild = function(self, name)
		return self[name]
	end
	services.ReplicatedStorage.WaitForChild = function()
		return medical
	end
	services.ReplicatedStorage.Medical = medical
	local requests, gearState = {}, ModuleHarness.signal()
	local mods = {
		gear = Harness.require("Gear/Gear"),
		gearConfig = Harness.require("Gear/Config"),
		drag = Harness.require("Gear/Drag"),
		gameConfig = ModuleHarness.load("shared/Medical/GameMode/Config", {}),
		movement = {
			stamina = function()
				return 1, false
			end,
		},
		interactionInput = {},
		remotes = {
			get = function(name)
				return if name == "GearState"
					then { OnClientEvent = gearState }
					else {
						FireServer = function(_, ...)
							table.insert(requests, table.pack(...))
						end,
					}
			end,
		},
	}
	local env = {
		game = game,
		workspace = workspace,
		script = {
			Parent = {
				Ui = "ui",
				InventoryInput = "input",
				InventoryDrag = "inventoryDrag",
				InteractionInput = "interactionInput",
				Weapons = { Movement = "movement" },
			},
		},
		require = function(key)
			return assert(mods[key], tostring(key))
		end,
		task = {
			spawn = function() end,
			defer = function(fn, ...)
				fn(...)
			end,
		},
	}
	mods.ui = ModuleHarness.load("client/Ui", env)
	mods.input = ModuleHarness.load("client/InventoryInput", env)
	mods.inventoryDrag = ModuleHarness.load("client/InventoryDrag", env)
	local screen = ModuleHarness.node("ScreenGui")
	screen.Parent = game
	return {
		env = env,
		mods = mods,
		game = game,
		workspace = workspace,
		player = player,
		services = services,
		screen = screen,
		requests = requests,
		gearState = gearState,
		bindings = bindings,
		root = root,
	}
end

test("inventory initializes and I toggles once even when Roblox processes the key", function()
	local f = uiFixture()
	local inventory = ModuleHarness.load("client/InventoryUi", f.env)
	inventory.init(f.screen)
	local key = { KeyCode = Roblox.Enum.KeyCode.I }
	expect(
		f.bindings.HellboundInventory("HellboundInventory", Roblox.Enum.UserInputState.Begin, key)
			== Roblox.Enum.ContextActionResult.Sink
	)
	expect(not inventory.isOpen(), "CAS consumes camera zoom but doesn't toggle a second time")
	f.services.UserInputService.InputBegan:Fire(key, true)
	expect(inventory.isOpen(), "processed I still opens field inventory with no locker or source")
	expect(f.requests[1][1] == "open")
	f.gearState:Fire(Harness.require("Gear/Gear").new(), { kind = "ground", items = {} }, false)
	f.services.UserInputService.InputBegan:Fire(key, true)
	expect(not inventory.isOpen())
	f.services.UserInputService.Focus = {}
	f.services.UserInputService.InputBegan:Fire(key, false)
	expect(not inventory.isOpen(), "typing blocks inventory")
	f.services.UserInputService.Focus = nil
	f.services.GuiService.MenuIsOpen = true
	f.services.UserInputService.InputBegan:Fire(key, true)
	expect(not inventory.isOpen(), "Roblox menu blocks inventory")
	f.services.GuiService.MenuIsOpen = false
	f.player.Character:SetAttribute("MedConscious", false)
	f.services.UserInputService.InputBegan:Fire(key, true)
	expect(not inventory.isOpen(), "unconsciousness blocks opening")
end)

test("modal detection respects hidden ancestors and disabled screens", function()
	local f = uiFixture()
	local parent = ModuleHarness.node("Frame")
	parent.Parent, parent.Visible = f.screen, false
	local modal = ModuleHarness.node("Frame")
	modal.Parent = parent
	f.mods.ui.modal(modal)
	expect(not f.mods.ui.isModalOpen(), "hidden parent doesn't block inventory")
	parent.Visible = true
	expect(f.mods.ui.isModalOpen())
	f.screen.Enabled = false
	expect(not f.mods.ui.isModalOpen())
	f.screen.Enabled = true
	modal:Destroy()
	expect(not f.mods.ui.isModalOpen())
end)

test("map player bearing uses the model, independently of camera rotation", function()
	local f = uiFixture()
	local map = ModuleHarness.load("client/MapHud", f.env)
	f.workspace.CurrentCamera = { CFrame = Roblox.CFrame.Angles(0, math.pi, 0) }
	expect(math.abs(map.playerBearing()) < 0.001, "player faces north despite south-facing camera")
	f.root.CFrame = Roblox.CFrame.Angles(0, -math.pi / 2, 0)
	expect(math.abs(map.playerBearing() - 90) < 0.001, "player now faces east")
	f.workspace.CurrentCamera.CFrame = Roblox.CFrame.new()
	expect(math.abs(map.playerBearing() - 90) < 0.001, "camera movement doesn't move the arrow")
	f.player.Character = nil
	expect(map.playerBearing() == 0)
end)

test("held equipment synchronization preserves ownership and removes lost items", function()
	local f = uiFixture()
	local Gear = f.mods.gear
	local state = Gear.fromKit(f.mods.gearConfig.Kits.Rifleman, {})
	local tools = ModuleHarness.load("server/Gear/GearTools", f.env)
	local usable = true
	tools.init({
		get = function()
			return state
		end,
		canUse = function()
			return usable
		end,
	})
	local backpack = ModuleHarness.node("Backpack")
	backpack.Parent = f.player
	local hum = f.player.Character:FindFirstChildOfClass("Humanoid")
	hum.UnequipTools = function()
		for _, tool in f.player.Character:GetChildren() do
			if tool:IsA("Tool") then
				tool.Parent = backpack
				tool.Unequipped:Fire()
			end
		end
	end
	hum.EquipTool = function(_, tool)
		hum:UnequipTools()
		tool.Parent = f.player.Character
		tool.Equipped:Fire()
	end
	tools.sync(f.player, state)
	tools.sync(f.player, state)
	expect(#backpack:GetChildren() == 2, "one held proxy per owned equipment type")
	tools.equip(f.player, "Hammer")
	expect(
		tools.held(f.player, "Hammer") and Gear.count(state, "Hammer") == 1,
		"equipping never consumes or duplicates the item"
	)
	expect(f.player.Character:GetAttribute("GearHeldItem") == "Hammer")
	tools.equip(f.player, "Hammer")
	expect(not tools.held(f.player, "Hammer"), "selecting again holsters")
	usable = false
	hum:EquipTool(backpack:GetChildren()[1])
	expect(
		#backpack:GetChildren() == 2 and not tools.held(f.player, "Hammer"),
		"server rejects native equip while incapacitated"
	)
	usable = true
	Gear.remove(state, "Hammer", 1)
	tools.sync(f.player, state)
	expect(#backpack:GetChildren() == 1)
	tools.equip(f.player, "Hammer")
	expect(not tools.held(f.player, "Hammer"), "cannot grant missing equipment")
	tools.equip(f.player, "Radio")
	expect(tools.held(f.player, "Radio") and Gear.count(state, "Radio") == 1)
	Gear.remove(state, "Radio", 1)
	tools.sync(f.player, state)
	expect(
		#backpack:GetChildren() == 0 and not tools.held(f.player, "Radio"),
		"dropping last radio destroys held proxy"
	)
	expect(f.player.Character:GetAttribute("GearHeldItem") == nil)
end)

test("drag requests route stacks, equipment and matching worn slots without mutating state", function()
	local Gear, Drag = Harness.require("Gear/Gear"), Harness.require("Gear/Drag")
	local state = Gear.new()
	Gear.wear(state, "Uniform")
	Gear.wear(state, "AssaultPack")
	Gear.add(state, "Radio", 2, "uniform")
	local origin = { kind = "contents", id = "Radio", count = 2, container = "uniform" }
	local move = Drag.request(origin, { kind = "container", name = "backpack" }, state)
	expect(move[1] == "move" and move[3] == 2 and move[4] == "uniform" and move[5] == "backpack")
	expect(
		Gear.count(state, "Radio") == 2 and state.items.backpack.Radio == nil,
		"requests are not optimistic mutations"
	)
	Gear.move(state, move[2], move[3], move[4], move[5])
	expect(
		Gear.count(state, "Radio") == 2 and state.items.backpack.Radio == 2,
		"server-equivalent move conserves stacks"
	)
	expect(Drag.request(origin, { kind = "equip" }, state) == nil, "stale origin cannot equip absent items")
	origin.container = "backpack"
	expect(Drag.request(origin, { kind = "equip" }, state)[1] == "equip")
	expect(Drag.request(origin, { kind = "source" }, state)[1] == "drop")
	local source = { kind = "arsenal", items = { "M4A1", "FieldPack", "Radio" }, instance = "locker" }
	local external = { kind = "source", id = "FieldPack", count = 1, source = "locker" }
	expect(
		Drag.request(external, { kind = "container", name = "backpack" }, state, source)[1] == "take",
		"worn backpack can be replaced"
	)
	external.id = "M4A1"
	expect(Drag.request(external, { kind = "slot", name = "handgun" }, state, source) == nil)
	local take = Drag.request(external, { kind = "slot", name = "primary" }, state, source)
	expect(take[1] == "take" and take[5] == "locker", "source identity accompanies validated slot takes")
	external.id = "Radio"
	expect(Drag.request(external, { kind = "equip" }, state, source)[1] == "takeEquip")
	expect(Drag.request({ kind = "slot", id = "Uniform", slot = "uniform" }, { kind = "source" }, state)[1] == "unwear")
end)

test("drag controller highlights targets, sends once and cancels mouse/touch safely", function()
	local f = uiFixture()
	local Gear = f.mods.gear
	local state = Gear.new()
	Gear.wear(state, "Uniform")
	Gear.wear(state, "AssaultPack")
	Gear.add(state, "Radio", 2, "uniform")
	local renders = 0
	local drag = f.mods.inventoryDrag.new(f.screen, {
		isOpen = function()
			return true
		end,
		state = function()
			return state
		end,
		source = function()
			return { kind = "ground", items = {} }
		end,
		send = function(...)
			table.insert(f.requests, table.pack(...))
		end,
		render = function()
			renders += 1
		end,
	})
	local row = ModuleHarness.node("TextButton")
	row.Parent = f.screen
	drag:origin(row, function()
		return { kind = "contents", container = "uniform", id = "Radio", count = 2 }
	end)
	local target = ModuleHarness.node("Frame")
	target.Parent = f.screen
	target.AbsolutePosition, target.AbsoluteSize = Roblox.Vector2.new(100, 0), Roblox.Vector2.new(100, 100)
	drag:target(target, function()
		return { kind = "container", name = "backpack" }
	end)
	local input = f.services.UserInputService
	local mouse = { UserInputType = Roblox.Enum.UserInputType.MouseButton1 }
	input.MouseLocation = Roblox.Vector2.new(20, 20)
	row.InputBegan:Fire(mouse)
	expect(drag:busy() and drag:clicked(), "pending press still allows ordinary clicks")
	input.MouseLocation = Roblox.Vector2.new(120, 20)
	input.InputChanged:Fire({ UserInputType = Roblox.Enum.UserInputType.MouseMovement })
	expect(not drag:clicked() and target:FindFirstChild("DropTarget").Visible)
	input.InputEnded:Fire(mouse)
	expect(#f.requests == 1 and f.requests[1][1] == "move" and f.requests[1][3] == 2)
	expect(not drag:busy() and not drag:clicked(), "release suppresses the old row's Activated drop")
	expect(not target:FindFirstChild("DropTarget").Visible and renders == 1)
	expect(Gear.count(state, "Radio") == 2 and state.items.backpack.Radio == nil)
	input.InputEnded:Fire(mouse)
	expect(#f.requests == 1, "duplicate release cannot send twice")
	input.MouseLocation = Roblox.Vector2.new(20, 20)
	row.InputBegan:Fire(mouse)
	input.MouseLocation = Roblox.Vector2.new(500, 500)
	input.InputChanged:Fire({ UserInputType = Roblox.Enum.UserInputType.MouseMovement })
	input.InputEnded:Fire(mouse)
	expect(#f.requests == 1, "outside drop cancels")
	local touch = { UserInputType = Roblox.Enum.UserInputType.Touch, Position = Roblox.Vector3.new(20, 20, 0) }
	row.InputBegan:Fire(touch)
	touch.Position = Roblox.Vector3.new(120, 20, 0)
	input.InputChanged:Fire(touch)
	input.InputEnded:Fire(mouse)
	expect(drag:busy(), "mouse release cannot finish another finger's drag")
	input.InputEnded:Fire(touch)
	expect(#f.requests == 2 and not drag:busy())
	input.MouseLocation = Roblox.Vector2.new(20, 20)
	row.InputBegan:Fire(mouse)
	input.MouseLocation = Roblox.Vector2.new(120, 20)
	input.InputChanged:Fire({ UserInputType = Roblox.Enum.UserInputType.MouseMovement })
	input.WindowFocusReleased:Fire()
	input.InputEnded:Fire(mouse)
	expect(not drag:busy() and #f.requests == 2, "focus loss never transfers")
	row.InputBegan:Fire(mouse)
	input.InputBegan:Fire({ UserInputType = Roblox.Enum.UserInputType.MouseButton2 })
	input.InputEnded:Fire(mouse)
	expect(not drag:busy() and #f.requests == 2, "right click cancels without a bulk drop")
end)

test("inventory drag capacity clamps quantities without item loss", function()
	local Gear, Drag = Harness.require("Gear/Gear"), Harness.require("Gear/Drag")
	local state = Gear.new()
	Gear.wear(state, "Uniform")
	Gear.wear(state, "AssaultPack")
	Gear.add(state, "Hammer", 4, "uniform")
	Gear.add(state, "Hammer", 13, "backpack")
	local origin = { kind = "contents", id = "Hammer", container = "uniform", count = 4 }
	local request = Drag.request(origin, { kind = "container", name = "backpack" }, state)
	expect(request[3] == 1, "only remaining capacity is requested")
	Gear.move(state, request[2], request[3], request[4], request[5])
	expect(Gear.count(state, "Hammer") == 17 and state.items.uniform.Hammer == 3)
	expect(
		Drag.request(origin, { kind = "container", name = "backpack" }, state) == nil,
		"full destination rejects remainder"
	)
	expect(Gear.equipment(state).Hammer and not Gear.equipment(state).Radio, "equipment follows real ownership")
end)

test("invalid, full, stale and outside inventory drops are harmless", function()
	local Gear, Drag = Harness.require("Gear/Gear"), Harness.require("Gear/Drag")
	local state = Gear.new()
	Gear.wear(state, "Uniform")
	Gear.add(state, "Hammer", 1, "uniform")
	local origin = { kind = "contents", id = "Hammer", count = 1, container = "uniform" }
	expect(Drag.request(origin, nil, state) == nil)
	expect(Drag.request(origin, { kind = "container", name = "vest" }, state) == nil)
	expect(Drag.request(origin, { kind = "container", name = "uniform" }, state) == nil)
	for _, count in { 0, -1, math.huge, 0 / 0, 0.5, "1" } do
		origin.count = count
		expect(Drag.request(origin, { kind = "source" }, state) == nil)
	end
	local source = { kind = "ground", items = { Hammer = 1 }, instance = "newPile" }
	expect(
		Drag.request(
			{ kind = "source", id = "Hammer", count = 1, source = "oldPile" },
			{ kind = "container", name = "uniform" },
			state,
			source
		) == nil
	)
	expect(Drag.request({ kind = "slot", id = "PlateCarrier", slot = "vest" }, { kind = "source" }, state) == nil)
	expect(Gear.count(state, "Hammer") == 1, "invalid drops do not discard or duplicate gear")
	expect(not Drag.started({ X = 0, Y = 0 }, { X = 3, Y = 3 }), "click isn't a drag")
	expect(Drag.started({ X = 0, Y = 0 }, { X = 8, Y = 0 }))
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	local process = require("@lune/process")
	process.exit(1)
end
