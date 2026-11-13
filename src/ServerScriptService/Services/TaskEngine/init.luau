--!strict
-- One task engine for every trade (bots use it too): Carry, Place, Timing, Connect, and (2026-11-13) Trace (welding:
-- follow the seam) and Gauge (hold to keep the needle in the green: pour, level, charge, voltage). Timing can ask for
-- several hits in a row (nailing). Holds each player's active minigame session and validates every remote that drives
-- it. Tool shop tools make tasks a bit easier through SetBonus (never finish them).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Guard = require(script.Guard)
local Carry = require(script.Carry)
local TimingTask = require(script.Timing)
local ConnectTask = require(script.Connect)
local TraceTask = require(script.Trace)
local GaugeTask = require(script.Gauge)

local TaskEngine = {}
TaskEngine.Guard = Guard
TaskEngine.Carry = Carry
-- Bots (BotService) score their Timing and Connect work with these same modules.
TaskEngine.TimingTask = TimingTask
TaskEngine.ConnectTask = ConnectTask
TaskEngine.TraceTask = TraceTask
TaskEngine.GaugeTask = GaugeTask

type Session = {
	kind: string,
	anchor: BasePart,
	label: string,
	onDone: (number) -> (),
	onCancel: () -> (),
	data: any,
}

local MAX_WANDER = 22 -- studs from the task before it cancels
local sessions: { [Player]: Session } = {}
local TaskBegin: RemoteEvent
local TaskEnd: RemoteEvent
local Toast: RemoteEvent

-- Timing green-zone width hook (e.g. the Awake buff from BuffService). Defaults to 1.
local timingWidth: (Player) -> number = function()
	return 1
end

function TaskEngine.SetTimingWidth(fn: (Player) -> number)
	timingWidth = fn
end

-- Tool bonuses (ToolShopService): (player, what) -> multiplier, what = "timing" | "trace" | "connect" | "gauge:<Style>".
local bonus: (Player, string) -> number = function()
	return 1
end

function TaskEngine.SetBonus(fn: (Player, string) -> number)
	bonus = fn
end

local function finish(p: Player, ok: boolean, accuracy: number, message: string?)
	local s = sessions[p]
	if not s then
		return
	end
	sessions[p] = nil
	if p.Parent then
		TaskEnd:FireClient(p, { ok = ok, accuracy = accuracy, message = message })
	end
	if ok then
		s.onDone(accuracy)
	else
		s.onCancel()
	end
end

function TaskEngine.IsBusy(p: Player): boolean
	return sessions[p] ~= nil
end

function TaskEngine.Cancel(p: Player, reason: string)
	finish(p, false, 0, reason)
end

function TaskEngine.CancelAll(reason: string)
	for p in sessions do
		finish(p, false, 0, reason)
	end
end

local function timingPayload(s: Session, missed: boolean): { [string]: any }
	local d = TimingTask.Payload(s.data.round, s.label, missed)
	d.hit = s.data.done + 1
	d.hits = s.data.hits
	return d
end

-- hits: how many hits in a row it takes (nailing: 3); each hit shrinks the green zone a little.
function TaskEngine.BeginTiming(p: Player, anchor: BasePart, label: string, onDone: (number) -> (), onCancel: () -> (), hits: number?): boolean
	if sessions[p] then
		return false
	end
	local round = TimingTask.NewRound(timingWidth(p) * bonus(p, "timing"))
	local s: Session = { kind = "Timing", anchor = anchor, label = label, onDone = onDone, onCancel = onCancel,
		data = { round = round, cap = 1, hits = math.clamp(hits or 1, 1, 5), done = 0, sum = 0 } }
	sessions[p] = s
	TaskBegin:FireClient(p, timingPayload(s, false))
	return true
end

-- Welding: trace the seam (TaskEngine/Trace).
function TaskEngine.BeginTrace(p: Player, anchor: BasePart, label: string, onDone: (number) -> (), onCancel: () -> ()): boolean
	if sessions[p] then
		return false
	end
	local round = TraceTask.NewRound(bonus(p, "trace"))
	sessions[p] = { kind = "Trace", anchor = anchor, label = label, onDone = onDone, onCancel = onCancel, data = { round = round, cap = 1 } }
	TaskBegin:FireClient(p, TraceTask.Payload(round, label, false))
	return true
