--!strict
-- COMPANY button (left column, under CREW) and panel, owner request 2026-11-12:
--  * MY COMPANY: start one (type a name) when you have a crew, or see yours: points, title, rank, members (the owner
--    can remove), join requests to accept or decline, players here to invite, leave.
--  * FIND: recently active companies with room; ASK TO JOIN sends a request a member has to accept.
--  * TOP 20: the leaderboard across all servers (also on the board at the RV park).
--  * An invite from someone in this server pops up with JOIN / NO.
--  * Until the player is in a company the button says TEAM UP with a gold outline.
-- Display only: every button sends a request (Company remote) that CompanyService checks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local CompanyController = {}

local player = Players.LocalPlayer
local remote: RemoteEvent
local panel: Frame
local content: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local popup: Frame
local openBtn: TextButton
local openStroke: UIStroke
local tab = "Mine"
local mine: { [string]: any } = {}
local boardTop: { any } = {}
local findList: { any } = {}
local findRequested = ""
local leaveArmed = false

local DARK = Color3.fromRGB(28, 30, 36)
local ROW = Color3.fromRGB(44, 47, 56)
local GOLD = Color3.fromRGB(255, 200, 60)
local GREEN = Color3.fromRGB(60, 150, 80)
local RED = Color3.fromRGB(160, 60, 55)
local BLUE = Color3.fromRGB(70, 90, 140)
local PURPLE = Color3.fromRGB(110, 80, 150)

local function corner(g: GuiObject)
	Instance.new("UICorner").Parent = g
end

