--!strict
-- Gauge minigame UI (2026-11-13): one big HOLD button (one finger; Space / gamepad A on other devices). Holding raises
-- the needle, letting go lets it fall; keep it in the green until the bar under it fills. Looks per style: Pour
-- (a concrete form filling up to the line), Level (a bubble to keep between the lines), Charge (a pressure gauge),
-- Voltage (a meter). The client draws its own run of the shared math; the server judges (TaskEngine/Gauge).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local SharedGauge = require(ReplicatedStorage.Shared.Util.Gauge)
local Input = require(script.Parent.Parent.InputController)

local Gauge = {}

local player = Players.LocalPlayer
local panel: Frame
local title: TextLabel
local hint: TextLabel
local meter: Frame
local band: Frame
local fill: Frame
local needle: Frame
local bubble: Frame
local unitLabel: TextLabel
local progress: Frame
local holdBtn: TextButton
local current: { [string]: any }? = nil
local state: SharedGauge.State? = nil
local held = false
local conn: RBXScriptConnection? = nil

local LOOK = {
	Pour = { button = "HOLD TO POUR", unit = "FILL LINE", color = Color3.fromRGB(170, 170, 165) },
	Level = { button = "HOLD TO PUSH", unit = "LEVEL", color = Color3.fromRGB(200, 230, 120) },
	Charge = { button = "HOLD TO CHARGE", unit = "PSI", color = Color3.fromRGB(80, 170, 230) },
	Voltage = { button = "HOLD TO RAISE", unit = "VOLTS", color = Color3.fromRGB(255, 210, 60) },
}

local function setHeld(on: boolean)
	if not current or held == on then
		return
	end
	local s = state
	local d = current :: any
	if s then
		SharedGauge.Advance(s, workspace:GetServerTimeNow(), d.rise, d.fall, d.lo, d.hi)
		s.held = on
	end
	held = on
	holdBtn.BackgroundTransparency = if on then 0 else 0.15
	Net.Event("GaugeHold"):FireServer(on)
end

local function hide()
	current = nil
	state = nil
	held = false
	panel.Visible = false
	Input.Unbind("CoopGaugeHold")
	if conn then
		conn:Disconnect()
		conn = nil
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GaugeTask"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -12)
	panel.Size = UDim2.new(0.5, 0, 0, 232)
	panel.BackgroundColor3 = Color3.fromRGB(25, 27, 32)
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel
	local size = Instance.new("UISizeConstraint")
	size.MinSize = Vector2.new(280, 232)
	size.MaxSize = Vector2.new(460, 232)
	size.Parent = panel

	title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 10, 0, 6)
	title.Size = UDim2.new(1, -66, 0, 26)
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
	hint.Position = UDim2.new(0, 10, 0, 34)
	hint.Size = UDim2.new(1, -66, 0, 18)
	hint.TextColor3 = Color3.fromRGB(200, 205, 215)
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Parent = panel

	-- the meter: a bar with the green band; fill (pour) or needle / bubble on top
	meter = Instance.new("Frame")
	meter.Position = UDim2.new(0, 10, 0, 60)
	meter.Size = UDim2.new(1, -20, 0, 44)
	meter.BackgroundColor3 = Color3.fromRGB(55, 58, 66)
	meter.ClipsDescendants = true
	meter.Parent = panel
	Instance.new("UICorner").Parent = meter
	fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = meter
	band = Instance.new("Frame")
	band.BorderSizePixel = 0
	band.BackgroundColor3 = Color3.fromRGB(70, 210, 100)
	band.BackgroundTransparency = 0.35
	band.ZIndex = 2
	band.Parent = meter
	needle = Instance.new("Frame")
	needle.AnchorPoint = Vector2.new(0.5, 0)
	needle.Size = UDim2.new(0, 6, 1, 0)
	needle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	needle.BorderSizePixel = 0
	needle.ZIndex = 3
	needle.Parent = meter
	bubble = Instance.new("Frame")
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = UDim2.fromScale(0, 0.5)
	bubble.Size = UDim2.fromOffset(30, 30)
	bubble.BackgroundColor3 = Color3.fromRGB(235, 250, 255)
	bubble.BackgroundTransparency = 0.15
	bubble.ZIndex = 3
	bubble.Parent = meter
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = bubble
	unitLabel = Instance.new("TextLabel")
	unitLabel.BackgroundTransparency = 1
	unitLabel.AnchorPoint = Vector2.new(1, 0)
	unitLabel.Position = UDim2.new(1, -6, 0, 2)
	unitLabel.Size = UDim2.new(0.3, 0, 0, 14)
	unitLabel.Font = Enum.Font.GothamBold
	unitLabel.TextScaled = true
	unitLabel.TextXAlignment = Enum.TextXAlignment.Right
	unitLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
	unitLabel.ZIndex = 4
	unitLabel.Parent = meter

	-- time-in-the-green bar
	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 10, 0, 110)
	track.Size = UDim2.new(1, -20, 0, 10)
	track.BackgroundColor3 = Color3.fromRGB(50, 52, 60)
	track.Parent = panel
	Instance.new("UICorner").Parent = track
	progress = Instance.new("Frame")
	progress.Size = UDim2.fromScale(0, 1)
	progress.BackgroundColor3 = Color3.fromRGB(70, 210, 100)
	progress.BorderSizePixel = 0
	progress.Parent = track
	Instance.new("UICorner").Parent = progress

	holdBtn = Instance.new("TextButton")
	holdBtn.Position = UDim2.new(0, 10, 0, 128)
	holdBtn.Size = UDim2.new(1, -20, 0, 94)
	holdBtn.TextScaled = true
	holdBtn.Font = Enum.Font.GothamBlack
	holdBtn.TextColor3 = Color3.new(1, 1, 1)
	holdBtn.BackgroundColor3 = Color3.fromRGB(240, 140, 30)
	holdBtn.BackgroundTransparency = 0.15
	holdBtn.AutoButtonColor = false
	holdBtn.Parent = panel
	Instance.new("UICorner").Parent = holdBtn
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.22, 0)
	pad.PaddingBottom = UDim.new(0.22, 0)
	pad.Parent = holdBtn
	holdBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setHeld(true)
		end
	end)
	holdBtn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setHeld(false)
		end
	end)
