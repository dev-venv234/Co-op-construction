--!strict
-- EDIT-TIME ONLY (2026-11-17, owner: "the spawn point area looks really bare, the rvs look bland, the coffee area
-- also"). Dresses up the RV park that DevTools/RVParkBuilder made, without rebuilding it (the site board buttons from
-- SiteBuilder and the runtime hooks stay untouched):
--   * each RV gets a "Polish" model: its own livery (two-tone body, pinstripes, dark window band, brand name),
--     headlights, bumper, solar panels and a dish on the roof, spare wheel, a striped awning with a valance and
--     string lights, an outdoor rug with camp chairs, potted plants, a grill and cooler, a lantern on the table,
--     a SITE number post and a power pedestal;
--   * Workspace.RVPark.Polish: the spawn plaza (stone circle, lanterns, a signpost pointing to coffee / truck lot /
--     Crew Supply / campfire, a welcome board), festoon lights zigzagging over the camp lane, pines and shrubs between
--     the sites, flower beds, tents and more seats by the campfire, and the coffee stand's café makeover (big cup on
--     the roof, striped awning, OPEN sign, chalkboards, more tables with round umbrellas, string lights, planters,
--     patio heaters, a bike rack).
-- Re-running replaces everything it made. Nothing here is a gameplay part: the decor doesn't collide (except tree
-- trunks, poles and the signpost), so it never blocks a walking player or the camp lane.
-- Run: require(game.ServerStorage.DevTools.CampPolishBuilder).Build()
local ServerStorage = game:GetService("ServerStorage")

local Builder = {}

local C = Color3.fromRGB
local M = Enum.Material
local WARM = C(255, 205, 150)
local rng = Random.new(20261117)

