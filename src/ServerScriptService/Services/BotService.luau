--!strict
-- Bot workers fill every trade no player has picked (CLAUDE.md: "Empty slots get bot workers, slower, make
-- mistakes, run the same task engine as players").
--  * Same rules: bots only work through JobService's bot entry points, which apply the same slot checks as a
--    player's tap (their trade, requirements done, nobody else on it, reach or operating the right machine).
--  * Same engine: they carry with TaskEngine.Carry and score Timing / Connect work with the task engine's own
--    TimingTask.JudgeAt / ConnectTask.Accuracy. Only the tap is simulated (with aim error, so they miss sometimes).
--  * Slower: 75% walk speed, a pause between tasks, slower wiring puzzles.
--  * When a player picks a trade, that trade's bot clocks out. Bots never get paid or earn XP.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Trades = require(ReplicatedStorage.Shared.Config.Trades)
local GaugeStyles = require(ReplicatedStorage.Shared.Util.Gauge).STYLES

local BotService = {}

type Bot = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	role: string,
	alive: boolean,
	seat: BasePart?,
	pro: boolean?, -- hired through the store (Hire a Pro): faster and more accurate, for this job only
}

local SPEED_SCALE = 0.75 -- bots walk at 75% of player speed
local AIM_SPREAD = 0.3 -- seconds of tap error (roughly 1 miss in 12 taps)
local THINK_MIN, THINK_MAX = 0.8, 1.8 -- pause between tasks
local START_GRACE = 8 -- seconds after a job starts before bots join (time to pick a trade)
-- A hired pro (paid boost): player walking speed, short pauses, a steadier hand. Still one worker on one trade,
-- going through the same slot rules and task engine as everyone else.
local PRO_AIM_SPREAD = 0.1
local PRO_MACHINE_AIM = 0.6
local SKINS = {
	Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 140, 100), Color3.fromRGB(141, 85, 54),
	Color3.fromRGB(255, 205, 170), Color3.fromRGB(110, 70, 45),
}

local S: any
local bots: { Bot } = {}
local rng = Random.new()
local proRole: { [string]: boolean } = {} -- trades with a hired pro on this job
local folder: Folder

function BotService.Init(services)
	S = services
end

-- How many bots work each trade right now (sent to clients for the trade picker).
function BotService.Summary(): { [string]: number }
	local out: { [string]: number } = {}
	for _, b in bots do
		if b.alive then
			out[b.role] = (out[b.role] or 0) + 1
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------
-- Body
---------------------------------------------------------------------------------------------------------------

