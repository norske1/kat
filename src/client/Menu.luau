--!nonstrict
-- The KAT-style medical menu: body diagram, action categories, injuries, vitals monitor and log.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Medical = ReplicatedStorage:WaitForChild("Medical")
local BodyParts = require(Medical.BodyParts)
local Remotes = require(Medical.Remotes)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

local Menu = {}

local window, modalButton
local titleLabel, triageLabel
local partButtons = {}
local categoryBar, actionList
local statusLabel, partTitle, partDetails, airwayLabel, medsLabel, logList
local monitor = {}
local ecgBars = {}

local view = nil
local selectedPart = "Torso"
local selectedCategory = "All"
local lastActionSignature = ""
local lastLogSignature = ""

local CATEGORY_LABELS = {
	All = "All",
	Examine = "Examine",
	Bandage = "Bandage",
	Medication = "Meds",
	Airway = "Airway",
	Breathing = "Breathing",
	Circulation = "Circulation",
	Pharmacy = "Pharmacy",
	Fluids = "Fluids",
	Surgery = "Surgery",
	Other = "Other",
}
local CATEGORY_ORDER = {
	"All",
	"Examine",
	"Bandage",
	"Medication",
	"Airway",
	"Breathing",
	"Circulation",
	"Pharmacy",
	"Fluids",
	"Surgery",
	"Other",
}
local TRIAGE_COLORS = {
	None = T.PanelLight,
	Minimal = Color3.fromRGB(60, 160, 70),
	Delayed = Color3.fromRGB(220, 180, 40),
	Immediate = Color3.fromRGB(200, 40, 45),
	Deceased = Color3.fromRGB(15, 15, 15),
}

local BLEED_COLORS = {
	[0] = Color3.fromRGB(70, 76, 88),
	[1] = Color3.fromRGB(150, 90, 70),
	[2] = Color3.fromRGB(190, 55, 45),
	[3] = Color3.fromRGB(235, 20, 20),
}

local function panel(props)
	local f = Ui.make("Frame", {
		BackgroundColor3 = T.Panel,
		BorderSizePixel = 0,
	})
	for k, v in props do
		(f :: any)[k] = v
	end
	Ui.corner(6).Parent = f
	return f
end

local function buildBody(parent)
	local body =
		panel({ Name = "Body", Size = UDim2.new(0, 190, 0, 330), Position = UDim2.new(0, 10, 0, 50), Parent = parent })
	Ui.label({
		Text = "Body",
		Font = T.FontBold,
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.new(0, 8, 0, 4),
		Parent = body,
	})
	local layout = {
		Head = { UDim2.new(0, 70, 0, 30), UDim2.new(0, 50, 0, 46) },
		Torso = { UDim2.new(0, 60, 0, 82), UDim2.new(0, 70, 0, 100) },
		LeftArm = { UDim2.new(0, 132, 0, 82), UDim2.new(0, 30, 0, 110) },
		RightArm = { UDim2.new(0, 28, 0, 82), UDim2.new(0, 30, 0, 110) },
		LeftLeg = { UDim2.new(0, 97, 0, 186), UDim2.new(0, 33, 0, 120) },
		RightLeg = { UDim2.new(0, 60, 0, 186), UDim2.new(0, 33, 0, 120) },
	}
	for name, l in layout do
		local b = Ui.button({
			Name = name,
			Text = "",
			Position = l[1],
			Size = l[2],
			BackgroundColor3 = BLEED_COLORS[0],
			Parent = body,
		})
		local stroke = Ui.make("UIStroke", { Thickness = 2, Color = Color3.new(1, 1, 1), Transparency = 1, Parent = b })
		local badge = Ui.label({
			Name = "Badge",
			Text = "",
			Font = T.FontBold,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Size = UDim2.new(1, 0, 1, -2),
			Parent = b,
		})
		b.Activated:Connect(function()
			selectedPart = name
			lastActionSignature = ""
			Menu.render()
		end)
		partButtons[name] = { button = b, stroke = stroke, badge = badge }
	end
	Ui.label({
		Text = "Viewer: left/right as seen from the front",
		TextSize = 10,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, -12, 0, 24),
		Position = UDim2.new(0, 8, 1, -26),
		Parent = body,
	})
end

