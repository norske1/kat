--!nonstrict
-- Progress bar, notifications, medical bag and debug panel.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Medical = ReplicatedStorage:WaitForChild("Medical")
local Items = require(Medical.Items)
local Remotes = require(Medical.Remotes)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

local Hud = {}

local progressFrame, progressFill, progressLabel
local progressJob = nil
local toastHolder
local bagFrame, bagList, bagTitle
local debugFrame, debugButton

local LEVEL_NAMES = { [0] = "Non-medic", [1] = "Medic", [2] = "Doctor" }

function Hud.init(screen: ScreenGui)
	progressFrame = Ui.make("Frame", {
		Name = "Progress",
		Size = UDim2.new(0, 360, 0, 46),
		Position = UDim2.new(0.5, -180, 0.78, 0),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 40,
		Parent = screen,
	}, { Ui.corner(6) })
	progressLabel = Ui.label({
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.new(0, 8, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 41,
		Parent = progressFrame,
	})
	local track = Ui.make("Frame", {
		Size = UDim2.new(1, -16, 0, 8),
		Position = UDim2.new(0, 8, 0, 26),
		BackgroundColor3 = T.PanelLight,
		ZIndex = 41,
		Parent = progressFrame,
	}, { Ui.corner(4) })
	progressFill = Ui.make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = T.Accent,
		ZIndex = 42,
		Parent = track,
	}, { Ui.corner(4) })
	Ui.label({
		Text = "[X] cancel",
		TextSize = 11,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, -16, 0, 10),
		Position = UDim2.new(0, 8, 1, -11),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 41,
		Parent = progressFrame,
	})

	toastHolder = Ui.make("Frame", {
		Name = "Toasts",
		Size = UDim2.new(0, 420, 0, 200),
		Position = UDim2.new(0.5, -210, 0, 60),
		BackgroundTransparency = 1,
		ZIndex = 45,
		Parent = screen,
	}, { Ui.list(4) })

	-- Medical bag
	bagFrame = Ui.make("Frame", {
		Name = "Bag",
		Size = UDim2.new(0, 260, 0, 380),
		Position = UDim2.new(1, -270, 0.5, -190),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 30,
		Parent = screen,
	}, { Ui.corner(8), Ui.padding(8) })
	bagTitle = Ui.label({
		Text = "Medical Bag",
		Font = T.FontBold,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 22),
		ZIndex = 31,
		Parent = bagFrame,
	})
	bagList = Ui.scroll({
		Size = UDim2.new(1, 0, 1, -26),
		Position = UDim2.new(0, 0, 0, 26),
		ZIndex = 31,
		Parent = bagFrame,
	})
	Ui.list(2).Parent = bagList

	local bagButton = Ui.button({
		Text = "Medical Bag [I]",
		Size = UDim2.new(0, 130, 0, 30),
		Position = UDim2.new(1, -140, 1, -110),
		BackgroundColor3 = T.Background,
		ZIndex = 30,
		Parent = screen,
	})
	bagButton.Activated:Connect(Hud.toggleBag)

	local menuButton = Ui.button({
		Text = "Self Treat [H]",
		Size = UDim2.new(0, 130, 0, 30),
		Position = UDim2.new(1, -140, 1, -145),
		BackgroundColor3 = T.Background,
		ZIndex = 30,
		Parent = screen,
	})
	menuButton.Activated:Connect(function()
		Remotes.get("OpenMenu"):FireServer(nil)
	end)
end

-- True while a panel that needs the mouse cursor is open (weapons unlock the mouse).
function Hud.wantsMouse(): boolean
	return (bagFrame ~= nil and bagFrame.Visible) or (debugFrame ~= nil and debugFrame.Visible)
end

function Hud.toggleBag()
	bagFrame.Visible = not bagFrame.Visible
end