local function box(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cyl(name: string, length: number, diameter: number, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance, collide: boolean?): Part
	local p = box(name, Vector3.new(length, diameter, diameter), cf, color, mat, parent, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(name: string, d: number, pos: Vector3, color: Color3, mat: Enum.Material, parent: Instance): Part
	local p = box(name, Vector3.new(d, d, d), CFrame.new(pos), color, mat, parent)
	p.Shape = Enum.PartType.Ball
	p.CastShadow = false
	return p
end

-- a vertical cylinder standing on `pos` (bottom center)
local function post(name: string, height: number, d: number, pos: Vector3, color: Color3, mat: Enum.Material, parent: Instance, collide: boolean?): Part
	return cyl(name, height, d, CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), color, mat, parent, collide)
end

local function nightLight(part: BasePart, range: number, brightness: number, color: Color3?)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color or WARM
	l.Shadows = false
	l.Parent = part
	part:SetAttribute("NightLight", true) -- DayNightService switches it with the time of day
end

local function text(part: BasePart, face: Enum.NormalId, lines: { { string | number | Color3 } }, ppStud: number, font: Enum.Font?)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = ppStud
	sg.LightInfluence = 0.4
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
		t.Font = font or Enum.Font.GothamBlack
		t.TextColor3 = (l[3] :: Color3?) or C(250, 245, 230)
		t.Text = l[1] :: string
		t.Parent = sg
	end
	sg.Parent = part
end

local function folder(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- A string of bulbs from a to b, sagging in the middle. One light per string (lights are expensive).
local BULBS = { C(255, 214, 150), C(255, 180, 90), C(255, 236, 190) }
local function stringLights(parent: Instance, a: Vector3, b: Vector3, sag: number, spacing: number)
	local cable = (b - a)
	local n = math.max(2, math.floor(cable.Magnitude / spacing))
	local mid: BasePart? = nil
	local prev = a
	for i = 0, n do
		local t = i / n
		local p = a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		if i > 0 then
			local seg = p - prev
			box("Cable", Vector3.new(0.08, 0.08, seg.Magnitude), CFrame.lookAt((p + prev) / 2, p), C(30, 30, 30), M.Fabric, parent).CastShadow = false
		end
		if i > 0 and i < n then
			local bulb = ball("Bulb", 0.4, p - Vector3.new(0, 0.25, 0), BULBS[i % #BULBS + 1], M.Neon, parent)
			if i == math.floor(n / 2) then
				mid = bulb
			end
		end
		prev = p
	end
	if mid then
		nightLight(mid, math.min(22, cable.Magnitude * 0.7), 0.8)
	end
end

local function lantern(parent: Instance, pos: Vector3, height: number)
	post("LanternPost", height, 0.35, pos, C(60, 45, 35), M.Wood, parent, true)
	local cage = box("Lantern", Vector3.new(0.9, 1.1, 0.9), CFrame.new(pos + Vector3.new(0, height + 0.55, 0)), C(40, 40, 42), M.Metal, parent)
	cage.Transparency = 0.2
	local glow = box("LanternGlow", Vector3.new(0.6, 0.8, 0.6), cage.CFrame, WARM, M.Neon, parent)
	nightLight(glow, 14, 1)
	box("LanternCap", Vector3.new(1.1, 0.2, 1.1), CFrame.new(pos + Vector3.new(0, height + 1.2, 0)), C(40, 40, 42), M.Metal, parent)
end

local FLOWERS = { C(220, 60, 70), C(250, 200, 60), C(170, 90, 200), C(250, 250, 245), C(240, 120, 60) }
local LEAF = { C(64, 110, 52), C(74, 124, 58), C(58, 100, 48), C(86, 132, 66) }

local function shrub(parent: Instance, pos: Vector3, size: number, flowers: boolean?)
	ball("Shrub", size, pos + Vector3.new(0, size * 0.35, 0), LEAF[rng:NextInteger(1, #LEAF)], M.Grass, parent)
	if rng:NextNumber() < 0.6 then
		ball("Shrub", size * 0.7, pos + Vector3.new(size * 0.45, size * 0.25, size * 0.2), LEAF[rng:NextInteger(1, #LEAF)], M.Grass, parent)
	end
	if flowers then
		local col = FLOWERS[rng:NextInteger(1, #FLOWERS)]
		for _ = 1, 5 do
			local off = Vector3.new(rng:NextNumber(-0.5, 0.5) * size, size * 0.6, rng:NextNumber(-0.5, 0.5) * size)
			ball("Flower", 0.35, pos + off, col, M.Fabric, parent)
		end
	end
end

local function pottedPlant(parent: Instance, pos: Vector3)
	cyl("Pot", 1.1, 1.2, CFrame.new(pos + Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(180, 95, 60), M.Concrete, parent)
	ball("Leaves", 1.5, pos + Vector3.new(0, 1.55, 0), LEAF[rng:NextInteger(1, #LEAF)], M.Grass, parent)
	local col = FLOWERS[rng:NextInteger(1, #FLOWERS)]
	for _ = 1, 3 do
		ball("Flower", 0.3, pos + Vector3.new(rng:NextNumber(-0.5, 0.5), 2.1, rng:NextNumber(-0.5, 0.5)), col, M.Fabric, parent)
	end
end

-- A folding camp chair facing `yaw` (front = -Z).
local function campChair(parent: Instance, at: CFrame, color: Color3)
	local frame = C(45, 45, 48)
	box("ChairSeat", Vector3.new(1.6, 0.15, 1.5), at * CFrame.new(0, 1.3, 0), color, M.Fabric, parent)
	box("ChairBack", Vector3.new(1.6, 1.6, 0.15), at * CFrame.new(0, 2.1, 0.75) * CFrame.Angles(math.rad(-12), 0, 0), color, M.Fabric, parent)
	for _, x in { -0.8, 0.8 } do
		box("ChairArm", Vector3.new(0.15, 0.12, 1.5), at * CFrame.new(x, 1.9, 0), frame, M.Metal, parent)
		for _, z in { -0.6, 0.6 } do
			box("ChairLeg", Vector3.new(0.1, 1.9, 0.1), at * CFrame.new(x, 0.95, z) * CFrame.Angles(z * 0.4, 0, 0), frame, M.Metal, parent)
		end
	end
end

local function signText(part: BasePart, faces: { Enum.NormalId }, words: string, color: Color3?)
	for _, f in faces do
		text(part, f, { { words, 1, color or C(255, 240, 210) } }, 30)
	end
end

---------------------------------------------------------------------------------------------------------------
-- RVs
---------------------------------------------------------------------------------------------------------------

local LIVERY = {
	{ body = C(246, 241, 228), main = C(30, 80, 110), accent = C(232, 150, 45), name = "TRAILBLAZER", awn = { C(30, 90, 125), C(244, 238, 222) } },
	{ body = C(243, 238, 228), main = C(150, 42, 40), accent = C(60, 60, 64), name = "SUNDOWNER", awn = { C(175, 52, 46), C(246, 240, 226) } },
	{ body = C(238, 234, 222), main = C(48, 100, 62), accent = C(214, 172, 62), name = "WANDERER", awn = { C(62, 122, 74), C(242, 236, 220) } },
	{ body = C(245, 241, 233), main = C(58, 58, 68), accent = C(226, 96, 42), name = "ROADSTAR", awn = { C(222, 112, 44), C(250, 244, 230) } },
	{ body = C(240, 236, 226), main = C(36, 112, 142), accent = C(250, 200, 64), name = "BIG SKY", awn = { C(40, 124, 154), C(250, 240, 220) } },
	{ body = C(244, 240, 230), main = C(110, 62, 120), accent = C(240, 180, 74), name = "NOMAD", awn = { C(122, 72, 132), C(246, 240, 226) } },
	{ body = C(241, 237, 225), main = C(150, 92, 42), accent = C(62, 92, 62), name = "HOMESTEAD", awn = { C(172, 112, 52), C(246, 238, 220) } },
}

local function polishRV(rv: Model, index: number): number
	local body = rv:FindFirstChild("Body") :: BasePart?
	if not body then
		return 0
	end
	local old = rv:FindFirstChild("Polish")
	if old then
		old:Destroy()
	end
	local m = folder("Polish", rv)
	local L = LIVERY[(index - 1) % #LIVERY + 1]
	local base = body.Position - Vector3.new(0, 5, 0)
	local cf = CFrame.new(base)
	local dark = C(30, 32, 36)

	-- Repaint the RV's own parts with its livery (absolute colors: re-running gives the same result)
	for _, d in rv:GetChildren() do
		if d:IsA("BasePart") then
			if d.Name == "Body" then
				d.Color = L.body
			elseif d.Name == "Stripe" or d.Name == "FenderSkirt" or d.Name == "FrontCap" or d.Name == "NoseCap" then
				d.Color = L.main
			elseif d.Name == "Skirt" then
				d.Color = dark
			elseif d.Name == "Awning" then
				d.Transparency = 1 -- the striped awning below replaces it
			end
		end
	end

	-- Sides: dark window band, accent pinstripe, lower swoosh, brand name. The door (+X, z 1.4..4.6) is left clear.
	for _, side in { -1, 1 } do
		local spans = if side > 0 then { { -12.6, 1.2 }, { 4.8, 12.6 } } else { { -12.6, 12.6 } }
		for _, s in spans do
			local len, zc = s[2] - s[1], (s[1] + s[2]) / 2
			box("WindowBand", Vector3.new(0.04, 2.5, len), cf * CFrame.new(side * 4.27, 6.6, zc), dark, M.Metal, m).CastShadow = false
			box("Pinstripe", Vector3.new(0.04, 0.22, len), cf * CFrame.new(side * 4.31, 4.75, zc), L.accent, M.Metal, m).CastShadow = false
			box("Swoosh", Vector3.new(0.04, 0.5, len), cf * CFrame.new(side * 4.31, 5.15, zc), L.main, M.Metal, m).CastShadow = false
		end
		local brand = box("Brand", Vector3.new(0.04, 1.1, 8), cf * CFrame.new(side * 4.3, 8.25, -7.6), L.body, M.Metal, m) -- (front half: clear of the awning)
		brand.Transparency = 1
		text(brand, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, { { L.name, 1, L.main } }, 40, Enum.Font.FredokaOne)
		-- mud flaps behind the rear wheels
		box("MudFlap", Vector3.new(0.9, 1.2, 0.1), cf * CFrame.new(side * 3.9, 0.9, 9.7), dark, M.Rubber, m)
	end

	-- Front: headlights, grille, bumper. Back: bumper, spare wheel with a cover.
	box("Grille", Vector3.new(4, 1.1, 0.1), cf * CFrame.new(0, 2.5, -13.1), dark, M.Metal, m)
	for _, x in { -3, 3 } do
		local hl = box("Headlight", Vector3.new(1.3, 0.7, 0.1), cf * CFrame.new(x, 2.5, -13.12), C(255, 250, 230), M.Neon, m)
		hl.CastShadow = false
	end
	box("FrontBumper", Vector3.new(8.6, 0.5, 0.5), cf * CFrame.new(0, 1.3, -13.3), C(200, 202, 208), M.Metal, m)
	box("RearBumper", Vector3.new(8.6, 0.5, 0.5), cf * CFrame.new(0, 1.0, 13.35), C(200, 202, 208), M.Metal, m)
	cyl("SpareWheel", 0.9, 3, cf * CFrame.new(1.4, 5.2, 13.55) * CFrame.Angles(0, math.pi / 2, 0), dark, M.Rubber, m)
	cyl("SpareCover", 0.95, 2.4, cf * CFrame.new(1.4, 5.2, 13.57) * CFrame.Angles(0, math.pi / 2, 0), L.main, M.Fabric, m)

	-- Roof: solar panels and a satellite dish
	for _, z in { -10.4, 9.6 } do
		box("SolarPanel", Vector3.new(3.4, 0.12, 2.8), cf * CFrame.new(0.6, 9.5, z) * CFrame.Angles(math.rad(6), 0, 0), C(30, 45, 80), M.Glass, m)
		box("SolarFrame", Vector3.new(3.6, 0.08, 3), cf * CFrame.new(0.6, 9.44, z) * CFrame.Angles(math.rad(6), 0, 0), C(190, 190, 195), M.Metal, m)
	end
	post("DishMast", 0.8, 0.2, base + Vector3.new(-2.8, 9.4, -3), C(190, 190, 195), M.Metal, m)
	cyl("Dish", 0.25, 1.6, cf * CFrame.new(-2.8, 10.5, -3) * CFrame.Angles(0, math.rad(30), math.rad(60)), C(235, 235, 235), M.Metal, m)

	-- Striped awning (same place and slope as the old one), valance, string lights
	local awnCF = cf * CFrame.new(6.4, 8.3, 3) * CFrame.Angles(0, 0, -0.18)
	local stripes = 8
	for j = 1, stripes do
		local z = -5.5 + (j - 0.5) * (11 / stripes)
		box("AwningStripe", Vector3.new(4.2, 0.2, 11 / stripes), awnCF * CFrame.new(0, 0, z), L.awn[j % 2 + 1], M.Fabric, m)
	end
	local edge = (awnCF * CFrame.new(2.1, 0, 0)).Position
	for j = 1, stripes do
		local z = -5.5 + (j - 0.5) * (11 / stripes)
		box("Valance", Vector3.new(0.08, 0.7, 11 / stripes), CFrame.new(edge.X + 0.05, edge.Y - 0.35, base.Z + 3 + z), L.awn[j % 2 + 1], M.Fabric, m).CastShadow = false
	end
	stringLights(m, Vector3.new(edge.X + 0.1, edge.Y - 0.75, base.Z - 2.4), Vector3.new(edge.X + 0.1, edge.Y - 0.75, base.Z + 8.4), 0.35, 1.3)

	-- Outdoor rug, two camp chairs, potted plants by the step
	box("RugBorder", Vector3.new(4.8, 0.05, 8.4), cf * CFrame.new(7.3, 0.03, 3), L.accent, M.Fabric, m).CastShadow = false
	box("Rug", Vector3.new(4.2, 0.06, 7.8), cf * CFrame.new(7.3, 0.04, 3), L.main, M.Fabric, m).CastShadow = false
	campChair(m, cf * CFrame.new(8.2, 0, 0.2) * CFrame.Angles(0, math.rad(-110), 0), L.accent)
	campChair(m, cf * CFrame.new(8.2, 0, 5.9) * CFrame.Angles(0, math.rad(-70), 0), L.main)
	pottedPlant(m, base + Vector3.new(5.6, 0, 0.9))
	pottedPlant(m, base + Vector3.new(5.6, 0, 5.1))

	-- By the picnic table: grill, cooler, a lantern on the table
	local g = base + Vector3.new(14, 0, -1.5)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		box("GrillLeg", Vector3.new(0.12, 2, 0.12), CFrame.new(g + Vector3.new(math.cos(a) * 0.6, 1, math.sin(a) * 0.6)), dark, M.Metal, m)
	end
	ball("GrillKettle", 1.8, g + Vector3.new(0, 2.3, 0), dark, M.Metal, m)
	box("Cooler", Vector3.new(1.8, 1.2, 1.1), CFrame.new(base + Vector3.new(14, 0.6, 7.2)), L.main, M.Metal, m)
	box("CoolerLid", Vector3.new(1.9, 0.25, 1.2), CFrame.new(base + Vector3.new(14, 1.3, 7.2)), C(245, 245, 240), M.Metal, m)
	local lan = box("TableLantern", Vector3.new(0.5, 0.7, 0.5), CFrame.new(base + Vector3.new(11, 3.1, 3)), WARM, M.Neon, m)
	nightLight(lan, 12, 0.8)

	-- SITE number post and a power pedestal at the lane-side corner of the pad
	local laneZ = if base.Z < -300 then -302.5 else -273.5
	local postAt = Vector3.new(base.X + 10, 0, laneZ)
	post("SitePost", 4.5, 0.5, postAt, C(110, 80, 50), M.Wood, m, true)
	local plate = box("SitePlate", Vector3.new(2.6, 1.3, 0.2), CFrame.new(postAt + Vector3.new(0, 3.6, 0)), C(60, 45, 35), M.Wood, m)
	signText(plate, { Enum.NormalId.Front, Enum.NormalId.Back }, "SITE " .. index)
	box("Pedestal", Vector3.new(0.9, 2.4, 0.7), CFrame.new(postAt + Vector3.new(1.6, 1.2, 0)), C(150, 152, 156), M.Metal, m)
	local led = box("PowerLED", Vector3.new(0.25, 0.25, 0.74), CFrame.new(postAt + Vector3.new(1.6, 2.0, 0)), C(80, 230, 110), M.Neon, m)
	led.CastShadow = false

	local n = 0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------------------------------------------
-- Park: spawn plaza, lane lights, trees, campfire
---------------------------------------------------------------------------------------------------------------

local SPAWN = Vector3.new(-110, 0, -288)

local function spawnPlaza(parent: Instance)
	local m = folder("SpawnPlaza", parent)
	-- ground under the plaza: no tall terrain grass poking through the stone (walkable top stays at y 0)
	workspace.Terrain:FillCylinder(CFrame.new(SPAWN + Vector3.new(0, -6, 0)), 8, 11.5, M.Ground)
	-- the default grey spawn pad becomes part of a stone plaza
	local sp = workspace:FindFirstChild("SpawnLocation")
	if sp and sp:IsA("SpawnLocation") then
		for _, d in sp:GetChildren() do
			if d:IsA("Decal") then
				d:Destroy()
			end
		end
		sp.Material = M.Slate
		sp.Color = C(150, 140, 125)
		sp.Transparency = 0
	end
	cyl("PlazaRim", 0.12, 21, CFrame.new(SPAWN + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(110, 100, 90), M.Slate, m).CastShadow = false
	cyl("Plaza", 0.14, 19.6, CFrame.new(SPAWN + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(176, 164, 146), M.Slate, m).CastShadow = false
	for k = 0, 7 do -- a compass rose of darker stones
		local a = k / 8 * math.pi * 2
		box("PlazaInlay", Vector3.new(0.8, 0.16, 3.4), CFrame.new(SPAWN + Vector3.new(math.cos(a) * 7.2, 0.08, math.sin(a) * 7.2)) * CFrame.Angles(0, -a + math.pi / 2, 0), C(125, 115, 102), M.Slate, m).CastShadow = false
	end
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + math.pi / 4
		lantern(m, SPAWN + Vector3.new(math.cos(a) * 10.6, 0, math.sin(a) * 10.6), 5)
	end
	-- signpost: boards point at the places a new player looks for
	local sp2 = SPAWN + Vector3.new(6, 0, 6)
	post("SignPole", 9, 0.6, sp2, C(110, 80, 50), M.Wood, m, true)
	local targets = {
		{ "COFFEE", Vector3.new(-40, 0, -350), C(190, 90, 60) },
		{ "TRUCK LOT + JOBS", Vector3.new(68, 0, -321), C(60, 120, 170) },
		{ "CREW SUPPLY", Vector3.new(-100, 0, -458), C(230, 120, 30) },
		{ "CAMPFIRE", Vector3.new(-40, 0, -210), C(80, 130, 70) },
	}
	for i, t in targets do
		local dir = (t[2] - sp2) * Vector3.new(1, 0, 1)
		local yaw = math.atan2(dir.X, dir.Z)
		local y = 8.2 - (i - 1) * 1.5
		-- board along its direction, starting at the pole
		local board = box("SignBoard", Vector3.new(0.25, 1.1, 5.2), CFrame.new(sp2 + Vector3.new(0, y, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, 2.6), t[3], M.WoodPlanks, m, true)
		signText(board, { Enum.NormalId.Left, Enum.NormalId.Right }, t[1])
		local tip = Instance.new("WedgePart")
		tip.Name = "SignTip"
		tip.Anchored = true
		tip.CanCollide = false
		tip.CanQuery = false
		tip.Size = Vector3.new(0.25, 1.1, 0.9)
		tip.Color = t[3]
		tip.Material = M.WoodPlanks
		for _, s in { 1, -1 } do
			local w = tip:Clone()
			w.Size = Vector3.new(0.25, 0.55, 0.9)
			w.CFrame = board.CFrame * CFrame.new(0, s * 0.275, 3.05) * CFrame.Angles(if s > 0 then math.pi else 0, 0, 0) * CFrame.Angles(0, math.pi, 0)
			w.Parent = m
		end
		tip:Destroy()
	end
	-- welcome board on two posts across the lane's north edge, facing the spawn
	local wb = Vector3.new(SPAWN.X, 0, -298.6)
	for _, dx in { -4, 4 } do
		post("WelcomePost", 7, 0.6, wb + Vector3.new(dx, 0, 0), C(110, 80, 50), M.Wood, m, true)
	end
	local welcome = box("WelcomeBoard", Vector3.new(10, 3.2, 0.4), CFrame.new(wb + Vector3.new(0, 5.6, 0)), C(70, 50, 35), M.WoodPlanks, m, true)
	text(welcome, Enum.NormalId.Back, {
		{ "WELCOME TO CREW CAMP", 0.45, C(255, 220, 160) },
		{ "grab a coffee, pick a trade, then a job at the truck lot", 0.3 },
	}, 30)
	text(welcome, Enum.NormalId.Front, { { "CREW CAMP", 0.6, C(255, 220, 160) } }, 30)
	local wl = box("WelcomeLight", Vector3.new(9, 0.2, 0.4), CFrame.new(wb + Vector3.new(0, 7.35, 0.4)), WARM, M.Neon, m)
	nightLight(wl, 12, 0.9)
	-- flower beds beside the plaza
	for _, off in { Vector3.new(-13, 0, -7), Vector3.new(13, 0, -7) } do
		local c = SPAWN + off
		box("BedEdge", Vector3.new(5.6, 0.5, 3.2), CFrame.new(c + Vector3.new(0, 0.25, 0)), C(120, 110, 100), M.Slate, m)
		box("BedSoil", Vector3.new(5, 0.52, 2.6), CFrame.new(c + Vector3.new(0, 0.27, 0)), C(70, 50, 35), M.Ground, m)
		for x = -1.8, 1.8, 1.2 do
			shrub(m, c + Vector3.new(x, 0.4, rng:NextNumber(-0.4, 0.4)), 1.1, true)
		end
	end
end

-- Festoon lights zigzagging over the camp lane (z -296..-280) between wooden poles on both edges.
local function laneLights(parent: Instance)
	local m = folder("LaneLights", parent)
	local north = { -150, -122, -86, -54 } -- (clear of the welcome board at x -114..-106)
	local south = { -136, -104, -70, -38 }
	local tops: { Vector3 } = {}
	for i = 1, #north do
		for _, p in { Vector3.new(north[i], 0, -298.6), Vector3.new(south[i], 0, -277.4) } do
			post("LightPole", 9, 0.45, p, C(100, 72, 48), M.Wood, m, true)
			table.insert(tops, p + Vector3.new(0, 8.8, 0))
		end
	end
	for i = 1, #tops - 1 do
		stringLights(m, tops[i], tops[i + 1], 1.4, 2.2)
	end
end

-- Pines and shrubs on open grass between the sites (never on pads, lanes, the patio, paths or the campfire).
local NO_GO = {
	{ -164, -344, -60, -296 }, -- north pads + RVs (x0, z0, x1, z1)
	{ -164, -300, -6, -274 }, -- camp lane
	{ -164, -280, -28, -230 }, -- south pads + RVs
	{ -66, -374, -14, -322 }, -- coffee patio
	{ -66, -230, -14, -188 }, -- campfire clearing
	{ -18, -380, 200, -170 }, -- entry road, truck lot, east half
	{ -100, -214, -70, -190 }, -- tents
	{ -64, -330, -14, -292 }, -- the walk from the lane up to the café
}
local function blocked(x: number, z: number, margin: number): boolean
	if x < -154 or x > -16 or z < -368 or z > -186 then
		return true
	end
	for _, r in NO_GO do
		if x > r[1] - margin and x < r[3] + margin and z > r[2] - margin and z < r[4] + margin then
			return true
		end
	end
	return (Vector3.new(x, 0, z) - SPAWN).Magnitude < 18
end

local function clearOfParts(pos: Vector3, size: Vector3, ignore: { Instance }): boolean
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = ignore
	return #workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, size.Y / 2 + 0.3, 0)), size, op) == 0
end

local function greenery(parent: Instance): (number, number)
	local m = folder("Greenery", parent)
	local pines = ServerStorage:FindFirstChild("Nature") and ServerStorage.Nature:FindFirstChild("Pines")
	local templates = if pines then pines:GetChildren() else {}
	local ignore: { Instance } = { workspace.Terrain, m }
	local nature = workspace:FindFirstChild("Nature")
	if nature then
		table.insert(ignore, nature)
	end
	local placed: { Vector3 } = {}
	local trees = 0
	for z = -366, -188, 11 do
		for x = -152, -18, 11 do
			local p = Vector3.new(x + rng:NextNumber(-3, 3), 0, z + rng:NextNumber(-3, 3))
			local ok = #templates > 0 and not blocked(p.X, p.Z, 4) and rng:NextNumber() < 0.75
			for _, q in placed do
				if (q - p).Magnitude < 15 then
					ok = false
					break
				end
			end
			if ok and clearOfParts(p, Vector3.new(7, 14, 7), ignore) then
				local t = (templates[rng:NextInteger(1, #templates)] :: Model):Clone()
				t:ScaleTo(t:GetScale() * rng:NextNumber(1.15, 1.6))
				t:PivotTo(CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
				t.Parent = m
				table.insert(placed, p)
				trees += 1
			end
		end
	end
	-- shrubs: along the pad edges and the fence, a few with flowers
	local shrubs = 0
	for _ = 1, 400 do
		if shrubs >= 60 then
			break
		end
		local p = Vector3.new(rng:NextNumber(-154, -16), 0, rng:NextNumber(-368, -186))
		if not blocked(p.X, p.Z, 0.5) then
			local near = false
			for _, q in placed do
				if (q - p).Magnitude < 4 then
					near = true
				end
			end
			if not near and clearOfParts(p, Vector3.new(3, 3, 3), ignore) then
				shrub(m, p, rng:NextNumber(1.6, 2.8), rng:NextNumber() < 0.35)
				shrubs += 1
			end
		end
	end
	return trees, shrubs
end

-- An A-frame tent facing `yaw` (big enough to read over the tall camp grass).
local function tent(parent: Instance, at: CFrame, color: Color3)
	local m = folder("Tent", parent)
	for _, s in { -1, 1 } do
		box("TentSide", Vector3.new(0.15, 6, 8.4), at * CFrame.new(s * 1.85, 2.35, 0) * CFrame.Angles(0, 0, s * math.rad(38)), color, M.Fabric, m, true)
	end
	box("TentRidge", Vector3.new(0.3, 0.3, 8.8), at * CFrame.new(0, 4.75, 0), C(60, 60, 60), M.Metal, m)
	box("TentFloor", Vector3.new(7.6, 0.1, 8.6), at * CFrame.new(0, 0.05, 0), C(70, 70, 60), M.Fabric, m)
	box("TentBack", Vector3.new(4.4, 3.4, 0.12), at * CFrame.new(0, 1.7, 4.1), color, M.Fabric, m)
	box("TentInside", Vector3.new(4.2, 3, 0.1), at * CFrame.new(0, 1.5, 4.0), C(30, 30, 28), M.Fabric, m)
	for _, s in { -1, 1 } do
		box("Flap", Vector3.new(1.9, 3.6, 0.1), at * CFrame.new(s * 2.2, 1.8, -4.4) * CFrame.Angles(0, s * math.rad(50), 0), color, M.Fabric, m)
	end
	for _, z in { -4.1, 4.1 } do
		box("Peg", Vector3.new(0.1, 0.5, 0.1), at * CFrame.new(4.2, 0.25, z), C(180, 180, 180), M.Metal, m)
		box("Peg", Vector3.new(0.1, 0.5, 0.1), at * CFrame.new(-4.2, 0.25, z), C(180, 180, 180), M.Metal, m)
	end
end

local function campfireExtras(parent: Instance)
	local m = folder("CampfireExtras", parent)
	local center = Vector3.new(-40, 0, -210)
	-- stump seats round the open side, a firewood stack, lanterns, string lights on poles round the clearing
	for k = 0, 4 do
		local a = math.rad(200 + k * 32)
		post("Stump", 1.6, 1.6, center + Vector3.new(math.cos(a) * 8.5, 0, math.sin(a) * 8.5), C(120, 85, 55), M.Wood, m, true)
	end
	for row = 0, 2 do
		for i = 0, 4 - row do
			cyl("Firewood", 3, 0.6, CFrame.new(center + Vector3.new(11, 0.3 + row * 0.55, -6 + i * 0.62 + row * 0.31)) * CFrame.Angles(0, 0, 0), C(140, 100, 65), M.Wood, m)
		end
	end
	local poles = { center + Vector3.new(-13, 0, -11), center + Vector3.new(13, 0, -11), center + Vector3.new(13, 0, 11), center + Vector3.new(-13, 0, 11) }
	for _, p in poles do
		post("FirePole", 8, 0.4, p, C(100, 72, 48), M.Wood, m, true)
	end
	for i = 1, 4 do
		stringLights(m, poles[i] + Vector3.new(0, 7.8, 0), poles[i % 4 + 1] + Vector3.new(0, 7.8, 0), 1.2, 2)
	end
	tent(parent, CFrame.new(-80, 0, -205) * CFrame.Angles(0, math.rad(-70), 0), C(220, 120, 50))
	tent(parent, CFrame.new(-90, 0, -196) * CFrame.Angles(0, math.rad(-100), 0), C(60, 120, 170))
	campChair(m, CFrame.new(-74, 0, -199) * CFrame.Angles(0, math.rad(-60), 0), C(200, 60, 60))
end

---------------------------------------------------------------------------------------------------------------
-- Café (the coffee stand's patio: x -60..-20, z -368..-328; the kiosk x -48..-32, z -365..-355, window facing +Z)
---------------------------------------------------------------------------------------------------------------

local function umbrella(parent: Instance, at: Vector3, a: Color3, b: Color3)
	post("UmbrellaPole", 6.8, 0.25, at, C(200, 200, 205), M.Metal, parent)
	-- a solid canopy with a pale crown and a pale hem (rings in alternating colors read as a target)
	cyl("UmbrellaHem", 0.25, 7.2, CFrame.new(at + Vector3.new(0, 6.8, 0)) * CFrame.Angles(0, 0, math.pi / 2), b, M.Fabric, parent)
	cyl("UmbrellaTop", 0.35, 6.8, CFrame.new(at + Vector3.new(0, 6.95, 0)) * CFrame.Angles(0, 0, math.pi / 2), a, M.Fabric, parent)
	cyl("UmbrellaCrown", 0.45, 1.2, CFrame.new(at + Vector3.new(0, 7.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), b, M.Fabric, parent)
	ball("UmbrellaTip", 0.4, at + Vector3.new(0, 7.45, 0), C(200, 200, 205), M.Metal, parent)
end

local function cafeTable(parent: Instance, at: Vector3, chairColor: Color3)
	cyl("CafeTable", 0.25, 3.4, CFrame.new(at + Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(60, 60, 64), M.Metal, parent, true)
	post("CafeTableLeg", 2.7, 0.35, at, C(60, 60, 64), M.Metal, parent)
	for _, a in { 0, math.pi } do
		campChair(parent, CFrame.new(at + Vector3.new(math.cos(a) * 2.4, 0, math.sin(a) * 2.4)) * CFrame.Angles(0, -a + math.pi / 2, 0), chairColor)
	end
	cyl("Mug", 0.5, 0.45, CFrame.new(at + Vector3.new(0.6, 3.15, 0.3)) * CFrame.Angles(0, 0, math.pi / 2), C(245, 240, 230), M.Concrete, parent)
end

local function cafe(parent: Instance)
	local m = folder("Cafe", parent)
	local stand = workspace.RVPark:FindFirstChild("CoffeeStand")
	local red, cream = C(175, 52, 46), C(246, 240, 226)
	-- hide the old plain umbrellas (round striped ones replace them)
	if stand then
		for _, d in stand:GetChildren() do
			if d:IsA("BasePart") and (d.Name == "Umbrella" or d.Name == "UmbrellaPole") then
				d.Transparency = 1
			end
		end
	end
	-- giant cup on the roof
	local cup = Vector3.new(-40, 9.2, -361)
	cyl("CupBody", 5, 4, CFrame.new(cup + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(248, 246, 240), M.Concrete, m)
	cyl("CupBand", 1.4, 4.08, CFrame.new(cup + Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), red, M.Fabric, m)
	cyl("CupCoffee", 0.1, 3.6, CFrame.new(cup + Vector3.new(0, 4.9, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(90, 55, 30), M.Fabric, m)
	cyl("CupSaucer", 0.3, 5.6, CFrame.new(cup + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(248, 246, 240), M.Concrete, m)
	box("HandleTop", Vector3.new(1.4, 0.45, 0.5), CFrame.new(cup + Vector3.new(2.5, 3.8, 0)), C(248, 246, 240), M.Concrete, m)
	box("HandleBottom", Vector3.new(1.4, 0.45, 0.5), CFrame.new(cup + Vector3.new(2.5, 1.4, 0)), C(248, 246, 240), M.Concrete, m)
	box("HandleSide", Vector3.new(0.45, 2.85, 0.5), CFrame.new(cup + Vector3.new(3.0, 2.6, 0)), C(248, 246, 240), M.Concrete, m)
	local steamSrc = box("Steam", Vector3.new(1, 0.1, 1), CFrame.new(cup + Vector3.new(0, 5, 0)), C(255, 255, 255), M.Concrete, m)
	steamSrc.Transparency = 1
	local steam = Instance.new("ParticleEmitter")
	steam.Rate = 3
	steam.Lifetime = NumberRange.new(2, 3)
	steam.Speed = NumberRange.new(1, 2)
	steam.SpreadAngle = Vector2.new(10, 10)
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	steam.Color = ColorSequence.new(C(250, 250, 250))
	steam.Parent = steamSrc
	local cupLight = box("CupLight", Vector3.new(0.5, 0.5, 0.5), CFrame.new(cup + Vector3.new(0, 1, 3.2)), WARM, M.Neon, m)
	cupLight.Transparency = 1
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Back
	spot.Range = 10
	spot.Angle = 70
	spot.Brightness = 2
	spot.Color = WARM
	spot.Shadows = false
	spot.Parent = cupLight
	cupLight:SetAttribute("NightLight", true)

	-- red and white stripes on the serving awning (same slope), and a valance
	local awnCF = CFrame.new(-40, 7.6, -352.9) * CFrame.Angles(math.rad(-16), 0, 0)
	for j = 0, 7 do
		if j % 2 == 1 then
			box("AwningStripe", Vector3.new(2, 0.22, 4.4), awnCF * CFrame.new(-7 + j * 2, 0, 0), cream, M.Fabric, m)
		end
	end
	local front = (awnCF * CFrame.new(0, 0, 2.2)).Position
	for j = 0, 15 do
		box("Valance", Vector3.new(1, 0.6, 0.08), CFrame.new(-47.5 + j, front.Y - 0.3, front.Z + 0.05), if j % 2 == 0 then red else cream, M.Fabric, m).CastShadow = false
	end
	-- OPEN sign in the window, a menu board on the east wall, an A-frame by the patio entrance
	local open = box("OpenSign", Vector3.new(2.6, 1, 0.1), CFrame.new(-45.6, 6.3, -355.1), C(255, 70, 60), M.Neon, m)
	text(open, Enum.NormalId.Back, { { "OPEN", 1, C(255, 250, 240) } }, 40)
	local menu = box("MenuBoard", Vector3.new(0.12, 3.4, 5), CFrame.new(-31.9, 4.6, -360), C(30, 36, 32), M.Slate, m)
	text(menu, Enum.NormalId.Right, {
		{ "MENU", 0.22, C(255, 220, 160) },
		{ "drip  -  latte  -  cold brew", 0.2 },
		{ "every cup: AWAKE", 0.2, C(150, 230, 150) },
		{ "+15% walk speed all job", 0.2, C(150, 230, 150) },
	}, 40, Enum.Font.Gotham)
	box("MenuFrame", Vector3.new(0.1, 3.7, 5.3), CFrame.new(-31.95, 4.6, -360), C(120, 85, 55), M.Wood, m)
	local af = Vector3.new(-40, 0, -327)
	for _, s in { -1, 1 } do
		local board = box("AFrame", Vector3.new(2.4, 3.4, 0.15), CFrame.new(af + Vector3.new(0, 1.6, 0)) * CFrame.Angles(s * math.rad(14), 0, 0) * CFrame.new(0, 0, s * 0.45), C(30, 36, 32), M.Slate, m)
		text(board, if s > 0 then Enum.NormalId.Back else Enum.NormalId.Front, {
			{ "FRESH", 0.25, C(255, 220, 160) },
			{ "COFFEE", 0.25, C(255, 220, 160) },
			{ "get AWAKE", 0.2, C(150, 230, 150) },
			{ "work faster", 0.18 },
		}, 40, Enum.Font.Gotham)
	end
	-- round striped umbrellas over the two old tables, two more tables, chairs
	umbrella(m, Vector3.new(-52, 0, -337), red, cream)
	umbrella(m, Vector3.new(-28, 0, -337), C(40, 110, 140), cream)
	for _, t in { { Vector3.new(-55, 0, -347), C(40, 110, 140) }, { Vector3.new(-25, 0, -347), red } } do
		cafeTable(m, t[1], t[2])
		umbrella(m, t[1], t[2], cream)
	end
	-- string lights: kiosk corners out to four poles round the patio
	local poles = { Vector3.new(-58.5, 0, -329.5), Vector3.new(-21.5, 0, -329.5), Vector3.new(-58.5, 0, -353), Vector3.new(-21.5, 0, -353) }
	for _, p in poles do
		post("CafePole", 9, 0.4, p, C(60, 60, 64), M.Metal, m, true)
	end
	local top = Vector3.new(0, 8.8, 0)
	local k1, k2 = Vector3.new(-48, 8.6, -355), Vector3.new(-32, 8.6, -355)
	stringLights(m, k1, poles[1] + top, 1, 2)
	stringLights(m, k2, poles[2] + top, 1, 2)
	stringLights(m, poles[1] + top, poles[2] + top, 1.2, 2)
	stringLights(m, poles[3] + top, poles[1] + top, 0.8, 2)
	stringLights(m, poles[4] + top, poles[2] + top, 0.8, 2)
	-- planters along the patio's south edge (gap in the middle to walk in), plants by the counter, heaters, bikes
	for _, span in { { -58, -45 }, { -35, -22 } } do
		box("Planter", Vector3.new(span[2] - span[1], 1.4, 1.8), CFrame.new((span[1] + span[2]) / 2, 0.7, -329), C(120, 85, 55), M.WoodPlanks, m, true)
		for x = span[1] + 1.2, span[2] - 1.2, 1.6 do
			shrub(m, Vector3.new(x, 1.2, -329), 1.2, rng:NextNumber() < 0.6)
		end
	end
	pottedPlant(m, Vector3.new(-49.4, 0, -353.8))
	pottedPlant(m, Vector3.new(-30.6, 0, -353.8))
	for _, x in { -58.5, -21.5 } do
		local h = Vector3.new(x, 0, -341)
		post("HeaterPole", 7, 0.35, h, C(170, 172, 176), M.Metal, m, true)
		cyl("HeaterBase", 0.3, 1.8, CFrame.new(h + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(170, 172, 176), M.Metal, m)
		cyl("HeaterHood", 0.4, 3.2, CFrame.new(h + Vector3.new(0, 7.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(170, 172, 176), M.Metal, m)
		local flame = cyl("HeaterGlow", 0.6, 1.2, CFrame.new(h + Vector3.new(0, 6.6, 0)) * CFrame.Angles(0, 0, math.pi / 2), C(255, 140, 60), M.Neon, m)
		nightLight(flame, 14, 1, C(255, 160, 90))
	end
	-- coffee sacks by the kiosk's west wall, a bike rack with two bikes on the east side
	for i, p in { Vector3.new(-50.5, 0.7, -362), Vector3.new(-50.5, 0.7, -359.6), Vector3.new(-50.5, 2.0, -360.8) } do
		local sack = box("CoffeeSack", Vector3.new(1.6, 1.3, 2.2), CFrame.new(p) * CFrame.Angles(0, i * 0.2, 0), C(170, 140, 100), M.Fabric, m)
		if i == 3 then
			text(sack, Enum.NormalId.Left, { { "BEANS", 1, C(80, 50, 30) } }, 40)
		end
	end
	box("BikeRack", Vector3.new(0.2, 1.6, 5), CFrame.new(-24, 0.8, -361), C(60, 60, 64), M.Metal, m)
	for i, z in { -362.4, -359.4 } do
		local col = if i == 1 then C(40, 110, 140) else C(200, 90, 50)
		for _, dx in { -1.6, 1.6 } do
			cyl("BikeWheel", 0.15, 2.2, CFrame.new(-24 + dx, 1.1, z), C(30, 30, 30), M.Rubber, m)
		end
		box("BikeFrame", Vector3.new(3, 0.2, 0.15), CFrame.new(-24, 1.6, z), col, M.Metal, m)
		box("BikeSeat", Vector3.new(0.8, 0.2, 0.4), CFrame.new(-25, 2.4, z), C(30, 30, 30), M.Fabric, m)
		box("BikeBars", Vector3.new(0.15, 0.2, 1.2), CFrame.new(-22.8, 2.5, z), C(30, 30, 30), M.Metal, m)
	end
end

---------------------------------------------------------------------------------------------------------------

function Builder.Build(): string
	local park = workspace:FindFirstChild("RVPark")
	assert(park, "No Workspace.RVPark: run DevTools/RVParkBuilder first")
	local old = park:FindFirstChild("Polish")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "Polish"

	local rvParts = 0
	local rvs = park:FindFirstChild("RVs")
	if rvs then
		for _, rv in rvs:GetChildren() do
			local idx = tonumber(string.match(rv.Name, "^RV_(%d+)$"))
			if rv:IsA("Model") and idx then
				rvParts += polishRV(rv, idx)
			end
		end
	end
	task.wait()
	spawnPlaza(root)
	laneLights(root)
	campfireExtras(root)
	task.wait()
	cafe(root)
	root.Parent = park -- parented before the trees so their clear-spot check sees all the new decor
	task.wait()
	local trees, shrubs = greenery(root)

	local parts, lights = 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
		end
	end
	return ("Camp polished: %d RV parts, %d park parts (%d trees, %d shrubs), %d lights"):format(rvParts, parts, trees, shrubs, lights)
end

return Builder
