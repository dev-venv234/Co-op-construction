--!strict
-- DEV TOOL (never required by game code). Builds the town's filler buildings in Workspace.Filler from the
-- "Filler" lots in TownLayout: a gas station, a hardware store and six houses. Each building faces its road
-- gate. Real materials only (no Plastic). Lights carry the NightLight attribute so the day/night cycle
-- switches them. Run in Studio Edit mode:  require(game.ServerStorage.DevTools.FillerBuilder).All()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.TownLayout) :: any

local Builder = {}

local terrain = workspace.Terrain
local FILL_TOP = -2 -- same rule as TownBuilder: walkable ground ends up at y = 0
local C = Color3.fromRGB
local M = Enum.Material
local WARM = C(255, 205, 150)
local HALF_ROAD = Layout.RoadWidth / 2

local roadsByName: { [string]: any } = {}
for _, r in Layout.Roads do
	roadsByName[r.Name] = r
end

local function box(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance, collide: boolean?): BasePart
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

local function wedge(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material
	w.Parent = parent
	return w
end

local function paint(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function glow(part: BasePart, kind: string, range: number, brightness: number)
	local l = if kind == "spot" then Instance.new("SpotLight") else Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = WARM
	l.Shadows = false
	if l:IsA("SpotLight") then
		l.Face = Enum.NormalId.Bottom
		l.Angle = 120
	end
	l.Parent = part
	part:SetAttribute("NightLight", true)
end

local function sign(part: BasePart, face: Enum.NormalId, lines: { { text: string, size: number, color: Color3? } }, bg: Color3?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0.3
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sg
	for i, line in lines do
		local t = Instance.new("TextLabel")
		t.LayoutOrder = i
		t.Size = UDim2.new(1, 0, line.size, 0)
		t.BackgroundTransparency = if bg then 0 else 1
		t.BackgroundColor3 = bg or C(0, 0, 0)
		t.BorderSizePixel = 0
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = line.color or C(250, 248, 240)
		t.Text = line.text
		t.Parent = sg
	end
	sg.Parent = part
end

local function fillRect(minX: number, minZ: number, maxX: number, maxZ: number, material: Enum.Material)
	terrain:FillBlock(
		CFrame.new((minX + maxX) / 2, FILL_TOP - 4, (minZ + maxZ) / 2),
		Vector3.new(maxX - minX, 8, maxZ - minZ),
		material
	)
end

-- Local frame for a lot: origin at the lot center, local -Z pointing at the road gate.
local function frameOf(lot: any): (CFrame, number, number)
	local center = Vector3.new((lot.Min.X + lot.Max.X) / 2, 0, (lot.Min.Y + lot.Max.Y) / 2)
	local g = lot.Gate
	local r = roadsByName[g.Road]
	local gatePoint = if r.Axis == "X" then Vector3.new(g.At, 0, r.At) else Vector3.new(r.At, 0, g.At)
	local O = CFrame.lookAt(center, Vector3.new(gatePoint.X, 0, gatePoint.Z))
	local sideways = r.Axis == "Z"
	local wx, wz = (lot.Max.X - lot.Min.X) / 2, (lot.Max.Y - lot.Min.Y) / 2
	return O, if sideways then wz else wx, if sideways then wx else wz
end

local function tree(parent: Instance, O: CFrame, x: number, z: number, scale: number)
	local m = Instance.new("Model")
	m.Name = "Tree"
	local trunk = box("Trunk", Vector3.new(8 * scale, 1.3 * scale, 1.3 * scale), O * CFrame.new(x, 4 * scale, z) * CFrame.Angles(0, 0, math.pi / 2),
		C(105, 75, 50), M.Wood, m)
	trunk.Shape = Enum.PartType.Cylinder
	local leaves = box("Leaves", Vector3.new(9, 9, 9) * scale, O * CFrame.new(x, 10 * scale, z), C(70, 120, 55), M.LeafyGrass, m, false)
	leaves.Shape = Enum.PartType.Ball
	local leaves2 = box("Leaves", Vector3.new(6.5, 6.5, 6.5) * scale, O * CFrame.new(x + 2 * scale, 13 * scale, z + 1 * scale), C(80, 135, 60), M.LeafyGrass, m, false)
	leaves2.Shape = Enum.PartType.Ball
	m.Parent = parent
end

local function lightPole(parent: Instance, O: CFrame, x: number, z: number, height: number)
	local pole = box("LightPole", Vector3.new(height, 0.7, 0.7), O * CFrame.new(x, height / 2, z) * CFrame.Angles(0, 0, math.pi / 2),
		C(70, 72, 76), M.Metal, parent)
	pole.Shape = Enum.PartType.Cylinder
	local lens = box("Lens", Vector3.new(2, 0.3, 2), O * CFrame.new(x, height + 0.2, z), WARM, M.Neon, parent)
	paint(lens)
	glow(lens, "spot", 55, 2.5)
end

local function buildGasStation(lot: any, parent: Instance)
	local O, hx, hz = frameOf(lot)
	local m = Instance.new("Model")
	m.Name = lot.Id
	local function at(x: number, y: number, z: number): CFrame
		return O * CFrame.new(x, y, z)
	end
	fillRect(lot.Min.X, lot.Min.Y, lot.Max.X, lot.Max.Y, M.Asphalt)

	-- Canopy over two pump islands
	for _, px in { -16, 16 } do
		for _, pz in { -30, -10 } do
			box("CanopyPost", Vector3.new(1.2, 14, 1.2), at(px, 7, pz), C(235, 235, 235), M.Metal, m)
		end
	end
	box("CanopyRoof", Vector3.new(42, 1.4, 28), at(0, 14.7, -20), C(240, 240, 240), M.Metal, m)
	box("CanopyTrim", Vector3.new(42.4, 0.9, 28.4), at(0, 13.8, -20), C(200, 40, 40), M.Metal, m)
	for _, lx in { -12, 0, 12 } do
		local panel = box("CanopyLight", Vector3.new(5, 0.2, 2), at(lx, 13.25, -20), WARM, M.Neon, m)
		paint(panel)
		glow(panel, "spot", 30, 2)
	end
	for _, ix in { -8, 8 } do
		box("Island", Vector3.new(3, 0.6, 12), at(ix, 0.3, -20), C(170, 170, 165), M.Concrete, m)
		for _, pz in { -24, -16 } do
			box("Pump", Vector3.new(2.2, 5, 1.4), at(ix, 3.1, pz), C(200, 45, 45), M.Metal, m)
			box("PumpScreen", Vector3.new(1.4, 1, 1.5), at(ix, 4.2, pz), C(30, 40, 50), M.Glass, m)
			box("Hose", Vector3.new(0.3, 3, 0.3), at(ix + 1.2, 2.6, pz), C(30, 30, 30), M.Rubber, m)
		end
	end

	-- Shop at the back
	local sz = 34
	box("Floor", Vector3.new(38, 0.4, 20), at(0, 0.2, sz), C(165, 160, 155), M.Concrete, m)
	box("BackWall", Vector3.new(38, 9, 0.8), at(0, 4.9, sz + 9.6), C(170, 90, 70), M.Brick, m)
	for _, sx in { -18.6, 18.6 } do
		box("SideWall", Vector3.new(0.8, 9, 20), at(sx, 4.9, sz), C(170, 90, 70), M.Brick, m)
	end
	box("Storefront", Vector3.new(36.4, 6, 0.3), at(0, 3.4, sz - 9.6), C(60, 80, 95), M.Glass, m).Transparency = 0.35
	box("Header", Vector3.new(38, 3, 0.8), at(0, 7.9, sz - 9.6), C(170, 90, 70), M.Brick, m)
	box("Roof", Vector3.new(39, 0.6, 21), at(0, 9.7, sz), C(130, 130, 128), M.Concrete, m)
	local shopSign = box("ShopSign", Vector3.new(22, 3, 0.4), at(0, 11.6, sz - 9.8), C(200, 40, 40), M.Metal, m)
	sign(shopSign, Enum.NormalId.Front, { { text = "QUICK STOP  -  GAS & SNACKS", size = 1 } })
	local open = box("OpenSign", Vector3.new(3, 1.2, 0.2), at(9, 5.5, sz - 9.85), C(255, 90, 60), M.Neon, m)
	paint(open)
	glow(open, "point", 12, 1)

	-- Price pylon by the road
	local pylonX, pylonZ = -hx + 10, -hz + 8
	box("PylonPole", Vector3.new(1, 16, 1), at(pylonX, 8, pylonZ), C(70, 72, 76), M.Metal, m)
	local board = box("PriceBoard", Vector3.new(9, 6, 0.6), at(pylonX, 15, pylonZ), C(240, 240, 240), M.Metal, m)
	sign(board, Enum.NormalId.Front, {
		{ text = "QUICK STOP", size = 0.34, color = C(200, 40, 40) },
		{ text = "REGULAR 3.49", size = 0.33, color = C(30, 30, 30) },
		{ text = "DIESEL 3.89", size = 0.33, color = C(30, 30, 30) },
	})
	lightPole(m, O, hx - 8, -hz + 10, 16)
	tree(m, O, hx - 10, hz - 10, 1)
	tree(m, O, -hx + 10, hz - 12, 0.9)
	m.Parent = parent
end

local function buildHardware(lot: any, parent: Instance)
	local O, hx, hz = frameOf(lot)
	local m = Instance.new("Model")
	m.Name = lot.Id
	local function at(x: number, y: number, z: number): CFrame
		return O * CFrame.new(x, y, z)
	end
	fillRect(lot.Min.X, lot.Min.Y, lot.Max.X, lot.Max.Y, M.Asphalt)

	local bz, bw, bd, bh = 22, 76, 40, 18
	local wall = C(205, 200, 185)
	box("BackWall", Vector3.new(bw, bh, 1), at(0, bh / 2, bz + bd / 2), wall, M.Concrete, m)
	for _, sx in { -bw / 2, bw / 2 } do
		box("SideWall", Vector3.new(1, bh, bd), at(sx, bh / 2, bz), wall, M.Concrete, m)
	end
	local fz = bz - bd / 2
	box("FrontLeft", Vector3.new(bw / 2 - 7, bh, 1), at(-(bw / 4 + 3.5), bh / 2, fz), wall, M.Concrete, m)
	box("FrontRight", Vector3.new(bw / 2 - 7, bh, 1), at(bw / 4 + 3.5, bh / 2, fz), wall, M.Concrete, m)
	box("FrontHeader", Vector3.new(14, bh - 9, 1), at(0, 9 + (bh - 9) / 2, fz), wall, M.Concrete, m)
	box("Entrance", Vector3.new(14, 9, 0.4), at(0, 4.5, fz), C(60, 80, 95), M.Glass, m).Transparency = 0.35
	box("Roof", Vector3.new(bw + 1, 0.8, bd + 1), at(0, bh + 0.4, bz), C(110, 115, 120), M.CorrodedMetal, m)
	box("Floor", Vector3.new(bw, 0.4, bd), at(0, 0.2, bz), C(160, 155, 150), M.Concrete, m)
	box("EntryCanopy", Vector3.new(18, 0.5, 6), at(0, 10.2, fz - 3), C(230, 120, 30), M.Metal, m)
	local banner = box("StoreSign", Vector3.new(40, 5, 0.5), at(0, 14.5, fz - 0.8), C(230, 120, 30), M.Metal, m)
	sign(banner, Enum.NormalId.Front, { { text = "HARDWARE & LUMBER", size = 1 } })
	local entryLight = box("EntryLight", Vector3.new(10, 0.2, 2), at(0, 9.85, fz - 3), WARM, M.Neon, m)
	paint(entryLight)
	glow(entryLight, "spot", 25, 2)

	-- Parking stalls in front
	for k = 0, 8 do
		local x = -48 + k * 12
		paint(box("StallLine", Vector3.new(0.4, 0.05, 16), at(x, 0.1, -hz + 22), C(235, 235, 230), M.Concrete, m))
	end
	-- Lumber yard racks on the side
	for k = 0, 2 do
		local rz = 2 + k * 14
		local rx = bw / 2 + 12
		for _, o in { -4, 4 } do
			box("RackPost", Vector3.new(0.6, 8, 0.6), at(rx + o, 4, rz), C(70, 72, 76), M.Metal, m)
		end
		box("RackShelf", Vector3.new(9, 0.4, 3), at(rx, 3.5, rz), C(70, 72, 76), M.Metal, m)
		box("Boards", Vector3.new(8.4, 1.6, 2.6), at(rx, 4.5, rz), C(205, 165, 115), M.WoodPlanks, m)
		box("Boards", Vector3.new(8.4, 1.4, 2.6), at(rx, 1.2, rz), C(190, 150, 100), M.WoodPlanks, m)
	end
	-- Cart corral and light poles
	box("CartCorral", Vector3.new(4, 3, 10), at(-hx + 18, 1.5, -hz + 30), C(160, 165, 170), M.DiamondPlate, m).Transparency = 0.3
	lightPole(m, O, -hx + 10, -hz + 10, 18)
	lightPole(m, O, hx - 10, -hz + 10, 18)
	m.Parent = parent
end

local HOUSE_WALLS = { C(225, 215, 190), C(185, 205, 220), C(215, 190, 175), C(200, 215, 185), C(235, 230, 220), C(190, 180, 200) }
local HOUSE_ROOFS = { M.RoofShingles, M.ClayRoofTiles }

local function buildHouse(lot: any, parent: Instance, k: number)
	local O, hx, hz = frameOf(lot)
	local m = Instance.new("Model")
	m.Name = lot.Id
	local function at(x: number, y: number, z: number): CFrame
		return O * CFrame.new(x, y, z)
	end
	local wallColor = HOUSE_WALLS[(k - 1) % #HOUSE_WALLS + 1]
	local wallMat = if k % 2 == 0 then M.WoodPlanks else M.Plaster
	local roofMat = HOUSE_ROOFS[(k - 1) % #HOUSE_ROOFS + 1]
	local roofColor = if roofMat == M.ClayRoofTiles then C(170, 85, 60) else C(70, 70, 75)
	local W, D, H = 24, 18, 10
	local cz = 8
	local front = cz - D / 2

	-- Driveway / walk from the gate to the porch (terrain)
	for zz = -hz, front - 4, 4 do
		local p = O:PointToWorldSpace(Vector3.new(0, 0, zz + 2))
		fillRect(p.X - 3, p.Z - 3, p.X + 3, p.Z + 3, M.Concrete)
	end

	box("Foundation", Vector3.new(W + 1, 0.8, D + 1), at(0, 0.4, cz), C(150, 145, 140), M.Concrete, m)
	box("WallBack", Vector3.new(W, H, 0.6), at(0, 0.8 + H / 2, cz + D / 2), wallColor, wallMat, m)
	for _, sx in { -W / 2, W / 2 } do
		box("WallSide", Vector3.new(0.6, H, D), at(sx, 0.8 + H / 2, cz), wallColor, wallMat, m)
	end
	box("WallFrontL", Vector3.new(W / 2 - 2, H, 0.6), at(-(W / 4 + 1), 0.8 + H / 2, front), wallColor, wallMat, m)
	box("WallFrontR", Vector3.new(W / 2 - 2, H, 0.6), at(W / 4 + 1, 0.8 + H / 2, front), wallColor, wallMat, m)
	box("WallFrontTop", Vector3.new(4, H - 7, 0.6), at(0, 0.8 + 7 + (H - 7) / 2, front), wallColor, wallMat, m)
	box("Door", Vector3.new(3.6, 7, 0.3), at(0, 0.8 + 3.5, front), C(110, 70, 45), M.Wood, m)
	for _, wx in { -7, 7 } do
		box("Window", Vector3.new(4, 3.4, 0.3), at(wx, 5.6, front - 0.2), C(60, 85, 105), M.Glass, m).Transparency = 0.25
		box("WindowBack", Vector3.new(4, 3.4, 0.3), at(wx, 5.6, cz + D / 2 + 0.2), C(60, 85, 105), M.Glass, m).Transparency = 0.25
	end

	-- Gable roof: two sloped halves plus wedge gable ends
	local top = 0.8 + H
	local a = math.rad(30)
	local rise = (D / 2) * math.tan(a)
	local slope = (D / 2 + 1) / math.cos(a)
	box("RoofFront", Vector3.new(W + 2, 0.6, slope), at(0, top + rise / 2, cz - D / 4 - 0.4) * CFrame.Angles(-a, 0, 0), roofColor, roofMat, m)
	box("RoofBack", Vector3.new(W + 2, 0.6, slope), at(0, top + rise / 2, cz + D / 4 + 0.4) * CFrame.Angles(a, 0, 0), roofColor, roofMat, m)
	for _, ex in { -W / 2, W / 2 } do
		wedge("Gable", Vector3.new(0.6, rise, D / 2), at(ex, top + rise / 2, cz - D / 4), wallColor, wallMat, m)
		wedge("Gable", Vector3.new(0.6, rise, D / 2), at(ex, top + rise / 2, cz + D / 4) * CFrame.Angles(0, math.pi, 0), wallColor, wallMat, m)
	end

	-- Porch, porch light, mailbox, picket fence, trees
	box("Porch", Vector3.new(10, 0.6, 5), at(0, 0.5, front - 2.5), C(150, 115, 80), M.WoodPlanks, m)
	for _, px in { -4.6, 4.6 } do
		box("PorchPost", Vector3.new(0.5, 7.5, 0.5), at(px, 4.5, front - 4.7), C(235, 235, 230), M.Wood, m)
	end
	box("PorchRoof", Vector3.new(11, 0.4, 5.6), at(0, 8.4, front - 2.6), roofColor, roofMat, m)
	local porchLight = box("PorchLight", Vector3.new(0.5, 0.7, 0.5), at(2.6, 7.2, front - 0.4), WARM, M.Neon, m)
	paint(porchLight)
	glow(porchLight, "point", 16, 1.1)
	box("MailboxPost", Vector3.new(0.4, 3.5, 0.4), at(6, 1.75, -hz + 3), C(110, 80, 50), M.Wood, m)
	box("Mailbox", Vector3.new(1, 1, 1.8), at(6, 3.9, -hz + 3), C(60, 60, 65), M.Metal, m)
	local fz = -hz + 1.5
	for _, side in { -1, 1 } do
		local len = hx - 6
		local cx = side * (6 + len / 2)
		box("FenceRail", Vector3.new(len, 0.3, 0.2), at(cx, 2.4, fz), C(240, 240, 235), M.Wood, m)
		box("FenceRail", Vector3.new(len, 0.3, 0.2), at(cx, 1.2, fz), C(240, 240, 235), M.Wood, m)
		for i = 0, math.floor(len / 2) do
			box("Picket", Vector3.new(0.4, 3, 0.15), at(side * (6 + i * 2), 1.5, fz + 0.1), C(240, 240, 235), M.Wood, m)
		end
	end
	tree(m, O, -hx + 10, -hz + 14, 1)
	tree(m, O, hx - 9, cz + 14, 0.85)
	m.Parent = parent
end

function Builder.All(): string
	local old = workspace:FindFirstChild("Filler")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Filler"
	root.Parent = workspace
	local built = {}
	local houses = 0
	for _, lot in Layout.Lots do
		if lot.Kind == "Filler" then
			if lot.Id == "GasStation" then
				buildGasStation(lot, root)
			elseif lot.Id == "Hardware" then
				buildHardware(lot, root)
			else
				houses += 1
				buildHouse(lot, root, houses)
			end
			table.insert(built, lot.Id)
			local lots = workspace:FindFirstChild("Town") and workspace.Town:FindFirstChild("Lots")
			local marker = lots and lots:FindFirstChild(lot.Id)
			local temp = marker and marker:FindFirstChild("TempSign")
			if temp then
				temp:Destroy()
			end
			task.wait()
		end
	end
	local parts, plastic = 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			if d.Material == M.Plastic or d.Material == M.SmoothPlastic then
				plastic += 1
			end
		end
	end
	return ("filler built: %s (%d parts, %d plastic)"):format(table.concat(built, ", "), parts, plastic)
end

return Builder
