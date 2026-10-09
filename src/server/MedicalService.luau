--!nonstrict
-- Owns every patient's medical state on the server, runs the simulation and syncs it to clients.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Config = require(Medical.Config)
local BodyParts = require(Medical.BodyParts)
local Remotes = require(Medical.Remotes)
local Sounds = require(Medical.Sounds)
local Patient = require(Medical.Sim.Patient)
local Simulation = require(Medical.Sim.Simulation)
local Damage = require(Medical.Sim.Damage)
local Snapshot = require(Medical.Sim.Snapshot)
local Ragdoll = require(script.Parent.Ragdoll)
local Inventory = require(script.Parent.Inventory)

local MedicalService = {}

export type Record = {
	model: Model,
	humanoid: Humanoid,
	player: Player?,
	state: any,
	viewers: { [Player]: boolean },
	prompt: ProximityPrompt?,
	headTiltHolder: Player?,
	carrier: Player?,
	dead: boolean,
	connections: { RBXScriptConnection },
	baseWalkSpeed: number,
	baseJumpPower: number,
	baseJumpHeight: number,
	lastVelocityY: number,
	bloodEmitter: ParticleEmitter?,
}

local records: { [Model]: Record } = {}
local viewing: { [Player]: Record } = {}

local viewRemote = Remotes.get("View")
local effectsRemote = Remotes.get("Effects")
local notifyRemote = Remotes.get("Notify")

MedicalService.records = records

-- Hooks filled in by other modules to avoid require cycles
MedicalService.onIncapacitated = function(_player: Player) end
MedicalService.onRecordRemoved = function(_record: Record) end

function MedicalService.medicLevel(player: Player): number
	local attr = player:GetAttribute("MedicalLevel")
	if typeof(attr) == "number" then
		return math.clamp(math.floor(attr), 0, 2)
	end
	if player.Team and Config.TeamMedicalLevels[player.Team.Name] then
		return Config.TeamMedicalLevels[player.Team.Name]
	end
	if RunService:IsStudio() then
		return Config.StudioMedicalLevel
	end
	return Config.DefaultMedicalLevel
end

function MedicalService.debugAllowed(player: Player): boolean
	if table.find(Config.AdminUserIds, player.UserId) then
		return true
	end
	return Config.DebugToolsInStudio and RunService:IsStudio()
end

Inventory.levelOf = MedicalService.medicLevel
Inventory.debugAllowed = MedicalService.debugAllowed

function MedicalService.get(model: Instance?): Record?
	if not model then
		return nil
	end
	return records[model :: Model]
end

function MedicalService.getByPlayer(player: Player): Record?
	return if player.Character then records[player.Character] else nil
end

function MedicalService.notify(player: Player?, text: string, kind: string?)
	if player and player.Parent then
		notifyRemote:FireClient(player, text, kind or "info")
	end
end

-- A player that cannot act (unconscious, dead or not spawned).
function MedicalService.isIncapacitated(player: Player): boolean
	local record = MedicalService.getByPlayer(player)
	if not record then
		return true
	end
	return not record.state.alive or not record.state.conscious
end

function MedicalService.rootOf(record: Record): BasePart?
	return record.model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function MedicalService.distance(player: Player, record: Record): number
	local medicChar = player.Character
	local medicRoot = medicChar and medicChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local root = MedicalService.rootOf(record)
	if not medicRoot or not root then
		return math.huge
	end
	return (medicRoot.Position - root.Position).Magnitude
end

local function displayName(record: Record): string
	if record.player then
		return record.player.DisplayName
	end
	return record.model.Name
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------
function MedicalService.buildView(player: Player, record: Record)
	local isSelf = record.player == player
	local level = MedicalService.medicLevel(player)
	local view = Snapshot.build(record.state, {
		viewerLevel = level,
		isSelf = isSelf,
		infinite = Config.InfiniteSupplies,
		inventoryHas = function(itemId)
			return Inventory.has(player, itemId)
		end,
	})
	view.name = displayName(record)
	view.target = record.model
	view.isSelf = isSelf
	view.level = level
	view.carried = record.carrier ~= nil
	return view
