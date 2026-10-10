--!nonstrict
-- ArmA-style inventory screen (I): the nearby arsenal or dropped gear on the left, your gear on the right
-- (weapon slots, uniform / vest / backpack with their load), plus total weight and a stamina bar.
-- Left click takes / drops one (one magazine for ammo), right click takes 5 / drops all.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Gear = require(Medical:WaitForChild("Gear").Gear)
local GearConfig = require(Medical.Gear.Config)
local Remotes = require(Medical.Remotes)
local Ui = require(script.Parent.Ui)
local InventoryInput = require(script.Parent.InventoryInput)
local InventoryDrag = require(script.Parent.InventoryDrag)
local T = Ui.Theme

local InventoryUi = {}

local gearRemote
local frame, sourceTitle, sourceList, contentTitle, contentList, weightLabel, staminaBar, staminaFill
local slotBoxes: { [string]: any } = {}
local snapshot = nil
local source: any = { kind = "ground", items = {} }
local selected = "uniform"
local isOpen = false
local dragger
local staminaFn: () -> (number, boolean) = function()
	return 1, false
end

local SLOT_TITLES = {
	primary = "PRIMARY",
	handgun = "HANDGUN",
	launcher = "LAUNCHER",
	uniform = "UNIFORM",
	vest = "VEST",
	backpack = "BACKPACK",
}
local SHORT = { uniform = "U", vest = "V", backpack = "B" }
local KIND_TITLES = { weapon = "WEAPONS", container = "UNIFORMS, VESTS & BACKPACKS", ammo = "AMMO", item = "EQUIPMENT" }

local function send(...)
	gearRemote:FireServer(...)
end

local function unit(id: string): number
	local def = Gear.def(id)
	return if def and def.kind == "ammo" then def.roundsPer or 1 else 1
end

local function countText(id: string, n: number): string
	local per = unit(id)
	if per > 1 then
		return string.format("x%d  (%d rds)", math.ceil(n / per), n)
	end
	return "x" .. n
end

local function kg(mass: number): string
	return string.format("%.1f kg", mass)
end

local function header(parent, order: number, text: string)
	Ui.label({
		Text = text,
		Font = T.FontBold,
		TextSize = 12,
		TextColor3 = T.TextDim,
		Size = UDim2.new(1, -6, 0, 20),
		LayoutOrder = order,
		Parent = parent,
	})
end

local function row(parent, order: number, text: string, right: string, onLeft, onRight, extra: { { any } }?, origin)
	local b = Ui.button({ Text = "", Size = UDim2.new(1, -6, 0, 26), LayoutOrder = order, Parent = parent })
	local extraWidth = if extra then #extra * 26 else 0
	Ui.label({
		Text = text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -(120 + extraWidth), 1, 0),
		Position = UDim2.fromOffset(8, 0),
		Parent = b,
	})
	Ui.label({
		Text = right,
		TextColor3 = T.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		Size = UDim2.new(0, 104, 1, 0),
		Position = UDim2.new(1, -(108 + extraWidth), 0, 0),
		Parent = b,
	})
	for i, e in (extra or {}) :: { { any } } do
		local mini = Ui.button({
			Text = e[1],
			Font = T.FontBold,
			TextSize = 12,
			Size = UDim2.fromOffset(22, 20),
			Position = UDim2.new(1, -26 * (extraWidth / 26 - i + 1), 0, 3),
			BackgroundColor3 = T.Panel,
			Parent = b,
		})
		mini.Activated:Connect(e[2])
	end
	b.Activated:Connect(function()
		if dragger:clicked() then
			onLeft()
		end
	end)
	b.MouseButton2Click:Connect(function()
		if dragger:clicked() then
			onRight()
		end
	end)
	if origin then
		dragger:origin(b, origin)
	end
	return b
end

local function sortedIds(items: { [string]: number }): { string }
	local ids = {}
	for id in items do
		if Gear.def(id) then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return Gear.def(a).name < Gear.def(b).name
	end)
	return ids
end

