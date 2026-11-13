--!strict
-- DEV TOOL (never required by game code). Builds the 4 construction sites in Workspace.Sites:
-- chain-link fence with a road gate, site office trailer, dumpster, porta-potties, staging and delivery signs,
-- floodlights and a tier/pay sign. Also adds the "start job" buttons under the RV park site board and retires
-- the gray-box yard (old job board removed, spawn moved into the RV park until stage 4 adds RV spawns).
-- The job itself (ghost slots, material piles) is built at runtime by JobService at the same place.
-- Run in Studio Edit mode:  require(game.ServerStorage.DevTools.SiteBuilder).All()   (safe to re-run)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Layout = require(ReplicatedStorage.Shared.Config.TownLayout) :: any
local Display = require(ReplicatedStorage.Shared.Config.Sites) :: any
local SitesConfig = require(ServerStorage.Config.Sites) :: any
local JobsConfig = require(ServerStorage.Config.Jobs) :: any

local Builder = {}

local C = Color3.fromRGB
local M = Enum.Material
local WARM = C(255, 205, 150)
local TIER_COLORS = { C(60, 140, 80), C(40, 100, 170), C(200, 120, 30), C(120, 60, 150) }
local GATE = 16 -- half width of the road gate

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

local function paint(p: Part)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function light(part: BasePart, kind: string, range: number, brightness: number)
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
		t.TextColor3 = line.color or C(250, 248, 240)
		t.Text = line.text
		t.Parent = sg
	end
	sg.Parent = part
end

