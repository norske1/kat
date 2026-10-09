--!strict
-- Placement rules and supply maths for base building (pure, no Roblox services).
local Logistics = {}

Logistics.LEADERS = { ["Squad Commander"] = true, Commander = true }

export type PlaceContext = {
	class: string,
	distance: number, -- from the player to the spot
	fob: { stock: number, habs: number }?, -- the friendly FOB whose radius contains the spot
	mainDistance: number, -- to the nearest main base
	fobDistance: number, -- to the nearest FOB of either side
	blocked: boolean, -- overlaps another structure
}

function Logistics.canPlace(kind: string, def: { cost: number }, ctx: PlaceContext, cfg): (boolean, string?)
	if not Logistics.LEADERS[ctx.class] then
		return false, "Only Squad Commanders and the Commander can place structures"
	elseif ctx.distance > cfg.PlaceRange then
		return false, "Too far away"
	elseif ctx.blocked then
		return false, "Something is in the way"
	end
	if kind == "FOB" then
		if ctx.mainDistance < cfg.FobMinFromMain then
			return false, "Too close to a main base"
		elseif ctx.fobDistance < cfg.FobSpacing then
			return false, "Too close to another FOB"
		end
		return true, nil
	end
	local fob = ctx.fob
	if not fob then
		return false, "Must be inside a friendly FOB's radius"
	elseif fob.stock < def.cost then
		return false, string.format("The FOB needs %d supplies (has %d)", def.cost, fob.stock)
	elseif kind == "HAB" and fob.habs > 0 then
		return false, "This FOB already has a HAB"
	end
	return true, nil
end

-- How much moves from `from` into a container holding `to` with capacity `cap`.
function Logistics.transfer(from: number, to: number, cap: number): number
	return math.max(0, math.min(from, cap - to))
end

return Logistics
