--!strict
-- Edit-time only: builds Workspace.SupplyStore, the crew's building-supply yard in front of the hardware store
-- (TownLayout lot "Hardware", on Main St). JobService finds the stacks (parts with a MaterialStack attribute) and the
-- "Dock" part at Start; the truck loads itself when it stops near the dock (drive-through loading).
-- Run: require(game.ServerStorage.DevTools.SupplyStoreBuilder).Build()
--
-- Layout (rebuilt 2026-11-17, owner: "the crew supply is awkward"). It used to have one driveway that ran straight
-- into a canopy post, the town's parked cars stood in the loading lane, the street sign stood in the yard, and two
-- side racks divided by zero (their parts ended up far outside the map). Now it is a one-way drive-through:
--   IN from Main St at the east end -> turn west along the dock under the canopy -> stop in the yellow LOADING BAY
--   (the truck loads itself) -> keep going west -> OUT onto Main St at the west end.
-- Build() also cuts the curb / paints the two driveways, closes the old middle driveway, moves the street sign onto
-- the grass between the driveways, and moves the hardware store's parked cars to a staff lot east of the store.
local Builder = {}

local C = Color3.fromRGB
local M = Enum.Material
local WARM = C(255, 225, 170)
local YELLOW = C(250, 210, 50)
local ORANGE = C(230, 120, 30)

-- Main St runs east-west at z = -400 (32 wide): its north curb is at z -416.5. The yard pad is x -172..-32,
-- z -484..-432.
local ENTRY_X, EXIT_X, DRIVE_W = -49, -155, 22
local OLD_GAP = { -112, -88 } -- the old middle driveway (closed)
local LANE_Z = -455 -- center of the drive lane under the canopy
local FILL_TOP = -2 -- terrain rule: walkable ground at y = 0

