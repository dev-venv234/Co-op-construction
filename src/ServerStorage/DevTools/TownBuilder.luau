--!strict
-- DEV TOOL (never required by game code). Builds the town from Shared.Config.TownLayout.
-- Run from Studio in Edit mode, e.g. in the command bar:
--   local B = require(game.ServerStorage.DevTools.TownBuilder)
--   B.Terrain()  B.Parts()        -- or B.All()
-- Safe to re-run: it clears the terrain and Workspace.Town first. Stage 1 = terrain + roads only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local L = require(ReplicatedStorage.Shared.Config.TownLayout) :: any

local Builder = {}

local terrain = workspace.Terrain
local HALF = L.RoadWidth / 2
local WALK = HALF + L.SidewalkWidth
local CORNER = HALF + 1 -- curbs stop at the crossing road's edge
-- Terrain renders a full top voxel 2 studs above the voxel. Filling only up to y = -2 leaves the top voxel
-- half full, which puts the walkable surface at exactly y = 0 (measured with raycasts).
local FILL_TOP = -2

local roadsByName: { [string]: any } = {}
for _, r in L.Roads do
	roadsByName[r.Name] = r
end

-- Center of a strip along a road: `along` = position on the road axis, `across` = offset from the center line.
local function pointOn(r: any, along: number, across: number, y: number): Vector3
	if r.Axis == "X" then
		return Vector3.new(along, y, r.At + across)
	end
	return Vector3.new(r.At + across, y, along)
end

local function sizeOn(r: any, alongLen: number, acrossLen: number, h: number): Vector3
	if r.Axis == "X" then
		return Vector3.new(alongLen, h, acrossLen)
	end
	return Vector3.new(acrossLen, h, alongLen)
end

local function fillRoadStrip(r: any, half: number, extend: number, material: Enum.Material)
	local a, b = r.From - extend, r.To + extend
	terrain:FillBlock(CFrame.new(pointOn(r, (a + b) / 2, 0, FILL_TOP - 4)), sizeOn(r, b - a, half * 2, 8), material)
end

local function fillRect(minX: number, minZ: number, maxX: number, maxZ: number, material: Enum.Material)
	terrain:FillBlock(
		CFrame.new((minX + maxX) / 2, FILL_TOP - 4, (minZ + maxZ) / 2),
		Vector3.new(maxX - minX, 8, maxZ - minZ),
		material
	)
end

-- Driveway rectangle from the road edge to the lot edge (crosses the sidewalk).
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

function Builder.Terrain()
	-- Archive the flat baseplate and the Phase 1 sketch instead of deleting them.
	local archive = ServerStorage:FindFirstChild("Archive") or Instance.new("Folder")
	archive.Name = "Archive"
	archive.Parent = ServerStorage
	for _, name in { "Baseplate", "SiteSketch_StarterHouse" } do
		local inst = workspace:FindFirstChild(name)
		if inst then
			inst.Parent = archive
		end
	end

	terrain:Clear()
	local B = L.Bounds
	for x = B.MinX, B.MaxX - 1, 400 do
		for z = B.MinZ, B.MaxZ - 1, 400 do
			terrain:FillBlock(CFrame.new(x + 200, FILL_TOP - 6, z + 200), Vector3.new(400, 12, 400), Enum.Material.Grass)
		end
		task.wait()
	end
	for _, h in L.Hills do
		terrain:FillBall(Vector3.new(h.X, h.Y, h.Z), h.R, Enum.Material.Grass)
	end
	task.wait()
	-- Sidewalks first, then dirt site pads, then asphalt on top (so crossings stay asphalt).
	for _, r in L.Roads do
		fillRoadStrip(r, WALK, WALK, Enum.Material.Pavement)
	end
	for _, lot in L.Lots do
		if lot.Kind == "Site" then
			fillRect(lot.Min.X, lot.Min.Y, lot.Max.X, lot.Max.Y, Enum.Material.Ground)
		end
	end
	task.wait()
	for _, r in L.Roads do
		fillRoadStrip(r, HALF, HALF, Enum.Material.Asphalt)
	end
	for _, lot in L.Lots do
		if lot.Gate then
			local x0, z0, x1, z1 = drivewayRect(lot)
			fillRect(x0, z0, x1, z1, Enum.Material.Asphalt)
		end
	end
	return "terrain done"
end

-- Curb/marking intervals ------------------------------------------------------------------------

-- Does perpendicular road q continue past road r's center line toward `side`?
local function extendsTo(q: any, r: any, side: number): boolean
	if side < 0 then
		return q.From < r.At - 1
	end
	return q.To > r.At + 1
end

