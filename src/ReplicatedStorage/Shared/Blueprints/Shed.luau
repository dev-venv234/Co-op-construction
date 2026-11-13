--!strict
-- Tier 1 shed job: ghost-outline data. Positions are relative to Origin (studs). North = -Z.
-- Kinds: Place (bring Item, snap into ghost), Timing, Connect, Deliver (truck), Inspect (finish).
local C = Color3.fromRGB

local corners = {
	{ id = "NW", x = -6, z = 15 },
	{ id = "NE", x = 6, z = 15 },
	{ id = "SW", x = -6, z = 25 },
	{ id = "SE", x = 6, z = 25 },
}

local slots = {}
local function add(s)
	s.Requires = s.Requires or {}
	table.insert(slots, s)
end

-- Site prep + foundation: one chain per corner so the crew can work in parallel
for _, c in corners do
	add({ Id = "stake_" .. c.id, Kind = "Place", Item = "Stake", Role = "Foreman", Phase = "Site prep",
		Label = "Drive stake", Pos = Vector3.new(c.x, 1.5, c.z), Size = Vector3.new(0.4, 3, 0.4),
		Done = { Color = C(255, 140, 0), Material = "Wood" }, Collide = false })
	add({ Id = "hole_" .. c.id, Kind = "Timing", Role = "Operator", Phase = "Site prep", Equipment = "Excavator", Reach = 18,
		Label = "Dig post hole", Requires = { "stake_" .. c.id },
		Pos = Vector3.new(c.x, 0.15, c.z), Size = Vector3.new(2, 0.3, 2),
		Done = { Color = C(60, 40, 25), Material = "Ground" }, Collide = false })
	add({ Id = "post_" .. c.id, Kind = "Place", Item = "Post", Role = "Laborer", Phase = "Foundation",
		Label = "Set post", Requires = { "hole_" .. c.id },
		Pos = Vector3.new(c.x, 3.5, c.z), Size = Vector3.new(1, 7, 1),
		Done = { Color = C(150, 110, 70), Material = "Wood" } })
	add({ Id = "pour_" .. c.id, Kind = "Timing", Role = "Laborer", Phase = "Foundation",
		Label = "Pour concrete", Requires = { "post_" .. c.id },
		Pos = Vector3.new(c.x, 0.25, c.z), Size = Vector3.new(2.4, 0.5, 2.4),
		Done = { Color = C(170, 170, 165), Material = "Concrete" } })
end

add({ Id = "deliver", Kind = "Deliver", Role = "Operator", Phase = "Site prep",
	Label = "Unload lumber", Pos = Vector3.new(22, 0.1, -4), Size = Vector3.new(18, 0.2, 18), Reach = 20,
	Done = { Color = C(150, 150, 150), Material = "Concrete", Transparency = 0.6 }, Collide = false })

add({ Id = "level", Kind = "Timing", Role = "Foreman", Phase = "Foundation",
	Label = "Level check", Requires = { "pour_NW", "pour_NE", "pour_SW", "pour_SE" },
	Pos = Vector3.new(0, 1.5, 10), Size = Vector3.new(1, 3, 1),
	Done = { Color = C(255, 220, 0), Material = "Metal" }, Collide = false })

-- Framing
add({ Id = "floor_1", Kind = "Place", Item = "Lumber", Role = "Laborer", Phase = "Framing",
	Label = "Lay floor", Requires = { "level", "deliver" },
	Pos = Vector3.new(0, 1.1, 17.5), Size = Vector3.new(12.6, 0.4, 5),
	Done = { Color = C(200, 160, 110), Material = "WoodPlanks" } })
add({ Id = "floor_2", Kind = "Place", Item = "Lumber", Role = "Laborer", Phase = "Framing",
	Label = "Lay floor", Requires = { "level", "deliver" },
	Pos = Vector3.new(0, 1.1, 22.5), Size = Vector3.new(12.6, 0.4, 5),
	Done = { Color = C(200, 160, 110), Material = "WoodPlanks" } })