local function box(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.CanCollide = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- decoration that never gets in the way (no collision, no queries, no shadow)
local function deco(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance): Part
	local p = box(name, size, cf, color, mat, parent, false)
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function cyl(name: string, length: number, diameter: number, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance, collide: boolean?): Part
	local p = box(name, Vector3.new(length, diameter, diameter), cf, color, mat, parent, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function upright(pos: Vector3): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
end

local function text(part: BasePart, face: Enum.NormalId, lines: { { string | number | Color3 } }, ppStud: number)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppStud
	sg.LightInfluence = 0.3
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sg
	for i, l in lines do
		local t = Instance.new("TextLabel")
		t.LayoutOrder = i
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, l[2] :: number, 0)
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = (l[3] :: Color3?) or C(250, 245, 230)
		t.Text = l[1] :: string
		t.Parent = sg
	end
	sg.Parent = part
end

local function nightLamp(part: BasePart, range: number, brightness: number)
	part:SetAttribute("NightLight", true)
	local s = Instance.new("SpotLight")
	s.Face = Enum.NormalId.Bottom
	s.Angle = 120
	s.Range = range
	s.Brightness = brightness
	s.Color = WARM
	s.Shadows = false
	s.Parent = part
end

-- Paint on the ground: a flat part just above the pad (no collision).
local function paint(name: string, size: Vector3, pos: Vector3, color: Color3, parent: Instance, yaw: number?): Part
	return deco(name, Vector3.new(size.X, 0.05, size.Z), CFrame.new(pos.X, 0.23, pos.Z) * CFrame.Angles(0, yaw or 0, 0), color, M.Concrete, parent)
end

-- A painted arrow on the ground pointing along `dir` (a unit vector on the ground).
local function arrow(parent: Instance, at: Vector3, dir: Vector3, color: Color3)
	local yaw = math.atan2(-dir.X, -dir.Z) -- CFrame front (-Z) along dir
	local cf = CFrame.new(at.X, 0.23, at.Z) * CFrame.Angles(0, yaw, 0)
	deco("ArrowShaft", Vector3.new(1.4, 0.05, 7), cf * CFrame.new(0, 0, 1), color, M.Concrete, parent)
	-- the head: two bars in a ">" shape at the front end
	for _, s in { -1, 1 } do
		deco("ArrowHead", Vector3.new(1.4, 0.05, 4.2), cf * CFrame.new(s * 1.3, 0, -1.6) * CFrame.Angles(0, s * math.rad(40), 0), color, M.Concrete, parent)
	end
end

-- Words painted flat on the ground, readable from above (top face). The text runs along the part's Z axis, so
-- size = (height, width) and yaw -pi/2 makes it read left to right for someone facing north (from the street).
local function groundWords(parent: Instance, words: string, at: Vector3, size: Vector2, yaw: number, color: Color3)
	local p = deco("GroundText", Vector3.new(size.X, 0.05, size.Y), CFrame.new(at.X, 0.24, at.Z) * CFrame.Angles(0, yaw, 0), C(0, 0, 0), M.Concrete, parent)
	p.Transparency = 1
	text(p, Enum.NormalId.Top, { { words, 1, color } }, 20)
end

-- A tall steel rack loaded with bundles (decoration: the yard looks like a real lumber yard).
local function rack(parent: Instance, at: Vector3, length: number, color: Color3, mat: Enum.Material, levels: number)
	local steel = C(40, 90, 160)
	local m = Instance.new("Model")
	m.Name = "Rack"
	local bays = math.max(1, math.floor(length / 10)) -- (was length/0 for short racks: NaN positions)
	for i = 0, bays do
		local x = at.X - length / 2 + i * (length / bays)
		for _, dz in { -2.6, 2.6 } do
			box("Upright", Vector3.new(0.6, levels * 4 + 1, 0.6), CFrame.new(x, (levels * 4 + 1) / 2, at.Z + dz), steel, M.Metal, m)
		end
	end
	for lv = 1, levels do
		local y = lv * 4 - 1.2
		for _, dz in { -2.6, 2.6 } do
			box("Beam", Vector3.new(length, 0.5, 0.4), CFrame.new(at.X, y, at.Z + dz), ORANGE, M.Metal, m)
		end
		for b = 0, math.max(1, math.floor(length / 7)) - 1 do
			local bx = at.X - length / 2 + 3.5 + b * 7
			box("Bundle", Vector3.new(6, 1.6, 4.6), CFrame.new(bx, y + 1.05, at.Z), color, mat, m)
		end
	end
	m.Parent = parent
end

-- A forklift (decoration).
local function forklift(parent: Instance, at: CFrame)
	local m = Instance.new("Model")
	m.Name = "Forklift"
	local body = C(240, 180, 30)
	local dark = C(35, 35, 38)
	box("Body", Vector3.new(4, 2.6, 6), at * CFrame.new(0, 2.2, 0.5), body, M.Metal, m)
	box("Counterweight", Vector3.new(4, 2.2, 1.4), at * CFrame.new(0, 2.0, 3.6), dark, M.Metal, m)
	box("Seat", Vector3.new(2, 0.6, 1.8), at * CFrame.new(0, 3.8, 1.2), dark, M.Fabric, m)
	for _, x in { -1.8, 1.8 } do
		box("CagePost", Vector3.new(0.25, 4, 0.25), at * CFrame.new(x, 5.5, -0.8), dark, M.Metal, m)
		box("CagePost", Vector3.new(0.25, 4, 0.25), at * CFrame.new(x, 5.5, 2.6), dark, M.Metal, m)
		box("Mast", Vector3.new(0.4, 7, 0.4), at * CFrame.new(x * 0.6, 4.4, -2.4), dark, M.Metal, m)
		box("Fork", Vector3.new(0.5, 0.25, 4), at * CFrame.new(x * 0.55, 0.9, -4.4), C(60, 60, 64), M.Metal, m)
		for _, z in { -1.5, 2.8 } do
			cyl("Wheel", 0.8, 1.8, at * CFrame.new(x * 1.08, 0.9, z), dark, M.Rubber, m)
		end
	end
	box("CageRoof", Vector3.new(3.9, 0.2, 3.7), at * CFrame.new(0, 7.5, 0.9), dark, M.Metal, m)
	box("Pallet", Vector3.new(4, 0.4, 4), at * CFrame.new(0, 1.25, -4.6), C(160, 125, 85), M.Wood, m)
	box("Load", Vector3.new(3.6, 1.6, 3.6), at * CFrame.new(0, 2.25, -4.6), C(200, 160, 110), M.WoodPlanks, m)
	m.Parent = parent
end

local function cone(parent: Instance, at: Vector3)
	local c = Instance.new("Model")
	c.Name = "Cone"
	box("Base", Vector3.new(1.4, 0.2, 1.4), CFrame.new(at + Vector3.new(0, 0.1, 0)), ORANGE, M.Rubber, c, false)
	cyl("Body", 1.6, 0.9, upright(at + Vector3.new(0, 1, 0)), ORANGE, M.Rubber, c, false)
	cyl("Band", 0.3, 0.95, upright(at + Vector3.new(0, 1.1, 0)), C(240, 240, 240), M.Fabric, c, false)
	c.Parent = parent
end

local function hedge(parent: Instance, x0: number, x1: number, z: number)
	local green = { C(64, 110, 52), C(74, 124, 58), C(58, 100, 48) }
	local i = 0
	for x = x0 + 1.6, x1 - 1.6, 3 do
		i += 1
		local s = 3 + (i % 3) * 0.4
		local b = deco("Shrub", Vector3.new(s, s * 0.8, s), CFrame.new(x, s * 0.36, z), green[i % 3 + 1], M.Grass, parent)
		b.Shape = Enum.PartType.Ball
	end
end

---------------------------------------------------------------------------------------------------------------
-- Ground: driveways, curb, terrain
---------------------------------------------------------------------------------------------------------------

local function fill(x0: number, z0: number, x1: number, z1: number, mat: Enum.Material)
	workspace.Terrain:FillBlock(CFrame.new((x0 + x1) / 2, FILL_TOP - 4, (z0 + z1) / 2), Vector3.new(x1 - x0, 8, z1 - z0), mat)
end

local function groundMaterialAt(x: number, z: number): Enum.Material
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = { workspace.Terrain }
	local r = workspace:Raycast(Vector3.new(x, 20, z), Vector3.new(0, -40, 0), p)
	return if r then r.Material else M.Grass
end

-- Main St's north curb: cut gaps at the new driveways, close the old one.
local function curbs(): string
	local roads = workspace:FindFirstChild("Town") and workspace.Town:FindFirstChild("Roads")
	local main = roads and roads:FindFirstChild("Main St")
	if not main then
		return "no Main St curb found"
	end
	local function northCurbs(): { BasePart }
		local out = {}
		for _, d in main:GetChildren() do
			if d:IsA("BasePart") and d.Name == "Curb" and math.abs(d.Position.Z - -416.5) < 0.6 and d.Size.Z < 2 then
				table.insert(out, d)
			end
		end
		return out
	end
	local cuts = 0
	for _, gap in { { ENTRY_X - DRIVE_W / 2, ENTRY_X + DRIVE_W / 2 }, { EXIT_X - DRIVE_W / 2, EXIT_X + DRIVE_W / 2 } } do
		for _, c in northCurbs() do
			local a, b = c.Position.X - c.Size.X / 2, c.Position.X + c.Size.X / 2
			if a < gap[2] and b > gap[1] then
				for _, piece in { { a, gap[1] }, { gap[2], b } } do
					if piece[2] - piece[1] > 0.5 then
						local n = c:Clone()
						n.Size = Vector3.new(piece[2] - piece[1], c.Size.Y, c.Size.Z)
						n.Position = Vector3.new((piece[1] + piece[2]) / 2, c.Position.Y, c.Position.Z)
						n.Parent = main
					end
				end
				c:Destroy()
				cuts += 1
			end
		end
	end
	-- close the old middle gap (only if no curb covers it yet)
	local covered = false
	for _, c in northCurbs() do
		local a, b = c.Position.X - c.Size.X / 2, c.Position.X + c.Size.X / 2
		if a <= OLD_GAP[1] + 0.5 and b >= OLD_GAP[2] - 0.5 then
			covered = true
		end
	end
	local any = northCurbs()[1]
	if not covered and any then
		local n = any:Clone()
		n.Size = Vector3.new(OLD_GAP[2] - OLD_GAP[1], any.Size.Y, any.Size.Z)
		n.Position = Vector3.new((OLD_GAP[1] + OLD_GAP[2]) / 2, any.Position.Y, any.Position.Z)
		n.Parent = main
	end
	return ("curb: %d cut, old gap %s"):format(cuts, if covered then "already closed" else "closed")
end

local function terrain()
	-- old middle driveway back to sidewalk / grass, copying the strip just west of it slice by slice (the terrain
	-- grid here runs on z = 2 mod 4: grass -430..-422, sidewalk -422..-418, road edge from -418)
	for z = -430, -422, 4 do
		local mat = groundMaterialAt(OLD_GAP[1] - 10, z + 2)
		fill(OLD_GAP[1], z, OLD_GAP[2], z + 4, mat)
	end
	-- the two new driveways (road edge to the pad)
	for _, x in { ENTRY_X, EXIT_X } do
		fill(x - DRIVE_W / 2, -432, x + DRIVE_W / 2, -416, M.Asphalt)
	end
	-- staff parking east of the store
	fill(-60, -528, -32, -492, M.Asphalt)
end

-- Town props standing in the new driveways move aside; the store's parked cars go to the staff lot.
local function moveTownLife(): string
	local life = workspace:FindFirstChild("TownLife")
	local moved = 0
	if not life then
		return "no TownLife"
	end
	local props = life:FindFirstChild("Props")
	if props then
		for _, m in props:GetChildren() do
			if m:IsA("Model") then
				local p = m:GetPivot().Position
				for _, x in { ENTRY_X, EXIT_X } do
					if math.abs(p.X - x) < DRIVE_W / 2 + 2 and p.Z < -414 and p.Z > -434 then
						local side = if p.X < x then -1 else 1
						m:PivotTo(m:GetPivot() + Vector3.new(side * (DRIVE_W + 2), 0, 0)) -- keeps their spacing
						moved += 1
					end
				end
			end
		end
	end
	local cars = life:FindFirstChild("ParkedCars")
	if cars then
		local k = 0
		for _, car in cars:GetChildren() do
			if car:IsA("Model") and car.Name == "Parked_Hardware" then
				local y = car:GetPivot().Position.Y
				car:PivotTo(CFrame.new(-46, y, -500 - k * 12) * CFrame.Angles(0, math.pi / 2, 0)) -- nose west, toward the store
				k += 1
				moved += 1
			end
		end
	end
	return ("moved %d town props / cars"):format(moved)
end

---------------------------------------------------------------------------------------------------------------
-- The yard
---------------------------------------------------------------------------------------------------------------

function Builder.Build()
	local old = workspace:FindFirstChild("SupplyStore")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "SupplyStore"
	local marks = Instance.new("Model")
	marks.Name = "Markings"
	marks.Parent = root

	-- Yard pad between the store and Main St
	box("YardPad", Vector3.new(140, 0.2, 52), CFrame.new(-102, 0.1, -458), C(150, 148, 142), M.Concrete, root)
	for x = -164, -40, 12 do
		deco("YardJoint", Vector3.new(0.2, 0.05, 52), CFrame.new(x, 0.22, -458), C(120, 118, 112), M.Concrete, root)
	end

	-- LOADING canopy over the drive lane, raised dock on its north side (truck pulls alongside, bed against the dock)
	local steel = C(70, 72, 76)
	for _, x in { -138, -105, -72 } do
		for _, z in { -478, -440 } do
			box("CanopyPost", Vector3.new(0.9, 16, 0.9), CFrame.new(x, 8, z), steel, M.Metal, root)
		end
		-- yellow guard around each front post (the lane side)
		box("PostGuard", Vector3.new(1.8, 3.2, 1.8), CFrame.new(x, 1.6, -440), YELLOW, M.Metal, root)
		deco("GuardStripe", Vector3.new(1.85, 0.5, 1.85), CFrame.new(x, 2.2, -440), C(30, 30, 30), M.Metal, root)
	end
	box("CanopyRoof", Vector3.new(72, 0.5, 42), CFrame.new(-105, 16.25, -459), C(95, 100, 105), M.CorrodedMetal, root)
	box("CanopyFascia", Vector3.new(72, 2.2, 0.4), CFrame.new(-105, 15.2, -438), ORANGE, M.Metal, root)
	local fascia = deco("CanopySign", Vector3.new(40, 2, 0.2), CFrame.new(-105, 15.2, -437.7), ORANGE, M.Metal, root)
	text(fascia, Enum.NormalId.Back, { { "CREW SUPPLY - DRIVE-THROUGH LOADING", 1, C(30, 30, 30) } }, 24)
	for _, x in { -128, -105, -82 } do
		local l = deco("CanopyLight", Vector3.new(3, 0.2, 3), CFrame.new(x, 15.9, -459), WARM, M.Neon, root)
		nightLamp(l, 36, 1.8)
	end
	-- hanging sign at the east end of the canopy, facing the trucks coming in
	local hang = deco("BaySign", Vector3.new(0.4, 3.4, 16), CFrame.new(-70, 11.6, LANE_Z), C(30, 32, 36), M.Metal, root)
	text(hang, Enum.NormalId.Right, {
		{ "STOP IN THE YELLOW BAY", 0.55, YELLOW },
		{ "your truck loads itself", 0.4, C(240, 240, 240) },
	}, 30)
	for _, z in { LANE_Z - 6, LANE_Z + 6 } do
		deco("BaySignChain", Vector3.new(0.12, 2.8, 0.12), CFrame.new(-70, 14.7, z), C(40, 40, 40), M.Metal, root)
	end

	box("Dock", Vector3.new(56, 2, 9), CFrame.new(-105, 1, -474), C(165, 160, 155), M.Concrete, root)
	box("DockEdge", Vector3.new(56, 2.2, 0.6), CFrame.new(-105, 1.1, -469.2), YELLOW, M.DiamondPlate, root)
	for x = -129, -81, 8 do
		box("Bumper", Vector3.new(2, 1.2, 0.8), CFrame.new(x, 1.2, -468.6), C(30, 30, 30), M.Rubber, root)
	end
	box("DockStairs", Vector3.new(4, 1, 3), CFrame.new(-136, 0.5, -472), C(150, 150, 150), M.DiamondPlate, root)
	for _, x in { -133.3, -76.7 } do
		box("DockRail", Vector3.new(0.3, 3, 9), CFrame.new(x, 3.5, -474), YELLOW, M.Metal, root)
	end

	-- Lane markings: the LOADING BAY box, travel arrows, IN / OUT
	local bay = { x0 = -130, x1 = -80, z0 = -467, z1 = -443 }
	paint("BayLine", Vector3.new(bay.x1 - bay.x0, 0, 0.7), Vector3.new((bay.x0 + bay.x1) / 2, 0, bay.z0), YELLOW, marks)
	paint("BayLine", Vector3.new(bay.x1 - bay.x0, 0, 0.7), Vector3.new((bay.x0 + bay.x1) / 2, 0, bay.z1), YELLOW, marks)
	paint("BayLine", Vector3.new(0.7, 0, bay.z1 - bay.z0), Vector3.new(bay.x0, 0, (bay.z0 + bay.z1) / 2), YELLOW, marks)
	paint("BayLine", Vector3.new(0.7, 0, bay.z1 - bay.z0), Vector3.new(bay.x1, 0, (bay.z0 + bay.z1) / 2), YELLOW, marks)
	for x = bay.x0 + 3, bay.x1 - 3, 5 do -- hatch along the dock side
		paint("BayHatch", Vector3.new(0.5, 0, 4), Vector3.new(x, 0, bay.z0 + 2.4), YELLOW, marks, math.rad(35))
	end
	groundWords(marks, "LOADING BAY", Vector3.new(-105, 0, -451), Vector2.new(5, 30), -math.pi / 2, YELLOW)
	local white = C(240, 240, 235)
	for _, x in { -60, -78, -132, -150 } do
		arrow(marks, Vector3.new(x, 0, LANE_Z), Vector3.new(-1, 0, 0), white)
	end
	arrow(marks, Vector3.new(ENTRY_X, 0, -438), Vector3.new(0, 0, -1), white) -- in: north, off the street
	arrow(marks, Vector3.new(EXIT_X, 0, -440), Vector3.new(0, 0, 1), white) -- out: south, onto the street
	groundWords(marks, "IN", Vector3.new(ENTRY_X, 0, -446), Vector2.new(4, 10), -math.pi / 2, white)
	groundWords(marks, "OUT", Vector3.new(EXIT_X, 0, -448), Vector2.new(4, 10), -math.pi / 2, white)
	-- curb lines along the lane's street side between the driveways (where trucks shouldn't cut across)
	local edgeW = (ENTRY_X - DRIVE_W / 2) - (EXIT_X + DRIVE_W / 2)
	paint("LaneEdge", Vector3.new(edgeW, 0, 0.4), Vector3.new((ENTRY_X + EXIT_X) / 2, 0, -435), white, marks)

	-- The loadable stacks on the dock (big pallet loads)
	local stacks = {
		{ item = "Lumber", x = -124, color = C(200, 160, 110), mat = M.WoodPlanks },
		{ item = "Lumber", x = -114, color = C(200, 160, 110), mat = M.WoodPlanks },
		{ item = "Sheet", x = -96, color = C(120, 120, 130), mat = M.CorrodedMetal },
		{ item = "Sheet", x = -86, color = C(120, 120, 130), mat = M.CorrodedMetal },
	}
	for _, s in stacks do
		local st = Instance.new("Model")
		st.Name = "Stack_" .. s.item
		box("Pallet", Vector3.new(6, 0.5, 5), CFrame.new(s.x, 2.25, -475), C(160, 125, 85), M.Wood, st)
		local load = box("Load", Vector3.new(5.4, 2.8, 4.4), CFrame.new(s.x, 3.9, -475), s.color, s.mat, st)
		load:SetAttribute("MaterialStack", s.item)
		for _, y in { 3.2, 4.6 } do
			box("Strap", Vector3.new(0.2, 0.15, 4.5), CFrame.new(s.x - 1.5, y, -475), C(40, 40, 40), M.Fabric, st, false)
			box("Strap", Vector3.new(0.2, 0.15, 4.5), CFrame.new(s.x + 1.5, y, -475), C(40, 40, 40), M.Fabric, st, false)
		end
		local tag = box("Tag", Vector3.new(4, 1.2, 0.1), CFrame.new(s.x, 6, -472.7), C(250, 250, 245), M.Fabric, st, false)
		text(tag, Enum.NormalId.Back, { { string.upper(s.item), 1, C(30, 30, 30) } }, 40)
		st.Parent = root
	end

	-- Lumber racks along the back, clear of both driveways
	rack(root, Vector3.new(-152, 0, -482), 24, C(200, 160, 110), M.WoodPlanks, 3)
	rack(root, Vector3.new(-58, 0, -482), 24, C(130, 130, 138), M.CorrodedMetal, 3)
	-- Loose pallets and bagged concrete on the outside edges (out of the truck's way)
	for i, p in { Vector3.new(-168, 0, -470), Vector3.new(-168, 0, -463), Vector3.new(-35, 0, -470), Vector3.new(-35, 0, -463) } do
		box("Pallet", Vector3.new(4, 0.5, 4), CFrame.new(p + Vector3.new(0, 0.25, 0)), C(160, 125, 85), M.Wood, root)
		if i % 2 == 1 then
			box("Bags", Vector3.new(3.6, 2, 3.6), CFrame.new(p + Vector3.new(0, 1.5, 0)), C(200, 195, 185), M.Fabric, root)
		end
	end
	forklift(root, CFrame.new(-146, 0, -473) * CFrame.Angles(0, math.pi / 2, 0))
	for _, p in { Vector3.new(-140, 0, -466), Vector3.new(-70, 0, -466), Vector3.new(ENTRY_X - 12, 0, -434), Vector3.new(EXIT_X + 12, 0, -434) } do
		cone(root, p)
	end

	-- Street side: the big sign on the grass between the two driveways, IN / OUT signs, hedges
	box("PylonPost", Vector3.new(1.2, 22, 1.2), CFrame.new(-108, 11, -429), steel, M.Metal, root)
	box("PylonPost", Vector3.new(1.2, 22, 1.2), CFrame.new(-92, 11, -429), steel, M.Metal, root)
	local pylon = box("Pylon", Vector3.new(20, 9, 1), CFrame.new(-100, 17, -429), ORANGE, M.Metal, root)
	text(pylon, Enum.NormalId.Back, {
		{ "CREW SUPPLY", 0.5, C(255, 255, 255) },
		{ "JOB MATERIALS - DRIVE-THROUGH LOADING", 0.28, C(30, 30, 30) },
	}, 24)
	local pylonLight = deco("PylonLight", Vector3.new(18, 0.3, 0.6), CFrame.new(-100, 22, -428), WARM, M.Neon, root)
	nightLamp(pylonLight, 20, 1.2)
	for _, s in { { x = ENTRY_X - DRIVE_W / 2 - 3, words = "ENTER", sub = "loading lane", col = C(60, 160, 80) },
		{ x = EXIT_X + DRIVE_W / 2 + 3, words = "EXIT", sub = "back to Main St", col = C(190, 60, 50) } } do
		box("SignPost", Vector3.new(0.5, 7, 0.5), CFrame.new(s.x, 3.5, -429), steel, M.Metal, root)
		local plate = box("DriveSign", Vector3.new(5, 3, 0.3), CFrame.new(s.x, 6.2, -429), s.col, M.Metal, root)
		text(plate, Enum.NormalId.Back, { { s.words, 0.6, C(255, 255, 255) }, { s.sub, 0.35, C(255, 255, 255) } }, 30)
		local lamp = deco("SignLamp", Vector3.new(4, 0.2, 0.4), CFrame.new(s.x, 7.85, -428.7), WARM, M.Neon, root)
		nightLamp(lamp, 10, 0.8)
	end
	local hedges = Instance.new("Model")
	hedges.Name = "Hedges"
	hedges.Parent = root
	hedge(hedges, EXIT_X + DRIVE_W / 2 + 6, -110, -429.5)
	hedge(hedges, -90, ENTRY_X - DRIVE_W / 2 - 6, -429.5)

	-- Staff parking east of the store (the town's parked cars move here)
	for k = 0, 3 do
		deco("StaffLine", Vector3.new(14, 0.05, 0.4), CFrame.new(-46, 0.06, -494 - k * 12), C(235, 235, 230), M.Concrete, root)
	end
	local staff = box("StaffSign", Vector3.new(0.3, 2, 5), CFrame.new(-33, 3, -496), C(40, 70, 130), M.Metal, root)
	text(staff, Enum.NormalId.Left, { { "STAFF PARKING", 1, C(255, 255, 255) } }, 30)
	box("StaffSignPost", Vector3.new(0.3, 2, 0.3), CFrame.new(-33, 1, -496), steel, M.Metal, root)

	root.Parent = workspace
	terrain()
	local c = curbs()
	local t = moveTownLife()
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return ("SupplyStore rebuilt: %d parts; %s; %s"):format(n, c, t)
end

return Builder
