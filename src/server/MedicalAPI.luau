--!nonstrict
-- Public server API for weapon systems, admin tools and game logic.
--
--   local MedicalAPI = require(game.ServerScriptService.MedicalServer.MedicalAPI)
--   MedicalAPI.damage(character, "LeftLeg", 35, "Bullet")   -- precise hit (part name or R15/R6 limb name)
--   MedicalAPI.damage(character, nil, 60, "Explosive")      -- spread over random body parts
--
-- Alternatively set Humanoid attributes before calling Humanoid:TakeDamage():
--   humanoid:SetAttribute("MedicalHitPart", hit.Name); humanoid:SetAttribute("MedicalDamageType", "Bullet")
local MedicalService = require(script.Parent.MedicalService)
local Inventory = require(script.Parent.Inventory)
local Ragdoll = require(script.Parent.Ragdoll)

local MedicalAPI = {}

MedicalAPI.DamageTypes = { "Bullet", "Explosive", "Blunt", "Fall", "Melee", "Stab", "Generic" }

function MedicalAPI.damage(character: Model, bodyPart: string?, amount: number, damageType: string?)
	MedicalService.applyDamage(character, bodyPart, amount, damageType)
end

-- Returns the raw simulation state table (read-only by convention).
function MedicalAPI.getState(character: Model)
	local record = MedicalService.get(character)
	return record and record.state
end

function MedicalAPI.isConscious(character: Model): boolean
	local record = MedicalService.get(character)
	return record ~= nil and record.state.conscious
end

function MedicalAPI.isAlive(character: Model): boolean
	local record = MedicalService.get(character)
	return record ~= nil and record.state.alive
end

function MedicalAPI.fullHeal(character: Model)
	MedicalService.heal(character)
end

function MedicalAPI.setMedicalLevel(player: Player, level: number)
	player:SetAttribute("MedicalLevel", math.clamp(level, 0, 2))
	Inventory.sync(player)
end

function MedicalAPI.giveItem(player: Player, itemId: string, count: number?)
	Inventory.give(player, itemId, count)
end

function MedicalAPI.restock(player: Player)
	Inventory.restock(player, MedicalService.medicLevel(player))
end

-- Register a non-player humanoid (NPCs, training dummies) with the medical system.
function MedicalAPI.registerNPC(model: Model, bloodType: string?)
	return MedicalService.register(model, nil, { bloodType = bloodType }) ~= nil
end

function MedicalAPI.setRagdoll(character: Model, enabled: boolean)
	Ragdoll.set(character, enabled)
end

return MedicalAPI
