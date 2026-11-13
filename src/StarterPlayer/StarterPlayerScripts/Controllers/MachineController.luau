--!strict
-- Hands-on machine controls (2026-11-12, owner chose full manual with a guide):
--  * Crane cab: < SWING >, BOOM UP / DOWN, HOOK UP / DOWN (keys A / D, W / S, R / F) and EXIT.
--  * Excavator: ARM UP / ARM DOWN (keys R / F) beside the drive buttons (VehicleController does the driving).
-- Holding a control sends its axis to the server (MachineInput, resent while held), which moves the machine; nothing
-- here moves anything. A panel under the hint bar shows the task hint and how far off target the hook / load /
-- bucket is, and the world shows a glowing column on the target plus a marker straight under the hook / bucket that
-- turns green once it's lined up. (Task state comes from the machine model's attributes, set by EquipmentService.)
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Settings = require(script.Parent.SettingsController)

local Machine = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local panel: Frame
local hintLabel: TextLabel
local infoLabel: TextLabel
local buttons: { [string]: TextButton } = {}
local rig: Model? = nil
local kind: string? = nil -- "Crane" or "Excavator"
local pressed: { [string]: boolean } = {} -- control name -> held (buttons and keys share it)
local lastSent = 0
local lastA, lastB, lastC = 0, 0, 0
local guides: Folder
local column: BasePart
local ring: BasePart
local marker: BasePart

local LIFT_TOL, DIG_TOL = 2.5, 3
local RESEND = 0.1
local GREEN = Color3.fromRGB(80, 230, 110)
local ORANGE = Color3.fromRGB(255, 160, 40)

-- control -> (axis, direction)
local CONTROLS: { [string]: { axis: string, dir: number, text: string, key: Enum.KeyCode, alt: Enum.KeyCode? } } = {
	SwingLeft = { axis = "a", dir = -1, text = "< SWING", key = Enum.KeyCode.A, alt = Enum.KeyCode.Left },
	SwingRight = { axis = "a", dir = 1, text = "SWING >", key = Enum.KeyCode.D, alt = Enum.KeyCode.Right },
	BoomUp = { axis = "b", dir = 1, text = "BOOM UP", key = Enum.KeyCode.W, alt = Enum.KeyCode.Up },
	BoomDown = { axis = "b", dir = -1, text = "BOOM DOWN", key = Enum.KeyCode.S, alt = Enum.KeyCode.Down },
	HookUp = { axis = "c", dir = 1, text = "HOOK UP", key = Enum.KeyCode.R },
	HookDown = { axis = "c", dir = -1, text = "HOOK DOWN", key = Enum.KeyCode.F },
	ArmUp = { axis = "a", dir = 1, text = "ARM UP", key = Enum.KeyCode.R },
	ArmDown = { axis = "a", dir = -1, text = "ARM DOWN", key = Enum.KeyCode.F },
}
local CRANE = { "SwingLeft", "SwingRight", "BoomUp", "BoomDown", "HookUp", "HookDown" }
local EXCAVATOR = { "ArmUp", "ArmDown" }

local function axes(): (number, number, number)
	local v = { a = 0, b = 0, c = 0 }
	for name, on in pressed do
		local c = CONTROLS[name]
		if on and c then
			v[c.axis] += c.dir
		end
	end
	return math.clamp(v.a, -1, 1), math.clamp(v.b, -1, 1), math.clamp(v.c, -1, 1)
end

local function send(force: boolean)
	local a, b, c = axes()
	local changed = a ~= lastA or b ~= lastB or c ~= lastC
	local active = a ~= 0 or b ~= 0 or c ~= 0
	if force or changed or (active and os.clock() - lastSent >= RESEND) then
		Net.Event("MachineInput"):FireServer(a, b, c)
		lastSent = os.clock()
		lastA, lastB, lastC = a, b, c
	end
end

