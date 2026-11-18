--!strict
-- Chaos events (CLAUDE.md launch list), 1-2 per job, planned when the job starts. Each crew's job has its own plan
-- (2026-11-17, several crews per server), and every message goes to that crew only:
--  * Rain delay: starts when the first concrete pour opens. 45 s of no pouring (JobService asks Blocks), and the
--    mud slows that crew's vehicles (VehicleService speed factor). The crew's clients draw the rain, the dark sky
--    and a countdown (player attribute RainUntil).
--  * Surprise inspector: at 50% progress an inspector walks the site and red-flags the worst work (lowest task
--    accuracy). Each flag adds a "Fix" task for that trade; every flag still unfixed at payout costs each paid
--    player 5% of base pay ("every visible mistake costs money").
--  * Crane mishap: the next crane lift is badly rigged. The load swings, slips and drops (EquipmentService);
--    a Laborer re-stacks it before the lift can be done again (JobService adds the rework task).
-- First-time drop-in jobs get no chaos. Studio-only test switch: workspace attribute DevChaos = "All" or a list
-- like "Rain,Inspector" forces those events (also on drop-in jobs).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Chaos = {}

local RAIN_SECONDS = 45
local MUD_FACTOR = 0.6 -- vehicle top speed in the mud
local INSPECT_AT = 0.5 -- share of the blueprint done when the inspector shows up
local FLAG_BELOW = 0.85 -- tasks under this accuracy are "visible mistakes"
local MAX_FLAGS = 4
local FINE_SHARE = 0.05 -- of base pay, per unfixed flag, per paid player
local FIXED_ACCURACY = 0.9 -- a fixed task counts this much in the grade
local INSPECTOR_STAYS = 25
local EVENTS = { "Rain", "Inspector", "CraneMishap" }

local S: any
local rng = Random.new()

-- Per job (cur.chaos).
type State = {
	plan: { [string]: boolean },
	fired: { [string]: boolean },
	flags: { [string]: boolean }, -- flagged slot id -> still unfixed
	raining: boolean,
	rainUntil: number?,
	inspector: Model?,
	over: boolean, -- the job ended: delayed work does nothing
}

function Chaos.Init(services)
	S = services
end

local function stateOf(cur: any): State
	local st = cur.chaos
	if not st then
		st = { plan = {}, fired = {}, flags = {}, raining = false, rainUntil = nil, inspector = nil, over = false }
		cur.chaos = st
	end
	return st
end

local function live(cur: any): boolean
	return S.JobService.Live(cur) and not stateOf(cur).over
end

local function hasPour(bp: any): boolean
	for _, def in bp.Slots do
		if string.sub(def.Id, 1, 5) == "pour_" then
			return true
		end
	end
	return false
end

local function forced(): { [string]: boolean }?
	local v = workspace:GetAttribute("DevChaos")
	if not RunService:IsStudio() or typeof(v) ~= "string" or v == "" then
		return nil
	end
	local out: { [string]: boolean } = {}
	for _, name in EVENTS do
		if v == "All" or string.find(v, name, 1, true) then
			out[name] = true
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------
-- Queries from JobService
---------------------------------------------------------------------------------------------------------------

local startRain: (cur: any) -> ()

-- Reason the slot can't be worked right now, or nil.
-- A planned rain delay starts the moment anyone reaches for a pour, so no pour slips through first.
function Chaos.Blocks(cur: any, slot: any): string?
	if string.sub(slot.def.Id, 1, 5) ~= "pour_" then
		return nil
	end
	local st = stateOf(cur)
	if st.plan.Rain and not st.fired.Rain then
		startRain(cur)
	end
	if st.raining then
		return "It's raining: no pouring concrete until it clears"
	end
	return nil
end

-- True once per job when a crane mishap is planned: this lift goes wrong.
function Chaos.TakeCraneMishap(cur: any): boolean
	local st = stateOf(cur)
	if st.plan.CraneMishap and not st.fired.CraneMishap then
		st.fired.CraneMishap = true
		return true
	end
	return false
end

-- Inspector fines: (amount per paid player, unfixed flags).
function Chaos.Fines(cur: any, cfg: any): (number, number)
	local n = 0
	for _, open in stateOf(cur).flags do
		if open then
			n += 1
		end
	end
	return n * math.floor(cfg.BasePay * FINE_SHARE + 0.5), n
end

-- A crewmate who joins mid-rain sees it too (CrewService.Changed).
local function tagRain(cur: any)
	local st = stateOf(cur)
	for _, p in S.CrewService.Members(cur.crew) do
		p:SetAttribute("RainUntil", if st.raining then st.rainUntil else nil)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Rain delay
---------------------------------------------------------------------------------------------------------------

