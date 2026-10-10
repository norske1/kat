--!strict
local Interaction = {}
-- selene: allow(deprecated)
local NO_KEY = Enum.KeyCode.Unknown

-- Explicit card shortcuts (attribute InteractionKey). Everything else is clicked on its card.
Interaction.Keys = { F = Enum.KeyCode.F, G = Enum.KeyCode.G, V = Enum.KeyCode.V }

type Context = {
	held: boolean,
	focused: boolean,
	modal: boolean,
	typing: boolean,
	hasCharacter: boolean,
	alive: boolean,
	conscious: boolean,
}

function Interaction.active(ctx: Context): boolean
	return ctx.held
		and ctx.focused
		and not ctx.modal
		and not ctx.typing
		and ctx.hasCharacter
		and ctx.alive
		and ctx.conscious
end

function Interaction.cursorRay(camera: any, point: Vector2): Ray?
	return if camera then camera:ViewportPointToRay(point.X, point.Y) else nil
end

function Interaction.target(parent: Instance?, arsenal: boolean): Instance?
	if parent == nil then
		return nil
	end
	local host = parent :: Instance
	if host:IsA("Model") then
		return host
	end
	local part = if host:IsA("BasePart") then host else host:FindFirstAncestorWhichIsA("BasePart")
	if part == nil then
		return nil
	end
	local source = part :: BasePart
	local model = source:FindFirstAncestorOfClass("Model")
	if model and (arsenal or model.PrimaryPart == source or model:FindFirstChildOfClass("Humanoid")) then
		return model
	end
	return source
end

function Interaction.shortcut(prompt: Instance): Enum.KeyCode
	local key = prompt:GetAttribute("InteractionKey")
	return (if typeof(key) == "string" then Interaction.Keys[key] else nil) or NO_KEY
end

-- Shortcut-only cards (no hold, e.g. vehicle cargo V) ignore clicks; everything else can be clicked/held on the card.
function Interaction.clickable(prompt: ProximityPrompt): boolean
	return prompt:GetAttribute("InteractionKey") == nil or prompt.HoldDuration > 0
end

-- Roblox triggers every shown Custom-style prompt on a bare click/tap, so clicks go through the cards instead.
function Interaction.configure(prompt: ProximityPrompt)
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ClickablePrompt = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.GamepadKeyCode = NO_KEY
	local key = Interaction.shortcut(prompt)
	if prompt.KeyboardKeyCode ~= key then
		prompt.KeyboardKeyCode = key
	end
end

return Interaction
