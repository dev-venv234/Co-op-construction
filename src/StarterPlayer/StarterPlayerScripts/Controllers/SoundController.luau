--!strict
-- All game audio, played on this client so the player's own volumes apply (SettingsController: Master, Music,
-- Effects, Ambient). Sound ids live in Shared/Config/Sounds.
--  * Machines: a looping engine on every truck, excavator and crane seat while someone is in it; pitch and volume
--    follow how fast it's moving (the crane: how fast its hook moves).
--  * Work: the server sends cues (Sfx remote: name + where) for placed pieces, nails, wiring, loading, the crane
--    dropping its load, the inspector's whistle and collapses. Missed taps click, payouts ring the till, level-ups chime.
--  * World: birds by day, crickets at night, rain + thunder during a rain delay, a music playlist.
--  * UI: a click on every button press.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Settings = require(script.Parent.SettingsController)

local SoundController = {}

local player = Players.LocalPlayer
local groups: { [string]: SoundGroup } = {}
local rng = Random.new()

local function applyVolumes()
	local master = Settings.Get("Master") :: number
	for name, g in groups do
		local v = Settings.Get(name)
		g.Volume = master * (if typeof(v) == "number" then v else 1)
	end
end

local function make(def: any, parent: Instance, name: string): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.Id
	s.Volume = def.Volume
	s.Looped = def.Loop == true
	s.SoundGroup = groups[def.Group] or groups.Effects
	s.Parent = parent
	return s
end

-- One-shot in the world at `pos` (heard from up to ~150 studs), or flat if pos is nil.
local function play(name: string, pos: Vector3?)
	local def = Sounds[name]
	if typeof(def) ~= "table" or not def.Id then
		return
	end
	local parent: Instance = SoundService
	local holder: Attachment? = nil
	if pos then
		holder = Instance.new("Attachment")
		holder.WorldPosition = pos
		holder.Parent = workspace.Terrain
		parent = holder :: Attachment
	end
	local s = make(def, parent, name)
	if holder then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 12
		s.RollOffMaxDistance = 150
	end
	s.PlaybackSpeed = rng:NextNumber(0.94, 1.06) -- a little variety
	local root: Instance = if holder then holder else s
	s.Ended:Connect(function()
		root:Destroy()
	end)
	s:Play()
	task.delay(20, function() -- safety net if Ended never fires
		if root.Parent then
			root:Destroy()
		end
	end)
end
SoundController.Play = play

---------------------------------------------------------------------------------------------------------------
-- Machines
---------------------------------------------------------------------------------------------------------------

type Engine = { seat: BasePart, sound: Sound, last: Vector3, speed: number, top: number, probe: BasePart }
local engines: { [BasePart]: Engine } = {}

local function trackSeat(seat: BasePart)
	if engines[seat] then
		return
	end
	local heavy = seat.Name ~= "DriverSeat"
	local def = if heavy then Sounds.EngineHeavy else Sounds.EngineTruck
	local s = make(def, seat, "Engine")
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = 120
	-- the crane doesn't drive: listen to its hook instead
	local probe: BasePart = seat
	if seat.Name == "CraneSeat" then
		local hook = seat.Parent and seat.Parent:FindFirstChild("HookBlock")
		if hook and hook:IsA("BasePart") then
			probe = hook
		end
	end
	engines[seat] = {
		seat = seat,
		sound = s,
		last = probe.Position,
		speed = 0,
		top = if seat.Name == "DriverSeat" then 36 elseif seat.Name == "CraneSeat" then 12 else 11,
		probe = probe,
	}
	seat.Destroying:Connect(function()
		engines[seat] = nil
	end)
end

local function maybeSeat(d: Instance)
	if (d:IsA("VehicleSeat") or d:IsA("Seat")) and (d.Name == "DriverSeat" or d.Name == "OperatorSeat" or d.Name == "CraneSeat") then
		trackSeat(d :: BasePart)
	end
end

local function updateEngines(dt: number)
	for seat, e in engines do
		if not seat.Parent then
			engines[seat] = nil
			continue
		end
		local occupied = (seat :: any).Occupant ~= nil
		local pos = e.probe.Position
		local v = (pos - e.last).Magnitude / math.max(dt, 1 / 240)
		e.last = pos
		e.speed += (math.min(v, e.top * 1.2) - e.speed) * math.min(1, dt * 4)
		if occupied then
			local k = math.clamp(e.speed / e.top, 0, 1)
			if not e.sound.Playing then
				e.sound:Play()
			end
			e.sound.PlaybackSpeed = 0.85 + 0.55 * k
			local def = if seat.Name == "DriverSeat" then Sounds.EngineTruck else Sounds.EngineHeavy
			e.sound.Volume = def.Volume * (0.65 + 0.35 * k)
		elseif e.sound.Playing then
			e.sound:Stop()
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------------------------------------------

