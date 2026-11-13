--!strict
-- Trace task (welding, 2026-11-13): trace the seam from START to END with one finger (or the mouse). The server
-- picks the seam and judges the recording the client sends back: it must start at the start, reach the end, move
-- forward without skipping, at a speed a hand can go, and taking about as long as it really took. Accuracy = how
-- close it stayed to the seam; wandering far off it too often breaks the weld (a miss: try a new seam).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TracePath = require(ReplicatedStorage.Shared.Util.TracePath)

local Trace = {}

export type Round = { points: { Vector2 }, tol: number, len: number, sentAt: number }

local rng = Random.new()
local TOL = 0.055 -- seam half-width that still counts as on it (fraction of the panel)
local MAX_SPEED = 2.2 -- panel widths per second between two samples
local MIN_SECONDS = 0.9

function Trace.NewRound(tolScale: number?): Round
	local pts = TracePath.Generate(rng)
	return { points = pts, tol = TOL * (tolScale or 1), len = TracePath.Length(pts), sentAt = os.clock() }
end

function Trace.Payload(r: Round, label: string, missed: boolean, why: string?): { [string]: any }
	local flat = {}
	for _, p in r.points do
		table.insert(flat, p.X)
		table.insert(flat, p.Y)
	end
	return { kind = "Trace", label = label, points = flat, tol = r.tol, missed = missed, why = why }
end

-- samples: flat { x, y, t, x, y, t, ... } (t = seconds since the first sample). Returns (ok, accuracy, why).
-- ok = nil: the recording is bad (ignored); false: a missed weld; true: done.
function Trace.Judge(r: Round, samples: { number }): (boolean?, number, string?)
	local n = #samples // 3
	if n < 6 then
		return nil, 0, "Trace the whole seam"
	end
	local last = samples[n * 3]
	if last < MIN_SECONDS or last < r.len / MAX_SPEED then
		return nil, 0, "Too fast: trace it slowly"
	end
	if os.clock() - r.sentAt < last - 0.5 then
		return nil, 0, nil -- claims more time than has passed since the seam was sent
	end
	local maxS, off, sum = 0, 0, 0
	local prev: Vector3? = nil
	for i = 0, n - 1 do
		local x, y, t = samples[i * 3 + 1], samples[i * 3 + 2], samples[i * 3 + 3]
		if prev then
			local dt = t - prev.Z
			if dt < 0 then
				return nil, 0, nil
			end
			local step = (Vector2.new(x, y) - Vector2.new(prev.X, prev.Y)).Magnitude
			if dt > 0 and step / dt > MAX_SPEED * 2 then
				return false, 0, "The torch jumped: keep it on the seam"
			end
		end
		prev = Vector3.new(x, y, t)
		local d, s = TracePath.Project(r.points, Vector2.new(x, y))
		if i == 0 and (s > r.len * 0.12 or d > r.tol * 2.5) then
			return false, 0, "Start at the green START mark"
		end
		if s > maxS + r.len * 0.25 then
			return false, 0, "You skipped part of the seam"
		end
		maxS = math.max(maxS, s)
		sum += math.min(d, r.tol * 3)
		if d > r.tol * 2 then
			off += 1
		end
	end
	if maxS < r.len * 0.92 then
		return false, 0, "Weld all the way to the END mark"
	end
	if off > n * 0.2 then
		return false, 0, "The weld wandered off the seam"
	end
	local mean = sum / n
	return true, math.clamp(1 - 0.5 * mean / r.tol, 0.45, 1), nil
end

return Trace