local walls = {
	{ id = "N", pos = Vector3.new(0, 4.8, 15), size = Vector3.new(12.6, 7, 0.5), nail = Vector3.new(0, 3, 14.2), role = "Laborer" },
	{ id = "S", pos = Vector3.new(0, 4.8, 25), size = Vector3.new(12.6, 7, 0.5), nail = Vector3.new(0, 3, 25.8), role = "Laborer", door = true },
	{ id = "W", pos = Vector3.new(-6, 4.8, 20), size = Vector3.new(0.5, 7, 9.5), nail = Vector3.new(-6.8, 3, 20), role = "Foreman" },
	{ id = "E", pos = Vector3.new(6, 4.8, 20), size = Vector3.new(0.5, 7, 9.5), nail = Vector3.new(6.8, 3, 20), role = "Foreman" },
}
for _, w in walls do
	add({ Id = "wall_" .. w.id, Kind = "Place", Item = "Lumber", Role = "Laborer", Phase = "Framing",
		Label = "Raise wall", Requires = { "floor_1", "floor_2" }, Pos = w.pos, Size = w.size,
		Done = { Color = C(215, 180, 130), Material = "WoodPlanks" }, Collide = not w.door })
	add({ Id = "nail_" .. w.id, Kind = "Timing", Role = w.role, Phase = "Framing",
		Label = if w.role == "Foreman" then "Brace & nail wall" else "Nail wall", Requires = { "wall_" .. w.id },
		Pos = w.nail, Size = Vector3.new(0.8, 0.8, 0.8),
		Done = { Color = C(90, 90, 95), Material = "Metal" }, Collide = false })
end

-- Roof
add({ Id = "roof", Kind = "Timing", Role = "Operator", Phase = "Roof",
	Label = "Hoist roof frame", Requires = { "nail_N", "nail_S", "nail_W", "nail_E" },
	Pos = Vector3.new(0, 8.6, 20), Size = Vector3.new(13.4, 0.5, 11),
	Done = { Color = C(190, 150, 100), Material = "WoodPlanks" } })
add({ Id = "sheet_1", Kind = "Place", Item = "Sheet", Role = "Laborer", Phase = "Roof",
	Label = "Lay roof sheet", Requires = { "roof" },
	Pos = Vector3.new(0, 9.05, 17.5), Size = Vector3.new(13.4, 0.3, 5),
	Done = { Color = C(120, 120, 130), Material = "CorrodedMetal" } })
add({ Id = "sheet_2", Kind = "Place", Item = "Sheet", Role = "Laborer", Phase = "Roof",
	Label = "Lay roof sheet", Requires = { "roof" },
	Pos = Vector3.new(0, 9.05, 22.5), Size = Vector3.new(13.4, 0.3, 5),
	Done = { Color = C(120, 120, 130), Material = "CorrodedMetal" } })
add({ Id = "light", Kind = "Connect", Role = "Electrician", Phase = "Roof",
	Label = "Wire work light", Requires = { "roof" },
	Pos = Vector3.new(11, 1.5, 28), Size = Vector3.new(2, 3, 2),
	Done = { Color = C(255, 230, 120), Material = "Neon" } })

-- Inspection needs everything else done
local everything = {}
for _, s in slots do
	table.insert(everything, s.Id)
end
add({ Id = "inspect", Kind = "Inspect", Role = "Foreman", Phase = "Inspection",
	Label = "Call inspection", Requires = everything,
	Pos = Vector3.new(-3, 2, 8), Size = Vector3.new(1, 4, 1),
	Done = { Color = C(60, 120, 220), Material = "Metal" } })

return {
	Id = "Shed",
	DisplayName = "Shed",
	Origin = Vector3.new(0, 0, 100),
	Items = {
		Stake = { Size = Vector3.new(0.4, 3, 0.4), Color = C(255, 140, 0), Material = "Wood", WalkSpeed = 16,
			Hold = CFrame.new(0.8, 0, -1.4) },
		Post = { Size = Vector3.new(1, 7, 1), Color = C(150, 110, 70), Material = "Wood", WalkSpeed = 13,
			Hold = CFrame.new(0, 0.5, -1.6) },
		Lumber = { Size = Vector3.new(1, 1, 8), Color = C(200, 160, 110), Material = "WoodPlanks", WalkSpeed = 12,
			Hold = CFrame.new(0, 1.8, 0) * CFrame.Angles(0, math.pi / 2, 0) },
		Sheet = { Size = Vector3.new(4, 0.3, 6), Color = C(120, 120, 130), Material = "CorrodedMetal", WalkSpeed = 13,
			Hold = CFrame.new(0, 2.6, 0) },
	},
	Piles = {
		{ Item = "Stake", Pos = Vector3.new(-22, 0, 8) },
		{ Item = "Post", Pos = Vector3.new(-22, 0, 16) },
		{ Item = "Sheet", Pos = Vector3.new(-22, 0, 24) },
	},
	-- The truck starts loaded with lumber; unloading it at the delivery pad makes a Lumber pile.
	Truck = { Spawn = CFrame.new(-34, 1.6, -18) * CFrame.Angles(0, -math.pi / 2, 0), Cargo = "Lumber" },
	DeliveryZone = { Radius = 12, PileOffset = Vector3.new(-6, 0, 12) },
	-- Heavy equipment parked on site at job start (local CFrames). The shed is small: no crane.
	Equipment = { Excavator = CFrame.new(-10, 1.8, -30) },
	Slots = slots,
}
