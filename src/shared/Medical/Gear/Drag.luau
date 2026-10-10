--!nonstrict
local Gear = require(script.Parent.Gear)
local Drag = {}

function Drag.started(start, point): boolean
	return (point.X - start.X) ^ 2 + (point.Y - start.Y) ^ 2 >= 64
end

function Drag.request(origin, target, state, source)
	if not origin or not target or not state then
		return nil
	end
	local def = Gear.def(origin.id)
	if not def then
		return nil
	end
	if origin.kind == "slot" then
		return if target.kind == "source" and state.slots[origin.slot] == origin.id
			then table.pack("unwear", origin.slot)
			else nil
	end
	local n = origin.count
	if typeof(n) ~= "number" or n ~= n or n == math.huge or n <= 0 or n % 1 ~= 0 then
		return nil
	end
	if origin.kind == "contents" then
		local bag = state.items[origin.container]
		n = math.min(n, bag and bag[origin.id] or 0)
		if n <= 0 then
			return nil
		end
		if target.kind == "source" then
			return table.pack("drop", origin.id, n, origin.container)
		elseif target.kind == "equip" and def.equipable then
			return table.pack("equip", origin.id)
		elseif target.kind == "container" and target.name ~= origin.container then
			n = math.min(n, Gear.room(state, target.name, origin.id))
			return if n > 0 then table.pack("move", origin.id, n, origin.container, target.name) else nil
		end
	elseif origin.kind == "source" then
		if not source or not origin.source or origin.source ~= source.instance then
			return nil
		end
		if source.kind == "arsenal" then
			if not table.find(source.items, origin.id) then
				return nil
			end
		else
			n = math.min(n, source.items[origin.id] or 0)
		end
		if n <= 0 then
			return nil
		end
		if def.slot then
			return if (target.kind == "slot" or target.kind == "container") and target.name == def.slot
				then table.pack("take", origin.id, 1, nil, origin.source)
				else nil
		elseif target.kind == "container" then
			n = math.min(n, Gear.room(state, target.name, origin.id))
			return if n > 0 then table.pack("take", origin.id, n, target.name, origin.source) else nil
		elseif target.kind == "equip" and def.equipable then
			local room = 0
			for _, c in Gear.CONTAINERS do
				room += Gear.room(state, c, origin.id)
			end
			return if room > 0 then table.pack("takeEquip", origin.id, 1, nil, origin.source) else nil
		end
	end
	return nil
end

return Drag
