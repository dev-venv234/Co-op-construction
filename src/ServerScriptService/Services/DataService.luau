--!strict
-- Player profiles in a DataStore. When someone joins, everything they had comes back:
--   Cash, trade XP (all 4 trades), FirstPayout (unlocks the RV start), LastTrade (re-picked automatically),
--   Stats (jobs done, total earned, best grade), owned Vehicles, the Truck the player takes on jobs, and their
--   Settings (volumes, graphics, controls: saved through the validated SaveSettings remote, shown to the client as the
--   "Settings" attribute).
-- A session lock stops two servers from writing the same profile. Saves: every 2 minutes, after every payout,
-- on leave and on shutdown. Old profiles are upgraded in place (Version). If DataStores aren't available
-- (Studio with API access off), profiles live in memory only and nothing is saved.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Data = {}
Data.Loaded = Instance.new("BindableEvent") -- (player)

local STORE_NAME = "CoopProfiles_v1"
local VERSION = 4
local LOCK_SECONDS = 300
local AUTOSAVE_SECONDS = 120
local GRADE_RANK = { ["A+"] = 5, A = 4, B = 3, C = 2, D = 1 }

local store: DataStore? = nil
local profiles: { [Player]: any } = {}
local canSave: { [Player]: boolean } = {}

local function default(): { [string]: any }
	return {
		Version = VERSION,
		Cash = 0,
		FirstPayout = false,
		XP = { Foreman = 0, Laborer = 0, Operator = 0, Electrician = 0 },
		LastTrade = "",
		Stats = { JobsDone = 0, TotalEarned = 0, BestGrade = "" },
		Vehicles = { StarterTruck = true },
		Truck = "StarterTruck", -- the truck this player's jobs spawn with (must be owned)
		CompanyId = "", -- the company this player belongs to (CompanyService), "" = none
		CompanyRequest = "", -- a company this player asked to join and is waiting on
		-- Quality "Auto": the client picks (Medium on phones, High elsewhere) until the player chooses
		Settings = { Master = 1, Music = 0.5, Effects = 1, Ambient = 0.8, Quality = "Auto", DriveLayout = "Right", BigButtons = false },
	}
end

-- Fills in anything an older profile is missing (one level deep for tables).
local function upgrade(data: any): any
	local d = default()
	for k, v in d do
		if data[k] == nil then
			data[k] = v
		elseif type(v) == "table" and type(data[k]) == "table" then
			for k2, v2 in v do
				if data[k][k2] == nil then
					data[k][k2] = v2
				end
			end
		end
	end
	data.Version = VERSION
	return data
end

local function deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end

local function key(p: Player): string
	return "u_" .. p.UserId
end

-- What each setting may hold (anything else from a client is ignored).
local SETTING_RULES: { [string]: any } = {
	Master = "volume",
	Music = "volume",
	Effects = "volume",
	Ambient = "volume",
	Quality = { Auto = true, Low = true, Medium = true, High = true },
	DriveLayout = { Right = true, Left = true },
	BigButtons = "boolean",
}
local lastSettings: { [Player]: number } = {}

-- Display copies for the client (truck dealer prompt text): "Trucks" = owned kinds, "Truck" = the one in use.
local function publishTrucks(p: Player, prof: any)
	local owned = {}
	for kind, has in prof.Vehicles do
		if has == true then
			table.insert(owned, kind)
		end
	end
	table.sort(owned)
	p:SetAttribute("Trucks", table.concat(owned, ","))
	p:SetAttribute("Truck", if prof.Vehicles[prof.Truck] == true then prof.Truck else "StarterTruck")
end

function Data.Get(p: Player): any
	return profiles[p]
end

function Data.IsMemoryOnly(): boolean
	return store == nil
end

-- Waits (up to `timeout` seconds) for the player's profile.
function Data.WhenLoaded(p: Player, timeout: number?): any
	local t0 = os.clock()
	while not profiles[p] and p.Parent and os.clock() - t0 < (timeout or 20) do
		task.wait(0.2)
	end
	return profiles[p]
end

local function cashValue(p: Player): IntValue?
	local ls = p:FindFirstChild("leaderstats")
	return if ls then ls:FindFirstChild("Cash") :: IntValue? else nil
end

local function load(p: Player)
	local data: any = nil
	if store then
		for attempt = 1, 5 do
			local ok, result = pcall(function()
				return (store :: DataStore):UpdateAsync(key(p), function(old)
					old = old or default()
					local lock = old.Lock
					if lock and lock.Job ~= game.JobId and os.time() - (lock.Time or 0) < LOCK_SECONDS and attempt < 5 then
						return nil -- another server still holds this profile; try again shortly
					end
					old.Lock = { Job = game.JobId, Time = os.time() }
					return old
				end)
			end)
			if ok and type(result) == "table" and result.Lock and result.Lock.Job == game.JobId then
				data = result
				break
			end
			task.wait(2)
		end
		if data then
			canSave[p] = true
		else
			warn("[Data] could not load", p.Name, "- using a temporary profile that won't be saved")
		end
	end
	data = upgrade(data or default())
	data.Lock = nil
	-- Studio-only switch to test the returning-player flow without a real save
	if RunService:IsStudio() and workspace:GetAttribute("DevReturningPlayer") == true then
		data.FirstPayout = true
	end
	if not p.Parent then
		return
	end
	profiles[p] = data
	local ls = p:WaitForChild("leaderstats", 10)
	local cash = ls and ls:FindFirstChild("Cash") :: IntValue?
	if cash then
		cash.Value = data.Cash
	end
	p:SetAttribute("RVUnlocked", data.FirstPayout == true)
	p:SetAttribute("JobsDone", data.Stats.JobsDone)
	publishTrucks(p, data)
	p:SetAttribute("Settings", HttpService:JSONEncode(data.Settings))
	Data.Loaded:Fire(p)
