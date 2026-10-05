--!nonstrict
-- Squad-style ticket bar (top), objective capture panel and end-of-round banner. Reads the attributes set by
-- GameMode.GameService on workspace, the Teams and the local player.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local GameConfig = require(Medical.GameMode.Config)
local Rules = require(Medical.GameMode.Rules)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

local GameModeHud = {}

local player = Players.LocalPlayer
local NEUTRAL = Color3.fromRGB(70, 72, 78)

local bar, cellRow, tickets = nil, nil, {}
local cells = {}
local capture, captureTitle, captureCounts, captureFill
local banner, bannerSub

local function mySide(): string?
	local team = player.Team
	return if team then team:GetAttribute("Side") else nil
end

local function ticketsOf(side: string): number?
	for _, team in game:GetService("Teams"):GetTeams() do
		if team:GetAttribute("Side") == side then
			return team:GetAttribute("Tickets")
		end
	end
	return nil
end

local function readPoints(): { Rules.Point }
	local points = {}
	for i = 1, workspace:GetAttribute("GameObjectives") or 0 do
		local owner = workspace:GetAttribute("Obj" .. i .. "Owner")
		points[i] = {
			owner = if owner == "A" or owner == "B" then owner else nil,
			progress = workspace:GetAttribute("Obj" .. i .. "Progress") or 0,
		}
	end
	return points
end

local function sideBox(side: string, order: number)
	local box = Ui.make("Frame", {
		Size = UDim2.fromOffset(92, 40),
		BackgroundColor3 = GameConfig.Sides[side].color,
		BackgroundTransparency = 0.15,
		LayoutOrder = order,
		Parent = bar,
	}, { Ui.corner(6) })
	Ui.label({
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 2),
		Text = GameConfig.Sides[side].name:upper(),
		TextSize = 11,
		Font = T.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = box,
	})
	tickets[side] = Ui.label({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 16),
		Text = "-",
		TextSize = 20,
		Font = T.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = box,
	})
end

local function cell(i: number)
	local frame = Ui.make("Frame", {
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = NEUTRAL,
		LayoutOrder = i,
		Parent = cellRow,
	}, { Ui.corner(6) })
	local stroke = Ui.make("UIStroke", { Thickness = 2, Color = T.Warn, Transparency = 1, Parent = frame })
	local number = Ui.label({
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 2),
		Text = tostring(i),
		TextSize = 18,
		Font = T.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local tag = Ui.label({
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.fromOffset(0, 23),
		Text = "",
		TextSize = 9,
		Font = T.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local track = Ui.make("Frame", {
		Size = UDim2.new(1, -8, 0, 3),
		Position = UDim2.new(0, 4, 1, -5),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = frame,
	})
	local fill = Ui.make("Frame", { BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track })
	cells[i] = { frame = frame, stroke = stroke, number = number, tag = tag, fill = fill }
end

local function build(screen: ScreenGui)
	bar = Ui.make("Frame", {
		Name = "GameModeBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.35,
		Parent = screen,
	}, { Ui.corner(8), Ui.padding(6) })
	local layout = Ui.list(8, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = bar
	sideBox("A", 1)
	cellRow = Ui.make("Frame", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = bar,
	})
	Ui.list(4, true).Parent = cellRow
	sideBox("B", 3)

	capture = Ui.make("Frame", {
		Name = "CapturePanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.68, 0),
		Size = UDim2.fromOffset(340, 52),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.3,
		Visible = false,
		Parent = screen,
	}, { Ui.corner(6) })
	captureTitle = Ui.label({
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 4),
		TextSize = 14,
		Font = T.FontBold,
		Parent = capture,
	})
	captureCounts = Ui.label({
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 4),
		TextSize = 13,
		TextColor3 = T.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = capture,
	})
	local track = Ui.make("Frame", {
		Size = UDim2.new(1, -16, 0, 10),
		Position = UDim2.fromOffset(8, 32),
		BackgroundColor3 = T.PanelLight,
		BorderSizePixel = 0,
		Parent = capture,
	}, { Ui.corner(3) })
	captureFill = Ui.make("Frame", { BorderSizePixel = 0, Parent = track }, { Ui.corner(3) })
	Ui.make("Frame", {
		Size = UDim2.new(0, 2, 1, 4),
		Position = UDim2.new(0.5, -1, 0, -2),
		BackgroundColor3 = T.Text,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	})

	banner = Ui.make("Frame", {
		Name = "RoundBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(460, 96),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = screen,
	}, { Ui.corner(10) })
	Ui.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 10),
		TextSize = 36,
		Font = T.FontBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = banner,
	})
	bannerSub = Ui.label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 62),
		TextSize = 16,
		TextColor3 = T.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = banner,
	})
