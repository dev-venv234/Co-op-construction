--!strict
-- Edit-time only: builds Workspace.SupplyStore, the crew's building-supply yard in front of the hardware store
-- (TownLayout lot "Hardware", gate on Main St). It replaces the old RV park loading dock: drive the truck under the
-- LOADING canopy, grab bundles from the stacks on the dock (parts with a MaterialStack attribute) and tap the truck bed.
-- JobService finds the stacks and the "Dock" part at Start. Pickup is free (the job supplies the materials).
-- Run: require(game.ServerStorage.DevTools.SupplyStoreBuilder).Build()
local Builder = {}

local C = Color3.fromRGB
local M = Enum.Material
local WARM = C(255, 225, 170)

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
	s.Parent = part
end

-- A tall steel rack loaded with bundles (decoration: the yard looks like a real lumber yard).
local function rack(parent: Instance, at: Vector3, length: number, color: Color3, mat: Enum.Material, levels: number)
	local steel = C(40, 90, 160)
	local m = Instance.new("Model")
	m.Name = "Rack"
	for i = 0, math.floor(length / 10) do
		local x = at.X - length / 2 + i * (length / math.floor(length / 10))
		for _, dz in { -2.6, 2.6 } do
			box("Upright", Vector3.new(0.6, levels * 4 + 1, 0.6), CFrame.new(x, (levels * 4 + 1) / 2, at.Z + dz), steel, M.Metal, m)
		end
	end
	for lv = 1, levels do
		local y = lv * 4 - 1.2
		for _, dz in { -2.6, 2.6 } do
			box("Beam", Vector3.new(length, 0.5, 0.4), CFrame.new(at.X, y, at.Z + dz), C(230, 120, 30), M.Metal, m)
		end
		for b = 0, math.floor(length / 7) - 1 do
			local bx = at.X - length / 2 + 3.5 + b * 7
			box("Bundle", Vector3.new(6, 1.6, 4.6), CFrame.new(bx, y + 1.05, at.Z), color, mat, m)
		end
	end
	m.Parent = parent
end

function Builder.Build()
	local old = workspace:FindFirstChild("SupplyStore")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Model")
	root.Name = "SupplyStore"

	-- Yard: concrete pad in front of the hardware store, between the store and Main St.
	box("YardPad", Vector3.new(140, 0.2, 52), CFrame.new(-102, 0.1, -458), C(150, 148, 142), M.Concrete, root)
	for x = -164, -40, 12 do
		box("YardJoint", Vector3.new(0.2, 0.05, 52), CFrame.new(x, 0.22, -458), C(120, 118, 112), M.Concrete, root, false)
	end

	-- LOADING canopy over a drive lane, raised dock on its south side (truck pulls alongside, bed against the dock).
	local steel = C(70, 72, 76)
	for _, x in { -138, -105, -72 } do
		for _, z in { -478, -440 } do
			box("CanopyPost", Vector3.new(0.9, 16, 0.9), CFrame.new(x, 8, z), steel, M.Metal, root)
		end
	end
	box("CanopyRoof", Vector3.new(72, 0.5, 42), CFrame.new(-105, 16.25, -459), C(95, 100, 105), M.CorrodedMetal, root)
	box("CanopyFascia", Vector3.new(72, 2.2, 0.4), CFrame.new(-105, 15.2, -438), C(230, 120, 30), M.Metal, root)
	local fascia = box("CanopySign", Vector3.new(40, 2, 0.2), CFrame.new(-105, 15.2, -437.7), C(230, 120, 30), M.Metal, root, false)
	text(fascia, Enum.NormalId.Back, { { "CREW SUPPLY - LOADING", 1, C(30, 30, 30) } }, 24)
	for _, x in { -128, -105, -82 } do
		local l = box("CanopyLight", Vector3.new(3, 0.2, 3), CFrame.new(x, 15.9, -459), WARM, M.Neon, root, false)
		nightLamp(l, 36, 1.8)
	end

	box("Dock", Vector3.new(56, 2, 9), CFrame.new(-105, 1, -474), C(165, 160, 155), M.Concrete, root)
	box("DockEdge", Vector3.new(56, 2.2, 0.6), CFrame.new(-105, 1.1, -469.2), C(230, 180, 40), M.DiamondPlate, root)
	for x = -129, -81, 8 do
		box("Bumper", Vector3.new(2, 1.2, 0.8), CFrame.new(x, 1.2, -468.6), C(30, 30, 30), M.Rubber, root)
	end
	box("DockStairs", Vector3.new(4, 1, 3), CFrame.new(-136, 0.5, -472), C(150, 150, 150), M.DiamondPlate, root)
	-- Lane arrows on the pad
	for _, x in { -125, -105, -85 } do
		box("LaneArrow", Vector3.new(6, 0.05, 1.2), CFrame.new(x, 0.23, -462), C(250, 220, 60), M.Concrete, root, false)
	end

	-- The loadable stacks (big pallet loads, several of each so it looks stocked)
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

	-- Lumber yard racks along both sides and the back (decoration)
	rack(root, Vector3.new(-160, 0, -458), 6, C(200, 160, 110), M.WoodPlanks, 3)
	rack(root, Vector3.new(-50, 0, -458), 6, C(185, 150, 105), M.WoodPlanks, 3)
	rack(root, Vector3.new(-150, 0, -482), 24, C(200, 160, 110), M.WoodPlanks, 3)
	rack(root, Vector3.new(-60, 0, -482), 24, C(130, 130, 138), M.CorrodedMetal, 3)
	-- Loose pallets and a few bagged-concrete stacks
	for i, p in { Vector3.new(-160, 0, -440), Vector3.new(-154, 0, -440), Vector3.new(-46, 0, -440), Vector3.new(-52, 0, -442) } do
		box("Pallet", Vector3.new(4, 0.5, 4), CFrame.new(p + Vector3.new(0, 0.25, 0)), C(160, 125, 85), M.Wood, root)
		if i % 2 == 0 then
			box("Bags", Vector3.new(3.6, 2, 3.6), CFrame.new(p + Vector3.new(0, 1.5, 0)), C(200, 195, 185), M.Fabric, root)
		end
	end

	-- Street sign pylon at the Main St gate
	box("PylonPost", Vector3.new(1.2, 22, 1.2), CFrame.new(-60, 11, -431), steel, M.Metal, root)
	box("PylonPost", Vector3.new(1.2, 22, 1.2), CFrame.new(-44, 11, -431), steel, M.Metal, root)
	local pylon = box("Pylon", Vector3.new(20, 9, 1), CFrame.new(-52, 17, -431), C(230, 120, 30), M.Metal, root)
	text(pylon, Enum.NormalId.Back, {
		{ "CREW SUPPLY", 0.5, C(255, 255, 255) },
		{ "LUMBER - SHEETS - PICKUP FOR JOBS", 0.28, C(30, 30, 30) },
	}, 24)
	local pylonLight = box("PylonLight", Vector3.new(18, 0.3, 0.6), CFrame.new(-52, 22, -430), WARM, M.Neon, root, false)
	nightLamp(pylonLight, 20, 1.2)

	root.Parent = workspace
	return root
end

return Builder
