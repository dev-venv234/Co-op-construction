--!strict
-- Driving. Two jobs:
--  * The drive model (2026-11-12): when the server hands this player the vehicle (model attribute DriverId = our
--    UserId, see VehicleService), the truck is simulated here, so it answers instantly. Throttle eases off near top
--    speed, the truck coasts when you let go, brakes hard against its motion, and steering eases in (less lock at
--    speed) and turns like a car (yaw = speed x tan(steer angle) / wheelbase). Machines without a wheelbase (the
--    excavator's tracks) turn on the spot. Limits come from the model's attributes; the server's guard checks them.
--  * Speedometer (2026-11-12): MPH (1 stud = 1 foot), gear D / N / R, a speed bar against the truck's top speed, and a
--    MUD tag while rain slows vehicles. Bottom center, moved up above the pedals when the screen is too narrow.
--  * On-screen truck controls for touch: big steer buttons bottom-left, GAS and BRAKE/REVERSE bottom-right, EXIT above
--    the brake. While driving on touch, the default thumbstick and jump button are hidden so the pedals take their
--    place. Keyboard and gamepad use the seat's normal throttle/steer and get just an EXIT (Space) button.
-- The pedal state is also sent to the server (DriveInput), which drives the vehicle whenever it owns it.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Settings = require(script.Parent.SettingsController)

local VehicleController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local pads: { [string]: TextButton } = {}
local held = { gas = false, brake = false, left = false, right = false }
local driving = false
local touchUI = false -- pedals on screen (set when getting in)
local lastSent = 0
local lastThrottle, lastSteer = 0, 0

-- drive model state
local seat: VehicleSeat? = nil
local vehicle: Model? = nil
local speed = 0 -- studs/s along the truck's nose (negative = reversing)
local steerAngle = 0 -- radians, + = right
local steerSmooth = 0 -- -1..1 (tracked machines)

local RESEND = 0.1
local COAST = 9 -- studs/s^2 lost when nothing is pressed (plus a bit more at speed)
local LOCK_SLOW = math.rad(34) -- steering lock at a crawl
local LOCK_FAST = math.rad(11) -- and at top speed (tracked machines)
local MAX_YAW = 0.9 -- rad/s: trucks never turn faster than this, so they stay steady at any speed
local MPH = 0.6818 -- studs/s -> mph (1 stud = 1 foot)
local STEER_IN = 2.4 -- rad/s turning the wheel
local STEER_OUT = 4.5 -- rad/s letting it center

-- Studio-only switch so the touch layout can be checked on a desktop: workspace attribute DevForceTouchUI = true
local function useTouchUI(): boolean
	return UserInputService.TouchEnabled
		or (RunService:IsStudio() and workspace:GetAttribute("DevForceTouchUI") == true)
end

local function axes(): (number, number)
	local throttle = (if held.gas then 1 else 0) - (if held.brake then 1 else 0)
	local steer = (if held.right then 1 else 0) - (if held.left then 1 else 0)
	return throttle, steer
end

local function send(force: boolean)
	local throttle, steer = axes()
	local changed = throttle ~= lastThrottle or steer ~= lastSteer
	local active = throttle ~= 0 or steer ~= 0
	if force or changed or (active and os.clock() - lastSent >= RESEND) then
		Net.Event("DriveInput"):FireServer(throttle, steer)
		lastSent = os.clock()
		lastThrottle, lastSteer = throttle, steer
	end
end

local function releaseAll()
	for k in held do
		held[k] = false
	end
	if not gui then
		return
	end
	for _, b in gui:GetDescendants() do
		if b:IsA("TextButton") and b:GetAttribute("Key") then
			b.BackgroundTransparency = 0.25
		end
	end
end

local function moveToward(a: number, b: number, step: number): number
	if a < b then
		return math.min(a + step, b)
	end
	return math.max(a - step, b)
end

local function num(m: Model, key: string, default: number): number
	local v = m:GetAttribute(key)
	return if typeof(v) == "number" then v else default
end

-- One step of the drive model, only while the server has handed us this vehicle.
local function driveStep(dt: number)
	local m, s = vehicle, seat
	if not driving or not m or not s or m:GetAttribute("DriverId") ~= player.UserId then
		speed, steerAngle, steerSmooth = 0, 0, 0
		return
	end
	local lv = m:FindFirstChildWhichIsA("LinearVelocity", true)
	local av = m:FindFirstChildWhichIsA("AngularVelocity", true)
	local root = lv and (lv :: LinearVelocity).Attachment0 and ((lv :: LinearVelocity).Attachment0 :: Attachment).Parent
	if not lv or not av or not root or not root:IsA("BasePart") then
		return
	end
	-- input: pedals on touch, else the seat (keyboard / gamepad)
	local throttle, steer = s.ThrottleFloat, s.SteerFloat
	if touchUI then
		local t, st = axes()
		if t ~= 0 then
			throttle = t
		end
		if st ~= 0 then
			steer = st
		end
	end
	local factor = num(m, "SpeedFactor", 1)
	local maxF = num(m, "MaxFwd", 30) * factor
	local maxR = num(m, "MaxRev", 12) * factor
	local accel, brake = num(m, "Accel", 20), num(m, "Brake", 45)

	-- bumping into something takes the speed off (we simulate it, so the real velocity is right here)
	local actual = root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector)
	if math.abs(speed) > math.abs(actual) + 4 then
		speed = actual + math.sign(speed) * 4
	end

	-- speed
	local target = if throttle > 0 then throttle * maxF elseif throttle < 0 then throttle * maxR else 0
	if throttle ~= 0 and (math.abs(speed) < 0.5 or math.sign(target) == math.sign(speed)) then
		local frac = math.clamp(math.abs(speed) / math.max(maxF, 1), 0, 1)
		speed = moveToward(speed, target, accel * (1.2 - 0.6 * frac) * dt) -- strong pull-away, easing near the top
	elseif throttle == 0 then
		speed = moveToward(speed, 0, (COAST + math.abs(speed) * 0.25) * dt)
	else
		speed = moveToward(speed, 0, brake * dt) -- pressing against the motion = brakes; then it backs up
	end
	if math.abs(speed) > maxF + 0.5 then
		speed = math.sign(speed) * maxF -- mud slowed us down
	end

	-- steering
	-- steering lock: full at a crawl; for trucks it is then capped so the turn rate stays under MAX_YAW
	local wbLock = m:GetAttribute("Wheelbase")
	local lock: number
	if typeof(wbLock) == "number" and wbLock > 0 then
		lock = math.min(LOCK_SLOW, math.atan(MAX_YAW * wbLock / math.max(math.abs(speed), 1)))
	else
		local frac = math.clamp(math.abs(speed) / math.max(num(m, "MaxFwd", 30), 1), 0, 1)
		lock = LOCK_SLOW + (LOCK_FAST - LOCK_SLOW) * frac
	end
	local want = steer * lock
	local centering = math.abs(want) < math.abs(steerAngle) or math.sign(want) ~= math.sign(steerAngle)
	steerAngle = moveToward(steerAngle, want, (if centering then STEER_OUT else STEER_IN) * dt)
	steerSmooth = moveToward(steerSmooth, steer, 4 * dt)
	local yaw: number
	local wb = m:GetAttribute("Wheelbase")
	if typeof(wb) == "number" and wb > 0 then
		yaw = speed * math.tan(steerAngle) / wb
	else
		yaw = steerSmooth * num(m, "Turn", 1) * (if speed < -0.5 then -1 else 1) -- tracks: turn on the spot
	end

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	;(lv :: LinearVelocity).VectorVelocity = flat * speed
	;(av :: AngularVelocity).AngularVelocity = Vector3.new(0, -yaw, 0)
	m:SetAttribute("LocalSteer", steerAngle) -- client-only: WheelController turns the front wheels by it
