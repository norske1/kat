--!strict
-- Per-player medical items. They live in the player's gear (Gear/GearService), so they take up room and
-- weigh something; this module is the medical system's view of them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Config)
local Items = require(Medical.Items)
local Gear = require(Medical.Gear.Gear)
local Remotes = require(Medical.Remotes)
local GearService = require(script.Parent.Gear.GearService)

local Inventory = {}

local inventoryRemote = Remotes.get("Inventory")

Inventory.levelOf = function(_player: Player): number
	return 0
end
Inventory.debugAllowed = function(_player: Player): boolean
	return false
end

-- Medical item counts across all containers.
function Inventory.get(player: Player): { [string]: number }
	local state = GearService.get(player)
	local out = {}
	for _, c in Gear.CONTAINERS do
		for id, n in state.items[c] do
			if Items[id] then
				out[id] = (out[id] or 0) + n
			end
		end
	end
	return out
end

function Inventory.has(player: Player, itemId: string): boolean
	if Config.InfiniteSupplies then
		return true
	end
	return Gear.count(GearService.get(player), itemId) > 0
end

function Inventory.take(player: Player, itemId: string): boolean
	if Config.InfiniteSupplies then
		return true
	end
	local def = Items[itemId]
	if def and def.reusable then
		return Inventory.has(player, itemId)
	end
	return GearService.removeItem(player, itemId, 1) == 1
end

-- Adds items as far as they fit. Returns how many were added.
function Inventory.give(player: Player, itemId: string, count: number?): number
	if not Items[itemId] then
		warn("[Medical] unknown item " .. itemId)
		return 0
	end
	return GearService.addItem(player, itemId, count or 1)
end

-- Tops the medical items up to the loadout for the player's medical level, as far as they fit.
function Inventory.restock(player: Player, level: number)
	local loadout = Config.Loadouts[level] or Config.Loadouts[0]
	local state = GearService.get(player)
	for itemId, count in loadout do
		local need = count - Gear.count(state, itemId)
		if need > 0 then
			Gear.add(state, itemId, need)
		end
	end
	GearService.changed(player)
end

function Inventory.clear(player: Player)
	local state = GearService.get(player)
	for _, c in Gear.CONTAINERS do
		for id in state.items[c] do
			if Items[id] then
				state.items[c][id] = nil
			end
		end
	end
	GearService.changed(player)
end

-- New character: class kit plus medical loadout (deferred so the Class attribute and Backpack are fresh).
function Inventory.spawn(player: Player)
	task.defer(GearService.spawn, player)
end

function Inventory.sync(player: Player)
	if player.Parent then
		inventoryRemote:FireClient(
			player,
			Inventory.get(player),
			Inventory.levelOf(player),
			Inventory.debugAllowed(player),
			Config.InfiniteSupplies
		)
	end
end

function Inventory.remove(_player: Player) end

GearService.onChanged(Inventory.sync)

return Inventory
