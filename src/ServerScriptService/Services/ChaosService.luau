--!strict
-- Chaos events (CLAUDE.md launch list), 1-2 per job, planned when the job starts:
--  * Rain delay: starts when the first concrete pour opens. 45 s of no pouring (JobService asks Blocks), and the
--    mud slows every vehicle (VehicleService speed factor). Clients draw the rain and a countdown (RainUntil).
--  * Surprise inspector: at 50% progress an inspector walks the site and red-flags the worst work (lowest task
--    accuracy). Each flag adds a "Fix" task for that trade; every flag still unfixed at payout costs each paid
--    player 5% of base pay ("every visible mistake costs money").
--  * Crane mishap: the next crane lift is badly rigged. The load swings, slips and drops (EquipmentService);
--    a Laborer re-stacks it before the lift can be done again (JobService adds the rework task).
-- First-time drop-in jobs get no chaos. Studio-only test switch: workspace attribute DevChaos = "All" or a list
-- like "Rain,Inspector" forces those events (also on drop-in jobs).
local Lighting = game:GetService("Lighting")
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
local Toast: RemoteEvent
local rng = Random.new()

local plan: { [string]: boolean } = {}
local fired: { [string]: boolean } = {}
local flags: { [string]: boolean } = {} -- flagged slot id -> still unfixed
local token = 0 -- bumps every job, so delayed work from an old job does nothing
local raining = false
local inspector: Model? = nil
local savedSky: { [string]: any }? = nil

function Chaos.Init(services)
	S = services
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

local startRain: () -> ()

-- Reason the slot can't be worked right now, or nil.
-- A planned rain delay starts the moment anyone reaches for a pour, so no pour slips through first.
function Chaos.Blocks(slot: any): string?
	if string.sub(slot.def.Id, 1, 5) ~= "pour_" then
		return nil
	end
	if plan.Rain and not fired.Rain then
		startRain()
	end
	if raining then
		return "It's raining: no pouring concrete until it clears"
	end
	return nil
end

-- True once per job when a crane mishap is planned: this lift goes wrong.
function Chaos.TakeCraneMishap(): boolean
	if plan.CraneMishap and not fired.CraneMishap then
		fired.CraneMishap = true
		return true
	end
	return false
end

-- Inspector fines: (amount per paid player, unfixed flags).
function Chaos.Fines(cfg: any): (number, number)
	local n = 0
	for _, open in flags do
		if open then
			n += 1
		end
	end
	return n * math.floor(cfg.BasePay * FINE_SHARE + 0.5), n
end

---------------------------------------------------------------------------------------------------------------
-- Rain delay
---------------------------------------------------------------------------------------------------------------

local function skyParts(): (Atmosphere, Clouds?)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmo then
		atmo = Instance.new("Atmosphere")
		atmo.Parent = Lighting
	end
	return atmo :: Atmosphere, workspace.Terrain:FindFirstChildOfClass("Clouds")
end

local function setStorm(on: boolean)
	local atmo, clouds = skyParts()
	if on then
		if savedSky then
			return
		end
		savedSky = {
			brightness = Lighting.Brightness,
			density = atmo.Density,
			haze = atmo.Haze,
			color = atmo.Color,
			clouds = clouds ~= nil,
			cover = if clouds then clouds.Cover else 0,
			cdensity = if clouds then clouds.Density else 0,
			ccolor = if clouds then clouds.Color else Color3.new(1, 1, 1),
		}
		if not clouds then
			clouds = Instance.new("Clouds")
			clouds.Name = "RainClouds"
			clouds.Parent = workspace.Terrain
		end
		Lighting.Brightness = Lighting.Brightness * 0.55
		atmo.Density = math.max(atmo.Density, 0.45)
		atmo.Haze = math.max(atmo.Haze, 2.5)
		atmo.Color = Color3.fromRGB(150, 155, 165)
		local c = clouds :: Clouds
		c.Cover = 0.9
		c.Density = 0.75
		c.Color = Color3.fromRGB(110, 115, 125)
	else
		local sv = savedSky
		if not sv then
			return
		end
		savedSky = nil
		Lighting.Brightness = sv.brightness
		atmo.Density = sv.density
		atmo.Haze = sv.haze
		atmo.Color = sv.color
		if clouds then
			if sv.clouds then
				clouds.Cover = sv.cover
				clouds.Density = sv.cdensity
				clouds.Color = sv.ccolor
			else
				clouds:Destroy()
			end
		end
	end
end

local function stopRain(announce: boolean)
	if not raining then
		return
	end
	raining = false
	workspace:SetAttribute("RainUntil", nil)
	S.VehicleService.SetSpeedFactor(1)
	setStorm(false)
	if announce then
		Toast:FireAllClients("The rain stopped. Pour the concrete!")
		S.JobService.Broadcast()
	end
end

