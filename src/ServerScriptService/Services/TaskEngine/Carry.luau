--!strict
-- Carry task: the server tracks what each worker holds. Heavier items slow you down.
-- A worker is a Player or a bot's character Model (bots use the same Carry code as players).
-- Clients never say what they hold; the "Carrying" attribute is display only.
local Carry = {}

type Held = { item: string, part: BasePart, speed: number }
local held: { [Instance]: Held } = {}
local DEFAULT_SPEED = 16

-- Speed multiplier hook (e.g. the Awake buff from BuffService). Defaults to 1.
local speedMultiplier: (Instance) -> number = function()
	return 1
end

function Carry.SetSpeedMultiplier(fn: (Instance) -> number)
	speedMultiplier = fn
end

local function characterOf(actor: Instance): Model?
	if actor:IsA("Player") then
		return actor.Character
	end
	return if actor:IsA("Model") then actor else nil
end

local function body(actor: Instance): (Humanoid?, BasePart?)
	local c = characterOf(actor)
	if not c then
		return nil, nil
	end
	return c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Final walk speed: item weight x buffs x the worker's own scale (bots walk slower: SpeedScale < 1).
local function speedFor(actor: Instance, base: number): number
	local scale = actor:GetAttribute("SpeedScale")
	return base * speedMultiplier(actor) * (if typeof(scale) == "number" then scale else 1)
end

function Carry.Holding(actor: Instance): string?
	local h = held[actor]
	return if h then h.item else nil
end

function Carry.PickUp(actor: Instance, item: string, def: any): boolean
	if held[actor] then
		return false
	end
	local hum, root = body(actor)
	if not hum or not root or hum.Health <= 0 then
		return false
	end
	local part = Instance.new("Part")
	part.Name = "Carried_" .. item
	part.Size = def.Size
	part.Color = def.Color
	local okMat, mat = pcall(function()
		return (Enum.Material :: any)[def.Material]
	end)
	part.Material = if okMat and mat then mat else Enum.Material.WoodPlanks
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = root.CFrame * (def.Hold or CFrame.new(0, 0, -1.6))
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = part
	w.Parent = part
	part.Parent = characterOf(actor)

	local speed = def.WalkSpeed or DEFAULT_SPEED
	held[actor] = { item = item, part = part, speed = speed }
	hum.WalkSpeed = speedFor(actor, speed)
	actor:SetAttribute("Carrying", item)
	return true
end

local function release(actor: Instance)
	local h = held[actor]
	if not h then
		return
	end
	held[actor] = nil
	h.part:Destroy()
	local hum = body(actor)
	if hum then
		hum.WalkSpeed = speedFor(actor, DEFAULT_SPEED)
	end
	actor:SetAttribute("Carrying", nil)
end

-- Item used up by a placement.
function Carry.Consume(actor: Instance)
	release(actor)
end

-- Worker dropped it; it goes back to the pile (piles are unlimited).
function Carry.Drop(actor: Instance)
	release(actor)
end

function Carry.DropAll()
	for actor in held do
		release(actor)
	end
end

function Carry.Forget(actor: Instance)
	held[actor] = nil
end

-- Re-applies walk speed after a buff changes or the character respawns.
function Carry.RefreshSpeed(actor: Instance)
	local hum = body(actor)
	if hum then
		local h = held[actor]
		hum.WalkSpeed = speedFor(actor, if h then h.speed else DEFAULT_SPEED)
	end
end

return Carry
