--!strict
-- Truck dealer prompt text for this player (display only; DealerService decides what a tap does):
-- locked until the first paycheck -> "Buy $3,000" -> "Use this truck" / "Switch to starter truck".
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Dealer = {}

local player = Players.LocalPlayer
local shown: { [ProximityPrompt]: boolean } = {}

local function owns(kind: string): boolean
	local list = player:GetAttribute("Trucks")
	if typeof(list) ~= "string" then
		return false
	end
	for k in string.gmatch(list, "[^,]+") do
		if k == kind then
			return true
		end
	end
	return false
end

local function apply(pp: ProximityPrompt)
	local kind = pp:GetAttribute("DealerTruck")
	if typeof(kind) ~= "string" then
		return
	end
	local name = tostring(pp:GetAttribute("DisplayName") or kind)
	local cap = tonumber(pp:GetAttribute("Capacity")) or 0
	local price = tonumber(pp:GetAttribute("Price")) or 0
	if player:GetAttribute("RVUnlocked") ~= true then
		pp.ActionText = "Opens after first paycheck"
		pp.ObjectText = ("%s $%d"):format(name, price)
	elseif not owns(kind) then
		pp.ActionText = ("Buy $%d"):format(price)
		pp.ObjectText = ("%s (holds %d)"):format(name, cap)
	elseif player:GetAttribute("Truck") == kind then
		pp.ActionText = "Switch to starter truck"
		pp.ObjectText = name .. ": your crew truck"
	else
		pp.ActionText = "Use this truck"
		pp.ObjectText = ("%s (holds %d)"):format(name, cap)
	end
end

local function refresh()
	for pp in shown do
		apply(pp)
	end
end

function Dealer.Start()
	ProximityPromptService.PromptShown:Connect(function(pp: ProximityPrompt)
		if pp:GetAttribute("DealerTruck") ~= nil then
			shown[pp] = true
			apply(pp)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(pp: ProximityPrompt)
		shown[pp] = nil
	end)
	for _, a in { "Trucks", "Truck", "RVUnlocked" } do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
end

return Dealer
