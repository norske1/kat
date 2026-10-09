--!strict
-- Ping visibility and limits (pure rules). The Commander's pings reach the whole side, a Squad Commander's
-- reach every squad on the side, and a squad member's only reach their own squad.
local Pings = {}

export type Ping = {
	id: number,
	uid: number,
	side: string,
	squad: number,
	class: string,
	scope: string, -- "all" | "squads" | "squad" | "self"
	expires: number,
	[string]: any,
}
export type Viewer = { uid: number, side: string?, squad: number, class: string }

function Pings.scope(class: string, squad: number): string
	if class == "Commander" then
		return "all"
	elseif class == "Squad Commander" then
		return "squads"
	elseif squad ~= 0 then
		return "squad"
	end
	return "self"
end

function Pings.visible(ping: Ping, v: Viewer): boolean
	if v.side ~= ping.side then
		return false
	end
	if v.uid == ping.uid or ping.scope == "all" then
		return true
	elseif ping.scope == "squads" then
		return v.squad ~= 0 or v.class == "Commander"
	elseif ping.scope == "squad" then
		return ping.squad ~= 0 and v.squad == ping.squad
	end
	return false
end

function Pings.limit(class: string, limits: { [string]: number }): number
	return limits[class] or limits.default or 2
end

-- Drops expired pings. Returns true if any were removed.
function Pings.prune(list: { Ping }, now: number): boolean
	local removed = false
	for i = #list, 1, -1 do
		if list[i].expires <= now then
			table.remove(list, i)
			removed = true
		end
	end
	return removed
end

-- Adds a ping, removing the author's oldest ones past their limit.
function Pings.add(list: { Ping }, ping: Ping, now: number, limits: { [string]: number })
	Pings.prune(list, now)
	local limit = Pings.limit(ping.class, limits)
	local mine = 0
	for _, p in list do
		if p.uid == ping.uid then
			mine += 1
		end
	end
	local i = 1
	while mine >= limit and i <= #list do
		if list[i].uid == ping.uid then
			table.remove(list, i)
			mine -= 1
		else
			i += 1
		end
	end
	table.insert(list, ping)
end

function Pings.clear(list: { Ping }, uid: number): boolean
	local removed = false
	for i = #list, 1, -1 do
		if list[i].uid == uid then
			table.remove(list, i)
			removed = true
		end
	end
	return removed
end

return Pings
