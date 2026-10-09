--!nonstrict
-- Chat window: channel tabs (Local / Team / Squad / Command) and a coloured channel tag on every message.
local TextChatService = game:GetService("TextChatService")

local ChatClient = {}

local TAGS = {
	{ match = "^RBXGeneral$", tag = "LOCAL", color = "D0D0D0" },
	{ match = "^RBXWhisper", tag = "WHISPER", color = "B0B0B0" },
	{ match = "^RBXTeam", tag = "TEAM", color = "6FB3FF" },
	{ match = "^Squad$", tag = "SQUAD", color = "7CE38B" },
	{ match = "^Command$", tag = "COMMAND", color = "F2C14E" },
}

function ChatClient.init()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end
	pcall(function()
		TextChatService.ChannelTabsConfiguration.Enabled = true
	end)
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local channel = message.TextChannel
		if not channel or not message.TextSource then
			return nil
		end
		for _, t in TAGS do
			if string.match(channel.Name, t.match) then
				local props = Instance.new("TextChatMessageProperties")
				props.PrefixText = string.format('<font color="#%s">[%s]</font> %s', t.color, t.tag, message.PrefixText)
				return props
			end
		end
		return nil
	end
end

return ChatClient
