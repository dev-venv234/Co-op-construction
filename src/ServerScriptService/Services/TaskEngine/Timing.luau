--!strict
-- Timing task: a needle sweeps a bar; tap when it's in the green zone.
-- The server picks the zone and start time, and judges each tap with its own clock (minus a capped
-- latency allowance), so the client can't claim a perfect hit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTiming = require(ReplicatedStorage.Shared.Util.Timing)

local Timing = {}

export type Round = { start: number, period: number, zMin: number, zMax: number, center: number, width: number }

local rng = Random.new()
local WIDTH = 0.2
local TOLERANCE = 0.035
local MAX_LATENCY = 0.2

-- widthScale > 1 widens the green zone (the Awake buff uses this).
function Timing.NewRound(widthScale: number?): Round
	local width = WIDTH * (widthScale or 1)
	local center = rng:NextNumber(0.2, 0.8)
	return {
		start = workspace:GetServerTimeNow() + 0.35,
		period = SharedTiming.PERIOD,
		zMin = center - width / 2,
		zMax = center + width / 2,
		center = center,
		width = width,
	}
end

function Timing.Payload(r: Round, label: string, missed: boolean): { [string]: any }
	return { kind = "Timing", label = label, start = r.start, period = r.period, zMin = r.zMin, zMax = r.zMax, missed = missed }
end

-- Judges a tap `elapsed` seconds after the needle started. Shared by players (Judge) and bots.
-- Returns nil if the tap came before the needle started (ignored), else hit + accuracy (0.6..1).
function Timing.JudgeAt(r: Round, elapsed: number): (boolean?, number)
	if elapsed < 0 then
		return nil, 0
	end
	local needle = SharedTiming.NeedleAt(elapsed, r.period)
	if needle < r.zMin - TOLERANCE or needle > r.zMax + TOLERANCE then
		return false, 0
	end
	local off = math.abs(needle - r.center) / (r.width / 2 + TOLERANCE)
	return true, 1 - 0.4 * math.min(off, 1)
end

-- A player's tap, judged on the server clock minus a capped latency allowance.
function Timing.Judge(r: Round, p: Player): (boolean?, number)
	local ok, ping = pcall(function()
		return p:GetNetworkPing()
	end)
	local latency = math.clamp(if ok and typeof(ping) == "number" then ping / 2 else 0.05, 0, MAX_LATENCY)
	return Timing.JudgeAt(r, workspace:GetServerTimeNow() - latency - r.start)
end

return Timing
