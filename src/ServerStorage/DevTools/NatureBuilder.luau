--!strict
-- Edit-time only: scatters pine trees (ServerStorage.Nature.Pines, 12 PBR variants with their pivot at the trunk base)
-- into Workspace.Nature. Trees stay off roads and sidewalks, out of every lot (sites, RV park, store, filler buildings),
-- away from existing parts, and sit on the terrain (hills included). Density rises with distance from the nearest road,
-- so the town ends up ringed by forest with scattered trees along the streets. Trees have no collision except a thin
-- invisible trunk post.
-- Run: require(game.ServerStorage.DevTools.NatureBuilder).Build()   (rebuilding replaces Workspace.Nature)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Layout = require(ReplicatedStorage.Shared.Config.TownLayout)

local Builder = {}

local GRID = 34 -- candidate spacing (studs); each candidate is jittered inside its cell
local ROAD_CLEAR = Layout.RoadWidth / 2 + Layout.SidewalkWidth + 10
local LOT_CLEAR = 14
local SEED = 7

local function distToRoad(x: number, z: number): number
	local best = math.huge
	for _, r in Layout.Roads do
		local d
		if r.Axis == "X" then
			local cx = math.clamp(x, math.min(r.From, r.To), math.max(r.From, r.To))
			d = Vector2.new(x - cx, z - r.At).Magnitude
		else
			local cz = math.clamp(z, math.min(r.From, r.To), math.max(r.From, r.To))
			d = Vector2.new(x - r.At, z - cz).Magnitude
		end
		best = math.min(best, d)
	end
	return best
end

local function inLot(x: number, z: number): boolean
	for _, lot in Layout.Lots do
		if x > lot.Min.X - LOT_CLEAR and x < lot.Max.X + LOT_CLEAR and z > lot.Min.Y - LOT_CLEAR and z < lot.Max.Y + LOT_CLEAR then
			return true
		end
	end
	return false
end

