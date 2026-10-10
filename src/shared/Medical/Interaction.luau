--!strict
local Interaction = {}
-- Never use Enum.KeyCode.Unknown on a prompt: mouse and touch input also report KeyCode Unknown, so Roblox treats a
-- bare click as "the prompt's key" and triggers every shown prompt at once (seat + cargo on one Alt+LMB). These
-- codes exist on no keyboard or gamepad, so only the card click / real shortcut can trigger a prompt.
Interaction.NoKeyboard = Enum.KeyCode.World95
Interaction.NoGamepad = Enum.KeyCode.World94

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
	return (if typeof(key) == "string" then Interaction.Keys[key] else nil) or Interaction.NoKeyboard
end

-- Shortcut-only cards (no hold, e.g. vehicle cargo V) ignore clicks; everything else can be clicked/held on the card.
function Interaction.clickable(prompt: ProximityPrompt): boolean
	return prompt:GetAttribute("InteractionKey") == nil or prompt.HoldDuration > 0
end

-- The client drives F/G/V itself (InputHoldBegin/End), so a shortcut press only reaches the cards it belongs to.
function Interaction.matches(prompt: Instance, key: Enum.KeyCode): boolean
	return key ~= Interaction.NoKeyboard and Interaction.shortcut(prompt) == key
end

-- Roblox never triggers a prompt on its own: no engine key, no engine click. Cards and shortcut keys call
-- InputHoldBegin/End, which still goes through Roblox's hold timer and fires Triggered on the server.
function Interaction.configure(prompt: ProximityPrompt)
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ClickablePrompt = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	if prompt.GamepadKeyCode ~= Interaction.NoGamepad then
		prompt.GamepadKeyCode = Interaction.NoGamepad
	end
	if prompt.KeyboardKeyCode ~= Interaction.NoKeyboard then
		prompt.KeyboardKeyCode = Interaction.NoKeyboard
	end
end

return Interaction
