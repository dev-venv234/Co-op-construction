--!strict
-- Shows which job sites this player can start at the RV park board. Locked buttons get a dark "LOCKED" cover
-- with the unlock rule and their prompt is hidden; the next site to unlock also shows a progress bar (the player's
-- trade closest to it, XP / XP needed; attributes from ProgressionService). Display only: JobService checks unlocks
-- again on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Display = require(ReplicatedStorage.Shared.Config.Sites)

local SiteBoard = {}

local player = Players.LocalPlayer
local buttons: { [BasePart]: boolean } = {}

local function infoFor(siteId: unknown): any
	for _, s in Display do
		if s.Lot == siteId then
			return s
		end
	end
	return nil
end

local function apply(button: BasePart)
	local s = infoFor(button:GetAttribute("StartSite"))
	if not s then
		return
	end
	local unlockedTier = player:GetAttribute("UnlockedTier")
	local unlocked = (if typeof(unlockedTier) == "number" then unlockedTier else 1) >= s.Tier
	local released = s.Release == "Launch" or RunService:IsStudio()
	local open = unlocked and released

	local pp = button:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp.Enabled = open
	end
	local cover = button:FindFirstChild("LockCover") :: SurfaceGui?
	if open then
		if cover then
			cover:Destroy()
		end
		return
	end
	if not cover then
		local sg = Instance.new("SurfaceGui")
		sg.Name = "LockCover"
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.ZOffset = 1
		local bg = Instance.new("Frame")
		bg.Name = "Bg"
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
		bg.BackgroundTransparency = 0.15
		bg.BorderSizePixel = 0
		bg.Parent = sg
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.BackgroundTransparency = 1
		t.TextColor3 = Color3.fromRGB(235, 235, 235)
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.Parent = bg
		-- progress (next site only)
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0.5, 0)
		bar.Position = UDim2.fromScale(0.5, 0.6)
		bar.Size = UDim2.fromScale(0.86, 0.14)
		bar.BackgroundColor3 = Color3.fromRGB(60, 62, 70)
		bar.BorderSizePixel = 0
		bar.Parent = bg
		Instance.new("UICorner").Parent = bar
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = Color3.fromRGB(255, 190, 50)
		fill.BorderSizePixel = 0
		fill.Parent = bar
		Instance.new("UICorner").Parent = fill
		local xp = Instance.new("TextLabel")
		xp.Name = "XP"
		xp.BackgroundTransparency = 1
		xp.Position = UDim2.fromScale(0.05, 0.77)
		xp.Size = UDim2.fromScale(0.9, 0.18)
		xp.TextColor3 = Color3.fromRGB(255, 210, 110)
		xp.TextScaled = true
		xp.Font = Enum.Font.GothamBold
		xp.Parent = bg
		sg.Parent = button
		cover = sg
	end
	local bg = (cover :: SurfaceGui):FindFirstChild("Bg") :: Frame
	local label = bg:FindFirstChild("Text") :: TextLabel
	local bar = bg:FindFirstChild("Bar") :: Frame
	local xpLabel = bg:FindFirstChild("XP") :: TextLabel
	local need = player:GetAttribute("NextSiteXP")
	local have = player:GetAttribute("ProgressXP")
	local level = player:GetAttribute("NextSiteLevel")
	local isNext = released and player:GetAttribute("NextSiteTier") == s.Tier and typeof(need) == "number"
		and typeof(have) == "number" and typeof(level) == "number"
	bar.Visible = isNext
	xpLabel.Visible = isNext
	if isNext then
		label.Position = UDim2.fromScale(0.05, 0.04)
		label.Size = UDim2.fromScale(0.9, 0.52)
		label.Text = ("LOCKED\nLevel %d in any trade"):format(level :: number)
		local frac = math.clamp((have :: number) / math.max(need :: number, 1), 0, 1)
		;(bar:FindFirstChild("Fill") :: Frame).Size = UDim2.fromScale(frac, 1)
		-- (no trade name at 0 XP: every trade ties, so naming one would be misleading)
		local who = if (have :: number) > 0 then tostring(player:GetAttribute("ProgressTrade")) .. " " else ""
		xpLabel.Text = ("%s%d / %d XP"):format(who, have :: number, need :: number)
	else
		label.Position = UDim2.fromScale(0, 0)
		label.Size = UDim2.fromScale(1, 1)
		label.Text = if released then ("LOCKED\n%s"):format(s.Unlock) else "COMING SOON"
	end
end

local function track(inst: Instance)
	if inst:IsA("BasePart") and inst:GetAttribute("StartSite") ~= nil and not buttons[inst] then
		buttons[inst] = true
		inst.ChildAdded:Connect(function(child)
			if child:IsA("ProximityPrompt") then
				task.defer(apply, inst)
			end
		end)
		inst.Destroying:Connect(function()
			buttons[inst] = nil
		end)
		task.defer(apply, inst)
	end
end

function SiteBoard.Start()
	workspace.DescendantAdded:Connect(track) -- buttons can stream in later
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	local function refresh()
		for b in buttons do
			apply(b)
		end
	end
	for _, attr in { "UnlockedTier", "NextSiteTier", "ProgressXP", "ProgressTrade" } do
		player:GetAttributeChangedSignal(attr):Connect(refresh)
	end
end

return SiteBoard
