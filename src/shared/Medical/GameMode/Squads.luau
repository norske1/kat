--!nonstrict
-- Squads and classes (pure, tested under Lune; the server's SquadService owns the live state).
-- Players are identified by UserId. A player is in at most one squad, or is their side's Commander, or neither
-- (then they're a Rifleman). The squad's creator leads it as Squad Commander; if they leave, the longest-serving
-- member takes over. Squad classes are capped per squad (GameConfig.Classes), the Commander is capped per side.
local Squads = {}

export type ClassDef = { name: string, cap: number?, perSide: boolean?, leader: boolean?, description: string? }
export type Squad = {
	id: number,
	side: string,
	number: number,
	leader: number,
	public: boolean,
	members: { number }, -- join order
	classes: { [number]: string },
}
export type State = {
	squads: { [number]: Squad },
	nextId: number,
	memberOf: { [number]: number },
	commanders: { [string]: number },
	config: { SquadSize: number, DefaultClass: string, Classes: { ClassDef } },
}

function Squads.new(config): State
	return { squads = {}, nextId = 1, memberOf = {}, commanders = {}, config = config }
end

function Squads.classDef(state: State, name: string): ClassDef?
	for _, def in state.config.Classes do
		if def.name == name then
			return def
		end
	end
	return nil
end

local function leaderClass(state: State): string
	for _, def in state.config.Classes do
		if def.leader then
			return def.name
		end
	end
	return state.config.DefaultClass
end

function Squads.squadOf(state: State, uid: number): Squad?
	local id = state.memberOf[uid]
	return if id then state.squads[id] else nil
end

function Squads.isCommander(state: State, uid: number): string?
	for side, commander in state.commanders do
		if commander == uid then
			return side
		end
	end
	return nil
end

function Squads.classOf(state: State, uid: number): string
	local squad = Squads.squadOf(state, uid)
	if squad then
		return squad.classes[uid] or state.config.DefaultClass
	end
	for _, def in state.config.Classes do
		if def.perSide and Squads.isCommander(state, uid) then
			return def.name
		end
	end
	return state.config.DefaultClass
end

function Squads.count(squad: Squad, class: string): number
	local n = 0
	for _, uid in squad.members do
		if squad.classes[uid] == class then
			n += 1
		end
	end
	return n
end

-- Squads of `side`, by number.
function Squads.list(state: State, side: string): { Squad }
	local out = {}
	for _, squad in state.squads do
		if squad.side == side then
			table.insert(out, squad)
		end
	end
	table.sort(out, function(a, b)
		return a.number < b.number
	end)
	return out
end

local function resign(state: State, uid: number)
	local side = Squads.isCommander(state, uid)
	if side then
		state.commanders[side] = nil
	end
end

-- Leaves the player's squad (if any). Returns the new leader if leadership changed hands.
function Squads.leave(state: State, uid: number): number?
	local squad = Squads.squadOf(state, uid)
	if not squad then
		return nil
	end
	state.memberOf[uid] = nil
	squad.classes[uid] = nil
	local i = table.find(squad.members, uid)
	if i then
		table.remove(squad.members, i)
	end
	if #squad.members == 0 then
		state.squads[squad.id] = nil
		return nil
	end
	if squad.leader == uid then
		squad.leader = squad.members[1]
		squad.classes[squad.leader] = leaderClass(state)
		return squad.leader
	end
	return nil
end

-- Removes the player from everything (left the game or changed sides).
function Squads.remove(state: State, uid: number): number?
	resign(state, uid)
	return Squads.leave(state, uid)
end

function Squads.create(state: State, uid: number, side: string): (boolean, string?)
	Squads.remove(state, uid)
	local used = {}
	for _, squad in Squads.list(state, side) do
		used[squad.number] = true
	end
	local number = 1
	while used[number] do
		number += 1
	end
	local squad: Squad = {
		id = state.nextId,
		side = side,
		number = number,
		leader = uid,
		public = true,
		members = { uid },
		classes = { [uid] = leaderClass(state) },
	}
	state.nextId += 1
	state.squads[squad.id] = squad
	state.memberOf[uid] = squad.id
	return true, nil
end

function Squads.join(state: State, uid: number, squadId: number, side: string): (boolean, string?)
	local squad = state.squads[squadId]
	if not squad or squad.side ~= side then
		return false, "That squad no longer exists"
	end
	if state.memberOf[uid] == squadId then
		return true, nil
	end
	if not squad.public then
		return false, "That squad is private"
	end
	if #squad.members >= state.config.SquadSize then
		return false, "That squad is full"
	end
	Squads.remove(state, uid)
	table.insert(squad.members, uid)
	squad.classes[uid] = state.config.DefaultClass
	state.memberOf[uid] = squad.id
	return true, nil
end

function Squads.kick(state: State, leader: number, target: number): (boolean, string?)
	local squad = Squads.squadOf(state, leader)
	if not squad or squad.leader ~= leader then
		return false, "Only the Squad Commander can kick"
	end
	if target == leader or state.memberOf[target] ~= squad.id then
		return false, "That player isn't in your squad"
	end
	Squads.leave(state, target)
	return true, nil
end

function Squads.setPublic(state: State, leader: number, public: boolean): (boolean, string?)
	local squad = Squads.squadOf(state, leader)
	if not squad or squad.leader ~= leader then
		return false, "Only the Squad Commander can change that"
	end
	squad.public = public
	return true, nil
end

function Squads.setClass(state: State, uid: number, class: string, side: string): (boolean, string?)
	local def = Squads.classDef(state, class)
	if not def then
		return false, "Unknown class"
	end
	if Squads.classOf(state, uid) == class then
		return true, nil
	end
	local squad = Squads.squadOf(state, uid)
	if def.perSide then
		local current = state.commanders[side]
		if current and current ~= uid then
			return false, "Your team already has a " .. class
		end
		Squads.leave(state, uid)
		state.commanders[side] = uid
		return true, nil
	end
	if not squad then
		if class == state.config.DefaultClass then
			resign(state, uid)
			return true, nil
		end
		return false, "Join or create a squad to pick a class"
	end
	if squad.leader == uid then
		return false, "Squad Commanders lead their squad; leave it to change class"
	end
	if def.leader then
		return false, "Only the squad's creator is its Squad Commander"
	end
	local cap: number? = (def :: ClassDef).cap
	local mine = squad :: Squad
	if cap and Squads.count(mine, class) >= cap then
		return false, ("Your squad already has %d %s"):format(cap, class)
	end
	mine.classes[uid] = class
	return true, nil
end

-- Plain data for the client (no sparse number-keyed tables, which don't survive remotes).
function Squads.serialize(state: State)
	local squads = {}
	for _, squad in state.squads do
		local members = {}
		for _, uid in squad.members do
			table.insert(members, { userId = uid, class = squad.classes[uid] })
		end
		table.insert(squads, {
			id = squad.id,
			side = squad.side,
			number = squad.number,
			leader = squad.leader,
			public = squad.public,
			members = members,
		})
	end
	table.sort(squads, function(a, b)
		return a.number < b.number
	end)
	return { squads = squads, commanders = { A = state.commanders.A or 0, B = state.commanders.B or 0 } }
end

return Squads
