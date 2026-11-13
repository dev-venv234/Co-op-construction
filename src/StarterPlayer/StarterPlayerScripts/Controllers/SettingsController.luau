--!strict
-- SETTINGS (button under GUIDE, top right): sound volumes, graphics quality, drive-button layout.
-- Everything applies at once on this device; the choice is saved to the player's profile (SaveSettings remote,
-- validated by DataService) and comes back as the "Settings" attribute next time.
--  * Sound: Master / Music / Effects / Ambient in 10% steps (SoundController reads them).
--  * Graphics: Low / Medium / High. Low turns off shadows and post effects and shows 30% of the forest; Medium keeps
--    shadows, drops sun rays and depth of field, shows 60%. "Auto" (until the player picks) = Medium on phones.
--  * Controls: drive buttons on the right or left hand side, Normal or Large (VehicleController reads them).
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Settings = {}

Settings.Defaults = {
	Master = 1,
	Music = 0.5,
	Effects = 1,
	Ambient = 0.8,
	Quality = "Auto",
	DriveLayout = "Right",
	BigButtons = false,
}
Settings.Current = table.clone(Settings.Defaults) :: { [string]: any }
Settings.Changed = Instance.new("BindableEvent") -- (key: string?)

local player = Players.LocalPlayer
local panel: Frame? = nil
local refreshers: { () -> () } = {}
local saveAt = 0

local TREE_SHARE = { Low = 0.3, Medium = 0.6, High = 1 }

function Settings.Get(key: string): any
	return Settings.Current[key]
end

-- Quality to use right now ("Auto" picks for the device).
function Settings.Quality(): string
	local q = Settings.Current.Quality
	if q == "Auto" then
		return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Medium" else "High"
	end
	return q
end

---------------------------------------------------------------------------------------------------------------
-- Graphics
---------------------------------------------------------------------------------------------------------------

-- Forest thinning: each tree keeps a fixed spot in a 0..99 order, so the same trees stay on every visit.
local hiddenFolder = Instance.new("Folder")
hiddenFolder.Name = "HiddenTrees_Local"
local hiddenFrom: { [Instance]: Instance } = {}

local function treeRank(m: Model): number
	local p = m:GetPivot().Position
	local h = bit32.bxor(math.floor(p.X) * 73856093, math.floor(p.Z) * 19349663)
	return h % 100
end

local function isTree(inst: Instance): boolean
	if not inst:IsA("Model") then
		return false
	end
	local folder = inst.Parent
	return folder ~= nil and folder:IsA("Folder") and folder.Parent ~= nil and folder.Parent.Name == "Nature"
end

local function applyTree(m: Model)
	local keep = TREE_SHARE[Settings.Quality()] or 1
	if treeRank(m) >= keep * 100 then
		hiddenFrom[m] = m.Parent
		m.Parent = hiddenFolder
	end
end

local function applyTrees()
	local keep = TREE_SHARE[Settings.Quality()] or 1
	-- bring back trees the new setting shows
	for m, from in hiddenFrom do
		if treeRank(m :: Model) < keep * 100 then
			if from.Parent then
				m.Parent = from
			end
			hiddenFrom[m] = nil
		end
	end
	local nature = workspace:FindFirstChild("Nature")
	if nature then
		for _, folder in nature:GetChildren() do
			if folder:IsA("Folder") then
				for _, m in folder:GetChildren() do
					if m:IsA("Model") then
						applyTree(m)
					end
				end
			end
		end
	end
end

local function applyGraphics()
	local q = Settings.Quality()
	Lighting.GlobalShadows = q ~= "Low"
	for _, fx in Lighting:GetChildren() do
		if fx:IsA("SunRaysEffect") or fx:IsA("DepthOfFieldEffect") then
			fx.Enabled = q == "High"
		elseif fx:IsA("BloomEffect") then
			fx.Enabled = q ~= "Low"
		end
	end
	applyTrees()
end

---------------------------------------------------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------------------------------------------------

local function set(key: string, value: any)
	Settings.Current[key] = value
	if key == "Quality" then
		applyGraphics()
	end
	Settings.Changed:Fire(key)
	for _, r in refreshers do
		r()
	end
	saveAt = os.clock() + 1 -- save once the player stops tapping
	task.delay(1.05, function()
		if os.clock() >= saveAt then
			Net.Event("SaveSettings"):FireServer(Settings.Current)
		end
	end)
end

local function loadFromProfile()
	local raw = player:GetAttribute("Settings")
	if typeof(raw) ~= "string" then
		return
	end
	local ok, t = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or typeof(t) ~= "table" then
		return
	end
	for k, v in t do
		if Settings.Defaults[k] ~= nil and typeof(v) == typeof(Settings.Defaults[k]) then
			Settings.Current[k] = v
		end
	end
	applyGraphics()
	Settings.Changed:Fire(nil)
	for _, r in refreshers do
		r()
	end
end

---------------------------------------------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------------------------------------------

local DARK = Color3.fromRGB(28, 30, 36)
local ROW = Color3.fromRGB(44, 47, 56)
local ON = Color3.fromRGB(240, 150, 40)
local OFF = Color3.fromRGB(70, 74, 86)

local function label(text: string, parent: Instance, size: UDim2, pos: UDim2): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = text
	t.Parent = parent
	return t
end

local function button(text: string, parent: Instance, size: UDim2, pos: UDim2, color: Color3): TextButton
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
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = b
	return b
end

local function row(list: Frame, order: number): Frame
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.new(1, 0, 0, 52)
	f.BackgroundColor3 = ROW
	f.Parent = list
	Instance.new("UICorner").Parent = f
	return f
