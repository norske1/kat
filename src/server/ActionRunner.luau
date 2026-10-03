--!nonstrict
-- Validates and runs timed treatments requested by clients.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Config)
local BodyParts = require(Medical.BodyParts)
local Items = require(Medical.Items)
local Remotes = require(Medical.Remotes)
local Actions = require(Medical.Sim.Actions)
local ActionFx = require(Medical.ActionFx)
local Sounds = require(Medical.Sounds)
local MedicalService = require(script.Parent.MedicalService)
local Inventory = require(script.Parent.Inventory)
local Carry = require(script.Parent.Carry)

local ActionRunner = {}

local progressRemote = Remotes.get("Progress")
local running: { [Player]: { cancelled: boolean, record: any, def: any } } = {}

local function rootPosition(player: Player): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root then (root :: BasePart).Position else nil
end

local function makeContext(player: Player, record, part: string)
	return {
		patient = record.state,
		part = part,
		medicLevel = MedicalService.medicLevel(player),
		isSelf = record.player == player,
		rng = record.state.rng,
		medicName = player.DisplayName,
	}
end

local function itemPicker(player: Player)
	return function(itemId: string)
		return Inventory.has(player, itemId)
	end
end

-- Checks everything except timing. Returns ok, reason, itemId.
local function check(player: Player, record, def, part: string): (boolean, string?, string?)
	if MedicalService.isIncapacitated(player) then
		return false, "You are incapacitated"
	end
	if record.player ~= player and MedicalService.distance(player, record) > Config.MaxTreatmentDistance then
		return false, "Too far away"
	end
	if record.carrier and def.server == nil then
		return false, "Put the patient down first"
	end
	local ctx = makeContext(player, record, part)
	local ok, reason = Actions.validate(def, ctx)
	if not ok then
		return false, reason
	end
	local hasItem, itemId = Actions.pickItem(def, itemPicker(player))
	if not hasItem then
		local needed = def.items and def.items[1]
		return false, "Requires " .. (if needed and Items[needed] then Items[needed].name else "an item")
	end
	return true, nil, itemId
end

function ActionRunner.isBusy(player: Player): boolean
	return running[player] ~= nil
end

function ActionRunner.cancel(player: Player)
	local job = running[player]
	if job then
		job.cancelled = true
	end
end

local function setClip(player: Player, clip: string?)
	local char = player.Character
	if not char or char:GetAttribute("MedAnim") == clip then
		return
	end
	char:SetAttribute("MedAnim", clip)
	char:SetAttribute("MedAnimT", if clip then workspace:GetServerTimeNow() else nil)
end

local function patientDown(record): boolean
	local s = record.state
	return not s.alive or not s.conscious or record.model:GetAttribute("MedRagdoll") == true
end

local function finish(player: Player, job)
	setClip(player, nil)
	if running[player] == job then
		running[player] = nil
	end
	if job.def.cpr and job.record.state.cpr and job.record.state.cpr.medic == player then
		job.record.state.cpr = nil
	end
	if player.Parent then
		progressRemote:FireClient(player, nil)
	end
end