function Hud.setInventory(items, level: number, debugAllowed: boolean, infinite: boolean)
	bagTitle.Text =
		string.format("Medical Bag - %s%s", LEVEL_NAMES[level] or "?", if infinite then " (infinite)" else "")
	Ui.clear(bagList)
	local ids = {}
	for id in items do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ca, cb = Items[a] and Items[a].category or "", Items[b] and Items[b].category or ""
		if ca ~= cb then
			return ca < cb
		end
		return a < b
	end)
	for i, id in ids do
		local def = Items[id]
		Ui.label({
			Text = string.format("%dx  %s", items[id], def and def.name or id),
			TextSize = 13,
			LayoutOrder = i,
			ZIndex = 32,
			Parent = bagList,
		})
	end
	Hud.setDebug(debugAllowed)
end

function Hud.setDebug(allowed: boolean)
	if not allowed or debugFrame then
		return
	end
	local screen = bagFrame.Parent
	debugFrame = Ui.make("Frame", {
		Name = "Debug",
		Size = UDim2.new(0, 170, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, 10, 0.3, 0),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 30,
		Parent = screen,
	}, { Ui.corner(6), Ui.padding(6), Ui.list(3) })
	Ui.label({ Text = "Medical debug [F2]", Font = T.FontBold, ZIndex = 31, Parent = debugFrame })
	debugButton = Ui.button({
		Text = "Debug [F2]",
		Size = UDim2.new(0, 130, 0, 30),
		Position = UDim2.new(1, -140, 1, -180),
		BackgroundColor3 = T.Background,
		ZIndex = 30,
		Parent = screen,
	})
	debugButton.Activated:Connect(Hud.toggleDebug)
	local debugRemote = Remotes.get("Debug")
	local buttons = {
		{ "Shot: left leg", "hurt", "LeftLeg", 40, "Bullet" },
		{ "Shot: torso", "hurt", "Torso", 35, "Bullet" },
		{ "Shot: head", "hurt", "Head", 25, "Bullet" },
		{ "Explosion", "hurt", nil, 70, "Explosive" },
		{ "Fall", "hurt", nil, 35, "Fall" },
		{ "Heal (target/self)", "heal" },
		{ "Restock bag", "restock" },
		{ "Level: non-medic", "level", 0 },
		{ "Level: medic", "level", 1 },
		{ "Level: doctor", "level", 2 },
		{ "Casualty: GSW leg", "dummy", "GunshotLeg" },
		{ "Casualty: airway", "dummy", "Unconscious" },
		{ "Casualty: VF arrest", "dummy", "CardiacArrest" },
		{ "Casualty: blast", "dummy", "Blast" },
		{ "Casualty: over-medicated", "dummy", "Overmedicated" },
	}
	for i, b in buttons do
		local btn = Ui.button({
			Text = b[1],
			TextSize = 12,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = i + 1,
			ZIndex = 31,
			Parent = debugFrame,
		})
		btn.Activated:Connect(function()
			debugRemote:FireServer(b[2], b[3], b[4], b[5])
		end)
	end
end

function Hud.toggleDebug()
	if debugFrame then
		debugFrame.Visible = not debugFrame.Visible
		debugButton.BackgroundColor3 = if debugFrame.Visible then T.Accent else T.Background
	end
end

function Hud.setProgress(data)
	progressJob = data
	if not data then
		progressFrame.Visible = false
		return
	end
	progressFrame.Visible = true
	progressLabel.Text = data.label .. (if data.repeating then " (repeating)" else "")
	local started = os.clock()
	local job = data
	task.spawn(function()
		while progressJob == job do
			local f = math.clamp((os.clock() - started) / math.max(job.duration, 0.05), 0, 1)
			progressFill.Size = UDim2.new(f, 0, 1, 0)
			if f >= 1 and job.repeating then
				started = os.clock()
			end
			task.wait()
		end
	end)
end

function Hud.notify(text: string, kind: string?)
	local color = if kind == "error"
		then T.Bad
		elseif kind == "warn" then T.Warn
		elseif kind == "result" then T.Good
		else T.Text
	local toast = Ui.make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.15,
		ZIndex = 46,
		Parent = toastHolder,
	}, { Ui.corner(6), Ui.padding(6) })
	Ui.label({
		Text = text,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 47,
		Parent = toast,
	})
	task.delay(4, function()
		toast:Destroy()
	end)
	local children = toastHolder:GetChildren()
	if #children > 6 then
		for _, c in children do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
end

return Hud