local function release()
	table.clear(pressed)
	for _, b in buttons do
		b.BackgroundTransparency = 0.2
	end
end

local function holdButton(name: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = CONTROLS[name].text
	b.TextScaled = true
	b.Font = Enum.Font.GothamBlack
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.2
	b.AutoButtonColor = false
	b.Visible = false
	b.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.18, 0)
	c.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.18, 0)
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.Parent = b
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = Color3.new(1, 1, 1)
	st.Transparency = 0.5
	st.Thickness = 2
	st.Parent = b
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			pressed[name] = true
			b.BackgroundTransparency = 0
			send(true)
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			pressed[name] = nil
			b.BackgroundTransparency = 0.2
			send(true)
		end
	end)
	buttons[name] = b
	return b
end

-- Places the buttons for the machine we're in. Sizes follow SETTINGS > Button size.
local function layout()
	local s = if Settings.Get("BigButtons") == true then 1.3 else 1
	local function put(b: TextButton, w: number, h: number, x: number, fromBottom: number, right: boolean)
		b.Size = UDim2.fromOffset(w * s, h * s)
		b.AnchorPoint = Vector2.new(if right then 1 else 0, 1)
		b.Position = UDim2.new(if right then 1 else 0, if right then -x else x, 1, -fromBottom)
	end
	-- crane: swing bottom-left, boom + hook columns bottom-right, EXIT above the swing buttons
	put(buttons.SwingLeft, 100, 80, 16, 16, false)
	put(buttons.SwingRight, 100, 80, 16 + 112 * s, 16, false)
	put(buttons.Exit, 100, 50, 16, 16 + 92 * s, false)
	put(buttons.HookDown, 100, 72, 16, 16, true)
	put(buttons.HookUp, 100, 72, 16, 16 + 84 * s, true)
	put(buttons.BoomDown, 100, 72, 16 + 112 * s, 16, true)
	put(buttons.BoomUp, 100, 72, 16 + 112 * s, 16 + 84 * s, true)
	-- excavator: ARM buttons above the steering buttons (VehicleController's side for steering)
	local steerLeft = Settings.Get("DriveLayout") ~= "Left"
	local above = 16 + 96 * s + 12
	put(buttons.ArmUp, 100, 64, 16, above, not steerLeft)
	put(buttons.ArmDown, 100, 64, 16 + 112 * s, above, not steerLeft)
end

local function bindKeys(list: { string })
	for _, name in list do
		local c = CONTROLS[name]
		local keys = { c.key }
		if c.alt then
			table.insert(keys, c.alt)
		end
		ContextActionService:BindActionAtPriority("Machine" .. name, function(_, state)
			if state == Enum.UserInputState.Begin then
				pressed[name] = true
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				pressed[name] = nil
			end
			send(true)
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
	end
end

local function unbindKeys()
	for name in CONTROLS do
		ContextActionService:UnbindAction("Machine" .. name)
	end
end

local function setTools(on: boolean)
	for _, name in { "CrewTools", "CompanyTools" } do
		local g = player.PlayerGui:FindFirstChild(name)
		if g and g:IsA("ScreenGui") then
			g.Enabled = on
		end
	end
end

local function enter(seatPart: BasePart)
	local m = seatPart.Parent
	if not m or not m:IsA("Model") then
		return
	end
	if seatPart.Name == "CraneSeat" then
		kind = "Crane"
	elseif seatPart.Name == "OperatorSeat" and m.Name == "Excavator" then
		kind = "Excavator"
	else
		return
	end
	rig = m
	release()
	local list = if kind == "Crane" then CRANE else EXCAVATOR
	for name, b in buttons do
		b.Visible = table.find(list, name) ~= nil or (name == "Exit" and kind == "Crane")
	end
	-- keyboard: the crane's keys stand in for walking (seated anyway); the excavator keeps WASD for driving
	bindKeys(list)
	layout()
	gui.Enabled = true
	if kind == "Crane" then
		GuiService.TouchControlsEnabled = false -- the crane buttons replace the thumbstick and jump
		setTools(false)
	end
end

local function leave()
	if not rig then
		return
	end
	if kind == "Crane" then
		GuiService.TouchControlsEnabled = true
		setTools(true)
	end
	rig, kind = nil, nil
	release()
	unbindKeys()
	send(true)
	gui.Enabled = false
	guides.Parent = nil
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "MachineControls"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local yellow = Color3.fromRGB(205, 145, 20)
	local grey = Color3.fromRGB(60, 65, 75)
	holdButton("SwingLeft", grey)
	holdButton("SwingRight", grey)
	holdButton("BoomUp", yellow)
	holdButton("BoomDown", yellow)
	holdButton("HookUp", Color3.fromRGB(70, 110, 160))
	holdButton("HookDown", Color3.fromRGB(70, 110, 160))
	holdButton("ArmUp", yellow)
	holdButton("ArmDown", yellow)
	local exit = Instance.new("TextButton")
	exit.Name = "Exit"
	exit.Text = "EXIT"
	exit.TextScaled = true
	exit.Font = Enum.Font.GothamBlack
	exit.TextColor3 = Color3.new(1, 1, 1)
	exit.BackgroundColor3 = Color3.fromRGB(70, 90, 140)
	exit.BackgroundTransparency = 0.2
	exit.Visible = false
	exit.Parent = gui
	local ec = Instance.new("UICorner")
	ec.CornerRadius = UDim.new(0.2, 0)
	ec.Parent = exit
	local ep = Instance.new("UIPadding")
	ep.PaddingTop = UDim.new(0.2, 0)
	ep.PaddingBottom = UDim.new(0.2, 0)
	ep.Parent = exit
	exit.Activated:Connect(function()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
	buttons.Exit = exit

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 96)
	panel.Size = UDim2.new(0.7, 0, 0, 62)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	panel.BackgroundTransparency = 0.15
	panel.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, 62)
	limit.Parent = panel
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 12)
	pc.Parent = panel
	hintLabel = Instance.new("TextLabel")
	hintLabel.BackgroundTransparency = 1
	hintLabel.Position = UDim2.new(0, 10, 0, 4)
	hintLabel.Size = UDim2.new(1, -20, 0, 30)
	hintLabel.Font = Enum.Font.GothamBold
	hintLabel.TextScaled = true
	hintLabel.TextColor3 = Color3.new(1, 1, 1)
	hintLabel.Parent = panel
	infoLabel = Instance.new("TextLabel")
	infoLabel.BackgroundTransparency = 1
	infoLabel.Position = UDim2.new(0, 10, 0, 34)
	infoLabel.Size = UDim2.new(1, -20, 0, 24)
	infoLabel.Font = Enum.Font.GothamBlack
	infoLabel.TextScaled = true
	infoLabel.TextColor3 = ORANGE
	infoLabel.Parent = panel

	-- world guides (this client only)
	guides = Instance.new("Folder")
	guides.Name = "MachineGuide_Local"
	local function guidePart(name: string, size: Vector3, transparency: number): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 210, 60)
		p.Transparency = transparency
		p.Parent = guides
		return p
	end
	column = guidePart("TargetColumn", Vector3.new(60, 0.5, 0.5), 0.55)
	ring = guidePart("TargetRing", Vector3.new(0.2, 5, 5), 0.35)
	marker = guidePart("UnderMarker", Vector3.new(0.25, 2.4, 2.4), 0.2)
