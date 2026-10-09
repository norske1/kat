--!nonstrict
-- Main menu and team select for the game mode. Players join on the Lobby team without a character; "Join Round"
-- opens team select, which asks the server to put them on a side (GameService.join enforces MaxTeamGap).
-- The Squads page (opened after joining a side, or from the main page) creates/joins squads and picks classes
-- through the Squad remote; the server (SquadService) validates everything and broadcasts SquadState.
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
local gui, mainPage, teamPage, careerPage, squadPage, resumeButton, status
local squadState = { squads = {}, commanders = { A = 0, B = 0 } }
local sq: { [string]: any } = {} -- squad page widgets
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
	squadPage.Visible = page == "squad"
	status.Text = ""
	sq.status.Text = ""
	if page == "squad" then
		sq.render()
	end
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

local function nameOf(uid: number): string
	local p = Players:GetPlayerByUserId(uid)
	return if p then p.DisplayName else "?"
end

local function sendSquad(action: string, arg: any?)
	sq.status.TextColor3 = T.TextDim
	sq.status.Text = "..."
	Remotes.get("Squad"):FireServer(action, arg)
end

local function mySquad()
	for _, squad in squadState.squads do
		for _, m in squad.members do
			if m.userId == player.UserId then
				return squad
			end
		end
	end
	return nil
end

local function panel(props)
	props.BackgroundColor3 = T.Panel
	return Ui.make("Frame", props, { Ui.corner(8) })
end

