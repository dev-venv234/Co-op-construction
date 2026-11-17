--!strict
-- Job lifecycle (one crew job per server):
--   RV park site button (unlocked tiers only) -> blueprint built at that site, the starter's truck (empty) in RV
--   lot stall 1 -> crew loads the job's materials at the Crew Supply store (Main St) -> drives to the site -> unloads on the
--   DELIVERY pad (a load bigger than the truck takes more trips) ->
--   ghost slots open as their requirements finish -> inspection -> payout -> cleanup.
-- First-time players get a "drop-in" job instead (SessionService): the truck is already loaded and parked at
-- the site. Every prompt is re-validated here before the task engine runs.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local JobsConfig = require(ServerStorage.Config.Jobs)
local SitesConfig = require(ServerStorage.Config.Sites)
local TownLayout = require(ReplicatedStorage.Shared.Config.TownLayout)

local Job = {}
Job.Started = Instance.new("BindableEvent") -- (siteId: string, dropIn: boolean, firstJob: boolean)
Job.Ended = Instance.new("BindableEvent") -- (success: boolean)
Job.Cleared = Instance.new("BindableEvent") -- after the site is torn down

local S: any
local StateEvent: RemoteEvent
local Toast: RemoteEvent
local PayoutEvent: RemoteEvent

type Current = {
	id: string,
	siteId: string,
	tier: number,
	dropIn: boolean,
	originCF: CFrame,
	bp: any,
	cfg: any,
	site: Model,
	slots: { [string]: any },
	order: { string },
	truck: any,
	delivered: { [string]: number }, -- bundles already unloaded at the site, per item
	trips: number,
	deadlineAt: number,
	startedAt: number, -- os.clock() when the job started
	roleWorked: { [string]: number }, -- os.clock() of the last task a player finished, per trade
	joined: { [Player]: number }, -- os.clock() from which each player counts as on this job (pay share by time)
	finishing: boolean,
	inspecting: boolean?,
	phaseNote: string?, -- shown as the phase instead of "Final inspection" (Retry Inspection: rebuilding)
}
local current: Current? = nil

local CLEANUP_DELAY = 10
local DOCK_REACH = 45 -- truck must be this close to the dock to load (anywhere under / beside the LOADING canopy)
local dockPos: Vector3? = nil

-- Every prompt goes through one handler table, so bots (Phase 3) and Studio tests can trigger
-- exactly the same server code a player's tap does.
local promptHandlers: { [ProximityPrompt]: (Player) -> () } = {}
local function onPrompt(pp: ProximityPrompt, fn: (Player) -> ())
	promptHandlers[pp] = fn
	pp.Triggered:Connect(fn)
	pp.Destroying:Connect(function()
		promptHandlers[pp] = nil
	end)
end

function Job.Trigger(p: Player, pp: ProximityPrompt)
	local fn = promptHandlers[pp]
	if fn then
		fn(p)
	end
end

-- Other services (e.g. the coffee stand) route their prompts through the same handler table.
Job.RegisterPrompt = onPrompt

function Job.Init(services)
	S = services
end

-- Read-only view of the running job (nil when none).
function Job.Current(): Current?
	return current
end

-- A worker is a Player or a bot's character Model (BotService).
local function rootOf(p: Instance): BasePart?
	local c = if p:IsA("Player") then p.Character else p
	return if c then c:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Is this worker within reach of `pos`? For players this uses the server-trusted spot (MoveGuard), never the raw
-- character position, which a modified client can put anywhere (security audit H1).
local function near(p: Instance, pos: Vector3, reach: number): boolean
	local root = rootOf(p)
	if p:IsA("Player") and S.MoveGuard then
		local at = S.MoveGuard.Position(p)
		if at and (at - pos).Magnitude <= reach then
			return true
		end
		-- standing there, but got there faster than anyone can walk: say why nothing happens
		if root and (root.Position - pos).Magnitude <= reach and S.TaskEngine.Guard.Allow(p, "MoveToast", 3) then
			Toast:FireClient(p, "Hold on: you got here faster than anyone can walk. Try again in a moment")
		end
		return false
	end
	return root ~= nil and (root.Position - pos).Magnitude <= reach
end

local function makePrompt(parent: Instance, action: string, object: string, reach: number): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = 0
	pp.MaxActivationDistance = reach
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.GamepadKeyCode = Enum.KeyCode.ButtonX
	pp.Parent = parent
	return pp
end

-- Bundles still to bring to the site, per item (already unloaded ones don't count).
local function remaining(cur: Current): { [string]: number }
	local out: { [string]: number } = {}
	for item, n in cur.cfg.Load do
		out[item] = math.max(0, n - (cur.delivered[item] or 0))
	end
	return out
end

-- How much of the job's load is delivered or on the truck (capped per item at what's needed), out of the total.
local function loadProgress(cur: Current): (number, number)
	local counts = if cur.truck then S.VehicleService.CargoCounts(cur.truck) else {}
	local have, need = 0, 0
	for item, n in cur.cfg.Load do
		need += n
		have += math.min((cur.delivered[item] or 0) + (counts[item] or 0), n)
	end
	return have, need
end

