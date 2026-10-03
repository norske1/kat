--!nonstrict
-- Screen effects for the local player: pain, blood loss, hypoxia, unconsciousness.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Ui = require(script.Parent.Ui)

local Effects = {}

local blur, color, overlay, blackout, causesLabel, vignette
local current = nil
local painFlash = 0
local lastPain = 0

function Effects.init(screen: ScreenGui)
	blur = Instance.new("BlurEffect")
	blur.Name = "MedicalBlur"
	blur.Size = 0
	blur.Parent = Lighting
	color = Instance.new("ColorCorrectionEffect")
	color.Name = "MedicalColor"
	color.Parent = Lighting

	overlay = Ui.make("Frame", {
		Name = "Effects",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = screen,
	})
	-- red vignette made from four gradient edges
	vignette = {}
	local edges = {
		{ UDim2.new(1, 0, 0.35, 0), UDim2.new(0, 0, 0, 0), 90 },
		{ UDim2.new(1, 0, 0.35, 0), UDim2.new(0, 0, 0.65, 0), -90 },
		{ UDim2.new(0.3, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 },
		{ UDim2.new(0.3, 0, 1, 0), UDim2.new(0.7, 0, 0, 0), 180 },
	}
	for _, e in edges do
		local f = Ui.make("Frame", {
			Size = e[1],
			Position = e[2],
			BackgroundColor3 = Color3.fromRGB(140, 0, 0),
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
			Parent = overlay,
		})
		Ui.make("UIGradient", {
			Rotation = e[3],
			Transparency = NumberSequence.new(0, 1),
			Parent = f,
		})
		table.insert(vignette, f)
	end

	blackout = Ui.make("Frame", {
		Name = "Blackout",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Visible = false,
		Parent = screen,
	})
	Ui.label({
		Text = "UNCONSCIOUS",
		Font = Ui.Theme.FontBold,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0.42, 0),
		TextColor3 = Color3.fromRGB(180, 180, 180),
		ZIndex = 51,
		Parent = blackout,
	})
	causesLabel = Ui.label({
		Text = "",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.new(0, 0, 0.42, 44),
		TextColor3 = Color3.fromRGB(130, 130, 130),
		ZIndex = 51,
		Parent = blackout,
	})

	RunService.RenderStepped:Connect(function(dt)
		Effects.render(dt)
	end)
end

function Effects.update(data)
	current = data
	if data and data.pain > lastPain + 0.08 then
		painFlash = 1
	end
	lastPain = if data then data.pain else 0
end

function Effects.render(dt: number)
	local d = current
	if not d or not blur then
		return
	end
	painFlash = math.max(0, painFlash - dt * 1.5)
	local down = not d.conscious or not d.alive
	blackout.Visible = down
	if down then
		blackout.BackgroundTransparency = 0.04
		if not d.alive then
			causesLabel.Text = "You died."
		elseif d.arrest then
			causesLabel.Text = "Your heart has stopped.\nOnly a medic can save you now."
		else
			causesLabel.Text = table.concat(d.causes or {}, ", ") .. "\nWaiting for medical attention..."
		end
	end
	local heartbeat = 0
	if d.heartRate > 0 then
		local t = os.clock() * d.heartRate / 60
		heartbeat = math.max(0, math.sin(t * math.pi * 2)) ^ 8
	end
	local pain = d.pain
	local vignetteAlpha = math.clamp(pain * 0.6 + d.bloodLoss * 0.3 + painFlash * 0.5 + heartbeat * pain * 0.2, 0, 0.85)
	for _, f in vignette do
		f.BackgroundTransparency = 1 - vignetteAlpha
	end
	blur.Size = math.clamp(d.bloodLoss * 8 + d.hypoxia * 14 + d.opioid * 6 + painFlash * 4, 0, 24)
	color.Saturation = -math.clamp(d.bloodLoss * 0.8 + d.hypoxia * 0.6, 0, 1)
	color.Brightness = -math.clamp(d.hypoxia * 0.25 + d.bloodLoss * 0.1, 0, 0.4)
	color.Contrast = math.clamp(d.opioid * 0.2, 0, 0.3)
end

return Effects
