local RunService = game:GetService("RunService")

local Animations = {}
Animations.__index = Animations

local function smoothstep(value)
	local t = math.clamp(value, 0, 1)
	return t * t * (3 - 2 * t)
end

local function play(handle, name)
	local effect = handle:FindFirstChild(name)
	if effect and effect:IsA("Sound") and effect.SoundId ~= "" then
		effect:Play()
	end
end

function Animations.new(tool)
	assert(tool:IsA("Tool") and tool:GetAttribute("WeaponAsset"), "Expected a WeaponAssets Tool")
	local handle = tool:WaitForChild("Handle")
	local kind = tool:GetAttribute("WeaponAsset")
	return setmetatable({
		tool = tool,
		handle = handle,
		kind = kind,
		baseGrip = tool.Grip,
		magazine = handle:WaitForChild("MagazineMotor"),
		bolt = handle:WaitForChild(kind == "pistol" and "SlideMotor" or "ChargingBoltMotor"),
		trigger = handle:WaitForChild("TriggerMotor"),
		connection = nil,
		aiming = false,
		aimAmount = 0,
		kick = 0,
		shotAt = -math.huge,
		reloadAt = nil,
		equipAt = 0,
	}, Animations)
end

function Animations:_step(dt)
	local now = os.clock()
	local reloadLength = self.kind == "carbine" and 1.15 or 0.95
	local reload = self.reloadAt and (now - self.reloadAt) / reloadLength or nil
	if reload and reload >= 1 then
		self.reloadAt = nil
		reload = nil
	end

	self.aimAmount += ((self.aiming and 1 or 0) - self.aimAmount) * (1 - math.exp(-12 * dt))
	self.kick *= math.exp(-19 * dt)
	local equip = smoothstep((now - self.equipAt) / 0.32)
	local tilt = 0
	local magazineDrop = 0
	local boltTravel = 0
	if reload then
		tilt = math.sin(reload * math.pi) * 0.23
		magazineDrop = smoothstep((reload - 0.08) / 0.22) * (1 - smoothstep((reload - 0.47) / 0.21))
		boltTravel = smoothstep((reload - 0.72) / 0.08) * (1 - smoothstep((reload - 0.82) / 0.11))
	end
	local shot = math.clamp((now - self.shotAt) / 0.13, 0, 1)
	boltTravel = math.max(boltTravel, (1 - shot) * (1 - shot))
	self.magazine.Transform = CFrame.new(0, -magazineDrop * (self.kind == "carbine" and 0.95 or 0.72), 0)
	self.bolt.Transform = CFrame.new(0, 0, boltTravel * (self.kind == "carbine" and 0.2 or 0.3))
	self.trigger.Transform = CFrame.Angles(-self.kick * 0.18, 0, 0)
	self.tool.Grip = self.baseGrip
		* CFrame.new(
			0,
			-0.28 * (1 - equip) + self.aimAmount * 0.09,
			0.14 * (1 - equip) - self.aimAmount * 0.14 + self.kick * 0.11
		)
		* CFrame.Angles(0.2 * (1 - equip) - self.aimAmount * 0.07 + self.kick * 0.12 + tilt, 0, tilt * 0.55)
end

function Animations:equip()
	if self.connection then
		return
	end
	self.equipAt = os.clock()
	self.connection = RunService.RenderStepped:Connect(function(dt)
		self:_step(dt)
	end)
	play(self.handle, "Equip")
end

function Animations:setAiming(aiming)
	self.aiming = aiming == true
end

function Animations:fire()
	if not self.connection or self.reloadAt then
		return false
	end
	self.shotAt = os.clock()
	self.kick = math.min(self.kick + 1, 1.5)
	play(self.handle, "Fire")
	return true
end

function Animations:dryFire()
	if self.connection then
		play(self.handle, "DryFire")
	end
end

function Animations:reload()
	if not self.connection or self.reloadAt then
		return false
	end
	self.reloadAt = os.clock()
	play(self.handle, "Reload")
	return true
end

function Animations:unequip()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.aiming = false
	self.aimAmount = 0
	self.kick = 0
	self.reloadAt = nil
	self.tool.Grip = self.baseGrip
	self.magazine.Transform = CFrame.identity
	self.bolt.Transform = CFrame.identity
	self.trigger.Transform = CFrame.identity
end

function Animations:destroy()
	self:unequip()
end

return Animations
