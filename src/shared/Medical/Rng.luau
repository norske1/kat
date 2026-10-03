--!strict
-- Small deterministic PRNG usable both in Roblox and in Lune tests.
export type Rng = {
	next: (self: Rng) -> number,
	range: (self: Rng, min: number, max: number) -> number,
	chance: (self: Rng, percentOrFraction: number) -> boolean,
	pickWeighted: (self: Rng, weights: { [string]: number }) -> string,
	state: number,
}

local Rng = {}
Rng.__index = Rng

function Rng.new(seed: number?): Rng
	local self = setmetatable({}, Rng) :: any
	self.state = math.floor(seed or (os.clock() * 1e6)) % 2147483647
	if self.state <= 0 then
		self.state = 1
	end
	return self
end

-- Park-Miller minimal standard generator
function Rng.next(self: Rng): number
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end

function Rng.range(self: Rng, min: number, max: number): number
	return min + (max - min) * self:next()
end

-- Accepts a fraction (0-1) or a percentage (>1).
function Rng.chance(self: Rng, p: number): boolean
	local fraction = if p > 1 then p / 100 else p
	return self:next() < fraction
end

function Rng.pickWeighted(self: Rng, weights: { [string]: number }): string
	local keys = {}
	local total = 0
	for key, weight in weights do
		table.insert(keys, key)
		total += weight
	end
	table.sort(keys)
	local roll = self:next() * total
	for _, key in keys do
		roll -= weights[key]
		if roll <= 0 then
			return key
		end
	end
	return keys[#keys]
end

return Rng
