--!strict
-- Per-player, per-action cooldowns so a client can't spam remotes.
local Players = game:GetService("Players")

local Guard = {}
local last: { [Player]: { [string]: number } } = {}

function Guard.Allow(p: Player, key: string, minInterval: number): boolean
	local now = os.clock()
	local t = last[p]
	if not t then
		t = {}
		last[p] = t
	end
	if t[key] and now - t[key] < minInterval then
		return false
	end
	t[key] = now
	return true
end

Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)

return Guard
