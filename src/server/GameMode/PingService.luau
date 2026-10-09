--!nonstrict
-- Server side of pings: validates who may ping and sends every player only the pings they're allowed to see.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local GameConfig = require(Medical.GameMode.Config)
local Pings = require(Medical.GameMode.Pings)
local Remotes = require(Medical.Remotes)

local PingService = {}

local hooks = {
	isDown = function(_player: Player): boolean
		return false
	end,
}
local list: { Pings.Ping } = {}
local nextId = 0
local lastPing: { [Player]: number } = {}
local stateRemote = nil

local function viewer(player: Player): Pings.Viewer
	return {
		uid = player.UserId,
		side = player.Team and player.Team:GetAttribute("Side"),
		squad = player:GetAttribute("SquadId") or 0,
		class = player:GetAttribute("Class") or GameConfig.DefaultClass,
	}
end

local function viewFor(player: Player)
	local v = viewer(player)
	local out = {}
	for _, p in list do
		if Pings.visible(p, v) then
			table.insert(out, {
				id = p.id,
				pos = p.pos,
				scope = p.scope,
				author = p.author,
				own = p.uid == player.UserId,
			})
		end
	end
	return out
end

local function broadcast()
	for _, player in Players:GetPlayers() do
		stateRemote:FireClient(player, viewFor(player))
	end
end

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e5
end

local function onPing(player: Player, action: any, pos: any)
	local now = os.clock()
	if now - (lastPing[player] or 0) < 0.35 then
		return
	end
	lastPing[player] = now
	if action == "clear" then
		if Pings.clear(list, player.UserId) then
			broadcast()
		end
		return
	end
	local v = viewer(player)
	if action ~= "enemy" or typeof(pos) ~= "Vector3" or not finite(pos) or not v.side then
		return
	end
	if not player.Character or hooks.isDown(player) then
		return
	end
	nextId += 1
	Pings.add(list, {
		id = nextId,
		uid = v.uid,
		side = v.side,
		squad = v.squad,
		class = v.class,
		scope = Pings.scope(v.class, v.squad),
		expires = now + GameConfig.Map.PingLifetime,
		pos = pos,
		author = player.DisplayName,
	}, now, GameConfig.Map.MaxPings)
	broadcast()
end

function PingService.init(options)
	for k, v in options or {} do
		hooks[k] = v
	end
	stateRemote = Remotes.get("PingState")
	Remotes.get("Ping").OnServerEvent:Connect(onPing)
	local function onPlayer(player: Player)
		for _, attr in { "SquadId", "Class" } do
			player:GetAttributeChangedSignal(attr):Connect(broadcast)
		end
		player:GetPropertyChangedSignal("Team"):Connect(function()
			Pings.clear(list, player.UserId)
			broadcast()
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastPing[player] = nil
		if Pings.clear(list, player.UserId) then
			broadcast()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Pings.prune(list, os.clock()) then
				broadcast()
			end
		end
	end)
end

return PingService
