--!strict
-- House blueprint generator. Turns a few numbers (size, floors) into ghost slots that use the same four
-- task types as the shed, so a new tier is config, not code.
-- Local coords: lot center = (0, 0, 0), front (road/gate side) = -Z. JobService moves and turns it onto a site.
-- Order of work: stakes -> pier holes (excavator) -> piers -> pours -> corner pier plates welded -> level check ->
-- per floor: deck, walls, nailing (3 nails), outlet boxes, circuit, light fixtures, HVAC ducts -> ductwork route ->
-- vents -> roof lift (crane) -> roof brackets welded + roof sheets -> breaker panel -> power on; AC unit -> charge;
-- stair rails welded -> inspection. The lumber truck delivery unlocks the first deck.
-- Mini-games (2026-11-13): pours, the level check, power on and the AC charge are Gauge tasks (hold to keep the needle
-- in the green), welds are Trace tasks (follow the seam), nailing is a 3-hit Timing task.
local C = Color3.fromRGB

local House = {}

export type Options = {
	Id: string,
	DisplayName: string,
	W: number, -- width along x
	D: number, -- depth along z
	Floors: number,
	HouseZ: number?, -- moves the house back from the gate
	PierSpacing: number?,
	WallSegment: number?,
}

local FLOOR_H = 7.4 -- floor-to-floor height
local WALL_H = 7
local GROUND_DECK = 1.3 -- top of the ground floor deck

local DONE = {
	Stake = { Color = C(255, 140, 0), Material = "Wood" },
	Hole = { Color = C(60, 40, 25), Material = "Ground" },
	Pier = { Color = C(150, 110, 70), Material = "Wood" },
	Pour = { Color = C(170, 170, 165), Material = "Concrete" },
	Floor = { Color = C(200, 160, 110), Material = "WoodPlanks" },
	Wall = { Color = C(215, 180, 130), Material = "WoodPlanks" },
	Nail = { Color = C(90, 90, 95), Material = "Metal" },
	Roof = { Color = C(190, 150, 100), Material = "WoodPlanks" },
	Sheet = { Color = C(120, 120, 130), Material = "CorrodedMetal" },
	Panel = { Color = C(255, 230, 120), Material = "Neon" },
	Level = { Color = C(255, 220, 0), Material = "Metal" },
	Inspect = { Color = C(60, 120, 220), Material = "Metal" },
	Pad = { Color = C(150, 150, 150), Material = "Concrete", Transparency = 0.6 },
	Box = { Color = C(110, 115, 125), Material = "Metal" },
	Fixture = { Color = C(255, 236, 190), Material = "Neon" },
	Panel = { Color = C(150, 155, 160), Material = "DiamondPlate" },
	Power = { Color = C(80, 230, 120), Material = "Neon" },
	Plate = { Color = C(120, 124, 130), Material = "DiamondPlate" },
	Weld = { Color = C(110, 113, 120), Material = "Metal" },
	Rail = { Color = C(55, 57, 62), Material = "Metal" },
	Duct = { Color = C(196, 200, 205), Material = "Metal" },
	Vent = { Color = C(80, 82, 86), Material = "DiamondPlate" },
	ACUnit = { Color = C(220, 222, 224), Material = "Metal" },
	Charge = { Color = C(80, 170, 230), Material = "Neon" },
}

House.Items = {
	Stake = { Size = Vector3.new(0.4, 3, 0.4), Color = C(255, 140, 0), Material = "Wood", WalkSpeed = 16,
		Hold = CFrame.new(0.8, 0, -1.4) },
	Post = { Size = Vector3.new(1, 7, 1), Color = C(150, 110, 70), Material = "Wood", WalkSpeed = 13,
		Hold = CFrame.new(0, 0.5, -1.6) },
	Lumber = { Size = Vector3.new(1, 1, 8), Color = C(200, 160, 110), Material = "WoodPlanks", WalkSpeed = 12,
		Hold = CFrame.new(0, 1.8, 0) * CFrame.Angles(0, math.pi / 2, 0) },
	Sheet = { Size = Vector3.new(4, 0.3, 6), Color = C(120, 120, 130), Material = "CorrodedMetal", WalkSpeed = 13,
		Hold = CFrame.new(0, 2.6, 0) },
	Box = { Size = Vector3.new(0.8, 1, 0.6), Color = C(110, 115, 125), Material = "Metal", WalkSpeed = 16,
		Hold = CFrame.new(0.8, 0, -1.2) },
	Fixture = { Size = Vector3.new(1.4, 0.4, 1.4), Color = C(255, 236, 190), Material = "Glass", WalkSpeed = 16,
		Hold = CFrame.new(0, 0.4, -1.4) },
	Panel = { Size = Vector3.new(1.8, 2.6, 0.5), Color = C(150, 155, 160), Material = "DiamondPlate", WalkSpeed = 14,
		Hold = CFrame.new(0, 0.3, -1.6) },
	Duct = { Size = Vector3.new(1.2, 1, 6), Color = C(196, 200, 205), Material = "Metal", WalkSpeed = 13,
		Hold = CFrame.new(0, 2.4, 0) },
	Vent = { Size = Vector3.new(1.6, 0.2, 1), Color = C(80, 82, 86), Material = "DiamondPlate", WalkSpeed = 16,
		Hold = CFrame.new(0.8, 0, -1.2) },
	ACUnit = { Size = Vector3.new(3, 3, 3), Color = C(220, 222, 224), Material = "Metal", WalkSpeed = 9,
		Hold = CFrame.new(0, 0.5, -2.6) },
}

