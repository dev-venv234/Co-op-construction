--!strict
-- DEV TOOL (never required by game code). Builds Workspace.RVPark inside the RVPark lot from TownLayout:
-- RV campsites (with spawn points), coffee stand, truck lot (stalls + site board), loading area, fence,
-- entrance arch, lamps and a campfire. Map only: the coffee prompt is added at runtime by BuffService.
-- Run in Studio Edit mode:  require(game.ServerStorage.DevTools.RVParkBuilder).All()
-- Safe to re-run: it repaints the park ground and replaces Workspace.RVPark.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.TownLayout) :: any
local Sites = require(ReplicatedStorage.Shared.Config.Sites) :: any

local Builder = {}

local terrain = workspace.Terrain
local FILL_TOP = -2 -- same rule as TownBuilder: walkable ground ends up at y = 0

local LOT
for _, lot in Layout.Lots do
	if lot.Id == "RVPark" then
		LOT = lot
	end
end
assert(LOT, "TownLayout has no RVPark lot")
local X0, Z0, X1, Z1 = LOT.Min.X, LOT.Min.Y, LOT.Max.X, LOT.Max.Y -- -160, -372, 160, -180

-- Ground plan (x, z ranges inside the lot)
local ENTRY = { -12, -372, 12, -232 } -- entry road from the Main St gate
local LANE = { -156, -296, -12, -280 } -- campground lane
local NORTH_PADS = { { -156, -128 }, { -124, -96 }, { -92, -64 } } -- z -340..-300
local SOUTH_PADS = { { -156, -128 }, { -124, -96 }, { -92, -64 }, { -60, -32 } } -- z -276..-236
local PATIO = { -60, -368, -20, -328 } -- coffee patio
local TRUCK_LOT = { 12, -368, 124, -276 }
local LOADING = { 124, -368, 156, -276 }
local PATH = { -4, -232, 4, -8 } -- footpath south to the gray-box yard

local C = Color3.fromRGB
local M = Enum.Material

local function fillRect(r: { number }, material: Enum.Material)
	terrain:FillBlock(
		CFrame.new((r[1] + r[3]) / 2, FILL_TOP - 4, (r[2] + r[4]) / 2),
		Vector3.new(r[3] - r[1], 8, r[4] - r[2]),
		material
	)
end

local function box(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance, collide: boolean?): Part
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

local function cyl(name: string, length: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = box(name, Vector3.new(length, diameter, diameter), cf, color, material, parent)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function wedgePart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): BasePart
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

local function vertical(pos: Vector3): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
end

local function paint(p: Part)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local WARM = C(255, 205, 150)

