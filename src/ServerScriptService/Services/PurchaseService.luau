--!strict
-- Monetization (2026-11-16): the ONE MarketplaceService.ProcessReceipt handler for every developer product, and
-- the 2x Pay game pass.
-- Catalog: ServerStorage.Config.Products (authoritative; ids are placeholders until the owner creates them).
--
-- Rules this file keeps:
--  * Grant once. The PurchaseId is written into the player's profile together with what it gave (cash through
--    EconomyService, or a boost credit), and PurchaseGranted is returned only after DataService.Save reports the
--    profile was written under this server's session lock. Any failure returns NotProcessedYet and Roblox sends
--    the receipt again (next purchase or next join); the recorded id makes the second run a save-only retry.
--  * A paid receipt is never left waiting on game state (Roblox does not refund unresolved purchases). A boost that
--    can't be used right now is kept as a credit and used later with the same Buy button, for free.
--  * The client only asks ("Purchase" remote: Open / Buy + a product key). The server checks the key, checks that
--    the boost has something to work on, and only then opens Roblox's purchase prompt itself. No job running means
--    no prompt, so no charge. Prices and ids never come from a client.
--  * Boosts work through the normal game systems (JobService, BotService, InspectionService); nothing here
--    finishes a job.
--  * 2x Pay (game pass, buyer only): ownership is asked from Roblox when the player joins and again when a pass
--    purchase prompt closes (never taken from the prompt's "purchased" flag alone). It is not stored in the profile.
--    The payout asks EconomyService.PayBoost, which this service feeds.
-- Studio only: real purchases can't run in Studio. With the workspace attribute DevMockPurchases = true the Buy
-- button runs a fake receipt through the same handler; ServerStorage.DevPurchase (a BindableFunction, server side
-- only) does the same for tests and can replay a PurchaseId or fake a failed save.
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Products = require(ServerStorage.Config.Products)

local Purchase = {}

local S: any
local Toast: RemoteEvent
local DataEvent: RemoteEvent
local IS_STUDIO = RunService:IsStudio()
local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
local AUTO_USE_SECONDS = 180 -- a boost bought from the Buy button is used right away if the receipt comes this soon
local GAPS: { [string]: number } = { Open = 0.5, Buy = 1 } -- seconds between requests, per action

local Items = Products.Items :: { [string]: any }
local keyByProductId: { [number]: string } = {}
local mockIdByKey: { [string]: number } = {}
local inFlight: { [string]: boolean } = {} -- PurchaseIds being handled right now
local wants: { [Player]: { [string]: number } } = {} -- boost key -> when the player last asked to buy it
local passOwned: { [Player]: boolean } = {} -- 2x Pay, as confirmed by Roblox this session
local PASS = Items.DoublePay

-- A boost: can(p) says whether it has something to work on right now (and why not); apply(p) does it, without
-- yielding, through the owning service. Registered in Start.
type Boost = { can: (Player) -> (boolean, string?), apply: (Player) -> (boolean, string?) }
local boosts: { [string]: Boost } = {}

function Purchase.Init(services)
	S = services
end

local function mockOn(): boolean
	return IS_STUDIO and workspace:GetAttribute("DevMockPurchases") == true
end

local function canUse(p: Player, key: string): (boolean, string?)
	local b = boosts[key]
	if not b then
		return false, Items[key].Name .. " isn't available yet"
	end
	return b.can(p)
end

local function sendCatalog(p: Player)
	local items = {}
	for _, key in Products.Order do
		local it = Items[key]
		local row: { [string]: any } = {
			Key = key, Type = it.Type, Name = it.Name, Desc = it.Desc, Robux = it.Robux, OnSale = it.Id > 0 or mockOn(),
		}
		if it.Type == "Boost" then
			row.Credits = S.DataService.Credits(p, key)
			row.Ready, row.Why = canUse(p, key)
		elseif it.Type == "Cash" then
			row.Cash = it.Cash
		elseif it.Type == "Pass" then
			row.Owned = passOwned[p] == true
		end
		table.insert(items, row)
	end
	DataEvent:FireClient(p, { kind = "Catalog", items = items })
end

-- Uses one saved credit now. False (credit kept) when the boost has nothing to work on.
local function useCredit(p: Player, key: string): boolean
	local it = Items[key]
	local ok, why = canUse(p, key)
	if not ok then
		Toast:FireClient(p, ("%s is saved for later: %s"):format(it.Name, why or "can't be used right now"))
		return false
	end
	if not S.DataService.TakeCredit(p, key) then
		return false
	end
	local applied, why2 = boosts[key].apply(p)
	if not applied then
		S.DataService.AddCredit(p, key, 1) -- nothing happened: the credit goes back
		Toast:FireClient(p, ("%s is saved for later: %s"):format(it.Name, why2 or "can't be used right now"))
		return false
	end
	print(("[Purchase] %s used %s"):format(p.Name, key))
	task.spawn(S.DataService.Save, p, false)
	return true
end

---------------------------------------------------------------------------------------------------------------
-- 2x Pay game pass
---------------------------------------------------------------------------------------------------------------

function Purchase.HasDoublePay(p: Player): boolean
	return passOwned[p] == true
end

local function setPass(p: Player, owned: boolean, how: string)
	if not p.Parent or passOwned[p] == owned then
		return
	end
	passOwned[p] = owned
	p:SetAttribute("DoublePay", owned) -- display copy for the store panel and HUD
	if owned then
		print(("[Purchase] %s has 2x Pay (%s)"):format(p.Name, how))
	end
end

-- Asks Roblox whether the player owns the pass. nil = Roblox didn't answer.
local function ownsPass(p: Player): boolean?
	if PASS.Id <= 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(p.UserId, PASS.Id)
	end)
	if not ok then
		return nil
	end
	return owns == true