end

local function pad(name: string, key: string?, text: string, color: Color3, size: UDim2, pos: UDim2, anchor: Vector2): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.TextScaled = true
	b.Font = Enum.Font.GothamBlack
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.25
	b.AutoButtonColor = false
	b.Size = size
	b.Position = pos
	b.AnchorPoint = anchor
	b.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.2, 0)
	c.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
	padding.PaddingLeft = UDim.new(0.1, 0)
	padding.PaddingRight = UDim.new(0.1, 0)
	padding.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.5
	stroke.Parent = b

	if key then
		b:SetAttribute("Key", key)
		-- Hold-to-press, multi-touch safe: each button tracks its own touch.
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				held[key] = true
				b.BackgroundTransparency = 0
				send(true)
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				held[key] = false
				b.BackgroundTransparency = 0.25
				send(true)
			end
		end)
	end
	return b
end

-- Places the drive buttons from the player's settings: pedals under the right thumb ("Right hand", default) or
-- the left, steering on the other side; Large = 1.3x. Outer buttons sit 16 px from the edge, inner ones beside them.
local speedo: Frame? = nil

local function layout()
	if not pads.Gas then
		return
	end
	local s = if Settings.Get("BigButtons") == true then 1.3 else 1
	local pedalsRight = Settings.Get("DriveLayout") ~= "Left"
	local function put(b: TextButton, w: number, h: number, fromEdge: number, onRight: boolean, fromBottom: number?)
		local y = fromBottom or 16
		b.Size = UDim2.fromOffset(w * s, h * s)
		if onRight then
			b.AnchorPoint = Vector2.new(1, 1)
			b.Position = UDim2.new(1, -fromEdge, 1, -y)
		else
			b.AnchorPoint = Vector2.new(0, 1)
			b.Position = UDim2.new(0, fromEdge, 1, -y)
		end
	end
	put(pads.Gas, 110, 130, 16, pedalsRight)
	put(pads.Brake, 96, 96, 16 + 122 * s, pedalsRight)
	if pads.Exit then
		if touchUI then
			put(pads.Exit, 96, 50, 16 + 122 * s, pedalsRight, 16 + 96 * s + 12) -- right above the brake
		else
			put(pads.Exit, 150, 50, 16, true) -- keyboard / gamepad: just the EXIT button, bottom-right
		end
	end
	local steerRight = not pedalsRight
	-- "<" always left of ">"
	put(pads.SteerLeft, 96, 96, if steerRight then 16 + 108 * s else 16, steerRight)
	put(pads.SteerRight, 96, 96, if steerRight then 16 else 16 + 108 * s, steerRight)
	-- speedometer: bottom center if it fits between the buttons, else above them
	if speedo then
		local sideUsed = if touchUI then 16 + 218 * s else 16 + 150
		local free = gui.AbsoluteSize.X - 2 * sideUsed
		speedo.Position = if free >= 190 or not touchUI
			then UDim2.new(0.5, 0, 1, -16)
			else UDim2.new(0.5, 0, 1, -(16 + 130 * s + 12))
	end
