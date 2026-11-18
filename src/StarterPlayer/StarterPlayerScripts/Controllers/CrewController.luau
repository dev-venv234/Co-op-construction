--!strict
-- Crew tools on screen (all big tap targets; the server validates everything in CrewService):
--  * QUICK JOIN: the server gives you the trade the crew needs most.
--  * PING: pick "Here" / "Need help" / "Bring lumber" / "Watch out"; the marker goes where your camera is looking
--    and the whole crew sees it for a few seconds (no typing needed).
--  * CREW: your crew with KICK buttons (a vote: most of the crew has to agree, the Foreman included) and LEAVE, and
--    every crew on the server (what it's building, which trades it needs) with JOIN, plus NEW CREW. (2026-11-17:
--    several crews per server; the server checks everything in CrewService.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Trades = require(ReplicatedStorage.Shared.Config.Trades)
local UI = require(script.Parent.UIController)

local Crew = {}

local player = Players.LocalPlayer
local DARK = Color3.fromRGB(30, 30, 34)
local PINGS = {
	{ id = "Here", text = "HERE", icon = "!", color = Color3.fromRGB(255, 205, 60) },
	{ id = "Help", text = "NEED HELP", icon = "?", color = Color3.fromRGB(90, 170, 255) },
	{ id = "Lumber", text = "BRING LUMBER", icon = "#", color = Color3.fromRGB(210, 160, 100) },
	{ id = "Danger", text = "WATCH OUT", icon = "X", color = Color3.fromRGB(240, 80, 70) },
}

local function button(text: string, color: Color3, size: UDim2, pos: UDim2, parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	Instance.new("UICorner").Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	return b
end

-- Where the camera is looking (center of the screen), or a spot in front of the player.
local function aimPoint(): Vector3?
	local cam = workspace.CurrentCamera
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not cam or not root then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c :: Instance }
	local ray = cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 250, params)
	if hit and (hit.Position - root.Position).Magnitude < 250 then
		return hit.Position
	end
	return root.Position + root.CFrame.LookVector * 15
end

local function showPing(d: { [string]: any })
	if typeof(d) ~= "table" or typeof(d.pos) ~= "Vector3" then
		return
	end
	local info = PINGS[1]
	for _, p in PINGS do
		if p.id == d.kind then
			info = p
		end
	end
	local anchor = Instance.new("Part")
	anchor.Name = "CrewPing"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = d.pos
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = info.color
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.2, 6, 6)
	ring.CFrame = CFrame.new(d.pos) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = anchor
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(150, 70)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 400
	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(1, 0, 0.55, 0)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBlack
	icon.TextScaled = true
	icon.TextColor3 = info.color
	icon.TextStrokeTransparency = 0.2
	icon.Text = info.icon .. " " .. info.text
	icon.Parent = bb
	local who = Instance.new("TextLabel")
	who.Position = UDim2.fromScale(0, 0.58)
	who.Size = UDim2.new(1, 0, 0.4, 0)
	who.BackgroundTransparency = 1
	who.Font = Enum.Font.GothamBold
	who.TextScaled = true
	who.TextColor3 = Color3.new(1, 1, 1)
	who.TextStrokeTransparency = 0.3
	who.Text = tostring(d.from) .. (if d.role then " (" .. tostring(d.role) .. ")" else "")
	who.Parent = bb
	bb.Parent = anchor
	anchor.Parent = workspace
	Debris:AddItem(anchor, 8)
	UI.Toast(("%s: %s"):format(tostring(d.from), info.text))
end