end

function MedicalService.pushView(record: Record)
	for player in record.viewers do
		viewRemote:FireClient(player, MedicalService.buildView(player, record))
	end
end

function MedicalService.closeView(player: Player)
	local record = viewing[player]
	if record then
		record.viewers[player] = nil
		viewing[player] = nil
	end
	viewRemote:FireClient(player, nil)
end

function MedicalService.openView(player: Player, record: Record): (boolean, string?)
	if MedicalService.isIncapacitated(player) then
		return false, "You are incapacitated"
	end
	if record.player ~= player and MedicalService.distance(player, record) > Config.MaxTreatmentDistance then
		return false, "Too far away"
	end
	if viewing[player] and viewing[player] ~= record then
		viewing[player].viewers[player] = nil
	end
	viewing[player] = record
	record.viewers[player] = true
	viewRemote:FireClient(player, MedicalService.buildView(player, record))
	return true
end

function MedicalService.viewingOf(player: Player): Record?
	return viewing[player]
end

---------------------------------------------------------------------------
-- Damage
---------------------------------------------------------------------------
function MedicalService.applyDamage(model: Model, bodyPart: string?, amount: number, damageType: string?)
	local record = records[model]
	if not record or not record.state.alive or amount <= 0 then
		return
	end
	local part = bodyPart
	if part and not BodyParts.isValid(part) then
		part = BodyParts.fromInstanceName(part)
	end
	if part then
		Damage.apply(record.state, part, amount, damageType)
	else
		Damage.applySpread(record.state, amount, damageType)
	end
	local now = os.clock()
	if amount >= 5 and record.state.alive and record.state.conscious and now - (record.lastHurtSound or 0) > 0.7 then
		record.lastHurtSound = now
		Sounds.play("Hurt", record.model:FindFirstChild("Head"))
	end
end

local function onHealthChanged(record: Record)
	if record.dead then
		return
	end
	local humanoid = record.humanoid
	local delta = Config.HealthBuffer - humanoid.Health
	if delta > 0.01 then
		local hitPart = humanoid:GetAttribute("MedicalHitPart")
		local damageType = humanoid:GetAttribute("MedicalDamageType")
		humanoid:SetAttribute("MedicalHitPart", nil)
		humanoid:SetAttribute("MedicalDamageType", nil)
		humanoid.Health = Config.HealthBuffer
		if Config.InterceptHumanoidDamage then
			MedicalService.applyDamage(record.model, hitPart, delta, damageType)
		end
	elseif delta < 0 then
		humanoid.Health = Config.HealthBuffer
	end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local function makeBloodEmitter(root: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MedicalBlood"
	emitter.Color = ColorSequence.new(Color3.fromRGB(110, 0, 0))
	emitter.LightEmission = 0
	emitter.Size = NumberSequence.new(0.12, 0.05)
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Acceleration = Vector3.new(0, -workspace.Gravity * 0.5, 0)
	emitter.Rate = 0
	emitter.Parent = root
	return emitter
end

local function makePrompt(record: Record): ProximityPrompt?
	local root = MedicalService.rootOf(record)
	if not root then
		return nil
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MedicalPrompt"
	prompt.ActionText = "Treat"
	prompt.ObjectText = displayName(record)
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.MaxTreatmentDistance
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("MedicalOwner", if record.player then record.player.UserId else 0)
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		if player == record.player then
			return
		end
		local ok, reason = MedicalService.openView(player, record)
		if not ok then
			MedicalService.notify(player, reason or "Cannot treat", "error")
		end
	end)
	return prompt
end

