--!strict
-- Shows each player only the prompts for their trade (plus open trades nobody holds) at their own crew's site;
-- another crew's slots, piles, truck and machines show no prompts (2026-11-17, several crews per server).
-- Display only: the server re-checks crew, trade, order and distance on every prompt.
local UI = require(script.Parent.Parent.UIController)

local PromptFilter = {}

local tracked: { [ProximityPrompt]: boolean } = {}

local function roleHeld(role: string): boolean
	local names = (UI.State.roles or {})[role]
	return names ~= nil and #names > 0
end

local function apply(pp: ProximityPrompt)
	if UI.Foreign(pp) then
		pp.Enabled = false
		return
	end
	if UI.SiteCrewOf(pp) ~= nil and pp:GetAttribute("Open") == nil and pp:GetAttribute("PileItem") == nil then
		pp.Enabled = true -- my crew's truck / machine prompts (they may have been hidden before I joined this crew)
		return
	end
	if pp:GetAttribute("PileItem") ~= nil then
		pp.Enabled = UI.State.active == true
		return
	end
	local open = pp:GetAttribute("Open")
	if open == nil then
		return -- not a job prompt (e.g. the job board)
	end
	local role = pp:GetAttribute("Role")
	local mine = UI.MyRole()
	pp.Enabled = open == true
		and mine ~= nil
		and typeof(role) == "string"
		and (role == mine or not roleHeld(role))
end

local function track(inst: Instance)
	if inst:IsA("ProximityPrompt") and not tracked[inst] then
		tracked[inst] = true
		inst:GetAttributeChangedSignal("Open"):Connect(function()
			apply(inst)
		end)
		inst.Destroying:Connect(function()
			tracked[inst] = nil
		end)
		task.defer(apply, inst)
	end
end

function PromptFilter.Start()
	workspace.DescendantAdded:Connect(track)
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	local function all()
		for pp in tracked do
			if pp.Parent then
				apply(pp)
			end
		end
	end
	UI.StateChanged.Event:Connect(all)
	game:GetService("Players").LocalPlayer:GetAttributeChangedSignal("CrewId"):Connect(all)
end

return PromptFilter