local function lamp(parent: Instance, pos: Vector3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = WARM
	l.Shadows = false
	l.Parent = parent
	if parent:IsA("BasePart") then
		parent:SetAttribute("NightLight", true)
	end
	return l
end

local function surfaceText(part: BasePart, face: Enum.NormalId, lines: { { text: string, size: number, color: Color3? } }, ppStud: number?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppStud or 40
	sg.LightInfluence = 0.3
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sg
	for i, line in lines do
		local t = Instance.new("TextLabel")
		t.LayoutOrder = i
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, line.size, 0)
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = line.color or C(250, 245, 230)
		t.Text = line.text
		t.Parent = sg
	end
	sg.Parent = part
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- RV: long axis along Z, door on the east (+X) side. `base` is the ground point under the RV center.
local RV_COLORS = { C(225, 220, 205), C(235, 232, 225), C(215, 210, 190), C(230, 225, 215) }
local STRIPES = { C(120, 70, 45), C(40, 95, 120), C(150, 45, 40), C(70, 110, 70) }
local AWNINGS = { C(60, 120, 160), C(180, 70, 60), C(80, 140, 90), C(200, 160, 60) }

local function buildRV(parent: Instance, index: number, base: Vector3)
	local m = model("RV_" .. index, parent)
	local cf = CFrame.new(base)
	local k = (index - 1) % 4 + 1
	local body = box("Body", Vector3.new(8.5, 8, 26), cf * CFrame.new(0, 5, 0), RV_COLORS[k], M.Metal, m)
	m.PrimaryPart = body
	box("Roof", Vector3.new(8.8, 0.4, 26.3), cf * CFrame.new(0, 9.2, 0), C(240, 240, 238), M.Metal, m)
	box("Stripe", Vector3.new(8.6, 0.8, 26.1), cf * CFrame.new(0, 4, 0), STRIPES[k], M.Metal, m)
	box("Skirt", Vector3.new(8.2, 0.8, 24), cf * CFrame.new(0, 0.7, 0), C(60, 60, 62), M.Metal, m)
	local glass = C(40, 55, 70)
	box("Windshield", Vector3.new(7.4, 2.6, 0.2), cf * CFrame.new(0, 6.6, -13.05), glass, M.Glass, m).Transparency = 0.2
	for _, side in { -1, 1 } do
		for _, z in { -8, 0, 8 } do
			if not (side == 1 and z == 0) then -- leave room for the door
				box("Window", Vector3.new(0.2, 2, 3.6), cf * CFrame.new(side * 4.3, 6.6, z), glass, M.Glass, m).Transparency = 0.2
			end
		end
	end
	box("Door", Vector3.new(0.2, 6.2, 2.8), cf * CFrame.new(4.32, 4.3, 3), C(150, 145, 135), M.Metal, m)
	box("DoorWindow", Vector3.new(0.22, 1.4, 1.6), cf * CFrame.new(4.34, 6, 3), glass, M.Glass, m)
	box("Step", Vector3.new(1.6, 0.5, 2.8), cf * CFrame.new(5.2, 0.75, 3), C(110, 80, 50), M.Wood, m)
	for _, wx in { -4.1, 4.1 } do
		for _, wz in { -8, 8 } do
			cyl("Wheel", 1, 2.6, cf * CFrame.new(wx, 1.3, wz), C(35, 35, 37), M.Metal, m)
		end
	end
	local awning = box("Awning", Vector3.new(4.2, 0.2, 11), cf * CFrame.new(6.4, 8.3, 3) * CFrame.Angles(0, 0, -0.18), AWNINGS[k], M.Fabric, m)
	paint(awning)
	local porch = box("PorchLight", Vector3.new(0.4, 0.6, 0.4), cf * CFrame.new(4.5, 7.6, 5.2), WARM, M.Neon, m)
	paint(porch)
	lamp(porch, porch.Position, 16, 1.2)

	-- Detail: rounded front cap, framed windows, roof A/C and vent, rear ladder, storage doors, lights,
	-- propane tanks and hitch, awning arms, wheel hubs and fender skirts.
	local frame = C(55, 55, 58)
	local white = C(240, 240, 238)
	wedgePart("FrontCap", Vector3.new(8.5, 1.6, 2.2), cf * CFrame.new(0, 8.4, -14.1), RV_COLORS[k], M.Metal, m)
	wedgePart("NoseCap", Vector3.new(8.5, 1.2, 1.0), cf * CFrame.new(0, 1.7, -13.5) * CFrame.Angles(math.pi, 0, 0), RV_COLORS[k], M.Metal, m)
	for _, side in { -1, 1 } do
		for _, z in { -8, 0, 8 } do
			if not (side == 1 and z == 0) then
				box("WindowFrame", Vector3.new(0.1, 2.4, 4.0), cf * CFrame.new(side * 4.27, 6.6, z), frame, M.Metal, m)
			end
		end
		box("StorageDoor", Vector3.new(0.1, 1.4, 2.6), cf * CFrame.new(side * 4.28, 2.3, -8.5), C(200, 200, 196), M.Metal, m)
		box("StorageDoor", Vector3.new(0.1, 1.4, 2.6), cf * CFrame.new(side * 4.28, 2.3, 9.5), C(200, 200, 196), M.Metal, m)
		box("FenderSkirt", Vector3.new(0.15, 1.2, 3.4), cf * CFrame.new(side * 4.32, 2.3, 8), RV_COLORS[k], M.Metal, m)
		box("FenderSkirt", Vector3.new(0.15, 1.2, 3.4), cf * CFrame.new(side * 4.32, 2.3, -8), RV_COLORS[k], M.Metal, m)
		paint(box("TailLight", Vector3.new(1.2, 0.5, 0.1), cf * CFrame.new(side * 3.4, 2.4, 13.08), C(210, 30, 30), M.Neon, m))
		paint(box("MarkerLight", Vector3.new(0.3, 0.3, 0.1), cf * CFrame.new(side * 3.9, 8.9, -13.08), C(255, 170, 40), M.Neon, m))
		for _, wz in { -8, 8 } do
			cyl("Hub", 1.06, 1.3, cf * CFrame.new(side * 4.1, 1.3, wz), C(190, 190, 195), M.Metal, m)
		end
	end
	box("AirConditioner", Vector3.new(3, 1.0, 3.6), cf * CFrame.new(0, 9.9, 2), white, M.Metal, m)
	box("RoofVent", Vector3.new(1.6, 0.5, 1.6), cf * CFrame.new(0, 9.65, -7), white, M.Metal, m)
	for _, lx in { -3.1, -1.9 } do
		box("LadderRail", Vector3.new(0.15, 8.6, 0.15), cf * CFrame.new(lx, 5.3, 13.25), frame, M.Metal, m)
	end
	for y = 2, 9, 1.2 do
		box("LadderRung", Vector3.new(1.3, 0.12, 0.12), cf * CFrame.new(-2.5, y, 13.25), frame, M.Metal, m)
	end
	box("DoorHandle", Vector3.new(0.1, 0.2, 0.5), cf * CFrame.new(4.45, 4.4, 4), C(200, 200, 205), M.Metal, m)
	for _, az in { -2.3, 8.3 } do
		box("AwningArm", Vector3.new(0.15, 6.4, 0.15), cf * CFrame.new(8.2, 4.6, az) * CFrame.Angles(0, 0, 0.18), frame, M.Metal, m)
	end
	for _, px in { -1.1, 1.1 } do
		cyl("Propane", 1.7, 1.2, cf * CFrame.new(px, 1.7, -14.9) * CFrame.Angles(0, 0, math.pi / 2), white, M.Metal, m)
	end
	box("Hitch", Vector3.new(0.6, 0.4, 3.4), cf * CFrame.new(0, 0.9, -15.5), frame, M.Metal, m)
	box("JackStand", Vector3.new(0.3, 1.0, 0.3), cf * CFrame.new(0, 0.5, -16.6), frame, M.Metal, m)

	-- Picnic table beside the RV
	local t = CFrame.new(base + Vector3.new(11, 0, 3))
	box("TableTop", Vector3.new(3.4, 0.3, 6), t * CFrame.new(0, 2.6, 0), C(140, 100, 60), M.WoodPlanks, m)
	for _, bx in { -2.3, 2.3 } do
		box("Bench", Vector3.new(1, 0.3, 6), t * CFrame.new(bx, 1.5, 0), C(140, 100, 60), M.WoodPlanks, m)
	end
	for _, lz in { -2.3, 2.3 } do
		box("Legs", Vector3.new(4.6, 1.4, 0.4), t * CFrame.new(0, 0.7, lz), C(110, 80, 50), M.Wood, m)
		box("TableLeg", Vector3.new(0.4, 2.45, 0.4), t * CFrame.new(0, 1.22, lz), C(110, 80, 50), M.Wood, m)
	end

	-- Where this RV's owner spawns (used by the session flow in stage 4)
	local sp = box("SpawnPoint", Vector3.new(2, 1, 2), CFrame.new(base + Vector3.new(7.5, 0.5, 3)), C(255, 255, 255), M.Concrete, m, false)
	sp.Transparency = 1
	paint(sp)
	sp:SetAttribute("RVSpawn", index)
end

local function buildCoffeeStand(parent: Instance)
	local m = model("CoffeeStand", parent)
	local wood = C(150, 105, 65)
	local dark = C(70, 50, 35)
	-- Kiosk footprint x -48..-32, z -365..-355, serving window faces south (+Z)
	box("Floor", Vector3.new(16, 0.4, 10), CFrame.new(-40, 0.2, -360), C(160, 155, 150), M.Concrete, m)
	box("BackWall", Vector3.new(16, 8, 0.6), CFrame.new(-40, 4.4, -364.7), wood, M.WoodPlanks, m)
	box("WallW", Vector3.new(0.6, 8, 10), CFrame.new(-47.7, 4.4, -360), wood, M.WoodPlanks, m)
	box("WallE", Vector3.new(0.6, 8, 10), CFrame.new(-32.3, 4.4, -360), wood, M.WoodPlanks, m)
	box("FrontLower", Vector3.new(16, 3.6, 0.6), CFrame.new(-40, 2.2, -355.3), wood, M.WoodPlanks, m)
	box("FrontHeader", Vector3.new(16, 1.6, 0.6), CFrame.new(-40, 7.6, -355.3), wood, M.WoodPlanks, m)
	box("Roof", Vector3.new(18, 0.4, 13), CFrame.new(-40, 8.8, -359.5) * CFrame.Angles(math.rad(-4), 0, 0), C(95, 100, 105), M.CorrodedMetal, m)
	local awning = box("Awning", Vector3.new(16, 0.2, 4.4), CFrame.new(-40, 7.6, -352.9) * CFrame.Angles(math.rad(-16), 0, 0), C(170, 55, 45), M.Fabric, m)
	paint(awning)

	-- Counter: the coffee prompt attaches here at runtime (BuffService looks for the CoffeeCounter attribute)
	local counter = box("Counter", Vector3.new(16, 0.4, 2.4), CFrame.new(-40, 4.2, -354.6), C(120, 120, 118), M.Granite, m)
	counter:SetAttribute("CoffeeCounter", true)
	box("BackBench", Vector3.new(14, 3, 2), CFrame.new(-40, 1.9, -363), dark, M.WoodPlanks, m)
	box("Espresso", Vector3.new(2.4, 2.6, 1.6), CFrame.new(-44, 4.7, -363), C(180, 180, 185), M.Metal, m)
	box("Grinder", Vector3.new(1, 1.8, 1), CFrame.new(-41, 4.3, -363), C(40, 40, 42), M.Metal, m)
	for i = 0, 2 do
		cyl("Cups", 1.4, 0.6, vertical(Vector3.new(-36 + i * 0.8, 4.1, -363)), C(245, 240, 230), M.Fabric, m)
	end
	local inside = box("KioskLight", Vector3.new(1.2, 0.3, 1.2), CFrame.new(-40, 8.4, -360), WARM, M.Neon, m)
	paint(inside)
	lamp(inside, inside.Position, 22, 1.6)

	-- Menu sign on the roof front
	local sign = box("MenuSign", Vector3.new(10, 3, 0.4), CFrame.lookAt(Vector3.new(-40, 10.6, -355.4), Vector3.new(-40, 10.6, -340)), C(55, 40, 30), M.WoodPlanks, m)
	surfaceText(sign, Enum.NormalId.Front, {
		{ text = "COFFEE", size = 0.6, color = C(255, 220, 160) },
		{ text = "get AWAKE - work faster all job", size = 0.35 },
	})

	-- Patio tables
	for _, x in { -52, -28 } do
		local t = CFrame.new(x, 0, -337)
		box("PatioTable", Vector3.new(3.4, 0.3, 3.4), t * CFrame.new(0, 2.8, 0), C(70, 70, 72), M.Metal, m)
		cyl("PatioLeg", 2.7, 0.4, t * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.pi / 2), C(70, 70, 72), M.Metal, m)
		for _, s in { Vector3.new(-2.4, 0, 0), Vector3.new(2.4, 0, 0) } do
			box("Stool", Vector3.new(1.2, 1.8, 1.2), t * CFrame.new(s + Vector3.new(0, 0.9, 0)), C(140, 100, 60), M.Wood, m)
		end
		local umb = box("Umbrella", Vector3.new(6, 0.2, 6), t * CFrame.new(0, 7, 0), C(230, 220, 200), M.Fabric, m)
		paint(umb)
		cyl("UmbrellaPole", 4.2, 0.25, t * CFrame.new(0, 4.9, 0) * CFrame.Angles(0, 0, math.pi / 2), C(200, 200, 200), M.Metal, m)
	end
	box("TrashCan", Vector3.new(1.6, 2.6, 1.6), CFrame.new(-23, 1.3, -350), C(50, 75, 55), M.Metal, m)
