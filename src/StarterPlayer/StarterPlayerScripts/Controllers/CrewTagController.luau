--!strict
-- Crew tags (2026-11-17, crew vs crew): a small tag over every other player's head with their crew's name in that
-- crew's color, and a crown on the crew leading this server's standings (player attribute TopCrew, LeagueService).
-- Display only, drawn locally from the CrewName / CrewId / TopCrew attributes the server sets.
local Players = game:GetService("Players")

local CrewTags = {}

local player = Players.LocalPlayer
local COLORS = {
	Color3.fromRGB(240, 170, 50), Color3.fromRGB(80, 170, 255), Color3.fromRGB(110, 210, 110),
	Color3.fromRGB(230, 90, 90), Color3.fromRGB(190, 120, 240), Color3.fromRGB(70, 210, 200),
}

local function refresh(p: Player)
	local c = p.Character
	local head = c and c:FindFirstChild("Head")
	if not head then
		return
	end
	local tag = head:FindFirstChild("CrewTag") :: BillboardGui?
	local name = p:GetAttribute("CrewName")
	if typeof(name) ~= "string" then
		if tag then
			tag:Destroy()
		end
		return
	end
	if not tag then
		local bb = Instance.new("BillboardGui")
		bb.Name = "CrewTag"
		bb.Size = UDim2.fromOffset(150, 22)
		bb.StudsOffset = Vector3.new(0, 3.1, 0)
		bb.MaxDistance = 90
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextStrokeTransparency = 0.35
		t.Parent = bb
		bb.Parent = head
		tag = bb
	end
	local id = p:GetAttribute("CrewId")
	local label = (tag :: BillboardGui):FindFirstChild("Text") :: TextLabel
	local top = p:GetAttribute("TopCrew") == true
	label.Text = if top then "#1 " .. name else name
	label.TextColor3 = if top then Color3.fromRGB(255, 215, 80)
		elseif typeof(id) == "number" then COLORS[(id - 1) % #COLORS + 1]
		else Color3.new(1, 1, 1)
end

local function track(p: Player)
	if p == player then
		return -- your own crew name is on your HUD
	end
	p.CharacterAdded:Connect(function(c)
		c:WaitForChild("Head", 10)
		refresh(p)
	end)
	for _, attr in { "CrewName", "CrewId", "TopCrew" } do
		p:GetAttributeChangedSignal(attr):Connect(function()
			refresh(p)
		end)
	end
	refresh(p)
end

function CrewTags.Start()
	Players.PlayerAdded:Connect(track)
	for _, p in Players:GetPlayers() do
		track(p)
	end
end

return CrewTags
