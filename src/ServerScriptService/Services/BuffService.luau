--!strict
-- "Awake" buff from the RV park coffee stand. Held on the server; lasts until the end of the next job
-- (or until you leave). Skipping coffee is allowed: you just work at normal speed while Awake players
-- are faster.
-- Effects: +15% walk speed (also while carrying) and a 25% wider green zone on Timing tasks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Buff = {}

local AWAKE_WALK = 1.15
local AWAKE_TIMING = 1.25
local COUNTER_REACH = 14
local CUP_SECONDS = 8

local awake: { [Player]: boolean } = {}
local S: any

function Buff.Init(services)
	S = services
end

function Buff.IsAwake(p: Player): boolean
	return awake[p] == true
end

local function apply(p: Player)
	p:SetAttribute("Awake", if awake[p] then true else nil) -- display only
	S.TaskEngine.Carry.RefreshSpeed(p)
end

function Buff.Grant(p: Player)
	awake[p] = true
	apply(p)
end

-- Called by JobService when a job ends (paid or failed).
function Buff.EndJob()
	for p in awake do
		awake[p] = nil
		if p.Parent then
			apply(p)
		end
	end
end

-- Short visual: a paper cup in the player's right hand.
local function showCup(p: Player)
	local c = p.Character
	local hand = c and (c:FindFirstChild("RightHand") or c:FindFirstChild("Right Arm")) :: BasePart?
	if not hand then
		return
	end
	local cup = Instance.new("Part")
	cup.Name = "CoffeeCup"
	cup.Shape = Enum.PartType.Cylinder
	cup.Size = Vector3.new(0.7, 0.5, 0.5)
	cup.Color = Color3.fromRGB(245, 240, 230)
	cup.Material = Enum.Material.Fabric
	cup.CanCollide = false
	cup.CanQuery = false
	cup.CanTouch = false
	cup.Massless = true
	cup.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - 0.1, -0.2) * CFrame.Angles(0, 0, math.pi / 2)
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand
	w.Part1 = cup
	w.Parent = cup
	cup.Parent = c
	task.delay(CUP_SECONDS, function()
		if cup.Parent then
			cup:Destroy()
		end
	end)
end

local function hookCounter(counter: BasePart)
	local Toast = Net.Event("Toast")
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "CoffeePrompt"
	pp.ActionText = "Grab coffee"
	pp.ObjectText = "Coffee stand"
	pp.HoldDuration = 1.2
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.GamepadKeyCode = Enum.KeyCode.ButtonX
	pp.Parent = counter
	S.JobService.RegisterPrompt(pp, function(p: Player)
		if not S.TaskEngine.Guard.Allow(p, "Coffee", 1) then
			return
		end
		local c = p.Character
		local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - counter.Position).Magnitude > COUNTER_REACH then
			return
		end
		if awake[p] then
			Toast:FireClient(p, "You already had your coffee. Get to work!")
			return
		end
		Buff.Grant(p)
		showCup(p)
		Toast:FireClient(p, "AWAKE! You move and work faster for your whole next job")
	end)
end

function Buff.Start()
	S.TaskEngine.Carry.SetSpeedMultiplier(function(p: Player): number
		return if awake[p] then AWAKE_WALK else 1
	end)
	S.TaskEngine.SetTimingWidth(function(p: Player): number
		return if awake[p] then AWAKE_TIMING else 1
	end)

	local function hookPlayer(p: Player)
		p.CharacterAdded:Connect(function(char)
			char:WaitForChild("Humanoid")
			task.defer(apply, p)
		end)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		awake[p] = nil
	end)

	-- The coffee counter is part of the map (built by DevTools/RVParkBuilder). Prompts are created here at
	-- runtime so the map itself holds no scripts.
	local park = workspace:WaitForChild("RVPark", 10)
	if not park then
		warn("[Buff] No Workspace.RVPark: coffee stand disabled")
		return
	end
	for _, d in park:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("CoffeeCounter") then
			hookCounter(d)
		end
	end
end

return Buff