end

local function buildTruckLot(parent: Instance)
	local m = model("TruckLot", parent)
	local white = C(235, 235, 230)
	-- 6 stalls along the south side of the lot, trucks parked nose-north
	for k = 0, 6 do
		local x = 28 + k * 14
		paint(box("StallLine", Vector3.new(0.4, 0.05, 24), CFrame.new(x, 0.1, -292), white, M.Concrete, m))
	end
	paint(box("StallBackLine", Vector3.new(84.4, 0.05, 0.4), CFrame.new(70, 0.1, -280), white, M.Concrete, m))
	for k = 1, 6 do
		local stall = box("Stall_" .. k, Vector3.new(7, 1, 14), CFrame.new(28 + (k - 0.5) * 14, 1.2, -292), white, M.Concrete, m, false)
		stall.Transparency = 1
		paint(stall)
		stall:SetAttribute("TruckStall", k)
		paint(box("StallNumber", Vector3.new(3, 0.05, 3), CFrame.new(28 + (k - 0.5) * 14, 0.1, -283), C(250, 200, 50), M.Concrete, m))
	end

	-- Site board (display only for now; picking a site comes with the session flow)
	local board = box("SiteBoard", Vector3.new(30, 12, 0.6), CFrame.lookAt(Vector3.new(68, 8, -365), Vector3.new(68, 8, -300)), C(40, 45, 50), M.Metal, m)
	board:SetAttribute("SiteBoard", true)
	local lines = { { text = "JOB SITES", size = 0.2, color = C(255, 200, 60) } }
	for _, s in Sites do
		local status = if s.Release == "Launch" then s.Unlock else "Coming soon"
		table.insert(lines, {
			text = ("%d  %s  |  %d min  |  %s each  |  %s"):format(s.Tier, string.upper(s.Name), s.Minutes, s.Pay, status),
			size = 0.15,
			color = if s.Release == "Launch" then C(240, 240, 235) else C(140, 140, 140),
		})
	end
	table.insert(lines, { text = "Coffee first, then load up at the dock", size = 0.12, color = C(170, 200, 230) })
	surfaceText(board, Enum.NormalId.Front, lines, 30)
	for _, x in { 55, 81 } do
		box("BoardPost", Vector3.new(0.8, 14, 0.8), CFrame.new(x, 7, -365.8), C(70, 72, 76), M.Metal, m)
	end
	box("BoardCanopy", Vector3.new(32, 0.4, 3), CFrame.new(68, 14.4, -365), C(95, 100, 105), M.CorrodedMetal, m)
	local boardLight = box("BoardLight", Vector3.new(20, 0.2, 0.4), CFrame.new(68, 14.1, -364), WARM, M.Neon, m)
	paint(boardLight)
	lamp(boardLight, boardLight.Position, 18, 1.5)

	-- Two floodlight poles
	for _, p in { Vector3.new(16, 0, -276), Vector3.new(120, 0, -366) } do
		cyl("FloodPole", 22, 1, vertical(p + Vector3.new(0, 11, 0)), C(70, 72, 76), M.Metal, m)
		box("FloodHead", Vector3.new(3, 0.8, 3), CFrame.new(p + Vector3.new(0, 22.2, 0)), C(70, 72, 76), M.Metal, m)
		local lens = box("FloodLens", Vector3.new(2.4, 0.15, 2.4), CFrame.new(p + Vector3.new(0, 21.75, 0)), WARM, M.Neon, m)
		paint(lens)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 120
		spot.Range = 60
		spot.Brightness = 3
		spot.Color = WARM
		spot.Shadows = false
		spot.Parent = lens
		lens:SetAttribute("NightLight", true)
	end
