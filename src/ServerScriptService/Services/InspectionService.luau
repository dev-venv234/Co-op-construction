--!strict
-- Final inspection (CLAUDE.md: "inspector walks the house; mistakes cost pay; skipped steps cause partial collapse").
-- When the Foreman calls the inspection, an inspector NPC walks the finished building. At each piece of weak work
-- (task accuracy under WEAK, worst first, machine tasks and paperwork excluded) he stops, and that piece collapses
-- (unanchored, real physics), taking down the finished pieces that were built on it. Each collapsed piece costs the
-- player who built it DAMAGE_SHARE of base pay ("whoever causes damage gets no pay for it"); bot work costs nobody.
-- Everything is decided on the server from server-side records.
--
-- Retry Inspection (2026-11-16, a paid boost: PurchaseService): after a walk with collapses the crew has a short
-- window to take a retry. Then every fallen piece becomes a rebuild task for its trade (normal rework slots, so
-- players and bots do them with the task engine), and when they're done or the time is up the inspector walks
-- again. A rebuilt piece goes back up and counts as well as it was rebuilt; a piece nobody rebuilt stays down and
-- is charged as before. So a retry never costs more than the first result, and nothing is finished for the crew.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Inspection = {}

local WEAK = 0.75
local MAX_WEAK = 5
local MAX_FALL = 8
local DAMAGE_SHARE = 0.06
local WALK_SPEED = 11
local RETRY_WINDOW = 25 -- seconds the crew has to take a retry after a walk with collapses
local RETRY_HOLD = 60 -- the window stays open this long (once) while someone is in Roblox's purchase prompt
local RETRY_SECONDS = 180 -- time to rebuild before the inspector walks again
local MAX_RETRIES = 2 -- per job

local S: any
local Toast: RemoteEvent
local inspector: Model? = nil
local token = 0

type Down = { slot: any, charge: Player? } -- a piece on the ground; charge = who pays for it (weak work only)
type Offer = { cur: any, untilT: number, taken: Player?, held: boolean }
local offer: Offer? = nil
local rebuiltBy: { [string]: Instance } = {} -- slot id -> who rebuilt it in a retry (they answer for it now)

function Inspection.Init(services)
	S = services
end

local function isRework(id: string): boolean
	return string.sub(id, 1, 8) == "restack_" or string.sub(id, 1, 4) == "fix_" or string.sub(id, 1, 5) == "load_"
		or string.sub(id, 1, 4) == "redo" or string.sub(id, -7) == "_mishap"
end

-- Only built pieces can fall: not checks and switches (level check, power on) or wiring (Connect).
local NOT_STRUCTURAL = { level = true, power = true }
local function structural(def: any): boolean
	return not NOT_STRUCTURAL[def.Id] and not def.NotStructural and def.Kind ~= "Connect" and def.Kind ~= "Inspect"
		and def.Kind ~= "Deliver" and not def.Equipment
end

-- Who answers for a piece: whoever rebuilt it in a retry, else whoever built it.
local function builderOf(slotId: string): Instance?
	local who: any = rebuiltBy[slotId]
	if not who then
		local rec = S.QualityService.RecordOf(slotId)
		who = rec and rec.player
	end
	return if typeof(who) == "Instance" then who else nil
end

-- Weak work only counts when a player built it: bots are the crew's stand-ins, and their misses already
-- lower the grade, so their work never collapses.
local function builtByPlayer(slotId: string): boolean
	local who = builderOf(slotId)
	return who ~= nil and who:IsA("Player")
end

local function walk(body: Model, pos: Vector3, timeout: number)
	local hum = body:FindFirstChildOfClass("Humanoid")
	local root = body:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		return
	end
	local t0 = os.clock()
	while body.Parent and os.clock() - t0 < timeout do
		if Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z).Magnitude < 5 then
			break
		end
		hum:MoveTo(Vector3.new(pos.X, root.Position.Y, pos.Z))
		task.wait(0.35)
	end
	if body.Parent and Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z).Magnitude >= 5 then
		body:PivotTo(CFrame.new(pos.X, 3.5, pos.Z))
	end
	hum:MoveTo(root.Position)
end