local function buildMonitor(parent)
	local m = Ui.make("Frame", {
		Name = "Monitor",
		Size = UDim2.new(1, -16, 0, 150),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundColor3 = T.Monitor,
		Parent = parent,
	}, { Ui.corner(4) })
	monitor.source = Ui.label({
		Text = "",
		TextSize = 11,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, -10, 0, 14),
		Position = UDim2.new(0, 6, 0, 2),
		Parent = m,
	})
	local function value(name, pos, color)
		Ui.label({
			Text = name,
			TextSize = 11,
			TextColor3 = color,
			Size = UDim2.new(0, 60, 0, 12),
			Position = pos,
			Parent = m,
		})
		return Ui.label({
			Text = "--",
			Font = T.FontMono,
			TextSize = 22,
			TextColor3 = color,
			Size = UDim2.new(0, 80, 0, 24),
			Position = pos + UDim2.new(0, 0, 0, 12),
			Parent = m,
		})
	end
	monitor.hr = value("HR", UDim2.new(0, 6, 0, 18), Color3.fromRGB(80, 255, 120))
	monitor.bp = value("NIBP", UDim2.new(0, 86, 0, 18), Color3.fromRGB(255, 90, 90))
	monitor.spo2 = value("SpO2", UDim2.new(0, 196, 0, 18), Color3.fromRGB(80, 200, 255))
	monitor.rr = value("RR", UDim2.new(0, 6, 0, 56), Color3.fromRGB(255, 230, 90))
	monitor.etco2 = value("EtCO2", UDim2.new(0, 86, 0, 56), Color3.fromRGB(240, 240, 240))
	monitor.rhythm = Ui.label({
		Text = "",
		TextSize = 12,
		Font = T.FontBold,
		TextColor3 = Color3.fromRGB(80, 255, 120),
		Size = UDim2.new(0, 140, 0, 36),
		Position = UDim2.new(0, 176, 0, 58),
		Parent = m,
	})
	local ecg = Ui.make("Frame", {
		Name = "ECG",
		Size = UDim2.new(1, -12, 0, 50),
		Position = UDim2.new(0, 6, 1, -54),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = m,
	})
	for i = 1, 100 do
		ecgBars[i] = Ui.make("Frame", {
			Size = UDim2.new(0, 3, 0, 3),
			Position = UDim2.new((i - 1) / 100, 0, 0.5, 0),
			BackgroundColor3 = Color3.fromRGB(80, 255, 120),
			BorderSizePixel = 0,
			Parent = ecg,
		})
	end
end