local function renderSource()
	Ui.clear(sourceList)
	local to = if snapshot and snapshot.slots[selected] then selected else nil
	if source.kind == "arsenal" then
		sourceTitle.Text = "ARSENAL"
		local lastGroup = nil
		for i, id in source.items do
			local def = Gear.def(id)
			if def then
				local group = KIND_TITLES[def.kind] or ("MEDICAL: " .. string.upper(def.category or ""))
				if group ~= lastGroup then
					header(sourceList, i * 2 - 1, group)
					lastGroup = group
				end
				local per = unit(id)
				local right = if def.slot then kg(def.mass) else kg(def.mass * per)
				row(
					sourceList,
					i * 2,
					def.name,
					right,
					function()
						send("take", id, per, to)
					end,
					function()
						send("take", id, per * 5, to)
					end,
					nil,
					function()
						return { kind = "source", id = id, count = per, source = source.instance }
					end
				)
			end
		end
	else
		local ids = sortedIds(source.items)
		sourceTitle.Text = if #ids > 0 then "GROUND" else "GROUND  (drop items here)"
		for i, id in ids do
			local n = source.items[id]
			row(
				sourceList,
				i,
				Gear.def(id).name,
				countText(id, n),
				function()
					send("take", id, unit(id), to)
				end,
				function()
					send("take", id, n, to)
				end,
				nil,
				function(one)
					return {
						kind = "source",
						id = id,
						count = if one then math.min(unit(id), n) else n,
						source = source.instance,
					}
				end
			)
		end
	end
end

local function renderSlots()
	for slot, box in slotBoxes do
		local id = snapshot.slots[slot]
		local def = id and Gear.def(id)
		box.name.Text = if def then def.name else "-"
		box.button.BackgroundColor3 = if slot == selected then T.Accent else T.PanelLight
		if box.bar then
			local cap = Gear.capacity(snapshot, slot)
			local load = Gear.load(snapshot, slot)
			box.load.Text = if def then string.format("%.1f / %.0f kg", load, cap) else ""
			box.fill.Size = UDim2.new(if cap > 0 then math.clamp(load / cap, 0, 1) else 0, 0, 1, 0)
			box.fill.BackgroundColor3 = if cap > 0 and load / cap > 0.9 then T.Warn else T.Good
		end
		box.drop.Visible = def ~= nil
	end
end

local function renderContents()
	Ui.clear(contentList)
	local id = snapshot.slots[selected]
	local def = id and Gear.def(id)
	contentTitle.Text = if def then string.upper(def.name) .. " CONTENTS" else "NO " .. SLOT_TITLES[selected]
	local items = snapshot.items[selected] or {}
	for i, itemId in sortedIds(items) do
		local n = items[itemId]
		local extra = {}
		if Gear.def(itemId).equipable then
			table.insert(extra, {
				"E",
				function()
					send("equip", itemId)
				end,
			})
		end
		for _, c in Gear.CONTAINERS do
			if c ~= selected and snapshot.slots[c] then
				table.insert(extra, {
					SHORT[c],
					function()
						send("move", itemId, unit(itemId), selected, c)
					end,
				})
			end
		end
		row(
			contentList,
			i,
			Gear.def(itemId).name,
			countText(itemId, n),
			function()
				send("drop", itemId, unit(itemId), selected)
			end,
			function()
				send("drop", itemId, n, selected)
			end,
			extra,
			function(one)
				return {
					kind = "contents",
					id = itemId,
					count = if one then math.min(unit(itemId), n) else n,
					container = selected,
				}
			end
		)
	end
end

local function render()
	if not snapshot or not frame then
		return
	end
	if dragger and dragger:busy() then
		return
	end
	if not snapshot.slots[selected] then
		for _, c in Gear.CONTAINERS do
			if snapshot.slots[c] then
				selected = c
				break
			end
		end
	end
	renderSlots()
	renderContents()
	renderSource()
	local mass = snapshot.mass or Gear.mass(snapshot)
	weightLabel.Text = string.format(
		"Weight %s    Speed %d%%%s",
		kg(mass),
		math.floor(Gear.speed(mass) * 100 + 0.5),
		if Gear.canSprint(mass) then "" else "    TOO HEAVY TO SPRINT"
	)
	weightLabel.TextColor3 = if Gear.canSprint(mass) then T.Text else T.Bad
end

function InventoryUi.isOpen(): boolean
	return isOpen
