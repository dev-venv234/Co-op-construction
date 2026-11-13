--!strict
-- Shows each player only the prompts for their trade (plus open trades nobody holds).
-- Display only: the server re-checks trade, order and distance on every prompt.
local UI = require(script.Parent.Parent.UIController)

local PromptFilter = {}

local tracked: { [ProximityPrompt]: boolean } = {}

local function roleHeld(role: string): boolean
	local names = (UI.State.roles or {})[role]
	return names ~= nil and #names > 0
end

local function apply(pp: ProximityPrompt)
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
	UI.StateChanged.Event:Connect(function()
		for pp in tracked do
			if pp.Parent then
				apply(pp)
			end
		end
	end)
end

return PromptFilter
