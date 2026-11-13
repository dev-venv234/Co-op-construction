--!strict
-- Town traffic (owner request 2026-11-12): civilian cars driving loops on the town roads, on the right-hand lane.
-- Purely cosmetic and local to each player (no network, no collisions): cars come from ReplicatedStorage.TownCars,
-- follow routes built from Shared/Config/TownLayout, turn smoothly at corners, and slow down and stop for whatever
-- is in front of them (players, crew trucks and machines, townspeople, other cars). Headlights at night. How many
-- cars depends on SETTINGS > Graphics (Low 5, Medium 9, High 13); far-away cars aren't drawn.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local TownLayout = require(ReplicatedStorage.Shared.Config.TownLayout)
local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Settings = require(script.Parent.SettingsController)

local Traffic = {}

local LANE = 7 -- lane center, studs right of the road's center line
local CRUISE = 26
local LOOK = 18 -- how far ahead a car checks for something in its way
local DRAW_DISTANCE = 700
local COUNT = { Low = 5, Medium = 9, High = 13 }

type Route = { pts: { Vector3 }, cum: { number }, length: number }
type Car = { model: Model, root: BasePart, route: Route, dist: number, speed: number, waited: number, lights: { Instance }, sound: Sound? }

local routes: { Route } = {}
local cars: { Car } = {}
local folder: Folder
local rng = Random.new(20261112)

local function road(name: string): any
	for _, r in TownLayout.Roads do
		if r.Name == name then
			return r
		end
	end
	return nil
end

-- A point on a road's center line: along = position along the road's axis.
local function onRoad(name: string, along: number): Vector3
	local r = road(name)
	if r.Axis == "X" then
		return Vector3.new(along, 0, r.At)
	end
	return Vector3.new(r.At, 0, along)
end