local function stopRain(cur: any, announce: boolean)
	local st = stateOf(cur)
	if not st.raining then
		return
	end
	st.raining = false
	st.rainUntil = nil
	for _, p in S.CrewService.Members(cur.crew) do
		p:SetAttribute("RainUntil", nil)
	end
	S.VehicleService.SetSpeedFactor(1, cur.site)
	if announce then
		S.JobService.Toast(cur, "The rain stopped. Pour the concrete!")
		S.JobService.Broadcast()
	end
end

startRain = function(cur: any)
	local st = stateOf(cur)
	st.fired.Rain = true
	st.raining = true
	st.rainUntil = workspace:GetServerTimeNow() + RAIN_SECONDS
	tagRain(cur)
	S.VehicleService.SetSpeedFactor(MUD_FACTOR, cur.site)
	S.JobService.Toast(cur, ("RAIN DELAY! No pouring concrete for %d s and the mud slows your vehicles. Keep working on the rest!"):format(RAIN_SECONDS))
	task.delay(RAIN_SECONDS, function()
		if live(cur) then
			stopRain(cur, true)
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- Surprise inspector
---------------------------------------------------------------------------------------------------------------

local function walk(body: Model, pos: Vector3, timeout: number)
	local hum = body:FindFirstChildOfClass("Humanoid")
	local root = body:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return
	end
	local goal = Vector3.new(pos.X, root.Position.Y, pos.Z)
	local t0 = os.clock()
	while body.Parent and os.clock() - t0 < timeout do
		local d = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z).Magnitude
		if d < 4 then
			break
		end
		hum:MoveTo(goal)
		task.wait(0.4)
	end
	if body.Parent and Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z).Magnitude >= 4 then
		body:PivotTo(CFrame.new(Vector3.new(pos.X, 3.5, pos.Z)))
	end
	hum:MoveTo(root.Position)
end