-- Drops a finished slot part with physics (remembering where it stood, for a rebuild).
local function collapse(slot: any)
	local p = slot.part
	if not p or not p.Parent then
		return
	end
	slot.homeCF = slot.homeCF or p.CFrame
	p.Anchored = false
	p.CanCollide = true
	p.Massless = false
	pcall(function()
		p:SetNetworkOwner(nil)
	end)
	local push = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit * 6
	p:ApplyImpulse((push + Vector3.new(0, 4, 0)) * p.AssemblyMass)
	p:ApplyAngularImpulse(Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * p.AssemblyMass * 8)
	p:SetAttribute("Collapsed", true)
	Net.Cue("CrashWood", p.Position)
end

-- Puts a rebuilt piece back where it stood (its decorations are welded to it and come along).
local function restore(slot: any)
	local p = slot.part
	if not p or not p.Parent or not slot.homeCF then
		return
	end
	p.AssemblyLinearVelocity = Vector3.zero
	p.AssemblyAngularVelocity = Vector3.zero
	p.Anchored = true
	p.CFrame = slot.homeCF
	p:SetAttribute("Collapsed", nil)
	S.BlueprintService.SetVisual(slot, "done")
	Net.Cue("Place", p.Position)
end

-- Finished pieces resting on `id` (direct dependents first, then theirs), done ones only.
local function dependents(cur: any, id: string, out: { any }, seen: { [string]: boolean })
	for _, other in cur.slots do
		local def = other.def
		if other.done and not seen[def.Id] and structural(def) then
			for _, r in def.Requires do
				if r == id then
					seen[def.Id] = true
					table.insert(out, other)
					dependents(cur, def.Id, out, seen)
					break
				end
			end
		end
		if #out >= MAX_FALL then
			return
		end
	end
end

