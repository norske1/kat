--!nonstrict
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local InventoryInput = {}

function InventoryInput.bind(key, toggle, canToggle)
	local function allowed()
		return not GuiService.MenuIsOpen and not UserInputService:GetFocusedTextBox() and canToggle()
	end
	ContextActionService:BindActionAtPriority("HellboundInventory", function()
		return if allowed() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 1, key)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == key and allowed() then
			toggle()
		end
	end)
end

return InventoryInput
