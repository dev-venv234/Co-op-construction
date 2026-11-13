--!strict
-- The guide: always tells you the next thing to do and points at it.
--  * A hint bar under the status bar ("Grab a Post from the pile, then bring it to the glowing outline").
--  * A glowing line from you to the target, an outline on it and a floating arrow with the distance.
--  * New players (no paycheck yet) get a short "How it works" card first. The GUIDE button turns it all on/off.
-- Display only: it reads the job state and prompt attributes; the server still checks every tap.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = require(script.Parent.UIController)

local Guide = {}

local player = Players.LocalPlayer
local prompts: { [ProximityPrompt]: boolean } = {}
local enabled = true

local hintLabel: TextLabel
local hintFrame: Frame
local beam: Beam
local fromAtt: Attachment
local toAtt: Attachment
local targetPart: Part
local highlight: Highlight
local arrow: BillboardGui
local arrowText: TextLabel
local edge: TextLabel -- screen-edge arrow when the target is off-screen

local GOLD = Color3.fromRGB(255, 205, 60)

---------------------------------------------------------------------------------------------------------------
-- Finding things
---------------------------------------------------------------------------------------------------------------

local function track(inst: Instance)
	if inst:IsA("ProximityPrompt") and not prompts[inst] then
		prompts[inst] = true
		inst.Destroying:Connect(function()
			prompts[inst] = nil
		end)
	end
end

