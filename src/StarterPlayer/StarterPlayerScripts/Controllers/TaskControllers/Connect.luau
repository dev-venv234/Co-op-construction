--!strict
-- Connect minigame UI: tap a tile to rotate it. When the wire runs IN -> OUT, the client sends the
-- rotations; the server re-checks them against its own copy of the puzzle.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local ConnectGrid = require(ReplicatedStorage.Shared.Util.ConnectGrid)

local Connect = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local modal: Frame
local gridFrame: Frame
local title: TextLabel
local grid: ConnectGrid.Grid? = nil
local tiles: { TextButton } = {}
local submitted = false

local GOLD = Color3.fromRGB(255, 200, 60)
local GREY = Color3.fromRGB(110, 115, 125)

-- Arm frames for each direction: N, E, S, W
local ARMS = {
	[0] = { anchor = Vector2.new(0.5, 0), pos = UDim2.fromScale(0.5, 0), size = UDim2.fromScale(0.24, 0.5) },
	[1] = { anchor = Vector2.new(1, 0.5), pos = UDim2.fromScale(1, 0.5), size = UDim2.fromScale(0.5, 0.24) },
	[2] = { anchor = Vector2.new(0.5, 1), pos = UDim2.fromScale(0.5, 1), size = UDim2.fromScale(0.24, 0.5) },
	[3] = { anchor = Vector2.new(0, 0.5), pos = UDim2.fromScale(0, 0.5), size = UDim2.fromScale(0.5, 0.24) },
}

local function close()
	grid = nil
	modal.Visible = false
	for _, t in tiles do
		t:Destroy()
	end
	table.clear(tiles)
	for _, c in gridFrame:GetChildren() do
		if c.Name == "Marker" then
			c:Destroy()
		end
	end
end

local function redraw()
	local g = grid
	if not g then
		return
	end
	local solved, path = ConnectGrid.Trace(g)
	for i, t in tiles do
		for _, c in t:GetChildren() do
			if c.Name == "Arm" then
				c:Destroy()
			end
		end
		local color = if path[i] then GOLD else GREY
		for _, d in ConnectGrid.Openings(g.kinds[i], g.rots[i]) do
			local a = ARMS[d]
			local arm = Instance.new("Frame")
			arm.Name = "Arm"
			arm.AnchorPoint = a.anchor
			arm.Position = a.pos
			arm.Size = a.size
			arm.BorderSizePixel = 0
			arm.BackgroundColor3 = color
			arm.Parent = t
		end
		local knob = t:FindFirstChild("Knob") :: Frame
		knob.BackgroundColor3 = color
	end
	if solved and not submitted then
		submitted = true
		title.Text = "Connected!"
		Net.Event("ConnectSubmit"):FireServer(table.clone(g.rots))
		task.delay(1, function()
			submitted = false
		end)
	end
end

local function marker(text: string, row: number, h: number, left: boolean)
	local m = Instance.new("TextLabel")
	m.Name = "Marker"
	m.AnchorPoint = Vector2.new(if left then 1 else 0, 0.5)
	m.Position = UDim2.new(if left then 0 else 1, if left then -2 else 2, (row - 0.5) / h, 0)
	m.Size = UDim2.fromOffset(34, 22)
	m.BackgroundColor3 = Color3.fromRGB(70, 200, 100)
	m.TextColor3 = Color3.new(1, 1, 1)
	m.Font = Enum.Font.GothamBold
	m.TextScaled = true
	m.Text = text
	m.Parent = gridFrame
end

local function open(d: { [string]: any })
	close()
	local g: ConnectGrid.Grid = {
		w = d.w,
		h = d.h,
		kinds = d.kinds,
		rots = table.clone(d.rots),
		startRow = d.startRow,
		goalRow = d.goalRow,
	}
	grid = g
	submitted = false
	title.Text = tostring(d.label) .. ": tap tiles to connect IN to OUT"
	local layout = gridFrame:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout
	layout.CellSize = UDim2.new(1 / g.w, -4, 1 / g.h, -4)
	for i = 1, g.w * g.h do
		local t = Instance.new("TextButton")
		t.Name = "Tile"
		t.LayoutOrder = i
		t.Text = ""
		t.AutoButtonColor = true
		t.BackgroundColor3 = Color3.fromRGB(45, 48, 56)
		local knob = Instance.new("Frame")
		knob.Name = "Knob"
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Position = UDim2.fromScale(0.5, 0.5)
		knob.Size = UDim2.fromScale(0.24, 0.24)
		knob.BorderSizePixel = 0
		knob.Parent = t
		t.Activated:Connect(function()
			local cur = grid
			if cur then
				cur.rots[i] = (cur.rots[i] + 1) % 4
				redraw()
			end
		end)
		t.Parent = gridFrame
		tiles[i] = t
	end
	marker("IN", g.startRow, g.h, true)
	marker("OUT", g.goalRow, g.h, false)
	modal.Visible = true
	redraw()
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "ConnectTask"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	modal = Instance.new("Frame")
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromScale(0.6, 0.85)
	modal.BackgroundColor3 = Color3.fromRGB(25, 27, 32)
	modal.Visible = false
	modal.Parent = gui
	Instance.new("UICorner").Parent = modal
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.9
	aspect.Parent = modal
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(420, 470)
	size.Parent = modal

	title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 10, 0, 6)
	title.Size = UDim2.new(1, -70, 0.1, 0)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = modal

	local cancel = Instance.new("TextButton")
	cancel.AnchorPoint = Vector2.new(1, 0)
	cancel.Position = UDim2.new(1, -6, 0, 4)
	cancel.Size = UDim2.fromOffset(48, 44)
	cancel.Text = "X"
	cancel.TextScaled = true
	cancel.Font = Enum.Font.GothamBold
	cancel.TextColor3 = Color3.new(1, 1, 1)
	cancel.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
	cancel.Parent = modal
	Instance.new("UICorner").Parent = cancel
	cancel.Activated:Connect(function()
		Net.Event("CancelTask"):FireServer()
	end)

	gridFrame = Instance.new("Frame")
	gridFrame.AnchorPoint = Vector2.new(0.5, 1)
	gridFrame.Position = UDim2.new(0.5, 0, 1, -14)
	gridFrame.Size = UDim2.new(1, -90, 0.82, 0)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = modal
	local sq = Instance.new("UIAspectRatioConstraint")
	sq.AspectRatio = 1
	sq.Parent = gridFrame
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(4, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gridFrame
end

function Connect.Start()
	build()
	Net.Event("TaskBegin").OnClientEvent:Connect(function(d)
		if typeof(d) == "table" and d.kind == "Connect" then
			open(d)
		end
	end)
	Net.Event("TaskEnd").OnClientEvent:Connect(function()
		if grid then
			close()
		end
	end)
end

return Connect