-- Returns the [lo, hi] span of a curb line and the gaps to cut out of it.
-- side = -1/+1 for curbs, 0 for the center line.
local function spanAndGaps(r: any, side: number): (number, number, { { number } })
	local lo, hi = r.From - HALF, r.To + HALF
	local gaps: { { number } } = {}
	for _, q in L.Roads do
		if q.Axis ~= r.Axis and r.At >= q.From - 1 and r.At <= q.To + 1 and q.At >= r.From - 1 and q.At <= r.To + 1 then
			local inner = side == 0 or extendsTo(q, r, side)
			if math.abs(q.At - r.From) < 1 then
				lo = if inner then q.At + CORNER else q.At - CORNER
			elseif math.abs(q.At - r.To) < 1 then
				hi = if inner then q.At - CORNER else q.At + CORNER
			elseif inner then
				table.insert(gaps, { q.At - CORNER, q.At + CORNER })
			end
		end
	end
	if side ~= 0 then
		for _, lot in L.Lots do
			local g = lot.Gate
			if g and g.Road == r.Name and g.Side == side then
				table.insert(gaps, { g.At - g.Width / 2, g.At + g.Width / 2 })
			end
		end
	end
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)
	return lo, hi, gaps
end

local function pieces(lo: number, hi: number, gaps: { { number } }): { { number } }
	local out = {}
	local cur = lo
	for _, g in gaps do
		if g[1] > cur then
			table.insert(out, { cur, math.min(g[1], hi) })
		end
		cur = math.max(cur, g[2])
	end
	if hi > cur then
		table.insert(out, { cur, hi })
	end
	local kept = {}
	for _, p in out do
		if p[2] - p[1] >= 2 then
			table.insert(kept, p)
		end
	end
	return kept
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.CanCollide = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function decal(p: Part)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local CURB_GREY = Color3.fromRGB(175, 172, 165)
local YELLOW = Color3.fromRGB(235, 190, 40)
local WHITE = Color3.fromRGB(235, 235, 230)
local POLE = Color3.fromRGB(70, 72, 76)
local LAMP = Color3.fromRGB(255, 214, 160)