function Crew.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CrewTools"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Left column under the trade button
	local quick = button("QUICK JOIN", Color3.fromRGB(70, 160, 90), UDim2.fromOffset(150, 46), UDim2.new(0, 8, 0.5, -47), gui)
	quick.Activated:Connect(function()
		Net.Event("QuickJoin"):FireServer()
	end)
	local crewBtn = button("CREW", Color3.fromRGB(70, 90, 130), UDim2.fromOffset(150, 46), UDim2.new(0, 8, 0.5, 5), gui)

	-- PING on the right edge, with a pop-out of 4 presets
	local ping = button("PING", Color3.fromRGB(230, 150, 40), UDim2.fromOffset(96, 56), UDim2.new(1, -104, 0.42, 0), gui)
	local menu = Instance.new("Frame")
	menu.BackgroundTransparency = 1
	menu.Size = UDim2.fromOffset(170, 4 * 52)
	menu.Position = UDim2.new(1, -282, 0.42, -76)
	menu.Visible = false
	menu.Parent = gui
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.Parent = menu
	for _, info in PINGS do
		local b = button(info.icon .. " " .. info.text, DARK, UDim2.new(1, 0, 0, 46), UDim2.new(), menu)
		b.TextColor3 = info.color
		b.Activated:Connect(function()
			menu.Visible = false
			local at = aimPoint()
			if at then
				Net.Event("Ping"):FireServer(info.id, at)
			end
		end)
	end
	ping.Activated:Connect(function()
		menu.Visible = not menu.Visible
	end)
	Net.Event("PingShown").OnClientEvent:Connect(showPing)

	-- CREW panel: my crew (KICK votes, LEAVE) and every crew on the server (JOIN), plus NEW CREW.
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.86, 0)
	panel.BackgroundColor3 = DARK
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner").Parent = panel
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 560)
	limit.Parent = panel
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 12, 0, 8)
	title.Size = UDim2.new(1, -80, 0, 34)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "CREWS"
	title.Parent = panel
	local close = button("X", Color3.fromRGB(120, 50, 50), UDim2.fromOffset(48, 44), UDim2.new(1, -56, 0, 6), panel)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	local rows = Instance.new("ScrollingFrame")
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.new(0, 10, 0, 56)
	rows.Size = UDim2.new(1, -20, 1, -118)
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.CanvasSize = UDim2.new()
	rows.ScrollBarThickness = 6
	rows.Parent = panel
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 6)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = rows
	-- bottom bar: NEW CREW / LEAVE CREW
	local newBtn = button("NEW CREW", Color3.fromRGB(60, 140, 80), UDim2.new(0.5, -15, 0, 48), UDim2.new(0, 10, 1, -56), panel)
	newBtn.Activated:Connect(function()
		Net.Event("CrewAction"):FireServer("New")
	end)
	local leaveBtn = button("LEAVE CREW", Color3.fromRGB(150, 70, 50), UDim2.new(0.5, -15, 0, 48), UDim2.new(0.5, 5, 1, -56), panel)
	leaveBtn.Activated:Connect(function()
		Net.Event("CrewAction"):FireServer("Leave")
	end)

	local function roleOf(name: string): string?
		for role, names in UI.State.roles or {} do
			if table.find(names, name) then
				return role
			end
		end
		return nil
	end
	local order = 0
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
	local function row(height: number, color: Color3): Frame
		order += 1
		local r = Instance.new("Frame")
		r.LayoutOrder = order
		r.Size = UDim2.new(1, -8, 0, height)
		r.BackgroundColor3 = color
		r.Parent = rows
		Instance.new("UICorner").Parent = r
		return r
	end
	local function header(t: string)
		order += 1
		local h = text(rows, t, UDim2.new(), UDim2.new(1, -8, 0, 24), Enum.Font.GothamBlack, Color3.fromRGB(255, 205, 90))
		h.LayoutOrder = order
	end

	local function refresh()
		for _, c in rows:GetChildren() do
			if c:IsA("Frame") or c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		order = 0
		local myId = player:GetAttribute("CrewId")
		local myName = player:GetAttribute("CrewName")
		title.Text = if typeof(myName) == "string" then string.upper(myName) else "CREWS"
		leaveBtn.Visible = myId ~= nil

		-- my crew: members with KICK (a vote)
		if myId ~= nil then
			header("YOUR CREW  -  KICK starts a vote: most of the crew has to agree")
			for _, pl in Players:GetPlayers() do
				if pl:GetAttribute("CrewId") == myId then
					local r = row(48, Color3.fromRGB(45, 46, 54))
					local role = roleOf(pl.Name)
					text(r, pl.DisplayName .. "  -  " .. (role or "no trade") .. (if pl == player then " (you)" else ""),
						UDim2.new(0, 10, 0, 6), UDim2.new(1, -120, 1, -12), Enum.Font.GothamBold,
						if role and Trades.Info[role] then Trades.Info[role].Color else Color3.new(1, 1, 1))
					if pl ~= player then
						local kick = button("KICK", Color3.fromRGB(150, 50, 50), UDim2.fromOffset(96, 44), UDim2.new(1, -102, 0, 2), r)
						kick.Activated:Connect(function()
							Net.Event("KickVote"):FireServer(pl.Name)
						end)
					end
				end
			end
		end

		-- server standings (crew points: LeagueService)
		local league = (UI.Board or {}).league or {}
		local anyPoints = false
		for _, st in league do
			if (st.points or 0) > 0 then
				anyPoints = true
			end
		end
		if #league > 0 then
			header("SERVER STANDINGS  -  finish jobs and win races for crew points")
			for rank, st in league do
				local r = row(34, if st.id == myId then Color3.fromRGB(40, 70, 55) else Color3.fromRGB(40, 41, 48))
				local crown = if rank == 1 and anyPoints then "[#1] " else ("%d. "):format(rank)
				text(r, ("%s%s  -  %d pts  |  %d job%s%s%s"):format(crown, tostring(st.name), st.points or 0, st.jobs or 0,
					if (st.jobs or 0) == 1 then "" else "s", if st.best then "  |  best " .. tostring(st.best) else "",
					if (st.wins or 0) > 0 then ("  |  %d race win%s"):format(st.wins, if st.wins == 1 then "" else "s") else ""),
					UDim2.new(0, 10, 0, 5), UDim2.new(1, -20, 1, -10), Enum.Font.GothamBold,
					if rank == 1 and anyPoints then Color3.fromRGB(255, 210, 90) else Color3.new(1, 1, 1))
			end
		end

		-- every crew on the server
		local board = UI.Board or {}
		local crews = board.crews or {}
		header(("CREWS ON THIS SERVER (%d/%d)"):format(#crews, tonumber(board.maxCrews) or 6))
		if #crews == 0 then
			local r = row(40, Color3.fromRGB(40, 41, 48))
			text(r, "No crews yet: pick a trade or tap NEW CREW to start one", UDim2.new(0, 10, 0, 8), UDim2.new(1, -20, 1, -16),
				Enum.Font.Gotham, Color3.fromRGB(200, 205, 215))
		end
		for _, c in crews do
			local mine = c.id == myId
			local r = row(76, if mine then Color3.fromRGB(40, 70, 55) else Color3.fromRGB(45, 46, 54))
			text(r, ("%s  (%d/%d)%s"):format(tostring(c.name), c.count or 0, c.max or 6, if mine then "  - yours" else ""),
				UDim2.new(0, 10, 0, 4), UDim2.new(1, -124, 0, 24), Enum.Font.GothamBlack, Color3.new(1, 1, 1))
			local doing = if c.job then ("%s at %s: %s (%d/%d)"):format(tostring(c.job), tostring(c.lot), tostring(c.phase), c.done or 0, c.total or 0)
				else "At camp, picking a job"
			text(r, doing, UDim2.new(0, 10, 0, 30), UDim2.new(1, -124, 0, 18), Enum.Font.Gotham, Color3.fromRGB(205, 210, 220))
			local open = c.open or {}
			text(r, if #open > 0 then "Needs: " .. table.concat(open, ", ") else "Every trade taken",
				UDim2.new(0, 10, 0, 52), UDim2.new(1, -124, 0, 18), Enum.Font.GothamBold, Color3.fromRGB(255, 190, 90))
			if not mine then
				local full = (c.count or 0) >= (c.max or 6)
				local join = button(if full then "FULL" else "JOIN", if full then Color3.fromRGB(70, 74, 86) else Color3.fromRGB(60, 110, 190),
					UDim2.fromOffset(104, 56), UDim2.new(1, -112, 0, 10), r)
				join.AutoButtonColor = not full
				local id = c.id
				join.Activated:Connect(function()
					if not full then
						Net.Event("CrewAction"):FireServer("Join", id)
					end
				end)
			end
		end
	end
	crewBtn.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			refresh()
		end
	end)
	local function changed()
		quick.Visible = UI.MyRole() == nil or UI.State.active == true
		if panel.Visible then
			refresh()
		end
	end
	UI.StateChanged.Event:Connect(changed)
	UI.BoardChanged.Event:Connect(function()
		if panel.Visible then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("CrewId"):Connect(changed)
end

return Crew