end

local function buildLoadingArea(parent: Instance)
	local m = model("LoadingArea", parent)
	local steel = C(70, 72, 76)
	for _, p in { Vector3.new(128, 0, -364), Vector3.new(152, 0, -364), Vector3.new(128, 0, -280), Vector3.new(152, 0, -280) } do
		box("CanopyPost", Vector3.new(0.8, 14, 0.8), CFrame.new(p + Vector3.new(0, 7, 0)), steel, M.Metal, m)
	end
	box("CanopyRoof", Vector3.new(30, 0.4, 90), CFrame.new(140, 14.2, -322), C(95, 100, 105), M.CorrodedMetal, m)
	-- Raised dock (2 studs: level with the truck bed) along the east edge
	box("Dock", Vector3.new(10, 2, 70), CFrame.new(150, 1, -322), C(165, 160, 155), M.Concrete, m)
	box("DockEdge", Vector3.new(0.6, 2.2, 70), CFrame.new(144.8, 1.1, -322), C(230, 180, 40), M.DiamondPlate, m)
	for z = -350, -294, 14 do
		box("Bumper", Vector3.new(0.8, 1.2, 2), CFrame.new(144.2, 1.2, z), C(30, 30, 30), M.Rubber, m)
	end
	-- Material stacks on pallets (stage 4 loads these into trucks)
	local stacks = {
		{ item = "Lumber", z = -346, color = C(200, 160, 110), material = M.WoodPlanks },
		{ item = "Post", z = -330, color = C(150, 110, 70), material = M.Wood },
		{ item = "Sheet", z = -314, color = C(120, 120, 130), material = M.CorrodedMetal },
		{ item = "Stake", z = -298, color = C(255, 140, 0), material = M.Wood },
	}
	for _, s in stacks do
		local stack = model("Stack_" .. s.item, m)
		box("Pallet", Vector3.new(5, 0.5, 6), CFrame.new(151, 2.25, s.z), C(160, 125, 85), M.Wood, stack)
		local load = box("Load", Vector3.new(4.4, 2.4, 5.4), CFrame.new(151, 3.7, s.z), s.color, s.material, stack)
		load:SetAttribute("MaterialStack", s.item)
		local tag = box("Tag", Vector3.new(0.1, 1, 3), CFrame.new(148.75, 3.7, s.z), C(250, 250, 245), M.Fabric, stack)
		paint(tag)
		surfaceText(tag, Enum.NormalId.Left, { { text = string.upper(s.item), size = 1 } }, 40)
	end
	-- LOADING sign on the canopy's west edge, facing the truck lot
	local sign = box("LoadingSign", Vector3.new(0.4, 3, 16), CFrame.new(125.6, 12, -322), C(230, 180, 40), M.Metal, m)
	surfaceText(sign, Enum.NormalId.Left, { { text = "LOADING", size = 1, color = C(30, 30, 30) } }, 30)
	for _, z in { -345, -300 } do
		local l = box("CanopyLight", Vector3.new(2, 0.2, 2), CFrame.new(140, 13.9, z), WARM, M.Neon, m)
		paint(l)
		lamp(l, l.Position, 30, 1.6)
	end