end

local function header(list: Frame, order: number, text: string)
	local h = label(text, list, UDim2.new(1, 0, 0, 26), UDim2.new())
	h.LayoutOrder = order
	h.TextColor3 = Color3.fromRGB(255, 200, 70)
end

-- Volume: [-] 80% [+]
local function stepper(list: Frame, order: number, title: string, key: string)
	local f = row(list, order)
	label(title, f, UDim2.new(0.4, -10, 0, 30), UDim2.new(0, 10, 0, 11))
	local minus = button("-", f, UDim2.new(0, 52, 0, 46), UDim2.new(0.4, 0, 0, 3), OFF)
	local value = label("", f, UDim2.new(0.6, -128, 0, 30), UDim2.new(0.4, 58, 0, 11))
	value.TextXAlignment = Enum.TextXAlignment.Center
	local plus = button("+", f, UDim2.new(0, 52, 0, 46), UDim2.new(1, -58, 0, 3), OFF)
	local function refresh()
		value.Text = ("%d%%"):format(math.floor((Settings.Current[key] :: number) * 100 + 0.5))
	end
	minus.Activated:Connect(function()
		set(key, math.max(0, math.floor((Settings.Current[key] :: number) * 10 + 0.5) / 10 - 0.1))
	end)
	plus.Activated:Connect(function()
		set(key, math.min(1, math.floor((Settings.Current[key] :: number) * 10 + 0.5) / 10 + 0.1))
	end)
	table.insert(refreshers, refresh)
	refresh()
end

-- One of a few choices: [Low][Medium][High]
local function choice(list: Frame, order: number, title: string, key: string, options: { { string | any } })
	local f = row(list, order)
	label(title, f, UDim2.new(0.34, -10, 0, 30), UDim2.new(0, 10, 0, 11))
	local n = #options
	local buttons = {}
	for i, opt in options do
		local w = 1 / n
		local b = button(opt[1] :: string, f, UDim2.new(0.66 * w, -6, 0, 46), UDim2.new(0.34 + 0.66 * w * (i - 1), 0, 0, 3), OFF)
		b.Activated:Connect(function()
			set(key, opt[2])
		end)
		buttons[i] = b
	end
	local function refresh()
		local cur = Settings.Current[key]
		if key == "Quality" then
			cur = Settings.Quality()
		end
		for i, opt in options do
			buttons[i].BackgroundColor3 = if opt[2] == cur then ON else OFF
		end
	end
	table.insert(refreshers, refresh)
	refresh()
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Settings"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	local open = Instance.new("TextButton")
	open.Name = "SettingsButton"
	open.AnchorPoint = Vector2.new(1, 0)
	open.Position = UDim2.new(1, -8, 0, 54) -- under GUIDE
	open.Size = UDim2.fromOffset(96, 44)
	open.BackgroundColor3 = Color3.fromRGB(70, 90, 140)
	open.Font = Enum.Font.GothamBlack
	open.TextScaled = true
	open.TextColor3 = Color3.new(1, 1, 1)
	open.Text = "SETTINGS"
	open.Parent = gui
	Instance.new("UICorner").Parent = open
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = open

	local p = Instance.new("Frame")
	p.Name = "Panel"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.5)
	p.Size = UDim2.new(0.9, 0, 0.9, 0)
	p.BackgroundColor3 = DARK
	p.Visible = false
	p.Parent = gui
	Instance.new("UICorner").Parent = p
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 620)
	limit.Parent = p
	panel = p

	local title = label("SETTINGS", p, UDim2.new(1, -80, 0, 34), UDim2.new(0, 14, 0, 8))
	title.Font = Enum.Font.GothamBlack
	local close = button("X", p, UDim2.fromOffset(52, 46), UDim2.new(1, -60, 0, 6), Color3.fromRGB(150, 60, 55))
	close.Activated:Connect(function()
		p.Visible = false
	end)
	open.Activated:Connect(function()
		p.Visible = not p.Visible
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.new(0, 12, 0, 58)
	scroll.Size = UDim2.new(1, -24, 1, -70)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = p
	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -10, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Parent = scroll
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	header(list, 1, "SOUND")
	stepper(list, 2, "Master", "Master")
	stepper(list, 3, "Music", "Music")
	stepper(list, 4, "Effects", "Effects")
	stepper(list, 5, "World", "Ambient")
	header(list, 10, "GRAPHICS")
	choice(list, 11, "Quality", "Quality", { { "Low", "Low" }, { "Medium", "Medium" }, { "High", "High" } })
	header(list, 20, "CONTROLS")
	choice(list, 21, "Drive buttons", "DriveLayout", { { "Right hand", "Right" }, { "Left hand", "Left" } })
	choice(list, 22, "Button size", "BigButtons", { { "Normal", false }, { "Large", true } })
	local note = label("Phones: Low or Medium runs smoother. Settings are saved to your profile.", list, UDim2.new(1, 0, 0, 22), UDim2.new())
	note.LayoutOrder = 30
	note.TextColor3 = Color3.fromRGB(170, 175, 190)
	note.Font = Enum.Font.Gotham
end

function Settings.Start()
	build()
	hiddenFolder.Parent = ReplicatedStorage -- client-only: trees hidden by the quality setting wait here
	-- trees streaming in later get the same treatment
	workspace.DescendantAdded:Connect(function(d)
		if isTree(d) then
			task.defer(function()
				if isTree(d) then
					applyTree(d :: Model)
				end
			end)
		end
	end)
	player:GetAttributeChangedSignal("Settings"):Connect(loadFromProfile)
	loadFromProfile()
	applyGraphics()
end

return Settings
