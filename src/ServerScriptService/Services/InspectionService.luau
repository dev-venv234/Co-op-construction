--!strict
-- Final inspection (CLAUDE.md: "inspector walks the house; mistakes cost pay; skipped steps cause partial collapse").
-- When the Foreman calls the inspection, an inspector NPC walks the finished building. At each piece of weak work
-- (task accuracy under WEAK, worst first, machine tasks and paperwork excluded) he stops, and that piece collapses
-- (unanchored, real physics), taking down the finished pieces that were built on it. Each collapsed piece costs the
-- player who built it DAMAGE_SHARE of base pay ("whoever causes damage gets no pay for it"); bot work costs nobody.
-- Everything is decided on the server from server-side records.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Inspection = {}

local WEAK = 0.75
local MAX_WEAK = 5
local MAX_FALL = 8
local DAMAGE_SHARE = 0.06
local WALK_SPEED = 11

local S: any
local Toast: RemoteEvent
local inspector: Model? = nil
local token = 0

function Inspection.Init(services)
	S = services
end

local function isRework(id: string): boolean
	return string.sub(id, 1, 8) == "restack_" or string.sub(id, 1, 4) == "fix_" or string.sub(id, 1, 5) == "load_"
		or string.sub(id, -7) == "_mishap"
end

-- Only built pieces can fall: not checks and switches (level check, power on) or wiring (Connect).
local NOT_STRUCTURAL = { level = true, power = true }
local function structural(def: any): boolean
	return not NOT_STRUCTURAL[def.Id] and def.Kind ~= "Connect" and def.Kind ~= "Inspect" and def.Kind ~= "Deliver"
		and not def.Equipment
end

-- Weak work only counts when a player built it: bots are the crew's stand-ins, and their misses already
-- lower the grade, so their work never collapses.
local function builtByPlayer(slotId: string): boolean
	local rec = S.QualityService.RecordOf(slotId)
	local who = rec and rec.player
	return typeof(who) == "Instance" and (who :: Instance):IsA("Player")
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

-- Drops a finished slot part with physics.
local function collapse(slot: any)
	local p = slot.part
	if not p or not p.Parent then
		return
	end
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

-- Runs the walk; calls onDone(damageByPlayer, collapsedCount) once (not called if the job is torn down first).
function Inspection.Run(cur: any, onDone: ({ [Player]: number }, number) -> ())
	token += 1
	local my = token
	task.spawn(function()
		local damage: { [Player]: number } = {}
		local fallen = 0
		local perPiece = math.floor(cur.cfg.BasePay * DAMAGE_SHARE + 0.5)

		-- Weak work, worst first
		local weak = {}
		for _, r in S.QualityService.LowestFor(WEAK, 40) do
			local slot = cur.slots[r.slotId]
			if slot and slot.done and not isRework(r.slotId) and structural(slot.def) and builtByPlayer(r.slotId) then
				table.insert(weak, slot)
				if #weak >= MAX_WEAK then
					break
				end
			end
		end

		local spawnCF = S.JobService.SiteSpawn() or cur.originCF
		local body = S.BotService.MakeBody("Inspector", Color3.fromRGB(240, 240, 235), Color3.fromRGB(250, 250, 250), spawnCF)
		if body then
			local hum = body:FindFirstChildOfClass("Humanoid") :: Humanoid
			hum.WalkSpeed = WALK_SPEED
			body:SetAttribute("Inspector", true)
			body.Parent = workspace
			inspector = body
		end
		Toast:FireAllClients("FINAL INSPECTION: the inspector is walking the house...")
		Net.Cue("Whistle", spawnCF.Position)

		-- Route: the four corners of the building, with a stop at each weak piece on the way.
		local o = cur.originCF
		-- Footprint of the building = extent of its finished slots (in the blueprint's own frame).
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, s in cur.slots do
			if s.done and s.def.Kind ~= "Deliver" and s.def.Kind ~= "Inspect" then
				local l = o:PointToObjectSpace(s.part.Position)
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
				return
			end
			if body then
				walk(body, stop.pos, 8)
			end
			local slot = stop.slot
			if slot and not slot.part:GetAttribute("Collapsed") then
				task.wait(1)
				local falling = { slot }
				dependents(cur, slot.def.Id, falling, { [slot.def.Id] = true })
				for _, s in falling do
					if not s.part:GetAttribute("Collapsed") and fallen < MAX_FALL then
						collapse(s)
						fallen += 1
					end
				end
				local rec = S.QualityService.RecordOf(slot.def.Id)
				local who = rec and rec.player
				local text = ("FAILED: %s collapsed"):format(slot.def.Label)
				if typeof(who) == "Instance" and who:IsA("Player") and who.Parent == Players then
					damage[who] = (damage[who] or 0) + perPiece
					text ..= (" - $%d off %s's pay"):format(perPiece, who.Name)
				elseif typeof(who) == "Instance" then
					text ..= " (bot work)"
				end
				Toast:FireAllClients(text)
				task.wait(1.2)
			end
		end

		if fallen == 0 then
			Toast:FireAllClients("INSPECTION PASSED! Solid work, crew.")
		else
			Toast:FireAllClients(("Inspection done: %d piece%s collapsed."):format(fallen, if fallen == 1 then "" else "s"))
		end
		task.wait(1.5)
		if token ~= my or S.JobService.Current() ~= cur then
			return
		end
		onDone(damage, fallen)
	end)
end

function Inspection.Start()
	Toast = Net.Event("Toast")
	S.JobService.Cleared.Event:Connect(function()
		token += 1
		if inspector then
			inspector:Destroy()
			inspector = nil
		end
	end)
end

return Inspection