function House.Make(o: Options)
	local slots = {}
	local function add(s: { [string]: any }): string
		s.Requires = s.Requires or {}
		table.insert(slots, s)
		return s.Id
	end

	local hw, hd = o.W / 2, o.D / 2
	local cz = o.HouseZ or 0
	local front, back = cz - hd, cz + hd
	local spacing = o.PierSpacing or 10
	local segLen = o.WallSegment or 12

	-- 1) Corner stakes (Foreman)
	local stakeIds = {}
	for _, c in { { "FL", -hw, front }, { "FR", hw, front }, { "BL", -hw, back }, { "BR", hw, back } } do
		table.insert(stakeIds, add({ Id = "stake_" .. c[1], Kind = "Place", Item = "Stake", Role = "Foreman", Phase = "Site prep",
			Label = "Drive stake", Pos = Vector3.new(c[2], 1.5, c[3]), Size = Vector3.new(0.4, 3, 0.4), Done = DONE.Stake, Collide = false }))
	end

	-- 2) Piers around the perimeter: hole (Operator) -> pier (Laborer) -> pour (Laborer)
	local pts = {}
	local nx = math.max(1, math.floor(o.W / spacing + 0.5))
	local nz = math.max(1, math.floor(o.D / spacing + 0.5))
	for i = 0, nx do
		local x = -hw + i * o.W / nx
		table.insert(pts, { x = x, z = front, stake = if i == 0 then "stake_FL" elseif i == nx then "stake_FR" else nil })
		table.insert(pts, { x = x, z = back, stake = if i == 0 then "stake_BL" elseif i == nx then "stake_BR" else nil })
	end
	for j = 1, nz - 1 do
		local z = front + j * o.D / nz
		table.insert(pts, { x = -hw, z = z })
		table.insert(pts, { x = hw, z = z })
	end
	local pourIds = {}
	local plateIds = {}
	for k, pt in pts do
		local hole = add({ Id = "hole_" .. k, Kind = "Timing", Role = "Operator", Phase = "Site prep", Label = "Dig pier hole",
			Equipment = "Excavator", Reach = 18,
			Requires = if pt.stake then { pt.stake } else stakeIds,
			Pos = Vector3.new(pt.x, 0.15, pt.z), Size = Vector3.new(2, 0.3, 2), Done = DONE.Hole, Collide = false })
		local pier = add({ Id = "pier_" .. k, Kind = "Place", Item = "Post", Role = "Laborer", Phase = "Foundation",
			Label = "Set pier", Requires = { hole },
			Pos = Vector3.new(pt.x, 0.5, pt.z), Size = Vector3.new(1.2, 1, 1.2), Done = DONE.Pier })
		local pour = add({ Id = "pour_" .. k, Kind = "Gauge", Style = "Pour", Role = "Laborer", Phase = "Foundation",
			Label = "Pour concrete", Requires = { pier },
			Pos = Vector3.new(pt.x, 0.25, pt.z), Size = Vector3.new(2.4, 0.5, 2.4), Done = DONE.Pour })
		table.insert(pourIds, pour)
		-- the corner piers get a steel plate welded on (Welder)
		if pt.stake then
			table.insert(plateIds, add({ Id = "plate_" .. k, Kind = "Trace", Role = "Welder", Phase = "Foundation",
				Label = "Weld pier plate", Requires = { pour },
				Pos = Vector3.new(pt.x, 1.05, pt.z), Size = Vector3.new(1.6, 0.12, 1.6), Done = DONE.Plate, Collide = false }))
		end
	end

	-- 3) Lumber delivery (Operator drives the truck onto this pad) and the level check (Foreman)
	local deliver = add({ Id = "deliver", Kind = "Deliver", Role = "Operator", Phase = "Site prep", Label = "Unload lumber",
		Pos = Vector3.new(hw + 20, 0.1, front - 16), Size = Vector3.new(18, 0.2, 18), Reach = 20, Done = DONE.Pad, Collide = false })
	local levelNeeds = table.clone(pourIds)
	for _, id in plateIds do
		table.insert(levelNeeds, id)
	end
	local level = add({ Id = "level", Kind = "Gauge", Style = "Level", Role = "Foreman", Phase = "Foundation", Label = "Level check",
		Requires = levelNeeds, Pos = Vector3.new(-hw - 4, 1.5, front - 4), Size = Vector3.new(1, 3, 1), Done = DONE.Level, Collide = false })

	-- 4) Each floor: deck strips -> wall segments -> nailing (Laborer/Foreman take turns) ->
	--    electrical (Electrician): outlet boxes -> run circuit (Connect) -> ceiling fixtures
	local prev = { level, deliver }
	local electrical = {}
	local hvac = {}
	for f = 1, o.Floors do
		local deck = GROUND_DECK + (f - 1) * FLOOR_H
		local phase = if o.Floors > 1 then "Framing (floor " .. f .. ")" else "Framing"
		local strips = math.max(1, math.ceil(o.D / 6))
		local depth = o.D / strips
		local floorIds = {}
		for k = 1, strips do
			table.insert(floorIds, add({ Id = ("floor%d_%d"):format(f, k), Kind = "Place", Item = "Lumber", Role = "Laborer", Phase = phase,
				Label = "Lay floor", Requires = prev,
				Pos = Vector3.new(0, deck - 0.2, front + (k - 0.5) * depth), Size = Vector3.new(o.W + 0.6, 0.4, depth), Done = DONE.Floor }))
		end

		local nails = {}
		local wallY = deck + WALL_H / 2
		local function side(name: string, alongX: boolean, fixed: number, len: number, outward: number, door: boolean)
			local n = math.max(1, math.ceil(len / segLen))
			local seg = len / n
			for i = 1, n do
				local a = -len / 2 + (i - 0.5) * seg
				local pos = if alongX then Vector3.new(a, wallY, fixed) else Vector3.new(fixed, wallY, cz + a)
				local size = if alongX then Vector3.new(seg, WALL_H, 0.5) else Vector3.new(0.5, WALL_H, seg)
				local id = ("%d%s%d"):format(f, name, i)
				local wall = add({ Id = "wall" .. id, Kind = "Place", Item = "Lumber", Role = "Laborer", Phase = phase,
					Label = "Raise wall", Requires = floorIds, Pos = pos, Size = size, Done = DONE.Wall,
					Collide = not (door and i == math.ceil(n / 2)) }) -- the front door segment stays walk-through
				local nailPos = if alongX
					then Vector3.new(a, deck + 1.7, fixed + outward * 0.8)
					else Vector3.new(fixed + outward * 0.8, deck + 1.7, cz + a)
				local role = if (i + #nails) % 2 == 0 then "Foreman" else "Laborer"
				table.insert(nails, add({ Id = "nail" .. id, Kind = "Timing", Hits = 3, Role = role, Phase = phase,
					Label = if role == "Foreman" then "Brace & nail wall" else "Nail wall", Requires = { wall },
					Pos = nailPos, Size = Vector3.new(0.8, 0.8, 0.8), Done = DONE.Nail, Collide = false }))
			end
		end
		side("F", true, front, o.W + 0.6, -1, f == 1)
		side("B", true, back, o.W + 0.6, 1, false)
		side("L", false, -hw, o.D - 0.5, -1, false)
		side("R", false, hw, o.D - 0.5, 1, false)

		local boxes = {}
		for i, z in { cz - o.D / 4, cz + o.D / 4 } do
			for _, side in { -1, 1 } do
				table.insert(boxes, add({ Id = ("box%d_%d%s"):format(f, i, if side < 0 then "L" else "R"), Kind = "Place", Item = "Box",
					Role = "Electrician", Phase = "Electrical", Label = "Set outlet box", Requires = nails,
					Pos = Vector3.new(side * (hw - 0.6), deck + 1.5, z), Size = Vector3.new(0.4, 1, 0.8), Done = DONE.Box }))
			end
		end
		local wire = add({ Id = "wire" .. f, Kind = "Connect", Role = "Electrician", Phase = "Electrical", Label = "Run circuit, floor " .. f,
			Requires = boxes, Pos = Vector3.new(hw + 6, 1.5, back - 4 - (f - 1) * 5), Size = Vector3.new(2, 3, 2), Done = DONE.Power })
		table.insert(electrical, wire)
		for _, x in { -o.W / 4, o.W / 4 } do
			table.insert(electrical, add({ Id = ("fixture%d_%s"):format(f, if x < 0 then "L" else "R"), Kind = "Place", Item = "Fixture",
				Role = "Electrician", Phase = "Electrical", Label = "Hang light fixture", Requires = { wire },
				Pos = Vector3.new(x, deck + WALL_H - 0.5, cz), Size = Vector3.new(1.4, 0.4, 1.4), Done = DONE.Fixture }))
		end
		-- HVAC: two trunk ducts along the ceiling -> route the ductwork (Connect) -> two floor vents
		local trunk = o.D - 4
		local ducts = {}
		for k, dz in { -trunk / 4, trunk / 4 } do
			table.insert(ducts, add({ Id = ("duct%d_%d"):format(f, k), Kind = "Place", Item = "Duct", Role = "HVAC", Phase = "HVAC",
				Label = "Hang duct", Requires = nails,
				Pos = Vector3.new(0, deck + WALL_H - 0.8, cz + dz), Size = Vector3.new(1.4, 1, trunk / 2), Done = DONE.Duct }))
		end
		local route = add({ Id = "route" .. f, Kind = "Connect", Role = "HVAC", Phase = "HVAC", Label = "Route ductwork, floor " .. f,
			Requires = ducts, Pos = Vector3.new(-hw - 6, 1.5, back - 4 - (f - 1) * 5), Size = Vector3.new(2, 3, 2), Done = DONE.Duct })
		for _, side in { -1, 1 } do
			table.insert(hvac, add({ Id = ("vent%d_%s"):format(f, if side < 0 then "L" else "R"), Kind = "Place", Item = "Vent",
				Role = "HVAC", Phase = "HVAC", Label = "Set floor vent", Requires = { route },
				Pos = Vector3.new(side * o.W / 4, deck + 0.08, front + 3), Size = Vector3.new(1.6, 0.16, 1), Done = DONE.Vent, Collide = false }))
		end
		prev = nails
	end

	-- 5) Roof: crane lift (Operator) per section, then sheets (Laborer)
	local roofY = GROUND_DECK + (o.Floors - 1) * FLOOR_H + WALL_H
	local sections = if o.W > 30 then 2 else 1
	local roofW = o.W + 1.4
	local secW = roofW / sections
	local roofD = o.D + 2.4
	local roofIds = {}
	for s = 1, sections do
		local x = -roofW / 2 + (s - 0.5) * secW
		local roof = add({ Id = "roof" .. s, Kind = "Timing", Role = "Operator", Phase = "Roof", Label = "Crane-lift roof",
			Equipment = "Crane", Reach = 70, Requires = prev, Pos = Vector3.new(x, roofY + 0.25, cz), Size = Vector3.new(secW, 0.5, roofD), Done = DONE.Roof })
		local n = math.max(1, math.ceil(roofD / 6))
		for k = 1, n do
			add({ Id = ("sheet%d_%d"):format(s, k), Kind = "Place", Item = "Sheet", Role = "Laborer", Phase = "Roof",
				Label = "Lay roof sheet", Requires = { roof },
				Pos = Vector3.new(x, roofY + 0.65, cz - roofD / 2 + (k - 0.5) * roofD / n), Size = Vector3.new(secW, 0.3, roofD / n),
				Done = DONE.Sheet })
		end
		table.insert(roofIds, roof)
		-- the roof section's steel brackets get welded down at both ends (Welder)
		for k, ez in { -roofD / 2 + 1, roofD / 2 - 1 } do
			add({ Id = ("bracket%d_%d"):format(s, k), Kind = "Trace", Role = "Welder", Phase = "Roof", Label = "Weld roof bracket",
				Requires = { roof }, Pos = Vector3.new(x + (if x < 0 then -secW / 2 + 1 else secW / 2 - 1), roofY - 0.35, cz + ez),
				Size = Vector3.new(0.6, 0.7, 1.2), Done = DONE.Weld, Collide = false })
		end
	end

	-- 6) Breaker panel once the house is closed in, then power on (Electrician)
	local panel = add({ Id = "panel", Kind = "Place", Item = "Panel", Role = "Electrician", Phase = "Electrical",
		Label = "Mount breaker panel", Requires = roofIds,
		Pos = Vector3.new(hw - 0.7, GROUND_DECK + 2.6, back - 3), Size = Vector3.new(0.5, 2.6, 1.8), Done = DONE.Panel })
	table.insert(electrical, panel)
	add({ Id = "power", Kind = "Gauge", Style = "Voltage", Role = "Electrician", Phase = "Electrical", Label = "Power on",
		Requires = electrical, Pos = Vector3.new(hw - 1.1, GROUND_DECK + 2.2, back - 5.2), Size = Vector3.new(0.6, 0.8, 0.6),
		Done = DONE.Power, Collide = false })

	-- 7) HVAC outside: the AC unit on its pad once the house is closed in and the vents are in, then charge it
	local acNeeds = table.clone(roofIds)
	for _, id in hvac do
		table.insert(acNeeds, id)
	end
	local ac = add({ Id = "acunit", Kind = "Place", Item = "ACUnit", Role = "HVAC", Phase = "HVAC", Label = "Place AC unit",
		Requires = acNeeds, Pos = Vector3.new(hw + 4, 1.5, cz), Size = Vector3.new(3, 3, 3), Done = DONE.ACUnit })
	add({ Id = "charge", Kind = "Gauge", Style = "Charge", Role = "HVAC", Phase = "HVAC", Label = "Charge refrigerant",
		Requires = { ac }, Pos = Vector3.new(hw + 4, 2, cz - 2.1), Size = Vector3.new(0.8, 0.8, 0.8), Done = DONE.Charge,
		Collide = false, NotStructural = true })

	-- 8) Stair rails welded on beside the front step (Welder)
	for _, side in { -1, 1 } do
		add({ Id = "rail_" .. (if side < 0 then "L" else "R"), Kind = "Trace", Role = "Welder", Phase = "Finish", Label = "Weld stair rail",
			Requires = prev, Pos = Vector3.new(side * 2.7, 1.6, front - 1.1), Size = Vector3.new(0.2, 3.2, 1.8), Done = DONE.Rail,
			Collide = false })
	end

	-- 9) Inspection needs everything else
	local all = {}
	for _, s in slots do
		table.insert(all, s.Id)
	end
	add({ Id = "inspect", Kind = "Inspect", Role = "Foreman", Phase = "Inspection", Label = "Call inspection", Requires = all,
		Pos = Vector3.new(0, 2, front - 12), Size = Vector3.new(1, 4, 1), Done = DONE.Inspect })

	return {
		Id = o.Id,
		DisplayName = o.DisplayName,
		Items = House.Items,
		Piles = {
			{ Item = "Stake", Pos = Vector3.new(-hw - 14, 0, front - 18) },
			{ Item = "Post", Pos = Vector3.new(-hw - 14, 0, front - 10) },
			{ Item = "Sheet", Pos = Vector3.new(-hw - 14, 0, front - 2) },
			{ Item = "Box", Pos = Vector3.new(hw + 14, 0, back - 2) },
			{ Item = "Fixture", Pos = Vector3.new(hw + 14, 0, back - 10) },
			{ Item = "Panel", Pos = Vector3.new(hw + 14, 0, back - 18) },
			{ Item = "Duct", Pos = Vector3.new(-8, 0, back + 10) },
			{ Item = "Vent", Pos = Vector3.new(0, 0, back + 10) },
			{ Item = "ACUnit", Pos = Vector3.new(8, 0, back + 10) },
		},
		-- Used only when there is no RV park truck stall to spawn the truck at.
		Truck = { Spawn = CFrame.new(hw + 20, 1.6, front - 40), Cargo = "Lumber" },
		DeliveryZone = { Radius = 12, PileOffset = Vector3.new(-14, 0, 0) },
		-- Heavy equipment parked on site at job start (local CFrames): excavator for the piers, crane for the roof.
		Equipment = {
			Excavator = CFrame.new(-hw - 4, 1.8, front - 40),
			Crane = CFrame.new(-hw - 18, 0, cz + 4),
		},
		Slots = slots,
	}
end

return House
