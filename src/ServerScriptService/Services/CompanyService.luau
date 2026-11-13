--!strict
-- Companies and the company leaderboard (owner request 2026-11-12; PLAN.md had "Own Your Company" and leaderboards
-- as post-launch, the owner pulled them in).
--  * Found: a player without a company taps START COMPANY and types a name (Roblox text filter, 3-24 characters).
--  * Invite: members invite players in the same server; the invitee taps JOIN.
--  * Request: players without a crew pick a company in FIND (recently active, with room) and ask to join; any member,
--    in any server, accepts or declines it from the COMPANY panel. The answer reaches the player on their server's
--    next refresh (or when they next join).
--  * Leave any time; the owner can remove members; an empty company closes. Up to MAX_MEMBERS members.
--  * Points: every paid job adds base pay / 10 x grade (A+ 1.5, A 1.25, B 1, C 0.75, D 0.5) for each member who
--    worked it, so bigger buildings, better grades and bigger crews climb faster. Titles by points.
--  * Leaderboard: top 20 by points across all servers (OrderedDataStore), on the board at the RV park and in the
--    COMPANY panel. Without DataStores (Studio with API access off) everything lives in memory for this server.
-- The server owns all of it: names are filtered, every action is re-checked (membership, room, owner, rate limits).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Company = {}

local MAX_MEMBERS = 12
local REFRESH = 30 -- seconds: membership / requests / titles for players in this server
local BOARD_REFRESH = 60 -- seconds: the top-20 leaderboard
local CACHE_TTL = 25
local TOP = 20
local INVITE_TTL = 120
local GRADE_MULT = { ["A+"] = 1.5, A = 1.25, B = 1, C = 0.75, D = 0.5 }
local TITLES = {
	{ 40000, "Construction Empire" },
	{ 10000, "Regional Builder" },
	{ 2500, "Builder" },
	{ 500, "Local Contractor" },
	{ 0, "Startup" },
}

local S: any
local Toast: RemoteEvent
local DataEvent: RemoteEvent

-- storage (DataStores, or memory)
local store: DataStore? = nil
local scores: OrderedDataStore? = nil
local active: OrderedDataStore? = nil
local mem = { records = {} :: { [string]: any }, scores = {} :: { [string]: number }, active = {} :: { [string]: number } }
local cache: { [string]: { rec: any, t: number } } = {}

local invites: { [Player]: { [string]: { expires: number, from: string } } } = {}
local lastAction: { [Player]: { [string]: number } } = {} -- per player, per action (opening the panel and then
-- tapping FIND right away must not drop the FIND)
local board: { { Id: string, Name: string, Score: number, Members: number, Title: string } } = {}
local boardPart: BasePart? = nil

function Company.Init(services)
	S = services
end

function Company.TitleFor(score: number): string
	for _, t in TITLES do
		if score >= t[1] then
			return t[2]
		end
	end
	return "Startup"
end

---------------------------------------------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------------------------------------------

local function count(t: { [any]: any }?): number
	local n = 0
	for _ in t or {} do
		n += 1
	end
	return n
end

-- Returns the record (nil = no such company) and whether the read worked (false = DataStore trouble: don't act
-- on the nil).
local function getRecord(id: string, fresh: boolean?): (any, boolean)
	if id == "" then
		return nil, true
	end
	local c = cache[id]
	if c and not fresh and os.clock() - c.t < CACHE_TTL then
		return c.rec, true
	end
	local rec
	if store then
		local ok, v = pcall(function()
			return (store :: DataStore):GetAsync(id)
		end)
		if not ok then
			return if c then c.rec else nil, false
		end
		rec = v
	else
		rec = mem.records[id]
	end
	cache[id] = { rec = rec, t = os.clock() }
	return rec, true
end

-- Atomic edit of a company record. fn gets the current record (or nil) and returns the new one (nil = delete).
local function updateRecord(id: string, fn: (any) -> any): (boolean, any)
	local result
	if store then
		local ok = pcall(function()
			(store :: DataStore):UpdateAsync(id, function(old)
				result = fn(old)
				return result
			end)
		end)
		if not ok then
			return false, nil
		end
		if result == nil then
			pcall(function()
				(store :: DataStore):RemoveAsync(id)
			end)
		end
	else
		result = fn(mem.records[id])
		mem.records[id] = result
	end
	cache[id] = { rec = result, t = os.clock() }
	return true, result