local function runOnce(player: Player, record, def, part: string, job): boolean
	local ok, reason, _ = check(player, record, def, part)
	if not ok then
		MedicalService.notify(player, reason or "Not possible", "error")
		return false
	end
	local ctx = makeContext(player, record, part)
	local duration = Actions.duration(def, ctx)
	local startPos = rootPosition(player)
	if def.cpr then
		record.state.cpr = { level = ctx.medicLevel, medic = player }
	end
	local label = def.name .. (if record.player == player then "" else " - " .. BodyParts.DisplayName[part])
	progressRemote:FireClient(player, { label = label, duration = duration, repeating = def.cpr == true })

	local fx = ActionFx.get(def)
	local medicChar = player.Character
	local medicHumanoid = medicChar and medicChar:FindFirstChildOfClass("Humanoid")
	if medicHumanoid then
		medicHumanoid:UnequipTools()
	end
	local isSelf = record.player == player
	setClip(player, ActionFx.base(fx, isSelf, patientDown(record)) .. "." .. fx.motion)
	local soundAt = MedicalService.rootOf(record) or (medicChar and medicChar:FindFirstChild("HumanoidRootPart"))
	if fx.start then
		Sounds.play(fx.start, soundAt)
	end
	local nextLoop = fx.interval or math.huge

	local elapsed = 0
	while elapsed < duration do
		elapsed += task.wait(0.1)
		if job.cancelled or not player.Parent or not record.model.Parent then
			return false
		end
		if MedicalService.isIncapacitated(player) then
			return false
		end
		local pos = rootPosition(player)
		if record.player ~= player and MedicalService.distance(player, record) > Config.MaxTreatmentDistance then
			MedicalService.notify(player, "Moved too far from the patient", "error")
			return false
		end
		if startPos and pos and (pos - startPos).Magnitude > Config.CancelMoveDistance then
			MedicalService.notify(player, "Treatment interrupted - you moved", "error")
			return false
		end
		if fx.loop and fx.interval and elapsed >= nextLoop then
			Sounds.play(fx.loop, soundAt)
			nextLoop += fx.interval
		end
	end

	local ok2, reason2, itemId = check(player, record, def, part)
	if not ok2 then
		MedicalService.notify(player, reason2 or "Not possible", "error")
		return false
	end
	if itemId and not Inventory.take(player, itemId) then
		MedicalService.notify(player, "Missing item", "error")
		return false
	end

	if def.server then
		local started, why = Carry.start(player, record, def.server)
		if not started then
			MedicalService.notify(player, why or "Cannot move patient", "error")
			return false
		end
	end

	local execCtx = makeContext(player, record, part)
	local success, result = pcall(Actions.execute, def, execCtx)
	if not success then
		warn("[Medical] action " .. def.id .. " failed: " .. tostring(result))
		MedicalService.notify(player, "Treatment failed", "error")
		return false
	end
	if ActionFx.isShock(def.id, result) then
		Sounds.play("AedShock", soundAt)
	elseif fx.finish then
		Sounds.play(fx.finish, soundAt)
	end
	if def.refund then
		for _, refundId in def.refund do
			if not (Items[refundId] and Items[refundId].reusable) then
				Inventory.give(player, refundId, 1)
			end
		end
	end
	if execCtx.grant then
		for grantId, n in execCtx.grant do
			Inventory.give(player, grantId, n)
		end
	end
	if def.hold and def.id == "HeadTilt" then
		record.headTiltHolder = player
	end
	if result then
		MedicalService.notify(player, result, "result")
		if record.player and record.player ~= player then
			MedicalService.notify(record.player, string.format("%s: %s", player.DisplayName, result), "info")
		end
	end
	MedicalService.pushView(record)
	return true
end

function ActionRunner.request(player: Player, model: Instance?, actionId: string, part: string)
	if typeof(actionId) ~= "string" or typeof(part) ~= "string" then
		return
	end
	if running[player] then
		MedicalService.notify(player, "Already busy", "error")
		return
	end
	local record = MedicalService.get(model)
	if not record then
		return
	end
	local def = Actions.ById[actionId]
	if not def or not BodyParts.isValid(part) then
		return
	end
	if def.id ~= "ReleaseHeadTilt" then
		MedicalService.releaseHeadTilt(player)
	end
	if Carry.isCarrying(player) and def.server == nil then
		MedicalService.notify(player, "Put the patient down first (G)", "error")
		return
	end

	local job = { cancelled = false, record = record, def = def }
	running[player] = job
	task.spawn(function()
		local ok, err = pcall(function()
			repeat
				local done = runOnce(player, record, def, part, job)
				local again = done
					and def.cpr
					and record.state.arrest ~= nil
					and record.state.alive
					and not job.cancelled
			until not again
		end)
		if not ok then
			warn("[Medical] " .. tostring(err))
		end
		finish(player, job)
	end)
end

MedicalService.onIncapacitated = function(player: Player)
	ActionRunner.cancel(player)
	MedicalService.releaseHeadTilt(player)
	Carry.drop(player)
end

MedicalService.onRecordRemoved = function(record)
	Carry.dropRecord(record)
	if record.player then
		ActionRunner.cancel(record.player)
		Carry.drop(record.player)
		MedicalService.releaseHeadTilt(record.player)
	end
	for player, job in running do
		if job.record == record then
			job.cancelled = true
		end
		local _ = player
	end
end

return ActionRunner