function Menu.init(screen: ScreenGui)
	window = Ui.make("Frame", {
		Name = "MedicalMenu",
		Size = UDim2.new(0, 960, 0, 600),
		Position = UDim2.new(0.5, -480, 0.5, -300),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.03,
		Visible = false,
		ZIndex = 10,
		Parent = screen,
	}, { Ui.corner(10) })
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(960, 600), Parent = window })
	local scale = Ui.make("UIScale", { Parent = window })
	local function rescale()
		local cam = workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			scale.Scale = math.min(1, (vp.X - 20) / 960, (vp.Y - 20) / 600)
		end
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	modalButton = Ui.make("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 0),
		Modal = true,
		Visible = false,
		Parent = screen,
	})

	titleLabel = Ui.label({
		Text = "Patient",
		Font = T.FontBold,
		TextSize = 20,
		Size = UDim2.new(0, 500, 0, 30),
		Position = UDim2.new(0, 14, 0, 10),
		Parent = window,
	})
	triageLabel = Ui.label({
		Text = "No triage",
		Font = T.FontBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = T.PanelLight,
		Size = UDim2.new(0, 120, 0, 24),
		Position = UDim2.new(1, -176, 0, 13),
		Parent = window,
	})
	Ui.corner(4).Parent = triageLabel
	local close = Ui.button({
		Text = "X",
		Font = T.FontBold,
		Size = UDim2.new(0, 30, 0, 26),
		Position = UDim2.new(1, -42, 0, 12),
		BackgroundColor3 = T.Accent,
		Parent = window,
	})
	close.Activated:Connect(function()
		Menu.requestClose()
	end)

	buildBody(window)

	-- status under body
	local statusPanel =
		panel({ Size = UDim2.new(0, 190, 0, 200), Position = UDim2.new(0, 10, 0, 390), Parent = window })
	Ui.padding(8).Parent = statusPanel
	statusLabel = Ui.label({
		Text = "",
		TextSize = 13,
		Size = UDim2.new(1, 0, 1, 0),
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = statusPanel,
	})

	-- actions
	local actionsPanel =
		panel({ Size = UDim2.new(0, 360, 0, 540), Position = UDim2.new(0, 210, 0, 50), Parent = window })
	categoryBar = Ui.make("Frame", {
		Size = UDim2.new(1, -12, 0, 62),
		Position = UDim2.new(0, 6, 0, 6),
		BackgroundTransparency = 1,
		Parent = actionsPanel,
	})
	Ui.make("UIGridLayout", {
		CellSize = UDim2.new(0, 84, 0, 26),
		CellPadding = UDim2.new(0, 4, 0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = categoryBar,
	})
	for i, cat in CATEGORY_ORDER do
		local b =
			Ui.button({ Name = cat, Text = CATEGORY_LABELS[cat], TextSize = 12, LayoutOrder = i, Parent = categoryBar })
		b.Activated:Connect(function()
			selectedCategory = cat
			lastActionSignature = ""
			Menu.render()
		end)
	end
	actionList =
		Ui.scroll({ Size = UDim2.new(1, -12, 1, -82), Position = UDim2.new(0, 6, 0, 76), Parent = actionsPanel })
	Ui.list(4).Parent = actionList

	-- right column
	local right = panel({ Size = UDim2.new(0, 370, 0, 540), Position = UDim2.new(0, 580, 0, 50), Parent = window })
	buildMonitor(right)
	local info = Ui.scroll({ Size = UDim2.new(1, -16, 0, 210), Position = UDim2.new(0, 8, 0, 164), Parent = right })
	Ui.list(3).Parent = info
	partTitle = Ui.label({ Text = "", Font = T.FontBold, TextSize = 15, LayoutOrder = 1, Parent = info })
	partDetails =
		Ui.label({ Text = "", TextSize = 13, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = info })
	airwayLabel = Ui.label({
		Text = "",
		TextSize = 13,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		TextColor3 = T.TextDim,
		Parent = info,
	})
	medsLabel = Ui.label({
		Text = "",
		TextSize = 13,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		TextColor3 = T.TextDim,
		Parent = info,
	})
	Ui.label({
		Text = "Activity log",
		Font = T.FontBold,
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.new(0, 8, 0, 378),
		Parent = right,
	})
	logList = Ui.scroll({ Size = UDim2.new(1, -16, 0, 136), Position = UDim2.new(0, 8, 0, 398), Parent = right })
	Ui.list(1).Parent = logList

	RunService.RenderStepped:Connect(Menu.renderEcg)
end

function Menu.isOpen(): boolean
	return window.Visible
end

function Menu.requestClose()
	Remotes.get("CloseMenu"):FireServer()
	Menu.setView(nil)
end

function Menu.setView(newView)
	local wasOpen = view ~= nil
	local changedTarget = newView and view and newView.target ~= view.target
	view = newView
	window.Visible = view ~= nil
	modalButton.Visible = view ~= nil
	if not view then
		return
	end
	if not wasOpen or changedTarget then
		selectedCategory = "All"
		selectedPart = "Torso"
		lastActionSignature = ""
		lastLogSignature = ""
	end
	Menu.render()
end

local function vitalsText(v)
	local hr = if v.hr then tostring(v.hr) else "--"
	local bp = if v.bp then string.format("%d/%d", v.bp[1], v.bp[2]) else "--/--"
	local spo2 = if v.spo2 then tostring(v.spo2) .. "%" else "--"
	return hr, bp, spo2
end

local function renderParts()
	for name, pb in partButtons do
		local p = view.parts[name]
		pb.button.BackgroundColor3 = BLEED_COLORS[p.bleed] or BLEED_COLORS[0]
		if #p.wounds == 0 and #p.bandaged > 0 and p.bleed == 0 then
			pb.button.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
		end
		pb.stroke.Transparency = if name == selectedPart then 0 else 1
		local badges = {}
		if p.tourniquet then
			table.insert(badges, "TQ")
		end
		if p.fracture then
			table.insert(badges, "FX")
		end
		if p.splint then
			table.insert(badges, "SP")
		end
		if p.access then
			table.insert(badges, if p.access.kind == "FAST IO" then "IO" else "IV")
		end
		if p.pulseOx then
			table.insert(badges, "Ox")
		end
		pb.badge.Text = table.concat(badges, " ")
	end
end

local function renderActions()
	local list = view.actions[selectedPart] or {}
	local parts = {}
	for _, a in list do
		if selectedCategory == "All" or a.category == selectedCategory then
			table.insert(parts, a.id .. tostring(a.enabled) .. tostring(a.reason))
		end
	end
	local signature = selectedPart .. selectedCategory .. table.concat(parts, "|") .. tostring(view.target)
	for _, b in categoryBar:GetChildren() do
		if b:IsA("TextButton") then
			local has = b.Name == "All"
			for _, a in list do
				if a.category == b.Name then
					has = true
					break
				end
			end
			b.BackgroundColor3 = if b.Name == selectedCategory then T.Accent elseif has then T.PanelLight else T.Panel
			b.TextColor3 = if has then T.Text else T.TextDim
		end
	end
	if signature == lastActionSignature then
		return
	end
	lastActionSignature = signature
	Ui.clear(actionList)
	local order = 0
	for _, a in list do
		if selectedCategory == "All" or a.category == selectedCategory then
			order += 1
			local text = string.format("%s  <font color='#8a9099'>%.0fs</font>", a.name, a.time)
			if not a.enabled and a.reason then
				text ..= string.format("\n<font size='11' color='#c08060'>%s</font>", a.reason)
			end
			local b = Ui.button({
				RichText = true,
				Text = text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				Size = UDim2.new(1, -8, 0, if a.enabled or not a.reason then 30 else 42),
				LayoutOrder = order,
				AutoButtonColor = a.enabled,
				BackgroundColor3 = if a.enabled then T.PanelLight else T.Panel,
				TextColor3 = if a.enabled then T.Text else T.TextDim,
				Parent = actionList,
			})
			Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = b })
			if a.enabled then
				local target = view.target
				local partName = selectedPart
				b.Activated:Connect(function()
					Remotes.get("RequestAction"):FireServer(target, a.id, partName)
				end)
			end
		end
	end
	if order == 0 then
		Ui.label({ Text = "No actions available here.", TextColor3 = T.TextDim, Parent = actionList })
	end
