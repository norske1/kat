--!strict
-- Donor compatibility table from the KAT official guide.
local BloodTypes = {}

local compatible: { [string]: { [string]: boolean } } = {
	["AB+"] = {
		["O-"] = true,
		["O+"] = true,
		["B-"] = true,
		["B+"] = true,
		["A-"] = true,
		["A+"] = true,
		["AB-"] = true,
		["AB+"] = true,
	},
	["AB-"] = { ["O-"] = true, ["B-"] = true, ["A-"] = true, ["AB-"] = true },
	["A+"] = { ["O-"] = true, ["O+"] = true, ["A-"] = true, ["A+"] = true },
	["A-"] = { ["O-"] = true, ["A-"] = true },
	["B+"] = { ["O-"] = true, ["O+"] = true, ["B-"] = true, ["B+"] = true },
	["B-"] = { ["O-"] = true, ["B-"] = true },
	["O+"] = { ["O-"] = true, ["O+"] = true },
	["O-"] = { ["O-"] = true },
}

function BloodTypes.isCompatible(recipient: string, donor: string): boolean
	local row = compatible[recipient]
	return row ~= nil and row[donor] == true
end

-- Item-safe identifier for a blood type ("O-" -> "O_neg").
function BloodTypes.toKey(bloodType: string): string
	return (bloodType:gsub("%+", "_pos"):gsub("%-", "_neg"))
end

function BloodTypes.fromKey(key: string): string
	return (key:gsub("_pos", "+"):gsub("_neg", "-"))
end

return BloodTypes