end

function Data.Save(p: Player, release: boolean?)
	local prof = profiles[p]
	if not prof then
		return
	end
	local cash = cashValue(p)
	if cash then
		prof.Cash = cash.Value
	end
	if not store or not canSave[p] then
		return
	end
	local snapshot = deepCopy(prof)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function(old)
			if old and old.Lock and old.Lock.Job ~= game.JobId then
				return nil -- someone else owns it now; don't overwrite
			end
			snapshot.Lock = if release then nil else { Job = game.JobId, Time = os.time() }
			return snapshot
		end)
	end)
	if not ok then
		warn("[Data] save failed for", p.Name, err)
	end
end

-- Returns true the first time a player is paid (that unlocks the RV start).
function Data.MarkFirstPayout(p: Player): boolean
	local prof = profiles[p]
	if not prof or prof.FirstPayout then
		return false
	end
	prof.FirstPayout = true
	p:SetAttribute("RVUnlocked", true)
	return true
end

function Data.OwnsVehicle(p: Player, kind: string): boolean
	local prof = profiles[p]
	return prof ~= nil and prof.Vehicles[kind] == true
end

-- Only call after the purchase was paid for (DealerService).
function Data.GrantVehicle(p: Player, kind: string)
	local prof = profiles[p]
	if prof then
		prof.Vehicles[kind] = true
		publishTrucks(p, prof)
	end
end

-- The truck this player's jobs spawn with (falls back to the starter truck if it isn't owned).
function Data.SelectedTruck(p: Player): string
	local prof = profiles[p]
	if prof and prof.Vehicles[prof.Truck] == true then
		return prof.Truck
	end
	return "StarterTruck"
end

function Data.SetSelectedTruck(p: Player, kind: string): boolean
	local prof = profiles[p]
	if not prof or prof.Vehicles[kind] ~= true then
		return false
	end
	prof.Truck = kind
	publishTrucks(p, prof)
	return true
end

function Data.SetLastTrade(p: Player, trade: string)
	local prof = profiles[p]
	if prof then
		prof.LastTrade = trade
	end
end

function Data.RecordJob(p: Player, earned: number, grade: string)
	local prof = profiles[p]
	if not prof then
		return
	end
	local st = prof.Stats
	st.JobsDone += 1
	st.TotalEarned += earned
	if (GRADE_RANK[grade] or 0) > (GRADE_RANK[st.BestGrade] or 0) then
		st.BestGrade = grade
	end
	p:SetAttribute("JobsDone", st.JobsDone)
end

function Data.Start()
	local ok, result = pcall(function()
		local s = DataStoreService:GetDataStore(STORE_NAME)
		s:GetAsync("probe") -- fails here when API access is off
		return s
	end)
	if ok then
		store = result
	else
		warn("[Data] DataStores unavailable, profiles are memory-only:", result)
	end

	Players.PlayerAdded:Connect(function(p)
		task.spawn(load, p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		Data.Save(p, true)
		profiles[p] = nil
		canSave[p] = nil
		lastSettings[p] = nil
	end)

	-- Settings from the client: only known keys, of the right type and range, at most twice a second.
	Net.Event("SaveSettings").OnServerEvent:Connect(function(p: Player, t: unknown)
		local prof = profiles[p]
		if not prof or typeof(t) ~= "table" then
			return
		end
		local now = os.clock()
		if now - (lastSettings[p] or 0) < 0.5 then
			return
		end
		lastSettings[p] = now
		local given = t :: { [any]: any }
		for key, rule in SETTING_RULES do
			local v = given[key]
			if rule == "volume" then
				if typeof(v) == "number" and v == v then
					prof.Settings[key] = math.clamp(math.floor(v * 10 + 0.5) / 10, 0, 1)
				end
			elseif rule == "boolean" then
				if typeof(v) == "boolean" then
					prof.Settings[key] = v
				end
			elseif typeof(v) == "string" and (rule :: { [string]: boolean })[v] then
				prof.Settings[key] = v
			end
		end
		p:SetAttribute("Settings", HttpService:JSONEncode(prof.Settings))
	end)
	game:BindToClose(function()
		for p in profiles do
			task.spawn(Data.Save, p, true)
		end
		task.wait(3)
	end)
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for p in profiles do
			task.spawn(Data.Save, p, false)
		end
	end
end

return Data
