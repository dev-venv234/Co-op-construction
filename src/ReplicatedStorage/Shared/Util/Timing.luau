--!strict
-- Shared needle math for the Timing task. The client draws it; the server judges taps with the same function.
local Timing = {}

Timing.PERIOD = 1.6 -- seconds for one sweep from 0 to 1

function Timing.NeedleAt(elapsed: number, period: number): number
	if elapsed <= 0 then
		return 0
	end
	local x = (elapsed / period) % 2
	return if x <= 1 then x else 2 - x
end

return Timing