local function root(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function posOf(pp: ProximityPrompt): Vector3?
	local p = pp.Parent
	if p and p:IsA("BasePart") then
		return p.Position
	elseif p and p:IsA("Attachment") then
		return p.WorldPosition
	end
	return nil
end

-- Nearest prompt that passes `ok`.
local function nearest(ok: (ProximityPrompt) -> boolean): ProximityPrompt?
	local r = root()
	local from = if r then r.Position else Vector3.zero
	local best, bestD = nil, math.huge
	for pp in prompts do
		if pp.Parent and ok(pp) then
			local pos = posOf(pp)
			if pos then
				local d = (pos - from).Magnitude
				if d < bestD then
					best, bestD = pp, d
				end
			end
		end
	end
	return best
end

local function seatModelName(): string?
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat then
		return nil
	end
	local m = seat:FindFirstAncestorOfClass("Model")
	return if m then m.Name else nil
end

local function isSlot(pp: ProximityPrompt): boolean
	return pp:GetAttribute("SlotId") ~= nil and pp:GetAttribute("Open") == true and pp.Enabled
end

---------------------------------------------------------------------------------------------------------------
-- What to do next
---------------------------------------------------------------------------------------------------------------

local function lower(s: any): string
	return string.lower(tostring(s))
end

local function objective(): (string, ProximityPrompt?)
	local role = UI.MyRole()
	local st = UI.State
	if not role then
		return "Tap Pick trade (left side) and choose your job: Foreman, Laborer, Operator or Electrician", nil
	end
	if not st.active then
		local btn = nearest(function(pp)
			return pp.Parent ~= nil and (pp.Parent :: Instance):GetAttribute("StartSite") ~= nil and pp.Enabled
		end)
		return "Walk to the JOB SITES board at the truck lot and tap a site button to start a job", btn
	end
	local phase = tostring(st.phase or "")
	local carrying = player:GetAttribute("Carrying")
	local seat = seatModelName()
	-- Joined while a crew was already out at the site (everyone starts at the RV park): ride out from the board.
	-- (While the truck is being loaded or driven there is work back in town, so this only shows after delivery.)
	if not seat and not carrying and not string.find(phase, "^Load the truck") and not string.find(phase, "^Drive to Site")
		and not string.find(phase, "^Unload") and phase ~= "Final inspection" and phase ~= "Finished" then
		local r = root()
		-- anything at the site (task outlines, or the material piles, which stay until the end)
		local slot = nearest(function(pp)
			return pp:GetAttribute("SlotId") ~= nil or pp:GetAttribute("PileItem") ~= nil
		end)
		local far = slot == nil or (r ~= nil and ((posOf(slot) :: Vector3) - r.Position).Magnitude > 250)
		if far then
			local btn = nearest(function(pp)
				return pp.Parent ~= nil and (pp.Parent :: Instance):GetAttribute("StartSite") == "Site_T" .. tostring(st.site)
			end)
			return ("The crew is at Site %s: tap the Site %s button on the JOB SITES board to ride out"):format(tostring(st.site), tostring(st.site)), btn
		end
	end
	-- Trades a bot is covering: don't send the player to do their work.
	local function botHas(r: any): boolean
		return typeof(r) == "string" and ((st.bots or {})[r] or 0) > 0 and r ~= role
	end

	if string.find(phase, "^Load the truck") then
		if carrying then
			return ("Put the %s on the truck: walk to the truck bed and tap Load truck"):format(lower(carrying)),
				nearest(function(pp)
					return pp:GetAttribute("LoadTruck") == true
				end)
		end
		return "Load the truck: drive it under the LOADING canopy at Crew Supply on Main St and stop. It loads itself",
			nearest(function(pp)
				return pp.Parent ~= nil and (pp.Parent :: Instance):GetAttribute("MaterialStack") ~= nil and pp.Enabled
			end)
	end
	if string.find(phase, "^Drive to Site") and not botHas("Operator") then
		if seat == "CrewTruck" then
			return phase .. ". Park on the glowing DELIVERY pad, then tap Unload", nearest(function(pp)
				return pp:GetAttribute("SlotId") == "deliver"
			end)
		end
		return "Get in the truck (tap Drive truck at the driver door) and drive it to the site", nearest(function(pp)
			return pp.Name == "BoardPrompt" and pp.ActionText == "Drive truck"
		end)
	end

	-- Building: my trade's open tasks first, then anything I'm allowed to help with.
	local function mine(pp: ProximityPrompt): boolean
		return isSlot(pp) and pp:GetAttribute("Role") == role
	end
	if carrying then
		local spot = nearest(function(pp)
			return isSlot(pp) and pp:GetAttribute("Kind") == "Place" and pp:GetAttribute("Item") == carrying
		end)
		if spot then
			return ("Bring the %s to the glowing outline and tap %s"):format(lower(carrying), spot.ActionText), spot
		end
		return ("Nothing needs a %s right now: tap DROP to put it down"):format(lower(carrying)), nil
	end
	local task = nearest(mine) or nearest(function(pp)
		return isSlot(pp) and not botHas(pp:GetAttribute("Role"))
	end)
	if not task then
		if phase == "Finished" then
			return "Job done! Your pay is on the way", nil
		elseif phase == "Final inspection" then
			return "The inspector is checking the house: stand back and watch", nil
		end
		return ("Nothing for the %s right now. Next up: %s"):format(role, phase), nil
	end
	local kind = task:GetAttribute("Kind")
	local item = task:GetAttribute("Item")
	local machine = task:GetAttribute("Equipment")
	local who = if task:GetAttribute("Role") == role then "" else ("(helping the %s) "):format(tostring(task:GetAttribute("Role")))
	if kind == "Place" and item then
		return ("%sGrab a %s from the %s pile, then bring it to the glowing outline"):format(who, lower(item), lower(item)),
			nearest(function(pp)
				return pp:GetAttribute("PileItem") == item
			end) or task
	end
	if machine then
		-- the crane arrives on its wheels: drive it onto its pad first
		local crane: Instance? = nil
		if machine == "Crane" then
			for _, site in workspace:GetChildren() do
				if string.sub(site.Name, 1, 8) == "JobSite_" and site:FindFirstChild("Crane") then
					crane = site:FindFirstChild("Crane")
				end
			end
		end
		if crane and crane:GetAttribute("Mode") ~= "set" then
			if seat == "Crane" then
				return ("%sDrive the crane onto the glowing CRANE PAD and stop: it sets itself up"):format(who),
					nearest(function(pp)
						return pp:GetAttribute("CranePad") == true
					end)
			end
			return ("%sGet the crane: tap Drive crane at its front cab"):format(who), nearest(function(pp)
				return pp.Name == "BoardPrompt" and pp.ActionText == "Drive crane"
			end)
		end
		local inIt = seat ~= nil and string.find(lower(seat), lower(machine), 1, true) ~= nil
		if not inIt then
			return ("%sGet in the %s: tap Operate %s at its cab"):format(who, lower(machine), lower(machine)),
				nearest(function(pp)
					return pp:GetAttribute("Machine") == machine
				end)
		end
		if machine == "Excavator" then
			return ("%sDrive up so the bucket reaches the glowing hole, tap %s, then ARM DOWN / ARM UP to scoop it 3 times"):format(
				who, task.ActionText), task
		end
		return ("%sTap %s, hook the roof section, then set it on the glowing outline (SWING / BOOM / HOOK)"):format(
			who, task.ActionText), task
	end
	local after = if kind == "Timing" then ", then tap TAP when the needle is in the green"
		elseif kind == "Connect" then ", then turn the tiles to connect the wire"
		else ""
	return ("%sGo to the glowing outline and tap %s%s"):format(who, task.ActionText, after), task
end

---------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Guide"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 2
	gui.Parent = player:WaitForChild("PlayerGui")

	hintFrame = Instance.new("Frame")
	hintFrame.AnchorPoint = Vector2.new(0.5, 0)
	hintFrame.Position = UDim2.new(0.5, 0, 0, 48)
	hintFrame.Size = UDim2.new(0.7, 0, 0, 44)
	hintFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	hintFrame.BackgroundTransparency = 0.15
	hintFrame.Parent = gui
	Instance.new("UICorner").Parent = hintFrame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = hintFrame
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(640, 44)
	size.Parent = hintFrame
	hintLabel = Instance.new("TextLabel")
	hintLabel.BackgroundTransparency = 1
	hintLabel.Position = UDim2.new(0, 10, 0, 4)
	hintLabel.Size = UDim2.new(1, -20, 1, -8)
	hintLabel.Font = Enum.Font.GothamBold
	hintLabel.TextScaled = true
	hintLabel.TextColor3 = Color3.new(1, 1, 1)
	hintLabel.Text = ""
	hintLabel.Parent = hintFrame

	local toggle = Instance.new("TextButton")
	toggle.Name = "GuideButton"
	toggle.AnchorPoint = Vector2.new(1, 0)
	toggle.Position = UDim2.new(1, -8, 0, 4)
	toggle.Size = UDim2.fromOffset(96, 44)
	toggle.BackgroundColor3 = GOLD
	toggle.Font = Enum.Font.GothamBlack
	toggle.TextScaled = true
	toggle.TextColor3 = Color3.fromRGB(30, 30, 34)
	toggle.Text = "GUIDE ON"
	toggle.Parent = gui
	Instance.new("UICorner").Parent = toggle
	toggle.Activated:Connect(function()
		enabled = not enabled
		toggle.Text = if enabled then "GUIDE ON" else "GUIDE OFF"
		toggle.BackgroundColor3 = if enabled then GOLD else Color3.fromRGB(90, 90, 96)
	end)

	-- World pointer: a client-only anchor part at the target, a beam from the player, an outline and an arrow.
	targetPart = Instance.new("Part")
	targetPart.Name = "GuideTarget"
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.CanTouch = false
	targetPart.Transparency = 1
	targetPart.Size = Vector3.new(0.2, 0.2, 0.2)
	toAtt = Instance.new("Attachment")
	toAtt.Parent = targetPart
	fromAtt = Instance.new("Attachment")
	beam = Instance.new("Beam")
	beam.Attachment0 = fromAtt
	beam.Attachment1 = toAtt
	beam.Color = ColorSequence.new(GOLD)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.15, 0.35), NumberSequenceKeypoint.new(1, 0.2) })
	beam.Width0 = 0.35
	beam.Width1 = 0.35
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Segments = 20
	beam.Parent = targetPart

	highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.8
	highlight.FillColor = GOLD
	highlight.OutlineColor = GOLD
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = gui

	arrow = Instance.new("BillboardGui")
	arrow.Size = UDim2.fromOffset(90, 60)
	arrow.StudsOffset = Vector3.new(0, 4, 0)
	arrow.AlwaysOnTop = true
	arrow.Adornee = targetPart
	arrowText = Instance.new("TextLabel")
	arrowText.Size = UDim2.fromScale(1, 1)
	arrowText.BackgroundTransparency = 1
	arrowText.Font = Enum.Font.GothamBlack
	arrowText.TextScaled = true
	arrowText.TextColor3 = GOLD
	arrowText.TextStrokeTransparency = 0.3
	arrowText.Parent = arrow
	arrow.Parent = gui

	edge = Instance.new("TextLabel")
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Size = UDim2.fromOffset(56, 56)
	edge.BackgroundTransparency = 1
	edge.Font = Enum.Font.GothamBlack
	edge.TextScaled = true
	edge.TextColor3 = GOLD
	edge.TextStrokeTransparency = 0.2
	edge.Text = ">"
	edge.Visible = false
	edge.Parent = gui
