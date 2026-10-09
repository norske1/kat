--!nonstrict
-- Live squads and classes (GameMode.Squads). The main menu's Squads page sends Squad(action, arg):
--   "sync", "create", "join" (squad id), "leave", "kick" (UserId), "public" (boolean), "class" (class name)
-- Every change is broadcast with SquadState and the sender gets SquadResult(ok, message).
-- The active class is the Player attribute "Class" (also used by CareerService). It follows the player's squad
-- role, except that a kicked player keeps their class until they respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local GameConfig = require(Medical.GameMode.Config)
local Squads = require(Medical.GameMode.Squads)
local Remotes = require(Medical.Remotes)
local MedicalService = require(script.Parent.Parent.MedicalService)

local SquadService = {}

local state = Squads.new(GameConfig)
local kicked: { [number]: boolean } = {} -- keep their class until they respawn
local lastRequest: { [Player]: number } = {}

local function sideOf(player: Player): string?
	local team = player.Team
	return if team then team:GetAttribute("Side") else nil
end

local function refresh()
	for _, player in Players:GetPlayers() do
		if not kicked[player.UserId] then
			player:SetAttribute("Class", Squads.classOf(state, player.UserId))
		end
		local squad = Squads.squadOf(state, player.UserId)
		player:SetAttribute("SquadId", if squad then squad.id else 0)
	end
	Remotes.get("SquadState"):FireAllClients(Squads.serialize(state))
end

local function reply(player: Player, ok: boolean, message: string?)
	Remotes.get("SquadResult"):FireClient(player, ok, message)
end

local function leadersOf(): { [number]: number }
	local leaders = {}
	for id, squad in state.squads do
		leaders[id] = squad.leader
	end
	return leaders
end

-- Tells players who just became Squad Commander because their leader left.
local function announceLeaders(before: { [number]: number })
	for id, squad in state.squads do
		if before[id] and before[id] ~= squad.leader then
			local leader = Players:GetPlayerByUserId(squad.leader)
			if leader then
				MedicalService.notify(leader, ("You now lead Squad %d"):format(squad.number), "info")
			end
		end
	end
end

local function handle(player: Player, action: any, arg: any)
	if action == "sync" then
		Remotes.get("SquadState"):FireClient(player, Squads.serialize(state))
		return
	end
	local side = sideOf(player)
	if not side then
		reply(player, false, "Join a team first")
		return
	end
	local uid = player.UserId
	local before = leadersOf()
	local ok, err
	if action == "create" then
		ok, err = Squads.create(state, uid, side)
	elseif action == "join" and type(arg) == "number" then
		ok, err = Squads.join(state, uid, arg, side)
	elseif action == "leave" then
		Squads.leave(state, uid)
		ok = true
	elseif action == "kick" and type(arg) == "number" then
		ok, err = Squads.kick(state, uid, arg)
		local target = Players:GetPlayerByUserId(arg)
		if ok and target then
			if target.Character then
				kicked[arg] = true
			end
			MedicalService.notify(target, "You were kicked from your squad", "warn")
		end
	elseif action == "public" and type(arg) == "boolean" then
		ok, err = Squads.setPublic(state, uid, arg)
	elseif action == "class" and type(arg) == "string" then
		ok, err = Squads.setClass(state, uid, arg, side)
	else
		return
	end
	if ok then
		kicked[uid] = nil
		announceLeaders(before)
		refresh()
	end
	reply(player, ok == true, err)
end

local function removePlayer(player: Player)
	local before = leadersOf()
	Squads.remove(state, player.UserId)
	kicked[player.UserId] = nil
	announceLeaders(before)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		kicked[player.UserId] = nil
		player:SetAttribute("Class", Squads.classOf(state, player.UserId))
	end)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		removePlayer(player)
		refresh()
	end)
	player:SetAttribute("Class", Squads.classOf(state, player.UserId))
end

function SquadService.classOf(player: Player): string
	return Squads.classOf(state, player.UserId)
end

function SquadService.init()
	Remotes.get("Squad").OnServerEvent:Connect(function(player, action, arg)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 0.25 then
			reply(player, false, "Slow down")
			return
		end
		lastRequest[player] = now
		handle(player, action, arg)
	end)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		removePlayer(player)
		refresh()
	end)
end

return SquadService
