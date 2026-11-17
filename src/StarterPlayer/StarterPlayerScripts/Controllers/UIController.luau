--!strict
-- HUD (job timer/progress), trade picker, Drop button, toasts and the payout screen (the Robux store is
-- StoreController).
-- Touch first: every button is >= 48 px tall, placed mid-screen so it never covers the thumbstick or jump.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local Trades = require(ReplicatedStorage.Shared.Config.Trades)
local Input = require(script.Parent.InputController)

local UI = {}
UI.State = { active = false, roles = {} } :: { [string]: any }
UI.StateChanged = Instance.new("BindableEvent")

local player = Players.LocalPlayer
local gui: ScreenGui
local toastList: Frame
local picker: Frame
local payoutPanel: Frame

local DARK = Color3.fromRGB(25, 27, 32)
local WHITE = Color3.new(1, 1, 1)

local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, r or 10) })
end

local function label(text: string, props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = text,
	}
	for k, v in props do
		base[k] = v
	end
	return new("TextLabel", base)
end

local function button(text: string, color: Color3, props: { [string]: any }): TextButton
	local base = {
		BackgroundColor3 = color,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = text,
		AutoButtonColor = true,
	}
	for k, v in props do
		base[k] = v
	end
	local b = new("TextButton", base, { corner(), new("UIPadding", {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
	}) })
	return b
end

function UI.MyRole(): string?
	for role, names in UI.State.roles or {} do
		if table.find(names, player.Name) then
			return role
		end
	end
	return nil
end

-- "Laborer  Lv 3" (levels are display copies set by the server)
local function tradeText(): string
	local role = UI.MyRole()
	if not role then
		return "Pick trade"
	end
	local level = player:GetAttribute("Level_" .. role)
	return if typeof(level) == "number" then ("%s  Lv %d"):format(role, level) else role
end

function UI.Toast(text: string)
	local t = label(text, {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = DARK,
		Parent = toastList,
	})
	corner(8).Parent = t
	local kids = toastList:GetChildren()
	local count = 0
	for _, k in kids do
		if k:IsA("TextLabel") then
			count += 1
		end
	end
	if count > 3 then
		for _, k in kids do
			if k:IsA("TextLabel") and k ~= t then
				k:Destroy()
				break
			end
		end
	end
	task.delay(3, function()
		if t.Parent then
			t:Destroy()
		end
	end)
end

local function buildPicker()
	picker = new("Frame", {
		Name = "TradePicker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.8),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, {
		corner(14),
		new("UISizeConstraint", { MaxSize = Vector2.new(560, 380) }),
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
	})
	label("Pick your trade", { Size = UDim2.new(1, 0, 0.14, 0), ZIndex = 21, Parent = picker })
	local list = new("Frame", {
		Position = UDim2.fromScale(0, 0.17),
		Size = UDim2.fromScale(1, 0.83),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = picker,
	}, {
		-- 6 trades: two columns of three, so every button stays well over 44 px tall on a phone
		new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 1 / 3, -6), CellPadding = UDim2.fromOffset(10, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	for i, id in Trades.Order do
		local info = Trades.Info[id]
		local b = button("", info.Color, {
			Name = id,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 1 / #Trades.Order - 0.03, 0),
			TextScaled = false,
			ZIndex = 22,
			Parent = list,
		})
		b:SetAttribute("Role", id)
		label(id, { Name = "Title", Size = UDim2.fromScale(1, 0.45), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = b })
		label(info.Description, {
			Name = "Desc",
			Position = UDim2.fromScale(0, 0.47),
			Size = UDim2.fromScale(1, 0.53),
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
			Parent = b,
		})
		b.Activated:Connect(function()
			Net.Event("PickRole"):FireServer(id)
			picker.Visible = false
		end)
	end
end

local function refreshPicker()
	for _, b in picker:GetDescendants() do
		if b:IsA("TextButton") then
			local role = b:GetAttribute("Role")
			local names = (UI.State.roles or {})[role] or {}
			local info = Trades.Info[role]
			local title = b:FindFirstChild("Title") :: TextLabel
			local full = #names >= info.Max and not table.find(names, player.Name)
			local botCount = (UI.State.bots or {})[role] or 0
			title.Text = role .. (if #names > 0 then "  (" .. table.concat(names, ", ") .. ")"
				elseif botCount > 0 then "  (bot - pick to take over)"
				else "  (open)")
			b.BackgroundColor3 = if full then Color3.fromRGB(70, 70, 75) else info.Color
		end
	end
end

local function buildPayout()
	payoutPanel = new("Frame", {
		Name = "Payout",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.8, 0.7),
		BackgroundColor3 = DARK,
		Visible = false,
		ZIndex = 30,
		Parent = gui,
	}, {
		corner(14),
		new("UISizeConstraint", { MaxSize = Vector2.new(460, 320) }),
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }),
	})
	label("", { Name = "Title", Size = UDim2.fromScale(1, 0.2), ZIndex = 31, Parent = payoutPanel })
	label("", {
		Name = "Body",
		Position = UDim2.fromScale(0, 0.22),
		Size = UDim2.fromScale(1, 0.5),
		Font = Enum.Font.Gotham,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 31,
		Parent = payoutPanel,
	})
	local ok = button("OK", Color3.fromRGB(60, 160, 90), {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(0.5, 0, 0, 52),
		ZIndex = 32,
		Parent = payoutPanel,
	})
	ok.Activated:Connect(function()
		payoutPanel.Visible = false
	end)