end

local function hidePointer()
	targetPart.Parent = nil
	highlight.Adornee = nil
	arrow.Enabled = false
	edge.Visible = false
end

-- Points the edge arrow at an off-screen target (turn around / look left / right).
local function updateEdge(pos: Vector3)
	local cam = workspace.CurrentCamera
	if not cam then
		edge.Visible = false
		return
	end
	local vp = cam.ViewportSize
	local sp, onScreen = cam:WorldToViewportPoint(pos)
	if onScreen and sp.Z > 0 then
		edge.Visible = false
		return
	end
	-- Direction to the target in camera space, flattened to the screen.
	local rel = cam.CFrame:PointToObjectSpace(pos)
	local dir = Vector2.new(rel.X, -rel.Y)
	if dir.Magnitude < 0.01 then
		dir = Vector2.new(0, 1)
	end
	dir = dir.Unit
	local center = vp / 2
	local margin = 50
	local sx = if dir.X ~= 0 then (center.X - margin) / math.abs(dir.X) else math.huge
	local sy = if dir.Y ~= 0 then (center.Y - margin) / math.abs(dir.Y) else math.huge
	local at = center + dir * math.min(sx, sy)
	edge.Position = UDim2.fromOffset(at.X, at.Y)
	edge.Rotation = math.deg(math.atan2(dir.Y, dir.X))
	edge.Visible = true
