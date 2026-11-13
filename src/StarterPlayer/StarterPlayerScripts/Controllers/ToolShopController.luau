--!strict
-- Tool shop panel (2026-11-13): opens when the server sends the catalog (the "Browse tools" prompt at the counter on
-- Main St). One row per tool: what it does, which trade, the price, and BUY (or OWNED). Display only: BUY sends a
-- request (Shop remote) that ToolShopService checks (price, cash, ownership, standing at the counter).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local ToolShop = {}

local player = Players.LocalPlayer
local panel: Frame
local list: ScrollingFrame
local cashLabel: TextLabel

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

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ToolShopPanel"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 21
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.92, 0.9)
	panel.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 640)
	limit.Parent = panel

	text(panel, "TOOL SHOP", UDim2.new(0, 14, 0, 8), UDim2.new(0.5, 0, 0, 34), Enum.Font.GothamBlack, Color3.fromRGB(255, 170, 40))
	cashLabel = text(panel, "", UDim2.new(0.45, 0, 0, 12), UDim2.new(0.4, -70, 0, 26), Enum.Font.GothamBold, Color3.fromRGB(120, 230, 130))
	cashLabel.TextXAlignment = Enum.TextXAlignment.Right
	text(panel, "Tools make your trade's mini-game easier. They never do the work for you.", UDim2.new(0, 14, 0, 46),
		UDim2.new(1, -28, 0, 18), Enum.Font.Gotham, Color3.fromRGB(190, 195, 205))

	local close = Instance.new("TextButton")
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
end

local function render(d: any)
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	cashLabel.Text = ("Your cash: $%d"):format(tonumber(d.cash) or 0)
	for i, it in d.items or {} do
		local row = Instance.new("Frame")
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -8, 0, 78)
		row.BackgroundColor3 = Color3.fromRGB(44, 47, 56)
		row.Parent = list
		Instance.new("UICorner").Parent = row
		text(row, tostring(it.Name), UDim2.new(0, 10, 0, 6), UDim2.new(1, -150, 0, 24), Enum.Font.GothamBlack, Color3.new(1, 1, 1))
		text(row, tostring(it.Trade), UDim2.new(0, 10, 0, 30), UDim2.new(1, -150, 0, 16), Enum.Font.GothamBold, Color3.fromRGB(255, 190, 90))
		text(row, tostring(it.Desc), UDim2.new(0, 10, 0, 48), UDim2.new(1, -150, 0, 22), Enum.Font.Gotham, Color3.fromRGB(200, 205, 215))
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -8, 0.5, 0)
		b.Size = UDim2.fromOffset(128, 56)
		b.TextScaled = true
		b.Font = Enum.Font.GothamBlack
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = row
		Instance.new("UICorner").Parent = b
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.Parent = b
		if it.Owned then
			b.Text = "OWNED"
			b.BackgroundColor3 = Color3.fromRGB(70, 74, 86)
			b.AutoButtonColor = false
		else
			b.Text = ("BUY $%d"):format(tonumber(it.Price) or 0)
			b.BackgroundColor3 = if (tonumber(d.cash) or 0) >= (tonumber(it.Price) or 0) then Color3.fromRGB(60, 150, 80) else Color3.fromRGB(110, 80, 60)
			b.Activated:Connect(function()
				Net.Event("Shop"):FireServer("Buy", it.Id)
			end)
		end
	end
	panel.Visible = true
end

function ToolShop.Start()
	build()
	Net.Event("ShopData").OnClientEvent:Connect(function(d)
		if typeof(d) == "table" and d.kind == "Catalog" then
			render(d)
		end
	end)
	-- walking away from the counter closes it
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panel.Visible then
				local shop = workspace:FindFirstChild("ToolShop")
				local counter = shop and shop:FindFirstChild("Counter", true)
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not counter or not counter:IsA("BasePart") or not root or (root.Position - counter.Position).Magnitude > 24 then
					panel.Visible = false
				end
			end
		end
	end)
end

return ToolShop
