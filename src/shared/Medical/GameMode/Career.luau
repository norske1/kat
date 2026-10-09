--!strict
-- Player career stats (pure, tested under Lune). Saved by the server's CareerService and shown in the main menu.
local Career = {}

export type Data = { kills: number, deaths: number, seconds: number, classSeconds: { [string]: number } }

Career.DefaultClass = "Rifleman" -- class of players outside a squad (GameConfig.DefaultClass)

function Career.new(): Data
	return { kills = 0, deaths = 0, seconds = 0, classSeconds = {} }
end

local function count(value: any): number
	return if type(value) == "number" and value == value and value >= 0 then value else 0
end

-- Turns whatever was stored (or nothing) into valid career data.
function Career.sanitize(raw: any): Data
	local data = Career.new()
	if type(raw) ~= "table" then
		return data
	end
	data.kills = math.floor(count(raw.kills))
	data.deaths = math.floor(count(raw.deaths))
	data.seconds = count(raw.seconds)
	if type(raw.classSeconds) == "table" then
		for class, seconds in raw.classSeconds do
			if type(class) == "string" then
				data.classSeconds[class] = count(seconds)
			end
		end
	end
	return data
end

-- Adds the stats in `extra` to `data` (e.g. what was earned in-session before the saved data loaded).
function Career.merge(data: Data, extra: Data): Data
	data.kills += extra.kills
	data.deaths += extra.deaths
	data.seconds += extra.seconds
	for class, seconds in extra.classSeconds do
		data.classSeconds[class] = (data.classSeconds[class] or 0) + seconds
	end
	return data
end

function Career.kd(kills: number, deaths: number): number
	return if deaths == 0 then kills else kills / deaths
end

function Career.formatKd(kills: number, deaths: number): string
	return ("%.2f"):format(Career.kd(kills, deaths))
end

function Career.mostUsedClass(classSeconds: { [string]: number }): string
	local best, bestSeconds = Career.DefaultClass, 0
	for class, seconds in classSeconds do
		if seconds > bestSeconds or (seconds == bestSeconds and seconds > 0 and class < best) then
			best, bestSeconds = class, seconds
		end
	end
	return best
end

-- 45s, 12m, 3h 05m
function Career.formatTime(seconds: number): string
	local total = math.floor(seconds)
	local h, m = total // 3600, (total % 3600) // 60
	if h > 0 then
		return ("%dh %02dm"):format(h, m)
	elseif m > 0 then
		return ("%dm"):format(m)
	end
	return ("%ds"):format(total)
end

return Career