end

local UP = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's axis (X) to vertical

local function update()
	local m = rig
	if not m or not m.Parent then
		if m then
			leave()
		end
		return
	end
	local session = m:GetAttribute("Session")
	local target = m:GetAttribute("TargetPos")
	local hint = m:GetAttribute("Hint")
	-- what hangs under the controls: the hook (or its load) / the bucket
	local under: Vector3? = nil
	local load = m:FindFirstChild("CraneLoad") :: BasePart?
	if kind == "Crane" then
		local hook = m:FindFirstChild("HookBlock") :: BasePart?
		if load then
			under = load.Position - Vector3.new(0, load.Size.Y / 2, 0)
		elseif hook then
			under = hook.Position - Vector3.new(0, 0.9, 0)
		end
	else
		local bucket = m:FindFirstChild("Bucket") :: BasePart?
		if bucket then
			under = bucket.Position - Vector3.new(0, 0.8, 0)
		end
	end
	if typeof(session) ~= "string" then
		panel.Visible = true
		hintLabel.Text = if kind == "Crane" then "Tap the glowing roof outline to start a lift (the controls work any time)"
			else "Drive up to a glowing hole and tap it to start digging"
		infoLabel.Text = if kind == "Crane" then "A/D swing  -  W/S boom  -  R/F hook" else "R/F arm up / down"
		infoLabel.TextColor3 = Color3.fromRGB(170, 175, 185)
		guides.Parent = nil
		return
	end
	panel.Visible = true
	hintLabel.Text = if typeof(hint) == "string" then hint else ""
	if typeof(target) ~= "Vector3" or not under then
		guides.Parent = nil
		return
	end
	local err = Vector2.new((under :: Vector3).X - target.X, (under :: Vector3).Z - target.Z).Magnitude
	local tol = if kind == "Crane" then LIFT_TOL else DIG_TOL
	local lined = err < tol
	if kind == "Crane" and load then
		local dy = load.Position.Y - target.Y
		infoLabel.Text = if lined then ("LINED UP: lower it (%.1f studs to go)"):format(math.max(0, dy))
			else ("Load %.1f studs off the outline"):format(err)
	elseif kind == "Crane" then
		infoLabel.Text = if lined then "Over the section: lower the hook onto it" else ("Hook %.1f studs off the section"):format(err)
	else
		local done, need = m:GetAttribute("Scoops"), m:GetAttribute("ScoopsNeed")
		infoLabel.Text = ("Bucket %.1f studs off  -  scoops %s/%s"):format(err, tostring(done or 0), tostring(need or 3))
	end
	infoLabel.TextColor3 = if lined then GREEN else ORANGE
	-- world guides
	guides.Parent = workspace
	column.CFrame = CFrame.new(target + Vector3.new(0, 30, 0)) * UP
	ring.CFrame = CFrame.new(target + Vector3.new(0, 0.12, 0)) * UP
	ring.Color = if lined then GREEN else Color3.fromRGB(255, 210, 60)
	-- marker straight under the hook / load / bucket, on whatever is below it
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { m, guides }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	rp.FilterDescendantsInstances = ignore
	local from = (under :: Vector3) + Vector3.new(0, 0.5, 0)
	local hit = workspace:Raycast(from, Vector3.new(0, -200, 0), rp)
	local at = if hit then hit.Position else Vector3.new(from.X, 0, from.Z)
	if kind == "Excavator" then
		at = Vector3.new(from.X, math.max(at.Y, -1), from.Z)
	end
	marker.CFrame = CFrame.new(at + Vector3.new(0, 0.15, 0)) * UP
	marker.Color = if lined then GREEN else ORANGE
end

function Machine.Start()
	build()
	Settings.Changed.Event:Connect(function()
		if rig then
			layout()
		end
	end)
	local function hook(char: Model)
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		hum.Seated:Connect(function(active, seatPart)
			if active and seatPart then
				enter(seatPart)
			else
				leave()
			end
		end)
		hum.Died:Connect(leave)
	end
	if player.Character then
		task.spawn(hook, player.Character)
	end
	player.CharacterAdded:Connect(function(c)
		leave()
		hook(c)
	end)
	RunService.Heartbeat:Connect(function()
		if rig then
			send(false)
			update()
		end
	end)
end

return Machine
