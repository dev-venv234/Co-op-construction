--!strict
-- EDIT-TIME ONLY. Makes the town feel lived in (owner request 2026-11-12): Workspace.TownLife =
--   Props: benches along Main St and Oak Ave (with a sittable BenchSeat), fire hydrants on the curbs, a mailbox and a
--          trash bin at every house's driveway, bins next to the Main St benches;
--   ParkedCars: a car in each house's driveway, cars at the gas station pumps and in the hardware store lot.
-- Models: ServerStorage.PropModels (bench, hydrant, mailbox, trash bin) and ReplicatedStorage.TownCars (also used
-- by the moving traffic), all AI-generated meshes. Every spot is checked first: anything solid in the way and the
-- piece is skipped (or tries the next candidate), so re-running is safe. Run: require(this).All()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TownLayout = require(ReplicatedStorage.Shared.Config.TownLayout)

local Builder = {}

local HALF_ROAD = TownLayout.RoadWidth / 2 -- 16
local rng = Random.new(1112)

local function road(name: string): any
	for _, r in TownLayout.Roads do
		if r.Name == name then
			return r
		end
	end
	return nil
end

local function lot(id: string): any
	for _, l in TownLayout.Lots do
		if l.Id == id then
			return l
		end
	end
	return nil
end

local life: Folder
local propsFolder: Folder
local carsFolder: Folder

local function ground(x: number, z: number): number
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { life }
	-- start low: the town is flat (y ~ 0) and a high ray lands on canopies and awnings (gas station)
	local hit = workspace:Raycast(Vector3.new(x, 8, z), Vector3.new(0, -40, 0), rp)
	return if hit then hit.Position.Y else 0
end