end

local function render()
	local d, s = current, state
	if not d or not s then
		return
	end
	SharedGauge.Advance(s, workspace:GetServerTimeNow(), d.rise, d.fall, d.lo, d.hi)
	local v = s.v
	local inBand = v >= d.lo and v <= d.hi
	if d.style == "Pour" then
		fill.Size = UDim2.fromScale(v, 1)
		fill.BackgroundColor3 = Color3.fromRGB(165, 165, 160)
		needle.Position = UDim2.fromScale(v, 0)
	elseif d.style == "Level" then
		bubble.Position = UDim2.fromScale(v, 0.5)
		bubble.BackgroundColor3 = if inBand then Color3.fromRGB(190, 255, 200) else Color3.fromRGB(235, 250, 255)
	else
		needle.Position = UDim2.fromScale(v, 0)
	end
	needle.BackgroundColor3 = if inBand then Color3.fromRGB(120, 255, 140) else Color3.new(1, 1, 1)
	progress.Size = UDim2.fromScale(math.clamp(s.inBand / d.need, 0, 1), 1)
end

local function show(d: { [string]: any })
	current = d
	state = SharedGauge.NewState(d.start)
	held = false
	local look = LOOK[d.style] or LOOK.Pour
	local st = SharedGauge.STYLES[d.style]
	title.Text = tostring(d.label) .. (if d.missed then "  - out of time, again!" else "")
	title.TextColor3 = if d.missed then Color3.fromRGB(255, 140, 120) else Color3.new(1, 1, 1)
	hint.Text = if st then st.hint else ""
	holdBtn.Text = look.button
	holdBtn.BackgroundTransparency = 0.15
	unitLabel.Text = look.unit
	band.Position = UDim2.fromScale(d.lo, 0)
	band.Size = UDim2.fromScale(d.hi - d.lo, 1)
	fill.Visible = d.style == "Pour"
	bubble.Visible = d.style == "Level"
	needle.Visible = d.style ~= "Level"
	meter.BackgroundColor3 = if d.style == "Level" then Color3.fromRGB(90, 120, 60) else Color3.fromRGB(55, 58, 66)
	progress.Size = UDim2.fromScale(0, 1)
	panel.Visible = true
	Input.BindHold("CoopGaugeHold", setHeld, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	if not conn then
		conn = RunService.Heartbeat:Connect(render)
	end
end

function Gauge.Start()
	build()
	Net.Event("TaskBegin").OnClientEvent:Connect(function(d)
		if typeof(d) == "table" and d.kind == "Gauge" then
			show(d)
		end
	end)
	Net.Event("TaskEnd").OnClientEvent:Connect(function()
		if current then
			hide()
		end
	end)
end

return Gauge