local function money(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end

local function lotOf(id: string): any
	for _, lot in Layout.Lots do
		if lot.Id == id then
			return lot
		end
	end
	error("TownLayout has no lot " .. id)
end

local function displayOf(tier: number): any
	for _, s in Display do
		if s.Tier == tier then
			return s
		end
	end
	return { Name = "Site " .. tier }
end

local function buildSite(siteId: string, parent: Instance): number
	local cfg = SitesConfig[siteId]
	local lot = lotOf(siteId)
	local job = JobsConfig[cfg.Job]
	local bp = require(ReplicatedStorage.Shared.Blueprints:FindFirstChild(job.Blueprint) :: ModuleScript) :: any
	local disp = displayOf(cfg.Tier)
	local tint = TIER_COLORS[cfg.Tier] or TIER_COLORS[1]

	-- Same placement JobService uses: lot center, turned so local -Z (front) faces the road gate.
	local center = Vector3.new((lot.Min.X + lot.Max.X) / 2, 0, (lot.Min.Y + lot.Max.Y) / 2)
	local O = CFrame.new(center) * CFrame.Angles(0, cfg.Yaw, 0)
	local sideways = math.abs(math.sin(cfg.Yaw)) > 0.5
	local wx, wz = (lot.Max.X - lot.Min.X) / 2, (lot.Max.Y - lot.Min.Y) / 2
	local hx, hz = if sideways then wz else wx, if sideways then wx else wz
	local function at(x: number, y: number, z: number): CFrame
		return O * CFrame.new(x, y, z)
	end
	local function facing(x: number, y: number, z: number, tx: number, tz: number): CFrame
		return O * CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(tx, y, tz))
	end

	local m = Instance.new("Model")
	m.Name = siteId
	m:SetAttribute("Tier", cfg.Tier)

	-- Chain-link fence: steel posts, top rail, see-through mesh. Open gate at the front (road side).
	local fence = model("Fence", m)
	local fx, fz = hx - 2, hz - 2
	local function run(a: Vector3, b: Vector3)
		local d = b - a
		local len = d.Magnitude
		if len < 2 then
			return
		end
		local n = math.max(1, math.floor(len / 10 + 0.5))
		for i = 0, n do
			local p = a + d * (i / n)
			box("Post", Vector3.new(0.4, 7, 0.4), at(p.X, 3.5, p.Z), C(150, 152, 156), M.Metal, fence)
		end
		local mid = (a + b) / 2
		local alongX = math.abs(d.X) > 0
		box("TopRail", if alongX then Vector3.new(len, 0.3, 0.3) else Vector3.new(0.3, 0.3, len), at(mid.X, 6.9, mid.Z),
			C(150, 152, 156), M.Metal, fence)
		local mesh = box("Mesh", if alongX then Vector3.new(len, 6.4, 0.1) else Vector3.new(0.1, 6.4, len), at(mid.X, 3.4, mid.Z),
			C(165, 170, 175), M.Fabric, fence)
		mesh.Transparency = 0.6
		mesh.CastShadow = false
	end
	run(Vector3.new(-fx, 0, -fz), Vector3.new(-GATE, 0, -fz))
	run(Vector3.new(GATE, 0, -fz), Vector3.new(fx, 0, -fz))
	run(Vector3.new(-fx, 0, fz), Vector3.new(fx, 0, fz))
	run(Vector3.new(-fx, 0, -fz), Vector3.new(-fx, 0, fz))
	run(Vector3.new(fx, 0, -fz), Vector3.new(fx, 0, fz))
	for _, x in { -GATE, GATE } do
		box("GatePost", Vector3.new(0.8, 8, 0.8), at(x, 4, -fz), C(230, 140, 30), M.Metal, fence)
	end

	-- Tier / pay sign just inside the gate, facing the road
	local sign = model("TierSign", m)
	local sx, sz = GATE + 14, -fz + 3
	for _, dx in { -6, 6 } do
		box("SignPost", Vector3.new(0.6, 10, 0.6), at(sx + dx, 5, sz + 0.4), C(110, 80, 50), M.Wood, sign)
	end
	local board = box("Board", Vector3.new(14, 7, 0.4), facing(sx, 7, sz, sx, sz - 30), tint, M.Metal, sign)
	local lines = {
		{ text = "SITE " .. cfg.Tier, size = 0.22, color = C(255, 230, 150) },
		{ text = string.upper(disp.Name), size = 0.3 },
		{ text = ("TIER %d  |  %s each  |  %d min"):format(cfg.Tier, money(job.BasePay), job.Deadline // 60), size = 0.2 },
	}
	if cfg.Release ~= "Launch" then
		table.insert(lines, { text = "COMING IN AN UPDATE", size = 0.16, color = C(255, 170, 160) })
	end
	surfaceText(board, Enum.NormalId.Front, lines, 30)
	surfaceText(board, Enum.NormalId.Back, { { text = "SITE " .. cfg.Tier .. " - " .. string.upper(disp.Name), size = 0.4 } }, 30)

	-- Site office trailer near the front-left corner, door facing into the site
	local tr = model("SiteTrailer", m)
	local tx, tz = -hx + 20, -hz + 16
	for _, o in { { -9, -2.6 }, { 9, -2.6 }, { -9, 2.6 }, { 9, 2.6 } } do
		box("Block", Vector3.new(1.6, 1.2, 1.6), at(tx + o[1], 0.6, tz + o[2]), C(150, 150, 145), M.Concrete, tr)
	end
	box("Body", Vector3.new(22, 7, 8), at(tx, 4.7, tz), C(235, 235, 230), M.Metal, tr)
	box("Roof", Vector3.new(22.4, 0.3, 8.4), at(tx, 8.35, tz), C(200, 200, 200), M.Metal, tr)
	box("Stripe", Vector3.new(22.1, 0.6, 8.1), at(tx, 2.2, tz), C(40, 90, 150), M.Metal, tr)
	box("Door", Vector3.new(2.6, 5.6, 0.2), at(tx + 5, 4, tz + 4.05), C(120, 120, 125), M.Metal, tr)
	for _, wo in { -7, -2.5 } do
		box("Window", Vector3.new(3.4, 2, 0.2), at(tx + wo, 5.4, tz + 4.05), C(40, 55, 70), M.Glass, tr).Transparency = 0.2
	end
	box("Step", Vector3.new(3.4, 0.6, 2.4), at(tx + 5, 0.3, tz + 5.4), C(110, 80, 50), M.WoodPlanks, tr)
	box("Step", Vector3.new(3.4, 0.6, 1.2), at(tx + 5, 0.9, tz + 4.8), C(110, 80, 50), M.WoodPlanks, tr)
	local office = box("OfficeSign", Vector3.new(8, 1.6, 0.2), facing(tx - 3, 7.4, tz + 4.15, tx - 3, tz + 30), C(250, 250, 245), M.Metal, tr)
	surfaceText(office, Enum.NormalId.Front, { { text = "SITE OFFICE", size = 1, color = C(40, 40, 45) } }, 40)
	local porch = box("PorchLight", Vector3.new(0.6, 0.4, 0.4), at(tx + 5, 7.3, tz + 4.3), WARM, M.Neon, tr)
	paint(porch)
	light(porch, "point", 18, 1.3)

	-- Dumpster at the back-right corner
	local dump = model("Dumpster", m)
	local dx, dz = hx - 14, hz - 10
	box("Bin", Vector3.new(14, 5, 7), at(dx, 2.7, dz), C(40, 90, 55), M.CorrodedMetal, dump)
	box("Lip", Vector3.new(14.4, 0.4, 7.4), at(dx, 5.3, dz), C(30, 70, 45), M.Metal, dump)
	for _, o in { -5, 5 } do
		box("Skid", Vector3.new(0.8, 0.4, 7.4), at(dx + o, 0.2, dz), C(40, 40, 42), M.Metal, dump)
	end
	box("Debris", Vector3.new(6, 1.2, 3), at(dx - 2, 5.2, dz + 1) * CFrame.Angles(0.2, 0.3, 0), C(150, 120, 90), M.WoodPlanks, dump)

	-- Porta-potties at the back-left (two on the bigger sites)
	local potties = model("PortaPotties", m)
	for i = 1, if cfg.Tier >= 3 then 2 else 1 do
		local px, pz = -hx + 8 + (i - 1) * 5.5, hz - 8
		box("Body", Vector3.new(4.4, 7.6, 4.4), at(px, 3.8, pz), C(40, 95, 175), M.Metal, potties)
		box("Roof", Vector3.new(4.8, 0.4, 4.8), at(px, 7.8, pz), C(235, 235, 235), M.Metal, potties)
		box("Door", Vector3.new(3, 6.2, 0.15), at(px, 3.6, pz - 2.25), C(30, 80, 150), M.Metal, potties)
		box("Vent", Vector3.new(0.5, 1.4, 0.5), at(px + 1.4, 8.6, pz + 1.4), C(60, 60, 62), M.Metal, potties)
	end

	-- Staging signs next to the blueprint's material piles: building materials on the left, electrical on the right
	local staging = model("Staging", m)
	local function pileGroup(left: boolean): (number, number, number, number)
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, p in bp.Piles do
			if (p.Pos.X < 0) == left then
				minX, maxX = math.min(minX, p.Pos.X), math.max(maxX, p.Pos.X)
				minZ, maxZ = math.min(minZ, p.Pos.Z), math.max(maxZ, p.Pos.Z)
			end
		end
		return minX, maxX, minZ, maxZ
	end
	local function groupSign(label: string, x: number, z: number, color: Color3)
		box("SignPost", Vector3.new(0.5, 6, 0.5), at(x, 3, z), C(110, 80, 50), M.Wood, staging)
		local s = box("Sign", Vector3.new(7, 1.8, 0.2), facing(x, 5.6, z, x, z - 30), color, M.Metal, staging)
		surfaceText(s, Enum.NormalId.Front, { { text = label, size = 1, color = C(30, 30, 30) } }, 40)
		surfaceText(s, Enum.NormalId.Back, { { text = label, size = 1, color = C(30, 30, 30) } }, 40)
	end
	local minX, _, minZ, maxZ = pileGroup(true)
	if minX < math.huge then
		groupSign("STAGING", minX - 6, minZ - 4, C(250, 200, 40))
		for k = 0, 1 do
			local z = (minZ + maxZ) / 2 + (k - 0.5) * 8
			box("Pallet", Vector3.new(4, 0.4, 6), at(minX - 6, 0.2, z), C(160, 125, 85), M.Wood, staging)
			box("SpareLumber", Vector3.new(3.4, 1.4, 5.6), at(minX - 6, 1.1, z), C(200, 160, 110), M.WoodPlanks, staging)
		end
	end
	local _, eMaxX, _, eMaxZ = pileGroup(false)
	if eMaxX > -math.huge then
		groupSign("ELECTRICAL", eMaxX + 6, eMaxZ + 4, C(240, 200, 40))
	end

	-- Delivery sign beside the truck pad
	for _, def in bp.Slots do
		if def.Kind == "Deliver" then
			local px, pz = def.Pos.X + def.Size.X / 2 + 3, def.Pos.Z - def.Size.Z / 2
			box("DeliveryPost", Vector3.new(0.5, 6, 0.5), at(px, 3, pz), C(110, 80, 50), M.Wood, staging)
			local ds = box("DeliverySign", Vector3.new(7, 2.4, 0.2), facing(px, 5.4, pz, px, pz - 30), C(250, 250, 245), M.Metal, staging)
			surfaceText(ds, Enum.NormalId.Front, {
				{ text = "DELIVERY", size = 0.6, color = C(30, 30, 30) },
				{ text = "park the truck here", size = 0.35, color = C(60, 60, 60) },
			}, 40)
		end
	end

	-- Floodlights (front corners; back corners too on the bigger sites)
	local corners = { { -fx + 4, -fz + 4 }, { fx - 4, -fz + 4 } }
	if cfg.Tier >= 3 then
		table.insert(corners, { -fx + 4, fz - 4 })
		table.insert(corners, { fx - 4, fz - 4 })
	end
	local lights = model("Floodlights", m)
	for _, c in corners do
		local pole = box("Pole", Vector3.new(20, 0.9, 0.9), at(c[1], 10, c[2]) * CFrame.Angles(0, 0, math.pi / 2), C(70, 72, 76), M.Metal, lights)
		pole.Shape = Enum.PartType.Cylinder
		box("Head", Vector3.new(3, 0.8, 3), at(c[1], 20.2, c[2]), C(70, 72, 76), M.Metal, lights)
		local lens = box("Lens", Vector3.new(2.4, 0.15, 2.4), at(c[1], 19.75, c[2]), WARM, M.Neon, lights)
		paint(lens)
		light(lens, "spot", 70, 3)
	end

	-- The stage-1 temporary sign at this lot is replaced by the tier sign.
	local lots = workspace:FindFirstChild("Town") and workspace.Town:FindFirstChild("Lots")
	local marker = lots and lots:FindFirstChild(siteId)
	local temp = marker and marker:FindFirstChild("TempSign")
	if temp then
		temp:Destroy()
	end

	m.Parent = parent
	local n = 0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- "Start job" buttons in front of the RV park site board (JobService adds the prompts at runtime).
local function buildBoardButtons(): number
	local park = workspace:FindFirstChild("RVPark")
	local truckLot = park and park:FindFirstChild("TruckLot")
	if not truckLot then
		warn("[SiteBuilder] No RVPark.TruckLot: build the RV park first")
		return 0
	end
	local old = truckLot:FindFirstChild("SiteButtons")
	if old then
		old:Destroy()
	end
	local f = model("SiteButtons", truckLot)
	for k, siteId in SitesConfig.Order do
		local cfg = SitesConfig[siteId]
		local x = 68 + (k - 2.5) * 7
		box("ButtonPost", Vector3.new(0.6, 3, 0.6), CFrame.new(x, 1.5, -361.4), C(70, 72, 76), M.Metal, f)
		local b = box("Button_" .. siteId, Vector3.new(4.4, 2.4, 0.6), CFrame.lookAt(Vector3.new(x, 4, -361), Vector3.new(x, 4, -330)),
			TIER_COLORS[cfg.Tier] or TIER_COLORS[1], M.Metal, f)
		b:SetAttribute("StartSite", siteId)
		surfaceText(b, Enum.NormalId.Front, {
			{ text = "SITE " .. cfg.Tier, size = 0.55 },
			{ text = string.upper(displayOf(cfg.Tier).Name), size = 0.35, color = C(230, 235, 240) },
		}, 40)
	end
	return #SitesConfig.Order
end

-- The gray-box yard is retired: its job board goes away and players spawn on the RV park camp lane
-- until the stage 4 session flow spawns each player at their own RV.
local function retireYard(): string
	local hub = workspace:FindFirstChild("Hub")
	if hub then
		hub:Destroy()
	end
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		spawn.Size = Vector3.new(10, 1, 10)
		spawn.CFrame = CFrame.new(-110, 0.5, -288)
		spawn.Material = M.Concrete
		spawn.Color = C(160, 160, 155)
		return "spawn moved to the RV park"
	end
	return "no SpawnLocation found"
end

function Builder.All(): string
	local root = workspace:FindFirstChild("Sites")
	if root then
		root:Destroy()
	end
	local sites = Instance.new("Folder")
	sites.Name = "Sites"
	sites.Parent = workspace
	local counts = {}
	for _, siteId in SitesConfig.Order do
		table.insert(counts, ("%s=%d parts"):format(siteId, buildSite(siteId, sites)))
		task.wait()
	end
	local buttons = buildBoardButtons()
	return ("sites built: %s; %d board buttons; %s"):format(table.concat(counts, ", "), buttons, retireYard())
end

return Builder