local function text(t: string, size: UDim2, parent: Instance, color: Color3?, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Font = if bold then Enum.Font.GothamBlack else Enum.Font.GothamBold
	l.TextScaled = true
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = t
	l.Parent = parent
	return l
end

local function button(t: string, color: Color3, size: UDim2, parent: Instance, onTap: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBlack
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = t
	b.Parent = parent
	corner(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	b.Activated:Connect(onTap)
	return b
end

local order = 0
local function line(height: number?): Frame
	order += 1
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, 0, 0, height or 48)
	f.BackgroundTransparency = 1
	f.Parent = content
	return f
end

-- A row: label on the left, up to two buttons on the right.
local function row(label: string, buttons: { { string | Color3 | () -> () } }?, color: Color3?): Frame
	local f = line(48)
	f.BackgroundColor3 = ROW
	f.BackgroundTransparency = 0
	corner(f)
	local n = if buttons then #buttons else 0
	text(label, UDim2.new(1, -(n * 104) - 16, 0, 28), f, color).Position = UDim2.new(0, 10, 0, 10)
	for i, spec in buttons or {} do
		local b = button(spec[1] :: string, spec[2] :: Color3, UDim2.fromOffset(98, 44), f, spec[3] :: () -> ())
		b.Position = UDim2.new(1, -(n - i + 1) * 104, 0, 2)
	end
	return f
end

local function heading(t: string)
	local f = line(30)
	text(t, UDim2.new(1, 0, 1, 0), f, GOLD, true)
end

local function note(t: string)
	local f = line(26)
	text(t, UDim2.new(1, 0, 1, 0), f, Color3.fromRGB(180, 185, 195))
end

local function clear()
	for _, c in content:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	order = 0
end

local render: () -> ()

local function send(...: any)
	remote:FireServer(...)
end

local function renderMine()
	local c = mine.company
	if not c then
		heading("YOU'RE NOT IN A COMPANY YET")
		note("Got a crew? Start a company and invite them:")
		local f = line(50)
		local box = Instance.new("TextBox")
		box.Size = UDim2.new(1, -170, 0, 46)
		box.Position = UDim2.new(0, 0, 0, 2)
		box.BackgroundColor3 = ROW
		box.TextColor3 = Color3.new(1, 1, 1)
		box.PlaceholderText = "Company name (3-24 letters)"
		box.PlaceholderColor3 = Color3.fromRGB(150, 155, 165)
		box.Font = Enum.Font.GothamBold
		box.TextScaled = true
		box.ClearTextOnFocus = false
		box.Text = ""
		box.Parent = f
		corner(box)
		button("START", GREEN, UDim2.new(0, 160, 0, 46), f, function()
			send("Create", box.Text)
		end).Position = UDim2.new(1, -160, 0, 2)
		note("No crew? Ask to join a company:")
		local g = line(50)
		button("FIND A COMPANY", PURPLE, UDim2.new(1, 0, 0, 46), g, function()
			tab = "Find"
			send("Find")
			render()
		end)
		if mine.request then
			heading("WAITING")
			row(("Asked to join %s"):format(tostring(mine.request.Name)), { { "CANCEL", RED, function()
				send("CancelRequest")
			end } })
		end
		return
	end
	local head = line(40)
	text(tostring(c.Name), UDim2.new(1, 0, 1, 0), head, GOLD, true)
	note(("%s  -  %d points  -  %d jobs  -  %s"):format(tostring(c.Title), c.Score or 0, c.Jobs or 0,
		if c.Rank then ("#%d on the leaderboard"):format(c.Rank) else "not in the top 20 yet"))
	heading(("MEMBERS (%d/%d)"):format(#(c.Members or {}), mine.max or 12))
	for _, m in c.Members or {} do
		local label = ("%s%s  -  %d pts%s"):format(if m.Owner then "* " else "", tostring(m.Name), m.Points or 0, if m.Online then "  (here)" else "")
		local btns = nil
		if c.IsOwner and not m.Owner then
			btns = { { "REMOVE", RED, function()
				send("Kick", m.Uid)
			end } }
		end
		row(label, btns)
	end
	if #(c.Requests or {}) > 0 then
		heading("WANTS TO JOIN")
		for _, r in c.Requests do
			row(tostring(r.Name), {
				{ "ACCEPT", GREEN, function()
					send("Answer", r.Uid, true)
				end },
				{ "NO", RED, function()
					send("Answer", r.Uid, false)
				end },
			})
		end
	end
	heading("INVITE PLAYERS HERE")
	if #(c.Invitable or {}) == 0 then
		note("Everyone in this server is already in a company.")
	end
	for _, name in c.Invitable or {} do
		row(tostring(name), { { "INVITE", BLUE, function()
			send("Invite", name)
		end } })
	end
	local f = line(52)
	local leaveBtn
	leaveBtn = button(if leaveArmed then "TAP AGAIN TO LEAVE" else "LEAVE COMPANY", RED, UDim2.new(1, 0, 0, 46), f, function()
		if leaveArmed then
			leaveArmed = false
			send("Leave")
		else
			leaveArmed = true
			leaveBtn.Text = "TAP AGAIN TO LEAVE"
			task.delay(4, function()
				leaveArmed = false
				if leaveBtn.Parent then
					leaveBtn.Text = "LEAVE COMPANY"
				end
			end)
		end
	end)
end

local function renderFind()
	heading("COMPANIES LOOKING FOR MEMBERS")
	if mine.company then
		note(("You're in %s. Leave it first to join another."):format(tostring(mine.company.Name)))
	end
	local f = line(50)
	button("REFRESH", BLUE, UDim2.new(1, 0, 0, 46), f, function()
		send("Find")
	end)
	if #findList == 0 then
		note("No companies with room right now: start your own in MY COMPANY!")
	end
	for _, e in findList do
		local label = ("%s%s  -  %d/12  -  %d pts"):format(if e.Rank then ("#%d "):format(e.Rank) else "", tostring(e.Name), e.Members or 0, e.Score or 0)
		local btns = nil
		if not mine.company then
			if findRequested == e.Id then
				btns = { { "ASKED", Color3.fromRGB(90, 90, 96), function() end } }
			else
				btns = { { "ASK TO JOIN", GREEN, function()
					send("Request", e.Id)
					findRequested = e.Id
					render()
				end } }
			end
		end
		row(label, btns)
	end
end

local function renderTop()
	heading("TOP 20 COMPANIES (ALL SERVERS)")
	if #boardTop == 0 then
		note("No companies yet. Start one and finish jobs to get on the board!")
	end
	local myId = mine.company and mine.company.Id
	for i, e in boardTop do
		row(("%d. %s  -  %d pts  -  %s"):format(i, tostring(e.Name), e.Score or 0, tostring(e.Title)), nil,
			if e.Id == myId then GOLD elseif i <= 3 then Color3.new(1, 1, 1) else Color3.fromRGB(200, 205, 215))
	end
	note("Points: base pay / 10 x grade (A+ 1.5x) for every member on the job.")
end

render = function()
	for name, b in tabButtons do
		b.BackgroundColor3 = if name == tab then Color3.fromRGB(240, 150, 40) else Color3.fromRGB(70, 74, 86)
	end
	clear()
	if tab == "Mine" then
		renderMine()
	elseif tab == "Find" then
		renderFind()
	else
		renderTop()
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CompanyTools"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	local open = button("COMPANY", PURPLE, UDim2.fromOffset(150, 46), gui, function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			send("Panel")
			render()
		end
	end)
	open.Name = "CompanyButton"
	open.Position = UDim2.new(0, 8, 0.5, 57) -- left column: Pick trade, QUICK JOIN, CREW, COMPANY
	openBtn = open
	-- gold outline + "TEAM UP" while the player has no company, so newcomers find it (refreshButton)
	openStroke = Instance.new("UIStroke")
	openStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	openStroke.Color = GOLD
	openStroke.Thickness = 3
	openStroke.Parent = open

	local top = Instance.new("ScreenGui")
	top.Name = "CompanyPanel"
	top.ResetOnSpawn = false
	top.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	top.DisplayOrder = 21
	top.Parent = player.PlayerGui

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.92, 0.92)
	panel.BackgroundColor3 = DARK
	panel.Visible = false
	panel.Parent = top
	corner(panel)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 660)
	limit.Parent = panel

	text("COMPANY", UDim2.new(1, -80, 0, 34), panel, Color3.new(1, 1, 1), true).Position = UDim2.new(0, 14, 0, 8)
	button("X", RED, UDim2.fromOffset(52, 46), panel, function()
		panel.Visible = false
	end).Position = UDim2.new(1, -60, 0, 6)

	local tabs = Instance.new("Frame")
	tabs.BackgroundTransparency = 1
	tabs.Position = UDim2.new(0, 12, 0, 56)
	tabs.Size = UDim2.new(1, -24, 0, 46)
	tabs.Parent = panel
	for i, spec in { { "Mine", "MY COMPANY" }, { "Find", "FIND" }, { "Top", "TOP 20" } } do
		local b = button(spec[2], Color3.fromRGB(70, 74, 86), UDim2.new(1 / 3, -6, 1, 0), tabs, function()
			tab = spec[1]
			if tab == "Find" then
				send("Find")
			end
			render()
		end)
		b.Position = UDim2.new((i - 1) / 3, 3, 0, 0)
		tabButtons[spec[1]] = b
	end

	content = Instance.new("ScrollingFrame")
	content.Position = UDim2.new(0, 12, 0, 110)
	content.Size = UDim2.new(1, -24, 1, -122)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content

	-- invite popup
	popup = Instance.new("Frame")
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Position = UDim2.new(0.5, 0, 0, 100)
	popup.Size = UDim2.new(0.8, 0, 0, 120)
	popup.BackgroundColor3 = DARK
	popup.Visible = false
	popup.Parent = top
	corner(popup)
	local pl = Instance.new("UISizeConstraint")
	pl.MaxSize = Vector2.new(460, 120)
	pl.Parent = popup
	local msg = text("", UDim2.new(1, -20, 0, 50), popup)
	msg.Name = "Message"
	msg.Position = UDim2.new(0, 10, 0, 8)
	msg.TextXAlignment = Enum.TextXAlignment.Center
	local yes = button("JOIN", GREEN, UDim2.new(0.5, -15, 0, 46), popup, function() end)
	yes.Name = "Yes"
	yes.Position = UDim2.new(0, 10, 0, 64)
	local no = button("NO", RED, UDim2.new(0.5, -15, 0, 46), popup, function() end)
	no.Name = "No"
	no.Position = UDim2.new(0.5, 5, 0, 64)
end

local inviteId: string? = nil

local function refreshButton()
	local has = mine.company ~= nil
	openBtn.Text = if has then "COMPANY" else "TEAM UP"
	openStroke.Enabled = not has
end

local function onData(d: any)
	if typeof(d) ~= "table" then
		return
	end
	if d.kind == "Mine" then
		mine = d
		refreshButton()
		if d.company then
			findRequested = ""
		elseif d.request then
			findRequested = d.request.Id
		end
		if panel.Visible and tab == "Mine" then
			render()
		end
	elseif d.kind == "Board" then
		boardTop = d.top or {}
		if panel.Visible and tab == "Top" then
			render()
		end
	elseif d.kind == "Find" then
		findList = d.list or {}
		findRequested = if typeof(d.requested) == "string" then d.requested else findRequested
		if panel.Visible and tab == "Find" then
			render()
		end
	elseif d.kind == "Invite" then
		inviteId = d.companyId
		local msg = popup:FindFirstChild("Message") :: TextLabel
		msg.Text = ("%s invites you to join %s"):format(tostring(d.from), tostring(d.company))
		popup.Visible = true
		task.delay(60, function()
			if inviteId == d.companyId then
				popup.Visible = false
			end
		end)
	end
end

function CompanyController.Start()
	remote = Net.Event("Company")
	build()
	local yes = popup:FindFirstChild("Yes") :: TextButton
	local no = popup:FindFirstChild("No") :: TextButton
	yes.Activated:Connect(function()
		if inviteId then
			send("RespondInvite", inviteId, true)
		end
		popup.Visible = false
	end)
	no.Activated:Connect(function()
		if inviteId then
			send("RespondInvite", inviteId, false)
		end
		popup.Visible = false
	end)
	Net.Event("CompanyData").OnClientEvent:Connect(onData)
end

return CompanyController
