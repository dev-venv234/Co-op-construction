--!strict
-- Tool shop (owner request 2026-11-13): Workspace.ToolShop on Main St (built by DevTools/ToolShopBuilder). Tap
-- "Browse tools" at its counter: the catalog (ServerStorage.Config.Tools) comes to the client (ToolShopController);
-- BUY sends a request that is checked here: a real tool, not owned yet, the player at the counter, and the cash
-- (EconomyService.TrySpend) before DataService.GrantTool and a save. Owned tools feed TaskEngine.SetBonus (and the
-- machine controls) with their multipliers.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Tools = require(ServerStorage.Config.Tools)

local Shop = {}

local S: any
local counter: BasePart? = nil
local REACH = 20

function Shop.Init(services)
	S = services
end

-- Multiplier from every owned tool with this effect (1 = none).
function Shop.Bonus(p: Player, what: string): number
	local prof = S.DataService.Get(p)
	if not prof or type(prof.Tools) ~= "table" then
		return 1
	end
	local m = 1
	for id, owned in prof.Tools do
		local t = (Tools :: any)[id]
		if owned == true and t and t.Effect and typeof(t.Effect[what]) == "number" then
			m *= t.Effect[what]
		end
	end
	return m
end

local function atCounter(p: Player): boolean
	local c = p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	return counter ~= nil and root ~= nil and (root.Position - (counter :: BasePart).Position).Magnitude <= REACH
end

local function cashOf(p: Player): number
	local ls = p:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Cash")
	return if cash and cash:IsA("IntValue") then cash.Value else 0
end

local function sendCatalog(p: Player)
	local items = {}
	for _, id in Tools.Order do
		local t = (Tools :: any)[id]
		table.insert(items, { Id = id, Name = t.Name, Trade = t.Trade, Price = t.Price, Desc = t.Desc, Owned = S.DataService.HasTool(p, id) })
	end
	Net.Event("ShopData"):FireClient(p, { kind = "Catalog", cash = cashOf(p), items = items })
end

local function buy(p: Player, id: unknown)
	local Toast = Net.Event("Toast")
	if typeof(id) ~= "string" then
		return
	end
	local t = (Tools :: any)[id]
	if not t or not table.find(Tools.Order, id) then
		warn("[ToolShop] unknown tool from", p.Name)
		return
	end
	if not atCounter(p) then
		Toast:FireClient(p, "Walk up to the tool shop counter to buy")
		return
	end
	if S.DataService.HasTool(p, id) then
		Toast:FireClient(p, "You already have the " .. t.Name)
		return
	end
	if not S.EconomyService.TrySpend(p, t.Price, "tool: " .. t.Name) then
		Toast:FireClient(p, ("The %s is $%d: earn it on the job sites"):format(t.Name, t.Price))
		return
	end
	S.DataService.GrantTool(p, id)
	task.spawn(S.DataService.Save, p, false)
	Toast:FireClient(p, ("You bought the %s! %s"):format(t.Name, t.Desc))
	Net.Cue("Cash", (counter :: BasePart).Position)
	sendCatalog(p)
end

function Shop.Start()
	S.TaskEngine.SetBonus(Shop.Bonus)
	local budget: { [Player]: number } = {}
	Net.Event("Shop").OnServerEvent:Connect(function(p: Player, action: unknown, id: unknown)
		local now = os.clock()
		if now - (budget[p] or 0) < 0.4 then
			return
		end
		budget[p] = now
		if action == "Buy" then
			buy(p, id)
		elseif action == "Open" and atCounter(p) then
			sendCatalog(p)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		budget[p] = nil
	end)

	local shop = workspace:WaitForChild("ToolShop", 15)
	local c = shop and shop:FindFirstChild("Counter", true)
	if not c or not c:IsA("BasePart") then
		warn("[ToolShop] no Workspace.ToolShop counter: run DevTools/ToolShopBuilder")
		return
	end
	counter = c
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "ShopPrompt"
	pp.ActionText = "Browse tools"
	pp.ObjectText = "Tool Shop"
	pp.HoldDuration = 0.2
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp:SetAttribute("ToolShop", true)
	pp.Parent = c
	S.JobService.RegisterPrompt(pp, function(p: Player)
		if atCounter(p) then
			sendCatalog(p)
		end
	end)
end

return Shop
