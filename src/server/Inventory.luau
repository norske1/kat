--!strict
-- Per-player medical item inventory.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Config)
local Items = require(Medical.Items)
local Remotes = require(Medical.Remotes)

local Inventory = {}

local inventories: { [Player]: { [string]: number } } = {}
local inventoryRemote = Remotes.get("Inventory")

Inventory.levelOf = function(_player: Player): number
	return 0
end
Inventory.debugAllowed = function(_player: Player): boolean
	return false
end

function Inventory.get(player: Player): { [string]: number }
	local inv = inventories[player]
	if not inv then
		inv = {}
		inventories[player] = inv
	end
	return inv
end

function Inventory.has(player: Player, itemId: string): boolean
	if Config.InfiniteSupplies then
		return true
	end
	return (Inventory.get(player)[itemId] or 0) > 0
end

function Inventory.take(player: Player, itemId: string): boolean
	if Config.InfiniteSupplies then
		return true
	end
	local def = Items[itemId]
	if def and def.reusable then
		return Inventory.has(player, itemId)
	end
	local inv = Inventory.get(player)
	local n = inv[itemId] or 0
	if n <= 0 then
		return false
	end
	inv[itemId] = if n > 1 then n - 1 else nil :: any
	Inventory.sync(player)
	return true
end

function Inventory.give(player: Player, itemId: string, count: number?)
	if not Items[itemId] then
		warn("[Medical] unknown item " .. itemId)
		return
	end
	local inv = Inventory.get(player)
	inv[itemId] = (inv[itemId] or 0) + (count or 1)
	Inventory.sync(player)
end

-- Tops the inventory up to the loadout for the player's medical level.
function Inventory.restock(player: Player, level: number)
	local loadout = Config.Loadouts[level] or Config.Loadouts[0]
	local inv = Inventory.get(player)
	for itemId, count in loadout do
		if (inv[itemId] or 0) < count then
			inv[itemId] = count
		end
	end
	Inventory.sync(player)
end

function Inventory.clear(player: Player)
	inventories[player] = {}
	Inventory.sync(player)
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

function Inventory.remove(player: Player)
	inventories[player] = nil
end

return Inventory
