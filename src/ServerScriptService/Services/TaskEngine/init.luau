--!strict
-- One task engine for every trade (and later, bots): Carry, Place, Timing, Connect.
-- Holds each player's active minigame session and validates every remote that drives it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Guard = require(script.Guard)
local Carry = require(script.Carry)
local TimingTask = require(script.Timing)
local ConnectTask = require(script.Connect)

local TaskEngine = {}
TaskEngine.Guard = Guard
TaskEngine.Carry = Carry
-- Bots (BotService) score their Timing and Connect work with these same modules.
TaskEngine.TimingTask = TimingTask
TaskEngine.ConnectTask = ConnectTask

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

function TaskEngine.BeginTiming(p: Player, anchor: BasePart, label: string, onDone: (number) -> (), onCancel: () -> ()): boolean
	if sessions[p] then
		return false
	end
	local round = TimingTask.NewRound(timingWidth(p))
	sessions[p] = { kind = "Timing", anchor = anchor, label = label, onDone = onDone, onCancel = onCancel, data = { round = round, cap = 1 } }
	TaskBegin:FireClient(p, TimingTask.Payload(round, label, false))
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
		finish(p, true, math.min(acc, s.data.cap), nil)
	else
		s.data.cap = math.max(0.4, s.data.cap - 0.15)
		s.data.round = TimingTask.NewRound(timingWidth(p))
		TaskBegin:FireClient(p, TimingTask.Payload(s.data.round, s.label, true))
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
		finish(p, true, ConnectTask.Accuracy(os.clock() - s.data.started), nil)
	else
		Toast:FireClient(p, "Not connected yet")
	end
end

function TaskEngine.Start()
	TaskBegin = Net.Event("TaskBegin")
	TaskEnd = Net.Event("TaskEnd")
	Toast = Net.Event("Toast")

	Net.Event("TimingTap").OnServerEvent:Connect(onTap)
	Net.Event("ConnectSubmit").OnServerEvent:Connect(onConnectSubmit)
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
