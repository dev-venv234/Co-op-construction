--!strict
-- Robux store (2026-11-16): STORE button (left edge, under the top bar) -> panel with the crew boosts, the 2x Pay pass and cash packs,
-- plus a big RETRY INSPECTION button while a retry is on offer. Display only: every button just sends
-- Purchase("Buy", key). The server (PurchaseService) checks it, uses a saved credit or opens Roblox's purchase
-- prompt itself, and grants from the receipt. No prices, ids or amounts are ever sent from here.
-- Touch first: every button is at least 44 px tall; the panel scrolls.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local UI = require(script.Parent.UIController)

local Store = {}

local player = Players.LocalPlayer
local panel: Frame
local list: ScrollingFrame
local retryBtn: TextButton
local catalog: { [string]: any }? = nil
local lastAsk = 0

local GREEN = Color3.fromRGB(60, 150, 80)
local BLUE = Color3.fromRGB(60, 110, 190)
local GRAY = Color3.fromRGB(70, 74, 86)
local GOLD = Color3.fromRGB(255, 200, 60)

local function text(parent: Instance, t: string, pos: UDim2, size: UDim2, font: Enum.Font, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = pos
	l.Size = size
	l.Font = font
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color
	l.Text = t
	l.Parent = parent
	return l
end

local function pad(b: Instance, y: number, x: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, y)
	p.PaddingBottom = UDim.new(0, y)
	p.PaddingLeft = UDim.new(0, x)
	p.PaddingRight = UDim.new(0, x)
	p.Parent = b
end

-- Asks the server for the catalog (it also rate-limits; this just avoids pointless requests).
local function ask()
	if os.clock() - lastAsk > 0.6 then
		lastAsk = os.clock()
		Net.Event("Purchase"):FireServer("Open")
	end
end

local function buy(key: string)
	Net.Event("Purchase"):FireServer("Buy", key)
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function render()
	local d = catalog
	if not d then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, it in d.items or {} do
		local row = Instance.new("Frame")
		row.Name = tostring(it.Key)
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -8, 0, 84)
		row.BackgroundColor3 = Color3.fromRGB(44, 47, 56)
		row.Parent = list
		Instance.new("UICorner").Parent = row
		local title = tostring(it.Name)
		if it.Type == "Cash" then
			title ..= ("  +$%s"):format(commas(tonumber(it.Cash) or 0))
		end
		text(row, title, UDim2.new(0, 10, 0, 6), UDim2.new(1, -158, 0, 24), Enum.Font.GothamBlack, Color3.new(1, 1, 1))
		local desc = text(row, tostring(it.Desc), UDim2.new(0, 10, 0, 32), UDim2.new(1, -158, 0, 30), Enum.Font.Gotham, Color3.fromRGB(200, 205, 215))
		desc.TextWrapped = true
		-- boosts say why they can't be used right now (the server refuses those before any purchase)
		local note = ""
		if it.Type == "Boost" and not it.Ready then
			note = tostring(it.Why or "")
		elseif it.Type == "Boost" and (tonumber(it.Credits) or 0) > 0 then
			note = "Already paid for: tap USE"
		end
		text(row, note, UDim2.new(0, 10, 0, 64), UDim2.new(1, -158, 0, 15), Enum.Font.GothamBold, Color3.fromRGB(255, 190, 90))

		local b = Instance.new("TextButton")
		b.Name = "Buy"
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -8, 0.5, 0)
		b.Size = UDim2.fromOffset(136, 60)
		b.TextScaled = true
		b.Font = Enum.Font.GothamBlack
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = row
		Instance.new("UICorner").Parent = b
		pad(b, 10, 6)
		local credits = tonumber(it.Credits) or 0
		if it.Type == "Pass" and it.Owned then
			b.Text = "OWNED"
			b.BackgroundColor3 = GRAY
			b.AutoButtonColor = false
		else
			if it.Type == "Boost" and credits > 0 then
				b.Text = ("USE (%d)"):format(credits)
				b.BackgroundColor3 = if it.Ready then BLUE else GRAY
			elseif not it.OnSale then
				b.Text = "SOON"
				b.BackgroundColor3 = GRAY
			else
				b.Text = ("%d R$"):format(tonumber(it.Robux) or 0)
				b.BackgroundColor3 = if it.Type == "Boost" and not it.Ready then GRAY else GREEN
			end
			b.Activated:Connect(function()
				buy(it.Key)
			end)
		end
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Store"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 22
	gui.Parent = player:WaitForChild("PlayerGui")

	local open = Instance.new("TextButton")
	open.Name = "StoreButton"
	-- left edge, second row (level with SETTINGS on the right): the first row's left end is Roblox's own menu buttons
	open.Position = UDim2.new(0, 8, 0, 54)
	open.Size = UDim2.fromOffset(96, 44)
	open.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
	open.Font = Enum.Font.GothamBlack
	open.TextScaled = true
	open.TextColor3 = GOLD
	open.Text = "STORE"
	open.Parent = gui
	Instance.new("UICorner").Parent = open
	pad(open, 10, 6)

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.94, 0.92)
	panel.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(660, 660)
	limit.Parent = panel

	text(panel, "STORE", UDim2.new(0, 14, 0, 8), UDim2.new(0.5, 0, 0, 34), Enum.Font.GothamBlack, GOLD)
	text(panel, "Boosts help the whole crew. Nothing here builds the job for you.", UDim2.new(0, 14, 0, 46),
		UDim2.new(1, -84, 0, 18), Enum.Font.Gotham, Color3.fromRGB(190, 195, 205))

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 6)
	close.Size = UDim2.fromOffset(52, 46)
	close.Text = "X"
	close.TextScaled = true
	close.Font = Enum.Font.GothamBlack
	close.TextColor3 = Color3.new(1, 1, 1)
	close.BackgroundColor3 = Color3.fromRGB(160, 60, 55)
	close.Parent = panel
	Instance.new("UICorner").Parent = close
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.new(0, 12, 0, 72)
	list.Size = UDim2.new(1, -24, 1, -84)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			ask()
			render()
		end
	end)

	-- Retry Inspection: a big button in the middle while the server's offer to my crew is open (RetryOfferUntil)
	retryBtn = Instance.new("TextButton")
	retryBtn.Name = "RetryButton"
	retryBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	retryBtn.Position = UDim2.fromScale(0.5, 0.62)
	retryBtn.Size = UDim2.new(0.6, 0, 0, 64)
	retryBtn.BackgroundColor3 = Color3.fromRGB(200, 120, 30)
	retryBtn.Font = Enum.Font.GothamBlack
	retryBtn.TextScaled = true
	retryBtn.TextColor3 = Color3.new(1, 1, 1)
	retryBtn.Visible = false
	retryBtn.Parent = gui
	Instance.new("UICorner").Parent = retryBtn
	pad(retryBtn, 10, 10)
	local rl = Instance.new("UISizeConstraint")
	rl.MaxSize = Vector2.new(440, 64)
	rl.MinSize = Vector2.new(260, 64)
	rl.Parent = retryBtn
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.Parent = retryBtn
	retryBtn.Activated:Connect(function()
		buy("RetryInspection")
	end)
