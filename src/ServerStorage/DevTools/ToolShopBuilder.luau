--!strict
-- EDIT-TIME ONLY (2026-11-13). Builds Workspace.ToolShop on the south side of Main St, east of the gas station, facing
-- the road: brick store with shop windows, door opening, awning, lit sign, parking apron; inside a counter (the
-- "Counter" part: ToolShopService puts the Browse tools prompt on it), a pegboard wall of tools, stocked shelves and a
-- display. Clears the pines standing in its footprint. Re-running replaces it. Run: require(this).Build()
local MaterialService = game:GetService("MaterialService")

local Builder = {}

local C = Color3.fromRGB
local M = Enum.Material
-- local frame: front (shop windows) toward -Z = toward Main St
local ORIGIN = CFrame.new(240, 0, -468) * CFrame.Angles(0, math.pi, 0)
local W, D, H = 38, 26, 14

local model: Model

local function part(name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = ORIGIN * lcf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function clearTrees()
	local nature = workspace:FindFirstChild("Nature")
	if not nature then
		return 0
	end
	local center = (ORIGIN * at(0, 0, -6)).Position
	local n = 0
	for _, d in nature:GetDescendants() do
		if d:IsA("Model") and d:FindFirstChild("TrunkCollider", true) then
			local p = d:GetPivot().Position
			if math.abs(p.X - center.X) < 34 and math.abs(p.Z - center.Z) < 34 then
				d:Destroy()
				n += 1
			end
		end
	end
	return n
end

local function tool(kind: string, x: number, y: number)
	local z = D / 2 - 1.1
	if kind == "hammer" then
		part("Hammer", Vector3.new(0.3, 2.2, 0.3), at(x, y, z), C(150, 105, 60), M.Wood, false)
		part("HammerHead", Vector3.new(1.3, 0.5, 0.5), at(x, y + 1.1, z), C(90, 92, 98), M.Metal, false)
	elseif kind == "wrench" then
		part("Wrench", Vector3.new(0.35, 2.4, 0.15), at(x, y, z) * CFrame.Angles(0, 0, 0.3), C(190, 192, 198), M.Metal, false)
		part("WrenchJaw", Vector3.new(0.8, 0.4, 0.15), at(x + 0.35, y + 1.15, z) * CFrame.Angles(0, 0, 0.3), C(190, 192, 198), M.Metal, false)
	elseif kind == "drill" then
		part("Drill", Vector3.new(1.6, 0.8, 0.6), at(x, y + 0.5, z), C(230, 160, 30), M.Metal, false)
		part("DrillGrip", Vector3.new(0.5, 1.2, 0.5), at(x - 0.4, y - 0.3, z), C(40, 40, 44), M.Rubber, false)
		part("DrillBit", Vector3.new(0.9, 0.15, 0.15), at(x + 1.2, y + 0.5, z), C(160, 160, 165), M.Metal, false)
	elseif kind == "saw" then
		part("SawBlade", Vector3.new(2.6, 0.8, 0.08), at(x, y, z), C(200, 202, 208), M.Metal, false)
		part("SawGrip", Vector3.new(0.7, 0.9, 0.3), at(x - 1.5, y + 0.1, z), C(160, 40, 35), M.Wood, false)
	else -- level
		part("Level", Vector3.new(3, 0.45, 0.25), at(x, y, z), C(240, 200, 40), M.Metal, false)
		part("LevelVial", Vector3.new(0.5, 0.3, 0.27), at(x, y, z), C(150, 230, 120), M.Glass, false)
	end
end

local function shelf(x: number, z: number, faceX: number)
	part("ShelfSide", Vector3.new(1.8, 7, 0.2), at(x, 3.8, z - 3), C(70, 72, 78), M.Metal)
	part("ShelfSide", Vector3.new(1.8, 7, 0.2), at(x, 3.8, z + 3), C(70, 72, 78), M.Metal)
	local colors = { C(200, 70, 50), C(60, 110, 190), C(230, 170, 40), C(70, 150, 80), C(120, 120, 128) }
	for k, y in { 1.2, 3.4, 5.6 } do
		part("Shelf", Vector3.new(1.8, 0.2, 6.2), at(x, y, z), C(90, 92, 98), M.Metal)
		for i = 0, 4 do
			local c = colors[(i + k) % #colors + 1]
			part("Stock", Vector3.new(1.2, 1.2, 0.9), at(x + faceX * 0.1, y + 0.7, z - 2.4 + i * 1.2), c, M.Fabric, false)
		end
	end
end

function Builder.Build()
	local old = workspace:FindFirstChild("ToolShop")
	if old then
		old:Destroy()
	end
	local cleared = clearTrees()
	model = Instance.new("Model")
	model.Name = "ToolShop"

	local brick = C(156, 88, 64)
	local trim = C(240, 238, 230)
	local dark = C(48, 50, 56)
	-- floor, apron, parking lines
	part("Floor", Vector3.new(W, 0.6, D), at(0, 0.3, 0), C(176, 172, 164), M.Concrete)
	part("Apron", Vector3.new(W + 6, 0.12, 30), at(0, 0.06, -D / 2 - 15), C(58, 60, 64), M.Asphalt)
	for i = -2, 2 do
		part("ParkingLine", Vector3.new(0.3, 0.14, 9), at(i * 7.6, 0.08, -D / 2 - 22), C(235, 235, 230), M.Concrete, false)
	end
	part("Step", Vector3.new(10, 0.5, 3), at(0, 0.25, -D / 2 - 1.5), C(170, 168, 160), M.Concrete)

	-- walls
	local walls = {
		part("WallBack", Vector3.new(W, H, 0.8), at(0, H / 2 + 0.6, D / 2 - 0.4), brick, M.Brick),
		part("WallLeft", Vector3.new(0.8, H, D), at(-W / 2 + 0.4, H / 2 + 0.6, 0), brick, M.Brick),
		part("WallRight", Vector3.new(0.8, H, D), at(W / 2 - 0.4, H / 2 + 0.6, 0), brick, M.Brick),
		part("FrontLeft", Vector3.new(9, H, 0.8), at(-W / 2 + 4.5, H / 2 + 0.6, -D / 2 + 0.4), brick, M.Brick),
		part("FrontRight", Vector3.new(9, H, 0.8), at(W / 2 - 4.5, H / 2 + 0.6, -D / 2 + 0.4), brick, M.Brick),
		part("Header", Vector3.new(W - 18, 4, 0.8), at(0, H - 1.4, -D / 2 + 0.4), brick, M.Brick),
	}
	for _, side in { -1, 1 } do
		table.insert(walls, part("Bulkhead", Vector3.new(7, 2.6, 0.8), at(side * 6.5, 1.9, -D / 2 + 0.4), brick, M.Brick))
		local glass = part("ShopWindow", Vector3.new(7, 7.4, 0.3), at(side * 6.5, 6.9, -D / 2 + 0.4), C(140, 180, 200), M.Glass)
		glass.Transparency = 0.55
		glass.Reflectance = 0.15
		part("Mullion", Vector3.new(0.3, 7.4, 0.5), at(side * 6.5, 6.9, -D / 2 + 0.4), dark, M.Metal, false)
		part("WindowSill", Vector3.new(7.4, 0.3, 0.9), at(side * 6.5, 3.25, -D / 2 + 0.2), trim, M.Concrete, false)
		part("DoorJamb", Vector3.new(0.5, 10, 0.9), at(side * 3.25, 5.6, -D / 2 + 0.4), dark, M.Metal, false)
	end
	if MaterialService:FindFirstChild("CoopBrick") then
		for _, w in walls do
			w.MaterialVariant = "CoopBrick"
		end
	end
	part("DoorHead", Vector3.new(7, 0.5, 0.9), at(0, 10.6, -D / 2 + 0.4), dark, M.Metal, false)
	local open = part("OpenSign", Vector3.new(2.4, 0.9, 0.15), at(-6.5, 8.6, -D / 2 + 0.2), C(255, 80, 60), M.Neon, false)
	open.Name = "OpenSign"

	-- roof, parapet, awning, sign
	part("Roof", Vector3.new(W + 1, 0.8, D + 1), at(0, H + 1, 0), C(62, 64, 70), M.Concrete)
	part("Parapet", Vector3.new(W + 1, 1.6, 0.8), at(0, H + 2.2, -D / 2 - 0.1), C(230, 120, 30), M.Metal)
	local awning = part("Awning", Vector3.new(26, 0.4, 5), at(0, 11.4, -D / 2 - 2.4) * CFrame.Angles(math.rad(-12), 0, 0), C(230, 120, 30), M.Fabric)
	awning.CastShadow = true
	for _, x in { -12, 12 } do
		part("AwningArm", Vector3.new(0.3, 0.3, 5), at(x, 11.0, -D / 2 - 2.4) * CFrame.Angles(math.rad(-12), 0, 0), dark, M.Metal, false)
	end
	local sign = part("Sign", Vector3.new(24, 4.2, 0.5), at(0, H + 5.2, -D / 2 - 0.1), C(30, 32, 38), M.Metal)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	sg.Parent = sign
	local function label(t: string, y: number, h: number, color: Color3, font: Enum.Font)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.04, y)
		l.Size = UDim2.fromScale(0.92, h)
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = t
		l.Parent = sg
	end
	label("TOOL SHOP", 0.06, 0.6, C(255, 170, 40), Enum.Font.GothamBlack)
	label("TOOLS FOR EVERY TRADE", 0.66, 0.28, C(235, 235, 235), Enum.Font.GothamBold)
	for _, x in { -9, 0, 9 } do
		local lamp = part("SignLight", Vector3.new(1.2, 0.4, 0.8), at(x, H + 3, -D / 2 - 0.9), C(255, 235, 190), M.Neon, false)
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Top
		l.Range = 8
		l.Angle = 70
		l.Brightness = 1.5
		l.Parent = lamp
	end

	-- inside: lights, counter, pegboard with tools, shelves, display
	for _, x in { -10, 0, 10 } do
		local panel = part("CeilingLight", Vector3.new(6, 0.25, 2), at(x, H + 0.45, 0), C(255, 248, 230), M.Neon, false)
		local l = Instance.new("PointLight")
		l.Range = 20
		l.Brightness = 1.1
		l.Color = C(255, 244, 225)
		l.Parent = panel
	end
	local counter = part("Counter", Vector3.new(12, 3.4, 2.6), at(0, 2.3, 4), C(120, 84, 52), M.WoodPlanks)
	counter.Name = "Counter"
	part("CounterTop", Vector3.new(12.6, 0.3, 3), at(0, 4.15, 4), C(60, 62, 66), M.Granite)
	part("Register", Vector3.new(1.6, 1.1, 1.2), at(3.5, 4.85, 4), C(40, 42, 46), M.Metal, false)
	part("RegisterScreen", Vector3.new(1.2, 0.8, 0.1), at(3.5, 5.6, 3.6) * CFrame.Angles(math.rad(-15), 0, 0), C(80, 200, 255), M.Neon, false)
	part("CounterMat", Vector3.new(3, 0.05, 1.6), at(-2.5, 4.32, 4), C(30, 30, 32), M.Rubber, false)
	part("Pegboard", Vector3.new(30, 7, 0.2), at(0, 6.6, D / 2 - 0.9), C(196, 166, 116), M.Wood, false)
	local kinds = { "hammer", "wrench", "drill", "saw", "level" }
	for i = 0, 9 do
		tool(kinds[i % #kinds + 1], -13 + i * 2.9, if i % 2 == 0 then 8 else 5.6)
	end
	shelf(-W / 2 + 2, -3, 1)
	shelf(-W / 2 + 2, 5, 1)
	shelf(W / 2 - 2, -3, -1)
	shelf(W / 2 - 2, 5, -1)
	-- display pallet: a welding machine and an AC unit
	part("Pallet", Vector3.new(7, 0.5, 4), at(0, 0.85, -5), C(160, 125, 80), M.WoodPlanks)
	part("Welder", Vector3.new(2, 2.2, 3), at(-1.8, 2.2, -5), C(40, 90, 170), M.Metal)
	part("WelderFace", Vector3.new(1.4, 1.2, 0.1), at(-1.8, 2.4, -6.55), C(30, 30, 34), M.Metal, false)
	part("ACDisplay", Vector3.new(2.6, 2.6, 2.6), at(1.8, 2.4, -5), C(220, 222, 224), M.Metal)
	part("ACFan", Vector3.new(2, 0.1, 2), at(1.8, 3.75, -5), C(50, 52, 56), M.DiamondPlate, false)

	model.PrimaryPart = model:FindFirstChild("Floor") :: BasePart
	model.Parent = workspace
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return ("ToolShop built: %d parts, %d trees cleared"):format(n, cleared)
end

return Builder
