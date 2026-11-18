--!strict
-- Crew vs crew on one server (owner 2026-11-17: "its still co op in your team/company/crew but your competing against
-- other crews"). Everything here is decided on the server from server-side job results.
--  * Standings: every job a crew finishes (passes inspection) earns crew points: BasePay / 100 x the grade
--    (A+ 1.5, A 1.3, B 1.1, C 1, D 0.8), +2 for finishing early, +5 for winning a race. Points last as long as the
--    crew exists on this server. The leading crew wears a crown (player attribute TopCrew) and the server hears it
--    when the lead changes.
--  * Races: a crew that starts the same site (tier) as another crew within RACE_WINDOW seconds of it is in a race with
--    it. The first of the two to pass inspection wins RACE_BONUS extra pay (on each paid member's paycheck, before the
--    2x Pay pass) and the race points. The other crew is paid as usual: a race never costs anything. If the rival
--    drops out (out of time, or the crew left), the one still building wins when it passes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local League = {}

local RACE_WINDOW = 90 -- seconds between two crews starting the same site for it to be a race
local RACE_BONUS = 0.2 -- extra pay for the race winner (share of each paid member's paycheck)
local RACE_POINTS = 5
local EARLY_POINTS = 2
local GRADE_MULT = { ["A+"] = 1.5, A = 1.3, B = 1.1, C = 1, D = 0.8 }

type Score = { points: number, jobs: number, best: string?, wins: number }

local S: any
local Toast: RemoteEvent
local scores: { [any]: Score } = {} -- crew -> its standing on this server
local leader: any = nil

function League.Init(services)
	S = services
end

local function scoreOf(crew: any): Score
	local s = scores[crew]
	if not s then
		s = { points = 0, jobs = 0, best = nil, wins = 0 }
		scores[crew] = s
	end
	return s
end

local GRADE_ORDER = { D = 1, C = 2, B = 3, A = 4, ["A+"] = 5 }

-- Standings, best first (sent to every client with the crew board).
function League.Standings(): { { [string]: any } }
	local out = {}
	for _, crew in S.CrewService.All() do
		local s = scores[crew]
		table.insert(out, {
			id = crew.id,
			name = crew.name,
			points = if s then s.points else 0,
			jobs = if s then s.jobs else 0,
			best = if s then s.best else nil,
			wins = if s then s.wins else 0,
		})
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return a.id < b.id
	end)
	return out
end

-- The crown goes to the crew with the most points (none while nobody has scored).
local function refreshLeader(announce: boolean)
	local best, bestPts = nil, 0
	for _, crew in S.CrewService.All() do
		local s = scores[crew]
		if s and s.points > bestPts then
			best, bestPts = crew, s.points
		end
	end
	if best ~= leader then
		leader = best
		if announce and best then
			Toast:FireAllClients(("%s takes the lead on this server with %d points!"):format(best.name, bestPts))
		end
	end
	for _, p in Players:GetPlayers() do
		local c = S.CrewService.Of(p)
		p:SetAttribute("TopCrew", if c ~= nil and c == leader then true else nil)
	end
end

-- What a job's crew sees about its race (sent with its state), or nil.
function League.RaceInfo(cur: any): { [string]: any }?
	local race = cur.race
	if not race then
		return nil
	end
	local rival = race.rival
	local info: { [string]: any } = { rival = rival.crew.name, result = race.result }
	if not race.result then
		if S.JobService.Live(rival) and not race.rivalOut then
			local done, total = 0, 0
			for _, id in rival.order do
				total += 1
				if rival.slots[id] and rival.slots[id].done then
					done += 1
				end
			end
			info.theirDone, info.theirTotal = done, total
		else
			info.rivalOut = true
		end
	end
	return info
end

-- Called by JobService.finish when a job passes inspection, before the payout: the extra pay share for winning a race
-- (0 when it isn't racing or already lost). Settles the race for both crews.
function League.ClaimRace(cur: any): number
	local race = cur.race
	if not race or race.result then
		return 0
	end
	local rival = race.rival
	race.result = "won"
	if rival.race and rival.race.rival == cur and not rival.race.result then
		rival.race.result = "lost"
		S.JobService.Toast(rival, ("%s passed inspection first and won the race. Finish strong: you still get full pay"):format(cur.crew.name))
	end
	Toast:FireAllClients(("RACE WON: %s beat %s at the %s!"):format(cur.crew.name, rival.crew.name, cur.bp.DisplayName))
	S.JobService.Broadcast()
	return RACE_BONUS
end

-- Called by JobService.finish after the payout of a job that passed inspection.
function League.JobDone(cur: any, grade: string, early: boolean)
	local s = scoreOf(cur.crew)
	local won = cur.race ~= nil and cur.race.result == "won"
	local pts = math.floor(cur.cfg.BasePay / 100 * (GRADE_MULT[grade] or 1) + 0.5)
		+ (if early then EARLY_POINTS else 0) + (if won then RACE_POINTS else 0)
	s.points += pts
	s.jobs += 1
	if won then
		s.wins += 1
	end
	if not s.best or (GRADE_ORDER[grade] or 0) > (GRADE_ORDER[s.best] or 0) then
		s.best = grade
	end
	S.JobService.Toast(cur, ("+%d crew points (%d total)"):format(pts, s.points))
	refreshLeader(true)
	S.JobService.Broadcast()
end

-- A new job races a job of another crew at the same site that started less than RACE_WINDOW seconds ago.
local function pairUp(cur: any)
	for _, other in S.JobService.All() do
		if other ~= cur and other.crew ~= cur.crew and other.siteId == cur.siteId and not other.finishing
			and not other.race and cur.startedAt - other.startedAt <= RACE_WINDOW then
			cur.race = { rival = other }
			other.race = { rival = cur }
			local what = cur.bp.DisplayName
			S.JobService.Toast(cur, ("RACE! %s is building a %s too. First to pass inspection gets +%d%% pay"):format(
				other.crew.name, what, math.floor(RACE_BONUS * 100)))
			S.JobService.Toast(other, ("RACE! %s just started a %s too. First to pass inspection gets +%d%% pay"):format(
				cur.crew.name, what, math.floor(RACE_BONUS * 100)))
			Toast:FireAllClients(("%s vs %s: %s race!"):format(other.crew.name, cur.crew.name, what))
			Net.Cue("Whistle", nil)
			S.JobService.Broadcast()
			return
		end
	end
end

-- A job ended without passing (out of time, or the crew left): its rival wins when it passes.
local function dropOut(cur: any)
	local race = cur.race
	if not race or race.result then
		return
	end
	race.result = "out"
	local rival = race.rival
	if rival.race and rival.race.rival == cur and not rival.race.result then
		rival.race.rivalOut = true
		S.JobService.Toast(rival, ("%s dropped out of the race: pass inspection to win it"):format(cur.crew.name))
	end
	S.JobService.Broadcast()
end

function League.Start()
	Toast = Net.Event("Toast")
	S.JobService.Started.Event:Connect(pairUp)
	S.JobService.Ended.Event:Connect(function(cur, success: boolean)
		if not success then
			dropOut(cur)
		end
	end)
	S.CrewService.Emptied.Event:Connect(function(crew)
		scores[crew] = nil
		task.defer(refreshLeader, false)
	end)
	S.CrewService.Changed.Event:Connect(function()
		refreshLeader(false) -- crown on whoever is in the leading crew now
	end)
end

return League