end

local function setRanks(id: string, score: number?)
	if score == nil then
		if scores then
			pcall(function()
				(scores :: OrderedDataStore):RemoveAsync(id)
				;(active :: OrderedDataStore):RemoveAsync(id)
			end)
		end
		mem.scores[id] = nil
		mem.active[id] = nil
		return
	end
	if scores then
		pcall(function()
			(scores :: OrderedDataStore):SetAsync(id, math.floor(score))
			;(active :: OrderedDataStore):SetAsync(id, os.time())
		end)
	else
		mem.scores[id] = math.floor(score)
		mem.active[id] = os.time()
	end
end

local function top(ordered: OrderedDataStore?, memTable: { [string]: number }, n: number): { { key: string, value: number } }
	local out = {}
	if ordered then
		local ok, pages = pcall(function()
			return ordered:GetSortedAsync(false, n)
		end)
		if ok and pages then
			for _, e in pages:GetCurrentPage() do
				table.insert(out, { key = e.key, value = e.value })
			end
		end
	else
		for k, v in memTable do
			table.insert(out, { key = k, value = v })
		end
		table.sort(out, function(a, b)
			return a.value > b.value
		end)
		while #out > n do
			table.remove(out)
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------------------------------------------

local function uidOf(p: Player): string
	return tostring(p.UserId)
end

local function profile(p: Player): any
	return S.DataService.Get(p)
end

local function companyIdOf(p: Player): string
	local prof = profile(p)
	return if prof and typeof(prof.CompanyId) == "string" then prof.CompanyId else ""
end

local function rankOf(id: string): number?
	for i, e in board do
		if e.Id == id then
			return i
		end
	end
	return nil
end

local function setCompanyTag(p: Player, rec: any)
	p:SetAttribute("Company", if rec then rec.Name else nil)
	p:SetAttribute("CompanyTitle", if rec then Company.TitleFor(rec.Score or 0) else nil)
	local ls = p:FindFirstChild("leaderstats")
	if ls then
		local v = ls:FindFirstChild("Company") :: StringValue?
		if not v then
			v = Instance.new("StringValue")
			v.Name = "Company"
			v.Parent = ls
		end
		(v :: StringValue).Value = if rec then rec.Name else "-"
	end
end

-- Everything the COMPANY panel shows for this player.
local function sendMine(p: Player)
	local prof = profile(p)
	if not prof then
		return
	end
	local id = companyIdOf(p)
	local rec = getRecord(id)
	local payload: { [string]: any } = { kind = "Mine", max = MAX_MEMBERS }
	if rec then
		local members, requests = {}, {}
		for uid, m in rec.Members or {} do
			local online = Players:GetPlayerByUserId(tonumber(uid) or 0)
			table.insert(members, { Uid = uid, Name = m.Name, Points = m.Points or 0, Owner = tonumber(uid) == rec.Owner, Online = online ~= nil })
		end
		table.sort(members, function(a, b)
			return a.Points > b.Points
		end)
		for uid, r in rec.Requests or {} do
			table.insert(requests, { Uid = uid, Name = r.Name })
		end
		local invitable = {}
		for _, other in Players:GetPlayers() do
			if other ~= p and companyIdOf(other) == "" then
				table.insert(invitable, other.Name)
			end
		end
		payload.company = {
			Id = rec.Id,
			Name = rec.Name,
			Score = rec.Score or 0,
			Jobs = rec.Jobs or 0,
			Title = Company.TitleFor(rec.Score or 0),
			Rank = rankOf(rec.Id),
			Members = members,
			Requests = requests,
			IsOwner = rec.Owner == p.UserId,
			Invitable = invitable,
		}
	elseif typeof(prof.CompanyRequest) == "string" and prof.CompanyRequest ~= "" then
		local r = getRecord(prof.CompanyRequest)
		payload.request = { Id = prof.CompanyRequest, Name = if r then r.Name else "?" }
	end
	DataEvent:FireClient(p, payload)
end

local function sendMineToMembers(rec: any)
	if not rec then
		return
	end
	for uid in rec.Members or {} do
		local pl = Players:GetPlayerByUserId(tonumber(uid) or 0)
		if pl then
			sendMine(pl)
		end
	end
