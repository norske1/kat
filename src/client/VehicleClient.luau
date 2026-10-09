--!nonstrict
-- Driving / flying (the driver's client owns the vehicle and sets its drive constraints), the mounted gun for the
-- gunner seat, and the vehicle HUD.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Remotes = require(Medical.Remotes)
local VehicleConfig = require(Medical.Vehicles.Config)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

local VehicleClient = {}

local player = Players.LocalPlayer
local speed = 0
local firing = false
local lastAim, lastShot = 0, 0

local function key(code: Enum.KeyCode): number
	return if UserInputService:GetFocusedTextBox() == nil and UserInputService:IsKeyDown(code) then 1 else 0
end

local function drive(dt: number, def, seat: VehicleSeat, hull: BasePart)
	local lv = hull:FindFirstChild("Drive") :: LinearVelocity?
	local av = hull:FindFirstChild("Turn") :: AngularVelocity?
	if not lv or not av then
		return
	end
	local throttle, steer = seat.ThrottleFloat, seat.SteerFloat
	local target = if throttle > 0 then throttle * def.speed elseif throttle < 0 then throttle * def.reverse else 0
	local rate = def.accel * (if target == 0 then 1.5 else 1)
	speed += math.clamp(target - speed, -rate * dt, rate * dt)
	local look = hull.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	if def.kind == "car" then
		lv.PlaneVelocity = Vector2.new(flat.X * speed, flat.Z * speed)
		local grip = math.clamp(math.abs(speed) / 12, 0, 1)
		local reverse = if speed < -0.5 then -1 else 1
		av.AngularVelocity = Vector3.new(0, -steer * def.turn * grip * reverse, 0)
	else
		local climb = key(VehicleConfig.ClimbUp) - key(VehicleConfig.ClimbDown)
		lv.VectorVelocity = flat * speed + Vector3.yAxis * climb * (def.climb or 30)
		av.AngularVelocity = Vector3.new(0, -steer * def.turn, 0)
	end
end

function VehicleClient.init(screen: ScreenGui)
	local remote = Remotes.get("Vehicle")
	local hud = Ui.label({
		Name = "VehicleHud",
		Text = "",
		RichText = true,
		Font = T.FontBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),
		Size = UDim2.fromOffset(640, 44),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		Parent = screen,
	})
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			firing = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			firing = false
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		local model = seat and seat:FindFirstAncestorOfClass("Model")
		local def = model and VehicleConfig.Types[model:GetAttribute("Vehicle") or ""]
		if not def or not model.PrimaryPart then
			hud.Visible = false
			speed = 0
			return
		end
		local hull = model.PrimaryPart
		local role = seat:GetAttribute("Role")
		local hint = "F: switch seat   Space: get out"
		if role == "driver" and seat:IsA("VehicleSeat") then
			drive(dt, def, seat, hull)
			hint = if def.kind == "heli"
				then "W/S: speed   A/D: turn   E/Q: climb / descend   Space: get out"
				else "WASD: drive   F: switch seat   Space: get out"
		elseif role == "gunner" and def.turret then
			local dir = workspace.CurrentCamera.CFrame.LookVector
			local now = os.clock()
			if firing and now - lastShot >= 60 / def.turret.rpm then
				lastShot = now
				remote:FireServer("fire", model, dir)
			elseif now - lastAim > 0.1 then
				lastAim = now
				remote:FireServer("aim", model, dir)
			end
			hint = "Mouse: aim   Left click: fire   F: switch seat"
		end
		local hp = (model:GetAttribute("Health") or 0) / math.max(1, model:GetAttribute("MaxHealth") or 1)
		local kmh = hull.AssemblyLinearVelocity.Magnitude * 0.28 * 3.6
		local cargo = model:GetAttribute("SupplyCap") or 0
		local cargoText = if cargo > 0
			then string.format("   SUPPLIES %d/%d", model:GetAttribute("Supplies") or 0, cargo)
			else ""
		hud.Text = string.format(
			'%s  [%s]   HP %d%%   %d km/h%s\n<font size="12">%s</font>',
			string.upper(def.name),
			string.upper(role or ""),
			math.floor(hp * 100 + 0.5),
			math.floor(kmh + 0.5),
			cargoText,
			hint
		)
		hud.Visible = true
	end)
end

return VehicleClient