-- One walk: the four corners of the building with a stop at each weak piece, which collapses with what rests on
-- it. Returns the pieces that fell on this walk, or nil when the job was torn down meanwhile.
local function inspect(cur: any, my: number, again: boolean): { Down }?
	local fell: { Down } = {}

	-- Weak work, worst first (a piece still on the ground from an earlier walk isn't judged twice)
	local weak = {}
	for _, r in S.QualityService.LowestFor(WEAK, 40) do
		local slot = cur.slots[r.slotId]
		if slot and slot.done and not isRework(r.slotId) and structural(slot.def) and builtByPlayer(r.slotId)
			and not slot.part:GetAttribute("Collapsed") then
			table.insert(weak, slot)
			if #weak >= MAX_WEAK then
				break
			end
		end
	end

	local spawnCF = S.JobService.SiteSpawn() or cur.originCF
	local body = inspector
	if not body or not body.Parent then
		body = S.BotService.MakeBody("Inspector", Color3.fromRGB(240, 240, 235), Color3.fromRGB(250, 250, 250), spawnCF)
		if body then
			local hum = body:FindFirstChildOfClass("Humanoid") :: Humanoid
			hum.WalkSpeed = WALK_SPEED
			body:SetAttribute("Inspector", true)
			body.Parent = workspace
			inspector = body
		end
	end
	Toast:FireAllClients(if again then "RE-INSPECTION: the inspector is walking the house again..."
		else "FINAL INSPECTION: the inspector is walking the house...")
	Net.Cue("Whistle", spawnCF.Position)

	-- Route: the four corners of the building, with a stop at each weak piece on the way.
	local o = cur.originCF
	-- Footprint of the building = extent of its finished slots (in the blueprint's own frame).
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, s in cur.slots do
		if s.done and s.def.Kind ~= "Deliver" and s.def.Kind ~= "Inspect" and not isRework(s.def.Id) then
			local at = if s.homeCF then s.homeCF.Position else s.part.Position
			local l = o:PointToObjectSpace(at)
			minX, maxX = math.min(minX, l.X), math.max(maxX, l.X)
			minZ, maxZ = math.min(minZ, l.Z), math.max(maxZ, l.Z)
		end
	end
	if minX == math.huge then
		minX, maxX, minZ, maxZ = -12, 12, -10, 10
	end
	minX -= 6; maxX += 6; minZ -= 6; maxZ += 6
	local route = {}
	for _, c in { Vector3.new(minX, 0, minZ), Vector3.new(maxX, 0, minZ), Vector3.new(maxX, 0, maxZ), Vector3.new(minX, 0, maxZ) } do
		table.insert(route, { pos = o:PointToWorldSpace(c) })
	end
	for _, slot in weak do
		-- insert each weak piece after the nearest corner
		local best, bestD = 1, math.huge
		for i, r in route do
			local d = (r.pos - slot.part.Position).Magnitude
			if r.slot == nil and d < bestD then
				best, bestD = i, d
			end
		end
		table.insert(route, best + 1, { pos = slot.part.Position, slot = slot })
	end

	for _, stop in route do
		if token ~= my or S.JobService.Current() ~= cur then
			return nil
		end
		if body then
			walk(body, stop.pos, 8)
		end
		local slot = stop.slot
		if slot and not slot.part:GetAttribute("Collapsed") then
			task.wait(1)
			local who = builderOf(slot.def.Id)
			local payer: Player? = if who and who:IsA("Player") and who.Parent == Players then who else nil
			local falling = { slot }
			dependents(cur, slot.def.Id, falling, { [slot.def.Id] = true })
			for _, s in falling do
				if not s.part:GetAttribute("Collapsed") and #fell < MAX_FALL then
					collapse(s)
					table.insert(fell, { slot = s, charge = if s == slot then payer else nil })
				end
			end
			local perPiece = math.floor(cur.cfg.BasePay * DAMAGE_SHARE + 0.5)
			local text = ("FAILED: %s collapsed"):format(slot.def.Label)
			if payer then
				text ..= (" - $%d off %s's pay"):format(perPiece, payer.Name)
			elseif who then
				text ..= " (bot work)"
			end
			Toast:FireAllClients(text)
			task.wait(1.2)
		end
	end
	return fell
end

---------------------------------------------------------------------------------------------------------------
-- Retry Inspection
---------------------------------------------------------------------------------------------------------------

-- Is a retry on offer right now? (PurchaseService asks before it charges or uses a credit.)
function Inspection.CanRetry(): (boolean, string?)
	local o = offer
	if not o or o.taken or S.JobService.Current() ~= o.cur then
		return false, "Retry Inspection is for right after a final inspection where work collapsed"
	end
	return true, nil
end

-- Takes the retry on offer for the crew. Never yields.
function Inspection.TakeRetry(p: Player): (boolean, string?)
	local ok, why = Inspection.CanRetry()
	local o = offer
	if not ok or not o then
		return false, why
	end
	o.taken = p
	Toast:FireAllClients(("%s bought RETRY INSPECTION: rebuild the fallen work, then the inspector walks again!"):format(p.Name))
	return true, nil
end

-- Someone is in Roblox's purchase prompt for the retry: keep the window open longer (once per offer).
function Inspection.HoldRetry()
	local o = offer
	if o and not o.taken and not o.held then
		o.held = true
		o.untilT = math.max(o.untilT, workspace:GetServerTimeNow() + RETRY_HOLD)
		workspace:SetAttribute("RetryOfferUntil", o.untilT)
	end
end

-- That prompt closed without a purchase: stop holding.
function Inspection.ReleaseRetry()
	local o = offer
	if o and not o.taken and o.held then
		o.untilT = math.min(o.untilT, workspace:GetServerTimeNow() + 6)
		workspace:SetAttribute("RetryOfferUntil", o.untilT)
	end
end

-- Opens the offer and waits. True when someone took it.
local function waitForRetry(cur: any, my: number, pieces: number): boolean
	local o: Offer = { cur = cur, untilT = workspace:GetServerTimeNow() + RETRY_WINDOW, taken = nil, held = false }
	offer = o
	workspace:SetAttribute("RetryOfferUntil", o.untilT) -- clients show a RETRY button while this is ahead
	Toast:FireAllClients(("RETRY INSPECTION? Rebuild the %d fallen piece%s and get inspected again instead of paying for them (STORE, %d s)"):format(
		pieces, if pieces == 1 then "" else "s", RETRY_WINDOW))
	local alive = true
	while not o.taken and workspace:GetServerTimeNow() < o.untilT do
		if token ~= my or S.JobService.Current() ~= cur then
			alive = false
			break
		end
		task.wait(0.25)
	end
	offer = nil
	workspace:SetAttribute("RetryOfferUntil", nil)
	return alive and o.taken ~= nil
end

-- The retry itself: every fallen piece becomes a rebuild task for its trade. Rebuilt pieces go back up and leave
-- `down`; what isn't rebuilt in time stays down. Returns false when the job was torn down meanwhile.
local function rebuild(cur: any, my: number, down: { Down }, round: number): boolean
	S.JobService.SetPhaseNote(cur, "Rebuild the fallen work for re-inspection")
	local open = true
	local pending = 0
	local ids: { string } = {}
	local rebuilt: { [Down]: boolean } = {}
	for _, d in down do
		local slot = d.slot
		local home: CFrame = slot.homeCF or slot.part.CFrame
		local id = ("redo%d_%s"):format(round, slot.def.Id)
		local added = S.JobService.AddSlot({
			Id = id,
			Kind = "Timing",
			Role = slot.def.Role,
			Phase = "Rework",
			Label = "Rebuild: " .. slot.def.Label,
			Size = Vector3.new(2.2, 2.2, 2.2),
			Done = { Color = Color3.fromRGB(80, 200, 90), Material = "Neon", Transparency = 1 },
			Collide = false,
			Reach = 12,
		}, CFrame.new(home.Position.X, 1.2, home.Position.Z), nil, function(worker: Instance)
			if not open then
				return
			end
			restore(slot)
			rebuilt[d] = true
			pending -= 1
			-- the piece now counts as well as it was rebuilt, and whoever rebuilt it answers for it
			local rec = S.QualityService.RecordOf(id)
			S.QualityService.Replace(slot.def.Id, if rec then rec.accuracy else 0.9)
			rebuiltBy[slot.def.Id] = worker
		end)
		if added then
			pending += 1
			table.insert(ids, id)
		end
	end
	Toast:FireAllClients(("Rebuild the fallen work (%d task%s, green markers): %d:%02d until the inspector walks again"):format(
		pending, if pending == 1 then "" else "s", RETRY_SECONDS // 60, RETRY_SECONDS % 60))
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < RETRY_SECONDS do
		if token ~= my or S.JobService.Current() ~= cur then
			return false
		end
		task.wait(0.5)
	end
	open = false
	for _, id in ids do
		S.JobService.DropSlot(id) -- rebuild tasks nobody finished close without credit
	end
	for i = #down, 1, -1 do
		if rebuilt[down[i]] then
			table.remove(down, i)
		end
	end
	S.JobService.SetPhaseNote(cur, nil)
	return token == my and S.JobService.Current() == cur
end

-- Runs the walk (and any retries); calls onDone(damageByPlayer, collapsedCount) once (not called if the job is
-- torn down first).
function Inspection.Run(cur: any, onDone: ({ [Player]: number }, number) -> ())
	token += 1
	local my = token
	table.clear(rebuiltBy)
	task.spawn(function()
		local perPiece = math.floor(cur.cfg.BasePay * DAMAGE_SHARE + 0.5)
		local down: { Down } = {} -- every piece on the ground right now
		local round = 0
		while true do
			local fell = inspect(cur, my, round > 0)
			if not fell then
				return
			end
			for _, d in fell do
				table.insert(down, d)
			end
			if #down == 0 then
				Toast:FireAllClients("INSPECTION PASSED! Solid work, crew.")
			else
				Toast:FireAllClients(("Inspection done: %d piece%s collapsed."):format(#down, if #down == 1 then "" else "s"))
			end
			task.wait(1.5)
			if token ~= my or S.JobService.Current() ~= cur then
				return
			end
			if #down == 0 or round >= MAX_RETRIES or not waitForRetry(cur, my, #down) then
				break
			end
			round += 1
			if not rebuild(cur, my, down, round) then
				return
			end
		end
		if token ~= my or S.JobService.Current() ~= cur then
			return
		end
		-- whoever built the weak pieces still on the ground pays for them
		local damage: { [Player]: number } = {}
		for _, d in down do
			local who = d.charge
			if who and who.Parent == Players then
				damage[who] = (damage[who] or 0) + perPiece
			end
		end
		onDone(damage, #down)
	end)
end

function Inspection.Start()
	Toast = Net.Event("Toast")
	workspace:SetAttribute("RetryOfferUntil", nil)
	S.JobService.Cleared.Event:Connect(function()
		token += 1
		offer = nil
		workspace:SetAttribute("RetryOfferUntil", nil)
		if inspector then
			inspector:Destroy()
			inspector = nil
		end
	end)
end

return Inspection
