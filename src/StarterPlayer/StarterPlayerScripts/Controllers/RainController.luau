--!strict
-- Rain delay (ChaosService): while workspace.RainUntil is in the future, rain falls around the camera and a
-- banner counts down. Display only; the server decides when it rains and blocks the pours.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Settings = require(script.Parent.SettingsController)

local Rain = {}

local player = Players.LocalPlayer
local emitterPart: Part
local emitter: ParticleEmitter
local banner: TextLabel
local conn: RBXScriptConnection? = nil

local function build()
	emitterPart = Instance.new("Part")
	emitterPart.Name = "RainCloud"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(90, 1, 90)

	emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Rate = 900
	emitter.Lifetime = NumberRange.new(1.1, 1.4)
	emitter.Speed = NumberRange.new(70, 85)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(4, 4)
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Size = NumberSequence.new(0.09)
	emitter.Squash = NumberSequence.new(-3) -- stretch each drop into a streak
	emitter.Transparency = NumberSequence.new(0.45)
	emitter.Color = ColorSequence.new(Color3.fromRGB(190, 205, 225))
	emitter.LightInfluence = 0.6
	emitter.Parent = emitterPart

	local gui = Instance.new("ScreenGui")
	gui.Name = "RainBanner"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")

	banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 200)
	banner.Size = UDim2.new(0.5, 0, 0, 34)
	banner.BackgroundColor3 = Color3.fromRGB(40, 70, 120)
	banner.BackgroundTransparency = 0.15
	banner.TextColor3 = Color3.new(1, 1, 1)
	banner.Font = Enum.Font.GothamBold
	banner.TextScaled = true
	banner.Visible = false
	banner.Parent = gui
	Instance.new("UICorner").Parent = banner
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(460, 34)
	size.Parent = banner
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = banner
end

local function update()
	local untilAt = workspace:GetAttribute("RainUntil")
	local left = if typeof(untilAt) == "number" then untilAt - workspace:GetServerTimeNow() else 0
	if left <= 0 then
		emitter.Enabled = false
		banner.Visible = false
		emitterPart.Parent = nil
		if conn then
			conn:Disconnect()
			conn = nil
		end
		return
	end
	local cam = workspace.CurrentCamera
	if cam then
		emitterPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0))
	end
	emitterPart.Parent = workspace
	local q = Settings.Quality()
	emitter.Rate = if q == "Low" then 300 elseif q == "Medium" then 600 else 900 -- lighter rain on slower devices
	emitter.Enabled = true
	banner.Visible = true
	local s = math.ceil(left)
	banner.Text = ("RAIN DELAY %d:%02d  -  no pouring, mud slows vehicles"):format(s // 60, s % 60)
end

local function watch()
	if not conn then
		conn = RunService.Heartbeat:Connect(update)
	end
	update()
end

function Rain.Start()
	build()
	workspace:GetAttributeChangedSignal("RainUntil"):Connect(watch)
	watch()
end

return Rain
