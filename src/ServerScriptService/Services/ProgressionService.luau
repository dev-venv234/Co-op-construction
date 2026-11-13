--!strict
-- Trade XP and levels (each trade levels separately) and which job sites a player has unlocked.
-- XP lives in the saved profile (DataService). Player attributes (Level_<Trade>, BestLevel, UnlockedTier) are display
-- copies for the HUD and the site board; the server always re-checks. Unlock progress (2026-11-12, owner asked how
-- many Site 1 jobs Site 2 takes): NextSiteTier / NextSiteLevel / NextSiteXP (the next locked site and the XP it needs)
-- and ProgressTrade / ProgressXP (the player's trade closest to it) drive the bar on the site board, and every
-- finished job ends with a "Site N unlocks at..." toast.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Trades = require(ReplicatedStorage.Shared.Config.Trades)
local SitesConfig = require(ServerStorage.Config.Sites)

local Progression = {}

local TASK_XP = 10 -- per task, scaled by accuracy
local JOB_XP = 50 -- for finishing a job you worked on

local S: any

function Progression.Init(services)
	S = services
end

-- Level L needs 60 * (L - 1)^2 XP: L2 = 60, L3 = 240, L8 = 2,940, L15 = 11,760.
function Progression.LevelFor(xp: number): number
	local level = 1
	while xp >= 60 * level * level do
		level += 1
	end
	return level
end

function Progression.BestLevel(p: Player): number
	local prof = S.DataService.Get(p)
	if not prof then
		return 1
	end
	local best = 1
	for _, trade in Trades.Order do
		best = math.max(best, Progression.LevelFor(prof.XP[trade] or 0))
	end
	return best
end

-- Highest site tier this player may start (tier 1 is always open).
function Progression.UnlockedTier(p: Player): number
	if RunService:IsStudio() and workspace:GetAttribute("DevUnlockAll") == true then
		return 99
	end
	local best = Progression.BestLevel(p)
	local tier = 1
	for _, id in SitesConfig.Order do
		local site = SitesConfig[id]
		if best >= (site.MinLevel or 1) then
			tier = math.max(tier, site.Tier)
		end
	end
	return tier
end

local function publish(p: Player)
	local prof = S.DataService.Get(p)
	if not prof then
		return
	end
	for _, trade in Trades.Order do
		p:SetAttribute("Level_" .. trade, Progression.LevelFor(prof.XP[trade] or 0))
	end
	p:SetAttribute("BestLevel", Progression.BestLevel(p))
	local tier = Progression.UnlockedTier(p)
	p:SetAttribute("UnlockedTier", tier)
	-- the next site to unlock (one that can be played here) and the trade closest to it
	local nextTier, nextLevel = nil, nil
	for _, id in SitesConfig.Order do
		local site = SitesConfig[id]
		local playable = site.Release == "Launch" or RunService:IsStudio()
		if site.Tier > tier and playable and (nextTier == nil or site.Tier < nextTier) then
			nextTier, nextLevel = site.Tier, site.MinLevel or 1
		end
	end
	local bestTrade, bestXP = Trades.Order[1], -1
	for _, trade in Trades.Order do
		local xp = prof.XP[trade] or 0
		if xp > bestXP then
			bestTrade, bestXP = trade, xp
		end
	end
	p:SetAttribute("NextSiteTier", nextTier)
	p:SetAttribute("NextSiteLevel", nextLevel)
	p:SetAttribute("NextSiteXP", if nextLevel then 60 * (nextLevel - 1) ^ 2 else nil)
	p:SetAttribute("ProgressTrade", bestTrade)
	p:SetAttribute("ProgressXP", math.floor(math.max(bestXP, 0)))
end

local function add(p: Player, xp: number)
	local trade = S.CrewService.GetRole(p)
	local prof = S.DataService.Get(p)
	if not trade or not prof or xp <= 0 then
		return
	end
	local Toast = Net.Event("Toast")
	local levelBefore = Progression.LevelFor(prof.XP[trade] or 0)
	local tierBefore = Progression.UnlockedTier(p)
	prof.XP[trade] = (prof.XP[trade] or 0) + xp
	publish(p)
	local levelAfter = Progression.LevelFor(prof.XP[trade])
	if levelAfter > levelBefore then
		Toast:FireClient(p, ("%s level %d!"):format(trade, levelAfter))
	end
	local tierAfter = Progression.UnlockedTier(p)
	if tierAfter > tierBefore then
		Toast:FireClient(p, ("New job site unlocked: Site %d"):format(tierAfter))
	end
end

function Progression.AwardTask(p: Player, accuracy: number)
	add(p, math.floor(TASK_XP * math.clamp(accuracy, 0, 1) + 0.5))
end

function Progression.AwardJob(p: Player)
	add(p, JOB_XP)
	local nextTier, level, need = p:GetAttribute("NextSiteTier"), p:GetAttribute("NextSiteLevel"), p:GetAttribute("NextSiteXP")
	if typeof(nextTier) == "number" and typeof(level) == "number" and typeof(need) == "number" then
		Net.Event("Toast"):FireClient(p, ("Site %d unlocks at level %d in any trade: your %s is at %d / %d XP"):format(
			nextTier, level, tostring(p:GetAttribute("ProgressTrade")), p:GetAttribute("ProgressXP") or 0, need))
	end
end

function Progression.Start()
	S.DataService.Loaded.Event:Connect(publish)
	for _, p in game:GetService("Players"):GetPlayers() do
		publish(p)
	end
end

return Progression