end

-- The dash: speed in MPH, gear, a bar against top speed, and a MUD tag.
local speedoNum: TextLabel
local speedoGear: TextLabel
local speedoFill: Frame
local speedoMud: TextLabel
local shownSpeed = 0 -- studs/s, smoothed (negative = reversing)
local lastRootPos: Vector3? = nil

local function buildSpeedo()
	local f = Instance.new("Frame")
	f.Name = "Speedometer"
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 1, -16)
	f.Size = UDim2.fromOffset(176, 76)
	f.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	f.BackgroundTransparency = 0.12
	f.Active = false
	f.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 255, 255)
	st.Transparency = 0.75
	st.Thickness = 2
	st.Parent = f
	local function label(name: string, text: string, pos: UDim2, size: UDim2, font: Enum.Font, color: Color3, align: Enum.TextXAlignment): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = pos
		l.Size = size
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = color
		l.TextXAlignment = align
		l.Text = text
		l.Parent = f
		return l
	end
	speedoNum = label("Speed", "0", UDim2.fromOffset(10, 4), UDim2.fromOffset(100, 50), Enum.Font.GothamBlack, Color3.new(1, 1, 1), Enum.TextXAlignment.Right)
	label("Unit", "MPH", UDim2.fromOffset(116, 10), UDim2.fromOffset(48, 18), Enum.Font.GothamBold, Color3.fromRGB(170, 175, 185), Enum.TextXAlignment.Left)
	speedoGear = label("Gear", "N", UDim2.fromOffset(116, 29), UDim2.fromOffset(48, 25), Enum.Font.GothamBlack, Color3.fromRGB(170, 175, 185), Enum.TextXAlignment.Left)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.new(0, 12, 1, -16)
	bar.Size = UDim2.new(1, -24, 0, 8)
	bar.BackgroundColor3 = Color3.fromRGB(50, 54, 64)
	bar.BorderSizePixel = 0
	bar.Parent = f
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = bar
	speedoFill = Instance.new("Frame")
	speedoFill.Name = "Fill"
	speedoFill.Size = UDim2.fromScale(0, 1)
	speedoFill.BorderSizePixel = 0
	speedoFill.BackgroundColor3 = Color3.fromRGB(70, 200, 90)
	speedoFill.Parent = bar
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = speedoFill
	speedoMud = Instance.new("TextLabel")
	speedoMud.Name = "Mud"
	speedoMud.AnchorPoint = Vector2.new(0.5, 1)
	speedoMud.Position = UDim2.new(0.5, 0, 0, -4)
	speedoMud.Size = UDim2.fromOffset(110, 22)
	speedoMud.BackgroundColor3 = Color3.fromRGB(150, 95, 40)
	speedoMud.Font = Enum.Font.GothamBlack
	speedoMud.TextScaled = true
	speedoMud.TextColor3 = Color3.new(1, 1, 1)
	speedoMud.Text = "MUD: SLOW"
	speedoMud.Visible = false
	speedoMud.Parent = f
	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(1, 0)
	mc.Parent = speedoMud
	speedo = f
