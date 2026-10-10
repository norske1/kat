--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Interaction = require(ReplicatedStorage:WaitForChild("Medical").Interaction)
local Ui = require(script.Parent.Ui)

local InteractionInput = {}
local focused = true

UserInputService.WindowFocusReleased:Connect(function()
	focused = false
end)
UserInputService.WindowFocused:Connect(function()
	focused = true
end)

function InteractionInput.isHeld(): boolean
	return focused and UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
end

function InteractionInput.isActive(): boolean
	local character = Players.LocalPlayer.Character
	return Interaction.active({
		held = InteractionInput.isHeld(),
		focused = focused,
		modal = Ui.isModalOpen(),
		typing = UserInputService:GetFocusedTextBox() ~= nil,
		hasCharacter = character ~= nil,
		alive = character ~= nil and character:GetAttribute("MedAlive") ~= false,
		conscious = character ~= nil and character:GetAttribute("MedConscious") ~= false,
	})
end

function InteractionInput.cursorRay(): Ray?
	return Interaction.cursorRay(workspace.CurrentCamera, UserInputService:GetMouseLocation())
end

function InteractionInput.cast(distance: number): RaycastResult?
	local ray = InteractionInput.cursorRay()
	if ray == nil then
		return nil
	end
	local cursor = ray :: Ray
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	local character = Players.LocalPlayer.Character
	local camera = workspace.CurrentCamera
	if character then
		table.insert(exclude, character)
	end
	if camera then
		table.insert(exclude, camera)
	end
	params.FilterDescendantsInstances = exclude
	return workspace:Raycast(cursor.Origin, cursor.Direction * distance, params)
end

return InteractionInput