end

-- On join: keep asking (slowly) until Roblox answers, so an owner never loses the pass to an API hiccup.
local function checkPassOnJoin(p: Player)
	local wait = 2
	while p.Parent do
		local owns = ownsPass(p)
		if owns ~= nil then
			setPass(p, owns, "owned on join")
			return
		end
		task.wait(wait)
		wait = math.min(wait * 2, 60)
	end
end

-- A pass prompt closed saying "purchased". That flag is never trusted on its own: the pass counts once Roblox's own
-- ownership check says so (its cache is refreshed when this event fires; a few tries cover any delay).
local function onPassPromptFinished(p: Instance, passId: number, purchased: boolean)
	if not purchased or passId ~= PASS.Id or PASS.Id <= 0 or not p:IsA("Player") or passOwned[p] then
		return
	end
	for _, pause in { 0, 1, 2, 4, 8 } do
		task.wait(pause)
		if not p.Parent then
			return
		end
		if ownsPass(p) == true then
			setPass(p, true, "bought in game")
			Toast:FireAllClients(("%s bought 2x PAY: double paychecks from now on!"):format(p.Name))
			return
		end
	end
	warn("[Purchase] a 2x Pay purchase was reported for", p.Name, "but Roblox doesn't show the pass: not granted")
end

---------------------------------------------------------------------------------------------------------------
-- The receipt handler
---------------------------------------------------------------------------------------------------------------

local function persist(p: Player, sim: any?): (boolean, string?)
	if sim and sim.failSave then
		return false, "simulated failure"
	end
	local ok, why = S.DataService.Save(p, false)
	if not ok and why == "memory" and IS_STUDIO then
		return true, nil -- Studio with API access off: nothing can be saved, and no real purchase can happen here
	end
	return ok, why
end

-- Runs with the receipt id locked. No yields between the duplicate check and recording the id.
local function grant(p: Player, key: string, info: any, sim: any?): Enum.ProductPurchaseDecision
	local it = Items[key]
	local purchaseId = info.PurchaseId :: string
	-- A profile that can't be saved (no session lock, DataStores down) never gets a purchase: wait for a good one.
	local persistable = S.DataService.CanPersist(p) or (IS_STUDIO and S.DataService.IsMemoryOnly())
	if not persistable then
		warn("[Purchase] profile of", p.Name, "can't be saved right now; receipt", purchaseId, "stays open")
		return NOT_YET
	end
	local fresh = not S.DataService.HasReceipt(p, purchaseId)
	if fresh then
		if it.Type == "Cash" then
			if not S.EconomyService.AddCash(p, it.Cash, "cash pack " .. key) then
				return NOT_YET
			end
		elseif it.Type == "Boost" then
			S.DataService.AddCredit(p, key, 1)
		else
			warn("[Purchase] receipt for", key, "which is not a developer product")
			return NOT_YET
		end
		S.DataService.AddReceipt(p, purchaseId, tonumber(info.CurrencySpent) or 0)
		print(("[Purchase] %s bought %s (receipt %s)"):format(p.Name, key, purchaseId))
	end
	-- Save before telling Roblox it's done. The id and the grant go out in the same write.
	local saved, why = persist(p, sim)
	if not saved then
		warn(("[Purchase] receipt %s for %s not saved yet (%s): Roblox will send it again"):format(purchaseId, p.Name, tostring(why)))
		return NOT_YET
	end
	if fresh and p.Parent then
		if it.Type == "Cash" then
			Toast:FireClient(p, ("%s: +$%d. Thanks for backing the crew!"):format(it.Name, it.Cash))
		else
			local asked = wants[p] and wants[p][key]
			if asked and os.clock() - asked < AUTO_USE_SECONDS then
				wants[p][key] = nil
				useCredit(p, key)
			else
				Toast:FireClient(p, ("%s is saved: open the STORE and tap USE when you need it"):format(it.Name))
			end
		end
		sendCatalog(p)
	end
	return GRANTED
