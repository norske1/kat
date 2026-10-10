--!strict
local Interaction = {}

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

return Interaction
