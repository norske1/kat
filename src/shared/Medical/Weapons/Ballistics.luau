--!strict
-- Bullet flight: muzzle velocity plus gravity, stepped in segments so bullets take time to arrive and
-- drop over distance. The server (damage) and every client (tracers, impacts, cracks) use the same maths.
local Ballistics = {}

export type Bullet = {
	position: Vector3,
	velocity: Vector3,
	traveled: number,
	range: number,
	age: number,
}

function Ballistics.new(origin: Vector3, direction: Vector3, speed: number, range: number): Bullet
	return { position = origin, velocity = direction.Unit * speed, traveled = 0, range = range, age = 0 }
end

-- Position and velocity after dt seconds of free flight.
function Ballistics.advance(position: Vector3, velocity: Vector3, gravity: Vector3, dt: number): (Vector3, Vector3)
	return position + velocity * dt + gravity * (0.5 * dt * dt), velocity + gravity * dt
end

-- Moves a bullet forward by dt. `cast(from, displacement)` returns a RaycastResult (or nil).
-- Returns the hit, if any, and whether the bullet is finished (hit something or out of range).
function Ballistics.step(bullet: Bullet, gravity: Vector3, dt: number, cast: (Vector3, Vector3) -> any): (any, boolean)
	local nextPosition, nextVelocity = Ballistics.advance(bullet.position, bullet.velocity, gravity, dt)
	local delta = nextPosition - bullet.position
	local remaining = bullet.range - bullet.traveled
	if delta.Magnitude > remaining then
		delta = delta.Unit * math.max(remaining, 0.01)
		nextPosition = bullet.position + delta
	end
	bullet.age += dt
	local hit = cast(bullet.position, delta)
	if hit then
		bullet.traveled += (hit.Position - bullet.position).Magnitude
		bullet.position = hit.Position
		return hit, true
	end
	bullet.traveled += delta.Magnitude
	bullet.position = nextPosition
	bullet.velocity = nextVelocity
	return nil, bullet.traveled >= bullet.range - 1e-3
end

-- Bullet drop in studs after `distance` studs at `speed` studs/s under `gravity` studs/s².
function Ballistics.dropAt(distance: number, speed: number, gravity: number): number
	local t = distance / speed
	return 0.5 * gravity * t * t
end

return Ballistics