local birds: Sound
local crickets: Sound
local rain: Sound
local music: Sound
local track = 0
local nextThunder = 0

local function nextTrack()
	track = track % #Sounds.MusicTracks + 1
	music.SoundId = Sounds.MusicTracks[track]
	music:Play()
end

local function updateWorld(dt: number)
	local t = Lighting.ClockTime
	local day = t >= 6 and t < 19
	local rainUntil = Players.LocalPlayer:GetAttribute("RainUntil")
	local raining = typeof(rainUntil) == "number" and rainUntil > workspace:GetServerTimeNow()
	local function fade(s: Sound, target: number)
		s.Volume += (target - s.Volume) * math.min(1, dt * 1.5)
		if s.Volume > 0.01 and not s.Playing then
			s:Play()
		elseif s.Volume <= 0.01 and s.Playing then
			s:Stop()
		end
	end
	fade(birds, if day and not raining then Sounds.Birds.Volume else 0)
	fade(crickets, if not day and not raining then Sounds.Crickets.Volume else 0)
	fade(rain, if raining then Sounds.Rain.Volume else 0)
	if raining and os.clock() >= nextThunder then
		nextThunder = os.clock() + rng:NextNumber(12, 26)
		play("Thunder", nil)
	end
end

---------------------------------------------------------------------------------------------------------------

function SoundController.Start()
	for _, name in { "Music", "Effects", "Ambient" } do
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
		groups[name] = g
	end
	applyVolumes()
	Settings.Changed.Event:Connect(applyVolumes)

	birds = make(Sounds.Birds, SoundService, "Birds")
	crickets = make(Sounds.Crickets, SoundService, "Crickets")
	rain = make(Sounds.Rain, SoundService, "Rain")
	for _, s in { birds, crickets, rain } do
		s.Volume = 0
	end
	music = make({ Id = Sounds.MusicTracks[1], Volume = Sounds.MusicVolume, Group = "Music" }, SoundService, "Music")
	music.Ended:Connect(nextTrack)
	task.delay(2, nextTrack)

	-- machines
	for _, d in workspace:GetDescendants() do
		maybeSeat(d)
	end
	workspace.DescendantAdded:Connect(maybeSeat)

	RunService.Heartbeat:Connect(function(dt)
		updateEngines(dt)
		updateWorld(dt)
	end)

	-- cues from the server
	Net.Event("Sfx").OnClientEvent:Connect(function(name: unknown, pos: unknown)
		if typeof(name) == "string" then
			play(name, if typeof(pos) == "Vector3" then pos else nil)
		end
	end)
	Net.Event("TaskBegin").OnClientEvent:Connect(function(d)
		if typeof(d) == "table" and d.missed then
			play("Miss", nil)
		end
	end)
	Net.Event("Payout").OnClientEvent:Connect(function(d)
		if typeof(d) == "table" and d.success and (tonumber(d.pay) or 0) > 0 then
			play("Cash", nil)
		end
	end)
	local lastPing = 0
	Net.Event("Toast").OnClientEvent:Connect(function()
		if os.clock() - lastPing > 0.4 then
			lastPing = os.clock()
			play("Ping", nil)
		end
	end)
	-- level-ups (Level_<Trade> attributes going up)
	local levels: { [string]: number } = {}
	for k, v in player:GetAttributes() do
		if string.sub(k, 1, 6) == "Level_" and typeof(v) == "number" then
			levels[k] = v
		end
	end
	player.AttributeChanged:Connect(function(k)
		if string.sub(k, 1, 6) == "Level_" then
			local v = player:GetAttribute(k)
			if typeof(v) == "number" then
				if levels[k] and v > levels[k] then
					play("Chime", nil)
				end
				levels[k] = v
			end
		end
	end)

	-- a click on every button press (not the hold-down drive pedals)
	local gui = player:WaitForChild("PlayerGui")
	local function hookButton(b: Instance)
		if b:IsA("GuiButton") and b:GetAttribute("Key") == nil then
			b.Activated:Connect(function()
				play("Click", nil)
			end)
		end
	end
	for _, d in gui:GetDescendants() do
		hookButton(d)
	end
	gui.DescendantAdded:Connect(hookButton)
end

return SoundController
