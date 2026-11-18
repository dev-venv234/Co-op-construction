--!strict
-- Per-task accuracy (0..1, decided by the server) rolled up into a job grade. Each job keeps its own records
-- (JobService: cur.quality = Quality.New()), so crews working at the same time never mix grades.
local Quality = {}

export type Record = { player: Player, slotId: string, accuracy: number }
export type Records = { Record }

function Quality.New(): Records
	return {}
end

function Quality.Record(q: Records, p: Instance, slotId: string, accuracy: number)
	table.insert(q, { player = p :: any, slotId = slotId, accuracy = math.clamp(accuracy, 0, 1) })
end

function Quality.Average(q: Records): number
	if #q == 0 then
		return 0
	end
	local sum = 0
	for _, r in q do
		sum += r.accuracy
	end
	return sum / #q
end

-- Chaos: rework records (loading, re-stacking, fixes, retry rebuilds, mishaps) are never flagged by the inspector.
local function isRework(id: string): boolean
	return string.sub(id, 1, 5) == "load_" or string.sub(id, 1, 8) == "restack_" or string.sub(id, 1, 4) == "fix_"
		or string.sub(id, 1, 4) == "redo" or string.sub(id, -7) == "_mishap"
end

-- The worst build tasks under `threshold` accuracy, lowest first (at most `limit`).
function Quality.LowestFor(q: Records, threshold: number, limit: number): { { slotId: string, accuracy: number } }
	local out = {}
	for _, r in q do
		if r.accuracy < threshold and not isRework(r.slotId) then
			table.insert(out, { slotId = r.slotId, accuracy = r.accuracy })
		end
	end
	table.sort(out, function(a, b)
		return a.accuracy < b.accuracy
	end)
	while #out > limit do
		table.remove(out)
	end
	return out
end

-- A flagged task was redone: its record takes the new accuracy.
function Quality.Replace(q: Records, slotId: string, accuracy: number)
	for _, r in q do
		if r.slotId == slotId then
			r.accuracy = math.clamp(accuracy, 0, 1)
		end
	end
end

-- The record for one task (who did it and how well), or nil.
function Quality.RecordOf(q: Records, slotId: string): Record?
	for _, r in q do
		if r.slotId == slotId then
			return r
		end
	end
	return nil
end

-- The slot ids of every task this worker has on record (the payout uses them to see which trade they worked).
function Quality.TasksOf(q: Records, p: Instance): { string }
	local out = {}
	for _, r in q do
		if (r.player :: any) == p then
			table.insert(out, r.slotId)
		end
	end
	return out
end

function Quality.Contributors(q: Records): { [Player]: number }
	local out: { [Player]: number } = {}
	for _, r in q do
		out[r.player] = (out[r.player] or 0) + 1
	end
	return out
end

function Quality.Grade(avg: number): string
	if avg >= 0.95 then
		return "A+"
	elseif avg >= 0.9 then
		return "A"
	elseif avg >= 0.8 then
		return "B"
	elseif avg >= 0.7 then
		return "C"
	end
	return "D"
end

return Quality