end

local function buildFence(parent: Instance)
	local m = model("Fence", parent)
	local wood = C(120, 90, 60)
	local function run(a: Vector3, b: Vector3)
		local dir = b - a
		local len = dir.Magnitude
		if len < 2 then
			return
		end
		local n = math.max(1, math.floor(len / 12))
		for i = 0, n do
			box("Post", Vector3.new(0.7, 3.6, 0.7), CFrame.new(a + dir * (i / n) + Vector3.new(0, 1.8, 0)), wood, M.Wood, m)
		end
		for _, h in { 1.4, 2.9 } do
			local mid = (a + b) / 2 + Vector3.new(0, h, 0)
			local size = if math.abs(dir.X) > 0 then Vector3.new(len, 0.4, 0.3) else Vector3.new(0.3, 0.4, len)
			box("Rail", size, CFrame.new(mid), wood, M.Wood, m)
		end
	end
	local n, s, w, e = Z0 + 1, Z1 - 1, X0 + 1, X1 - 1
	run(Vector3.new(w, 0, n), Vector3.new(-17, 0, n)) -- north, west of the gate
	run(Vector3.new(17, 0, n), Vector3.new(e, 0, n)) -- north, east of the gate
	run(Vector3.new(w, 0, s), Vector3.new(-6, 0, s)) -- south, west of the footpath
	run(Vector3.new(6, 0, s), Vector3.new(e, 0, s)) -- south, east of the footpath
	run(Vector3.new(w, 0, n), Vector3.new(w, 0, s)) -- west
	run(Vector3.new(e, 0, n), Vector3.new(e, 0, s)) -- east
