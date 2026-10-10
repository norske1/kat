--!nonstrict
local Gear = require(script.Parent.Parent.Gear.Gear)
local Hotbar = {}
Hotbar.Keys = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
local weaponSlots = { primary = 1, handgun = 2, launcher = 3 }
local equipmentSlots = { Hammer = 4, Radio = 5 }

function Hotbar.layout(entries)
	local sorted = table.clone(entries)
	table.sort(sorted, function(a, b)
		return (a.weaponId or "") .. ":" .. a.name < (b.weaponId or "") .. ":" .. b.name
	end)
	local slots, extra = {}, {}
	for _, entry in sorted do
		local def = entry.weaponId and Gear.def(entry.weaponId)
		local slot = (def and weaponSlots[def.slot]) or (entry.itemId and equipmentSlots[entry.itemId])
		if slot and not slots[slot] then
			slots[slot] = entry
		else
			table.insert(extra, entry)
		end
	end
	for i, entry in extra do
		if i + 5 <= #Hotbar.Keys then
			slots[i + 5] = entry
		end
	end
	return slots
end

return Hotbar