end

local function processReceipt(info: any, sim: any?): Enum.ProductPurchaseDecision
	if typeof(info) ~= "table" or typeof(info.PurchaseId) ~= "string" or info.PurchaseId == "" then
		return NOT_YET
	end
	local purchaseId = info.PurchaseId :: string
	local key = if typeof(info.ProductId) == "number" then keyByProductId[info.ProductId] else nil
	if not key then
		warn("[Purchase] receipt", purchaseId, "is for a product this game doesn't know:", info.ProductId)
		return NOT_YET
	end
	local p = if typeof(info.PlayerId) == "number" then Players:GetPlayerByUserId(info.PlayerId) else nil
	if not p then
		return NOT_YET -- left mid-purchase: Roblox delivers the receipt again when they next join
	end
	local prof = if sim and sim.noProfile then nil else S.DataService.WhenLoaded(p, 10)
	if not prof or not p.Parent then
		return NOT_YET
	end
	-- the same receipt can arrive twice at once: the second waits, then finds the id recorded
	local waited = os.clock()
	while inFlight[purchaseId] do
		if os.clock() - waited > 30 then
			return NOT_YET
		end
		task.wait(0.1)
	end
	if not p.Parent or S.DataService.Get(p) ~= prof then
		return NOT_YET
	end
	inFlight[purchaseId] = true
	local ok, decision = pcall(grant, p, key, info, sim)
	inFlight[purchaseId] = nil
	if not ok then
		warn("[Purchase] error while handling receipt", purchaseId, decision)
		return NOT_YET
	end
	return decision
end

---------------------------------------------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------------------------------------------

-- Studio only: a fake receipt through the real handler. opts (tests): purchaseId, userId, productId, failSave,
-- noProfile. Returns the decision's name.
local function mockReceipt(p: Player, key: string, opts: any?): string
	local it = Items[key]
	if not IS_STUDIO or not it or it.Type == "Pass" then
		return "NotAProduct"
	end
	local o = opts or {}
	local decision = processReceipt({
		PlayerId = if o.userId ~= nil then o.userId else p.UserId,
		ProductId = if o.productId ~= nil then o.productId else mockIdByKey[key],
		PurchaseId = if o.purchaseId ~= nil then o.purchaseId else "MOCK-" .. HttpService:GenerateGUID(false),
		CurrencySpent = it.Robux,
		CurrencyType = Enum.CurrencyType.Robux,
		PlaceIdWherePurchased = game.PlaceId,
	}, o)
	return decision.Name
end

-- Opens Roblox's purchase prompt for a developer product (the server decides; see onBuy).
local function prompt(p: Player, key: string)
	local it = Items[key]
	if mockOn() then
		print(("[Purchase] MOCK purchase of %s by %s (Studio only)"):format(key, p.Name))
		task.spawn(mockReceipt, p, key, nil)
		return
	end
	if it.Id <= 0 then
		Toast:FireClient(p, it.Name .. " isn't on sale yet")
		return
	end
	if not S.DataService.CanPersist(p) then
		Toast:FireClient(p, "Purchases are off right now: your save didn't load. Rejoin and try again")
		return
	end
	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(p, it.Id)
	end)
	if not ok then
		warn("[Purchase] could not open the purchase prompt:", err)
	end
end

local function onBuy(p: Player, key: string)
	local it = Items[key]
	if not S.DataService.Get(p) then
		Toast:FireClient(p, "Your save is still loading: try again in a moment")
		return
	end
	if it.Type == "Cash" then
		prompt(p, key)
	elseif it.Type == "Boost" then
		-- nothing to use it on: no prompt, so nothing is charged
		local ok, why = canUse(p, key)
		if not ok then
			Toast:FireClient(p, why or (it.Name .. " can't be used right now"))
			return
		end
		if S.DataService.Credits(p, key) > 0 then
			useCredit(p, key) -- already paid for
			sendCatalog(p)
			return
		end
		wants[p] = wants[p] or {}
		wants[p][key] = os.clock()
		if key == "RetryInspection" then
			S.InspectionService.HoldRetry() -- the offer waits (once) while this player is in the purchase prompt
		end
		prompt(p, key)
	elseif it.Type == "Pass" then
		if passOwned[p] then
			Toast:FireClient(p, "You already own " .. it.Name)
		elseif mockOn() then
			print(("[Purchase] MOCK pass purchase by %s (Studio only)"):format(p.Name))
			setPass(p, true, "mock")
			Toast:FireAllClients(("%s bought 2x PAY: double paychecks from now on!"):format(p.Name))
			sendCatalog(p)
		elseif it.Id <= 0 then
			Toast:FireClient(p, it.Name .. " isn't on sale yet")
		else
			local ok, err = pcall(function()
				MarketplaceService:PromptGamePassPurchase(p, it.Id)
			end)
			if not ok then
				warn("[Purchase] could not open the pass prompt:", err)
			end
		end
	end