local function buildStreetlight(r: any, along: number, side: number, parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Streetlight"
	m:SetAttribute("Streetlight", true)
	local base = pointOn(r, along, side * (WALK - 2), 0)
	local toRoad = if r.Axis == "X" then Vector3.new(0, 0, -side) else Vector3.new(-side, 0, 0)
	part("Pole", Vector3.new(18, 0.8, 0.8), CFrame.new(base + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.pi / 2), POLE, Enum.Material.Metal, m).Shape =
		Enum.PartType.Cylinder
	local armSize = if r.Axis == "X" then Vector3.new(0.4, 0.4, 7) else Vector3.new(7, 0.4, 0.4)
	part("Arm", armSize, CFrame.new(base + Vector3.new(0, 17.6, 0) + toRoad * 3.3), POLE, Enum.Material.Metal, m)
	local headSize = if r.Axis == "X" then Vector3.new(1.6, 0.6, 2.6) else Vector3.new(2.6, 0.6, 1.6)
	part("Head", headSize, CFrame.new(base + Vector3.new(0, 17.3, 0) + toRoad * 6.6), POLE, Enum.Material.Metal, m)
	local lensSize = if r.Axis == "X" then Vector3.new(1.2, 0.15, 2.1) else Vector3.new(2.1, 0.15, 1.2)
	local lens = part("Lens", lensSize, CFrame.new(base + Vector3.new(0, 16.92, 0) + toRoad * 6.6), LAMP, Enum.Material.Neon, m)
	decal(lens)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 110
	light.Range = 50
	light.Brightness = 2.5
	light.Color = LAMP
	light.Shadows = false
	light.Parent = lens
	m.Parent = parent
end

function Builder.Parts()
	local old = workspace:FindFirstChild("Town")
	if old then
		old:Destroy()
	end
	local town = Instance.new("Folder")
	town.Name = "Town"
	local roads = Instance.new("Folder")
	roads.Name = "Roads"
	roads.Parent = town
	local lights = Instance.new("Folder")
	lights.Name = "Streetlights"
	lights.Parent = town
	local lots = Instance.new("Folder")
	lots.Name = "Lots"
	lots.Parent = town
	town.Parent = workspace

	local counts = { curbs = 0, lines = 0, lights = 0, stripes = 0 }
	for _, r in L.Roads do
		local folder = Instance.new("Folder")
		folder.Name = r.Name
		-- Curbs (0.6 tall: trucks can't hop them, people can step over)
		for _, side in { -1, 1 } do
			local lo, hi, gaps = spanAndGaps(r, side)
			for _, p in pieces(lo, hi, gaps) do
				local len = p[2] - p[1]
				part("Curb", sizeOn(r, len, 1, 0.6), CFrame.new(pointOn(r, (p[1] + p[2]) / 2, side * (HALF + 0.5), 0.3)),
					CURB_GREY, Enum.Material.Concrete, folder)
				counts.curbs += 1
			end
		end
		-- Double yellow center line
		local lo, hi, gaps = spanAndGaps(r, 0)
		for _, p in pieces(lo, hi, gaps) do
			local len = p[2] - p[1]
			for _, off in { -0.45, 0.45 } do
				local line = part("CenterLine", sizeOn(r, len, 0.35, 0.05),
					CFrame.new(pointOn(r, (p[1] + p[2]) / 2, off, 0.1)), YELLOW, Enum.Material.Concrete, folder)
				decal(line)
				counts.lines += 1
			end
		end
		-- Streetlights, alternating sides, kept away from crossings and driveways
		local blocked: { number } = {}
		for _, s in { -1, 1 } do
			local _, _, g = spanAndGaps(r, s)
			for _, gap in g do
				table.insert(blocked, (gap[1] + gap[2]) / 2)
			end
		end
		local side = 1
		local along = lo + 40
		while along <= hi - 30 do
			local ok = true
			for _, b in blocked do
				if math.abs(b - along) < 30 then
					ok = false
				end
			end
			if ok then
				buildStreetlight(r, along, side, lights)
				counts.lights += 1
				side = -side
			end
			along += L.StreetlightSpacing
		end
		folder.Parent = roads
		task.wait()
	end

	-- Zebra crossings
	local cw = Instance.new("Folder")
	cw.Name = "Crosswalks"
	for _, c in L.Crosswalks do
		local r = roadsByName[c.Road]
		for off = -HALF + 2.5, HALF - 2.5, 3.6 do
			local stripe = part("Stripe", sizeOn(r, 6, 1.8, 0.05), CFrame.new(pointOn(r, c.At, off, 0.1)), WHITE, Enum.Material.Concrete, cw)
			decal(stripe)
			counts.stripes += 1
		end
	end
	cw.Parent = roads

	-- Lot markers (invisible bounds for later stages) + a temporary wooden sign at each gate
	for _, lot in L.Lots do
		local w, d = lot.Max.X - lot.Min.X, lot.Max.Y - lot.Min.Y
		local marker = part(lot.Id, Vector3.new(w, 1, d), CFrame.new((lot.Min.X + lot.Max.X) / 2, 0.5, (lot.Min.Y + lot.Max.Y) / 2),
			Color3.new(1, 1, 1), Enum.Material.Concrete, lots, false)
		marker.Transparency = 1
		decal(marker)
		marker:SetAttribute("Kind", lot.Kind)
		if lot.Tier then
			marker:SetAttribute("Tier", lot.Tier)
		end

		local g = lot.Gate
		if g then
			local r = roadsByName[g.Road]
			local signPos = pointOn(r, g.At + g.Width / 2 + 4, g.Side * (WALK + 3), 0)
			local facing = pointOn(r, g.At + g.Width / 2 + 4, 0, 0)
			local sign = Instance.new("Model")
			sign.Name = "TempSign"
			sign:SetAttribute("Temporary", true)
			part("Post", Vector3.new(0.6, 6, 0.6), CFrame.new(signPos + Vector3.new(0, 3, 0)), Color3.fromRGB(110, 80, 50), Enum.Material.Wood, sign)
			local board = part("Board", Vector3.new(9, 3, 0.4), CFrame.lookAt(signPos + Vector3.new(0, 6.5, 0), facing + Vector3.new(0, 6.5, 0)),
				Color3.fromRGB(150, 115, 75), Enum.Material.WoodPlanks, sign)
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local sg = Instance.new("SurfaceGui")
				sg.Face = face
				sg.PixelsPerStud = 30
				local t = Instance.new("TextLabel")
				t.Size = UDim2.fromScale(1, 1)
				t.BackgroundTransparency = 1
				t.TextColor3 = Color3.new(1, 1, 1)
				t.TextStrokeTransparency = 0.4
				t.TextScaled = true
				t.Font = Enum.Font.GothamBlack
				t.Text = lot.Label
				t.Parent = sg
				sg.Parent = board
			end
			sign.Parent = marker
		end
	end

	return ("parts done: %d curbs, %d line strips, %d streetlights, %d crosswalk stripes, %d lots"):format(
		counts.curbs, counts.lines, counts.lights, counts.stripes, #L.Lots)
end

function Builder.All()
	return Builder.Terrain() .. "; " .. Builder.Parts()
end

return Builder