-- This trip: bundles on the truck, and how many it should carry (its capacity or what's left, whichever is less).
local function tripProgress(cur: Current): (number, number)
	if not cur.truck then
		return 0, 0
	end
	local left = 0
	for _, n in remaining(cur) do
		left += n
	end
	local onTruck = 0
	for _, n in S.VehicleService.CargoCounts(cur.truck) do
		onTruck += n
	end
	return onTruck, math.min(S.VehicleService.Capacity(cur.truck), left)
end

local function snapshot(): { [string]: any }
	local s: { [string]: any } = { active = false, roles = S.CrewService.Snapshot() }
	local cur = current
	if cur then
		local done, total, phase = 0, 0, "Wrapping up"
		for _, id in cur.order do
			local slot = cur.slots[id]
			total += 1
			if slot.done then
				done += 1
			elseif phase == "Wrapping up" then
				phase = slot.def.Phase
			end
		end
		local deliver = cur.slots.deliver
		if deliver and not deliver.done then
			local have, need = loadProgress(cur)
			local onTruck, target = tripProgress(cur)
			-- a loaded truck already at the site (first-timer drop-ins start that way) only needs unloading
			local atSite = cur.truck ~= nil and (S.VehicleService.Position(cur.truck) - deliver.part.Position).Magnitude < 60
			phase = if onTruck == 0 or onTruck < target
				then ("Load the truck at Crew Supply %d/%d"):format(have, need)
				elseif atSite then "Unload the truck at DELIVERY"
				else ("Drive to Site %d, unload at DELIVERY"):format(cur.tier)
			if cur.trips > 0 then
				phase ..= (" (trip %d)"):format(cur.trips + 1)
			end
		end
		s.active = true
		s.job = cur.bp.DisplayName
		s.site = cur.tier
		s.deadlineAt = cur.deadlineAt
		s.done = done
		s.total = total
		s.phase = if cur.finishing then "Finished" elseif cur.phaseNote then cur.phaseNote
			elseif cur.inspecting then "Final inspection" else phase
	end
	s.bots = if S.BotService then S.BotService.Summary() else {}
	return s
end

function Job.Broadcast()
	StateEvent:FireAllClients(snapshot())
end

local function requirementsMet(cur: Current, slot: any): boolean
	for _, id in slot.def.Requires do
		local req = cur.slots[id]
		if not req or not req.done then
			return false
		end
	end
	-- Chaos rework (e.g. re-stack a dropped crane load) adds requirements per slot; blueprint defs stay untouched.
	if slot.extraRequires then
		for _, id in slot.extraRequires do
			local req = cur.slots[id]
			if req and not req.done then
				return false
			end
		end
	end
	return true
end

local function refresh(cur: Current)
	for _, slot in cur.slots do
		if not slot.done then
			local open = requirementsMet(cur, slot)
			if open ~= slot.open then
				slot.open = open
				if open then
					slot.openedAt = os.clock() -- (StalledRoles: how long its work has been waiting)
				end
				slot.prompt:SetAttribute("Open", open)
				S.BlueprintService.SetVisual(slot, if open then "open" else "locked")
			end
		end
	end
end

local finish: (success: boolean, damage: { [Player]: number }?, fallen: number?) -> ()

local function complete(cur: Current, slot: any, p: Instance, accuracy: number)
	if current ~= cur or cur.finishing or slot.done then
		return
	end
	slot.done = true
	slot.busyBy = nil
	slot.prompt:Destroy()
	if p:IsA("Player") then
		cur.roleWorked[slot.def.Role] = os.clock() -- a player is working this trade (StalledRoles)
	end
	S.QualityService.Record(p, slot.def.Id, accuracy)
	S.ProgressionService.AwardTask(p, accuracy)
	S.BlueprintService.SetVisual(slot, "done")
	if S.DetailService then
		S.DetailService.OnDone(cur, slot) -- siding, windows, doors, pitched roofs
	end
	-- Sound cue for the crew: nails and finishing work hammer, pieces thud into place, electrical work sparks.
	local def = slot.def
	local cue = if def.Kind == "Connect" or def.Kind == "Trace" or def.Role == "Electrician" then "Spark"
		elseif def.Kind == "Place" or def.Kind == "Deliver" or def.Equipment == "Crane" then "Place"
		elseif def.Kind == "Timing" and not def.Equipment then "Hammer"
		else nil
	if cue then
		Net.Cue(cue, slot.part.Position)
	end
	-- Rework slots (ChaosService) clean up after themselves and report back.
	if slot.cleanup then
		slot.cleanup:Destroy()
		slot.cleanup = nil
	end
	if slot.onDone then
		task.spawn(slot.onDone, p)
	end
	if slot.def.Kind == "Inspect" then
		-- The inspector walks the house; weak work collapses and is charged to whoever built it.
		if S.InspectionService then
			cur.inspecting = true
			Job.Broadcast()
			S.InspectionService.Run(cur, function(damage, fallen)
				finish(true, damage, fallen)
			end)
		else
			finish(true)
		end
		return
	end
	refresh(cur)
	Job.Broadcast()
end

local onPrompt_slot: (cur: Current, slot: any) -> ()

-- A rework task added mid-job (ChaosService: re-stack a dropped load, fix an inspector flag).
-- def is a normal slot def (Id, Kind, Role, Label, Size, Done, Requires...); cleanup is destroyed when it's done.
function Job.AddSlot(def: any, cf: CFrame, cleanup: Instance?, onDone: ((Instance) -> ())?): any
	local cur = current
	if not cur or cur.finishing or cur.slots[def.Id] then
		return nil
	end
	def.Requires = def.Requires or {}
	def.Phase = def.Phase or "Rework"
	local slot: any = S.BlueprintService.AddSlot(cur.site, def, cf)
	slot.cleanup = cleanup
	slot.onDone = onDone
	cur.slots[def.Id] = slot
	table.insert(cur.order, def.Id)
	onPrompt_slot(cur, slot)
	refresh(cur)
	Job.Broadcast()
	return slot
end

-- Closes a rework slot nobody finished (its time ran out): no credit, no quality record.
function Job.DropSlot(id: string)
	local cur = current
	local slot = cur and cur.slots[id]
	if not cur or not slot or slot.done then
		return
	end
	slot.done = true -- a task still running on it ends in nothing (complete() ignores done slots)
	slot.busyBy = nil
	slot.prompt:Destroy()
	slot.part:Destroy()
	cur.slots[id] = nil
	local i = table.find(cur.order, id)
	if i then
		table.remove(cur.order, i)
	end
	Job.Broadcast()
end

-- What the HUD shows as the phase while the job is at inspection (nil = the normal text).
function Job.SetPhaseNote(cur: Current, note: string?)
	if current == cur then
		cur.phaseNote = note
		Job.Broadcast()
	end
end

-- Crane mishap: the lift failed, the load lies on the ground. A Laborer re-stacks it before the lift can go again.
local function onCraneMishap(cur: Current, slot: any, p: Instance, debris: BasePart?)
	if current ~= cur or cur.finishing or slot.done then
		if debris then
			debris:Destroy()
		end
		return
	end
	slot.busyBy = nil
	S.QualityService.Record(p, slot.def.Id .. "_mishap", 0.4)
	local id = "restack_" .. slot.def.Id
	local at = if debris then debris.Position else slot.part.Position
	Job.AddSlot({
		Id = id,
		Kind = "Timing",
		Role = "Laborer",
		Phase = "Rework",
		Label = "Re-stack dropped load",
		Size = Vector3.new(8.6, 2, 6.6),
		Done = { Color = Color3.fromRGB(190, 150, 100), Material = "WoodPlanks", Transparency = 1 },
		Collide = false,
		Reach = 12,
	}, CFrame.new(at.X, 1, at.Z), debris, nil)
	slot.extraRequires = slot.extraRequires or {}
	table.insert(slot.extraRequires, id)
	refresh(cur)
	Job.Broadcast()
	Net.Cue("CrashMetal", at)
	Toast:FireAllClients("CRANE MISHAP! The load slipped off the hook. Laborer: re-stack it, then the Operator lifts again")
end

-- Finishes an equipment task (players and bots): normal motion, or a crane mishap when ChaosService armed one.
local function finishRig(cur: Current, slot: any, rig: any, p: Instance, acc: number)
	local mishap = rig.kind == "Crane" and S.ChaosService and S.ChaosService.TakeCraneMishap()
	S.EquipmentService.FinishWork(rig, slot, function()
		complete(cur, slot, p, acc)
	end, if mishap then function(debris: BasePart?)
		onCraneMishap(cur, slot, p, debris)
	end else nil)
end

-- Chaos blocks (rain: no pouring). Returns the reason or nil.
local function chaosBlock(slot: any): string?
	return if S.ChaosService then S.ChaosService.Blocks(slot) else nil
end

local function onPile(cur: Current, p: Instance, item: string, pilePart: BasePart)
	if current ~= cur or cur.finishing then
		return
	end
	if S.TaskEngine.IsBusy(p) or not near(p, pilePart.Position, 14) then
		return
	end
	if S.TaskEngine.Carry.Holding(p) then
		Toast:FireClient(p, "Hands full. Use it or tap Drop first")
		return
	end
	S.TaskEngine.Carry.PickUp(p, item, cur.bp.Items[item])
end

local function addPile(cur: Current, item: string, worldPos: Vector3)
	local pp = S.BlueprintService.AddPile(cur.site, item, cur.bp.Items[item], worldPos)
	onPrompt(pp, function(pl)
		onPile(cur, pl, item, pp.Parent :: BasePart)
	end)
end

-- Where an unloaded item's pile goes: the blueprint's staging spot for it, else next to the delivery pad.
local function deliveredPilePos(cur: Current, item: string, padDef: any, k: number): Vector3
	for _, pile in cur.bp.Piles do
		if pile.Item == item then
			return cur.originCF:PointToWorldSpace(pile.Pos)
		end
	end
	local off = cur.bp.DeliveryZone.PileOffset
	return cur.originCF:PointToWorldSpace(Vector3.new(padDef.Pos.X + off.X, 0, padDef.Pos.Z + off.Z + (k - 1) * 5))
end

-- Unload the truck on the DELIVERY pad (players and bots). Returns false with a reason when it can't.
-- Each trip must bring a full truck (or everything that's left). The slot completes once the whole load is here.
local function doDeliver(cur: Current, slot: any, actor: Instance): (boolean, string?)
	local truck = cur.truck
	local onTruck, target = tripProgress(cur)
	if not truck or onTruck == 0 or onTruck < target then
		return false, ("Fill the truck at Crew Supply on Main St first (%d/%d this trip)"):format(onTruck, target)
	end
	local offset = S.VehicleService.Position(truck) - slot.part.Position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > cur.bp.DeliveryZone.Radius then
		return false, "Drive the truck onto the DELIVERY pad first"
	end
	local unloaded = S.VehicleService.UnloadAll(truck)
	local k = 0
	for item, n in unloaded do
		local before = cur.delivered[item] or 0
		cur.delivered[item] = before + n
		if before == 0 then
			k += 1
			addPile(cur, item, deliveredPilePos(cur, item, slot.def, k))
		end
	end
	cur.trips += 1
	local have, need = loadProgress(cur)
	if have >= need then
		Toast:FireAllClients("Materials delivered! Grab them from the piles")
		complete(cur, slot, actor, 1)
	else
		Toast:FireAllClients(("Trip %d unloaded (%d/%d bundles). Drive back to Crew Supply for the rest"):format(
			cur.trips, have, need))
		Job.Broadcast()
	end
	return true, nil
end

-- Rush Delivery (a paid boost for the whole crew, PurchaseService): the supplier trucks whatever is still missing
-- straight to the site. It only skips the hauling: every piece still has to be built by the crew. Can it be used now?
function Job.CanRush(): (boolean, string?)
	local cur = current
	if not cur or cur.finishing then
		return false, "Start a job first: Rush Delivery brings that job's materials to the site"
	end
	local deliver = cur.slots.deliver
	if not deliver or deliver.done then
		return false, "This job's materials are already at the site"
	end
	return true, nil
end

-- Does the same bookkeeping as unloading the last trip (doDeliver): piles for what wasn't on site yet, the truck
-- emptied, the Deliver slot completed in the buyer's name. Never yields.
function Job.RushDelivery(buyer: Player): (boolean, string?)
	local ok, why = Job.CanRush()
	local cur = current
	if not ok or not cur then
		return false, why
	end
	local slot = cur.slots.deliver
	if cur.truck then
		S.VehicleService.UnloadAll(cur.truck) -- what's on the truck counts as delivered too
	end
	local k = 0
	for item, n in cur.cfg.Load do
		local before = cur.delivered[item] or 0
		cur.delivered[item] = n
		if before == 0 then
			k += 1
			addPile(cur, item, deliveredPilePos(cur, item, slot.def, k))
		end
	end
	Toast:FireAllClients(("RUSH DELIVERY! %s had the materials trucked straight to Site %d. Grab them from the piles"):format(
		buyer.Name, cur.tier))
	complete(cur, slot, buyer, 1)
	return true, nil
end

local function onSlot(cur: Current, p: Player, slot: any)
	if current ~= cur or cur.finishing or slot.done then
		return
	end
	local def = slot.def
	if not S.CrewService.GetRole(p) then
		Toast:FireClient(p, "Pick a trade first")
		return
	end
	if not S.CrewService.CanDo(p, def.Role) then
		Toast:FireClient(p, "That's the " .. def.Role .. "'s job")
		return
	end
	if not requirementsMet(cur, slot) then
		Toast:FireClient(p, "Not ready yet")
		return
	end
	local blocked = chaosBlock(slot)
	if blocked then
		Toast:FireClient(p, blocked)
		return
	end
	if slot.busyBy then
		Toast:FireClient(p, "Someone is already on it")
		return
	end
	if S.TaskEngine.IsBusy(p) then
		return
	end
	-- Equipment tasks (excavator holes, crane lifts): the player must be operating that machine within its
	-- reach. Everything else: the player must be standing close to the slot.
	local rig: any = nil
	if def.Equipment then
		local why
		rig, why = S.EquipmentService.CheckOperator(p, def.Equipment, slot.part.Position)
		if not rig then
			Toast:FireClient(p, why or "You need the right machine for this")
			return
		end
	elseif not near(p, slot.part.Position, (def.Reach or 12) + 4) then
		return
	end

	local function done(acc: number)
		if rig then
			finishRig(cur, slot, rig, p, acc)
		else
			complete(cur, slot, p, acc)
		end
	end
	local function cancelled()
		slot.busyBy = nil
		if rig then
			S.EquipmentService.CancelWork(rig)
		end
	end

	if def.Kind == "Place" then
		if S.TaskEngine.Carry.Holding(p) ~= def.Item then
			Toast:FireClient(p, "Bring a " .. def.Item .. " from the pile")
			return
		end
		S.TaskEngine.Carry.Consume(p)
		Toast:FireClient(p, "Placed " .. def.Item)
		done(1)
	elseif def.Kind == "Timing" and rig then
		-- machine tasks are done by hand with the machine's own controls (EquipmentService, client MachineController)
		slot.busyBy = p
		S.EquipmentService.BeginManual(rig, slot, p, done, cancelled)
		Toast:FireClient(p, if rig.kind == "Crane" then "Lift started: lower the hook onto the roof section on the ground"
			else "Dig: lower the arm into the glowing hole and lift it out, 3 times")
	elseif def.Kind == "Timing" then
		slot.busyBy = p
		if not S.TaskEngine.BeginTiming(p, slot.part, def.Label, done, cancelled, def.Hits) then
			slot.busyBy = nil
		end
	elseif def.Kind == "Trace" then
		slot.busyBy = p
		if not S.TaskEngine.BeginTrace(p, slot.part, def.Label, done, cancelled) then
			slot.busyBy = nil
		end
	elseif def.Kind == "Gauge" then
		slot.busyBy = p
		if not S.TaskEngine.BeginGauge(p, slot.part, def.Label, def.Style or "Pour", done, cancelled) then
			slot.busyBy = nil
		end
	elseif def.Kind == "Connect" then
		slot.busyBy = p
		if not S.TaskEngine.BeginConnect(p, slot.part, def.Label, done, cancelled) then
			slot.busyBy = nil
		end
	elseif def.Kind == "Deliver" then
		local ok, why = doDeliver(cur, slot, p)
		if not ok then
			Toast:FireClient(p, why or "Can't unload yet")
		end
	elseif def.Kind == "Inspect" then
		done(1)
	end
end

-- Loading at Crew Supply (Workspace.SupplyStore): carry a bundle from a supply stack, then tap the truck bed.
local function onLoadTruck(cur: Current, p: Player)
	if current ~= cur or cur.finishing or not cur.truck then
		return
	end
	if cur.slots.deliver and cur.slots.deliver.done then
		return
	end
	local item = S.TaskEngine.Carry.Holding(p)
	if not item then
		Toast:FireClient(p, "Grab a bundle from the stacks at Crew Supply first")
		return
	end
	if not cur.cfg.Load[item] then
		Toast:FireClient(p, "This job doesn't need " .. item .. " on the truck")
		return
	end
	local counts = S.VehicleService.CargoCounts(cur.truck)
	if (counts[item] or 0) >= remaining(cur)[item] then
		Toast:FireClient(p, "Enough " .. item .. " loaded")
		return
	end
	local onTruck = tripProgress(cur)
	if onTruck >= S.VehicleService.Capacity(cur.truck) then
		Toast:FireClient(p, ("The truck is full (%d). Drive this load to the site, then come back for the rest"):format(onTruck))
		return
	end
	if not near(p, cur.truck.bed.Position, 14) then
		return
	end
	if dockPos and (S.VehicleService.Position(cur.truck) - dockPos).Magnitude > DOCK_REACH then
		Toast:FireClient(p, "Park the truck under the LOADING canopy at Crew Supply first")
		return
	end
	S.TaskEngine.Carry.Consume(p)
	S.VehicleService.AddCargo(cur.truck, item, cur.bp.Items[item])
	Net.Cue("Place", cur.truck.bed.Position)
	S.QualityService.Record(p, "load_" .. item, 1)
	S.ProgressionService.AwardTask(p, 1)
	local have, total = loadProgress(cur)
	local onTruck, target = tripProgress(cur)
	if onTruck >= target and have < total then
		Toast:FireAllClients(("Truck full (%d/%d bundles)! Drive to Site %d; the rest needs another trip"):format(
			have, total, cur.tier))
	else
		Toast:FireAllClients(("Loaded %s (%d/%d)"):format(item, have, total))
	end
	Job.Broadcast()
end

local loadingNow = false -- a stack is loading the truck right now (bundles in the air)

-- A bundle flying from a stack into the truck bed (looks only; the cargo is added when it lands). Yields ~0.45 s.
local function flyBundle(from: BasePart, to: BasePart, def: any)
	local b = Instance.new("Part")
	b.Name = "FlyingBundle"
	b.Anchored = true
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.Size = Vector3.new(2.6, 1, 6)
	b.Color = if def and typeof(def.Color) == "Color3" then def.Color else Color3.fromRGB(200, 170, 120)
	local ok, mat = pcall(function()
		return (Enum.Material :: any)[def.Material]
	end)
	b.Material = if ok and mat then mat else Enum.Material.WoodPlanks
	local a = from.Position + Vector3.new(0, from.Size.Y / 2 + 0.6, 0)
	b.CFrame = CFrame.new(a)
	b.Parent = workspace
	local t0 = os.clock()
	while true do
		local k = math.min(1, (os.clock() - t0) / 0.45)
		local c = to.Position + Vector3.new(0, 1.5, 0)
		local pos = a:Lerp(c, k) + Vector3.new(0, math.sin(k * math.pi) * 6, 0)
		b.CFrame = to.CFrame.Rotation + pos
		if k >= 1 then
			break
		end
		task.wait()
	end
	b:Destroy()
end

-- Loads n bundles of `item` from `stack` into the job's truck, flying over one after another. `p` (if any) gets the
-- task credit (XP, quality) per bundle. Toasts the progress and refreshes the HUD when done.
local function loadBundles(cur: Current, p: Player?, item: string, stack: BasePart, n: number)
	local truck = cur.truck
	if not truck or not truck.bed or loadingNow then
		return
	end
	local bed = truck.bed :: BasePart
	local def = cur.bp.Items[item]
	loadingNow = true
	task.spawn(function()
		local loaded = 0
		-- stops when the job ends or its materials are all on site (Rush Delivery can do that mid-flight)
		local function stillNeeded(): boolean
			return current == cur and not cur.finishing and truck.model.Parent ~= nil
				and not (cur.slots.deliver and cur.slots.deliver.done)
		end
		for _ = 1, n do
			if not stillNeeded() then
				break
			end
			flyBundle(stack, bed, def)
			if stillNeeded() and S.VehicleService.AddCargo(truck, item, def) then
				loaded += 1
				Net.Cue("Place", bed.Position)
				if p and p.Parent then
					S.QualityService.Record(p, "load_" .. item, 1)
					S.ProgressionService.AwardTask(p, 1)
				end
			end
		end
		loadingNow = false
		if not stillNeeded() or loaded == 0 then
			return
		end
		local have, total = loadProgress(cur)
		local onT, target = tripProgress(cur)
		if have >= total then
			Toast:FireAllClients(("All loaded (%d/%d)! Drive to Site %d"):format(have, total, cur.tier))
		elseif onT >= target then
			Toast:FireAllClients(("Truck full (%d/%d bundles)! Drive to Site %d; the rest needs another trip"):format(
				have, total, cur.tier))
		else
			Toast:FireAllClients(("Loaded %d %s (%d/%d)"):format(loaded, item, have, total))
		end
		Job.Broadcast()
	end)
end

-- Holding a stack at Crew Supply loads every bundle of that kind this trip still needs (the truck has to be at the
-- LOADING canopy). The drive-through below does the same on its own, so this is just the manual way.
-- (Carrying a bundle and tapping the bed still works, e.g. for a bundle someone already holds.)
local function onDockStack(p: Player, item: string, stack: BasePart)
	local cur = current
	if not cur or cur.finishing or (cur.slots.deliver and cur.slots.deliver.done) then
		Toast:FireClient(p, "Start a job at the site board first")
		return
	end
	local need = cur.cfg.Load[item]
	if not need then
		Toast:FireClient(p, "This job doesn't need " .. item .. " (it's already at the site)")
		return
	end
	local truck = cur.truck
	if not truck or not truck.bed or loadingNow then
		return
	end
	if S.TaskEngine.IsBusy(p) or not near(p, stack.Position, 12) then
		return
	end
	local onTruckItem = S.VehicleService.CargoCounts(truck)[item] or 0
	local want = (remaining(cur)[item] or 0) - onTruckItem
	if want <= 0 then
		Toast:FireClient(p, "No more " .. item .. " needed: the rest is on the truck or at the site")
		return
	end
	if not dockPos or (S.VehicleService.Position(truck) - dockPos).Magnitude > DOCK_REACH then
		Toast:FireClient(p, "Park the truck under the LOADING canopy first, then hold a stack to load it")
		return
	end
	local onTruck = tripProgress(cur)
	local room = S.VehicleService.Capacity(truck) - onTruck
	if room <= 0 then
		Toast:FireClient(p, ("The truck is full (%d). Drive this load to the site, then come back for the rest"):format(onTruck))
		return
	end
	loadBundles(cur, p, item, stack, math.min(want, room))
end

-- Drive-through loading (2026-11-12, owner: "the loading is way to hard"): stop the job's truck at Crew Supply (within
-- DOCK_REACH of the dock, nearly still for ~1 s) and the yard loads everything this trip needs, item by item, from
-- the stacks. The driver (else the nearest crew member) gets the task credit. Runs a few times a second.
local stacksByItem: { [string]: BasePart } = {}
local yardLast: Vector3? = nil
local yardStill = 0
local function driveThrough()
	local cur = current
	if not cur or cur.finishing or not cur.truck or not cur.truck.bed or loadingNow or not dockPos then
		yardLast, yardStill = nil, 0
		return
	end
	if cur.slots.deliver and cur.slots.deliver.done then
		return
	end
	local truck = cur.truck
	local pos = S.VehicleService.Position(truck)
	if (pos - (dockPos :: Vector3)).Magnitude > DOCK_REACH then
		yardLast, yardStill = nil, 0
		return
	end
	local moved = if yardLast then ((pos - yardLast :: Vector3) * Vector3.new(1, 0, 1)).Magnitude else math.huge
	yardLast = pos
	yardStill = if moved < 1.2 then yardStill + 1 else 0 -- under ~3 studs/s at 0.4 s a check
	if yardStill < 2 then
		return
	end
	local onTruck = tripProgress(cur)
	local room = S.VehicleService.Capacity(truck) - onTruck
	if room <= 0 then
		return
	end
	local counts = S.VehicleService.CargoCounts(truck)
	for item, need in remaining(cur) do
		local want = need - (counts[item] or 0)
		local stack = stacksByItem[item]
		if want > 0 and stack then
			-- credit: whoever is driving, else the nearest crew member in the yard
			local occ = truck.seat.Occupant
			local credit = if occ then Players:GetPlayerFromCharacter(occ.Parent) else nil
			if not credit then
				local best = 60
				for _, pl in Players:GetPlayers() do
					local r = rootOf(pl)
					if r and (r.Position - pos).Magnitude < best then
						best, credit = (r.Position - pos).Magnitude, pl
					end
				end
			end
			if yardStill == 2 then
				Toast:FireAllClients("Loading the truck at Crew Supply...")
			end
			loadBundles(cur, credit, item, stack, math.min(want, room))
			return
		end
	end
end

local function lotCenter(lotId: string): Vector3?
	for _, lot in TownLayout.Lots do
		if lot.Id == lotId then
			return Vector3.new((lot.Min.X + lot.Max.X) / 2, 0, (lot.Min.Y + lot.Max.Y) / 2)
		end
	end
	return nil
end

-- The crew's truck waits in the RV park truck lot (stall 1); without the RV park it parks at the site.
local function stallCFrame(): CFrame?
	local park = workspace:FindFirstChild("RVPark")
	local stall = park and park:FindFirstChild("Stall_1", true)
	if stall and stall:IsA("BasePart") then
		return stall.CFrame
	end
	return nil
end

-- Where crew members appear at the running job's site (next to the inspection clipboard).
function Job.SiteSpawn(): CFrame?
	local cur = current
	if not cur then
		return nil
	end
	for _, def in cur.bp.Slots do
		if def.Kind == "Inspect" then
			local pos = cur.originCF:PointToWorldSpace(Vector3.new(def.Pos.X + 6, 3, def.Pos.Z - 4))
			return CFrame.lookAt(pos, cur.originCF.Position + Vector3.new(0, 3, 0))
		end
	end
	return cur.originCF * CFrame.new(0, 3, 0)
end

-- Can this player start this site? (Returns a reason when not.)
function Job.CanStart(p: Player, siteId: string): (boolean, string?)
	local siteCfg = SitesConfig[siteId]
	if not siteCfg then
		return false, "Unknown site"
	end
	if siteCfg.Release ~= "Launch" and not RunService:IsStudio() then
		return false, "This site opens in a future update"
	end
	if S.ProgressionService.UnlockedTier(p) < siteCfg.Tier then
		return false, ("Site %d unlocks at trade level %d"):format(siteCfg.Tier, siteCfg.MinLevel or 1)
	end
	if siteCfg.Truck and not S.DataService.OwnsVehicle(p, siteCfg.Truck) then
		return false, ("Site %d needs the Work pickup (truck dealer at the RV lot)"):format(siteCfg.Tier)
	end
	return true, nil
end

-- opts.dropIn: first-timer starter job (no role needed, truck already loaded and parked at the site).
function Job.StartJob(p: Player, siteId: string, opts: { dropIn: boolean? }?): boolean
	local dropIn = opts ~= nil and opts.dropIn == true
	if current then
		Toast:FireClient(p, "A job is already running")
		return false
	end
	if not dropIn then
		if not S.CrewService.GetRole(p) then
			Toast:FireClient(p, "Pick a trade first")
			return false
		end
		local ok, why = Job.CanStart(p, siteId)
		if ok then
			ok, why = S.CrewService.CanStartJobs(p)
		end
		if not ok then
			Toast:FireClient(p, why or "Locked")
			return false
		end
	end
	local siteCfg = SitesConfig[siteId]
	local center = lotCenter(siteId)
	if not siteCfg or not center then
		warn("[Job] unknown site", siteId)
		return false
	end
	local cfg = JobsConfig[siteCfg.Job]
	local bp = require(ReplicatedStorage.Shared.Blueprints:FindFirstChild(cfg.Blueprint) :: ModuleScript) :: any
	local originCF = CFrame.new(center) * CFrame.Angles(0, siteCfg.Yaw, 0)

	-- Materials that ride on the truck don't start at the site.
	local onTruck: { [string]: boolean } = {}
	for item in cfg.Load do
		onTruck[item] = true
	end
	local site, slots, piles = S.BlueprintService.Build(bp, workspace, originCF, onTruck)
	local order = {}
	for _, def in bp.Slots do
		table.insert(order, def.Id)
	end
	local stall = stallCFrame()
	local spawnCF = if dropIn or not stall then originCF * bp.Truck.Spawn else stall
	-- The starter's truck (drop-ins: the starter truck; sites that need a truck: that one).
	local truckKind = if dropIn then "StarterTruck" else (siteCfg.Truck or S.DataService.SelectedTruck(p))
	local truck = S.VehicleService.SpawnTruck(spawnCF, site, truckKind)
	S.EquipmentService.SpawnFor(bp, originCF, site) -- excavator, crane (bigger houses)
	if dropIn then
		for item, n in cfg.Load do
			for _ = 1, n do
				S.VehicleService.AddCargo(truck, item, bp.Items[item])
			end
		end
	end

	local cur: Current = {
		id = siteCfg.Job,
		siteId = siteId,
		tier = siteCfg.Tier,
		dropIn = dropIn,
		originCF = originCF,
		bp = bp,
		cfg = cfg,
		site = site,
		slots = slots,
		order = order,
		truck = truck,
		delivered = {},
		trips = 0,
		deadlineAt = workspace:GetServerTimeNow() + cfg.Deadline,
		startedAt = os.clock(),
		roleWorked = {},
		joined = {},
		finishing = false,
	}
	for _, pl in Players:GetPlayers() do
		cur.joined[pl] = cur.startedAt -- everyone here at the start counts from the start
	end
	current = cur

	for _, slot in slots do
		onPrompt_slot(cur, slot)
	end
	for item, pp in piles do
		onPrompt(pp, function(pl)
			onPile(cur, pl, item, pp.Parent :: BasePart)
		end)
	end
	local loadPrompt = makePrompt(truck.bed, "Load truck", "Truck bed", 12)
	loadPrompt:SetAttribute("LoadTruck", true) -- for the client guide
	onPrompt(loadPrompt, function(pl)
		onLoadTruck(cur, pl)
	end)

	S.QualityService.Reset()
	refresh(cur)
	Job.Broadcast()
	if dropIn then
		Toast:FireAllClients(("Welcome to the crew! %s job at Site %d. %d:00 on the clock"):format(
			bp.DisplayName, siteCfg.Tier, cfg.Deadline // 60))
	else
		local need = 0
		for _, n in cfg.Load do
			need += n
		end
		local cap = S.VehicleService.Capacity(truck)
		local trips = math.max(1, math.ceil(need / math.max(1, cap)))
		Toast:FireAllClients(("%s started the %s job at Site %d! Load %d bundles at Crew Supply on Main St (the truck holds %d: %d trip%s), then drive."):format(
			p.Name, bp.DisplayName, siteCfg.Tier, need, cap, trips, if trips == 1 then "" else "s"))
	end
	-- firstJob: started by someone who hasn't been paid yet (ChaosService keeps a newcomer's first job calm)
	local starterProfile = S.DataService.Get(p)
	Job.Started:Fire(siteId, dropIn, starterProfile ~= nil and starterProfile.FirstPayout ~= true)
	return true
end

onPrompt_slot = function(cur: Current, slot: any)
	onPrompt(slot.prompt, function(pl)
		onSlot(cur, pl, slot)
	end)
end

finish = function(success: boolean, damage: { [Player]: number }?, fallen: number?)
	local cur = current
	if not cur or cur.finishing then
		return
	end
	cur.finishing = true
	S.TaskEngine.CancelAll("The job is over")
	local timeLeft = math.max(0, cur.deadlineAt - workspace:GetServerTimeNow())

	if success then
		local avg = S.QualityService.Average()
		local pay, parts = S.EconomyService.ComputePayout(cur.cfg, avg, timeLeft)
		local contributors = S.QualityService.Contributors()
		-- Surprise inspector: every flagged mistake nobody fixed comes off each paycheck.
		local fine, flags = 0, 0
		if S.ChaosService then
			fine, flags = S.ChaosService.Fines(cur.cfg)
		end
		-- Fair share (EconomyService.PayShare): how many tasks each trade has on this job, and how long it ran.
		local roleTotals: { [string]: number } = {}
		for _, slot in cur.slots do
			roleTotals[slot.def.Role] = (roleTotals[slot.def.Role] or 0) + 1
		end
		local nowClock = os.clock()
		local jobSeconds = nowClock - cur.startedAt
		-- the trade each player mostly worked, and how many players mainly worked each trade
		local mainRoleOf: { [Player]: string } = {}
		local workers: { [string]: number } = {}
		for _, pl in Players:GetPlayers() do
			local mine: { [string]: number } = {}
			local best: string?, bestN = nil, 0
			for _, id in S.QualityService.TasksOf(pl) do
				local slot = cur.slots[id]
				if slot then
					local r = slot.def.Role
					mine[r] = (mine[r] or 0) + 1
					if mine[r] > bestN then
						best, bestN = r, mine[r]
					end
				end
			end
			if best then
				mainRoleOf[pl] = best
				workers[best] = (workers[best] or 0) + 1
			end
		end
		local paidPlayers: { Player } = {}
		for _, pl in Players:GetPlayers() do
			local tasks = contributors[pl] or 0
			local myDamage = if damage then damage[pl] or 0 else 0
			-- the trade this player mostly worked decides how many tasks a full paycheck needs
			local mainRole = mainRoleOf[pl]
			local need = S.EconomyService.TasksForFullPay(cur.cfg, #cur.order,
				if mainRole then roleTotals[mainRole] or 0 else 0, if mainRole then workers[mainRole] or 1 else 1)
			local share, shareWhy = S.EconomyService.PayShare(cur.cfg, tasks, need,
				nowClock - (cur.joined[pl] or cur.startedAt), jobSeconds)
			local gross = math.floor(pay * share + 0.5)
			local net = if tasks > 0 then math.max(0, gross - fine - myDamage) else 0
			-- 2x Pay game pass: the buyer's own paycheck only (EconomyService asks PurchaseService; 1 or 2, never more)
			local boost = if net > 0 then S.EconomyService.PayBoost(pl) else 1
			local earned = net * boost
			local note: string? = nil
			if earned > 0 then
				S.EconomyService.AddCash(pl, earned, cur.bp.DisplayName .. " job")
				-- job XP and company points need at least half a fair share
				if share >= 0.5 then
					table.insert(paidPlayers, pl)
					S.ProgressionService.AwardJob(pl)
				end
				S.DataService.RecordJob(pl, earned, S.QualityService.Grade(avg))
				if S.DataService.MarkFirstPayout(pl) then
					note = "First paycheck! Your own RV at the RV park is unlocked: next shift starts there."
				end
				task.spawn(S.DataService.Save, pl, false)
			else
				note = "You didn't finish any tasks on this job, so no pay this time."
			end
			PayoutEvent:FireClient(pl, {
				success = true,
				job = cur.bp.DisplayName,
				grade = S.QualityService.Grade(avg),
				accuracy = avg,
				quality = parts.quality,
				early = parts.early,
				base = parts.base,
				pay = earned,
				passBonus = earned - net, -- extra from the 2x Pay pass (0 without it)
				tasks = tasks,
				share = share, -- part of the paycheck earned (1 = all of it)
				shareWhy = shareWhy, -- "tasks" or "late" when under 1
				needTasks = need,
				timeLeft = timeLeft,
				fines = if tasks > 0 then math.min(fine, gross) else 0,
				finesCount = flags,
				damage = if tasks > 0 then math.min(myDamage, math.max(0, gross - fine)) else 0,
				collapsed = fallen or 0,
				note = note,
			})
		end
		-- company points for everyone who was paid (CompanyService)
		if S.CompanyService and #paidPlayers > 0 then
			S.CompanyService.AddJob(paidPlayers, cur.cfg.BasePay, S.QualityService.Grade(avg))
		end
	else
		PayoutEvent:FireAllClients({ success = false, job = cur.bp.DisplayName, note = "Out of time! The client walked off the job." })
	end
	-- The Awake buff lasts for one job.
	S.BuffService.EndJob()
	Job.Broadcast()
	Job.Ended:Fire(success)

	task.delay(CLEANUP_DELAY, function()
		if current ~= cur then
			return
		end
		S.TaskEngine.Carry.DropAll()
		S.EquipmentService.Clear()
		S.VehicleService.DespawnAll()
		cur.site:Destroy()
		current = nil
		Job.Broadcast()
		Job.Cleared:Fire()
	end)
end

---------------------------------------------------------------------------------------------------------------
-- Bot workers (BotService). Bots go through the same slot rules as players: their trade, requirements done,
-- nobody else on it, close enough or operating the right machine. Only the minigame input is simulated.
---------------------------------------------------------------------------------------------------------------

-- Open, unclaimed slots for a trade, nearest first.
function Job.OpenSlotsFor(role: string, from: Vector3): { any }
	local cur = current
	local out = {}
	if not cur or cur.finishing then
		return out
	end
	for _, slot in cur.slots do
		if not slot.done and slot.open and not slot.busyBy and slot.def.Role == role and not chaosBlock(slot) then
			table.insert(out, slot)
		end
	end
	table.sort(out, function(a, b)
		return (a.part.Position - from).Magnitude < (b.part.Position - from).Magnitude
	end)
	return out
end

-- Trades whose work is waiting on nobody: an open task nobody has claimed for `seconds`, and no player has finished
-- a task of that trade for `seconds` either (bot work doesn't count). BotService sends a helper bot to a trade a
-- player holds but isn't working (CLAUDE.md: no trade idle more than a minute). Deliveries are left out: the crew
-- is busy loading and driving then.
function Job.StalledRoles(seconds: number): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local cur = current
	if not cur or cur.finishing or cur.inspecting then
		return out
	end
	local now = os.clock()
	if now - cur.startedAt < seconds then
		return out
	end
	for _, slot in cur.slots do
		local role = slot.def.Role
		if not out[role] and not slot.done and slot.open and not slot.busyBy and slot.def.Kind ~= "Deliver"
			and not chaosBlock(slot)
			and now - (slot.openedAt or cur.startedAt) >= seconds
			and now - (cur.roleWorked[role] or cur.startedAt) >= seconds then
			out[role] = true
		end
	end
	return out
end

-- Has a player finished a task of this trade since `t` (os.clock)?
function Job.PlayerWorkedSince(role: string, t: number): boolean
	local cur = current
	return cur ~= nil and (cur.roleWorked[role] or 0) > t
end

function Job.UsesRole(role: string): boolean
	local cur = current
	if not cur then
		return false
	end
	for _, def in cur.bp.Slots do
		if def.Role == role then
			return true
		end
	end
	return false
end

function Job.LoadReady(): boolean
	local cur = current
	if not cur then
		return false
	end
	local onTruck, target = tripProgress(cur)
	return onTruck > 0 and onTruck >= target -- a full truck (or the last of the load) is ready to unload
end

local function botCan(cur: Current?, role: string, slot: any): boolean
	return cur ~= nil and current == cur and not cur.finishing and not slot.done and not slot.busyBy
		and slot.def.Role == role and requirementsMet(cur, slot) and not chaosBlock(slot)
end

function Job.BotPickUp(bot: Model, item: string): boolean
	local cur = current
	local pile = cur and cur.site:FindFirstChild("Pile_" .. item)
	if not cur or not pile or not pile:IsA("BasePart") then
		return false
	end
	onPile(cur, bot, item, pile)
	return S.TaskEngine.Carry.Holding(bot) == item
end

function Job.BotPlace(bot: Model, role: string, slot: any): boolean
	local cur = current
	if not botCan(cur, role, slot) or slot.def.Kind ~= "Place" then
		return false
	end
	if not near(bot, slot.part.Position, (slot.def.Reach or 12) + 4) or S.TaskEngine.Carry.Holding(bot) ~= slot.def.Item then
		return false
	end
	S.TaskEngine.Carry.Consume(bot)
	complete(cur :: Current, slot, bot, 1)
	return true
end

-- Claims a Timing / Connect / Inspect slot for a bot. Returns the machine rig for equipment tasks.
function Job.BotBegin(bot: Model, role: string, slot: any): (boolean, any)
	local cur = current
	if not botCan(cur, role, slot) then
		return false, nil
	end
	local def = slot.def
	local rig: any = nil
	if def.Equipment then
		rig = S.EquipmentService.CheckOperator(bot, def.Equipment, slot.part.Position)
		if not rig then
			return false, nil
		end
	elseif not near(bot, slot.part.Position, (def.Reach or 12) + 4) then
		return false, nil
	end
	slot.busyBy = bot
	if rig then
		-- the bot runs the machine through the same hand controls (EquipmentService.Autopilot)
		local c = cur :: Current
		S.EquipmentService.BeginManual(rig, slot, bot, function(acc: number)
			finishRig(c, slot, rig, bot, acc)
		end, function()
			if slot.busyBy == bot then
				slot.busyBy = nil
			end
			S.EquipmentService.CancelWork(rig)
		end)
	end
	return true, rig
end

function Job.BotFinish(bot: Model, slot: any, accuracy: number, rig: any)
	local cur = current
	if not cur or slot.busyBy ~= bot then
		return
	end
	if rig then
		finishRig(cur, slot, rig, bot, accuracy)
	else
		complete(cur, slot, bot, accuracy)
	end
end

function Job.BotAbort(bot: Model, slot: any, rig: any)
	if slot.busyBy == bot then
		slot.busyBy = nil
	end
	if rig then
		S.EquipmentService.CancelWork(rig)
	end
end

function Job.BotDeliver(bot: Model, slot: any): boolean
	local cur = current
	if not botCan(cur, "Operator", slot) or slot.def.Kind ~= "Deliver" then
		return false
	end
	return (doDeliver(cur :: Current, slot, bot))
end

-- Site buttons at the RV park site board (map parts with a StartSite attribute, built by DevTools/SiteBuilder).
local function hookSiteButton(button: BasePart)
	local siteId = button:GetAttribute("StartSite")
	local siteCfg = if typeof(siteId) == "string" then SitesConfig[siteId] else nil
	if not siteCfg then
		return
	end
	local cfg = JobsConfig[siteCfg.Job]
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "StartJobPrompt"
	pp.ActionText = "Start job"
	pp.ObjectText = ("Site %d - %d min - $%d each"):format(siteCfg.Tier, cfg.Deadline // 60, cfg.BasePay)
	pp.HoldDuration = 0.4
	pp.MaxActivationDistance = 7
	pp.RequiresLineOfSight = false
	pp.Parent = button
	onPrompt(pp, function(p)
		if not S.TaskEngine.Guard.Allow(p, "StartJob", 1) or not near(p, button.Position, 12) then
			return
		end
		-- Everyone joins at the RV park: if a crew is already working at this site, the button is a ride out there.
		local cur = current
		if cur and not cur.finishing then
			if cur.siteId == siteId then
				local cf = Job.SiteSpawn()
				local c = p.Character
				if cf and c and not S.TaskEngine.IsBusy(p) and not S.TaskEngine.Carry.Holding(p) then
					local to = cf * CFrame.new(math.random(-4, 4), 0, math.random(-3, 3))
					c:PivotTo(to)
					if S.MoveGuard then
						S.MoveGuard.Snap(p, to.Position) -- the server moved them: that spot is trusted
					end
					Toast:FireClient(p, ("Crew shuttle: you're at Site %d. Pick a trade and help out!"):format(cur.tier))
				end
			else
				Toast:FireClient(p, ("A crew is working at Site %d: tap the Site %d button to ride out"):format(cur.tier, cur.tier))
			end
			return
		end
		Job.StartJob(p, siteId :: string)
	end)
end

-- Dock stacks (map parts with a MaterialStack attribute, built by DevTools/RVParkBuilder).
local function hookDockStack(stack: BasePart)
	local item = stack:GetAttribute("MaterialStack")
	if typeof(item) ~= "string" then
		return
	end
	local loadable = false
	for _, cfg in JobsConfig do
		if cfg.Load[item] then
			loadable = true
		end
	end
	if not loadable then
		return -- stakes and posts already wait at each site
	end
	stacksByItem[item] = stack -- Crew Supply's stacks are hooked last, so they win over any old RV park ones
	local pp = makePrompt(stack, "Load " .. item .. " onto the truck", "Crew Supply", 10)
	pp.HoldDuration = 0.5
	onPrompt(pp, function(p)
		if S.TaskEngine.Guard.Allow(p, "DockPick", 0.4) then
			onDockStack(p, item, stack)
		end
	end)
end

function Job.Start()
	StateEvent = Net.Event("State")
	Toast = Net.Event("Toast")
	PayoutEvent = Net.Event("Payout")

	local park = workspace:WaitForChild("RVPark", 10)
	if park then
		for _, d in park:GetDescendants() do
			if d:IsA("BasePart") then
				if d:GetAttribute("StartSite") ~= nil then
					hookSiteButton(d)
				elseif d:GetAttribute("MaterialStack") ~= nil then
					hookDockStack(d)
				elseif d.Name == "Dock" then
					dockPos = d.Position
				end
			end
		end
	else
		warn("[Job] No Workspace.RVPark: no way to start jobs")
	end
	-- Crew Supply (DevTools/SupplyStoreBuilder) is where trucks load: its stacks and its Dock replace the old RV park dock.
	local store = workspace:WaitForChild("SupplyStore", 10)
	if store then
		for _, d in store:GetDescendants() do
			if d:IsA("BasePart") then
				if d:GetAttribute("MaterialStack") ~= nil then
					hookDockStack(d)
				elseif d.Name == "Dock" then
					dockPos = d.Position
				end
			end
		end
	else
		warn("[Job] No Workspace.SupplyStore: trucks can only load at an old RV park dock")
	end
	do
		task.spawn(function()
			while true do
				task.wait(0.4)
				local ok, err = pcall(driveThrough)
				if not ok then
					warn("[Job] drive-through loading:", err)
				end
			end
		end)
	end

	-- Studio-only test hook (server side; clients can't reach ServerStorage).
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "DevTrigger"
		-- Test scripts move the player around from the server, so by default the hook trusts where they stand.
		-- keepPosition = true leaves the trusted spot alone (to test MoveGuard itself).
		hook.OnInvoke = function(playerName: string, prompt: ProximityPrompt, keepPosition: boolean?)
			local pl = Players:FindFirstChild(playerName)
			if pl and pl:IsA("Player") then
				if S.MoveGuard and not keepPosition then
					S.MoveGuard.Snap(pl)
				end
				Job.Trigger(pl, prompt)
				return true
			end
			return false
		end
		hook.Parent = ServerStorage
	end

	-- Pay share by time: someone who joins while a job is running counts from now, not from the job's start.
	Players.PlayerAdded:Connect(function(p)
		local cur = current
		if cur then
			cur.joined[p] = os.clock()
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		local cur = current
		if cur then
			cur.joined[p] = nil
		end
	end)

	Net.Event("Hello").OnServerEvent:Connect(function(p)
		if S.TaskEngine.Guard.Allow(p, "Hello", 1) then
			StateEvent:FireClient(p, snapshot())
		end
	end)
	S.CrewService.Changed.Event:Connect(Job.Broadcast)

	-- Deadline watcher
	while true do
		task.wait(1)
		local cur = current
		if cur and not cur.finishing and not cur.inspecting and workspace:GetServerTimeNow() >= cur.deadlineAt then
			finish(false)
		end
	end
end

return Job
