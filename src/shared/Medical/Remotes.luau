--!strict
-- RemoteEvents shared between server and client. The server creates them, clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.Names = {
	"OpenMenu", -- C->S (target Model?) nil = self
	"CloseMenu", -- C->S
	"RequestAction", -- C->S (target Model, actionId, bodyPart)
	"CancelAction", -- C->S
	"DropCarry", -- C->S
	"Debug", -- C->S (command, ...)
	"View", -- S->C (view?) patient snapshot, nil closes the menu
	"Effects", -- S->C (effects) own screen effects
	"Progress", -- S->C ({ label, duration }?)
	"Notify", -- S->C (text, kind)
	"Inventory", -- S->C (items, level, debugAllowed)
	"GunFire", -- C->S (tool, origin, directions)
	"GunReload", -- C->S (tool)
	"GunState", -- C->S (tool, aiming, pitch)
	"GunFx", -- S->C (shooter, weaponId, origin, hits) shots by other players
	"GunHit", -- S->C (kind) hit confirmation for the shooter
	"LockerTake", -- C->S (slot BasePart) take / equip a weapon from a locker
}

local FOLDER = "MedicalRemotes"

function Remotes.get(name: string): RemoteEvent
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	if not folder then
		if RunService:IsServer() then
			folder = Instance.new("Folder")
			folder.Name = FOLDER
			folder.Parent = ReplicatedStorage
		else
			folder = ReplicatedStorage:WaitForChild(FOLDER)
		end
	end
	assert(folder, "remotes folder missing")
	local remote = folder:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name)
		end
	end
	return remote :: RemoteEvent
end

function Remotes.init()
	for _, name in Remotes.Names do
		Remotes.get(name)
	end
end

return Remotes
