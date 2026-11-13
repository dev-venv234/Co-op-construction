--!strict
-- Edit-time only: a ring of mountains around the town (outside TownLayout.Bounds) in Terrain.
-- Height rises from 0 at the town edge to big noisy peaks; grassy foothills, rock slopes, snow caps.
-- The town itself is never touched. HeightAt is public so other tools can place things on the slopes.
-- Run (long, ~1-2 min): require(game.ServerStorage.DevTools.MountainBuilder).Build()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(ReplicatedStorage.Shared.Config.TownLayout)

local Builder = {}

local CELL = 16 -- column size (studs)
local RING = 1400 -- how far the mountains reach past the town edge
local RISE = 520 -- distance over which the ground climbs from the town edge to full mountains
local SEED = 4.31

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Ridged multi-octave noise in 0..1
local function ridges(x: number, z: number): number
	local sum, amp, freq, norm = 0, 1, 1 / 900, 0
	for _ = 1, 5 do
		local n = 1 - math.abs(math.noise(x * freq, z * freq, SEED))
		sum += n * n * amp
		norm += amp
		amp *= 0.5
		freq *= 2.1
	end
	return sum / norm
end

-- Distance from (x, z) to the town rectangle (0 inside).
local function outside(x: number, z: number): number
	local b = Layout.Bounds
	local dx = math.max(b.MinX - x, 0, x - b.MaxX)
	local dz = math.max(b.MinZ - z, 0, z - b.MaxZ)
	return math.sqrt(dx * dx + dz * dz)
end

function Builder.HeightAt(x: number, z: number): number
	local d = outside(x, z)
	if d <= 0 then
		return 0
	end
	local base = smooth(d / RISE)
	local peak = 260 + 520 * smooth((math.noise(x / 1600, z / 1600, SEED + 9) + 1) / 2)
	return base * (40 + peak * ridges(x, z)) + base * 30
end

function Builder.Build(onProgress: ((number) -> ())?): number
	local T = workspace.Terrain
	local b = Layout.Bounds
	local x0, x1 = b.MinX - RING, b.MaxX + RING
	local z0, z1 = b.MinZ - RING, b.MaxZ + RING
	local columns = 0
	local rows = math.floor((x1 - x0) / CELL)
	local row = 0
	for x = x0, x1, CELL do
		for z = z0, z1, CELL do
			local cx, cz = x + CELL / 2, z + CELL / 2
			if outside(cx, cz) <= 0 then
				continue
			end
			local h = Builder.HeightAt(cx, cz)
			if h < 2 then
				continue
			end
			-- A 64-stud rock shell under the surface (the inside is never seen; a solid fill would cost ~10x the memory),
			-- then a skin chosen by height.
			local top = h - 2
			local shell = math.min(64, top + 12)
			T:FillBlock(CFrame.new(cx, top - shell / 2, cz), Vector3.new(CELL, shell, CELL), Enum.Material.Rock)
			local skin = if h < 120 then Enum.Material.Grass elseif h < 200 then Enum.Material.Ground
				elseif h < 470 then Enum.Material.Rock else Enum.Material.Snow
			local skinDepth = if skin == Enum.Material.Snow then 14 else 8
			T:FillBlock(CFrame.new(cx, top - skinDepth / 2 + 2, cz), Vector3.new(CELL, skinDepth, CELL), skin)
			columns += 1
		end
		row += 1
		if row % 6 == 0 then
			if onProgress then
				onProgress(row / rows)
			end
			task.wait()
		end
	end
	return columns
end

return Builder