-- Red-flags a finished slot: red outline + FIX tag, and a Fix task for the same trade on the ground below it.
local function flag(cur: any, slot: any)
	local st = stateOf(cur)
	local id = slot.def.Id
	local marker = Instance.new("Folder")
	marker.Name = "InspectorFlag_" .. id
	local box = Instance.new("SelectionBox")
	box.Adornee = slot.part
	box.Color3 = Color3.fromRGB(235, 40, 40)
	box.LineThickness = 0.08
	box.SurfaceTransparency = 0.75
	box.SurfaceColor3 = Color3.fromRGB(235, 40, 40)
	box.Parent = marker
	local bb = Instance.new("BillboardGui")
	bb.Adornee = slot.part
	bb.Size = UDim2.fromOffset(110, 34)
	bb.StudsOffset = Vector3.new(0, slot.part.Size.Y / 2 + 1.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 140
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = "FIX: " .. slot.def.Role
	t.Parent = bb
	local corner = Instance.new("UICorner")
	corner.Parent = t
	bb.Parent = marker
	marker.Parent = slot.part.Parent

	st.flags[id] = true
	local p = slot.part.Position
	S.JobService.AddSlot(cur, {
		Id = "fix_" .. id,
		Kind = "Timing",
		Role = slot.def.Role,
		Phase = "Rework",
		Label = "Fix: " .. slot.def.Label,
		Size = Vector3.new(2.2, 2.2, 2.2),
		Done = { Color = Color3.fromRGB(80, 200, 90), Material = "Neon", Transparency = 1 },
		Collide = false,
		Reach = 12,
	}, CFrame.new(p.X, 1.2, p.Z), marker, function()
		if st.flags[id] then
			st.flags[id] = false
			S.QualityService.Replace(cur.quality, id, FIXED_ACCURACY)
			S.JobService.Toast(cur, "Fixed: " .. slot.def.Label .. " (no fine for that one)")
		end
	end)
end

local function startInspector(cur: any)
	local st = stateOf(cur)
	st.fired.Inspector = true
	local spawnCF = S.JobService.SiteSpawn(cur)
	if not spawnCF then
		return
	end
	local body = S.BotService.MakeBody("Inspector", Color3.fromRGB(240, 240, 235), Color3.fromRGB(250, 250, 250), spawnCF)
	if not body then
		return
	end
	body:SetAttribute("Inspector", true)
	local hum = body:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.WalkSpeed = 10
	hum.DisplayName = "Inspector"
	local head = body:FindFirstChild("Head") :: BasePart?
	if head then
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(120, 26)
		tag.StudsOffset = Vector3.new(0, 2.6, 0)
		tag.MaxDistance = 120
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
		t.BackgroundTransparency = 0.2
		t.TextColor3 = Color3.fromRGB(255, 220, 80)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.Text = "INSPECTOR"
		t.Parent = tag
		tag.Parent = head
	end
	body.Parent = workspace
	st.inspector = body
	local root = body:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	S.JobService.Toast(cur, "SURPRISE INSPECTOR on site! Every visible mistake costs money: fix the red flags before payout")
	Net.Cue("Whistle", spawnCF.Position)
	local t0 = os.clock()

	-- The worst finished work (machine tasks and the paperwork aren't "visible" mistakes).
	local picks = {}
	for _, r in S.QualityService.LowestFor(cur.quality, FLAG_BELOW, 12) do
		local slot = cur.slots[r.slotId]
		if slot and slot.done and not slot.def.Equipment and slot.def.Kind ~= "Deliver" and slot.def.Kind ~= "Inspect"
			and st.flags[r.slotId] == nil then
			table.insert(picks, slot)
			if #picks >= MAX_FLAGS then
				break
			end
		end
	end
	if #picks == 0 then
		walk(body, cur.originCF.Position, 10)
	end
	for _, slot in picks do
		if not live(cur) or not body.Parent then
			return
		end
		walk(body, slot.part.Position, 10)
		task.wait(1.2)
		if not live(cur) or cur.finishing then
			return
		end
		flag(cur, slot)
	end
	if #picks == 0 then
		S.JobService.Toast(cur, "Inspector: clean work, no flags. Nice job crew!")
	else
		local fine = math.floor(cur.cfg.BasePay * FINE_SHARE + 0.5)
		S.JobService.Toast(cur, ("Inspector flagged %d mistake%s: -$%d each at payout unless fixed"):format(
			#picks, if #picks == 1 then "" else "s", fine))
	end
	task.wait(math.max(2, INSPECTOR_STAYS - (os.clock() - t0)))
	if not live(cur) or not body.Parent then
		return
	end
	local away = spawnCF.Position + spawnCF.LookVector * -30
	walk(body, away, 6)
	if st.inspector == body then
		st.inspector = nil
	end
	body:Destroy()
end

---------------------------------------------------------------------------------------------------------------
-- Planning and the watch loop
---------------------------------------------------------------------------------------------------------------

local function planFor(cur: any, calm: boolean)
	local st = stateOf(cur)
	local force = forced()
	if force then
		for name in force do
			st.plan[name] = true
		end
	elseif not calm then
		local candidates = { "Inspector" }
		if hasPour(cur.bp) then
			table.insert(candidates, "Rain")
		end
		if cur.bp.Equipment and cur.bp.Equipment.Crane then
			table.insert(candidates, "CraneMishap")
		end
		local n = if #candidates > 1 and rng:NextNumber() < 0.5 then 2 else 1
		for _ = 1, n do
			local i = rng:NextInteger(1, #candidates)
			st.plan[candidates[i]] = true
			table.remove(candidates, i)
		end
	end
	local names = {}
	for _, name in EVENTS do
		if st.plan[name] then
			table.insert(names, name)
		end
	end
	cur.site:SetAttribute("ChaosPlan", if #names > 0 then table.concat(names, ",") else nil)
	if #names > 0 then
		print(("[Chaos] %s planned: %s"):format(cur.crew.name, table.concat(names, ", ")))
	end
end

-- The job is over: stop the rain, send the inspector home, and make delayed work do nothing.
local function wrapUp(cur: any)
	local st = stateOf(cur)
	stopRain(cur, false)
	st.over = true
	if st.inspector then
		st.inspector:Destroy()
		st.inspector = nil
	end
end

local function tick(cur: any)
	if cur.finishing then
		return
	end
	local st = stateOf(cur)
	if st.plan.Rain and not st.fired.Rain then
		for id, slot in cur.slots do
			if string.sub(id, 1, 5) == "pour_" and slot.open and not slot.done then
				startRain(cur)
				break
			end
		end
	end
	if st.plan.Inspector and not st.fired.Inspector then
		local done, total = 0, 0
		for _, def in cur.bp.Slots do
			total += 1
			local slot = cur.slots[def.Id]
			if slot and slot.done then
				done += 1
			end
		end
		if total > 0 and done / total >= INSPECT_AT then
			st.fired.Inspector = true
			task.spawn(startInspector, cur)
		end
	end
end

function Chaos.Start()
	S.JobService.Started.Event:Connect(function(cur, dropIn: boolean, firstJob: boolean?)
		planFor(cur, dropIn or firstJob == true) -- a newcomer's first job stays calm
	end)
	S.JobService.Ended.Event:Connect(function(cur)
		stopRain(cur, false)
	end)
	S.JobService.Cleared.Event:Connect(wrapUp)
	S.CrewService.Changed.Event:Connect(function(crew)
		local cur = S.JobService.Of(crew)
		if cur and stateOf(cur).raining then
			tagRain(cur)
		end
	end)
	while true do
		task.wait(1)
		for _, cur in S.JobService.All() do
			local ok, err = pcall(tick, cur)
			if not ok then
				warn("[Chaos]", err)
			end
		end
	end
end

return Chaos
