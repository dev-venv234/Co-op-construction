--!strict
-- Shared math for the Gauge task (2026-11-13): hold to make the value rise, let go and it falls (0..1). Keep it inside
-- the green band long enough. The server re-plays the player's press / release times with this to judge the task;
-- the client draws its own run of the same math.
local Gauge = {}

Gauge.DT = 0.02 -- simulation step (seconds)

-- Styles (what the task looks like + how it behaves). band = width of the green band, center = where it sits (the
-- server shifts it a little each round), need = seconds inside the band to finish, limit = seconds before it's a miss.
Gauge.STYLES = {
	Pour = { rise = 0.42, fall = 0.1, band = 0.14, center = 0.72, need = 2.2, limit = 16,
		hint = "Hold POUR to fill the form up to the line, then keep it there" },
	Level = { rise = 0.55, fall = 0.4, band = 0.16, center = 0.5, need = 2.0, limit = 16,
		hint = "Hold to push the bubble: keep it between the lines" },
	Charge = { rise = 0.32, fall = 0.16, band = 0.12, center = 0.62, need = 2.4, limit = 18,
		hint = "Hold CHARGE: bring the pressure into the green and hold it there" },
	Voltage = { rise = 0.5, fall = 0.22, band = 0.13, center = 0.78, need = 2.0, limit = 16,
		hint = "Hold to raise the voltage: keep the needle in the green" },
}

export type State = { t: number, v: number, held: boolean, inBand: number, out: number, entered: boolean }

function Gauge.NewState(start: number): State
	return { t = start, v = 0, held = false, inBand = 0, out = 0, entered = false }
end

-- Moves the state forward to time `to` (the held flag stays as it is). lo..hi is the green band.
function Gauge.Advance(s: State, to: number, rise: number, fall: number, lo: number, hi: number)
	while s.t + Gauge.DT <= to do
		s.t += Gauge.DT
		s.v = math.clamp(s.v + (if s.held then rise else -fall) * Gauge.DT, 0, 1)
		if s.v >= lo and s.v <= hi then
			s.inBand += Gauge.DT
			s.entered = true
		elseif s.entered then
			s.out += Gauge.DT -- slipped out after getting in: costs accuracy
		end
	end
end

-- 1.0 never slipping out, down to 0.5.
function Gauge.Accuracy(s: State, need: number): number
	return math.clamp(1 - 0.5 * s.out / need, 0.5, 1)
end

return Gauge