end

local function setMembership(p: Player, id: string)
	local prof = profile(p)
	if not prof then
		return
	end
	prof.CompanyId = id
	prof.CompanyRequest = ""
	setCompanyTag(p, (getRecord(id)))
	task.spawn(S.DataService.Save, p, false)
end

-- Re-checks a player against the stored record: removed while away, accepted / declined while away.
local function reconcile(p: Player, fresh: boolean)
	local prof = profile(p)
	if not prof then
		return
	end
	local uid = uidOf(p)
	local id = companyIdOf(p)
	if id ~= "" then
		local rec, readOk = getRecord(id, fresh)
		if not readOk then
			return -- try again next refresh
		end
		if not rec or not (rec.Members or {})[uid] then
			prof.CompanyId = ""
			setCompanyTag(p, nil)
			Toast:FireClient(p, "You're no longer in a company. Tap COMPANY to start or join one.")
		else
			setCompanyTag(p, rec)
		end
	end
	local req = if typeof(prof.CompanyRequest) == "string" then prof.CompanyRequest else ""
	if prof.CompanyId == "" and req ~= "" then
		local rec, readOk = getRecord(req, fresh)
		if not readOk then
			return
		end
		if rec and (rec.Members or {})[uid] then
			setMembership(p, req)
			Toast:FireClient(p, ("Welcome to %s! Your request was accepted."):format(rec.Name))
		elseif not rec or not (rec.Requests or {})[uid] then
			prof.CompanyRequest = ""
			Toast:FireClient(p, ("Your request to join %s wasn't accepted. Try another company in FIND."):format(if rec then rec.Name else "that company"))
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------------------------

