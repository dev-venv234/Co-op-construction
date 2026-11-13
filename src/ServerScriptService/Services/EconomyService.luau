--!strict
-- Cash and the payout formula. Gray box: cash lives in leaderstats only (DataService saving comes in Phase 3).
local Players = game:GetService("Players")

local Economy = {}

local function cashValue(p: Player): IntValue?
	local ls = p:FindFirstChild("leaderstats")
	return if ls then ls:FindFirstChild("Cash") :: IntValue? else nil
end

local function setup(p: Player)
	if p:FindFirstChild("leaderstats") then
		return
	end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = ls
	ls.Parent = p
end

function Economy.Start()
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do
		setup(p)
	end
end

function Economy.AddCash(p: Player, amount: number, reason: string)
	assert(amount >= 0 and amount == math.floor(amount), "bad amount")
	local c = cashValue(p)
	if c then
		c.Value += amount
		print(("[Economy] +$%d to %s (%s)"):format(amount, p.Name, reason))
	end
end

-- Takes `amount` (from server config, never from a client) if the player has it. Returns false otherwise.
function Economy.TrySpend(p: Player, amount: number, reason: string): boolean
	assert(amount >= 0 and amount == math.floor(amount), "bad amount")
	local c = cashValue(p)
	if not c or c.Value < amount then
		return false
	end
	c.Value -= amount
	print(("[Economy] -$%d from %s (%s)"):format(amount, p.Name, reason))
	return true
end

-- Base pay x quality (0.5x-1.5x) x early bonus. avgAccuracy is 0..1 and computed on the server.
function Economy.ComputePayout(cfg: any, avgAccuracy: number, timeLeft: number): (number, { [string]: any })
	local quality = math.clamp(
		cfg.MinQuality + avgAccuracy * (cfg.MaxQuality - cfg.MinQuality),
		cfg.MinQuality,
		cfg.MaxQuality
	)
	local early = timeLeft >= cfg.EarlyThreshold
	local pay = cfg.BasePay * quality * (if early then 1 + cfg.EarlyBonus else 1)
	return math.floor(pay + 0.5), { base = cfg.BasePay, quality = quality, early = early }
end

return Economy