-- Work clothes for bot bodies (image templates; the hard hat and beard accessories live in ServerStorage.NPCs.BotKit).
local SHIRTS = { "rbxassetid://5493875935", "rbxassetid://754020586" }
local PANTS = { "rbxassetid://129458425", "rbxassetid://7934666389" }
local FACES = { "rbxassetid://10749456", "rbxasset://textures/face.png" }
-- Roblox's default R15 idle and walk animations (server-side NPCs have no Animate script running).
local IDLE_ANIM = "rbxassetid://507766388"
local WALK_ANIM = "rbxassetid://507777826"

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function animate(hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local function load(id: string): AnimationTrack?
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		return if ok then track else nil
	end
	local idle, walk = load(IDLE_ANIM), load(WALK_ANIM)
	if idle then
		idle.Looped = true
		idle:Play()
	end
	if walk then
		walk.Looped = true
	end
	hum.Running:Connect(function(speed: number)
		if not walk then
			return
		end
		if speed > 0.5 then
			if not walk.IsPlaying then
				walk:Play(0.2)
			end
			walk:AdjustSpeed(speed / 12)
		elseif walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)
end

-- An R15 worker body in work clothes with a hard hat. `shirt` tints the shirt toward the trade color.
-- Unparented. Also used by ChaosService for the inspector, and by TownLifeService (hat = nil: no hard hat).
function BotService.MakeBody(name: string, shirt: Color3, hat: Color3?, at: CFrame): Model?
	local tone = SKINS[rng:NextInteger(1, #SKINS)]
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = tone
	desc.LeftArmColor = tone
	desc.RightArmColor = tone
	desc.TorsoColor = tone
	desc.LeftLegColor = tone
	desc.RightLegColor = tone
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[Bots] could not build a body:", model)
		return nil
	end
	model.Name = name
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayName = name

	local s = Instance.new("Shirt")
	s.ShirtTemplate = pick(SHIRTS)
	s.Color3 = Color3.new(1, 1, 1):Lerp(shirt, 0.45)
	s.Parent = model
	local pa = Instance.new("Pants")
	pa.PantsTemplate = pick(PANTS)
	pa.Parent = model
	local head = model:FindFirstChild("Head") :: BasePart?
	local face = head and head:FindFirstChild("face") :: Decal?
	if face then
		face.Texture = pick(FACES)
	end

	local kit = ServerStorage:FindFirstChild("NPCs") and ServerStorage.NPCs:FindFirstChild("BotKit")
	local hardHat = kit and kit:FindFirstChild("HardHat")
	if hardHat and hat then
		local acc = hardHat:Clone() :: Accessory
		local handle = acc:FindFirstChild("Handle") :: BasePart?
		local mesh = handle and handle:FindFirstChildWhichIsA("SpecialMesh")
		if mesh then
			mesh.TextureId = ""
			mesh.VertexColor = Vector3.new(1, 1, 1)
		end
		if handle then
			handle.Color = hat
			handle.Material = Enum.Material.Metal
		end
		hum:AddAccessory(acc)
	end
	local beard = kit and kit:FindFirstChild("Beard")
	if beard and rng:NextNumber() < 0.35 then
		hum:AddAccessory(beard:Clone() :: Accessory)
	end
	animate(hum)
	model:PivotTo(at)
	return model
end

local function spawnBot(role: string, at: CFrame): Bot?
	local color = Trades.Info[role].Color
	local model = BotService.MakeBody(role .. " (bot)", color, color, at)
	if not model then
		return nil
	end
	model.Name = role .. " Bot"
	model:SetAttribute("Bot", true)
	model:SetAttribute("SpeedScale", SPEED_SCALE)
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	hum.WalkSpeed = 16 * SPEED_SCALE
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return { model = model, hum = hum, root = root, role = role, alive = true }
end

-- Also clears a seat the bot sat in by accident (seats grab whoever touches them), so it never gets stuck seated.
local function leaveSeat(b: Bot)
	local seat = b.seat or b.hum.SeatPart
	b.seat = nil
	if not seat then
		return
	end
	local w = seat:FindFirstChild("SeatWeld")
	if w then
		w:Destroy()
	end
	b.hum.Sit = false
	b.hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	b.model:PivotTo(CFrame.new(seat.Position + seat.CFrame.RightVector * -5 + Vector3.new(0, 2, 0)))
	task.wait(0.2)
end

local function despawn(b: Bot)
	b.alive = false
	S.TaskEngine.Carry.Drop(b.model)
	if b.seat then
		local w = b.seat:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
	end
	b.model:Destroy()
	local i = table.find(bots, b)
	if i then
		table.remove(bots, i)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------------------------------------------

-- Walks to `pos` (stops within `within` studs). If blocked for too long it steps over, like a player walking round.
local function walkTo(b: Bot, pos: Vector3, within: number)
	if b.seat or b.hum.SeatPart then
		leaveSeat(b)
	end
	local goal = Vector3.new(pos.X, 0, pos.Z)
	local limit = (b.root.Position - pos).Magnitude / (b.hum.WalkSpeed * 0.7) + 4
	local t0 = os.clock()
	while b.alive and os.clock() - t0 < limit do
		local here = Vector3.new(b.root.Position.X, 0, b.root.Position.Z)
		if (goal - here).Magnitude <= within then
			b.hum:MoveTo(b.root.Position)
			return
		end
		b.hum:MoveTo(Vector3.new(pos.X, b.root.Position.Y, pos.Z))
		task.wait(0.4)
	end
	if b.alive then
		b.model:PivotTo(CFrame.new(Vector3.new(pos.X, 3.5, pos.Z)))
	end
end

-- A spot on the ground beside a slot (slots can be up on a wall, a floor above, or on the roof).
local function standFor(b: Bot, slot: any): Vector3
	local p = slot.part.Position
	local flat = Vector3.new(b.root.Position.X - p.X, 0, b.root.Position.Z - p.Z)
	local dir = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	return Vector3.new(p.X, 3, p.Z) + dir * 2.5
end

-- Steers a drivable machine (truck, excavator) toward `target` through VehicleService.Drive.
local function driveTo(vehicle: any, target: Vector3, within: number, timeout: number)
	local t0 = os.clock()
	while os.clock() - t0 < timeout and vehicle.model.Parent do
		local lp = vehicle.chassis.CFrame:PointToObjectSpace(target)
		local dist = Vector2.new(lp.X, lp.Z).Magnitude
		if dist <= within then
			S.VehicleService.Drive(vehicle, 0, 0)
			return
		end
		local angle = math.atan2(lp.X, -lp.Z) -- positive = target is to the right
		local throttle = if math.abs(angle) > 1.3 then 0.5 else 1
		if dist < 25 then
			throttle *= 0.6
		end
		S.VehicleService.Drive(vehicle, throttle, math.clamp(angle * 1.6, -1, 1))
		task.wait(0.1)
	end
	S.VehicleService.Drive(vehicle, 0, 0)
	if vehicle.model.Parent then
		-- Couldn't get there (blocked, or tipped over): put it down upright next to the target, facing it, on the
		-- first spot around the target where nothing solid is in the way (placed posts, walls, piles, people).
		local from = vehicle.chassis.Position - target
		local start = if Vector2.new(from.X, from.Z).Magnitude > 0.1 then math.atan2(from.X, from.Z) else 0
		local foot = Vector3.new(vehicle.chassis.Size.X + 3.4, 3.6, vehicle.chassis.Size.Z + 1.5)
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = { vehicle.model, workspace.Terrain, folder } -- (the bot driving it is in folder)
		op.RespectCanCollide = true
		local best: CFrame? = nil
		for i = 0, 11 do
			local a = start + (if i % 2 == 0 then 1 else -1) * math.ceil(i / 2) * math.rad(30)
			local pos = target + Vector3.new(math.sin(a), 0, math.cos(a)) * (within - 1)
			local cf = CFrame.lookAt(Vector3.new(pos.X, 1.8, pos.Z), Vector3.new(target.X, 1.8, target.Z))
			best = best or cf
			if #workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0.6, 0), foot, op) == 0 then
				best = cf
				break
			end
		end
		vehicle.model:PivotTo(best :: CFrame)
		task.wait(0.3)
	end
end

local function sitIn(b: Bot, seat: BasePart, boardPart: BasePart): boolean
	if b.seat == seat then
		return true
	end
	walkTo(b, boardPart.Position, 8)
	local s = seat :: any
	if s.Occupant and s.Occupant ~= b.hum then
		return false
	end
	if b.hum.SeatPart and b.hum.SeatPart ~= seat then
		leaveSeat(b)
	end
	s:Sit(b.hum)
	task.wait(0.4)
	if b.hum.SeatPart ~= seat then
		return false
	end
	b.seat = seat
	return true
end

---------------------------------------------------------------------------------------------------------------
-- Work
---------------------------------------------------------------------------------------------------------------

-- A bot's tap on the Timing needle: aims for the zone center with some error, judged by the task engine.
local function simulateTiming(pro: boolean?): number
	local TT = S.TaskEngine.TimingTask
	local cap = 1
	for _ = 1, 6 do
		local r = TT.NewRound()
		local aim = r.center * r.period -- the needle first reaches the zone center at this time
		local noise = (rng:NextNumber() + rng:NextNumber() - 1) * (if pro then PRO_AIM_SPREAD else AIM_SPREAD)
		task.wait(0.35 + math.max(0, aim + noise) + (if pro then rng:NextNumber(0.1, 0.3) else rng:NextNumber(0.2, 0.8)))
		local hit, acc = TT.JudgeAt(r, aim + noise)
		if hit then
			return math.min(acc, cap)
		end
		cap = math.max(0.4, cap - 0.15) -- same miss penalty as players
	end
	return 0.4
end

local function operate(b: Bot, kind: string, slot: any): boolean
	local rig = S.EquipmentService.Find(kind)
	if not rig or not rig.boardPart then
		return false
	end
	-- the crane arrives on its wheels: drive it onto its pad first (standing still there sets it up)
	if kind == "Crane" and rig.mode == "drive" and rig.driveSeat and rig.vehicle and rig.pad then
		if not sitIn(b, rig.driveSeat, rig.driveSeat) then
			return false
		end
		driveTo(rig.vehicle, rig.pad.Position, 3, 40)
		local t = os.clock()
		while rig.mode ~= "set" and os.clock() - t < 5 do
			task.wait(0.2)
		end
		if rig.mode ~= "set" then
			S.EquipmentService.SetUp(rig) -- didn't stop on it: set it up on the pad
		end
		leaveSeat(b)
		task.wait(0.4)
	end
	if not sitIn(b, rig.seat, rig.boardPart) then
		return false
	end
	if kind == "Excavator" and rig.vehicle then
		driveTo(rig.vehicle, slot.part.Position, rig.reach - 3, 30)
	end
	return true
end

-- Bot Operator brings the truck onto the DELIVERY pad (only when it's already at the site; the crew
-- drives it over from the RV park) and unloads it.
local function deliver(b: Bot, slot: any): boolean
	local cur = S.JobService.Current()
	local truck = cur and cur.truck
	if not truck or not S.JobService.LoadReady() then
		return false
	end
	local pad = slot.part.Position
	if (S.VehicleService.Position(truck) - pad).Magnitude > 160 then
		return false
	end
	if not sitIn(b, truck.seat, truck.seat) then
		return false
	end
	driveTo(truck, pad, 6, 40)
	leaveSeat(b)
	return S.JobService.BotDeliver(b.model, slot)
end

-- Is any task for this machine still not done?
local function machineWorkLeft(kind: string): boolean
	local cur = S.JobService.Current()
	if not cur then
		return false
	end
	for _, s in cur.slots do
		if not s.done and s.def.Equipment == kind then
			return true
		end
	end
	return false
end

-- A machine task through the machine's own controls (the same ones players use), with the bot's aim error.
local MACHINE_AIM = 1.4 -- studs
local function runMachine(b: Bot, kind: string, slot: any): boolean
	if not operate(b, kind, slot) then
		return false
	end
	local ok, rig = S.JobService.BotBegin(b.model, b.role, slot)
	if not ok or not rig then
		return false
	end
	local finished = S.EquipmentService.Autopilot(rig, function()
		return b.alive
	end, if b.pro then PRO_MACHINE_AIM else MACHINE_AIM)
	if not finished then
		S.JobService.BotAbort(b.model, slot, rig)
		return false
	end
	task.wait(if rig.kind == "Crane" then 1.5 else 0.6)
	if rig.kind == "Excavator" and rig.vehicle and rig.home and not machineWorkLeft("Excavator") then
		-- All holes dug: park it back where it started, clear of the house (the floor gets built over the holes
		-- next, and a machine left inside the footprint gets wedged), then climb out.
		driveTo(rig.vehicle, rig.home.Position, 4, 25)
		leaveSeat(b)
	end
	return true
end

local function workOn(b: Bot, slot: any): boolean
	local def = slot.def
	local cur = S.JobService.Current()
	if not cur then
		return false
	end
	if def.Kind == "Place" then
		local Carry = S.TaskEngine.Carry
		if Carry.Holding(b.model) ~= def.Item then
			if Carry.Holding(b.model) then
				Carry.Drop(b.model)
			end
			local pile = cur.site:FindFirstChild("Pile_" .. def.Item)
			if not pile then
				return false
			end
			walkTo(b, pile.Position, 6)
			if not S.JobService.BotPickUp(b.model, def.Item) then
				return false
			end
		end
		walkTo(b, standFor(b, slot), 4)
		return S.JobService.BotPlace(b.model, b.role, slot)
	elseif def.Kind == "Timing" or def.Kind == "Connect" or def.Kind == "Inspect" or def.Kind == "Trace" or def.Kind == "Gauge" then
		if def.Equipment then
			return runMachine(b, def.Equipment, slot)
		end
		walkTo(b, standFor(b, slot), 4)
		local ok, rig = S.JobService.BotBegin(b.model, b.role, slot)
		if not ok then
			return false
		end
		local acc = 1
		if def.Kind == "Timing" then
			-- several hits in a row (nailing): each one judged like a player's tap
			local n = math.max(1, def.Hits or 1)
			local sum = 0
			for _ = 1, n do
				sum += simulateTiming(b.pro)
			end
			acc = sum / n
		elseif def.Kind == "Trace" then
			-- a bot's weld: slow and a little wobbly (a pro: quicker and steady)
			task.wait(if b.pro then rng:NextNumber(2.5, 4) else rng:NextNumber(4, 8))
			acc = if b.pro then rng:NextNumber(0.9, 1) else rng:NextNumber(0.66, 0.95)
		elseif def.Kind == "Gauge" then
			-- a bot holding the needle in the green: a few seconds, sometimes slipping out
			local st = GaugeStyles[def.Style or "Pour"]
			task.wait((if st then st.need else 2) + (if b.pro then rng:NextNumber(0.8, 1.6) else rng:NextNumber(2, 4.5)))
			acc = if b.pro then rng:NextNumber(0.92, 1) else rng:NextNumber(0.7, 0.96)
		elseif def.Kind == "Connect" then
			-- bots are slow at the wiring puzzle (a pro less so)
			local seconds = if b.pro then rng:NextNumber(4, 7) else rng:NextNumber(8, 18)
			task.wait(seconds)
			acc = S.TaskEngine.ConnectTask.Accuracy(seconds)
		else
			task.wait(1)
		end
		if not b.alive then
			S.JobService.BotAbort(b.model, slot, rig)
			return false
		end
		S.JobService.BotFinish(b.model, slot, acc, rig)
		if rig then
			task.wait(if rig.kind == "Crane" then 3.2 else 0.6) -- let the machine finish its motion
			if rig.kind == "Excavator" and rig.vehicle and rig.home and not machineWorkLeft("Excavator") then
				-- All holes dug: park it back where it started, clear of the house (the floor gets built over the
				-- holes next, and a machine left inside the footprint gets wedged), then climb out.
				driveTo(rig.vehicle, rig.home.Position, 4, 25)
				leaveSeat(b)
			end
		end
		return true
	elseif def.Kind == "Deliver" then
		return deliver(b, slot)
	end
	return false
end

local function brain(b: Bot)
	while b.alive do
		local cur = S.JobService.Current()
		if not cur or cur.finishing then
			task.wait(1)
			continue
		end
		local did = false
		for _, slot in S.JobService.OpenSlotsFor(b.role, b.root.Position) do
			if not b.alive then
				break
			end
			local ok, result = pcall(workOn, b, slot)
			if not ok then
				warn("[Bots]", b.model.Name, result)
			elseif result then
				did = true
				break
			end
		end
		task.wait(if not did then 1.5 elseif b.pro then rng:NextNumber(0.3, 0.6) else rng:NextNumber(THINK_MIN, THINK_MAX))
	end
end

---------------------------------------------------------------------------------------------------------------
-- Crew management
---------------------------------------------------------------------------------------------------------------

-- Turns a bot into the hired pro for its trade.
local function makePro(b: Bot)
	b.pro = true
	b.model:SetAttribute("Pro", true)
	b.model:SetAttribute("SpeedScale", 1)
	b.hum.WalkSpeed = 16
	b.model.Name = "Pro " .. b.role
	b.hum.DisplayName = b.role .. " (PRO)"
	-- a gold hard hat, so the crew can spot the pro
	for _, acc in b.model:GetChildren() do
		local handle = if acc:IsA("Accessory") and acc.Name == "HardHat" then acc:FindFirstChild("Handle") else nil
		if handle and handle:IsA("BasePart") then
			handle.Color = Color3.fromRGB(255, 200, 40)
		end
	end
end

local function hasPro(role: string): boolean
	for _, b in bots do
		if b.alive and b.pro and b.role == role then
			return true
		end
	end
	return false
end

local function wanted(): { [string]: number }
	local out: { [string]: number } = {}
	local cur = S.JobService.Current()
	if not cur or cur.finishing then
		return out
	end
	local crew = S.CrewService.Snapshot()
	for _, role in Trades.Order do
		if #(crew[role] or {}) == 0 and S.JobService.UsesRole(role) then
			out[role] = if role == "Laborer" and cur.tier >= 3 then 2 else 1
		end
	end
	-- a hired pro stays for the whole job, even if a player picks that trade later (it was paid for)
	for role in proRole do
		out[role] = math.max(out[role] or 0, 1)
	end
	return out
end

local function reconcile()
	local want = wanted()
	local have: { [string]: number } = {}
	for _, b in bots do
		have[b.role] = (have[b.role] or 0) + 1
	end
	local Toast = Net.Event("Toast")
	local changed = false
	-- regular bots clock out before a pro does
	for pass = 1, 2 do
		for i = #bots, 1, -1 do
			local b = bots[i]
			if (b.pro == true) == (pass == 2) and (want[b.role] or 0) < (have[b.role] or 0) then
				have[b.role] -= 1
				Toast:FireAllClients(b.role .. " bot clocked out: a player took the job")
				despawn(b)
				changed = true
			end
		end
	end
	local spawnCF = S.JobService.SiteSpawn()
	if spawnCF then
		for role, n in want do
			for _ = (have[role] or 0) + 1, n do
				local b = spawnBot(role, spawnCF * CFrame.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-4, 4)))
				if b then
					local asPro = proRole[role] == true and not hasPro(role)
					if asPro then
						makePro(b)
					end
					table.insert(bots, b)
					task.spawn(brain, b)
					Toast:FireAllClients(if asPro then "The pro " .. role .. " is on site"
						else role .. " bot joined the crew (it fills the empty trade)")
					changed = true
				end
			end
		end
	end
	if changed then
		S.JobService.Broadcast()
	end
end

local function clearAll()
	for i = #bots, 1, -1 do
		despawn(bots[i])
	end
	table.clear(proRole) -- a pro is hired for one job
end

---------------------------------------------------------------------------------------------------------------
-- Hire a Pro (a paid boost, PurchaseService): a skilled bot takes an empty trade for the rest of this job.
---------------------------------------------------------------------------------------------------------------

-- The empty trade (no player on it, no pro yet) with the most unfinished work on this job.
local function proCandidate(): string?
	local cur = S.JobService.Current()
	if not cur or cur.finishing or cur.inspecting then
		return nil
	end
	local left: { [string]: number } = {}
	for _, slot in cur.slots do
		if not slot.done then
			left[slot.def.Role] = (left[slot.def.Role] or 0) + 1
		end
	end
	local best: string?, bestN = nil, 0
	for _, role in Trades.Order do
		if not proRole[role] and not S.CrewService.IsRoleHeld(role) and (left[role] or 0) > bestN then
			best, bestN = role, left[role]
		end
	end
	return best
end

function BotService.CanHirePro(): (boolean, string?)
	local cur = S.JobService.Current()
	if not cur or cur.finishing then
		return false, "Start a job first: a pro is hired for one job"
	end
	if cur.inspecting then
		return false, "The job is at final inspection: there's no work left for a pro"
	end
	if not proCandidate() then
		return false, "No empty trade with work left: a pro takes a trade no player is on"
	end
	return true, nil
end

-- Never yields. The pro replaces the regular bot on that trade (or joins now if the bots aren't on site yet).
function BotService.HirePro(buyer: Player): (boolean, string?)
	local ok, why = BotService.CanHirePro()
	local role = proCandidate()
	if not ok or not role then
		return false, why
	end
	proRole[role] = true
	local upgraded = false
	for _, b in bots do
		if b.alive and b.role == role and not b.pro then
			makePro(b)
			upgraded = true
			break
		end
	end
	Net.Event("Toast"):FireAllClients(("%s HIRED A PRO %s for this job!"):format(buyer.Name, string.upper(role)))
	if upgraded then
		S.JobService.Broadcast()
	else
		task.defer(reconcile) -- no bot on that trade yet: bring the pro in
	end
	return true, nil
end

function BotService.Start()
	folder = Instance.new("Folder")
	folder.Name = "CrewBots"
	folder.Parent = workspace
	S.JobService.Started.Event:Connect(function()
		task.delay(START_GRACE, reconcile)
	end)
	S.JobService.Cleared.Event:Connect(clearAll)
	S.CrewService.Changed.Event:Connect(function()
		task.defer(reconcile)
	end)
end

return BotService