local function buildSquadPage()
	squadPage = Ui.make("Frame", {
		Name = "Squads",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 490),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	centered({
		Text = "SQUADS",
		Font = T.FontBold,
		TextSize = 32,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = squadPage,
	})
	sq.class = centered({
		TextSize = 15,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 42),
		Parent = squadPage,
	})

	-- left: commander + squad list
	local left = panel({ Size = UDim2.fromOffset(370, 340), Position = UDim2.fromOffset(0, 72), Parent = squadPage })
	local create = Ui.button({
		Text = "CREATE SQUAD",
		Font = T.FontBold,
		TextSize = 16,
		BackgroundColor3 = T.Accent,
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.fromOffset(12, 12),
		Parent = left,
	})
	create.Activated:Connect(function()
		sendSquad("create")
	end)
	sq.commander = Ui.label({
		TextSize = 14,
		Size = UDim2.new(1, -128, 0, 32),
		Position = UDim2.fromOffset(12, 54),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Parent = left,
	})
	sq.commanderButton = Ui.button({
		Size = UDim2.fromOffset(100, 30),
		Position = UDim2.new(1, -112, 0, 55),
		Parent = left,
	})
	sq.commanderButton.Activated:Connect(function()
		local side = mySide()
		if side and squadState.commanders[side] == player.UserId then
			sendSquad("class", GameConfig.DefaultClass)
		else
			sendSquad("class", "Commander")
		end
	end)
	sq.list = Ui.scroll({
		Size = UDim2.new(1, -24, 0, 236),
		Position = UDim2.fromOffset(12, 94),
		Parent = left,
	})
	Ui.list(6).Parent = sq.list

	-- right: my squad
	local right = panel({ Size = UDim2.fromOffset(374, 340), Position = UDim2.fromOffset(386, 72), Parent = squadPage })
	sq.header = Ui.label({
		Font = T.FontBold,
		TextSize = 18,
		Size = UDim2.new(1, -230, 0, 30),
		Position = UDim2.fromOffset(12, 12),
		Parent = right,
	})
	sq.public = Ui.button({
		Size = UDim2.fromOffset(100, 30),
		Position = UDim2.new(1, -218, 0, 12),
		Parent = right,
	})
	sq.public.Activated:Connect(function()
		local squad = mySquad()
		if squad then
			sendSquad("public", not squad.public)
		end
	end)
	sq.leave = Ui.button({
		Text = "LEAVE",
		Size = UDim2.fromOffset(94, 30),
		Position = UDim2.new(1, -106, 0, 12),
		Parent = right,
	})
	sq.leave.Activated:Connect(function()
		sendSquad("leave")
	end)
	sq.hint = Ui.label({
		Text = "You're not in a squad, so you're a Rifleman. Create or join a squad to pick a class.",
		TextSize = 15,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, -24, 0, 60),
		Position = UDim2.fromOffset(12, 50),
		Parent = right,
	})
	sq.classes = Ui.make("Frame", {
		Size = UDim2.new(1, -24, 0, 74),
		Position = UDim2.fromOffset(12, 50),
		BackgroundTransparency = 1,
		Parent = right,
	}, {
		Ui.make("UIGridLayout", {
			CellSize = UDim2.fromOffset(112, 34),
			CellPadding = UDim2.fromOffset(5, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	sq.members = Ui.scroll({
		Size = UDim2.new(1, -24, 0, 196),
		Position = UDim2.fromOffset(12, 134),
		Parent = right,
	})
	Ui.list(4).Parent = sq.members

	sq.status = centered({
		Text = "",
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 418),
		Parent = squadPage,
	})
	local done = Ui.button({
		Text = "DONE",
		Font = T.FontBold,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(160, 34),
		Position = UDim2.new(0.5, 0, 0, 450),
		Parent = squadPage,
	})
	done.Activated:Connect(function()
		if mySide() and player.Character then
			MainMenu.close()
		else
			show("main")
		end
	end)
	sq.render = function()
		local side = mySide()
		local squad = mySquad()
		local leader = squad and squad.leader == player.UserId
		sq.class.Text = "Your class: " .. tostring(player:GetAttribute("Class") or GameConfig.DefaultClass)

		local commander = if side then squadState.commanders[side] or 0 else 0
		sq.commander.Text = "Commander: " .. (if commander ~= 0 then nameOf(commander) else "vacant")
		sq.commanderButton.Text = if commander == player.UserId then "RESIGN" else "TAKE"
		local canTake = commander == 0 or commander == player.UserId
		sq.commanderButton.Active = canTake
		sq.commanderButton.AutoButtonColor = canTake
		sq.commanderButton.TextColor3 = if canTake then T.Text else T.TextDim

		Ui.clear(sq.list)
		for i, s in squadState.squads do
			if s.side == side then
				local row = panel({
					Size = UDim2.new(1, -6, 0, 40),
					BackgroundColor3 = T.PanelLight,
					LayoutOrder = i,
					Parent = sq.list,
				})
				row.BackgroundColor3 = T.PanelLight
				Ui.label({
					Text = ("Squad %d  %d/%d  %s"):format(
						s.number,
						#s.members,
						GameConfig.SquadSize,
						if s.public then "Public" else "Private"
					),
					Font = T.FontBold,
					TextSize = 14,
					Size = UDim2.new(1, -100, 0, 20),
					Position = UDim2.fromOffset(10, 2),
					Parent = row,
				})
				Ui.label({
					Text = "Led by " .. nameOf(s.leader),
					TextSize = 12,
					TextColor3 = T.TextDim,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = false,
					Size = UDim2.new(1, -100, 0, 16),
					Position = UDim2.fromOffset(10, 21),
					Parent = row,
				})
				local mine = squad and squad.id == s.id
				local open = s.public and #s.members < GameConfig.SquadSize
				local join = Ui.button({
					Text = if mine then "JOINED" elseif not s.public then "PRIVATE" elseif open then "JOIN" else "FULL",
					Size = UDim2.fromOffset(80, 28),
					Position = UDim2.new(1, -88, 0, 6),
					Parent = row,
				})
				local can = open and not mine
				join.Active = can
				join.AutoButtonColor = can
				join.TextColor3 = if can then T.Text else T.TextDim
				join.Activated:Connect(function()
					if join.Active then
						sendSquad("join", s.id)
					end
				end)
			end
		end

		sq.hint.Visible = squad == nil
		sq.classes.Visible = squad ~= nil
		sq.public.Visible = leader == true
		sq.leave.Visible = squad ~= nil
		sq.header.Text = if squad
			then ("Squad %d  %d/%d"):format(squad.number, #squad.members, GameConfig.SquadSize)
			else "No squad"
		Ui.clear(sq.classes)
		Ui.clear(sq.members)
		if not squad then
			return
		end
		sq.public.Text = if squad.public then "PUBLIC" else "PRIVATE"
		local myClass
		local taken = {}
		for _, m in squad.members do
			taken[m.class] = (taken[m.class] or 0) + 1
			if m.userId == player.UserId then
				myClass = m.class
			end
		end
		for i, def in GameConfig.Classes do
			if not def.perSide then
				local count = taken[def.name] or 0
				local selected = myClass == def.name
				local full = def.cap ~= nil and count >= def.cap and not selected
				local allowed = not selected and not full and not leader and not def.leader
				local b = Ui.button({
					Text = if def.cap then ("%s %d/%d"):format(def.name, count, def.cap) else def.name,
					TextSize = 12,
					TextWrapped = true,
					LayoutOrder = i,
					BackgroundColor3 = if selected then T.Accent else T.PanelLight,
					TextColor3 = if selected or allowed then T.Text else T.TextDim,
					AutoButtonColor = allowed,
					Parent = sq.classes,
				})
				b.Active = allowed
				b.Activated:Connect(function()
					if b.Active then
						sendSquad("class", def.name)
					end
				end)
			end
		end
		for i, m in squad.members do
			local row = Ui.make("Frame", {
				Size = UDim2.new(1, -6, 0, 30),
				BackgroundColor3 = T.PanelLight,
				LayoutOrder = i,
				Parent = sq.members,
			}, { Ui.corner(4) })
			Ui.label({
				Text = nameOf(m.userId),
				TextSize = 14,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				Size = UDim2.new(0.5, -10, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				Parent = row,
			})
			Ui.label({
				Text = m.class or GameConfig.DefaultClass,
				TextSize = 13,
				TextColor3 = T.TextDim,
				Size = UDim2.new(0.5, -80, 1, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				Parent = row,
			})
			if leader and m.userId ~= player.UserId then
				local kick = Ui.button({
					Text = "KICK",
					TextSize = 12,
					TextColor3 = T.Bad,
					Size = UDim2.fromOffset(60, 22),
					Position = UDim2.new(1, -66, 0, 4),
					Parent = row,
				})
				kick.Activated:Connect(function()
					sendSquad("kick", m.userId)
				end)
			end
		end
	end
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
		Size = UDim2.fromOffset(460, 340),
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
	local squadsButton = Ui.button({
		Text = "SQUADS",
		Font = T.FontBold,
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(280, 40),
		Position = UDim2.new(0.5, 0, 0, 246),
		Parent = mainPage,
	})
	squadsButton.Activated:Connect(function()
		if mySide() then
			show("squad")
		else
			show("team")
			status.TextColor3 = T.TextDim
			status.Text = "Join a team first, then pick a squad"
		end
	end)
	resumeButton = Ui.button({
		Text = "RESUME",
		Font = T.FontBold,
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(280, 40),
		Position = UDim2.new(0.5, 0, 0, 296),
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
	buildSquadPage()
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
	Remotes.get("SquadState").OnClientEvent:Connect(function(newState)
		if typeof(newState) == "table" then
			squadState = newState
			if isOpen and squadPage.Visible then
				sq.render()
			end
		end
	end)
	Remotes.get("SquadResult").OnClientEvent:Connect(function(ok, message)
		sq.status.TextColor3 = if ok then T.TextDim else T.Bad
		sq.status.Text = if ok then "" elseif typeof(message) == "string" then message else "Not allowed"
	end)
	Remotes.get("Squad"):FireServer("sync")
	player:GetAttributeChangedSignal("Class"):Connect(function()
		if isOpen and squadPage.Visible then
			sq.render()
		end
	end)
	Remotes.get("TeamResult").OnClientEvent:Connect(function(ok, message)
		pending = false
		if ok then
			show("squad")
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