end

local function updateSpeedo(dt: number)
	local m, s = vehicle, seat
	local root = s and s.AssemblyRootPart
	if not driving or not m or not root or dt <= 0 then
		lastRootPos = nil
		shownSpeed = 0
		return
	end
	local pos = root.Position
	local v = if lastRootPos then ((pos - lastRootPos :: Vector3) * Vector3.new(1, 0, 1)):Dot(root.CFrame.LookVector) / dt else 0
	lastRootPos = pos
	if math.abs(v) > 250 then
		v = shownSpeed -- a teleport, not speed
	end
	shownSpeed += (v - shownSpeed) * math.min(1, dt * 8)
	speedoNum.Text = tostring(math.floor(math.abs(shownSpeed) * MPH + 0.5))
	if shownSpeed < -0.8 then
		speedoGear.Text, speedoGear.TextColor3 = "R", Color3.fromRGB(255, 110, 90)
	elseif shownSpeed > 0.8 then
		speedoGear.Text, speedoGear.TextColor3 = "D", Color3.fromRGB(110, 220, 120)
	else
		speedoGear.Text, speedoGear.TextColor3 = "N", Color3.fromRGB(170, 175, 185)
	end
	local frac = math.clamp(math.abs(shownSpeed) / math.max(num(m, "MaxFwd", 30), 1), 0, 1)
	speedoFill.Size = UDim2.fromScale(frac, 1)
	speedoFill.BackgroundColor3 = Color3.fromRGB(70, 200, 90):Lerp(Color3.fromRGB(255, 160, 40), frac)
	speedoMud.Visible = num(m, "SpeedFactor", 1) < 0.99
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "DriveControls"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 4
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local grey = Color3.fromRGB(60, 65, 75)
	-- Steering bottom-left (where the thumbstick normally is), pedals bottom-right (where jump is); layout() can
	-- swap the sides and enlarge them (SETTINGS > Controls).
	pads.SteerLeft = pad("SteerLeft", "left", "<", grey, UDim2.fromOffset(96, 96), UDim2.new(0, 16, 1, -16), Vector2.new(0, 1))
	pads.SteerRight = pad("SteerRight", "right", ">", grey, UDim2.fromOffset(96, 96), UDim2.new(0, 124, 1, -16), Vector2.new(0, 1))
	pads.Gas = pad("Gas", "gas", "GAS", Color3.fromRGB(50, 160, 80), UDim2.fromOffset(110, 130), UDim2.new(1, -16, 1, -16), Vector2.new(1, 1))
	pads.Brake = pad("Brake", "brake", "BRAKE\nREV", Color3.fromRGB(180, 60, 50), UDim2.fromOffset(96, 96), UDim2.new(1, -138, 1, -16), Vector2.new(1, 1))
	layout()
	-- Exit: above the brake (layout() places it)
	local exit = pad("Exit", nil, "EXIT", Color3.fromRGB(70, 90, 140), UDim2.fromOffset(96, 50), UDim2.new(1, -138, 1, -124), Vector2.new(1, 1))
	pads.Exit = exit
	buildSpeedo()
	layout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout) -- phone turned / window resized
	exit.Activated:Connect(function()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			-- Jump state leaves the seat even while the default touch controls are hidden.
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
end

local function enter(s: VehicleSeat)
	driving = true
	seat = s
	speed, steerAngle, steerSmooth = 0, 0, 0
	local m: Instance? = s.Parent
	while m and not (m:IsA("Model") and m:GetAttribute("MaxFwd") ~= nil) do
		m = m.Parent
	end
	vehicle = if m and m:IsA("Model") then m else nil
	touchUI = useTouchUI()
	releaseAll()
	for name, b in pads do
		b.Visible = touchUI or name == "Exit"
	end
	if pads.Exit then
		pads.Exit.Text = if touchUI then "EXIT" else "EXIT (Space)"
	end
	layout()
	gui.Enabled = true
	if touchUI then
		GuiService.TouchControlsEnabled = false -- hide thumbstick + jump; the pedals replace them
		-- PING / CREW / COMPANY sit where the pedals go on a phone: tucked away while driving
		for _, name in { "CrewTools", "CompanyTools" } do
			local g = player.PlayerGui:FindFirstChild(name)
			if g and g:IsA("ScreenGui") then
				g.Enabled = false
			end
		end
	end
end

local function leave()
	if not driving then
		return
	end
	driving = false
	if vehicle then
		vehicle:SetAttribute("LocalSteer", nil)
	end
	seat, vehicle = nil, nil
	speed, steerAngle, steerSmooth = 0, 0, 0
	releaseAll()
	gui.Enabled = false
	lastThrottle, lastSteer = 0, 0
	GuiService.TouchControlsEnabled = true
	for _, name in { "CrewTools", "CompanyTools" } do
		local g = player.PlayerGui:FindFirstChild(name)
		if g and g:IsA("ScreenGui") then
			g.Enabled = true
		end
	end
end

local function hookCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.Seated:Connect(function(active, seatPart)
		if active and seatPart and seatPart:IsA("VehicleSeat") then
			enter(seatPart)
		else
			leave()
		end
	end)
	hum.Died:Connect(leave)
end

function VehicleController.Start()
	build()
	Settings.Changed.Event:Connect(layout)
	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	player.CharacterAdded:Connect(function(c)
		leave()
		hookCharacter(c)
	end)
	RunService.Heartbeat:Connect(function(dt)
		if driving and touchUI then
			send(false)
		end
		updateSpeedo(dt)
	end)
	RunService.Stepped:Connect(function(_, dt)
		driveStep(dt)
	end)
end

return VehicleController
