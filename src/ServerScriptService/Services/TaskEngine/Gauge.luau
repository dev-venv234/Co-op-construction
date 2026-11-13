--!strict
-- Gauge task (2026-11-13): hold to raise the needle, let go and it falls; keep it in the green band long enough.
-- The client only says "held" / "let go"; the server re-plays those times (its own clock minus a capped latency
-- allowance) with Shared/Util/Gauge, so the result can't be faked. Styles: Pour, Level, Charge, Voltage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedGauge = require(ReplicatedStorage.Shared.Util.Gauge)

local Gauge = {}

export type Round = {
	style: string,
	rise: number,
	fall: number,
	lo: number,
	hi: number,
	need: number,
	start: number,
	limit: number,
	state: SharedGauge.State,
}

local rng = Random.new()
local MAX_LATENCY = 0.2

-- bandScale > 1 widens the green band (tools from the tool shop).
function Gauge.NewRound(style: string, bandScale: number?): Round
	local st = SharedGauge.STYLES[style] or SharedGauge.STYLES.Pour
	local band = st.band * (bandScale or 1)
	local center = math.clamp(st.center + rng:NextNumber(-0.08, 0.08), band / 2 + 0.05, 0.95 - band / 2)
	local start = workspace:GetServerTimeNow() + 0.4
	return {
		style = if SharedGauge.STYLES[style] then style else "Pour",
		rise = st.rise,
		fall = st.fall,
		lo = center - band / 2,
		hi = center + band / 2,
		need = st.need,
		start = start,
		limit = st.limit,
		state = SharedGauge.NewState(start),
	}
end

function Gauge.Payload(r: Round, label: string, missed: boolean): { [string]: any }
	return { kind = "Gauge", label = label, style = r.style, rise = r.rise, fall = r.fall, lo = r.lo, hi = r.hi, need = r.need,
		start = r.start, limit = r.limit, missed = missed }
end

local function now(p: Player?): number
	local latency = 0.05
	if p then
		local ok, ping = pcall(function()
			return p:GetNetworkPing()
		end)
		latency = math.clamp(if ok and typeof(ping) == "number" then ping / 2 else 0.05, 0, MAX_LATENCY)
	end
	return workspace:GetServerTimeNow() - latency
end

-- The player pressed or let go.
function Gauge.SetHeld(r: Round, p: Player, held: boolean)
	local t = now(p)
	if t <= r.state.t then
		r.state.held = held -- before the start (or a second change in the same step)
		return
	end
	SharedGauge.Advance(r.state, t, r.rise, r.fall, r.lo, r.hi)
	r.state.held = held
end

-- Checked often: returns "done" (with accuracy), "miss" (out of time), or nil (still going).
function Gauge.Check(r: Round, p: Player?): (string?, number)
	SharedGauge.Advance(r.state, now(p), r.rise, r.fall, r.lo, r.hi)
	if r.state.inBand >= r.need then
		return "done", SharedGauge.Accuracy(r.state, r.need)
	end
	if r.state.t - r.start > r.limit then
		return "miss", 0
	end
	return nil, 0
end

return Gauge
