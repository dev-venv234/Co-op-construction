--!strict
-- Lot helpers over Shared.Config.TownLayout (used by JobService at runtime and the edit-time site builder).
local TownLayout = require(script.Parent.Parent.Config.TownLayout) :: any

local Lots = {}

local roadAxis: { [string]: string } = {}
for _, r in TownLayout.Roads do
	roadAxis[r.Name] = r.Axis
end

function Lots.Get(id: string): any
	for _, lot in TownLayout.Lots do
		if lot.Id == id then
			return lot
		end
	end
	return nil
end

function Lots.Center(lot: any): Vector3
	return Vector3.new((lot.Min.X + lot.Max.X) / 2, 0, (lot.Min.Y + lot.Max.Y) / 2)
end

-- Turn for a blueprint on this lot so its front (local -Z) faces the lot's road gate.
-- CFrame.Angles(0, yaw, 0) sends local -Z to (-sin yaw, 0, -cos yaw).
function Lots.Yaw(lot: any): number
	local g = lot.Gate
	if not g then
		return 0
	end
	if roadAxis[g.Road] == "X" then
		-- road runs east-west: a lot south of it (Side +1) faces north (-Z), one north of it faces south
		return if g.Side > 0 then 0 else math.pi
	end
	-- road runs north-south: a lot east of it (Side +1) faces west (-X), one west of it faces east
	return if g.Side > 0 then math.pi / 2 else -math.pi / 2
end

-- "A", "B", "C" for a tier's first, second, third lot.
function Lots.Letter(index: number): string
	return string.char(64 + index)
end

return Lots
