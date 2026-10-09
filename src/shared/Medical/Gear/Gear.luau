--!nonstrict
-- Pure inventory logic (no Roblox services): worn slots, container contents, weight and movement.
local GearConfig = require(script.Parent.Config)
local Items = require(script.Parent.Parent.Items)

local Gear = {}

Gear.WEAPON_SLOTS = { "primary", "handgun", "launcher" }
Gear.CONTAINERS = { "uniform", "vest", "backpack" }
Gear.SLOTS = { "primary", "handgun", "launcher", "uniform", "vest", "backpack" }

export type State = {
	slots: { [string]: string },
	items: { [string]: { [string]: number } },
}

local defCache = {}

-- Definition for any item id: gear items from GearConfig, medical items from Items.
function Gear.def(id: string)
	if typeof(id) ~= "string" then
		return nil
	end
	local cached = defCache[id]
	if cached then
		return cached
	end
	local def = GearConfig.Items[id]
	if not def then
		local med = Items[id]
		if not med then
			return nil
		end
		local mass = GearConfig.MedicalMassOverride[id]
		if not mass and med.category == "Fluids" then
			local volume = tonumber(string.match(id, "(%d+)$"))
			mass = if volume then volume / 1000 else 0.5
		end
		def = {
			name = med.name,
			kind = "medical",
			mass = mass or GearConfig.MedicalMass[med.category] or 0.1,
			arsenal = true,
			category = med.category,
		}
	end
	defCache[id] = def
	return def
end

function Gear.new(): State
	return { slots = {}, items = { uniform = {}, vest = {}, backpack = {} } }
end

local function isContainer(c: string): boolean
	return c == "uniform" or c == "vest" or c == "backpack"
end
Gear.isContainer = isContainer

function Gear.capacity(state: State, c: string): number
	local id = state.slots[c]
	local def = id and Gear.def(id)
	return if def and def.capacity then def.capacity else 0
end

function Gear.load(state: State, c: string): number
	local total = 0
	local bag = state.items[c]
	if bag then
		for id, n in bag do
			local def = Gear.def(id)
			total += (if def then def.mass else 0) * n
		end
	end
	return total
end

function Gear.mass(state: State): number
	local total = 0
	for _, slot in Gear.SLOTS do
		local def = state.slots[slot] and Gear.def(state.slots[slot])
		if def then
			total += def.mass
		end
	end
	for _, c in Gear.CONTAINERS do
		total += Gear.load(state, c)
	end
	return total
end

function Gear.count(state: State, id: string): number
	local n = 0
	for _, c in Gear.CONTAINERS do
		n += state.items[c][id] or 0
	end
	return n
end

-- How many of `id` still fit in container `c`.
function Gear.room(state: State, c: string, id: string): number
	local def = Gear.def(id)
	if not def or def.kind == "container" or def.kind == "weapon" or not state.slots[c] then
		return 0
	end
	if def.mass <= 0 then
		return math.huge
	end
	local free = Gear.capacity(state, c) - Gear.load(state, c)
	return math.max(0, math.floor(free / def.mass + 1e-6))
end

-- Adds up to n items into `c` (or uniform -> vest -> backpack). Returns how many were added.
function Gear.add(state: State, id: string, n: number, c: string?): number
	local added = 0
	for _, container in (if c then { c } else Gear.CONTAINERS) do
		if added >= n then
			break
		end
		local take = math.min(n - added, Gear.room(state, container, id))
		if take > 0 then
			local bag = state.items[container]
			bag[id] = (bag[id] or 0) + take
			added += take
		end
	end
	return added
end

-- Removes up to n items from `c` (or uniform -> vest -> backpack). Returns how many were removed.
function Gear.remove(state: State, id: string, n: number, c: string?): number
	local removed = 0
	for _, container in (if c then { c } else Gear.CONTAINERS) do
		if removed >= n then
			break
		end
		local bag = state.items[container]
		local have = bag and bag[id] or 0
		local take = math.min(n - removed, have)
		if take > 0 then
			bag[id] = if have - take > 0 then have - take else nil
			removed += take
		end
	end
	return removed
end

-- Moves up to n items between own containers. Returns how many moved.
function Gear.move(state: State, id: string, n: number, from: string, to: string): number
	if from == to or not isContainer(from) or not isContainer(to) then
		return 0
	end
	local amount = math.min(n, state.items[from][id] or 0, Gear.room(state, to, id))
	if amount <= 0 then
		return 0
	end
	Gear.remove(state, id, amount, from)
	Gear.add(state, id, amount, to)
	return amount
end

-- Puts on a weapon or container. Returns the item that was in the slot and, for containers, the
-- items that no longer fit (the rest move into the new container).
function Gear.wear(state: State, id: string): (boolean, string?, { [string]: number }?)
	local def = Gear.def(id)
	if not def or not def.slot then
		return false, nil, nil
	end
	local slot = def.slot
	local old = state.slots[slot]
	state.slots[slot] = id
	if not isContainer(slot) then
		return true, old, nil
	end
	local contents = state.items[slot]
	state.items[slot] = {}
	local overflow = {}
	for itemId, count in contents do
		local fit = Gear.add(state, itemId, count, slot)
		if fit < count then
			overflow[itemId] = count - fit
		end
	end
	return true, old, overflow
end

-- Takes off whatever is in `slot`. Returns the item and the container's contents.
function Gear.unwear(state: State, slot: string): (string?, { [string]: number }?)
	local id = state.slots[slot]
	if not id then
		return nil, nil
	end
	state.slots[slot] = nil
	if isContainer(slot) then
		local contents = state.items[slot]
		state.items[slot] = {}
		return id, contents
	end
	return id, nil
end

-- Walk speed multiplier for a carried mass.
function Gear.speed(mass: number): number
	local cfg = GearConfig
	if mass <= cfg.FreeMass then
		return 1
	end
	local t = math.clamp((mass - cfg.FreeMass) / (cfg.MaxMass - cfg.FreeMass), 0, 1)
	return 1 + (cfg.MinSpeed - 1) * t
end

function Gear.canSprint(mass: number): boolean
	return mass <= GearConfig.NoSprintMass
end

-- Seconds of continuous sprint from full stamina at this mass.
function Gear.sprintSeconds(mass: number): number
	local cfg = GearConfig
	local t = math.clamp((mass - cfg.FreeMass) / math.max(cfg.NoSprintMass - cfg.FreeMass, 1), 0, 1)
	return cfg.SprintSecondsLight + (cfg.SprintSecondsHeavy - cfg.SprintSecondsLight) * t
end

-- Builds a kit. `medical` is an optional { [itemId]: count } added after the kit items.
function Gear.fromKit(kit, medical: { [string]: number }?): (State, { [string]: number })
	local state = Gear.new()
	local missing = {}
	if kit then
		for _, slot in { "uniform", "vest", "backpack", "primary", "handgun" } do
			if kit[slot] then
				Gear.wear(state, kit[slot])
			end
		end
		for _, entry in kit.items or {} do
			local id, n = entry[1], entry[2]
			local added = Gear.add(state, id, n)
			if added < n then
				missing[id] = n - added
			end
		end
	end
	if medical then
		local ids = {}
		for id in medical do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			local n = medical[id]
			local added = Gear.add(state, id, n)
			if added < n then
				missing[id] = n - added
			end
		end
	end
	return state, missing
end

-- Plain copy safe to send over a remote.
function Gear.snapshot(state: State)
	local items = {}
	for _, c in Gear.CONTAINERS do
		items[c] = table.clone(state.items[c])
	end
	return { slots = table.clone(state.slots), items = items, mass = Gear.mass(state) }
end

return Gear
