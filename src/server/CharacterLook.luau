--!strict
-- Spawns every player as an R15 rig with the classic blocky body parts and classic scaling, so characters look
-- like R6 but keep R15 joints. The player's clothes, face, accessories and colours are kept.
local Players = game:GetService("Players")

local CharacterLook = {}

local cache: { [number]: HumanoidDescription } = {}

local function description(player: Player): HumanoidDescription
	local cached = cache[player.UserId]
	if cached then
		return cached:Clone()
	end
	local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, math.max(player.UserId, 1))
	local result: HumanoidDescription = if ok and desc then desc else Instance.new("HumanoidDescription")
	for _, prop in { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
		(result :: any)[prop] = 0
	end
	result.HeightScale = 1
	result.WidthScale = 1
	result.DepthScale = 1
	result.HeadScale = 1
	result.BodyTypeScale = 0
	result.ProportionScale = 0
	if ok and desc then
		cache[player.UserId] = result
	end
	return result:Clone()
end

function CharacterLook.load(player: Player)
	if not player.Parent then
		return
	end
	local ok, err = pcall(function()
		player:LoadCharacterWithHumanoidDescription(description(player))
	end)
	if not ok then
		warn("[KATMedical] blocky R15 spawn failed, using the default character: " .. tostring(err))
		player:LoadCharacter()
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn("[KATMedical] characters are R6: set Game Settings > Avatar > Avatar Type to R15")
	end
end

Players.PlayerRemoving:Connect(function(player)
	cache[player.UserId] = nil
end)

return CharacterLook