end

function Purchase.Start()
	Toast = Net.Event("Toast")
	DataEvent = Net.Event("PurchaseData")

	-- product ids -> keys (placeholders are skipped); Studio also gets fake negative ids for mock receipts
	local placeholders = {}
	for i, key in Products.Order do
		local it = Items[key]
		assert(it and typeof(it.Id) == "number" and typeof(it.Robux) == "number", "bad Products entry " .. key)
		if it.Type ~= "Pass" then
			mockIdByKey[key] = -i
			if IS_STUDIO then
				keyByProductId[-i] = key
			end
			if it.Id > 0 then
				assert(keyByProductId[it.Id] == nil, "Products: id used twice: " .. it.Id)
				keyByProductId[it.Id] = key
			end
		end
		if it.Id <= 0 then
			table.insert(placeholders, key)
		end
	end
	if #placeholders > 0 then
		warn("[Purchase] not on sale yet (no id in ServerStorage.Config.Products): " .. table.concat(placeholders, ", "))
	end

	-- Boosts: each one works through the service that owns that part of the game.
	boosts.RushDelivery = {
		can = function(_p: Player)
			return S.JobService.CanRush()
		end,
		apply = function(p: Player)
			return S.JobService.RushDelivery(p)
		end,
	}

	boosts.HirePro = {
		can = function(_p: Player)
			return S.BotService.CanHirePro()
		end,
		apply = function(p: Player)
			return S.BotService.HirePro(p)
		end,
	}

	boosts.RetryInspection = {
		can = function(_p: Player)
			return S.InspectionService.CanRetry()
		end,
		apply = function(p: Player)
			return S.InspectionService.TakeRetry(p)
		end,
	}
	-- A retry prompt that closed without a purchase stops holding the offer open. (Only a hint for the timer: the
	-- purchase itself is only ever granted by the receipt.)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_userId: number, productId: number, purchased: boolean)
		if not purchased and productId == Items.RetryInspection.Id and productId > 0 then
			S.InspectionService.ReleaseRetry()
		end
	end)

	-- The one receipt handler.
	MarketplaceService.ProcessReceipt = function(info)
		local ok, decision = pcall(processReceipt, info, nil)
		if not ok then
			warn("[Purchase] ProcessReceipt error:", decision)
			return NOT_YET
		end
		return decision
	end

	Net.Event("Purchase").OnServerEvent:Connect(function(p: Player, action: unknown, key: unknown)
		if typeof(action) ~= "string" or GAPS[action] == nil then
			return
		end
		if not S.TaskEngine.Guard.Allow(p, "Purchase:" .. action, GAPS[action]) then
			return
		end
		if action == "Open" then
			sendCatalog(p)
		elseif action == "Buy" then
			if typeof(key) ~= "string" or #key > 32 or Items[key] == nil then
				warn("[Purchase] bad Buy request from", p.Name)
				return
			end
			onBuy(p, key)
		end
	end)

	-- 2x Pay: the payout asks EconomyService.PayBoost; ownership comes from Roblox on join and after a purchase.
	S.EconomyService.SetPayBoost(function(p: Player): number
		return if passOwned[p] == true then PASS.Multiplier else 1
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPromptFinished)
	Players.PlayerAdded:Connect(function(p)
		task.spawn(checkPassOnJoin, p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(checkPassOnJoin, p)
	end

	Players.PlayerRemoving:Connect(function(p)
		wants[p] = nil
		passOwned[p] = nil
	end)

	-- Studio-only test hook (server side; clients can't reach ServerStorage), like JobService's DevTrigger.
	if IS_STUDIO then
		local hook = Instance.new("BindableFunction")
		hook.Name = "DevPurchase"
		hook.OnInvoke = function(playerName: string, key: string, opts: any?)
			local pl = Players:FindFirstChild(playerName)
			if not pl or not pl:IsA("Player") then
				return "NoPlayer"
			end
			if key == "DoublePay" then
				setPass(pl, not (opts and opts.remove), "mock") -- the pass has no receipt: just flip ownership
				return "PassSet"
			end
			return mockReceipt(pl, key, opts)
		end
		hook.Parent = ServerStorage
	end
end

return Purchase