function MedicalService.register(model: Model, player: Player?, options: { bloodType: string? }?): Record?
	if records[model] then
		return records[model]
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 10)
	if not humanoid then
		return nil
	end
	local state = Patient.new({ bloodType = options and options.bloodType, seed = math.random(1, 2 ^ 30) })
	local record: Record = {
		model = model,
		humanoid = humanoid :: Humanoid,
		player = player,
		state = state,
		viewers = {},
		prompt = nil,
		headTiltHolder = nil,
		carrier = nil,
		dead = false,
		connections = {},
		baseWalkSpeed = (humanoid :: Humanoid).WalkSpeed,
		baseJumpPower = (humanoid :: Humanoid).JumpPower,
		baseJumpHeight = (humanoid :: Humanoid).JumpHeight,
		lastVelocityY = 0,
		bloodEmitter = nil,
	}
	records[model] = record

	local h = record.humanoid
	h.BreakJointsOnDeath = false
	h.RequiresNeck = false
	h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	h:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	h.MaxHealth = Config.HealthBuffer
	h.Health = Config.HealthBuffer
	model:SetAttribute("MedicalManaged", true)

	table.insert(
		record.connections,
		h.HealthChanged:Connect(function()
			onHealthChanged(record)
		end)
	)
	table.insert(
		record.connections,
		model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				MedicalService.unregister(model)
			end
		end)
	)

	local root = MedicalService.rootOf(record)
	if root and Config.BloodEffects then
		record.bloodEmitter = makeBloodEmitter(root)
	end
	record.prompt = makePrompt(record)
	return record
end

function MedicalService.unregister(model: Model)
	local record = records[model]
	if not record then
		return
	end
	records[model] = nil
	for _, c in record.connections do
		c:Disconnect()
	end
	for viewer in record.viewers do
		viewing[viewer] = nil
		if viewer.Parent then
			viewRemote:FireClient(viewer, nil)
		end
	end
	MedicalService.onRecordRemoved(record)
end

---------------------------------------------------------------------------
-- Applying simulation state to the character
---------------------------------------------------------------------------
local function setAttributes(record: Record)
	local s = record.state
	local m = record.model
	m:SetAttribute("MedAlive", s.alive)
	m:SetAttribute("MedConscious", s.conscious)
	m:SetAttribute("MedInArrest", s.arrest ~= nil)
	m:SetAttribute("MedBleeding", s.bleedRate > 0.00001)
	m:SetAttribute("MedTriage", s.triage)
	m:SetAttribute("MedBloodVolume", math.floor(s.bloodVolume * 100) / 100)
end

function MedicalService.movementMultiplier(record: Record): number
	local s = record.state
	local mult = 1
	for _, leg in { "LeftLeg", "RightLeg" } do
		local part = s.parts[leg]
		if part.fracture ~= 0 then
			mult = math.min(mult, if part.splint then Config.SplintedLegSpeed else Config.FracturedLegSpeed)
		end
	end
	if s.painPerceived > 0.6 then
		mult *= 0.85
	end
	if s.bloodVolume < Config.BloodClass2 then
		mult *= 0.8
	end
	local move = record.model:GetAttribute("MoveSpeed") or 1
	if mult < 0.95 then
		move = math.min(move, 1) -- no sprinting while injured
	end
	return mult
		* move
		* (record.model:GetAttribute("MedCarryMultiplier") or 1)
		* (record.model:GetAttribute("GearSpeed") or 1)
end

-- Re-applies walk speed right away (sprint / crouch changes) instead of waiting for the next tick.
function MedicalService.refreshMovement(model: Model)
	local record = MedicalService.get(model)
	if record and record.state.alive and record.state.conscious and not record.carrier then
		record.humanoid.WalkSpeed = record.baseWalkSpeed * MedicalService.movementMultiplier(record)
	end
end

local function applyToCharacter(record: Record)
	local s = record.state
	local h = record.humanoid
	setAttributes(record)

	if not s.alive then
		if not record.dead then
			record.dead = true
			Ragdoll.set(record.model, true)
			h:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
			h.Health = 0
			if record.prompt then
				record.prompt.ActionText = "Examine"
			end
		end
		return
	end

	local down = not s.conscious
	Ragdoll.set(record.model, down or record.carrier ~= nil)
	if down then
		h.WalkSpeed = 0
		h.JumpPower = 0
		h.JumpHeight = 0
	else
		h.WalkSpeed = record.baseWalkSpeed * MedicalService.movementMultiplier(record)
		h.JumpPower = record.baseJumpPower
		h.JumpHeight = record.baseJumpHeight
	end
	if record.bloodEmitter then
		local rate = s.bleedRate
		record.bloodEmitter.Rate = if rate <= 0.00001 then 0 else math.clamp(rate * 2500, 2, 40)
	end