end

local function buildEntrance(parent: Instance)
	local m = model("Entrance", parent)
	local log = C(110, 80, 50)
	for _, x in { -18, 18 } do
		cyl("ArchPost", 14, 1.4, vertical(Vector3.new(x, 7, -374)), log, M.Wood, m)
		local lantern = box("Lantern", Vector3.new(0.9, 1.2, 0.9), CFrame.new(x, 10, -375.2), WARM, M.Neon, m)
		paint(lantern)
		lamp(lantern, lantern.Position, 18, 1.4)
	end
	cyl("ArchBeam", 39, 1.2, CFrame.new(0, 14, -374), log, M.Wood, m)
	local sign = box("ArchSign", Vector3.new(24, 4, 0.4), CFrame.lookAt(Vector3.new(0, 11.4, -374), Vector3.new(0, 11.4, -420)), C(150, 115, 75), M.WoodPlanks, m)
	surfaceText(sign, Enum.NormalId.Front, {
		{ text = "RV PARK", size = 0.65 },
		{ text = "COFFEE  -  TRUCKS  -  LOADING", size = 0.3, color = C(255, 220, 160) },
	})
	surfaceText(sign, Enum.NormalId.Back, { { text = "HAVE A GOOD SHIFT", size = 0.6 } })
	for _, x in { -8, 8 } do
		box("Chain", Vector3.new(0.15, 2.4, 0.15), CFrame.new(x, 12.8, -374), C(90, 90, 95), M.Metal, m)
	end