end

-- Hold-in-the-green (TaskEngine/Gauge); style = Pour / Level / Charge / Voltage.
function TaskEngine.BeginGauge(p: Player, anchor: BasePart, label: string, style: string, onDone: (number) -> (), onCancel: () -> ()): boolean
	if sessions[p] then
		return false
	end
	local round = GaugeTask.NewRound(style, bonus(p, "gauge:" .. style))
	sessions[p] = { kind = "Gauge", anchor = anchor, label = label, onDone = onDone, onCancel = onCancel,
		data = { round = round, cap = 1, style = style } }
	TaskBegin:FireClient(p, GaugeTask.Payload(round, label, false))
	return true
end

function TaskEngine.BeginConnect(p: Player, anchor: BasePart, label: string, onDone: (number) -> (), onCancel: () -> ()): boolean
	if sessions[p] then
		return false
	end
	local puzzle = ConnectTask.NewPuzzle()
	sessions[p] = { kind = "Connect", anchor = anchor, label = label, onDone = onDone, onCancel = onCancel, data = { puzzle = puzzle, started = os.clock() } }
	TaskBegin:FireClient(p, ConnectTask.Payload(puzzle, label))
	return true
end

local function onTap(p: Player)
	if not Guard.Allow(p, "TimingTap", 0.2) then
		return
	end
	local s = sessions[p]
	if not s or s.kind ~= "Timing" then
		return
	end
	local hit, acc = TimingTask.Judge(s.data.round, p)
	if hit == nil then
		return
	elseif hit then
		s.data.done += 1
		s.data.sum += math.min(acc, s.data.cap)
		if s.data.done >= s.data.hits then
			finish(p, true, s.data.sum / s.data.hits, nil)
		else
			-- next nail: a slightly smaller green zone
			s.data.round = TimingTask.NewRound(timingWidth(p) * bonus(p, "timing") * 0.85 ^ s.data.done)
			TaskBegin:FireClient(p, timingPayload(s, false))
		end
	else
		s.data.cap = math.max(0.4, s.data.cap - 0.15)
		s.data.round = TimingTask.NewRound(timingWidth(p) * bonus(p, "timing") * 0.85 ^ s.data.done)
		TaskBegin:FireClient(p, timingPayload(s, true))
	end
end

local function onConnectSubmit(p: Player, rots: unknown)
	if not Guard.Allow(p, "ConnectSubmit", 0.3) then
		return
	end
	local s = sessions[p]
	if not s or s.kind ~= "Connect" then
		return
	end
	local g = s.data.puzzle
	local n = g.w * g.h
	if typeof(rots) ~= "table" then
		warn("[TaskEngine] bad ConnectSubmit from", p.Name)
		return
	end
	local count = 0
	for _ in rots :: { [any]: any } do
		count += 1
	end
	local clean: { number } = {}
	for i = 1, n do
		local v = (rots :: { [any]: any })[i]
		if typeof(v) ~= "number" or v ~= math.floor(v) or v < 0 or v > 3 then
			warn("[TaskEngine] bad ConnectSubmit from", p.Name)
			return
		end
		clean[i] = v
	end
	if count ~= n then
		warn("[TaskEngine] bad ConnectSubmit size from", p.Name)
		return
	end
	if ConnectTask.Check(g, clean) then
		finish(p, true, ConnectTask.Accuracy((os.clock() - s.data.started) / bonus(p, "connect")), nil)
	else
		Toast:FireClient(p, "Not connected yet")
	end
end