end

local function showPayout(d: { [string]: any })
	local title = payoutPanel:FindFirstChild("Title") :: TextLabel
	local body = payoutPanel:FindFirstChild("Body") :: TextLabel
	if d.success then
		title.Text = ("%s DONE - Grade %s"):format(string.upper(tostring(d.job)), tostring(d.grade))
		local lines = {
			("Base pay: $%d"):format(d.base or 0),
			("Quality: %d%% accuracy -> x%.2f"):format(math.floor((d.accuracy or 0) * 100 + 0.5), d.quality or 1),
			if d.early then "Finished early: +25%" else "No early bonus",
			("Your tasks: %d"):format(d.tasks or 0),
		}
		-- a paycheck is scaled by the share of the job you did (or by time, if you joined late)
		if typeof(d.share) == "number" and d.share < 1 and (d.tasks or 0) > 0 then
			local pct = math.floor(d.share * 100 + 0.5)
			table.insert(lines, if d.shareWhy == "late" then ("Your share: %d%% (you joined this job late)"):format(pct)
				else ("Your share: %d%% (%d of %d tasks for full pay)"):format(pct, d.tasks or 0, d.needTasks or 0))
		end
		if (d.collapsed or 0) > 0 then
			table.insert(lines, ("Collapse: %d piece%s fell%s"):format(d.collapsed, if d.collapsed == 1 then "" else "s",
				if (d.damage or 0) > 0 then (" - your work: -$%d"):format(d.damage) else ""))
		end
		if (d.finesCount or 0) > 0 then
			table.insert(lines, ("Inspector fines: -$%d (%d unfixed)"):format(d.fines or 0, d.finesCount))
		end
		if (d.passBonus or 0) > 0 then
			table.insert(lines, ("2x Pay pass: +$%d"):format(d.passBonus))
		end
		table.insert(lines, ("YOU EARNED: $%d"):format(d.pay or 0))
		if d.note then
			table.insert(lines, d.note)
		end
		body.Text = table.concat(lines, "\n")
		title.TextColor3 = Color3.fromRGB(120, 230, 140)
	else
		title.Text = "JOB FAILED"
		title.TextColor3 = Color3.fromRGB(240, 110, 100)
		body.Text = tostring(d.note or "")
	end
	payoutPanel.Visible = true
end

