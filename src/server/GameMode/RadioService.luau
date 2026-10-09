--!nonstrict
-- Proximity chat and radio channels on top of Roblox's TextChatService (which keeps Roblox's text filter).
-- RBXGeneral becomes local chat, the RBXTeam channels become the Team radio, and "Squad" and "Command"
-- channels are added. Whispers only reach players in local range.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local GameConfig = require(Medical.GameMode.Config)
local Comms = require(Medical.GameMode.Comms)

local RadioService = {}

local hooks = {
	hasRadio = function(_player: Player): boolean
		return true
	end,
	isDown = function(_player: Player): boolean
		return false
	end,
	notify = function(_player: Player, _text: string) end,
}

local function info(player: Player): Comms.Info
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local team = player.Team
	return {
		uid = player.UserId,
		side = team and team:GetAttribute("Side"),
		squad = player:GetAttribute("SquadId") or 0,
		class = player:GetAttribute("Class") or GameConfig.DefaultClass,
		radio = hooks.hasRadio(player),
		conscious = not hooks.isDown(player),
		pos = if root then (root :: BasePart).Position else nil,
	}
end

local function channelKind(channel: TextChannel): string?
	local name = channel.Name
	if name == "RBXGeneral" or string.sub(name, 1, 10) == "RBXWhisper" then
		return "local"
	elseif string.sub(name, 1, 7) == "RBXTeam" then
		return "team"
	elseif name == "Squad" then
		return "squad"
	elseif name == "Command" then
		return "command"
	end
	return nil
end

local warned: { [string]: boolean } = {}

local function hook(inst: Instance)
	if not inst:IsA("TextChannel") then
		return
	end
	local channel = inst :: TextChannel
	local kind = channelKind(channel)
	if not kind then
		return
	end
	channel.ShouldDeliverCallback = function(message: TextChatMessage, target: TextSource): boolean
		local sender = message.TextSource and Players:GetPlayerByUserId(message.TextSource.UserId)
		local receiver = Players:GetPlayerByUserId(target.UserId)
		if not sender or not receiver then
			return false
		end
		local s = info(sender)
		if sender == receiver then
			local why = Comms.blocked(kind, s, GameConfig.Chat)
			if why and not warned[message.MessageId] then
				warned[message.MessageId] = true
				task.delay(30, function()
					warned[message.MessageId] = nil
				end)
				hooks.notify(sender, why)
			end
			return true
		end
		return Comms.canHear(kind, s, info(receiver), GameConfig.Chat)
	end
end

local function sourceOf(channel: TextChannel, player: Player): TextSource?
	for _, child in channel:GetChildren() do
		if child:IsA("TextSource") and child.UserId == player.UserId then
			return child
		end
	end
	return nil
end

-- Squad / Command membership decides who gets the channel tab.
local function setMember(channel: TextChannel, player: Player, member: boolean)
	local existing = sourceOf(channel, player)
	if member and not existing then
		pcall(function()
			channel:AddUserAsync(player.UserId)
		end)
	elseif not member and existing then
		existing:Destroy()
	end
end

function RadioService.init(options)
	for k, v in options or {} do
		hooks[k] = v
	end
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[Radio] set TextChatService.ChatVersion to TextChatService for proximity chat and radio channels")
		return
	end
	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		if not channels then
			warn("[Radio] TextChatService has no TextChannels folder")
			return
		end
		local function make(name: string): TextChannel
			local ch = channels:FindFirstChild(name)
			if not ch then
				ch = Instance.new("TextChannel")
				ch.Name = name
				ch.Parent = channels
			end
			return ch
		end
		local squad = make("Squad")
		local command = make("Command")
		for _, ch in channels:GetChildren() do
			hook(ch)
		end
		channels.ChildAdded:Connect(hook)

		local function update(player: Player)
			local onSide = player.Team ~= nil and player.Team:GetAttribute("Side") ~= nil
			setMember(squad, player, onSide and (player:GetAttribute("SquadId") or 0) ~= 0)
			setMember(command, player, onSide and Comms.LEADERS[player:GetAttribute("Class") or ""] == true)
		end
		local function onPlayer(player: Player)
			player:GetAttributeChangedSignal("SquadId"):Connect(function()
				update(player)
			end)
			player:GetAttributeChangedSignal("Class"):Connect(function()
				update(player)
			end)
			player:GetPropertyChangedSignal("Team"):Connect(function()
				update(player)
			end)
			update(player)
		end
		Players.PlayerAdded:Connect(onPlayer)
		for _, player in Players:GetPlayers() do
			task.spawn(onPlayer, player)
		end
	end)
end

return RadioService