end

local function update()
	if not enabled then
		hintFrame.Visible = false
		hidePointer()
		return
	end
	local ok, text, target = pcall(objective)
	if not ok then
		return
	end
	hintFrame.Visible = true
	hintLabel.Text = text :: string
	local pos = target and posOf(target)
	local r = root()
	if not pos or not r then
		hidePointer()
		return
	end
	targetPart.Position = pos
	targetPart.Parent = workspace
	fromAtt.Parent = r
	local part = target and target.Parent
	highlight.Adornee = if part and part:IsA("BasePart") then part else nil
	arrow.Enabled = true
	updateEdge(pos)
	arrowText.Text = ("v\n%dm"):format(math.floor((pos - r.Position).Magnitude / 3.5))
end

-- First-time card: four lines, one big button.
local function intro()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HowItWorks"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.8, 0, 0.7, 0)
	panel.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 420)
	limit.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = panel
	local lines = {
		{ "HOW IT WORKS", 0.13, GOLD },
		{ "1. Pick a trade. Each one has its own jobs on the site.", 0.11 },
		{ "2. Follow the yellow line and the hint at the top. It always shows your next step.", 0.11 },
		{ "3. Glowing blue outlines are tasks: bring materials, tap in the green, connect wires, run machines.", 0.13 },
		{ "4. Finish before the clock runs out. Better work = more pay.", 0.11 },
	}
	for i, l in lines do
		local t = Instance.new("TextLabel")
		t.LayoutOrder = i
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, l[2] :: number, 0)
		t.Font = if i == 1 then Enum.Font.GothamBlack else Enum.Font.GothamBold
		t.TextScaled = true
		t.TextWrapped = true
		t.TextColor3 = (l[3] :: Color3?) or Color3.new(1, 1, 1)
		t.Text = l[1] :: string
		t.Parent = panel
	end
	local ok = Instance.new("TextButton")
	ok.LayoutOrder = 10
	ok.Size = UDim2.new(0.6, 0, 0, 56)
	ok.BackgroundColor3 = Color3.fromRGB(240, 140, 30)
	ok.Font = Enum.Font.GothamBlack
	ok.TextScaled = true
	ok.TextColor3 = Color3.new(1, 1, 1)
	ok.Text = "GOT IT"
	ok.Parent = panel
	Instance.new("UICorner").Parent = ok
	ok.Activated:Connect(function()
		gui:Destroy()
	end)
end

function Guide.Start()
	build()
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	workspace.DescendantAdded:Connect(track)
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		if t >= 0.3 then
			t = 0
			update()
		end
	end)
	task.delay(1, function()
		if player:GetAttribute("RVUnlocked") ~= true then
			intro()
		end
	end)
end

return Guide