function Builder.Build(): number
	local kit = ServerStorage:FindFirstChild("Nature") and ServerStorage.Nature:FindFirstChild("Pines")
	assert(kit and #kit:GetChildren() > 0, "ServerStorage.Nature.Pines is missing")
	local variants = kit:GetChildren()

	local old = workspace:FindFirstChild("Nature")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Nature"
	root.Parent = workspace

	local rng = Random.new(SEED)
	local down = RaycastParams.new()
	down.FilterType = Enum.RaycastFilterType.Include
	down.FilterDescendantsInstances = { workspace.Terrain }
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { root, workspace.Terrain }

	local b = Layout.Bounds
	local count = 0
	-- Trees already placed, by grid cell, so new ones keep their distance (canopies may touch, trunks may not crowd).
	local placed: { [number]: { { pos: Vector3, r: number } } } = {}
	local function key(cx: number, cz: number): number
		return cx * 100000 + cz
	end
	local function crowded(pos: Vector3, r: number): boolean
		local cx, cz = math.floor(pos.X / GRID), math.floor(pos.Z / GRID)
		for ix = cx - 1, cx + 1 do
			for iz = cz - 1, cz + 1 do
				for _, o in placed[key(ix, iz)] or {} do
					if Vector2.new(o.pos.X - pos.X, o.pos.Z - pos.Z).Magnitude < (o.r + r) * 0.6 then
						return true
					end
				end
			end
		end
		return false
	end
	local batch = Instance.new("Folder")
	batch.Name = "Chunk"
	local inBatch = 0
	for gx = b.MinX + GRID / 2, b.MaxX - GRID / 2, GRID do
		for gz = b.MinZ + GRID / 2, b.MaxZ - GRID / 2, GRID do
			local x = gx + rng:NextNumber(-GRID * 0.45, GRID * 0.45)
			local z = gz + rng:NextNumber(-GRID * 0.45, GRID * 0.45)
			local dr = distToRoad(x, z)
			if dr < ROAD_CLEAR or inLot(x, z) then
				continue
			end
			-- Sparse near streets, dense forest further out.
			local p = math.clamp((dr - ROAD_CLEAR) / 200, 0.12, 0.7)
			if rng:NextNumber() > p then
				continue
			end
			local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), down)
			if not hit or hit.Material == Enum.Material.Water then
				continue
			end
			local v = variants[rng:NextInteger(1, #variants)] :: Model
			local scale = rng:NextNumber(1.6, 2.6)
			local radius = ((v:GetAttribute("Radius") :: number?) or 5) * scale
			if crowded(hit.Position, radius) then
				continue
			end
			if #workspace:GetPartBoundsInRadius(hit.Position + Vector3.new(0, 10, 0), radius + 2, overlap) > 0 then
				continue
			end
			local k = key(math.floor(hit.Position.X / GRID), math.floor(hit.Position.Z / GRID))
			placed[k] = placed[k] or {}
			table.insert(placed[k], { pos = hit.Position, r = radius })
			local tree = v:Clone()
			tree:ScaleTo(scale)
			tree:PivotTo(CFrame.new(hit.Position - Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
			local h = ((v:GetAttribute("Height") :: number?) or 26) * scale
			local post = Instance.new("Part")
			post.Name = "TrunkCollider"
			post.Anchored = true
			post.Transparency = 1
			post.CastShadow = false
			post.Size = Vector3.new(1.4 * scale, h * 0.5, 1.4 * scale)
			post.CFrame = CFrame.new(hit.Position + Vector3.new(0, h * 0.25, 0))
			post.Parent = tree
			tree.Parent = batch
			count += 1
			inBatch += 1
			if inBatch >= 60 then
				batch.Parent = root
				batch = Instance.new("Folder")
				batch.Name = "Chunk"
				inBatch = 0
				task.wait()
			end
		end
	end
	batch.Parent = root
	return count
end

-- Pines on the lower mountain slopes outside the town (MountainBuilder terrain): grass/dirt band only (below the
-- rock line), thinning out as the slope climbs. Goes into Workspace.Nature.Slopes (rebuilt each call).
function Builder.BuildSlopes(): number
	local kit = ServerStorage:FindFirstChild("Nature") and ServerStorage.Nature:FindFirstChild("Pines")
	assert(kit and #kit:GetChildren() > 0, "ServerStorage.Nature.Pines is missing")
	local variants = kit:GetChildren()
	local root = workspace:FindFirstChild("Nature") or Instance.new("Folder")
	root.Name = "Nature"
	root.Parent = workspace
	local old = root:FindFirstChild("Slopes")
	if old then
		old:Destroy()
	end
	local slopes = Instance.new("Folder")
	slopes.Name = "Slopes"
	slopes.Parent = root

	local rng = Random.new(SEED + 1)
	local down = RaycastParams.new()
	down.FilterType = Enum.RaycastFilterType.Include
	down.FilterDescendantsInstances = { workspace.Terrain }
	local b = Layout.Bounds
	local step = 44
	local count = 0
	local inBatch = 0
	for x = b.MinX - 900, b.MaxX + 900, step do
		for z = b.MinZ - 900, b.MaxZ + 900, step do
			if x > b.MinX and x < b.MaxX and z > b.MinZ and z < b.MaxZ then
				continue
			end
			local px, pz = x + rng:NextNumber(-step * 0.45, step * 0.45), z + rng:NextNumber(-step * 0.45, step * 0.45)
			local hit = workspace:Raycast(Vector3.new(px, 1200, pz), Vector3.new(0, -1400, 0), down)
			if not hit or hit.Position.Y > 190 or hit.Position.Y < 3 then
				continue
			end
			if hit.Material ~= Enum.Material.Grass and hit.Material ~= Enum.Material.Ground then
				continue
			end
			if rng:NextNumber() > 0.75 - hit.Position.Y / 400 then
				continue
			end
			local v = variants[rng:NextInteger(1, #variants)] :: Model
			local tree = v:Clone()
			tree:ScaleTo(rng:NextNumber(1.8, 2.8))
			tree:PivotTo(CFrame.new(hit.Position - Vector3.new(0, 1, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
			tree.Parent = slopes
			count += 1
			inBatch += 1
			if inBatch >= 80 then
				inBatch = 0
				task.wait()
			end
		end
	end
	return count
end

return Builder
