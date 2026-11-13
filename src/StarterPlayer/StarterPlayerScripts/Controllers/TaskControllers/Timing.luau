--!strict
-- Timing minigame UI: one big TAP button (one finger). Space / gamepad A also tap.
-- The client only draws the needle and reports "I tapped"; the server decides hit or miss.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local SharedTiming = require(ReplicatedStorage.Shared.Util.Timing)
local Input = require(script.Parent.Parent.InputController)

local Timing = {}

local player = Players.LocalPlayer
local panel: Frame
local zone: Frame
local needle: Frame
local title: TextLabel
local current: { [string]: any }? = nil
local renderConn: RBXScriptConnection? = nil

local function hide()
	current = nil
	panel.Visible = false
	Input.Unbind("CoopTimingTap")
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function tap()
	if current then
		Net.Event("TimingTap"):FireServer()
		needle.BackgroundColor3 = Color3.new(1, 1, 1)
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TimingTask"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -12)
	panel.Size = UDim2.new(0.42, 0, 0, 170)
	panel.BackgroundColor3 = Color3.fromRGB(25, 27, 32)
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel
	local size = Instance.new("UISizeConstraint")
	size.MinSize = Vector2.new(260, 170)
	size.MaxSize = Vector2.new(440, 170)
	size.Parent = panel

	title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 10, 0, 6)
	title.Size = UDim2.new(1, -66, 0, 28)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBold
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

	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 10, 0, 50)
	bar.Size = UDim2.new(1, -20, 0, 30)
	bar.BackgroundColor3 = Color3.fromRGB(60, 62, 70)
	bar.ClipsDescendants = true
	bar.Parent = panel
	Instance.new("UICorner").Parent = bar

	zone = Instance.new("Frame")
	zone.BackgroundColor3 = Color3.fromRGB(70, 200, 100)
	zone.BorderSizePixel = 0
	zone.Size = UDim2.fromScale(0.2, 1)
	zone.Parent = bar

	needle = Instance.new("Frame")
	needle.AnchorPoint = Vector2.new(0.5, 0)
	needle.Size = UDim2.new(0, 6, 1, 0)
	needle.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
	needle.BorderSizePixel = 0
	needle.ZIndex = 2
	needle.Parent = bar

	local tapBtn = Instance.new("TextButton")
	tapBtn.Position = UDim2.new(0, 10, 0, 90)
	tapBtn.Size = UDim2.new(1, -20, 0, 70)
	tapBtn.Text = "TAP in the green"
	tapBtn.TextScaled = true
	tapBtn.Font = Enum.Font.GothamBlack
	tapBtn.TextColor3 = Color3.new(1, 1, 1)
	tapBtn.BackgroundColor3 = Color3.fromRGB(240, 140, 30)
	tapBtn.Parent = panel
	Instance.new("UICorner").Parent = tapBtn
	tapBtn.Activated:Connect(tap)
end

local function show(d: { [string]: any })
	current = d
	title.Text = tostring(d.label) .. (if d.missed then "  - missed, again!" else "")
	title.TextColor3 = if d.missed then Color3.fromRGB(255, 140, 120) else Color3.new(1, 1, 1)
	zone.Position = UDim2.fromScale(d.zMin, 0)
	zone.Size = UDim2.fromScale(d.zMax - d.zMin, 1)
	panel.Visible = true
	Input.BindTap("CoopTimingTap", tap, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	if not renderConn then
		renderConn = RunService.Heartbeat:Connect(function()
			local c = current
			if not c then
				return
			end
			local x = SharedTiming.NeedleAt(workspace:GetServerTimeNow() - c.start, c.period)
			needle.Position = UDim2.fromScale(x, 0)
			needle.BackgroundColor3 = Color3.fromRGB(255, 220, 60)
		end)
	end
end

function Timing.Start()
	build()
	Net.Event("TaskBegin").OnClientEvent:Connect(function(d)
		if typeof(d) == "table" and d.kind == "Timing" then
			show(d)
		end
	end)
	Net.Event("TaskEnd").OnClientEvent:Connect(function()
		if current then
			hide()
		end
	end)
end

return Timing
