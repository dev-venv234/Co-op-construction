--!strict
-- Connect task: a grid of wire tiles. Tap a tile to rotate it; connect IN (left edge) to OUT (right edge).
-- Directions: 0 = N, 1 = E, 2 = S, 3 = W. Rows grow downward.
local ConnectGrid = {}

export type Grid = {
	w: number,
	h: number,
	kinds: { string },
	rots: { number },
	startRow: number,
	goalRow: number,
}

local DX = { [0] = 0, 1, 0, -1 }
local DY = { [0] = -1, 0, 1, 0 }
local BASE: { [string]: { number } } = { I = { 0, 2 }, L = { 0, 1 } }

function ConnectGrid.Openings(kind: string, rot: number): { number }
	local base = BASE[kind] or BASE.I
	return { (base[1] + rot) % 4, (base[2] + rot) % 4 }
end

-- Follows the path from IN. Returns whether it reaches OUT, and the set of tile indexes reached.
function ConnectGrid.Trace(g: Grid): (boolean, { [number]: boolean })
	local path: { [number]: boolean } = {}
	local x, y, entry = 1, g.startRow, 3
	for _ = 1, g.w * g.h + 1 do
		if x < 1 or x > g.w or y < 1 or y > g.h then
			return false, path
		end
		local i = (y - 1) * g.w + x
		if path[i] then
			return false, path
		end
		local o = ConnectGrid.Openings(g.kinds[i], g.rots[i] or 0)
		local exit
		if o[1] == entry then
			exit = o[2]
		elseif o[2] == entry then
			exit = o[1]
		else
			return false, path
		end
		path[i] = true
		if x == g.w and y == g.goalRow and exit == 1 then
			return true, path
		end
		x += DX[exit]
		y += DY[exit]
		entry = (exit + 2) % 4
	end
	return false, path
end

local function dirFromDelta(dx: number, dy: number): number
	if dx == 1 then
		return 1
	elseif dx == -1 then
		return 3
	elseif dy == -1 then
		return 0
	end
	return 2
end

-- Used by the server: builds a solvable puzzle, then scrambles it so it starts unsolved.
function ConnectGrid.Generate(w: number, h: number, rng: Random): Grid
	local startRow = rng:NextInteger(1, h)
	local visited: { [number]: boolean } = {}
	local path: { { number } } = {}

	local function dfs(x: number, y: number): boolean
		visited[(y - 1) * w + x] = true
		table.insert(path, { x, y })
		if x == w then
			return true
		end
		local dirs = { 0, 1, 2, 3 }
		for i = 4, 2, -1 do
			local j = rng:NextInteger(1, i)
			dirs[i], dirs[j] = dirs[j], dirs[i]
		end
		for _, d in dirs do
			local nx, ny = x + DX[d], y + DY[d]
			if nx >= 1 and nx <= w and ny >= 1 and ny <= h and not visited[(ny - 1) * w + nx] then
				if dfs(nx, ny) then
					return true
				end
			end
		end
		table.remove(path)
		return false
	end
	dfs(1, startRow)

	local kinds: { string } = {}
	local rots: { number } = {}
	for i = 1, w * h do
		kinds[i] = if rng:NextInteger(1, 2) == 1 then "I" else "L"
		rots[i] = rng:NextInteger(0, 3)
	end

	local entry = 3
	for k, c in path do
		local x, y = c[1], c[2]
		local i = (y - 1) * w + x
		local exit = 1
		if k < #path then
			local n = path[k + 1]
			exit = dirFromDelta(n[1] - x, n[2] - y)
		end
		if (entry + 2) % 4 == exit then
			kinds[i] = "I"
			rots[i] = entry % 2
		else
			kinds[i] = "L"
			for r = 0, 3 do
				local o = ConnectGrid.Openings("L", r)
				if (o[1] == entry and o[2] == exit) or (o[1] == exit and o[2] == entry) then
					rots[i] = r
					break
				end
			end
		end
		entry = (exit + 2) % 4
	end

	local g: Grid = { w = w, h = h, kinds = kinds, rots = rots, startRow = startRow, goalRow = path[#path][2] }
	repeat
		for i = 1, w * h do
			rots[i] = rng:NextInteger(0, 3)
		end
	until not (ConnectGrid.Trace(g))
	return g
end

return ConnectGrid
