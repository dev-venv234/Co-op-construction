--!strict
-- Finishing details on the buildings as the crew builds them (owner, 2026-11-12: "the houses and the sheds look
-- basic"). JobService calls OnDone for every finished slot; this dresses it up:
--  * walls: painted siding (CoopSiding when there is one) in the job's colors, skirt and frieze boards, and on the
--    longer walls a window (glass, muntins, trim, sill, shutters on houses);
--  * the walk-through wall segment (def.Collide == false): a door with frame, knob, porch light and a concrete stoop
--    (the shed gets a barn door with an X brace);
--  * once every roof sheet over a roof section is on: a pitched shingle roof over it (two slopes, gable ends, ridge cap,
--    fascia, gutters, downspouts, and a brick chimney on houses).
-- Everything is welded to the slot part it belongs to and doesn't collide, so the inspector's collapse takes it down
-- with the piece. Colors are picked once per job. Looks only: no gameplay, no money.
local MaterialService = game:GetService("MaterialService")

local Detail = {}

local S: any
local C = Color3.fromRGB
local M = Enum.Material

local HOUSE_PALETTES = {
	{ siding = C(196, 214, 226), trim = C(245, 245, 240), door = C(150, 40, 40), shutter = C(52, 70, 96), roof = C(70, 72, 78) },
	{ siding = C(210, 220, 196), trim = C(245, 245, 240), door = C(40, 70, 110), shutter = C(70, 90, 60), roof = C(80, 64, 52) },
	{ siding = C(236, 226, 200), trim = C(250, 250, 246), door = C(60, 100, 70), shutter = C(110, 70, 45), roof = C(62, 62, 66) },
	{ siding = C(170, 176, 182), trim = C(240, 240, 238), door = C(190, 120, 40), shutter = C(40, 44, 50), roof = C(48, 50, 56) },
	{ siding = C(222, 198, 170), trim = C(248, 246, 240), door = C(90, 50, 40), shutter = C(120, 60, 50), roof = C(90, 60, 50) },
}
local SHED_PALETTES = {
	{ siding = C(150, 52, 44), trim = C(240, 238, 230), door = C(150, 52, 44), shutter = C(150, 52, 44), roof = C(66, 68, 72) },
	{ siding = C(120, 140, 112), trim = C(238, 236, 228), door = C(120, 140, 112), shutter = C(120, 140, 112), roof = C(80, 66, 54) },
	{ siding = C(160, 166, 172), trim = C(240, 240, 236), door = C(160, 166, 172), shutter = C(160, 166, 172), roof = C(60, 60, 64) },
}

type Job = { cur: any, palette: any, center: Vector3, shed: boolean, rng: Random }
local job: Job? = nil

function Detail.Init(services)
	S = services
end

local function jobFor(cur: any): Job
	local j = job
	if j and j.cur == cur then
		return j
	end
	local shed = cur.bp and cur.bp.Id == "Shed"
	local rng = Random.new()
	local list = if shed then SHED_PALETTES else HOUSE_PALETTES
	-- the building's center: the middle of its walls
	local sum, n = Vector3.zero, 0
	for _, s in cur.slots do
		if string.sub(s.def.Id, 1, 4) == "wall" and s.part then
			sum += s.part.Position
			n += 1
		end
	end
	local center = if n > 0 then sum / n else cur.originCF.Position
	local nj: Job = { cur = cur, palette = list[rng:NextInteger(1, #list)], center = center, shed = shed, rng = rng }
	job = nj
	return nj
end

-- A decoration part welded to `to`.
local function deco(to: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	if shape then
		p.Shape = shape
	end
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = to
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = p
	w.Parent = p
	return p
end

local function wedge(to: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = to
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = p
	w.Parent = p
	return p
end

local function variant(p: BasePart, name: string)
	if MaterialService:FindFirstChild(name) then
		p.MaterialVariant = name
	end
end

---------------------------------------------------------------------------------------------------------------
-- Walls, windows, doors
---------------------------------------------------------------------------------------------------------------

-- The wall's frame: X along the wall, Y up, Z out of the building (outward face at +Z * thickness/2).
local function wallFrame(j: Job, wall: BasePart): (CFrame, number, number, number)
	local cf, size = wall.CFrame, wall.Size
	local alongX = size.X >= size.Z
	local len = if alongX then size.X else size.Z
	local thick = if alongX then size.Z else size.X
	local outward = if alongX then cf.LookVector else cf.RightVector
	local toCenter = j.center - wall.Position
	if outward:Dot(Vector3.new(toCenter.X, 0, toCenter.Z)) > 0 then
		outward = -outward
	end
	local frame = CFrame.lookAt(wall.Position, wall.Position - outward) -- LookVector = -outward, so +Z = outward
	return frame, len, size.Y, thick
end

local function window(j: Job, wall: BasePart, f: CFrame, len: number, h: number, t: number)
	local pal = j.palette
	local w = math.min(3.4, len - 1.8)
	if w < 1.6 then
		return
	end
	local wh = if j.shed then 2.2 else 3.2
	local cy = h * 0.08 + 0.4
	local glass = deco(wall, "Window", Vector3.new(w, wh, t + 0.12), f * CFrame.new(0, cy, 0), C(120, 160, 185), M.Glass)
	glass.Transparency = 0.12
	glass.Reflectance = 0.18
	local out = t / 2 + 0.08
	local trim = pal.trim
	-- frame + sill
	deco(wall, "WindowTrim", Vector3.new(w + 0.6, 0.3, 0.16), f * CFrame.new(0, cy + wh / 2 + 0.15, out), trim, M.Wood)
	deco(wall, "WindowTrim", Vector3.new(0.3, wh, 0.16), f * CFrame.new(-w / 2 - 0.15, cy, out), trim, M.Wood)
	deco(wall, "WindowTrim", Vector3.new(0.3, wh, 0.16), f * CFrame.new(w / 2 + 0.15, cy, out), trim, M.Wood)
	deco(wall, "WindowSill", Vector3.new(w + 0.9, 0.22, 0.5), f * CFrame.new(0, cy - wh / 2 - 0.11, t / 2 + 0.22), trim, M.Wood)
	-- muntins
	deco(wall, "Muntin", Vector3.new(0.12, wh, 0.1), f * CFrame.new(0, cy, out - 0.02), trim, M.Wood)
	deco(wall, "Muntin", Vector3.new(w, 0.12, 0.1), f * CFrame.new(0, cy, out - 0.02), trim, M.Wood)
	-- shutters (houses)
	if not j.shed and len >= w + 3 then
		for _, side in { -1, 1 } do
			local sx = side * (w / 2 + 0.75)
			deco(wall, "Shutter", Vector3.new(0.9, wh + 0.2, 0.14), f * CFrame.new(sx, cy, out), pal.shutter, M.Wood)
			for k = 1, 4 do
				deco(wall, "Louver", Vector3.new(0.7, 0.08, 0.06), f * CFrame.new(sx, cy - wh / 2 + k * wh / 5, out + 0.09), pal.shutter:Lerp(C(0, 0, 0), 0.25), M.Wood)
			end
		end
	end
end

local function door(j: Job, wall: BasePart, f: CFrame, len: number, h: number, t: number)
	local pal = j.palette
	local dw = math.min(if j.shed then 4.4 else 3.2, len - 0.8)
	local dh = h - 0.9
	local bottom = -h / 2
	local out = t / 2 + 0.07
	local slab = deco(wall, "Door", Vector3.new(dw, dh, 0.14), f * CFrame.new(0, bottom + dh / 2, out), pal.door, M.Wood)
	if j.shed then
		-- barn door: X brace and a frame of boards
		local diag = math.sqrt(dw * dw + dh * dh)
		local ang = math.atan2(dh, dw)
		for _, s in { 1, -1 } do
			deco(wall, "Brace", Vector3.new(diag - 0.4, 0.35, 0.1), f * CFrame.new(0, bottom + dh / 2, out + 0.1) * CFrame.Angles(0, 0, s * ang), pal.trim, M.Wood)
		end
	else
		-- panels and a brass knob
		for _, py in { 0.25, -0.2 } do
			deco(wall, "DoorPanel", Vector3.new(dw - 1, dh * 0.3, 0.06), slab.CFrame * CFrame.new(0, py * dh, 0.09), pal.door:Lerp(C(0, 0, 0), 0.15), M.Wood)
		end
		deco(wall, "Knob", Vector3.new(0.3, 0.3, 0.3), slab.CFrame * CFrame.new(dw / 2 - 0.4, -0.2, 0.18), C(200, 165, 70), M.Metal, Enum.PartType.Ball)
		local lamp = deco(wall, "PorchLight", Vector3.new(0.5, 0.7, 0.4), f * CFrame.new(dw / 2 + 0.7, bottom + dh - 0.4, t / 2 + 0.25), C(255, 230, 170), M.Neon)
		local light = Instance.new("PointLight")
		light.Range = 10
		light.Brightness = 0.8
		light.Color = C(255, 214, 160)
		light.Parent = lamp
	end
	-- door frame
	deco(wall, "DoorTrim", Vector3.new(dw + 0.7, 0.35, 0.18), f * CFrame.new(0, bottom + dh + 0.17, out), pal.trim, M.Wood)
	for _, side in { -1, 1 } do
		deco(wall, "DoorTrim", Vector3.new(0.35, dh, 0.18), f * CFrame.new(side * (dw / 2 + 0.17), bottom + dh / 2, out), pal.trim, M.Wood)
	end
	-- stoop: from the ground up to the floor, in front of the door
	local floorY = wall.Position.Y + bottom
	local groundY = (j.cur.originCF :: CFrame).Position.Y
	local rise = floorY - groundY
	if rise > 0.3 then
		local depth = 1.8
		deco(wall, "Stoop", Vector3.new(dw + 1.6, rise, depth), f * CFrame.new(0, bottom - rise / 2, t / 2 + depth / 2), C(176, 174, 168), M.Concrete)
	end
end

local function dressWall(j: Job, slot: any)
	local wall = slot.part :: BasePart
	local pal = j.palette
	wall.Color = pal.siding
	wall.Material = M.WoodPlanks
	variant(wall, "CoopSiding")
	local f, len, h, t = wallFrame(j, wall)
	local out = t / 2 + 0.06
	-- skirt and frieze boards along the outside
	deco(wall, "Skirt", Vector3.new(len, 0.5, 0.12), f * CFrame.new(0, -h / 2 + 0.25, out), pal.trim, M.Wood)
	deco(wall, "Frieze", Vector3.new(len, 0.4, 0.12), f * CFrame.new(0, h / 2 - 0.2, out), pal.trim, M.Wood)
	if slot.def.Collide == false then
		door(j, wall, f, len, h, t)
	elseif len >= 5 then
		window(j, wall, f, len, h, t)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Roofs
---------------------------------------------------------------------------------------------------------------

local function buildRoof(j: Job, deck: BasePart)
	if deck:FindFirstChild("Ridge") then
		return
	end
	local pal = j.palette
	local cf, size = deck.CFrame, deck.Size
	-- ridge along the longer side; frame F: X across the span, Z along the ridge, origin on top of the deck
	local ridgeAlongZ = size.Z >= size.X
	local span = if ridgeAlongZ then size.X else size.Z
	local ridgeLen = if ridgeAlongZ then size.Z else size.X
	-- (+0.6: just over the roof sheets lying on the deck, so they don't poke out at the eaves)
	local F = cf * CFrame.new(0, size.Y / 2 + 0.6, 0) * (if ridgeAlongZ then CFrame.new() else CFrame.Angles(0, math.pi / 2, 0))
	local half = span / 2
	local rise = half * (if j.shed then 0.45 else 0.6)
	local ov = 0.8 -- overhang past the walls
	local slope = math.atan2(rise, half)
	local roofLen = ridgeLen + 2 * ov * 0.6
	for _, side in { 1, -1 } do
		-- slab from the eave (beyond the wall, a little lower) up to the ridge
		local eave = Vector3.new(side * (half + ov), -ov * math.tan(slope), 0)
		local ridge = Vector3.new(0, rise, 0)
		local along = (ridge - eave)
		local up = Vector3.new(side * math.sin(slope), math.cos(slope), 0) -- the slope's outward normal
		local mid = (eave + ridge) / 2 + up * 0.22
		deco(deck, "RoofSlope", Vector3.new(along.Magnitude, 0.45, roofLen),
			F * CFrame.new(mid) * CFrame.Angles(0, 0, math.atan2(along.Y, along.X)), pal.roof, M.RoofShingles)
		-- fascia + gutter along the eave, downspouts at the ends
		deco(deck, "Fascia", Vector3.new(0.25, 0.7, roofLen), F * CFrame.new(eave + Vector3.new(side * 0.12, -0.15, 0)), pal.trim, M.Wood)
		deco(deck, "Gutter", Vector3.new(0.45, 0.4, roofLen), F * CFrame.new(eave + Vector3.new(side * 0.45, -0.4, 0)), C(150, 152, 156), M.Metal)
		local deckBottom = (F * CFrame.new(eave)).Position.Y
		local ground = (j.cur.originCF :: CFrame).Position.Y
		local drop = deckBottom - ground
		if drop > 1 and not j.shed then
			-- downspouts down the house corners, with an elbow out to the gutter
			for _, e in { 1, -1 } do
				local z = e * (ridgeLen / 2 - 0.9)
				local gy = eave.Y - 0.5
				local wallX = side * (half - 0.3)
				local gutterX = side * (half + ov + 0.45)
				deco(deck, "Downspout", Vector3.new(math.abs(gutterX - wallX) + 0.3, 0.3, 0.3),
					F * CFrame.new((wallX + gutterX) / 2, gy, z), C(150, 152, 156), M.Metal)
				local fall = drop - 0.5
				deco(deck, "Downspout", Vector3.new(0.3, fall, 0.3), F * CFrame.new(wallX, gy - fall / 2, z), C(150, 152, 156), M.Metal)
			end
		end
	end
	-- gable ends: two half-triangles at each end, siding-colored
	for _, e in { 1, -1 } do
		for _, side in { 1, -1 } do
			local g = wedge(deck, "Gable", Vector3.new(0.35, rise, half),
				F * CFrame.new(side * half / 2, rise / 2, e * (ridgeLen / 2 - 0.2)) * CFrame.Angles(0, -side * math.pi / 2, 0),
				pal.siding, M.WoodPlanks)
			variant(g, "CoopSiding")
		end
		-- a small vent in the gable
		deco(deck, "GableVent", Vector3.new(1.4, 1, 0.15), F * CFrame.new(0, rise * 0.45, e * (ridgeLen / 2 - 0.0)), pal.trim, M.Wood)
	end
	local ridge = deco(deck, "Ridge", Vector3.new(0.9, 0.35, roofLen + 0.2), F * CFrame.new(0, rise + 0.32, 0), pal.roof:Lerp(C(0, 0, 0), 0.25), M.Slate)
	ridge.Name = "Ridge"
	-- brick chimney on houses
	if not j.shed then
		local x, z = half * 0.45, ridgeLen * 0.22
		local h = rise + 2.6
		local chim = deco(deck, "Chimney", Vector3.new(2.2, h, 2.2), F * CFrame.new(x, h / 2 - 0.2, z), C(150, 70, 55), M.Brick)
		variant(chim, "CoopBrick")
		deco(deck, "ChimneyCap", Vector3.new(2.6, 0.3, 2.6), F * CFrame.new(x, h - 0.05, z), C(120, 120, 118), M.Concrete)
	end
end

-- Called when the last sheet over a roof deck goes on (and for decks with no sheets).
local function roofReady(j: Job, cur: any, deckId: string)
	local deck = cur.slots[deckId]
	if not deck or not deck.done then
		return
	end
	for _, s in cur.slots do
		local req = s.def.Requires
		if req and table.find(req, deckId) and string.sub(s.def.Id, 1, 5) == "sheet" and not s.done then
			return -- more sheets to go
		end
	end
	buildRoof(j, deck.part)
end

---------------------------------------------------------------------------------------------------------------

-- JobService: a slot was finished.
function Detail.OnDone(cur: any, slot: any)
	if not cur or not slot or not slot.part then
		return
	end
	local ok, err = pcall(function()
		local j = jobFor(cur)
		local id = slot.def.Id :: string
		if string.sub(id, 1, 4) == "wall" then
			dressWall(j, slot)
		elseif string.sub(id, 1, 4) == "nail" then
			slot.part.Transparency = 1 -- the nails are in the wall now (no metal cube stuck on the outside)
		elseif string.sub(id, 1, 5) == "sheet" then
			local deckId = slot.def.Requires and slot.def.Requires[1]
			if typeof(deckId) == "string" then
				roofReady(j, cur, deckId)
			end
		elseif string.sub(id, 1, 4) == "roof" then
			roofReady(j, cur, id)
		end
	end)
	if not ok then
		warn("[Detail]", err)
	end
end

return Detail
