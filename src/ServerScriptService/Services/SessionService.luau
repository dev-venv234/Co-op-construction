--!strict
-- Session flow: where players appear and when (owner rule, 2026-11-11: everyone who joins starts at the RV park).
--  * Joining: returning players (the first payout unlocks their own RV) spawn at their RV; first-time players
--    spawn on the RV park camp lane next to the coffee stand and the truck lot board. Nobody is dropped into a job.
--    If a crew is already working, the guide points the joiner at that site's board button, which gives them a
--    ride out to the site (JobService).
--  * Respawning during a job you've worked on puts you back at its site; otherwise you go back to the RV park.
--  * When a job is cleared, everyone heads back to the RV park for the next 4:00 AM shift.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Session = {}

local S: any
local rvOf: { [Player]: number } = {}
local rvSpawns: { [number]: BasePart } = {}
local rvCount = 0
local campSpawn = CFrame.new(-110, 4, -288)

function Session.Init(services)
	S = services
end

local function returning(p: Player): boolean
	local prof = S.DataService.Get(p)
	return prof ~= nil and prof.FirstPayout == true
end

local function assignRV(p: Player)
	if rvOf[p] then
		return
	end
	local used: { [number]: boolean } = {}
	for _, i in rvOf do
		used[i] = true
	end
	for i = 1, rvCount do
		if rvSpawns[i] and not used[i] then
			rvOf[p] = i
			p:SetAttribute("RV", i)
			return
		end
	end
end

-- The player's spot at the RV park: their own RV, or the camp lane until they've earned one.
local function parkCFrame(p: Player): CFrame
	local i = if returning(p) then rvOf[p] else nil
	local sp = if i then rvSpawns[i] else nil
	if sp then
		local pos = sp.Position + Vector3.new(0, 3, 0)
		return CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0))
	end
	return campSpawn
end

-- Has this player worked on the running job? (Only they respawn at its site.)
local function inJob(p: Player): boolean
	local cur = S.JobService.Current()
	if not cur or cur.finishing then
		return false
	end
	return (S.QualityService.Contributors()[p] or 0) > 0
end

local function place(p: Player, joining: boolean)
	local c = p.Character
	if not c then
		return
	end
	local root = c:FindFirstChild("HumanoidRootPart") or c:WaitForChild("HumanoidRootPart", 5)
	if not root or not c.Parent then
		return
	end
	local target = parkCFrame(p)
	if not joining and inJob(p) then
		target = S.JobService.SiteSpawn() or target
	end
	c:PivotTo(target)
	if S.MoveGuard then
		S.MoveGuard.Snap(p, target.Position) -- the server moved them: that spot is trusted
	end
end

local function onJoin(p: Player)
	local prof = S.DataService.WhenLoaded(p)
	if not prof or not p.Parent then
		return
	end
	local Toast = Net.Event("Toast")
	local trade = S.CrewService.TryRestore(p) -- back in last session's trade
	if returning(p) then
		assignRV(p)
	end
	place(p, true)
	if returning(p) then
		local level = if trade then p:GetAttribute("Level_" .. trade) else nil
		local cash = p:FindFirstChild("leaderstats") and (p.leaderstats :: any).Cash.Value or 0
		Toast:FireClient(p, ("Welcome back! %s%s, $%d in the bank, %d jobs done."):format(
			trade or "No trade yet", if typeof(level) == "number" then " Lv " .. level else "", cash, prof.Stats.JobsDone))
	else
		Toast:FireClient(p, "Welcome to the crew! Pick a trade, grab a coffee, then start Site 1 at the truck lot board.")
	end
	local cur = S.JobService.Current()
	if cur and not cur.finishing then
		Toast:FireClient(p, ("A crew is working at Site %d right now: tap its button on the JOB SITES board to ride out."):format(cur.tier))
	elseif returning(p) then
		Toast:FireClient(p, "4:00 AM. Grab a coffee, then pick a site on the board at the truck lot.")
	end
end

local function onCleared()
	local Toast = Net.Event("Toast")
	for _, p in Players:GetPlayers() do
		if returning(p) then
			assignRV(p)
		end
		place(p, true)
		Toast:FireClient(p, if returning(p)
			then "Shift over. You're back at your RV: next shift starts at 4:00 AM."
			else "Shift over. Back at the RV park: grab a coffee and start the next job at the truck lot board.")
	end
end

function Session.Start()
	local park = workspace:WaitForChild("RVPark", 10)
	if park then
		for _, d in park:GetDescendants() do
			local i = d:GetAttribute("RVSpawn")
			if d:IsA("BasePart") and typeof(i) == "number" then
				rvSpawns[i] = d
				rvCount = math.max(rvCount, i)
			end
		end
	end
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		campSpawn = CFrame.new(spawn.Position + Vector3.new(0, 3.5, 0))
	end

	local function hook(p: Player)
		p.CharacterAdded:Connect(function()
			if S.DataService.Get(p) then
				task.defer(place, p, false) -- respawn: back to the job if you were working on it
			end
		end)
		task.spawn(onJoin, p)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		rvOf[p] = nil
	end)
	S.JobService.Cleared.Event:Connect(onCleared)
end

return Session
