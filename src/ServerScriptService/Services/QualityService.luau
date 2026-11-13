--!strict
-- Per-task accuracy (0..1, decided by the server) rolled up into a job grade.
local Quality = {}

type Record = { player: Player, slotId: string, accuracy: number }
local records: { Record } = {}

function Quality.Reset()
	table.clear(records)
end

function Quality.Record(p: Player, slotId: string, accuracy: number)
	table.insert(records, { player = p, slotId = slotId, accuracy = math.clamp(accuracy, 0, 1) })
end

function Quality.Average(): number
	if #records == 0 then
		return 0
	end
	local sum = 0
	for _, r in records do
		sum += r.accuracy
	end
	return sum / #records
end

-- Chaos: rework records (loading, re-stacking, fixes, mishaps) are never flagged by the inspector.
local function isRework(id: string): boolean
	return string.sub(id, 1, 5) == "load_" or string.sub(id, 1, 8) == "restack_" or string.sub(id, 1, 4) == "fix_"
		or string.sub(id, -7) == "_mishap"
end

-- The worst build tasks under `threshold` accuracy, lowest first (at most `limit`).
function Quality.LowestFor(threshold: number, limit: number): { { slotId: string, accuracy: number } }
	local out = {}
	for _, r in records do
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
function Quality.Replace(slotId: string, accuracy: number)
	for _, r in records do
		if r.slotId == slotId then
			r.accuracy = math.clamp(accuracy, 0, 1)
		end
	end
end

-- The record for one task (who did it and how well), or nil.
function Quality.RecordOf(slotId: string): Record?
	for _, r in records do
		if r.slotId == slotId then
			return r
		end
	end
	return nil
end

function Quality.Contributors(): { [Player]: number }
	local out: { [Player]: number } = {}
	for _, r in records do
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