startRain = function()
	fired.Rain = true
	raining = true
	local my = token
	workspace:SetAttribute("RainUntil", workspace:GetServerTimeNow() + RAIN_SECONDS)
	S.VehicleService.SetSpeedFactor(MUD_FACTOR)
	setStorm(true)
	Toast:FireAllClients(("RAIN DELAY! No pouring concrete for %d s and the mud slows every vehicle. Keep working on the rest!"):format(RAIN_SECONDS))
	task.delay(RAIN_SECONDS, function()
		if token == my then
			stopRain(true)
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
local function flag(slot: any)
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

	flags[id] = true
	local p = slot.part.Position
	S.JobService.AddSlot({
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
		if flags[id] then
			flags[id] = false
			S.QualityService.Replace(id, FIXED_ACCURACY)
			Toast:FireAllClients("Fixed: " .. slot.def.Label .. " (no fine for that one)")
		end
	end)
end

local function startInspector(cur: any)
	fired.Inspector = true
	local my = token
	local spawnCF = S.JobService.SiteSpawn()
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
	inspector = body
	local root = body:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	Toast:FireAllClients("SURPRISE INSPECTOR on site! Every visible mistake costs money: fix the red flags before payout")
	Net.Cue("Whistle", spawnCF.Position)
	local t0 = os.clock()

	-- The worst finished work (machine tasks and the paperwork aren't "visible" mistakes).
	local picks = {}
	for _, r in S.QualityService.LowestFor(FLAG_BELOW, 12) do
		local slot = cur.slots[r.slotId]
		if slot and slot.done and not slot.def.Equipment and slot.def.Kind ~= "Deliver" and slot.def.Kind ~= "Inspect"
			and flags[r.slotId] == nil then
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
		if token ~= my or not body.Parent then
			return
		end
		walk(body, slot.part.Position, 10)
		task.wait(1.2)
		if token ~= my or S.JobService.Current() ~= cur or cur.finishing then
			return
		end
		flag(slot)
	end
	if #picks == 0 then
		Toast:FireAllClients("Inspector: clean work, no flags. Nice job crew!")
	else
		local fine = math.floor(cur.cfg.BasePay * FINE_SHARE + 0.5)
		Toast:FireAllClients(("Inspector flagged %d mistake%s: -$%d each at payout unless fixed"):format(
			#picks, if #picks == 1 then "" else "s", fine))
	end
	task.wait(math.max(2, INSPECTOR_STAYS - (os.clock() - t0)))
	if token ~= my or not body.Parent then
		return
	end
	local away = spawnCF.Position + spawnCF.LookVector * -30
	walk(body, away, 6)
	if inspector == body then
		inspector = nil
	end
	body:Destroy()
end

---------------------------------------------------------------------------------------------------------------
-- Planning and the watch loop
---------------------------------------------------------------------------------------------------------------

local function reset()
	token += 1
	stopRain(false)
	if inspector then
		inspector:Destroy()
		inspector = nil
	end
	table.clear(plan)
	table.clear(fired)
	table.clear(flags)
	workspace:SetAttribute("ChaosPlan", nil)
end

local function planFor(dropIn: boolean)
	reset()
	local cur = S.JobService.Current()
	if not cur then
		return
	end
	local force = forced()
	if force then
		for name in force do
			plan[name] = true
		end
	elseif not dropIn then
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
			plan[candidates[i]] = true
			table.remove(candidates, i)
		end
	end
	local names = {}
	for _, name in EVENTS do
		if plan[name] then
			table.insert(names, name)
		end
	end
	workspace:SetAttribute("ChaosPlan", if #names > 0 then table.concat(names, ",") else nil)
	if #names > 0 then
		print("[Chaos] planned:", table.concat(names, ", "))
	end
end

local function tick()
	local cur = S.JobService.Current()
	if not cur or cur.finishing then
		return
	end
	if plan.Rain and not fired.Rain then
		for id, slot in cur.slots do
			if string.sub(id, 1, 5) == "pour_" and slot.open and not slot.done then
				startRain()
				break
			end
		end
	end
	if plan.Inspector and not fired.Inspector then
		local done, total = 0, 0
		for _, def in cur.bp.Slots do
			total += 1
			local slot = cur.slots[def.Id]
			if slot and slot.done then
				done += 1
			end
		end
		if total > 0 and done / total >= INSPECT_AT then
			fired.Inspector = true
			task.spawn(startInspector, cur)
		end
	end
end

function Chaos.Start()
	Toast = Net.Event("Toast")
	S.JobService.Started.Event:Connect(function(_siteId: string, dropIn: boolean, firstJob: boolean?)
		planFor(dropIn or firstJob == true) -- a newcomer's first job stays calm
	end)
	S.JobService.Ended.Event:Connect(function()
		stopRain(false)
	end)
	S.JobService.Cleared.Event:Connect(reset)
	while true do
		task.wait(1)
		local ok, err = pcall(tick)
		if not ok then
			warn("[Chaos]", err)
		end
	end
end

return Chaos