local function onTraceSubmit(p: Player, samples: unknown)
	if not Guard.Allow(p, "TraceSubmit", 0.4) then
		return
	end
	local s = sessions[p]
	if not s or s.kind ~= "Trace" then
		return
	end
	if typeof(samples) ~= "table" then
		warn("[TaskEngine] bad TraceSubmit from", p.Name)
		return
	end
	local list = samples :: { [any]: any }
	local n = #list
	if n < 18 or n > 900 or n % 3 ~= 0 then
		Toast:FireClient(p, "Trace the whole seam, from START to END")
		return
	end
	local clean: { number } = table.create(n)
	for i = 1, n do
		local v = list[i]
		if typeof(v) ~= "number" or v ~= v or math.abs(v) == math.huge then
			warn("[TaskEngine] bad TraceSubmit from", p.Name)
			return
		end
		local isTime = i % 3 == 0
		if (isTime and (v < 0 or v > 60)) or (not isTime and (v < -0.1 or v > 1.1)) then
			warn("[TaskEngine] bad TraceSubmit from", p.Name)
			return
		end
		clean[i] = v
	end
	local ok, acc, why = TraceTask.Judge(s.data.round, clean)
	if ok == nil then
		if why then
			Toast:FireClient(p, why)
		end
	elseif ok then
		finish(p, true, math.min(acc, s.data.cap), nil)
	else
		s.data.cap = math.max(0.4, s.data.cap - 0.15)
		s.data.round = TraceTask.NewRound(bonus(p, "trace"))
		TaskBegin:FireClient(p, TraceTask.Payload(s.data.round, s.label, true, why))
	end
end

-- press / release events: never dropped for being quick (a lost "let go" would leave the needle rising), only a
-- per-second budget against spam
local holdBudget: { [Player]: { t: number, n: number } } = {}
local function onGaugeHold(p: Player, held: unknown)
	if typeof(held) ~= "boolean" then
		return
	end
	local nowC = os.clock()
	local b = holdBudget[p]
	if not b or nowC - b.t >= 1 then
		holdBudget[p] = { t = nowC, n = 1 }
	else
		b.n += 1
		if b.n > 30 then
			return
		end
	end
	local s = sessions[p]
	if s and s.kind == "Gauge" then
		GaugeTask.SetHeld(s.data.round, p, held)
	end
end

function TaskEngine.Start()
	TaskBegin = Net.Event("TaskBegin")
	TaskEnd = Net.Event("TaskEnd")
	Toast = Net.Event("Toast")

	Net.Event("TimingTap").OnServerEvent:Connect(onTap)
	Net.Event("ConnectSubmit").OnServerEvent:Connect(onConnectSubmit)
	Net.Event("TraceSubmit").OnServerEvent:Connect(onTraceSubmit)
	Net.Event("GaugeHold").OnServerEvent:Connect(onGaugeHold)
	-- gauges finish (or run out of time) on the server's clock
	task.spawn(function()
		while true do
			task.wait(0.05)
			for p, s in sessions do
				if s.kind == "Gauge" then
					local result, acc = GaugeTask.Check(s.data.round, p)
					if result == "done" then
						finish(p, true, math.min(acc, s.data.cap), nil)
					elseif result == "miss" then
						s.data.cap = math.max(0.4, s.data.cap - 0.15)
						s.data.round = GaugeTask.NewRound(s.data.style, bonus(p, "gauge:" .. s.data.style))
						TaskBegin:FireClient(p, GaugeTask.Payload(s.data.round, s.label, true))
					end
				end
			end
		end
	end)
	Net.Event("CancelTask").OnServerEvent:Connect(function(p)
		if Guard.Allow(p, "CancelTask", 0.3) then
			finish(p, false, 0, "Cancelled")
		end
	end)
	Net.Event("DropItem").OnServerEvent:Connect(function(p)
		if Guard.Allow(p, "DropItem", 0.3) then
			Carry.Drop(p)
		end
	end)

	local function hook(p: Player)
		p.CharacterRemoving:Connect(function()
			finish(p, false, 0, "Task cancelled")
			Carry.Forget(p)
			p:SetAttribute("Carrying", nil)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		holdBudget[p] = nil
		finish(p, false, 0, nil)
		Carry.Forget(p)
	end)

	-- Walk away from a task and it cancels (so nobody holds a slot forever).
	task.spawn(function()
		while true do
			task.wait(0.5)
			for p, s in sessions do
				local c = p.Character
				local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not root or (root.Position - s.anchor.Position).Magnitude > MAX_WANDER then
					finish(p, false, 0, "You walked away from the task")
				end
			end
		end
	end)
end

return TaskEngine