end

local function status(points, i: number, a: number, b: number, side: string?): string
	if a == b then
		return if a > 0 then "CONTESTED" else ""
	end
	local who = if a > b then "A" else "B"
	local point = points[i]
	local prefix = if who == side then "" else GameConfig.Sides[who].name:upper() .. " "
	if not Rules.canAffect(points, i, who) then
		local next = Rules.attackable(points, who)
		return "LOCKED" .. (if who == side and next then " - TAKE OBJECTIVE " .. next .. " FIRST" else "")
	elseif point.owner == who then
		return prefix .. (if math.abs(point.progress) < 100 then "RESTORING" else "SECURED")
	elseif point.owner then
		return prefix .. "NEUTRALISING"
	end
	return prefix .. "CAPTURING"
end

local function update()
	local side = mySide()
	local points = readPoints()
	for key, label in tickets do
		label.Text = tostring(ticketsOf(key) or "-")
	end

	for i = #cells + 1, #points do
		cell(i)
	end
	local attack = if side then Rules.attackable(points, side) else nil
	local threat = if side then Rules.attackable(points, Rules.other(side)) else nil
	for i, c in cells do
		local point = points[i]
		c.frame.Visible = point ~= nil
		if point then
			c.frame.BackgroundColor3 = if point.owner then GameConfig.Sides[point.owner].color else NEUTRAL
			local towards = if point.progress >= 0 then "A" else "B"
			c.fill.BackgroundColor3 = GameConfig.Sides[towards].color:Lerp(Color3.new(1, 1, 1), 0.35)
			c.fill.Size = UDim2.fromScale(math.abs(point.progress) / 100, 1)
			local tag, locked = "", false
			if side and point.owner == side and threat == i then
				tag = "DEFEND"
			elseif attack == i then
				tag = "ATTACK"
			elseif side and point.owner ~= side then
				tag, locked = "LOCKED", true
			end
			c.tag.Text = tag
			c.stroke.Transparency = if tag == "ATTACK" or tag == "DEFEND" then 0 else 1
			c.stroke.Color = if tag == "DEFEND" then T.Bad else T.Warn
			c.frame.BackgroundTransparency = if locked then 0.55 else 0.05
		end
	end

	local where = player:GetAttribute("InObjective") or 0
	local point = points[where]
	capture.Visible = point ~= nil
	if point then
		local a = workspace:GetAttribute("Obj" .. where .. "A") or 0
		local b = workspace:GetAttribute("Obj" .. where .. "B") or 0
		local text = status(points, where, a, b, side)
		captureTitle.Text = "OBJECTIVE " .. where .. (if text ~= "" then "  -  " .. text else "")
		captureCounts.Text = ("%d : %d"):format(a, b)
		local p = point.progress / 100
		captureFill.BackgroundColor3 = GameConfig.Sides[if p >= 0 then "A" else "B"].color
		captureFill.Position = UDim2.fromScale(if p >= 0 then 0.5 else 0.5 + p / 2, 0)
		captureFill.Size = UDim2.fromScale(math.abs(p) / 2, 1)
	end

	local winner = workspace:GetAttribute("GameWinner")
	banner.Visible = winner == "A" or winner == "B"
	if banner.Visible then
		local title = banner:FindFirstChild("Title")
		title.Text = GameConfig.Sides[winner].name:upper() .. " WINS"
		title.TextColor3 = GameConfig.Sides[winner].color
		local left = math.max(0, math.ceil((workspace:GetAttribute("GameResetAt") or 0) - workspace:GetServerTimeNow()))
		bannerSub.Text = (if winner == side then "Victory" elseif side then "Defeat" else "")
			.. "  -  next round in "
			.. left
			.. "s"
	end
end

function GameModeHud.init(screen: ScreenGui)
	if not GameConfig.Enabled then
		return
	end
	build(screen)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			update()
		end
	end)
end

return GameModeHud