end

function Menu.render()
	if not view then
		return
	end
	titleLabel.Text = (if view.isSelf then "Self treatment - " else "Treating ")
		.. view.name
		.. (if view.bloodType then "   [" .. view.bloodType .. "]" else "")
	triageLabel.Text = if view.triage == "None" then "No triage" else view.triage:upper()
	triageLabel.BackgroundColor3 = TRIAGE_COLORS[view.triage] or T.PanelLight
	statusLabel.Text = if #view.status > 0 then table.concat(view.status, "\n") else "No visible problems"
	statusLabel.TextColor3 = if not view.alive then T.TextDim elseif view.inArrest then T.Bad else T.Text

	renderParts()
	renderActions()

	local p = view.parts[selectedPart]
	partTitle.Text = BodyParts.DisplayName[selectedPart]
	local lines = {}
	for _, w in p.wounds do
		local bleed = ({ [0] = "", [1] = " - oozing", [2] = " - bleeding", [3] = " - BLEEDING HEAVILY" })[w.bleed]
		table.insert(lines, "- " .. w.text .. bleed)
	end
	for _, b in p.bandaged do
		table.insert(lines, "- Bandaged: " .. b)
	end
	if p.stitched > 0 then
		table.insert(lines, string.format("- %d stitched wound(s)", p.stitched))
	end
	if p.fracture then
		table.insert(lines, "- " .. p.fracture .. (if p.splint then " (splinted)" else ""))
	elseif p.splint then
		table.insert(lines, "- Splint applied")
	end
	if p.surgery and p.surgery > 0 then
		table.insert(lines, "- Surgery stage: " .. ({ "incised", "exposed", "prepared" })[p.surgery])
	end
	if p.tourniquet then
		table.insert(lines, string.format("- Tourniquet on for %d:%02d", p.tourniquet // 60, p.tourniquet % 60))
	end
	if p.access then
		table.insert(lines, string.format("- %s%s", p.access.kind, if p.access.flowing then "" else " (blocked)"))
		for _, bag in p.access.bags do
			table.insert(lines, "    " .. bag)
		end
	end
	if p.pulseOx then
		table.insert(lines, "- Pulse oximeter attached")
	end
	partDetails.Text = if #lines > 0 then table.concat(lines, "\n") else "No injuries found"

	local a = view.airway
	local airway = { "Airway:" }
	if a.device then
		table.insert(airway, a.device)
	end
	if a.recovery then
		table.insert(airway, "recovery position")
	end
	if a.headTilt then
		table.insert(airway, "head tilt held")
	end
	if a.known then
		if a.occluded then
			table.insert(airway, "OCCLUDED")
		end
		if a.obstructed then
			table.insert(airway, "OBSTRUCTED")
		end
		if not a.occluded and not a.obstructed then
			table.insert(airway, "clear (last check)")
		end
	else
		table.insert(airway, "not assessed")
	end
	airwayLabel.Text = table.concat(airway, " ")
	medsLabel.Text = if #view.meds > 0 then "Medications: " .. table.concat(view.meds, ", ") else ""

	local v = view.vitals
	local hr, bp, spo2 = vitalsText(v)
	monitor.hr.Text = hr
	monitor.bp.Text = bp
	monitor.spo2.Text = spo2
	monitor.rr.Text = if v.rr then tostring(v.rr) else "--"
	monitor.etco2.Text = if v.etco2 then tostring(v.etco2) else "--"
	monitor.source.Text = if v.source == "monitor"
		then "AED-X monitor"
		elseif v.source == "pulseox" then "Pulse oximeter (+ last manual checks)"
		else "Manual checks only - attach a monitor for live vitals"
	if v.rhythm then
		monitor.rhythm.Text = v.rhythmName .. (if v.shockable then "\nSHOCKABLE" else "")
		monitor.rhythm.TextColor3 = if v.shockable
			then T.Bad
			elseif v.rhythm == "Sinus" then Color3.fromRGB(80, 255, 120)
			else T.Warn
	else
		monitor.rhythm.Text = ""
	end

	local logParts = {}
	for _, entry in view.log do
		table.insert(logParts, entry.text)
	end
	local logSignature = table.concat(logParts, "|")
	if logSignature ~= lastLogSignature then
		lastLogSignature = logSignature
		Ui.clear(logList)
		for i, entry in view.log do
			Ui.label({
				Text = string.format(
					"<font color='#8a9099'>%d:%02d ago</font>  %s",
					entry.ago // 60,
					entry.ago % 60,
					entry.text
				),
				RichText = true,
				TextSize = 12,
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = i,
				Parent = logList,
			})
		end
	end
end

-- ECG waveforms -------------------------------------------------------------
local function sinusWave(phase: number): number
	-- phase 0..1 within one beat
	if phase < 0.1 then
		return math.sin(phase / 0.1 * math.pi) * 0.12 -- P
	elseif phase < 0.16 then
		return 0
	elseif phase < 0.18 then
		return -0.15 -- Q
	elseif phase < 0.21 then
		return 1 -- R
	elseif phase < 0.24 then
		return -0.3 -- S
	elseif phase < 0.4 then
		return 0
	elseif phase < 0.55 then
		return math.sin((phase - 0.4) / 0.15 * math.pi) * 0.25 -- T
	end
	return 0
end

local function sample(rhythm: string, hr: number, t: number): number
	if rhythm == "Sinus" or rhythm == "PEA" then
		local rate = if rhythm == "PEA" then 40 else math.max(hr, 1)
		local beat = (t * rate / 60) % 1
		return sinusWave(beat) * (if rhythm == "PEA" then 0.6 else 1)
	elseif rhythm == "VT" then
		return math.sin(t * math.pi * 2 * 3) * 0.8
	elseif rhythm == "VF" then
		return (math.sin(t * 23) * 0.4 + math.sin(t * 37 + 1) * 0.3 + math.sin(t * 13) * 0.2)
	elseif rhythm == "Tamponade" then
		local beat = (t * math.max(hr, 60) / 60) % 1
		return sinusWave(beat) * 0.3
	end
	return math.sin(t * 5) * 0.02
end

function Menu.renderEcg()
	if not view or not window.Visible then
		return
	end
	local v = view.vitals
	local rhythm = v.rhythm
	local hasTrace = rhythm ~= nil
	local t0 = os.clock()
	for i, bar in ecgBars do
		bar.Visible = hasTrace
		if hasTrace then
			local t = t0 - (#ecgBars - i) * 0.03
			local y = sample(rhythm, v.hr or 0, t)
			bar.Position = UDim2.new((i - 1) / #ecgBars, 0, 0.5 - y * 0.42, 0)
		end
	end
end

return Menu
