--!strict
-- Trace minigame UI (welding, 2026-11-13): the seam is drawn on a steel plate; put a finger (or the mouse) on the
-- green START, drag along the seam to the END and let go. A glowing weld bead follows the finger. One finger, any
-- device. The client only records where the finger went; the server judges it (TaskEngine/Trace).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Trace = {}

local player = Players.LocalPlayer
local panel: Frame
local plate: TextButton
local title: TextLabel
local hint: TextLabel
local seamDots: { Frame } = {}
local beadDots: { Frame } = {}
local startMark: Frame
local endMark: Frame
local current: { [string]: any }? = nil
local tracking: InputObject? = nil
local lastPos: Vector2? = nil
local samples: { number } = {}
local t0 = 0
local lastSample = 0
local beadCount = 0
local conn: RBXScriptConnection? = nil

local MAX_SAMPLES = 280
local SAMPLE_EVERY = 0.03

local function dot(size: number, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Visible = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	f.Parent = plate
	return f
end

local function clearBead()
	for _, d in beadDots do
		d.Visible = false
	end
	beadCount = 0
end

local function hide()
	current = nil
	tracking = nil
	panel.Visible = false
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

local function points(d: { [string]: any }): { Vector2 }
	local out = {}
	local flat = d.points :: { number }
	for i = 1, #flat, 2 do
		table.insert(out, Vector2.new(flat[i], flat[i + 1]))
	end
	return out
end

local function drawSeam(d: { [string]: any })
	local pts = points(d)
	-- dots every ~2% of the plate along the seam
	local list = {}
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local n = math.max(1, math.floor((b - a).Magnitude / 0.02))
		for k = 0, n - 1 do
			table.insert(list, a:Lerp(b, k / n))
		end
	end
	table.insert(list, pts[#pts])
	for i, p in list do
		local s = seamDots[i]
		if not s then
			s = dot(9, Color3.fromRGB(255, 255, 255), 2)
			seamDots[i] = s
		end
		s.Position = UDim2.fromScale(p.X, p.Y)
		s.BackgroundTransparency = 0.35
		s.Visible = true
	end
	for i = #list + 1, #seamDots do
		seamDots[i].Visible = false
	end
	startMark.Position = UDim2.fromScale(pts[1].X, pts[1].Y)
	endMark.Position = UDim2.fromScale(pts[#pts].X, pts[#pts].Y)
	startMark.Visible = true
	endMark.Visible = true
end

local function toPlate(p: Vector2): Vector2
	local a, s = plate.AbsolutePosition, plate.AbsoluteSize
	return Vector2.new((p.X - a.X) / s.X, (p.Y - a.Y) / s.Y)
end

local function addBead(u: Vector2)
	beadCount += 1
	local b = beadDots[beadCount]
	if not b then
		b = dot(12, Color3.fromRGB(255, 150, 40), 3)
		beadDots[beadCount] = b
	end
	b.Position = UDim2.fromScale(u.X, u.Y)
	b.Visible = true
end

local function sample()
	local p = lastPos
	if not tracking or not p or #samples >= MAX_SAMPLES * 3 then
		return
	end
	local now = os.clock()
	if #samples > 0 and now - lastSample < SAMPLE_EVERY then
		return
	end
	lastSample = now
	local u = toPlate(p)
	table.insert(samples, math.clamp(u.X, -0.05, 1.05))
	table.insert(samples, math.clamp(u.Y, -0.05, 1.05))
	table.insert(samples, now - t0)
	addBead(u)
end

local function release()
	if not tracking then
		return
	end
	sample()
	tracking = nil
	if #samples >= 18 then
		hint.Text = "Checking the weld..."
		Net.Event("TraceSubmit"):FireServer(samples)
	end
	samples = {}
	task.delay(0.6, function()
		if current and not tracking then
			clearBead()
			hint.Text = "Start on the green dot and follow the seam to the red one"
		end
	end)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TraceTask"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.55)
	panel.Size = UDim2.fromScale(0.9, 0.72)
	panel.BackgroundColor3 = Color3.fromRGB(25, 27, 32)
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 480)
	limit.Parent = panel

	title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 12, 0, 6)
	title.Size = UDim2.new(1, -70, 0, 30)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local cancel = Instance.new("TextButton")
	cancel.AnchorPoint = Vector2.new(1, 0)
	cancel.Position = UDim2.new(1, -6, 0, 4)
	cancel.Size = UDim2.fromOffset(48, 44)
	cancel.Text = "X"
	cancel.TextScaled = true
	cancel.Font = Enum.Font.GothamBold
	cancel.TextColor3 = Color3.new(1, 1, 1)
	cancel.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
	cancel.Parent = panel
	Instance.new("UICorner").Parent = cancel
	cancel.Activated:Connect(function()
		Net.Event("CancelTask"):FireServer()
	end)

	hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.new(0, 12, 0, 38)
	hint.Size = UDim2.new(1, -24, 0, 22)
	hint.TextColor3 = Color3.fromRGB(200, 205, 215)
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Parent = panel

	-- the steel plate (a square, as big as fits)
	local area = Instance.new("Frame")
	area.BackgroundTransparency = 1
	area.Position = UDim2.new(0, 10, 0, 66)
	area.Size = UDim2.new(1, -20, 1, -76)
	area.Parent = panel
	plate = Instance.new("TextButton")
	plate.Text = ""
	plate.AutoButtonColor = false
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Color3.fromRGB(92, 98, 108)
	plate.Parent = area
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.25
	aspect.Parent = plate
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 8)
	pc.Parent = plate
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(150, 156, 166), Color3.fromRGB(95, 100, 110))
	grad.Rotation = 35
	grad.Parent = plate

	startMark = dot(30, Color3.fromRGB(70, 220, 100), 4)
	endMark = dot(30, Color3.fromRGB(230, 70, 60), 4)
	for _, m in { startMark, endMark } do
		local st = Instance.new("UIStroke")
		st.Color = Color3.new(1, 1, 1)
		st.Thickness = 2
		st.Parent = m
	end

	plate.InputBegan:Connect(function(input)
		if not current or tracking then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			tracking = input
			lastPos = Vector2.new(input.Position.X, input.Position.Y)
			samples = {}
			clearBead()
			t0 = os.clock()
			lastSample = 0
			hint.Text = "Keep the torch on the seam..."
			sample()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local tr = tracking
		if not tr then
			return
		end
		if (tr.UserInputType == Enum.UserInputType.Touch and input == tr)
			or (tr.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
			lastPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local tr = tracking
		if tr and (input == tr or (tr.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
			release()
		end
	end)
end

local function show(d: { [string]: any })
	current = d
	tracking = nil
	samples = {}
	clearBead()
	title.Text = tostring(d.label) .. (if d.missed then "  - try again" else "")
	title.TextColor3 = if d.missed then Color3.fromRGB(255, 140, 120) else Color3.new(1, 1, 1)
	hint.Text = if d.missed and typeof(d.why) == "string" then d.why .. ". New seam!"
		else "Start on the green dot and follow the seam to the red one"
	panel.Visible = true
	task.defer(drawSeam, d)
	if not conn then
		conn = RunService.Heartbeat:Connect(sample)
	end
end

function Trace.Start()
	build()
	Net.Event("TaskBegin").OnClientEvent:Connect(function(d)
		if typeof(d) == "table" and d.kind == "Trace" then
			show(d)
		end
	end)
	Net.Event("TaskEnd").OnClientEvent:Connect(function()
		if current then
			hide()
		end
	end)
end

return Trace
