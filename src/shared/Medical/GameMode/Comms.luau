--!strict
-- Who hears a chat message (pure rules, no Roblox services). Local chat only reaches players in range;
-- the radio channels need a radio on both ends: Team (same side), Squad (same squad) and Command
-- (Squad Commanders and the Commander of the same side).
local Comms = {}

export type Info = {
	uid: number,
	side: string?,
	squad: number, -- 0 = no squad
	class: string,
	radio: boolean,
	conscious: boolean,
	pos: Vector3?, -- nil when there's no character (lobby)
}

export type ChatConfig = { LocalRange: number, UnconsciousCanTalk: boolean }

Comms.LEADERS = { ["Squad Commander"] = true, Commander = true }

function Comms.isRadio(channel: string): boolean
	return channel == "team" or channel == "squad" or channel == "command"
end

-- Why the sender can't use a channel (nil if they can).
function Comms.blocked(channel: string, s: Info, cfg: ChatConfig): string?
	if not s.conscious and not cfg.UnconsciousCanTalk then
		return "You can't talk while unconscious"
	end
	if not Comms.isRadio(channel) then
		return nil
	end
	if not s.side then
		return "Join a team to use the radio"
	elseif not s.radio then
		return "You need a Radio in your inventory to use the radio"
	elseif channel == "squad" and s.squad == 0 then
		return "You're not in a squad"
	elseif channel == "command" and not Comms.LEADERS[s.class] then
		return "Only Squad Commanders and the Commander can use the command channel"
	end
	return nil
end

function Comms.canHear(channel: string, s: Info, r: Info, cfg: ChatConfig): boolean
	if s.uid == r.uid then
		return true
	end
	if Comms.blocked(channel, s, cfg) then
		return false
	end
	if channel == "local" then
		local sp, rp = s.pos, r.pos
		if sp and rp then
			local dx, dy, dz = sp.X - rp.X, sp.Y - rp.Y, sp.Z - rp.Z
			return dx * dx + dy * dy + dz * dz <= cfg.LocalRange * cfg.LocalRange
		end
		return sp == nil and rp == nil -- lobby players talk to each other
	end
	if not Comms.isRadio(channel) or not r.radio or not r.conscious or s.side ~= r.side then
		return false
	end
	if channel == "squad" then
		return r.squad == s.squad
	elseif channel == "command" then
		return Comms.LEADERS[r.class] == true
	end
	return true
end

return Comms