function UI.Start()
	gui = new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- Top status bar
	local top = new("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(0.6, 0, 0, 40),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.2,
		Parent = gui,
	}, { corner(10), new("UISizeConstraint", { MaxSize = Vector2.new(560, 40) }) })
	local status = label("", {
		Size = UDim2.fromScale(1, 1),
		Parent = top,
	})
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = status })

	toastList = new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100), -- below the guide's hint bar
		Size = UDim2.new(0.6, 0, 0, 140),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		new("UISizeConstraint", { MaxSize = Vector2.new(520, 140) }),
		new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	-- Trade button (left, mid-height: above the thumbstick)
	local tradeBtn = button("Pick trade", Color3.fromRGB(70, 90, 140), {
		Name = "TradeButton",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, -78), -- left column, centered (QUICK JOIN, CREW, COMPANY below)
		Size = UDim2.new(0, 150, 0, 50),
		Parent = gui,
	})
	tradeBtn.Activated:Connect(function()
		picker.Visible = not picker.Visible
	end)

	-- Awake badge (coffee buff), just above the trade button
	local awakeBadge = label("AWAKE  +speed", {
		Name = "AwakeBadge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.38, -44),
		Size = UDim2.new(0, 150, 0, 30),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(120, 75, 40),
		Visible = false,
		Parent = gui,
	})
	corner(8).Parent = awakeBadge
	local function onAwake()
		awakeBadge.Visible = player:GetAttribute("Awake") == true
	end
	player:GetAttributeChangedSignal("Awake"):Connect(onAwake)
	onAwake()
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 6) == "Level_" then
			tradeBtn.Text = tradeText()
		end
	end)

	-- Drop button (right, mid-height: above the jump button). Only shown while carrying.
	local dropBtn = button("Drop", Color3.fromRGB(170, 80, 60), {
		Name = "DropButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.38, 0),
		Size = UDim2.new(0, 150, 0, 50),
		Visible = false,
		Parent = gui,
	})
	local function drop()
		Net.Event("DropItem"):FireServer()
	end
	dropBtn.Activated:Connect(drop)
	local function onCarry()
		local item = player:GetAttribute("Carrying")
		dropBtn.Visible = item ~= nil
		dropBtn.Text = if item then "Drop " .. tostring(item) else "Drop"
		if item then
			Input.BindTap("CoopDrop", drop, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
		else
			Input.Unbind("CoopDrop")
		end
	end
	player:GetAttributeChangedSignal("Carrying"):Connect(onCarry)
	onCarry()

	buildPicker()
	buildPayout()

	Net.Event("State").OnClientEvent:Connect(function(s)
		UI.State = s
		local role = UI.MyRole()
		tradeBtn.Text = tradeText()
		tradeBtn.BackgroundColor3 = if role then Trades.Info[role].Color else Color3.fromRGB(70, 90, 140)
		refreshPicker()
		UI.StateChanged:Fire(s)
	end)
	Net.Event("Toast").OnClientEvent:Connect(function(text)
		if typeof(text) == "string" then
			UI.Toast(text)
		end
	end)
	Net.Event("TaskEnd").OnClientEvent:Connect(function(d)
		if d.ok then
			UI.Toast(("Nice! %d%% accuracy"):format(math.floor(d.accuracy * 100 + 0.5)))
		elseif d.message then
			UI.Toast(d.message)
		end
	end)
	Net.Event("Payout").OnClientEvent:Connect(showPayout)

	-- Countdown text
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local s = UI.State
		if s.active then
			local left = math.max(0, (s.deadlineAt or 0) - workspace:GetServerTimeNow())
			status.Text = ("%s  %d:%02d  |  %d/%d done  |  %s"):format(
				string.upper(s.job or ""), left // 60, math.floor(left % 60), s.done or 0, s.total or 0, s.phase or "")
			status.TextColor3 = if left < 60 then Color3.fromRGB(255, 120, 100) else WHITE
		else
			status.Text = if UI.MyRole() then "Grab a coffee, then pick a site at the truck lot board" else "Tap 'Pick trade' to choose your job"
			status.TextColor3 = WHITE
		end
	end)

	Net.Event("Hello"):FireServer()
	-- Returning players get their last trade back from the save; only ask if nothing was restored.
	task.delay(3, function()
		if not UI.MyRole() then
			picker.Visible = true
		end
	end)
end

return UI
