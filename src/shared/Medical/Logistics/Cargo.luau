--!strict
local Cargo = {}

export type Access = {
	side: string?,
	vehicleSide: string?,
	alive: boolean,
	conscious: boolean,
	distance: number,
	range: number,
}

function Cargo.canAccess(ctx: Access): boolean
	return (ctx.side == "A" or ctx.side == "B")
		and ctx.side == ctx.vehicleSide
		and ctx.alive
		and ctx.conscious
		and ctx.distance >= 0
		and ctx.distance <= ctx.range
end

export type State = {
	cargo: number,
	capacity: number,
	stock: number,
	stockCapacity: number,
	unlimited: boolean,
}

function Cargo.move(state: State, loading: boolean, amount: any): (number, number, number, string?)
	local requested: number
	if amount == "all" then
		requested = math.huge
	elseif typeof(amount) == "number" and amount > 0 and amount < math.huge and amount % 1 == 0 then
		requested = amount
	else
		return state.cargo, state.stock, 0, "Choose a positive whole-number quantity"
	end
	local available = if loading then (if state.unlimited then math.huge else state.stock) else state.cargo
	local room = if loading
		then state.capacity - state.cargo
		else (if state.unlimited then math.huge else state.stockCapacity - state.stock)
	local moved = math.max(0, math.min(requested, available, room))
	if moved == 0 then
		return state.cargo, state.stock, 0, if available <= 0 then "No supplies available" else "Destination is full"
	end
	local cargo = state.cargo + (if loading then moved else -moved)
	local stock = if state.unlimited then state.stock else state.stock + (if loading then -moved else moved)
	return cargo, stock, moved, nil
end

return Cargo