end

-- "RETRY INSPECTION 35 R$ (0:21)" or "USE RETRY (0:21)" when one is already paid for.
local function retryText(left: number): string
	local price, credits = nil, 0
	if catalog then
		for _, it in catalog.items or {} do
			if it.Key == "RetryInspection" then
				price, credits = tonumber(it.Robux), tonumber(it.Credits) or 0
			end
		end
	end
	local what = if credits > 0 then "USE YOUR RETRY" elseif price then ("RETRY INSPECTION  %d R$"):format(price) else "RETRY INSPECTION"
	local s = math.max(0, math.ceil(left))
	return ("%s  (%d:%02d)"):format(what, s // 60, s % 60)
end

function Store.Start()
	build()
	Net.Event("PurchaseData").OnClientEvent:Connect(function(d)
		if typeof(d) == "table" and d.kind == "Catalog" then
			catalog = d
			if panel.Visible then
				render()
			end
		end
	end)
	-- what's usable changes with the job, saved credits and the pass: refresh while the panel is open
	local function changed()
		if panel.Visible or retryBtn.Visible then
			ask()
		end
	end
	UI.StateChanged.Event:Connect(changed)
	player:GetAttributeChangedSignal("Credits"):Connect(changed)
	player:GetAttributeChangedSignal("DoublePay"):Connect(changed)
	player:GetAttributeChangedSignal("RetryOfferUntil"):Connect(function()
		if typeof(player:GetAttribute("RetryOfferUntil")) == "number" then
			lastAsk = 0
			ask() -- for the price / saved credit on the button
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local untilT = player:GetAttribute("RetryOfferUntil")
		local left = if typeof(untilT) == "number" then untilT - workspace:GetServerTimeNow() else 0
		retryBtn.Visible = left > 0
		if left > 0 then
			retryBtn.Text = retryText(left)
		end
	end)
end

return Store
