--!strict
-- Connect task: route a wire from IN to OUT by rotating tiles. The server keeps the tile kinds and
-- checks the submitted rotations itself.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConnectGrid = require(ReplicatedStorage.Shared.Util.ConnectGrid)

local Connect = {}
local rng = Random.new()
local SIZE = 4

function Connect.NewPuzzle(): ConnectGrid.Grid
	return ConnectGrid.Generate(SIZE, SIZE, rng)
end

function Connect.Payload(g: ConnectGrid.Grid, label: string): { [string]: any }
	return {
		kind = "Connect",
		label = label,
		w = g.w,
		h = g.h,
		kinds = table.clone(g.kinds),
		rots = table.clone(g.rots),
		startRow = g.startRow,
		goalRow = g.goalRow,
	}
end

-- rots must already be validated (exact length, integers 0..3).
function Connect.Check(g: ConnectGrid.Grid, rots: { number }): boolean
	local solved = ConnectGrid.Trace({
		w = g.w,
		h = g.h,
		kinds = g.kinds,
		rots = rots,
		startRow = g.startRow,
		goalRow = g.goalRow,
	})
	return solved
end

function Connect.Accuracy(seconds: number): number
	if seconds <= 12 then
		return 1
	end
	return math.max(0.6, 1 - (seconds - 12) / 75)
end

return Connect
