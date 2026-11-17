--!strict
-- Everyone on the server is one crew. Players pick a trade; slot limits come from Trades config.
-- Rule for small crews: if nobody holds a trade, anyone may do that trade's tasks (bots cover empty trades too).
-- Crew tools (all validated here):
--  * Quick Join: the server picks the trade the crew needs most (your last trade first if it's free).
--  * Forming a crew: when a player is the Foreman, only they start jobs at the site board (JobService asks
--    CanStartJobs). If no job has been started START_GRACE seconds after the crew became free, anyone may start one
--    (security audit H3: a Foreman can't hold the crew up).
--  * Pings: tap a preset ("Here", "Need help", "Bring lumber", "Watch out") and it shows a marker where you're
--    looking for the whole crew. Rate limited, position checked against the sender.
--  * Kick: always a vote of at least two people. With the Foreman among the voters one more crew member is enough;
--    otherwise most of the rest of the crew. Votes count for KICK_VOTE_SECONDS. (Audit H3: the Foreman used to
--    kick alone and at once, and the Foreman slot is first come, first served.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Trades = require(ReplicatedStorage.Shared.Config.Trades)

local Crew = {}
Crew.Changed = Instance.new("BindableEvent")

local roles: { [Player]: string } = {}
local S: any

function Crew.Init(services)
	S = services
end

function Crew.GetRole(p: Player): string?
	return roles[p]
end

local function countRole(role: string): number
	local n = 0
	for p, r in roles do
		if r == role and p.Parent then
			n += 1
		end
	end
	return n
end

function Crew.IsRoleHeld(role: string): boolean
	return countRole(role) > 0
end

function Crew.CanDo(p: Player, role: string): boolean
	local mine = roles[p]
	if not mine then
		return false
	end
	return mine == role or not Crew.IsRoleHeld(role)
end

function Crew.Snapshot(): { [string]: { string } }
	local out: { [string]: { string } } = {}
	for _, id in Trades.Order do
		out[id] = {}
	end
	for p, r in roles do
		if p.Parent and out[r] then
			table.insert(out[r], p.Name)
		end
	end
	return out
end

-- On join: put the player back in the trade they played last time (if that slot is free).
function Crew.TryRestore(p: Player): string?
	local prof = S.DataService.Get(p)
	local last = prof and prof.LastTrade
	if roles[p] or typeof(last) ~= "string" or not Trades.Info[last] then
		return roles[p]
	end
	if countRole(last) >= Trades.Info[last].Max then
		return nil
	end
	roles[p] = last
	Crew.Changed:Fire()
	return last
end

local START_GRACE = 90 -- seconds the Foreman has to start a job before anyone may
local KICK_VOTE_SECONDS = 120 -- how long a kick vote counts
local idleSince = os.clock() -- when the crew last became free to start a job (server start, or a job cleared)

-- When a player holds Foreman, only the Foreman starts jobs (they "form the crew and pick the job tier"), for the
-- first START_GRACE seconds the crew is free. After that anyone may: it's counted from when the crew became free,
-- not from when the Foreman took the trade, so re-picking Foreman doesn't reset it.
function Crew.CanStartJobs(p: Player): (boolean, string?)
	if Crew.IsRoleHeld("Foreman") and roles[p] ~= "Foreman" then
		local left = START_GRACE - (os.clock() - idleSince)
		if left > 0 then
			return false, ("The Foreman picks the job: ask them to tap a site button (anyone can start in %d s)"):format(math.ceil(left))
		end
	end
	return true, nil
end

-- Votes needed to remove a player. Never fewer than two people, the Foreman included.
function Crew.VotesNeeded(others: number, foremanVoted: boolean): number
	if foremanVoted then
		return 2
	end
	return math.max(2, math.floor(others / 2) + 1)
end

local PINGS = { Here = true, Help = true, Lumber = true, Danger = true }
local PING_RANGE = 300
local votes: { [Player]: { [Player]: number } } = {} -- target -> voter -> when they voted

local function setRole(p: Player, role: string)
	roles[p] = role
	S.DataService.SetLastTrade(p, role)
	Crew.Changed:Fire()
end

-- Trade the crew needs most: one the job uses that no player holds (bots don't count), the player's last trade first.
local function bestTradeFor(p: Player): string?
	local prof = S.DataService.Get(p)
	local last = prof and prof.LastTrade
	local order = table.clone(Trades.Order)
	if typeof(last) == "string" and table.find(order, last) then
		table.remove(order, table.find(order, last) :: number)
		table.insert(order, 1, last)
	end
	local job = S.JobService.Current()
	for _, role in order do
		if countRole(role) == 0 and (not job or S.JobService.UsesRole(role)) then
			return role
		end
	end
	for _, role in order do
		if countRole(role) < Trades.Info[role].Max then
			return role
		end
	end
	return nil
end

function Crew.Start()
	local Toast = Net.Event("Toast")
	S.JobService.Cleared.Event:Connect(function()
		idleSince = os.clock()
	end)
	local PingShown = Net.Event("PingShown")

	Net.Event("QuickJoin").OnServerEvent:Connect(function(p: Player)
		if not S.TaskEngine.Guard.Allow(p, "QuickJoin", 1) or S.TaskEngine.IsBusy(p) then
			return
		end
		-- Quick Join is for getting a trade; it never moves someone who already has one (a double tap would
		-- otherwise switch them away and clock out a bot mid-job). Switching stays on the TRADE button.
		if roles[p] then
			Toast:FireClient(p, "You're already the " .. roles[p] .. ". Tap TRADE to switch")
			return
		end
		local role = bestTradeFor(p)
		if not role then
			Toast:FireClient(p, "Every trade is full")
			return
		end
		if roles[p] == role then
			Toast:FireClient(p, "You're already the " .. role .. ", the crew needs you there")
			return
		end
		setRole(p, role)
		Toast:FireClient(p, "Quick Join: you're the " .. role .. " (the crew needed one)")
	end)

	Net.Event("Ping").OnServerEvent:Connect(function(p: Player, kind: unknown, pos: unknown)
		if typeof(kind) ~= "string" or not PINGS[kind] or typeof(pos) ~= "Vector3" then
			return
		end
		if not S.TaskEngine.Guard.Allow(p, "Ping", 1.2) then
			return
		end
		local c = p.Character
		local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (pos - root.Position).Magnitude > PING_RANGE or pos.Y ~= pos.Y then
			return
		end
		PingShown:FireAllClients({ from = p.Name, kind = kind, pos = pos, role = roles[p] })
	end)

	Net.Event("KickVote").OnServerEvent:Connect(function(p: Player, targetName: unknown)
		if typeof(targetName) ~= "string" or #targetName > 40 or not S.TaskEngine.Guard.Allow(p, "KickVote", 2) then
			return
		end
		local target = Players:FindFirstChild(targetName)
		if not target or not target:IsA("Player") or target == p then
			return
		end
		local now = os.clock()
		local v = votes[target] or {}
		votes[target] = v
		v[p] = now
		local have, foremanVoted = 0, false
		for voter, at in v do
			if voter.Parent == Players and now - at <= KICK_VOTE_SECONDS then
				have += 1
				foremanVoted = foremanVoted or roles[voter] == "Foreman"
			else
				v[voter] = nil -- left, or the vote is too old
			end
		end
		local need = Crew.VotesNeeded(#Players:GetPlayers() - 1, foremanVoted)
		if have >= need then
			votes[target] = nil
			Toast:FireAllClients(if foremanVoted then ("%s was removed from the crew by the Foreman and the crew"):format(target.Name)
				else ("%s was voted out of the crew"):format(target.Name))
			target:Kick("Your crew voted to remove you.")
		else
			Toast:FireAllClients(("Vote to remove %s: %d/%d%s"):format(target.Name, have, need,
				if foremanVoted then " (the Foreman needs one more crew member to agree)" else ""))
		end
	end)

	Net.Event("PickRole").OnServerEvent:Connect(function(p: Player, role: unknown)
		if typeof(role) ~= "string" or not Trades.Info[role] then
			warn("[Crew] rejected PickRole from", p.Name, role)
			return
		end
		if not S.TaskEngine.Guard.Allow(p, "PickRole", 0.5) then
			return
		end
		if roles[p] == role then
			return
		end
		if S.TaskEngine.IsBusy(p) then
			Toast:FireClient(p, "Finish your current task first")
			return
		end
		if countRole(role) >= Trades.Info[role].Max then
			Toast:FireClient(p, role .. " is taken")
			return
		end
		roles[p] = role
		S.DataService.SetLastTrade(p, role)
		Toast:FireClient(p, "You're the " .. role)
		Crew.Changed:Fire()
	end)
	Players.PlayerRemoving:Connect(function(p)
		votes[p] = nil
		for _, v in votes do
			v[p] = nil
		end
		if roles[p] then
			roles[p] = nil
			Crew.Changed:Fire()
		end
	end)
end

return Crew
