--!strict
-- Server-trusted positions (2026-11-16, security audit H1). Players own their character's physics, so the server
-- can't take a character's position at face value: a modified client can put it anywhere. The reach checks that
-- decide work (JobService.near: slots, piles, truck loading, site buttons) ask this service instead.
--
-- For each player the server keeps a "trusted spot". It follows the character, but it can only move as fast as
-- that character may really walk: the server's own WalkSpeed (so carrying something heavy slows it too) times
-- SLACK, plus a short allowance that builds up while standing or lagging (BURST_SECONDS). For a normal player the
-- trusted spot is simply where they stand. Someone who teleports gains nothing: their trusted spot gets there when
-- a walker would have, and until then prompts over there don't work.
--  * Riding: the spot follows a seated player, as long as they reached the seat honestly (spot within RIDE_SNAP).
--  * When the server itself moves a character (the crew shuttle, back to the RV) it calls Snap with the new spot.
--    A new character starts trusted where the server spawned it.
-- Nobody is pulled back or punished: a false alarm (a shove from a truck, a long lag spike) only means a prompt
-- works a moment later.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MoveGuard = {}

local SLACK = 1.3 -- trusted speed = server walk speed x this
local BURST_SECONDS = 2.5 -- allowance that can build up, in seconds of walking
local MIN_SPEED = 8 -- studs/s floor (a frozen or very slow character still catches up)
local RIDE_SNAP = 18 -- sitting down counts when the trusted spot is this close
local HOLD_SECONDS = 1.5 -- after a server teleport: how long to wait for the client to show up there

type Track = { char: Model?, pos: Vector3, budget: number, riding: boolean, hold: number? }
local tracks: { [Player]: Track } = {}

local function parts(p: Player): (BasePart?, Humanoid?)
	local c = p.Character
	if not c then
		return nil, nil
	end
	local root = c:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil, c:FindFirstChildOfClass("Humanoid")
end

-- The player's trusted position, or nil when they have no living character.
function MoveGuard.Position(p: Player): Vector3?
	local t = tracks[p]
	if not t or t.char == nil or t.char ~= p.Character then
		return nil
	end
	return t.pos
end

-- The server moved this character itself: trust the new spot (`at`, or where the character is now).
function MoveGuard.Snap(p: Player, at: Vector3?)
	local t = tracks[p]
	local root = parts(p)
	if not t or not root then
		return
	end
	t.char = p.Character
	t.pos = at or root.Position
	t.budget = 0
	t.riding = false
	t.hold = os.clock() + HOLD_SECONDS -- the client takes a moment to report the new position
end

local function step(dt: number)
	local now = os.clock()
	for p, t in tracks do
		local root, hum = parts(p)
		if not root or not hum or hum.Health <= 0 then
			t.char = nil
			continue
		end
		local actual = root.Position
		if t.char ~= p.Character then
			-- a new character: it is where the server just spawned it
			t.char = p.Character
			t.pos = actual
			t.budget = 0
			t.riding = false
			t.hold = nil
			continue
		end
		if t.hold then
			if (actual - t.pos).Magnitude > 12 and now < t.hold then
				continue
			end
			t.hold = nil
		end
		local speed = math.max(hum.WalkSpeed, MIN_SPEED) * SLACK
		local cap = speed * BURST_SECONDS
		if hum.SeatPart then
			if not t.riding and (actual - t.pos).Magnitude <= RIDE_SNAP then
				t.riding = true
			end
		else
			t.riding = false
		end
		if t.riding then
			t.pos = actual
			t.budget = cap
			continue
		end
		t.budget = math.min(t.budget + speed * dt, cap)
		local dx, dz = actual.X - t.pos.X, actual.Z - t.pos.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= t.budget then
			t.budget -= d
			t.pos = actual
		else
			-- too far for the time that has passed: the trusted spot walks toward the character
			local k = t.budget / d
			t.pos = Vector3.new(t.pos.X + dx * k, actual.Y, t.pos.Z + dz * k)
			t.budget = 0
		end
	end
end

function MoveGuard.Start()
	local function add(p: Player)
		tracks[p] = { char = nil, pos = Vector3.zero, budget = 0, riding = false }
	end
	Players.PlayerAdded:Connect(add)
	for _, p in Players:GetPlayers() do
		add(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		tracks[p] = nil
	end)
	RunService.Heartbeat:Connect(step)

	-- Studio-only test hook (server side): Invoke(playerName) -> { trusted, actual, budget }.
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "DevMoveGuard"
		hook.OnInvoke = function(playerName: string)
			local pl = Players:FindFirstChild(playerName)
			local t = if pl and pl:IsA("Player") then tracks[pl] else nil
			local root = if pl and pl:IsA("Player") then parts(pl) else nil
			if not t or not root then
				return nil
			end
			return { trusted = MoveGuard.Position(pl :: Player), actual = root.Position, budget = t.budget, riding = t.riding }
		end
		hook.Parent = ServerStorage
	end
end

return MoveGuard
