--!nonstrict
-- Main menu and team select for the game mode. Players join on the Lobby team without a character; "Join Round"
-- opens team select, which asks the server to put them on a side (GameService.join enforces MaxTeamGap).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local UserInputService = game:GetService("UserInputService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local GameConfig = require(Medical.GameMode.Config)
local Rules = require(Medical.GameMode.Rules)
local Career = require(Medical.GameMode.Career)
local Remotes = require(Medical.Remotes)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

local MainMenu = {}

local player = Players.LocalPlayer
local gui, mainPage, teamPage, careerPage, resumeButton, status
local careerValues = {}
local cards = {}
local isOpen = false
local pending = false
local scriptedCamera = false

local function mySide(): string?
	local team = player.Team
	return if team then team:GetAttribute("Side") else nil
end

local function teamOf(side: string): Team?
	for _, team in Teams:GetTeams() do
		if team:GetAttribute("Side") == side then
			return team
		end
	end
	return nil
end

-- Players on `side` and on the other side, not counting the local player.
local function counts(side: string): (number, number)
	local joining, other = 0, 0
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Team then
			local s = p.Team:GetAttribute("Side")
			if s == side then
				joining += 1
			elseif s == Rules.other(side) then
				other += 1
			end
		end
	end
	return joining, other
end

local function show(page: string)
	mainPage.Visible = page == "main"
	teamPage.Visible = page == "team"
	careerPage.Visible = page == "career"
	status.Text = ""
end

function MainMenu.open(page: string?)
	isOpen = true
	gui.Enabled = true
	show(page or "main")
end

function MainMenu.close()
	isOpen = false
	pending = false
	gui.Enabled = false
end

function MainMenu.isOpen(): boolean
	return isOpen
end

local function centered(props)
	props.TextXAlignment = Enum.TextXAlignment.Center
	return Ui.label(props)
end

local function card(side: string, order: number, row: Frame)
	local color = GameConfig.Sides[side].color
	local frame = Ui.make("Frame", {
		Size = UDim2.fromOffset(230, 190),
		BackgroundColor3 = T.Panel,
		LayoutOrder = order,
		Parent = row,
	}, { Ui.corner(8), Ui.make("UIStroke", { Color = color, Thickness = 2 }) })
	centered({
		Text = GameConfig.Sides[side].name:upper(),
		Font = T.FontBold,
		TextSize = 24,
		TextColor3 = color,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 14),
		Parent = frame,
	})
	local playersLabel = centered({
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 56),
		Parent = frame,
	})
	local ticketsLabel = centered({
		TextSize = 14,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 80),
		Parent = frame,
	})
	local button = Ui.button({
		Text = "JOIN",
		Font = T.FontBold,
		TextSize = 18,
		BackgroundColor3 = color,
		Size = UDim2.new(1, -32, 0, 44),
		Position = UDim2.new(0, 16, 1, -60),
		Parent = frame,
	})
	button.Activated:Connect(function()
		if pending or not button.Active then
			return
		end
		if mySide() == side and player.Character then
			MainMenu.close()
			return
		end
		pending = true
		status.TextColor3 = T.TextDim
		status.Text = "Joining " .. GameConfig.Sides[side].name .. "..."
		Remotes.get("JoinTeam"):FireServer(side)
	end)
	cards[side] = { players = playersLabel, tickets = ticketsLabel, button = button, color = color }
end