end

local function buildCampLamps(parent: Instance)
	local m = model("CampLamps", parent)
	for _, p in { Vector3.new(-126, 0, -298), Vector3.new(-94, 0, -298), Vector3.new(-62, 0, -278), Vector3.new(-126, 0, -234), Vector3.new(-62, 0, -234) } do
		box("LampPost", Vector3.new(0.6, 8, 0.6), CFrame.new(p + Vector3.new(0, 4, 0)), C(110, 80, 50), M.Wood, m)
		box("LampCap", Vector3.new(1.4, 0.3, 1.4), CFrame.new(p + Vector3.new(0, 8.9, 0)), C(50, 50, 52), M.Metal, m)
		local glow = box("LampGlow", Vector3.new(1, 0.9, 1), CFrame.new(p + Vector3.new(0, 8.3, 0)), WARM, M.Neon, m)
		paint(glow)
		lamp(glow, glow.Position, 26, 1.4)
	end
	-- Campfire with log benches
	local fire = model("Campfire", parent)
	local center = Vector3.new(-40, 0, -210)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		box("Stone", Vector3.new(1.2, 0.8, 1.2), CFrame.new(center + Vector3.new(math.cos(a) * 3, 0.4, math.sin(a) * 3)) * CFrame.Angles(0, a, 0), C(110, 110, 105), M.Slate, fire)
	end
	local pit = box("FirePit", Vector3.new(3, 0.4, 3), CFrame.new(center + Vector3.new(0, 0.2, 0)), C(40, 30, 25), M.Slate, fire)
	local flame = Instance.new("Fire")
	flame.Size = 5
	flame.Heat = 6
	flame.Parent = pit
	local glow = Instance.new("PointLight")
	glow.Color = C(255, 150, 70)
	glow.Range = 22
	glow.Brightness = 2
	glow.Shadows = false
	glow.Parent = pit
	pit:SetAttribute("NightLight", true)
	for _, off in { Vector3.new(0, 0, -7), Vector3.new(0, 0, 7), Vector3.new(-7, 0, 0) } do
		local along = if off.X ~= 0 then CFrame.Angles(0, math.pi / 2, 0) else CFrame.new()
		cyl("LogBench", 6, 1.4, CFrame.new(center + off + Vector3.new(0, 0.7, 0)) * along, C(100, 70, 45), M.Wood, fire)
	end