end

local function handleEvents(record: Record)
	local events = Patient.drainEvents(record.state)
	for _, e in events do
		if e.name == "Unconscious" or e.name == "Died" then
			Sounds.play("BodyFall", record.model:FindFirstChild("HumanoidRootPart"))
		end
		if e.name == "Unconscious" or e.name == "Died" or e.name == "CardiacArrest" then
			if record.player then
				MedicalService.onIncapacitated(record.player)
				if viewing[record.player] then
					MedicalService.closeView(record.player)
				end
			end
		end
		if e.name == "Reopened" and record.player then
			MedicalService.notify(record.player, "A bandage came loose", "warn")
		end
	end
end

local function checkFallDamage(record: Record)
	if not Config.FallDamageEnabled then
		return
	end
	local root = MedicalService.rootOf(record)
	if not root then
		return
	end
	local vy = root.AssemblyLinearVelocity.Y
	local last = record.lastVelocityY
	record.lastVelocityY = vy
	if last < -Config.FallDamageMinVelocity and vy > last * 0.3 and record.carrier == nil then
		local amount = (-last - Config.FallDamageMinVelocity) * Config.FallDamagePerVelocity
		if amount > 1 then
			MedicalService.applyDamage(record.model, nil, amount, "Fall")
		end
	end
end

local function checkHeadTilt(record: Record)
	local holder = record.headTiltHolder
	if not holder then
		return
	end
	local a = record.state.airway
	if not a.headTilt then
		record.headTiltHolder = nil
		return
	end
	if
		not holder.Parent
		or MedicalService.isIncapacitated(holder)
		or MedicalService.distance(holder, record) > Config.HeadTiltRange
	then
		a.headTilt = false
		record.headTiltHolder = nil
		Patient.log(record.state, "Head tilt released")
		MedicalService.notify(holder, "You let go of the patient's head", "warn")
	end
end

function MedicalService.releaseHeadTilt(player: Player)
	for _, record in records do
		if record.headTiltHolder == player then
			record.state.airway.headTilt = false
			record.headTiltHolder = nil
			Patient.log(record.state, "Head tilt released")
		end
	end
end

local function pruneViewers(record: Record)
	for viewer in record.viewers do
		local keep = viewer.Parent ~= nil and not MedicalService.isIncapacitated(viewer)
		if
			keep
			and viewer ~= record.player
			and MedicalService.distance(viewer, record) > Config.MaxTreatmentDistance * 1.5
		then
			keep = false
		end
		if not keep then
			MedicalService.closeView(viewer)
		end
	end
end

function MedicalService.start()
	local tickAccumulator = 0
	local viewAccumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		for _, record in records do
			checkFallDamage(record)
		end
		tickAccumulator += dt
		viewAccumulator += dt
		if tickAccumulator >= Config.TickInterval then
			local step = tickAccumulator
			tickAccumulator = 0
			for _, record in records do
				if record.state.alive then
					local ok, err = pcall(Simulation.step, record.state, step)
					if not ok then
						warn("[Medical] simulation error: " .. tostring(err))
					end
				end
				checkHeadTilt(record)
				handleEvents(record)
				applyToCharacter(record)
				if record.player then
					effectsRemote:FireClient(record.player, Snapshot.selfEffects(record.state))
				end
			end
		end
		if viewAccumulator >= Config.ViewInterval then
			viewAccumulator = 0
			for _, record in records do
				pruneViewers(record)
				if next(record.viewers) then
					MedicalService.pushView(record)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		MedicalService.closeView(player)
		MedicalService.releaseHeadTilt(player)
	end)
end

function MedicalService.heal(model: Model)
	local record = records[model]
	if not record then
		return
	end
	if record.dead then
		return
	end
	Patient.fullHeal(record.state)
	record.headTiltHolder = nil
	applyToCharacter(record)
end

return MedicalService
