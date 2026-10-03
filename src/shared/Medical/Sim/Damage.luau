--!nonstrict
-- Converts incoming damage into wounds, fractures and thoracic injuries.
local Medical = script.Parent.Parent
local Config = require(Medical.Config)
local Wounds = require(Medical.Wounds)
local BodyParts = require(Medical.BodyParts)
local Patient = require(script.Parent.Patient)
local Circulation = require(script.Parent.Circulation)

local Damage = {}

local function sizeFor(amount: number): number
	if amount < Config.DamageSmall then
		return 1
	elseif amount < Config.DamageMedium then
		return 2
	end
	return 3
end

local function thoraxInjury(p, amount: number, damageType: string)
	if not Config.PneumothoraxEnabled then
		return
	end
	if damageType == "Blunt" or damageType == "Fall" then
		amount *= 0.5
	end
	if amount < Config.PneumothoraxDamageThreshold then
		return
	end
	local rng = p.rng
	local b = p.breathing
	local bonus =
		math.clamp((amount - Config.PneumothoraxDamageThreshold) / (Config.PneumothoraxDamageThreshold * 2), 0, 1)
	local chance = Config.PneumothoraxChance + Config.PneumothoraxDamageBonus * bonus
	if rng:chance(chance) then
		if b.ptx > 0 and rng:chance(Config.AdvancedPneumothoraxChance) then
			if rng:chance(0.5) then
				b.tension = true
			else
				b.hemo = true
			end
		else
			b.ptx = math.clamp(b.ptx + 1, 1, 4)
		end
		b.chestSeal = false
		Patient.event(p, "Pneumothorax")
	elseif damageType == "Bullet" or damageType == "Stab" or damageType == "Explosive" then
		if rng:chance(Config.DeepPenetratingInjuryChance) then
			b.dpi = true
			b.chestSeal = false
			if rng:chance(Config.TamponadeChance) and b.tamponade <= 0 then
				b.tamponade = 0.05
			end
		end
	end
end

-- Applies `amount` Roblox damage to a medical body part. Returns the wound created.
function Damage.apply(p, partName: string, amount: number, damageTypeIn: string?)
	if not p.alive or amount <= 0 then
		return nil
	end
	local damageType: string = if damageTypeIn and Wounds.DamageTypes[damageTypeIn] then damageTypeIn else "Generic"
	if not BodyParts.isValid(partName) then
		partName = p.rng:pickWeighted(BodyParts.HitWeights)
	end
	local rng = p.rng
	local part = p.parts[partName]
	local woundType = rng:pickWeighted(Wounds.DamageTypes[damageType])
	local size = sizeFor(amount)
	local wound = { type = woundType, size = size, amount = 1, clot = 0 }
	Circulation.addWound(part.wounds, wound)

	local woundPain = Wounds.Types[woundType].pain[size]
	p.painBurst = math.min(1, p.painBurst + woundPain * 0.5)

	-- fractures on limbs (and occasional torso/head skeletal trauma is ignored)
	if BodyParts.isLimb(partName) and part.fracture == 0 and Wounds.Types[woundType].causesFracture then
		local fractureChance = (Config.FractureChance[damageType] or 10) * math.clamp(amount / 30, 0.3, 2)
		if rng:chance(math.min(95, fractureChance)) then
			local kind = 1
			if rng:chance(Config.ComminutedFractureChance * math.clamp(amount / 40, 0.5, 2)) then
				kind = 3
			elseif rng:chance(Config.CompoundFractureChance) then
				kind = 2
			end
			part.fracture = kind
			part.fractureKnown = false
			part.splint = false
			p.painBurst = math.min(1, p.painBurst + 0.2)
			Patient.event(p, "Fracture", partName)
		end
	end

	if partName == "Torso" then
		thoraxInjury(p, amount, damageType)
	end

	if partName == "Head" and Config.HeadshotKillDamage > 0 and amount >= Config.HeadshotKillDamage then
		Patient.kill(p, "Head trauma")
		return wound
	end

	-- unconsciousness from trauma / pain
	local knockChance = 0
	if p.painPerceived + woundPain * 0.5 > Config.PainUnconsciousThreshold then
		knockChance = Config.PainUnconsciousChance
	end
	if partName == "Head" then
		knockChance *= Config.HeadHitUnconsciousMultiplier
		if amount >= Config.KnockoutDamage * 0.5 then
			knockChance = math.max(knockChance, 0.5)
		end
	end
	if amount >= Config.KnockoutDamage or rng:chance(knockChance) then
		if p.conscious then
			Patient.log(p, "Knocked unconscious")
		end
		p.knockedOut = true
	end

	Patient.event(p, "Wounded", { part = partName, type = woundType, size = size })
	return wound
end

-- Distributes damage across random body parts (explosions, falls without hit info).
function Damage.applySpread(p, amount: number, damageType: string?)
	local hits = if amount > 40 then 3 elseif amount > 20 then 2 else 1
	if damageType == "Fall" then
		for _, leg in { "LeftLeg", "RightLeg" } do
			Damage.apply(p, leg, amount / 2, damageType)
		end
		return
	end
	for _ = 1, hits do
		Damage.apply(p, p.rng:pickWeighted(BodyParts.HitWeights), amount / hits, damageType)
	end
end

return Damage
