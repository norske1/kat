--!nonstrict
-- Career stats per player: kills, deaths, time played and time per class (Player attribute "Class", Rifleman by
-- default until there is a class system). Saved in a DataStore and replicated to the client through attributes
-- CareerKills, CareerDeaths, CareerSeconds and CareerClass for the main menu's My Career page.
-- A kill goes to the last player who shot the victim within KillCreditSeconds; team kills don't count.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Medical = ReplicatedStorage:WaitForChild("Medical")
local Career = require(Medical.GameMode.Career)

local CareerService = {}

local STORE_NAME = "KATCareer_v1"
local KILL_CREDIT_SECONDS = 300 -- bleeding out can take minutes
local PUBLISH_SECONDS = 10
local AUTOSAVE_SECONDS = 120

type Profile = { data: Career.Data, loaded: boolean, lastTick: number }

local store = nil
local profiles: { [Player]: Profile } = {}
local lastHit: { [Model]: { player: Player, at: number } } = {}
local counted: { [Model]: boolean } = {}

local function getStore()
	if store == nil then
		local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
		store = if ok then result else false
		if not ok then
			warn("[Career] DataStore unavailable, stats won't be saved: " .. tostring(result))
		end
	end
	return if store then store else nil
end

local function keyOf(player: Player): string
	return "player_" .. player.UserId
end

local function classOf(player: Player): string
	local class = player:GetAttribute("Class")
	return if type(class) == "string" and class ~= "" then class else Career.DefaultClass
end

local function tick(player: Player, profile: Profile)
	local now = os.clock()
	local dt = now - profile.lastTick
	profile.lastTick = now
	profile.data.seconds += dt
	if player.Character then
		local class = classOf(player)
		profile.data.classSeconds[class] = (profile.data.classSeconds[class] or 0) + dt
	end
end

local function publish(player: Player, profile: Profile)
	local d = profile.data
	player:SetAttribute("CareerKills", d.kills)
	player:SetAttribute("CareerDeaths", d.deaths)
	player:SetAttribute("CareerSeconds", math.floor(d.seconds))
	player:SetAttribute("CareerClass", Career.mostUsedClass(d.classSeconds))
end

local function save(player: Player, profile: Profile)
	local ds = getStore()
	if not ds or not profile.loaded then
		return -- never overwrite saved stats we failed to load
	end
	tick(player, profile)
	local ok, err = pcall(ds.SetAsync, ds, keyOf(player), profile.data, { player.UserId })
	if not ok then
		warn("[Career] save failed for " .. player.Name .. ": " .. tostring(err))
	end
end

local function load(player: Player)
	local profile: Profile = { data = Career.new(), loaded = false, lastTick = os.clock() }
	profiles[player] = profile
	publish(player, profile)
	local ds = getStore()
	if not ds then
		return
	end
	for attempt = 1, 3 do
		local ok, raw = pcall(ds.GetAsync, ds, keyOf(player))
		if profiles[player] ~= profile then
			return -- left while loading
		end
		if ok then
			tick(player, profile)
			profile.data = Career.merge(Career.sanitize(raw), profile.data)
			profile.loaded = true
			publish(player, profile)
			return
		end
		warn(("[Career] load failed for %s (attempt %d): %s"):format(player.Name, attempt, tostring(raw)))
		task.wait(2 * attempt)
	end
	warn("[Career] stats for " .. player.Name .. " won't be saved this session")
end

-- A player's shot hit `model` (called by WeaponService).
function CareerService.noteHit(shooter: Player, model: Model)
	lastHit[model] = { player = shooter, at = os.clock() }
end

-- `player` died, or gave up while unconscious, as `character`. Counted once per character.
function CareerService.recordDeath(player: Player, model: Model?)
	if not model or counted[model] then
		return
	end
	local character = model :: Model
	counted[character] = true
	local profile = profiles[player]
	if profile then
		profile.data.deaths += 1
		publish(player, profile)
	end
	local hit = lastHit[character]
	lastHit[character] = nil
	if not hit or hit.player == player or not hit.player.Parent or os.clock() - hit.at > KILL_CREDIT_SECONDS then
		return
	end
	local team = player.Team
	if team and team == hit.player.Team and not player.Neutral then
		return -- team kill
	end
	local killer = profiles[hit.player]
	if killer then
		killer.data.kills += 1
		publish(hit.player, killer)
	end
end

local function onCharacter(player: Player, character: Model)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(game) then
			counted[character] = nil
			lastHit[character] = nil
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Once(function()
			CareerService.recordDeath(player, character)
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	load(player)
end

function CareerService.init()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			save(player, profile)
			profiles[player] = nil
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				save(player, profile)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
	task.spawn(function()
		local sinceSave = 0
		while true do
			task.wait(PUBLISH_SECONDS)
			sinceSave += PUBLISH_SECONDS
			local now = os.clock()
			for model, hit in lastHit do
				if now - hit.at > KILL_CREDIT_SECONDS or not model.Parent then
					lastHit[model] = nil
				end
			end
			for player, profile in profiles do
				tick(player, profile)
				publish(player, profile)
				if sinceSave >= AUTOSAVE_SECONDS then
					task.spawn(save, player, profile)
				end
			end
			if sinceSave >= AUTOSAVE_SECONDS then
				sinceSave = 0
			end
		end
	end)
end

return CareerService
