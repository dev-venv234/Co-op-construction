--!strict
-- Shared geometry for the Trace task (welding, 2026-11-13): a seam is a polyline in a 0..1 square. The client draws it
-- and records the finger; the server judges the recording against the same seam.
local TracePath = {}

-- A new seam: a few shapes (zig-zag, step, curve), always left to right with some up and down.
function TracePath.Generate(rng: Random): { Vector2 }
	local kind = rng:NextInteger(1, 3)
	local pts: { Vector2 } = {}
	local x0, x1 = 0.1, 0.9
	if kind == 1 then -- zig-zag
		local n = rng:NextInteger(3, 5)
		for i = 0, n do
			local y = if i % 2 == 0 then rng:NextNumber(0.25, 0.4) else rng:NextNumber(0.6, 0.75)
			table.insert(pts, Vector2.new(x0 + (x1 - x0) * i / n, y))
		end
	elseif kind == 2 then -- steps (a corner seam)
		local y = rng:NextNumber(0.25, 0.45)
		table.insert(pts, Vector2.new(x0, y))
		local x = x0
		for _ = 1, 2 do
			x += rng:NextNumber(0.2, 0.3)
			table.insert(pts, Vector2.new(x, y))
			y = math.clamp(y + rng:NextNumber(0.18, 0.3) * (if rng:NextNumber() < 0.5 then 1 else -1), 0.15, 0.85)
			table.insert(pts, Vector2.new(x, y))
		end
		table.insert(pts, Vector2.new(x1, y))
	else -- curve
		local amp = rng:NextNumber(0.15, 0.28)
		local phase = rng:NextNumber(0, math.pi)
		local waves = rng:NextNumber(0.8, 1.5)
		for i = 0, 16 do
			local u = i / 16
			table.insert(pts, Vector2.new(x0 + (x1 - x0) * u, 0.5 + amp * math.sin(phase + u * waves * 2 * math.pi)))
		end
	end
	return pts
end

function TracePath.Length(pts: { Vector2 }): number
	local len = 0
	for i = 2, #pts do
		len += (pts[i] - pts[i - 1]).Magnitude
	end
	return len
end

-- Distance from p to the seam, and how far along the seam (studs of seam from the start) the closest point is.
function TracePath.Project(pts: { Vector2 }, p: Vector2): (number, number)
	local best, bestS = math.huge, 0
	local acc = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local ab = b - a
		local l2 = ab:Dot(ab)
		local u = if l2 > 0 then math.clamp((p - a):Dot(ab) / l2, 0, 1) else 0
		local q = a + ab * u
		local d = (p - q).Magnitude
		local segLen = math.sqrt(l2)
		if d < best then
			best, bestS = d, acc + segLen * u
		end
		acc += segLen
	end
	return best, bestS
end

return TracePath
