--!strict
-- Crews (2026-11-17, owner: "5-8 companies per server"). A server holds up to MAX_CREWS crews at once; each has its
-- own trades, job, lot, truck, bots, inspection and pay (JobService keeps one job per crew).
--  * Getting a crew: picking a trade without one puts you in your company's crew if it's on this server (and has
--    room), else in a new crew of your own (bots fill the trades nobody holds), or, once every crew slot is taken,
--    in the crew with room that needs your trade most. QUICK JOIN joins a crew that needs your trade (one already
--    on a job first). The CREW panel lists every crew: JOIN one, start a NEW CREW, or LEAVE yours.
--  * A crew is named after the company of the player who started it ("Crew <n>" without one).
--  * Inside a crew the old rules hold: if nobody in the crew holds a trade, any member may do that trade's tasks
--    (bots cover empty trades too); while a member is Foreman, only they start jobs for START_GRACE seconds after the
--    crew became free (security audit H3: a Foreman can't hold the crew up).
--  * Pings go to your crewmates only.
--  * Kick: a vote of most of the rest of the crew, never fewer than two people; the Foreman's vote counts like
--    anyone's. Votes count for KICK_VOTE_SECONDS. Voted out = out of that crew and barred from it (not off the server).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Trades = require(ReplicatedStorage.Shared.Config.Trades)

local CrewService = {}
-- (Lua signals, not BindableEvents: those would hand listeners a copy of the crew table)
CrewService.Changed = Signal.new() -- (crew: Crew) members or trades changed
CrewService.Emptied = Signal.new() -- (crew: Crew) the last member left; the crew is gone after this

CrewService.MAX_CREWS = 6
CrewService.MAX_MEMBERS = 6

export type Crew = {
	id: number,
	name: string,
	companyId: string, -- "" for a pickup crew
	members: { [Player]: boolean },
	roles: { [Player]: string }, -- members who picked a trade
	idleSince: number, -- when the crew last became free to start a job
	votes: { [Player]: { [Player]: number } }, -- target -> voter -> when
	barred: { [number]: boolean }, -- user ids voted out of this crew
}

local crews: { [number]: Crew } = {}
local crewOf: { [Player]: Crew } = {}
local S: any
local Toast: RemoteEvent

local START_GRACE = 60 -- seconds the Foreman has to start a job before anyone may
local KICK_VOTE_SECONDS = 120 -- how long a kick vote counts
local PINGS = { Here = true, Help = true, Lumber = true, Danger = true }
local PING_RANGE = 300

function CrewService.Init(services)
	S = services
end

---------------------------------------------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------------------------------------------

function CrewService.Of(p: Player): Crew?
	return crewOf[p]
end

function CrewService.ById(id: number): Crew?
	return crews[id]
end

-- Every crew on the server, by id.
function CrewService.All(): { Crew }
	local out = {}
	for _, c in crews do
		table.insert(out, c)
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

function CrewService.Members(crew: Crew): { Player }
	local out = {}
	for p in crew.members do
		if p.Parent == Players then
			table.insert(out, p)
		end
	end
	return out
end

function CrewService.Count(crew: Crew): number
	return #CrewService.Members(crew)
end

-- A message for one crew only.
function CrewService.Toast(crew: Crew?, text: string)
	if not crew then
		return
	end
	for _, p in CrewService.Members(crew) do
		Toast:FireClient(p, text)
	end
end

function CrewService.GetRole(p: Player): string?
	local c = crewOf[p]
	return if c then c.roles[p] else nil
end

local function countRole(crew: Crew, role: string): number
	local n = 0
	for p, r in crew.roles do
		if r == role and p.Parent then
			n += 1
		end
	end
	return n
end

function CrewService.IsRoleHeld(crew: Crew?, role: string): boolean
	return crew ~= nil and countRole(crew, role) > 0
end

-- May this player do this trade's tasks? Their own trade, or one nobody in their crew holds.
function CrewService.CanDo(p: Player, role: string): boolean
	local c = crewOf[p]
	local mine = c and c.roles[p]
	if not c or not mine then
		return false
	end
	return mine == role or countRole(c, role) == 0
end

-- Who holds each trade in this crew (all trades listed, empty when nobody).
function CrewService.Snapshot(crew: Crew?): { [string]: { string } }
	local out: { [string]: { string } } = {}
	for _, id in Trades.Order do
		out[id] = {}
	end
	if crew then
		for p, r in crew.roles do
			if p.Parent and out[r] then
				table.insert(out[r], p.Name)
			end
		end
	end
	return out
end

-- When a member is Foreman, only the Foreman starts jobs for the first START_GRACE seconds the crew is free. Counted
-- from when the crew became free, not from when the Foreman took the trade, so re-picking Foreman doesn't reset it.
function CrewService.CanStartJobs(p: Player): (boolean, string?)
	local c = crewOf[p]
	if not c then
		return false, "Pick a trade first"
	end
	if countRole(c, "Foreman") > 0 and c.roles[p] ~= "Foreman" then
		local left = START_GRACE - (os.clock() - c.idleSince)
		if left > 0 then
			return false, ("The Foreman picks the job: ask them to tap a site button (anyone can start in %d s)"):format(math.ceil(left))
		end
	end
	return true, nil
end

-- JobService: the crew's job was cleared, so it's free to start the next one.
function CrewService.MarkIdle(crew: Crew)
	crew.idleSince = os.clock()
end

-- Votes needed to remove a player: most of the rest of the crew, never fewer than two.
function CrewService.VotesNeeded(others: number): number
	return math.max(2, math.floor(others / 2) + 1)
end

---------------------------------------------------------------------------------------------------------------
-- Joining and leaving
---------------------------------------------------------------------------------------------------------------

local function companyIdOf(p: Player): string
	local prof = S.DataService.Get(p)
	return if prof and typeof(prof.CompanyId) == "string" then prof.CompanyId else ""
end

local function hasRoom(c: Crew, role: string?): boolean
	if CrewService.Count(c) >= CrewService.MAX_MEMBERS then
		return false
	end
	return role == nil or countRole(c, role) < Trades.Info[role].Max
end

local function nextId(): number?
	for i = 1, CrewService.MAX_CREWS do
		if not crews[i] then
			return i
		end
	end
	return nil
end

local function tag(p: Player)
	local c = crewOf[p]
	p:SetAttribute("CrewId", if c then c.id else nil)
	p:SetAttribute("CrewName", if c then c.name else nil)
end

local function newCrew(founder: Player): Crew?
	local id = nextId()
	if not id then
		return nil
	end
	local cid = companyIdOf(founder)
	local company = founder:GetAttribute("Company")
	local name = if cid ~= "" and typeof(company) == "string" and company ~= "" then company else ("Crew %d"):format(id)
	-- two crews of one company on a server: number the second one
	for _, other in crews do
		if other.name == name then
			name = ("%s %d"):format(name, id)
		end
	end
	local c: Crew = {
		id = id,
		name = name,
		companyId = cid,
		members = {},
		roles = {},
		idleSince = os.clock(),
		votes = {},
		barred = {},
	}
	crews[id] = c
	return c
end

local function removeFrom(p: Player)
	local c = crewOf[p]
	if not c then
		return
	end
	crewOf[p] = nil
	c.members[p] = nil
	c.roles[p] = nil
	c.votes[p] = nil
	for _, v in c.votes do
		v[p] = nil
	end
	if p.Parent then
		tag(p)
		S.TaskEngine.Cancel(p, "You left the crew")
		S.TaskEngine.Carry.Drop(p)
	end
	if CrewService.Count(c) == 0 then
		CrewService.Emptied:Fire(c)
		crews[c.id] = nil
	else
		CrewService.Changed:Fire(c)
	end
end

-- Puts a player in a crew (leaving their old one). role: the trade to take there, when it's free.
local function join(p: Player, c: Crew, role: string?)
	if crewOf[p] == c then
		if role and not c.roles[p] and countRole(c, role) < Trades.Info[role].Max then
			c.roles[p] = role
			S.DataService.SetLastTrade(p, role)
			CrewService.Changed:Fire(c)
		end
		return
	end
	removeFrom(p)
	crewOf[p] = c
	c.members[p] = true
	if role and countRole(c, role) < Trades.Info[role].Max then
		c.roles[p] = role
		S.DataService.SetLastTrade(p, role)
	end
	tag(p)
	CrewService.Changed:Fire(c)
end

-- The crew a player without one goes to when they pick `role`: their company's crew here, else a new crew, else the
-- crew with room that needs that trade most (nobody holds it), else any crew with room for it.
local function crewFor(p: Player, role: string?): (Crew?, string?)
	local cid = companyIdOf(p)
	if cid ~= "" then
		for _, c in CrewService.All() do
			if c.companyId == cid and not c.barred[p.UserId] and hasRoom(c, role) then
				return c, nil
			end
		end
	end
	local fresh = if nextId() then newCrew(p) else nil
	if fresh then
		return fresh, nil
	end
	local best: Crew?, bestScore = nil, -1
	for _, c in CrewService.All() do
		if not c.barred[p.UserId] and hasRoom(c, role) then
			local score = CrewService.Count(c) + (if role and countRole(c, role) == 0 then 10 else 0)
			if score > bestScore then
				best, bestScore = c, score
			end
		end
	end
	if best then
		return best, nil
	end
	return nil, "Every crew on this server is full right now"
end

-- Trade the crew needs most: one its job uses that no player holds (bots don't count), the player's last trade first.
local function bestTradeFor(p: Player, c: Crew?): string?
	local prof = S.DataService.Get(p)
	local last = prof and prof.LastTrade
	local order = table.clone(Trades.Order)
	if typeof(last) == "string" and table.find(order, last) then
		table.remove(order, table.find(order, last) :: number)
		table.insert(order, 1, last)
	end
	local job = if c then S.JobService.Of(c) else nil
	for _, role in order do
		if (not c or countRole(c, role) == 0) and (not job or S.JobService.UsesRole(job, role)) then
			return role
		end
	end
	if c then
		for _, role in order do
			if countRole(c, role) < Trades.Info[role].Max then
				return role
			end
		end
	end
	return nil
end

-- On join: put the player back in the trade they played last time (in their company's crew or a new one).
function CrewService.TryRestore(p: Player): string?
	local prof = S.DataService.Get(p)
	local last = prof and prof.LastTrade
	if crewOf[p] or typeof(last) ~= "string" or not Trades.Info[last] then
		return CrewService.GetRole(p)
	end
	local c = crewFor(p, last)
	if not c then
		return nil
	end
	join(p, c, last)
	return CrewService.GetRole(p)
end

-- Board data for every client: each crew, who's in it, and what it needs (JobService adds the job info).
function CrewService.Board(): { { [string]: any } }
	local out = {}
	for _, c in CrewService.All() do
		local open = {}
		for _, role in Trades.Order do
			if countRole(c, role) == 0 then
				table.insert(open, role)
			end
		end
		local names = {}
		for _, p in CrewService.Members(c) do
			table.insert(names, p.DisplayName)
		end
		table.insert(out, {
			id = c.id,
			name = c.name,
			count = #names,
			max = CrewService.MAX_MEMBERS,
			names = names,
			open = open,
			company = c.companyId ~= "",
		})
	end
	return out
end

---------------------------------------------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------------------------------------------

local function busy(p: Player): boolean
	if S.TaskEngine.IsBusy(p) then
		Toast:FireClient(p, "Finish your current task first")
		return true
	end
	return false
end

local function onQuickJoin(p: Player)
	if not S.TaskEngine.Guard.Allow(p, "QuickJoin", 1) or S.TaskEngine.IsBusy(p) then
		return
	end
	local mine = crewOf[p]
	-- Quick Join is for getting a trade; it never moves someone who already has one (a double tap would otherwise
	-- switch them away and clock out a bot mid-job). Switching stays on the TRADE button.
	if mine and mine.roles[p] then
		Toast:FireClient(p, "You're already the " .. mine.roles[p] .. ". Tap TRADE to switch")
		return
	end
	if mine then
		local role = bestTradeFor(p, mine)
		if not role then
			Toast:FireClient(p, "Every trade in your crew is full")
			return
		end
		join(p, mine, role)
		Toast:FireClient(p, "Quick Join: you're the " .. role .. " (your crew needed one)")
		return
	end
	-- no crew yet: a crew that needs one of my trades, one already on a job first, then the fullest
	local best: Crew?, bestRole: string?, bestScore = nil, nil, -1
	for _, c in CrewService.All() do
		if not c.barred[p.UserId] and CrewService.Count(c) < CrewService.MAX_MEMBERS then
			local role = bestTradeFor(p, c)
			if role and countRole(c, role) == 0 then
				local score = (if S.JobService.Of(c) then 100 else 0) + CrewService.Count(c)
				if score > bestScore then
					best, bestRole, bestScore = c, role, score
				end
			end
		end
	end
	if best and bestRole then
		join(p, best, bestRole)
		Toast:FireClient(p, ("Quick Join: you're the %s on %s"):format(bestRole, best.name))
		return
	end
	local role = bestTradeFor(p, nil) or "Laborer"
	local c, why = crewFor(p, role)
	if not c then
		Toast:FireClient(p, why or "No crew has room")
		return
	end
	join(p, c, role)
	Toast:FireClient(p, ("Quick Join: no crew needed you, so you started %s as the %s (bots fill the other trades)"):format(c.name, role))
end

local function onPickRole(p: Player, role: unknown)
	if typeof(role) ~= "string" or not Trades.Info[role] then
		warn("[Crew] rejected PickRole from", p.Name, role)
		return
	end
	if not S.TaskEngine.Guard.Allow(p, "PickRole", 0.5) then
		return
	end
	local c = crewOf[p]
	if c and c.roles[p] == role then
		return
	end
	if busy(p) then
		return
	end
	if not c then
		local why
		c, why = crewFor(p, role)
		if not c then
			Toast:FireClient(p, why or "No crew has room")
			return
		end
		join(p, c, role)
		Toast:FireClient(p, ("You're the %s on %s"):format(role, c.name))
		return
	end
	if countRole(c, role) >= Trades.Info[role].Max then
		Toast:FireClient(p, role .. " is taken in your crew")
		return
	end
	c.roles[p] = role
	S.DataService.SetLastTrade(p, role)
	Toast:FireClient(p, "You're the " .. role)
	CrewService.Changed:Fire(c)
end

-- CREW panel: ("Join", crewId) | ("New") | ("Leave")
local function onCrewAction(p: Player, action: unknown, arg: unknown)
	if typeof(action) ~= "string" or not S.TaskEngine.Guard.Allow(p, "CrewAction", 1) then
		return
	end
	if action == "Leave" then
		local c = crewOf[p]
		if not c or busy(p) then
			return
		end
		local working = S.JobService.Of(c) ~= nil
		removeFrom(p)
		Toast:FireClient(p, if working then "You left the crew (no pay for that job). Pick a trade or join another crew"
			else "You left the crew. Pick a trade or join another crew")
	elseif action == "New" then
		if busy(p) then
			return
		end
		local mine = crewOf[p]
		if mine and CrewService.Count(mine) == 1 and not S.JobService.Of(mine) then
			Toast:FireClient(p, "You're already on a crew of your own")
			return
		end
		if not nextId() then
			Toast:FireClient(p, ("This server already has %d crews: join one of them"):format(CrewService.MAX_CREWS))
			return
		end
		local role = CrewService.GetRole(p)
		removeFrom(p)
		local c = newCrew(p)
		if not c then
			return
		end
		join(p, c, role)
		Toast:FireClient(p, ("You started %s. Bots fill the trades nobody holds; others can JOIN from the CREW panel"):format(c.name))
	elseif action == "Join" then
		if typeof(arg) ~= "number" or arg ~= arg then
			return
		end
		local c = crews[math.floor(arg)]
		if not c or crewOf[p] == c or busy(p) then
			return
		end
		if c.barred[p.UserId] then
			Toast:FireClient(p, "That crew voted you out")
			return
		end
		local role = CrewService.GetRole(p)
		if not hasRoom(c, nil) then
			Toast:FireClient(p, c.name .. " is full")
			return
		end
		local keep = if role and countRole(c, role) < Trades.Info[role].Max then role else nil
		join(p, c, keep)
		Toast:FireClient(p, ("You joined %s%s"):format(c.name,
			if keep then " as the " .. keep elseif role then (": " .. role .. " is taken there, pick another trade") else ": pick a trade"))
	end
end

function CrewService.Start()
	Toast = Net.Event("Toast")
	local PingShown = Net.Event("PingShown")

	Net.Event("QuickJoin").OnServerEvent:Connect(onQuickJoin)
	Net.Event("PickRole").OnServerEvent:Connect(onPickRole)
	Net.Event("CrewAction").OnServerEvent:Connect(onCrewAction)

	Net.Event("Ping").OnServerEvent:Connect(function(p: Player, kind: unknown, pos: unknown)
		if typeof(kind) ~= "string" or not PINGS[kind] or typeof(pos) ~= "Vector3" then
			return
		end
		if not S.TaskEngine.Guard.Allow(p, "Ping", 1.2) then
			return
		end
		local c = crewOf[p]
		local ch = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not c or not root or pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z or (pos - root.Position).Magnitude > PING_RANGE then
			return
		end
		for _, mate in CrewService.Members(c) do
			PingShown:FireClient(mate, { from = p.Name, kind = kind, pos = pos, role = c.roles[p] })
		end
	end)

	Net.Event("KickVote").OnServerEvent:Connect(function(p: Player, targetName: unknown)
		if typeof(targetName) ~= "string" or #targetName > 40 or not S.TaskEngine.Guard.Allow(p, "KickVote", 2) then
			return
		end
		local c = crewOf[p]
		local target = Players:FindFirstChild(targetName)
		if not c or not target or not target:IsA("Player") or target == p or crewOf[target] ~= c then
			return
		end
		local now = os.clock()
		local v = c.votes[target] or {}
		c.votes[target] = v
		v[p] = now
		local have = 0
		for voter, at in v do
			if crewOf[voter] == c and now - at <= KICK_VOTE_SECONDS then
				have += 1
			else
				v[voter] = nil -- left the crew, or the vote is too old
			end
		end
		local need = CrewService.VotesNeeded(CrewService.Count(c) - 1)
		if have >= need then
			c.votes[target] = nil
			c.barred[target.UserId] = true
			CrewService.Toast(c, ("%s was voted out of the crew"):format(target.Name))
			removeFrom(target)
			Toast:FireClient(target, "Your crew voted you out. Join another crew or start your own")
		else
			CrewService.Toast(c, ("Vote to remove %s from the crew: %d/%d"):format(target.Name, have, need))
		end
	end)

	Players.PlayerRemoving:Connect(removeFrom)
end

return CrewService
