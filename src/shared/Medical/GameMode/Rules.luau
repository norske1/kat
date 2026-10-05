--!strict
-- Squad-style ticket and objective rules (pure, no Roblox services, tested under Lune).
-- Objectives form a lane 1..N. Side A attacks 1 -> N, side B attacks N -> 1, and a side can only attack the
-- first objective it doesn't own counting from its own end. Progress runs from -100 (B) to 100 (A): an owned
-- objective must be neutralised (progress back to 0) before the other side can capture it.
local Rules = {}

export type Side = string -- "A" | "B"
export type Point = { owner: Side?, progress: number }
export type State = { tickets: { [Side]: number }, points: { Point }, winner: Side? }
export type Event = { kind: string, side: Side, point: number }
export type Settings = {
	CaptureSeconds: number,
	ExtraCapperBonus: number,
	MaxCaptureMultiplier: number,
	RegenSeconds: number,
	DeathTickets: number,
	ObjectiveLossTickets: number,
}

function Rules.other(side: Side): Side
	return if side == "A" then "B" else "A"
end

function Rules.sign(side: Side): number
	return if side == "A" then 1 else -1
end

-- Side A owns objective 1, side B owns the last one, the ones in between are neutral.
function Rules.new(count: number, tickets: number): State
	local points = {}
	for i = 1, count do
		local owner: Side? = if i == 1 then "A" elseif i == count then "B" else nil
		points[i] = { owner = owner, progress = if owner then Rules.sign(owner) * 100 else 0 }
	end
	return { tickets = { A = tickets, B = tickets }, points = points, winner = nil }
end

-- Index of the only objective `side` may attack, or nil if it owns them all.
function Rules.attackable(points: { Point }, side: Side): number?
	local n = #points
	local from, to, step = 1, n, 1
	if side == "B" then
		from, to, step = n, 1, -1
	end
	for i = from, to, step do
		if points[i].owner ~= side then
			return i
		end
	end
	return nil
end

-- Whether `side` can change objective i right now: attack it, or defend / restore one it owns.
function Rules.canAffect(points: { Point }, i: number, side: Side): boolean
	return points[i].owner == side or Rules.attackable(points, side) == i
end

local function toward(value: number, target: number, amount: number): number
	if value < target then
		return math.min(value + amount, target)
	end
	return math.max(value - amount, target)
end

local function lose(state: State, side: Side, amount: number)
	state.tickets[side] = math.max(state.tickets[side] - amount, 0)
	if state.tickets[side] <= 0 and not state.winner then
		state.winner = Rules.other(side)
	end
end

-- Advances objective i by dt seconds with countA / countB living players inside it. Returns events:
-- { kind = "lost", side, point } (side lost it, tickets taken) and { kind = "captured", side, point }.
function Rules.capture(state: State, i: number, countA: number, countB: number, dt: number, cfg: Settings): { Event }
	local events: { Event } = {}
	local p = state.points[i]
	if state.winner then
		return events
	end
	local diff = countA - countB
	if diff == 0 then
		if countA == 0 then
			-- empty: owned objectives restore, neutral ones drift back to 0
			local target = if p.owner then Rules.sign(p.owner :: Side) * 100 else 0
			p.progress = toward(p.progress, target, 100 / cfg.RegenSeconds * dt)
		end
		return events -- contested: frozen
	end
	local side: Side = if diff > 0 then "A" else "B"
	if not Rules.canAffect(state.points, i, side) then
		return events -- locked for this side
	end
	local n = math.abs(diff)
	local rate = 100 / cfg.CaptureSeconds * math.min(1 + (n - 1) * cfg.ExtraCapperBonus, cfg.MaxCaptureMultiplier)
	p.progress = toward(p.progress, Rules.sign(side) * 100, rate * dt)

	local owner = p.owner
	if owner and owner ~= side and Rules.sign(owner) * p.progress <= 0 then
		p.owner = nil
		p.progress = 0
		lose(state, owner, cfg.ObjectiveLossTickets)
		table.insert(events, { kind = "lost", side = owner, point = i })
	elseif not owner and math.abs(p.progress) >= 100 then
		p.owner = side
		table.insert(events, { kind = "captured", side = side, point = i })
	end
	return events
end

-- A player on `side` died.
function Rules.death(state: State, side: Side, cfg: Settings)
	if not state.winner then
		lose(state, side, cfg.DeathTickets)
	end
end

return Rules