end

function Builder.Terrain()
	-- Repaint the park's ground (grass first so a re-run starts clean), then the surfaces.
	fillRect({ X0, Z0, X1, Z1 }, M.Grass)
	fillRect(PATH, M.Pavement)
	for _, x in NORTH_PADS do
		fillRect({ x[1], -340, x[2], -300 }, M.Concrete)
	end
	for _, x in SOUTH_PADS do
		fillRect({ x[1], -276, x[2], -236 }, M.Concrete)
	end
	fillRect(PATIO, M.Brick)
	fillRect(LOADING, M.Concrete)
	fillRect(TRUCK_LOT, M.Asphalt)
	fillRect(LANE, M.Asphalt)
	fillRect(ENTRY, M.Asphalt)
	fillRect({ -60, -224, -20, -196 }, M.Ground) -- campfire clearing
	return "park ground painted"
end

function Builder.Parts()
	local old = workspace:FindFirstChild("RVPark")
	if old then
		old:Destroy()
	end
	-- The temporary stage-1 sign is replaced by the entrance arch.
	local lots = workspace:FindFirstChild("Town") and workspace.Town:FindFirstChild("Lots")
	local marker = lots and lots:FindFirstChild("RVPark")
	local temp = marker and marker:FindFirstChild("TempSign")
	if temp then
		temp:Destroy()
	end

	local park = Instance.new("Model")
	park.Name = "RVPark"
	park.ModelStreamingMode = Enum.ModelStreamingMode.Nonatomic
	local rvs = Instance.new("Folder")
	rvs.Name = "RVs"
	rvs.Parent = park
	local i = 0
	for _, x in NORTH_PADS do
		i += 1
		buildRV(rvs, i, Vector3.new((x[1] + x[2]) / 2 - 5, 0, -320))
	end
	for _, x in SOUTH_PADS do
		i += 1
		buildRV(rvs, i, Vector3.new((x[1] + x[2]) / 2 - 5, 0, -256))
	end
	task.wait()
	buildCoffeeStand(park)
	buildTruckLot(park)
	buildLoadingArea(park)
	task.wait()
	buildFence(park)
	buildEntrance(park)
	buildCampLamps(park)
	park.Parent = workspace

	local parts, lights = 0, 0
	for _, d in park:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	return ("RV park built: %d RVs, %d parts, %d lights"):format(i, parts, lights)
end

function Builder.All()
	return Builder.Terrain() .. "; " .. Builder.Parts()
end

return Builder