local function filterName(p: Player, raw: string): (string?, string?)
	local name = string.gsub(raw, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	name = string.gsub(name, "%s+", " ")
	local len = utf8.len(name)
	if not len or len < 3 or len > 24 then
		return nil, "Pick a name of 3 to 24 characters"
	end
	if string.find(name, "[^%w %-%&'%.]") then
		return nil, "Use letters, numbers, spaces and - & ' . only"
	end
	local ok, res = pcall(function()
		local r = TextService:FilterStringAsync(name, p.UserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(res) ~= "string" then
		return nil, "Couldn't check that name right now, try again"
	end
	if res ~= name or string.find(res, "#") then
		return nil, "That name isn't allowed, try another"
	end
	return name, nil
end

local function memberEntry(p: Player): { [string]: any }
	return { Name = p.Name, Joined = os.time(), Points = 0 }
end

local function cancelRequest(p: Player)
	local prof = profile(p)
	local req = if prof and typeof(prof.CompanyRequest) == "string" then prof.CompanyRequest else ""
	if req == "" then
		return
	end
	prof.CompanyRequest = ""
	local uid = uidOf(p)
	local _, rec = updateRecord(req, function(old)
		if old and old.Requests then
			old.Requests[uid] = nil
		end
		return old
	end)
	sendMineToMembers(rec)
end

local function create(p: Player, raw: any)
	if companyIdOf(p) ~= "" then
		Toast:FireClient(p, "You're already in a company")
		return
	end
	if typeof(raw) ~= "string" or #raw > 80 then
		return
	end
	local name, why = filterName(p, raw)
	if not name then
		Toast:FireClient(p, why or "That name doesn't work")
		return
	end
	cancelRequest(p)
	local id = ("%d_%d"):format(p.UserId, os.time())
	local ok, rec = updateRecord(id, function(old)
		if old then
			return old
		end
		return {
			Id = id,
			Name = name,
			Owner = p.UserId,
			Members = { [uidOf(p)] = memberEntry(p) },
			Requests = {},
			Score = 0,
			Jobs = 0,
			Created = os.time(),
		}
	end)
	if not ok or not rec or rec.Owner ~= p.UserId then
		Toast:FireClient(p, "Couldn't start the company right now, try again")
		return
	end
	setRanks(id, 0)
	setMembership(p, id)
	Toast:FireClient(p, ("You founded %s! Invite your crew from the COMPANY panel."):format(name))
	sendMine(p)
end

local function addMember(id: string, who: Player): (boolean, string?)
	local uid = uidOf(who)
	local why: string? = nil
	local ok, rec = updateRecord(id, function(old)
		if not old then
			why = "That company closed"
			return old
		end
		old.Members = old.Members or {}
		old.Requests = old.Requests or {}
		old.Requests[uid] = nil
		if old.Members[uid] then
			return old
		end
		if count(old.Members) >= MAX_MEMBERS then
			why = "That company is full"
			return old
		end
		old.Members[uid] = memberEntry(who)
		return old
	end)
	if not ok then
		return false, "Couldn't reach the company records, try again"
	end
	if why or not rec or not rec.Members[uid] then
		return false, why or "Couldn't join"
	end
	return true, nil
end

local function invite(p: Player, targetName: any)
	local id = companyIdOf(p)
	if id == "" or typeof(targetName) ~= "string" then
		return
	end
	local target = Players:FindFirstChild(targetName)
	if not target or not target:IsA("Player") or target == p then
		return
	end
	if companyIdOf(target) ~= "" then
		Toast:FireClient(p, target.Name .. " is already in a company")
		return
	end
	local rec = getRecord(id)
	if not rec or count(rec.Members) >= MAX_MEMBERS then
		Toast:FireClient(p, "Your company is full")
		return
	end
	invites[target] = invites[target] or {}
	invites[target][id] = { expires = os.clock() + INVITE_TTL, from = p.Name }
	DataEvent:FireClient(target, { kind = "Invite", companyId = id, company = rec.Name, from = p.Name })
	Toast:FireClient(p, ("Invite sent to %s"):format(target.Name))
end

local function respondInvite(p: Player, id: any, accept: any)
	if typeof(id) ~= "string" or typeof(accept) ~= "boolean" then
		return
	end
	local pending = invites[p] and invites[p][id]
	if not pending or os.clock() > pending.expires then
		return
	end
	invites[p][id] = nil
	if not accept then
		local from = Players:FindFirstChild(pending.from)
		if from and from:IsA("Player") then
			Toast:FireClient(from, p.Name .. " said no thanks")
		end
		return
	end
	if companyIdOf(p) ~= "" then
		Toast:FireClient(p, "Leave your company first")
		return
	end
	cancelRequest(p)
	local ok, why = addMember(id, p)
	if not ok then
		Toast:FireClient(p, why or "Couldn't join")
		return
	end
	setMembership(p, id)
	local rec = getRecord(id)
	Toast:FireClient(p, ("Welcome to %s!"):format(rec and rec.Name or "the company"))
	sendMineToMembers(rec)
end

local function request(p: Player, id: any)
	if typeof(id) ~= "string" or #id > 40 or companyIdOf(p) ~= "" then
		return
	end
	local uid = uidOf(p)
	local rec = getRecord(id, true)
	if not rec then
		Toast:FireClient(p, "That company closed")
		return
	end
	if count(rec.Members) >= MAX_MEMBERS then
		Toast:FireClient(p, "That company is full")
		return
	end
	cancelRequest(p)
	local ok, newRec = updateRecord(id, function(old)
		if not old then
			return old
		end
		old.Requests = old.Requests or {}
		if count(old.Requests) < 20 then
			old.Requests[uid] = { Name = p.Name, At = os.time() }
		end
		return old
	end)
	if not ok or not newRec or not newRec.Requests[uid] then
		Toast:FireClient(p, "Couldn't send the request, try again")
		return
	end
	profile(p).CompanyRequest = id
	task.spawn(S.DataService.Save, p, false)
	Toast:FireClient(p, ("Request sent to %s. A member has to accept it."):format(newRec.Name))
	for muid in newRec.Members do
		local m = Players:GetPlayerByUserId(tonumber(muid) or 0)
		if m then
			Toast:FireClient(m, ("%s wants to join %s: answer in the COMPANY panel"):format(p.Name, newRec.Name))
		end
	end
	sendMine(p)
	sendMineToMembers(newRec)
end

local function answer(p: Player, uid: any, accept: any)
	local id = companyIdOf(p)
	if id == "" or typeof(uid) ~= "string" or typeof(accept) ~= "boolean" then
		return
	end
	local requester = Players:GetPlayerByUserId(tonumber(uid) or 0)
	if accept and requester and companyIdOf(requester) ~= "" then
		Toast:FireClient(p, requester.Name .. " already joined another company")
		accept = false
	end
	local why: string? = nil
	local ok, rec = updateRecord(id, function(old)
		if not old or not (old.Members or {})[uidOf(p)] then
			why = "You're not in that company any more"
			return old
		end
		local r = (old.Requests or {})[uid]
		if not r then
			why = "That request is gone"
			return old
		end
		old.Requests[uid] = nil
		if accept then
			if count(old.Members) >= MAX_MEMBERS then
				why = "Your company is full"
			else
				old.Members[uid] = { Name = r.Name, Joined = os.time(), Points = 0 }
			end
		end
		return old
	end)
	if not ok or why then
		Toast:FireClient(p, why or "Couldn't update the company, try again")
		sendMine(p)
		return
	end
	if requester then
		if accept then
			setMembership(requester, id)
			Toast:FireClient(requester, ("Welcome to %s! %s accepted your request."):format(rec.Name, p.Name))
		else
			profile(requester).CompanyRequest = ""
			Toast:FireClient(requester, ("Your request to join %s wasn't accepted."):format(rec.Name))
			sendMine(requester)
		end
	end
	sendMineToMembers(rec)
end

local function leave(p: Player)
	local id = companyIdOf(p)
	if id == "" then
		return
	end
	local uid = uidOf(p)
	local ok, rec = updateRecord(id, function(old)
		if not old then
			return nil
		end
		old.Members[uid] = nil
		if count(old.Members) == 0 then
			return nil -- last one out closes the company
		end
		if old.Owner == p.UserId then
			local best, bestJoined = nil, math.huge
			for muid, m in old.Members do
				if (m.Joined or 0) < bestJoined then
					best, bestJoined = muid, m.Joined or 0
				end
			end
			old.Owner = tonumber(best) or old.Owner
		end
		return old
	end)
	if not ok then
		Toast:FireClient(p, "Couldn't leave right now, try again")
		return
	end
	if not rec then
		setRanks(id, nil)
	end
	setMembership(p, "")
	Toast:FireClient(p, "You left the company")
	sendMine(p)
	sendMineToMembers(rec)
end

local function kick(p: Player, uid: any)
	local id = companyIdOf(p)
	if id == "" or typeof(uid) ~= "string" or uid == uidOf(p) then
		return
	end
	local why: string? = nil
	local ok, rec = updateRecord(id, function(old)
		if not old or old.Owner ~= p.UserId then
			why = "Only the owner can remove members"
			return old
		end
		old.Members[uid] = nil
		return old
	end)
	if not ok or why then
		Toast:FireClient(p, why or "Couldn't update the company, try again")
		return
	end
	local gone = Players:GetPlayerByUserId(tonumber(uid) or 0)
	if gone then
		setMembership(gone, "")
		Toast:FireClient(gone, ("You were removed from %s"):format(rec.Name))
		sendMine(gone)
	end
	sendMineToMembers(rec)
end

-- Recently active companies with room, for players looking for a crew.
local function find(p: Player)
	local own = companyIdOf(p)
	local list = {}
	for _, e in top(active, mem.active, 15) do
		if #list >= 8 then
			break
		end
		if e.key ~= own then
			local rec = getRecord(e.key)
			if rec and count(rec.Members) < MAX_MEMBERS then
				table.insert(list, {
					Id = rec.Id,
					Name = rec.Name,
					Members = count(rec.Members),
					Score = rec.Score or 0,
					Title = Company.TitleFor(rec.Score or 0),
					Rank = rankOf(rec.Id),
				})
			end
		end
	end
	local prof = profile(p)
	DataEvent:FireClient(p, { kind = "Find", list = list, requested = if prof then prof.CompanyRequest else "" })
end

---------------------------------------------------------------------------------------------------------------
-- Points and the leaderboard
---------------------------------------------------------------------------------------------------------------

local function drawBoard()
	local part = boardPart
	if not part then
		return
	end
	local gui = part:FindFirstChildOfClass("SurfaceGui")
	local list = gui and gui:FindFirstChild("List")
	if not list then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for i = 1, 10 do
		local e = board[i]
		local t = Instance.new("TextLabel")
		t.LayoutOrder = i
		t.Size = UDim2.new(1, 0, 0.085, 0)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = if i == 1 then Color3.fromRGB(255, 210, 70) elseif i <= 3 then Color3.fromRGB(230, 230, 235) else Color3.fromRGB(190, 195, 205)
		t.Text = if e then ("%2d. %s  -  %s pts  (%s)"):format(i, e.Name, tostring(e.Score), e.Title) else ("%2d. ---"):format(i)
		t.Parent = list
	end
end

local function refreshBoard()
	local out = {}
	for _, e in top(scores, mem.scores, TOP) do
		local rec = getRecord(e.key)
		if rec then
			table.insert(out, { Id = e.key, Name = rec.Name, Score = e.value, Members = count(rec.Members), Title = Company.TitleFor(e.value) })
		end
	end
	board = out
	drawBoard()
	DataEvent:FireAllClients({ kind = "Board", top = board })
end

-- Called by JobService after a successful payout. paid = the players who were paid, grade = the job grade.
function Company.AddJob(paid: { Player }, basePay: number, grade: string)
	local per = math.floor(basePay / 10 * (GRADE_MULT[grade] or 1) + 0.5)
	local byCompany: { [string]: { Player } } = {}
	for _, p in paid do
		local id = companyIdOf(p)
		if id ~= "" then
			byCompany[id] = byCompany[id] or {}
			table.insert(byCompany[id], p)
		end
	end
	for id, members in byCompany do
		task.spawn(function()
			local gained = per * #members
			local ok, rec = updateRecord(id, function(old)
				if not old then
					return old
				end
				old.Score = (old.Score or 0) + gained
				old.Jobs = (old.Jobs or 0) + 1
				for _, p in members do
					local m = old.Members[uidOf(p)]
					if m then
						m.Points = (m.Points or 0) + per
					end
				end
				return old
			end)
			if not ok or not rec then
				return
			end
			setRanks(id, rec.Score)
			for _, p in members do
				setCompanyTag(p, rec)
				Toast:FireClient(p, ("+%d company points for %s (%d total: %s)"):format(gained, rec.Name, rec.Score, Company.TitleFor(rec.Score)))
			end
			refreshBoard()
			sendMineToMembers(rec)
		end)
	end
end

---------------------------------------------------------------------------------------------------------------

-- The leaderboard sign at the RV park (built at runtime, like the truck dealer), on the first clear spot.
local function buildBoard()
	local park = workspace:FindFirstChild("RVPark")
	if not park then
		return
	end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { workspace.Terrain }
	op.RespectCanCollide = true
	local spot: Vector3? = nil
	for _, c in { Vector3.new(-40, 0, -356), Vector3.new(-62, 0, -356), Vector3.new(40, 0, -330), Vector3.new(-40, 0, -330), Vector3.new(110, 0, -330) } do
		if #workspace:GetPartBoundsInBox(CFrame.new(c + Vector3.new(0, 7, 0)), Vector3.new(17, 13, 3), op) == 0 then
			spot = c
			break
		end
	end
	if not spot then
		warn("[Company] no clear spot for the leaderboard sign")
		return
	end
	local pos = spot :: Vector3
	local m = Instance.new("Model")
	m.Name = "CompanyLeaderboard"
	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Parent = m
		return p
	end
	local center = pos + Vector3.new(0, 7.5, 0)
	local face = CFrame.lookAt(center, center + Vector3.new(0, 0, 1)) -- facing south, toward the camp lane
	local b = part("Board", Vector3.new(16, 10, 0.5), face, Color3.fromRGB(28, 32, 40), Enum.Material.Metal)
	part("Trim", Vector3.new(16.4, 0.5, 0.7), face * CFrame.new(0, 5.2, 0), Color3.fromRGB(240, 130, 30), Enum.Material.Metal)
	for _, dx in { -7.4, 7.4 } do
		part("Post", Vector3.new(0.6, 12.5, 0.6), CFrame.new(pos + Vector3.new(dx, 6.25, -0.5)), Color3.fromRGB(70, 72, 76), Enum.Material.Metal)
	end
	local glow = part("Light", Vector3.new(12, 0.2, 0.3), face * CFrame.new(0, 5.6, -0.6), Color3.fromRGB(255, 225, 170), Enum.Material.Neon)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 14
	light.Angle = 100
	light.Brightness = 1.4
	light.Parent = glow
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0.3
	sg.Parent = b
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.14, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 200, 60)
	title.Text = "TOP CONSTRUCTION COMPANIES"
	title.Parent = sg
	local list = Instance.new("Frame")
	list.Name = "List"
	list.Position = UDim2.new(0.05, 0, 0.16, 0)
	list.Size = UDim2.new(0.9, 0, 0.82, 0)
	list.BackgroundTransparency = 1
	list.Parent = sg
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	m.Parent = park
	boardPart = b
	drawBoard()
end

-- seconds between two of the same action from one player (unknown actions are ignored)
local GAPS: { [string]: number } = {
	Panel = 0.5, Find = 2, Create = 0.8, Invite = 0.8, RespondInvite = 0.8, Request = 0.8,
	CancelRequest = 0.8, Answer = 0.8, Leave = 0.8, Kick = 0.8,
}

local function onAction(p: Player, action: unknown, a: unknown, b: unknown)
	if typeof(action) ~= "string" or not profile(p) then
		return
	end
	local now = os.clock()
	local minGap = GAPS[action]
	if not minGap then
		return
	end
	local mine = lastAction[p]
	if not mine then
		mine = {}
		lastAction[p] = mine
	end
	if now - (mine[action] or 0) < minGap then
		return
	end
	mine[action] = now
	if action == "Panel" then
		sendMine(p)
		DataEvent:FireClient(p, { kind = "Board", top = board })
	elseif action == "Create" then
		create(p, a)
	elseif action == "Invite" then
		invite(p, a)
	elseif action == "RespondInvite" then
		respondInvite(p, a, b)
	elseif action == "Request" then
		request(p, a)
	elseif action == "CancelRequest" then
		cancelRequest(p)
		sendMine(p)
	elseif action == "Answer" then
		answer(p, a, b)
	elseif action == "Leave" then
		leave(p)
	elseif action == "Kick" then
		kick(p, a)
	elseif action == "Find" then
		find(p)
	end
end

function Company.Start()
	Toast = Net.Event("Toast")
	DataEvent = Net.Event("CompanyData")
	local ok = pcall(function()
		local s = DataStoreService:GetDataStore("Companies_v1")
		s:GetAsync("probe")
		store = s
		scores = DataStoreService:GetOrderedDataStore("CompanyScores_v1")
		active = DataStoreService:GetOrderedDataStore("CompanyActive_v1")
	end)
	if not ok then
		store, scores, active = nil, nil, nil
		print("[Company] DataStores unavailable: companies live in memory for this server")
	end
	-- Studio-only: sample companies so the leaderboard and FIND can be checked without DataStores
	if not store and RunService:IsStudio() and workspace:GetAttribute("DevCompanies") == true then
		for i, spec in { { "Bayside Builders", 5200 }, { "Pine Ridge Co", 1800 }, { "Hammer & Sons", 640 }, { "Oak Ave Crew", 120 } } do
			local id = "dev_" .. i
			mem.records[id] = { Id = id, Name = spec[1], Owner = -i, Members = { [tostring(-i)] = { Name = "Sample" .. i, Joined = 0, Points = spec[2] } }, Requests = {}, Score = spec[2], Jobs = i * 3, Created = 0 }
			mem.scores[id] = spec[2]
			mem.active[id] = os.time() - i
		end
	end

	Net.Event("Company").OnServerEvent:Connect(onAction)
	buildBoard()

	local function onPlayer(p: Player)
		local prof = S.DataService.WhenLoaded(p)
		if not prof or not p.Parent then
			return
		end
		reconcile(p, true)
		if companyIdOf(p) == "" then
			setCompanyTag(p, nil)
		end
		sendMine(p)
		DataEvent:FireClient(p, { kind = "Board", top = board })
	end
	Players.PlayerAdded:Connect(function(p)
		task.spawn(onPlayer, p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		invites[p] = nil
		lastAction[p] = nil
	end)

	refreshBoard()
	local lastBoard = os.clock()
	while true do
		task.wait(REFRESH)
		for _, p in Players:GetPlayers() do
			if profile(p) then
				reconcile(p, true)
				sendMine(p)
			end
		end
		if os.clock() - lastBoard >= BOARD_REFRESH then
			lastBoard = os.clock()
			refreshBoard()
		end
	end
end

return Company
