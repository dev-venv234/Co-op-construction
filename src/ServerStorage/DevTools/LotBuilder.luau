--!strict
-- DEV TOOL (never required by game code). Adds lots to the finished town without rebuilding it (2026-11-17, several
-- crews per server): for each lot id given (they must be in Shared.Config.TownLayout) it
--   * paints the lot Ground and its driveway Asphalt (same fills as TownBuilder),
--   * cuts the curb at the gate (the town's curbs were built before these gates existed),
--   * clears the trees and props standing on the lot or the driveway,
--   * adds the invisible lot marker in Workspace.Town.Lots.
-- Also adds RV lot truck stall 7 (stall 6 is the truck dealer's display), so each of the 6 crews has a stall.
-- Then run SiteBuilder.All() for the fences, trailers and signs.
-- Run in Studio Edit mode:  require(game.ServerStorage.DevTools.LotBuilder:Clone()).Build({ "Site_T1b", ... })
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local L = require(ReplicatedStorage.Shared.Config.TownLayout) :: any
local Lots = require(ReplicatedStorage.Shared.Util.Lots) :: any

local Builder = {}

local terrain = workspace.Terrain
local HALF = L.RoadWidth / 2
local FILL_TOP = -2

local roadsByName: { [string]: any } = {}
for _, r in L.Roads do
	roadsByName[r.Name] = r
end

local function fillRect(minX: number, minZ: number, maxX: number, maxZ: number, material: Enum.Material)
	terrain:FillBlock(CFrame.new((minX + maxX) / 2, FILL_TOP - 4, (minZ + maxZ) / 2), Vector3.new(maxX - minX, 8, maxZ - minZ), material)
end

-- Same as TownBuilder: from the road edge to the lot edge (crosses the sidewalk).
local function drivewayRect(lot: any): (number, number, number, number)
	local g = lot.Gate
	local r = roadsByName[g.Road]
	local w = g.Width / 2
	if r.Axis == "X" then
		local edge = r.At + g.Side * HALF
		local lotEdge = if g.Side > 0 then lot.Min.Y else lot.Max.Y
		return g.At - w, math.min(edge, lotEdge), g.At + w, math.max(edge, lotEdge)
	end
	local edge = r.At + g.Side * HALF
	local lotEdge = if g.Side > 0 then lot.Min.X else lot.Max.X
	return math.min(edge, lotEdge), g.At - w, math.max(edge, lotEdge), g.At + w
end

-- Splits the curb on the gate's side of its road around the gate. Returns how many curbs were cut.
local function cutCurb(lot: any): number
	local g = lot.Gate
	local r = roadsByName[g.Road]
	local folder = workspace:FindFirstChild("Town") and workspace.Town:FindFirstChild("Roads")
	folder = folder and folder:FindFirstChild(r.Name)
	if not folder then
		return 0
	end
	local lo, hi = g.At - g.Width / 2, g.At + g.Width / 2
	local acrossWant = r.At + g.Side * (HALF + 0.5)
	local cut = 0
	for _, c in folder:GetChildren() do
		if c.Name ~= "Curb" or not c:IsA("BasePart") then
			continue
		end
		local along = if r.Axis == "X" then c.Position.X else c.Position.Z
		local across = if r.Axis == "X" then c.Position.Z else c.Position.X
		local len = if r.Axis == "X" then c.Size.X else c.Size.Z
		local a0, a1 = along - len / 2, along + len / 2
		if math.abs(across - acrossWant) > 0.6 or a1 <= lo or a0 >= hi then
			continue
		end
		for _, piece in { { a0, lo }, { hi, a1 } } do
			local p0, p1 = piece[1], piece[2]
			if p1 - p0 >= 2 then
				local n = c:Clone()
				local mid = (p0 + p1) / 2
				n.Size = if r.Axis == "X" then Vector3.new(p1 - p0, c.Size.Y, c.Size.Z) else Vector3.new(c.Size.X, c.Size.Y, p1 - p0)
				n.CFrame = if r.Axis == "X" then CFrame.new(mid, c.Position.Y, c.Position.Z) else CFrame.new(c.Position.X, c.Position.Y, mid)
				n.Parent = folder
			end
		end
		c:Destroy()
		cut += 1
	end
	return cut
end

-- Removes the top-level models (trees, props) that stand in a rectangle.
local function clearRect(minX: number, minZ: number, maxX: number, maxZ: number): number
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	local keep = { workspace.Terrain }
	for _, name in { "Town", "Sites", "RVPark", "SupplyStore", "Filler", "ToolShop" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(keep, f)
		end
	end
	op.FilterDescendantsInstances = keep
	local box = CFrame.new((minX + maxX) / 2, 30, (minZ + maxZ) / 2)
	local gone: { [Instance]: boolean } = {}
	for _, p in workspace:GetPartBoundsInBox(box, Vector3.new(maxX - minX, 60, maxZ - minZ), op) do
		-- the model right under its folder (Nature.Chunk.Ponderosa 4, TownLife.Props.Bench ...)
		local m: Instance = p
		while m.Parent and m.Parent ~= workspace and not m.Parent:IsA("Folder") do
			m = m.Parent
		end
		if m ~= workspace and not gone[m] and m.Parent then
			gone[m] = true
		end
	end
	local n = 0
	for m in gone do
		if m.Parent then
			m:Destroy()
			n += 1
		end
	end
	return n
end

local function marker(lot: any)
	local lots = workspace:FindFirstChild("Town") and workspace.Town:FindFirstChild("Lots")
	if not lots or lots:FindFirstChild(lot.Id) then
		return
	end
	local m = Instance.new("Part")
	m.Name = lot.Id
	m.Anchored = true
	m.CanCollide = false
	m.CanQuery = false
	m.CanTouch = false
	m.CastShadow = false
	m.Transparency = 1
	m.Size = Vector3.new(lot.Max.X - lot.Min.X, 1, lot.Max.Y - lot.Min.Y)
	m.CFrame = CFrame.new(Lots.Center(lot) + Vector3.new(0, 0.5, 0))
	m.Material = Enum.Material.Concrete
	m:SetAttribute("Kind", lot.Kind)
	if lot.Tier then
		m:SetAttribute("Tier", lot.Tier)
	end
	m.Parent = lots
end

-- RV lot stall 7, next to the dealer's stall 6 (copies stall 6's paint).
local function stallSeven(): string
	local tl = workspace:FindFirstChild("RVPark") and workspace.RVPark:FindFirstChild("TruckLot")
	if not tl then
		return "no TruckLot"
	end
	if tl:FindFirstChild("Stall_7") then
		return "stall 7 already there"
	end
	local s6 = tl:FindFirstChild("Stall_6") :: BasePart?
	if not s6 then
		return "no Stall_6"
	end
	local s7 = s6:Clone()
	s7.Name = "Stall_7"
	s7.CFrame = s6.CFrame + Vector3.new(14, 0, 0)
	s7.Parent = tl
	-- the line on its far side, its number, and the back line
	for _, c in tl:GetChildren() do
		if c:IsA("BasePart") and c.Name == "StallLine" and math.abs(c.Position.X - 112) < 0.5 then
			local n = c:Clone()
			n.CFrame = c.CFrame + Vector3.new(14, 0, 0)
			n.Parent = tl
		elseif c:IsA("BasePart") and c.Name == "StallNumber" and math.abs(c.Position.X - 105) < 0.5 then
			local n = c:Clone()
			n.CFrame = c.CFrame + Vector3.new(14, 0, 0)
			for _, d in n:GetDescendants() do
				if d:IsA("TextLabel") then
					d.Text = "7"
				end
			end
			n.Parent = tl
		elseif c:IsA("BasePart") and c.Name == "StallBackLine" then
			local n = c:Clone()
			n.Size = Vector3.new(14, c.Size.Y, c.Size.Z)
			n.CFrame = CFrame.new(119, c.Position.Y, c.Position.Z)
			n.Parent = tl
		end
	end
	-- asphalt under it if the lot surface stops short
	local hit = workspace:Raycast(Vector3.new(119, 20, -292), Vector3.new(0, -40, 0))
	if hit and hit.Instance == workspace.Terrain and hit.Material ~= Enum.Material.Asphalt then
		fillRect(112, -300, 128, -276, Enum.Material.Asphalt)
		return "stall 7 added (+ asphalt)"
	end
	return "stall 7 added"
end

function Builder.Build(ids: { string }): string
	local out = {}
	for _, id in ids do
		local lot = Lots.Get(id)
		if not lot then
			table.insert(out, id .. ": not in TownLayout")
			continue
		end
		local x0, z0, x1, z1 = drivewayRect(lot)
		local trees = clearRect(lot.Min.X - 6, lot.Min.Y - 6, lot.Max.X + 6, lot.Max.Y + 6)
			+ clearRect(x0 - 3, z0 - 3, x1 + 3, z1 + 3)
		fillRect(lot.Min.X, lot.Min.Y, lot.Max.X, lot.Max.Y, Enum.Material.Ground)
		fillRect(x0, z0, x1, z1, Enum.Material.Asphalt)
		local curbs = cutCurb(lot)
		marker(lot)
		table.insert(out, ("%s: %d things cleared, %d curb cut"):format(id, trees, curbs))
		task.wait()
	end
	table.insert(out, stallSeven())
	return table.concat(out, "; ")
end

return Builder