-- Turns a center-line polyline into the right-hand lane: each point is pushed right of its incoming and outgoing
-- directions (so at a 90-degree corner it lands where the two offset lanes meet). closed = loop back to the start.
local function lanePath(center: { Vector3 }, closed: boolean): Route
	local n = #center
	local pts = {}
	local function right(d: Vector3): Vector3
		return Vector3.new(-d.Z, 0, d.X)
	end
	for i = 1, n do
		local prev = center[if i == 1 then (if closed then n else 1) else i - 1]
		local nxt = center[if i == n then (if closed then 1 else n) else i + 1]
		local dIn = if (center[i] - prev).Magnitude > 0.1 then (center[i] - prev).Unit else nil
		local dOut = if (nxt - center[i]).Magnitude > 0.1 then (nxt - center[i]).Unit else nil
		local off = Vector3.zero
		if dIn then
			off += right(dIn) * LANE
		end
		if dOut and (not dIn or math.abs(dIn:Dot(dOut)) < 0.5) then
			off += right(dOut) * LANE
		end
		if not dIn and dOut then
			off = right(dOut) * LANE
		end
		table.insert(pts, center[i] + off)
	end
	if closed then
		table.insert(pts, pts[1])
	end
	local cum = { 0 }
	for i = 2, #pts do
		cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	return { pts = pts, cum = cum, length = cum[#cum] }
end

-- Out-and-back along a road: down the right lane, a U-turn, back up the other lane. The far end appears twice (arrive
-- in one lane, leave in the other) and so does the start (the loop closes on it), so both U-turns are short hops.
local function outAndBack(center: { Vector3 }): Route
	local full = table.clone(center)
	for i = #center, 1, -1 do
		table.insert(full, center[i])
	end
	return lanePath(full, true)
end

local function buildRoutes()
	local A = onRoad("Main St", 0) -- Main St / Oak Ave
	local B = onRoad("Main St", -1000) -- Main St / Pine Rd
	local Cc = onRoad("Ridge Rd", -1000) -- Pine Rd / Ridge Rd
	local D = onRoad("Ridge Rd", 0) -- Ridge Rd / Oak Ave
	routes = {
		lanePath({ A, B, Cc, D }, true), -- the town loop one way
		lanePath({ D, Cc, B, A }, true), -- and the other way
		outAndBack({ onRoad("Main St", -60), onRoad("Main St", 1080) }), -- out east past Site 1
		outAndBack({ onRoad("Ridge Rd", 60), onRoad("Ridge Rd", 1020) }), -- out east past Site 3
		outAndBack({ onRoad("Oak Ave", -1460), onRoad("Oak Ave", -2200), onRoad("Hilltop Dr", -880) }), -- south to Site 4
	}
end

local function sample(route: Route, dist: number): Vector3
	local d = dist % route.length
	local cum = route.cum
	local lo, hi = 1, #cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= d then
			lo = mid
		else
			hi = mid
		end
	end
	local seg = cum[hi] - cum[lo]
	local a = if seg > 0 then (d - cum[lo]) / seg else 0
	return route.pts[lo]:Lerp(route.pts[hi], a)
end

---------------------------------------------------------------------------------------------------------------

local function spawnCar(template: Model, route: Route, dist: number): Car?
	local m = template:Clone()
	local root = m.PrimaryPart
	if not root then
		return nil
	end
	-- one anchored root moves; everything else rides on welds
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Anchored = d == root
			d.CastShadow = d == root or d:IsA("MeshPart")
		end
	end
	local lights = {}
	for _, d in m:GetDescendants() do
		if d:IsA("SpotLight") or (d:IsA("BasePart") and d.Name == "Headlight") then
			table.insert(lights, d)
		end
	end
	local snd: Sound? = nil
	local effects = SoundService:FindFirstChild("Effects")
	if Sounds.EngineTruck then
		local s = Instance.new("Sound")
		s.SoundId = Sounds.EngineTruck.Id
		s.Looped = true
		s.Volume = 0.18
		s.PlaybackSpeed = rng:NextNumber(1.05, 1.25)
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = 70
		if effects and effects:IsA("SoundGroup") then
			s.SoundGroup = effects
		end
		s.Parent = root
		snd = s
	end
	m.Parent = folder
	if snd then
		snd:Play()
	end
	return { model = m, root = root, route = route, dist = dist, speed = CRUISE, waited = 0, lights = lights, sound = snd }
end

local function clearCars()
	for _, c in cars do
		c.model:Destroy()
	end
	table.clear(cars)
end

local function populate()
	clearCars()
	local templates = {}
	local store = ReplicatedStorage:FindFirstChild("TownCars")
	if store then
		for _, t in store:GetChildren() do
			if t:IsA("Model") and t.PrimaryPart then
				table.insert(templates, t)
			end
		end
	end
	if #templates == 0 or #routes == 0 then
		return
	end
	local total = COUNT[Settings.Quality()] or 9
	-- spread the cars over the routes (longer routes get more), evenly spaced on each, all starting in sync with
	-- the server clock so every player sees roughly the same traffic
	local per = {}
	local sum = 0
	for _, r in routes do
		sum += r.length
	end
	local given = 0
	for i, r in routes do
		per[i] = math.max(1, math.floor(total * r.length / sum + 0.5))
		given += per[i]
	end
	while given > total do
		local i = rng:NextInteger(1, #routes)
		if per[i] > 1 then
			per[i] -= 1
			given -= 1
		end
	end
	local t = workspace:GetServerTimeNow()
	local k = 0
	for i, r in routes do
		for j = 1, per[i] do
			k += 1
			local start = (t * CRUISE + r.length * (j - 1) / per[i]) % r.length
			local car = spawnCar(templates[(k - 1) % #templates + 1], r, start)
			if car then
				table.insert(cars, car)
			end
		end
	end
end

-- People and machines a car has to stop for (rescanned 5 times a second; cars themselves are checked every frame).
-- Only looks where they can be: players, townspeople, bots, and the trucks / excavator inside a job site.
local function obstacles(): { Vector3 }
	local out = {}
	for _, p in Players:GetPlayers() do
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			table.insert(out, r.Position)
		end
	end
	for _, name in { "Townsfolk", "CrewBots" } do
		local f = workspace:FindFirstChild(name)
		if f then
			for _, m in f:GetChildren() do
				local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
				if r then
					table.insert(out, r.Position)
				end
			end
		end
	end
	for _, site in workspace:GetChildren() do
		if string.sub(site.Name, 1, 8) == "JobSite_" then
			for _, name in { "CrewTruck", "Excavator" } do
				local m = site:FindFirstChild(name)
				if m and m:IsA("Model") and m.PrimaryPart then
					table.insert(out, m.PrimaryPart.Position)
				end
			end
		end
	end
	return out
end

local lastScan = 0
local cachedFixed: { Vector3 } = {}

local function update(dt: number)
	local now = os.clock()
	if now - lastScan > 0.2 then
		lastScan = now
		cachedFixed = obstacles()
	end
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local night = Lighting.ClockTime < 6.4 or Lighting.ClockTime > 18.6
	for _, c in cars do
		local pos = sample(c.route, c.dist)
		local ahead = sample(c.route, c.dist + 6)
		local behind = sample(c.route, c.dist - 6)
		local dir = ahead - behind
		local look = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
		-- blocked? anything inside a lane-wide box in front of the car
		local blocked = false
		local right = Vector3.new(-look.Z, 0, look.X)
		local function check(p: Vector3)
			local rel = p - pos
			local fwd = rel:Dot(look)
			if fwd > 4 and fwd < LOOK and math.abs(rel:Dot(right)) < 4.5 and math.abs(rel.Y) < 12 then
				blocked = true
			end
		end
		for _, p in cachedFixed do
			check(p)
		end
		for _, other in cars do
			if other ~= c then
				check(sample(other.route, other.dist))
			end
		end
		-- a car stuck behind another car for a while (two cars meeting at a crossing) goes anyway
		if blocked then
			c.waited += dt
			if c.waited > 4 then
				blocked = false
				if c.waited > 6 then
					c.waited = 0
				end
			end
		else
			c.waited = 0
		end
		local target = if blocked then 0 else CRUISE
		c.speed += (target - c.speed) * math.min(1, dt * (if blocked then 4 else 1.2))
		c.dist += c.speed * dt
		local far = (pos - camPos).Magnitude > DRAW_DISTANCE
		if far then
			if c.model.Parent then
				c.model.Parent = nil
			end
		else
			if not c.model.Parent then
				c.model.Parent = folder
			end
			c.root.CFrame = CFrame.lookAt(pos, pos + look)
			for _, l in c.lights do
				if l:IsA("SpotLight") then
					l.Enabled = night
				elseif l:IsA("BasePart") then
					l.Material = if night then Enum.Material.Neon else Enum.Material.Glass
				end
			end
			if c.sound then
				c.sound.PlaybackSpeed = 0.9 + 0.4 * math.clamp(c.speed / CRUISE, 0, 1)
			end
		end
	end
end

function Traffic.Start()
	folder = Instance.new("Folder")
	folder.Name = "Traffic_Local"
	folder.Parent = workspace
	buildRoutes()
	task.delay(3, populate) -- after SoundController made its groups
	Settings.Changed.Event:Connect(function(key)
		if key == "Quality" or key == nil then
			populate()
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Traffic