end

function InventoryUi.setOpen(value: boolean)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if
		value
		and not Gear.canOpen({
			hasCharacter = character ~= nil,
			alive = humanoid ~= nil and humanoid.Health > 0 and character:GetAttribute("MedAlive") ~= false,
			conscious = character ~= nil and character:GetAttribute("MedConscious") ~= false,
			typing = UserInputService:GetFocusedTextBox() ~= nil,
			modal = Ui.isModalOpen(),
			alreadyOpen = isOpen,
		})
	then
		return
	end
	isOpen = value
	if not value and dragger then
		dragger:cancel()
	end
	frame.Visible = isOpen
	if isOpen then
		send("open")
		render()
	end
end

function InventoryUi.toggle()
	InventoryUi.setOpen(not isOpen)
end

local function slotBox(parent, slot: string, x: number, y: number, w: number, container: boolean)
	local b = Ui.button({
		Text = "",
		Size = UDim2.fromOffset(w, if container then 62 else 46),
		Position = UDim2.fromOffset(x, y),
		Parent = parent,
	})
	Ui.label({
		Text = SLOT_TITLES[slot],
		Font = T.FontBold,
		TextSize = 11,
		TextColor3 = T.TextDim,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -30, 0, 14),
		Parent = b,
	})
	local name = Ui.label({
		Text = "-",
		Font = T.FontBold,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(8, 20),
		Size = UDim2.new(1, -16, 0, 18),
		Parent = b,
	})
	local drop = Ui.button({
		Text = "X",
		Font = T.FontBold,
		TextSize = 12,
		Size = UDim2.fromOffset(20, 18),
		Position = UDim2.new(1, -24, 0, 4),
		BackgroundColor3 = T.Panel,
		Parent = b,
	})
	drop.Activated:Connect(function()
		send("unwear", slot)
	end)
	local box = { button = b, name = name, drop = drop }
	dragger:target(b, function()
		local def = snapshot and snapshot.slots[slot] and Gear.def(snapshot.slots[slot])
		return { kind = if container and def then "container" else "slot", name = slot }
	end, 3)
	dragger:origin(b, function()
		local id = snapshot and snapshot.slots[slot]
		return if id then { kind = "slot", id = id, slot = slot } else nil
	end)
	if container then
		box.load = Ui.label({
			Text = "",
			TextSize = 11,
			TextColor3 = T.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(0, 8, 0, 4),
			Size = UDim2.new(1, -36, 0, 14),
			Parent = b,
		})
		box.bar = Ui.make("Frame", {
			BackgroundColor3 = T.Background,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 8, 1, -14),
			Size = UDim2.new(1, -16, 0, 6),
			Parent = b,
		})
		box.fill = Ui.make("Frame", { BackgroundColor3 = T.Good, BorderSizePixel = 0, Parent = box.bar })
		b.Activated:Connect(function()
			selected = slot
			render()
		end)
	end
	slotBoxes[slot] = box
end

