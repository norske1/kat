-- Usage: lune run tests/run.luau
local Harness = require("./harness")

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

test("game mode: team gap limit", function()
	local Rules = Harness.require("GameMode/Rules")
	expect(not Rules.canJoin(8, 5, 3), "5 vs 8: can't join the team with 8")
	expect(Rules.canJoin(5, 8, 3), "5 vs 8: can join the team with 5")
	expect(Rules.canJoin(7, 5, 3), "7 vs 5: joining makes 8 vs 5, gap 3 is allowed")
	expect(Rules.canJoin(0, 0, 3) and Rules.canJoin(2, 0, 3) and not Rules.canJoin(3, 0, 3), "small teams")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	local process = require("@lune/process")
	process.exit(1)
end