-- Is the box clear of solid things (terrain and our own pieces don't count)?
local function clear(cf: CFrame, size: Vector3): boolean
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { workspace.Terrain, life }
	op.RespectCanCollide = true
	return #workspace:GetPartBoundsInBox(cf, size, op) == 0
end

-- Places a copy of `template` with its bottom center at (x, ground, z), facing `yaw` (0 = front toward -Z).
local function put(template: Model, x: number, z: number, yaw: number, parent: Instance, name: string?): Model?
	local box, size = template:GetBoundingBox()
	local y = ground(x, z)
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	-- the template's pivot isn't always its bottom (the prop meshes pivot at their center): lift by the difference
	local lift = template:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
	-- check a slightly smaller box, lifted off the ground
	if not clear(cf * CFrame.new(0, size.Y / 2 + 0.3, 0), size * Vector3.new(0.9, 0.85, 0.9)) then
		return nil
	end
	local m = template:Clone()
	if name then
		m.Name = name
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m:PivotTo(cf + Vector3.new(0, lift, 0))
	m.Parent = parent
	return m
end

-- Yaw that turns a model's front (-Z) to face `dir`.
local function yawFor(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function props()
	local P = ServerStorage:FindFirstChild("PropModels")
	if not P then
		warn("[LifeBuilder] no ServerStorage.PropModels")
		return 0
	end
	local n = 0
	local main, oak = road("Main St"), road("Oak Ave")
	local bench, bin, hydrant, mailbox = P:FindFirstChild("Bench"), P:FindFirstChild("TrashBin"), P:FindFirstChild("Hydrant"), P:FindFirstChild("Mailbox")
	local function add(t: Instance?, x: number, z: number, yaw: number): boolean
		if t and t:IsA("Model") and put(t, x, z, yaw, propsFolder) then
			n += 1
			return true
		end
		return false
	end
	local edge = HALF_ROAD + 6.6 -- outer half of the 8-stud sidewalk (walkers use its middle)
	-- benches facing the road, with a bin beside each
	for _, b in {
		{ "X", main, -1, -240 }, { "X", main, -1, -150 }, { "X", main, -1, 150 }, { "X", main, -1, 240 },
		{ "X", main, 1, -200 }, { "X", main, 1, 200 },
		{ "Z", oak, -1, -800 }, { "Z", oak, -1, -1000 }, { "Z", oak, 1, -600 }, { "Z", oak, 1, -1200 },
	} do
		local axis, r, side, along = b[1], b[2], b[3], b[4]
		local x = if axis == "X" then along else r.At + side * edge
		local z = if axis == "X" then r.At + side * edge else along
		local toRoad = if axis == "X" then Vector3.new(0, 0, -side) else Vector3.new(-side, 0, 0)
		if add(bench, x, z, yawFor(toRoad)) then
			local along2 = along + 4.5
			add(bin, if axis == "X" then along2 else x, if axis == "X" then z else along2, yawFor(toRoad))
		end
	end
	-- hydrants on the curb every ~220 studs
	local curb = HALF_ROAD + 1.6
	for x = -880, 1000, 220 do
		add(hydrant, x + 30, main.At - curb, 0)
		add(hydrant, x + 140, main.At + curb, math.pi)
	end
	for z = -520, -2100, -260 do
		add(hydrant, oak.At + curb, z, math.pi / 2)
	end
	-- each house: mailbox and bin by the driveway, on the sidewalk
	for _, l in TownLayout.Lots do
		if l.Kind == "Filler" and string.sub(l.Id, 1, 6) == "House_" then
			local g = l.Gate
			local r = road(g.Road)
			local side = g.Side
			local x = r.At + side * edge
			local toRoad = Vector3.new(-side, 0, 0)
			add(mailbox, x, g.At + g.Width / 2 + 2.5, yawFor(toRoad))
			add(bin, x, g.At + g.Width / 2 + 6, yawFor(toRoad))
		end
	end
	return n
end

local function parked()
	local cars = ReplicatedStorage:FindFirstChild("TownCars")
	if not cars then
		warn("[LifeBuilder] no ReplicatedStorage.TownCars")
		return 0
	end
	local list = {}
	for _, c in cars:GetChildren() do
		if c:IsA("Model") then
			table.insert(list, c)
		end
	end
	local n = 0
	local function car(): Model
		return list[rng:NextInteger(1, #list)]
	end
	-- tries the candidate spots in order until one is clear
	local function park(spots: { { number } }, name: string)
		for _, s in spots do
			if put(car(), s[1], s[2], s[3], carsFolder, name) then
				n += 1
				return
			end
		end
	end
	-- house driveways: just inside the lot, nose toward the street
	for _, l in TownLayout.Lots do
		if l.Kind == "Filler" and string.sub(l.Id, 1, 6) == "House_" then
			local g = l.Gate
			local r = road(g.Road)
			local side = g.Side
			local edgeX = if side < 0 then l.Max.X else l.Min.X -- lot edge on the street side
			local yaw = yawFor(Vector3.new(-side, 0, 0))
			local spots = {}
			for _, inset in { 10, 16, 22 } do
				table.insert(spots, { edgeX + side * inset, g.At, yaw })
			end
			park(spots, "Parked_" .. l.Id)
			local _ = r
		end
	end
	-- gas station: beside the pumps (any part named like a pump), else the front of the lot
	local gas = lot("GasStation")
	local filler = workspace:FindFirstChild("Filler")
	local gasModel = filler and filler:FindFirstChild("GasStation")
	local pumps = {}
	if gasModel then
		for _, d in gasModel:GetDescendants() do
			if d:IsA("BasePart") and string.find(string.lower(d.Name), "pump") and d.Size.Y > 2 then
				table.insert(pumps, d)
			end
		end
	end
	local used = 0
	for _, p in pumps do
		if used >= 2 then
			break
		end
		local before = n
		park({ { p.Position.X + 7, p.Position.Z, math.pi }, { p.Position.X - 7, p.Position.Z, 0 } }, "Parked_GasStation")
		if n > before then
			used += 1
		end
	end
	if used == 0 and gas then
		park({ { (gas.Min.X + gas.Max.X) / 2 - 20, gas.Max.Y - 22, math.pi / 2 } }, "Parked_GasStation")
	end
	-- hardware store: the staff lot east of the store, noses west toward it (not the yard in front: that is Crew
	-- Supply's drive-through loading lane since 2026-11-17, DevTools/SupplyStoreBuilder)
	local hw = lot("Hardware")
	if hw then
		for k = 0, 2 do
			park({ { -46, -500 - k * 12, math.pi / 2 } }, "Parked_Hardware")
		end
	end
	return n
end

function Builder.All(): string
	local old = workspace:FindFirstChild("TownLife")
	if old then
		old:Destroy()
	end
	life = Instance.new("Folder")
	life.Name = "TownLife"
	life.Parent = workspace
	propsFolder = Instance.new("Folder")
	propsFolder.Name = "Props"
	propsFolder.Parent = life
	carsFolder = Instance.new("Folder")
	carsFolder.Name = "ParkedCars"
	carsFolder.Parent = life
	local a = props()
	local b = parked()
	return ("TownLife: %d props, %d parked cars"):format(a, b)
end

return Builder