function InventoryUi.init(screen: ScreenGui)
	gearRemote = Remotes.get("Gear")
	local ok, Movement = pcall(require, script.Parent.Weapons.Movement)
	if ok and Movement.stamina then
		staminaFn = Movement.stamina
	end

	frame = Ui.make("Frame", {
		Name = "Inventory",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(880, 540),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = screen,
	}, { Ui.corner(8) })

	Ui.window(frame, 880, 540)
	Ui.modal(frame)
	dragger = InventoryDrag.new(screen, {
		isOpen = InventoryUi.isOpen,
		state = function()
			return snapshot
		end,
		source = function()
			return source
		end,
		send = send,
		render = render,
	})
	Ui.make("TextButton", {
		Name = "MouseUnlock",
		Text = "",
		Modal = true,
		Size = UDim2.fromOffset(1, 1),
		BackgroundTransparency = 1,
		Parent = frame,
	})

	Ui.label({
		Text = "FIELD INVENTORY",
		Font = T.FontBold,
		TextSize = 18,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(0, 210, 0, 24),
		Parent = frame,
	})
	Ui.label({
		Text = "Drag stacks · Shift: one · RMB: bulk · E: equip",
		TextSize = 12,
		TextColor3 = T.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -560, 0, 14),
		Size = UDim2.new(0, 500, 0, 18),
		Parent = frame,
	})
	local close = Ui.button({
		Text = "X",
		Font = T.FontBold,
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -40, 0, 8),
		Parent = frame,
	})
	close.Activated:Connect(function()
		InventoryUi.setOpen(false)
	end)

	-- Left: source
	local left = Ui.make("Frame", {
		BackgroundColor3 = T.Panel,
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(0, 360, 1, -60),
		Parent = frame,
	}, { Ui.corner(6) })
	dragger:target(left, function()
		return { kind = "source" }
	end)
	sourceTitle = Ui.label({
		Text = "GROUND",
		Font = T.FontBold,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 20),
		Parent = left,
	})
	sourceList = Ui.scroll({ Position = UDim2.fromOffset(6, 30), Size = UDim2.new(1, -8, 1, -36), Parent = left })
	Ui.list(3).Parent = sourceList

	-- Right: gear
	local right = Ui.make("Frame", {
		BackgroundColor3 = T.Panel,
		Position = UDim2.fromOffset(388, 44),
		Size = UDim2.new(1, -404, 1, -60),
		Parent = frame,
	}, { Ui.corner(6) })
	local w = 150
	for i, slot in Gear.WEAPON_SLOTS do
		slotBox(right, slot, 10 + (i - 1) * (w + 8), 10, w, false)
	end
	for i, slot in Gear.CONTAINERS do
		slotBox(right, slot, 10 + (i - 1) * (w + 8), 64, w, true)
	end
	contentTitle = Ui.label({
		Text = "",
		Font = T.FontBold,
		Position = UDim2.fromOffset(10, 134),
		Size = UDim2.new(1, -150, 0, 20),
		Parent = right,
	})
	local equip = Ui.button({
		Text = "EQUIP ITEM",
		TextSize = 11,
		Position = UDim2.new(1, -132, 0, 134),
		Size = UDim2.fromOffset(120, 20),
		Parent = right,
	})
	dragger:target(equip, function()
		return { kind = "equip" }
	end, 3)
	local contentRegion = Ui.make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(6, 158),
		Size = UDim2.new(1, -8, 1, -196),
		Parent = right,
	})
	contentList = Ui.scroll({ Size = UDim2.fromScale(1, 1), Parent = contentRegion })
	Ui.list(3).Parent = contentList
	dragger:target(contentRegion, function()
		return { kind = "container", name = selected }
	end, 2)
	weightLabel = Ui.label({
		Text = "",
		Font = T.FontBold,
		Position = UDim2.new(0, 10, 1, -30),
		Size = UDim2.new(1, -20, 0, 22),
		Parent = right,
	})

	-- Stamina bar (shown while not full)
	staminaBar = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(180, 6),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screen,
	}, { Ui.corner(3) })
	staminaFill = Ui.make("Frame", { BackgroundColor3 = T.Text, BorderSizePixel = 0, Parent = staminaBar }, {
		Ui.corner(3),
	})
	RunService.RenderStepped:Connect(function()
		local value, exhausted = staminaFn()
		staminaBar.Visible = value < 0.999
		staminaFill.Size = UDim2.new(value, 0, 1, 0)
		staminaFill.BackgroundColor3 = if exhausted then T.Bad else T.Text
	end)

	Remotes.get("GearState").OnClientEvent:Connect(function(snap, src, openUi)
		snapshot = snap
		source = src or { kind = "ground", items = {} }
		if openUi and not isOpen then
			InventoryUi.setOpen(true)
		elseif isOpen then
			render()
		end
	end)

	local key = Enum.KeyCode[GearConfig.InventoryKey] or Enum.KeyCode.I
	InventoryInput.bind(key, InventoryUi.toggle, function()
		return isOpen or not Ui.isModalOpen()
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and isOpen and not UserInputService:GetFocusedTextBox() then
			InventoryUi.setOpen(false)
		end
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		InventoryUi.setOpen(false)
	end)

	-- Refresh the nearby source while open (walking up to / away from an arsenal or dropped gear).
	task.spawn(function()
		while true do
			task.wait(1)
			if isOpen then
				send("open")
			end
		end
	end)
end

return InventoryUi
