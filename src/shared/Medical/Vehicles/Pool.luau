--!strict
-- Vehicle caps and cooldowns for one side (pure rules). Each vehicle type has `cap` slots; spawning takes a free
-- slot whose timer has run out and restarts it, so a slot is ready `cooldown` seconds after its last spawn.
local Pool = {}

type Slot = { vehicle: number?, readyAt: number }
export type Pool = { [string]: { Slot } }

function Pool.new(types: { [string]: any }): Pool
	local pool = {}
	for id, def in types do
		local slots = {}
		for i = 1, def.cap do
			slots[i] = { vehicle = nil, readyAt = 0 }
		end
		pool[id] = slots
	end
	return pool
end

-- alive, ready-to-spawn count, seconds until the next free slot is ready (nil if none is free or one is ready)
function Pool.status(pool: Pool, id: string, now: number): (number, number, number?)
	local alive, ready, wait = 0, 0, nil :: number?
	for _, slot in pool[id] or {} :: { Slot } do
		if slot.vehicle then
			alive += 1
		elseif slot.readyAt <= now then
			ready += 1
		else
			local left = slot.readyAt - now
			wait = if wait then math.min(wait, left) else left
		end
	end
	return alive, ready, if ready > 0 then nil else wait
end

function Pool.claim(pool: Pool, id: string, vehicle: number, now: number, cooldown: number): (boolean, string?)
	local slots = pool[id]
	if not slots then
		return false, "Unknown vehicle"
	end
	for _, slot in slots do
		if not slot.vehicle and slot.readyAt <= now then
			slot.vehicle = vehicle
			slot.readyAt = now + cooldown
			return true, nil
		end
	end
	local alive, _, wait = Pool.status(pool, id, now)
	if alive >= #slots then
		return false, "All " .. #slots .. " are deployed"
	end
	return false, string.format("Next one ready in %d:%02d", (wait or 0) // 60, math.ceil(wait or 0) % 60)
end

function Pool.release(pool: Pool, id: string, vehicle: number)
	for _, slot in pool[id] or {} :: { Slot } do
		if slot.vehicle == vehicle then
			slot.vehicle = nil
		end
	end
end

function Pool.reset(pool: Pool)
	for _, slots in pool do
		for _, slot in slots do
			slot.vehicle = nil
			slot.readyAt = 0
		end
	end
end

return Pool