local function build()
	gui = Ui.make("ScreenGui", {
		Name = "MainMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	-- full-screen modal backdrop: frees the mouse in first person and blocks clicks to the game
	Ui.make("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		Modal = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.35,
		Parent = gui,
	})

	mainPage = Ui.make("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	careerPage = Ui.make("Frame", {
		Name = "Career",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 380),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	centered({
		Text = "MY CAREER",
		Font = T.FontBold,
		TextSize = 32,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = careerPage,
	})
	local rows = {
		{ "kills", "Total kills" },
		{ "deaths", "Total deaths" },
		{ "kd", "K/D ratio" },
		{ "class", "Most used class" },
		{ "time", "Time played" },
	}
	for i, row in rows do
		local frame = Ui.make("Frame", {
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.fromOffset(0, 50 + (i - 1) * 52),
			BackgroundColor3 = T.Panel,
			Parent = careerPage,
		}, { Ui.corner(6) })
		Ui.label({
			Text = row[2],
			TextSize = 16,
			TextColor3 = T.TextDim,
			Size = UDim2.new(0.6, -16, 1, 0),
			Position = UDim2.fromOffset(16, 0),
			Parent = frame,
		})
		careerValues[row[1]] = Ui.label({
			Text = "-",
			Font = T.FontBold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.4, -16, 1, 0),
			Position = UDim2.new(0.6, 0, 0, 0),
			Parent = frame,
		})
	end
	local careerBack = Ui.button({
		Text = "BACK",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(160, 34),
		Position = UDim2.new(0.5, 0, 0, 316),
		Parent = careerPage,
	})
	careerBack.Activated:Connect(function()
		show("main")
	end)
	centered({
		Text = GameConfig.MenuTitle,
		Font = T.FontBold,
		TextSize = 52,
		Size = UDim2.new(1, 0, 0, 60),
		Parent = mainPage,
	})
	centered({
		Text = GameConfig.MenuSubtitle,
		TextSize = 18,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 62),
		Parent = mainPage,
	})
	local join = Ui.button({
		Text = "JOIN ROUND",
		Font = T.FontBold,
		TextSize = 22,
		BackgroundColor3 = T.Accent,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(280, 54),
		Position = UDim2.new(0.5, 0, 0, 130),
		Parent = mainPage,
	})
	join.Activated:Connect(function()
		show("team")
	end)
	local careerButton = Ui.button({
		Text = "MY CAREER",
		Font = T.FontBold,
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(280, 40),
		Position = UDim2.new(0.5, 0, 0, 196),
		Parent = mainPage,
	})
	careerButton.Activated:Connect(function()
		show("career")
	end)
	resumeButton = Ui.button({
		Text = "RESUME",
		Font = T.FontBold,
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(280, 40),
		Position = UDim2.new(0.5, 0, 0, 246),
		Visible = false,
		Parent = mainPage,
	})
	resumeButton.Activated:Connect(MainMenu.close)

	teamPage = Ui.make("Frame", {
		Name = "TeamSelect",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 360),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	centered({
		Text = "SELECT TEAM",
		Font = T.FontBold,
		TextSize = 32,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = teamPage,
	})
	centered({
		Text = ("Teams can't be more than %d players apart"):format(GameConfig.MaxTeamGap),
		TextSize = 14,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 42),
		Parent = teamPage,
	})
	local row = Ui.make("Frame", {
		Size = UDim2.new(1, 0, 0, 190),
		Position = UDim2.fromOffset(0, 72),
		BackgroundTransparency = 1,
		Parent = teamPage,
	})
	local layout = Ui.list(20, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = row
	card("A", 1, row)
	card("B", 2, row)
	status = centered({
		Text = "",
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 268),
		Parent = teamPage,
	})
	local back = Ui.button({
		Text = "BACK",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(160, 34),
		Position = UDim2.new(0.5, 0, 0, 312),
		Parent = teamPage,
	})
	back.Activated:Connect(function()
		show("main")
	end)
end

local function updateCareer()
	local kills = player:GetAttribute("CareerKills") or 0
	local deaths = player:GetAttribute("CareerDeaths") or 0
	careerValues.kills.Text = tostring(kills)
	careerValues.deaths.Text = tostring(deaths)
	careerValues.kd.Text = Career.formatKd(kills, deaths)
	careerValues.class.Text = player:GetAttribute("CareerClass") or Career.DefaultClass
	careerValues.time.Text = Career.formatTime(player:GetAttribute("CareerSeconds") or 0)
end

local function update()
	if careerPage.Visible then
		updateCareer()
	end
	local side = mySide()
	resumeButton.Visible = side ~= nil and player.Character ~= nil
	for key, c in cards do
		local team = teamOf(key)
		local joining, other = counts(key)
		local current = side == key
		local allowed = current or Rules.canJoin(joining, other, GameConfig.MaxTeamGap)
		local size = if team then #team:GetPlayers() else 0
		c.players.Text = size .. (if size == 1 then " player" else " players")
		c.tickets.Text = tostring(if team then team:GetAttribute("Tickets") or "-" else "-") .. " tickets"
		c.button.Text = if current then "CURRENT TEAM" elseif allowed then "JOIN" else "TEAM FULL"
		c.button.Active = allowed
		c.button.AutoButtonColor = allowed
		c.button.BackgroundColor3 = if allowed then c.color else T.PanelLight
		c.button.TextColor3 = if allowed then T.Text else T.TextDim
	end
end

-- With no character (lobby, or waiting to respawn) the camera slowly circles the middle objective.
local function updateCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local character = player.Character
	if isOpen and not character then
		local focus = workspace:GetAttribute("LobbyFocus")
		if typeof(focus) ~= "Vector3" then
			focus = Vector3.new(0, 10, 0)
		end
		local angle = os.clock() * 0.05
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(focus + Vector3.new(math.cos(angle) * 120, 60, math.sin(angle) * 120), focus)
		scriptedCamera = true
	elseif scriptedCamera and character then
		scriptedCamera = false
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = character:FindFirstChildOfClass("Humanoid")
	end
end

function MainMenu.init()
	if not GameConfig.Enabled then
		return
	end
	build()
	MainMenu.open("main")
	Remotes.get("TeamResult").OnClientEvent:Connect(function(ok, message)
		pending = false
		if ok then
			MainMenu.close()
		else
			status.TextColor3 = T.Bad
			status.Text = if typeof(message) == "string" then message else "You can't join that team"
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= GameConfig.MenuKey then
			return
		end
		if not isOpen then
			MainMenu.open("main")
		elseif mySide() and player.Character then
			MainMenu.close()
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		updateCamera()
		acc += dt
		if isOpen and acc >= 0.25 then
			acc = 0
			update()
		end
	end)
end

return MainMenu
