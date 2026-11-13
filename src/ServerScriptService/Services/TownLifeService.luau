--!strict
-- Townspeople, so the town feels lived in (owner request 2026-11-12):
--  * residents walking the sidewalks of the town center and Oak Ave, pausing at each end;
--  * a couple of people hanging around the RV park coffee stand;
--  * people sitting on some of the street benches (benches come from DevTools/LifeBuilder: Workspace.TownLife).
-- Server-side Humanoids (everyone sees the same people) built with BotService.MakeBody in everyday clothes, no hard
-- hat, no name tag. They never touch jobs, money or tasks. Moving traffic is client-side (TrafficController) and
-- stops for them; parked cars and street props are map parts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TownLayout = require(ReplicatedStorage.Shared.Config.TownLayout)

local Life = {}

local S: any
local rng = Random.new()
local folder: Folder

local C = Color3.fromRGB
local SHIRTS = { C(70, 110, 170), C(180, 60, 60), C(60, 140, 90), C(220, 180, 60), C(120, 80, 150), C(230, 230, 225), C(40, 40, 48), C(200, 120, 60) }

-- Sidewalks are 8 studs wide, starting at the road edge (road half-width 16): walk on their middle (20 off center).
local function sidewalk(roadName: string, side: number, from: number, to: number): { Vector3 }
	for _, r in TownLayout.Roads do
		if r.Name == roadName then
			local off = side * (TownLayout.RoadWidth / 2 + TownLayout.SidewalkWidth / 2)
			if r.Axis == "X" then
				return { Vector3.new(from, 0, r.At + off), Vector3.new(to, 0, r.At + off) }
			else
				return { Vector3.new(r.At + off, 0, from), Vector3.new(r.At + off, 0, to) }
			end
		end
	end
	return {}
end

local WALKS = {
	sidewalk("Main St", -1, -280, 280),
	sidewalk("Main St", -1, 260, -260),
	sidewalk("Main St", 1, -300, 300),
	sidewalk("Oak Ave", -1, -440, -1150),
	sidewalk("Oak Ave", 1, -1150, -440),
	sidewalk("Main St", -1, 320, 900),
}

function Life.Init(services)
	S = services
end

-- fromY: where the ray starts (default 60); start lower under roofs and awnings
local function groundAt(p: Vector3, fromY: number?): Vector3
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { folder }
	local y = fromY or 60
	local hit = workspace:Raycast(Vector3.new(p.X, y, p.Z), Vector3.new(0, -(y + 60), 0), rp)
	return if hit then hit.Position else Vector3.new(p.X, 0, p.Z)
end

local function person(at: CFrame): (Model?, Humanoid?)
	local body = S.BotService.MakeBody("Resident", SHIRTS[rng:NextInteger(1, #SHIRTS)], nil, at)
	if not body then
		return nil, nil
	end
	body:SetAttribute("Townsperson", true)
	local hum = body:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.WalkSpeed = rng:NextNumber(5.5, 7.5)
	body.Parent = folder
	local root = body:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	return body, hum
end

-- Walks to `to`, re-issuing MoveTo (it gives up after 8 s); a stuck walker is put back on its path.
local function walkTo(body: Model, hum: Humanoid, to: Vector3)
	local root = body:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local t0 = os.clock()
	local limit = (Vector2.new(to.X - root.Position.X, to.Z - root.Position.Z)).Magnitude / hum.WalkSpeed + 6
	while body.Parent and os.clock() - t0 < limit do
		if Vector2.new(to.X - root.Position.X, to.Z - root.Position.Z).Magnitude < 3 then
			return
		end
		hum:MoveTo(Vector3.new(to.X, root.Position.Y, to.Z))
		hum.MoveToFinished:Wait()
	end
	if body.Parent then
		body:PivotTo(CFrame.new(groundAt(to) + Vector3.new(0, 3, 0)))
	end
end

local function walker(path: { Vector3 })
	local a, b = groundAt(path[1]), groundAt(path[2])
	local start = a:Lerp(b, rng:NextNumber(0, 0.8))
	local body, hum = person(CFrame.lookAt(start + Vector3.new(0, 3, 0), b + Vector3.new(0, 3, 0)))
	if not body or not hum then
		return
	end
	task.spawn(function()
		local target = b
		while body.Parent do
			walkTo(body, hum, target)
			task.wait(rng:NextNumber(1.5, 5))
			target = if target == b then a else b
		end
	end)
end

-- Someone standing still (anchored at the hip so nobody bumps them away), facing `look`.
local function stander(at: Vector3, look: Vector3)
	local pos = groundAt(at, at.Y + 3) + Vector3.new(0, 3, 0)
	local body = person(CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z)))
	if body then
		local root = body:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = true
		end
	end
end

function Life.Start()
	folder = Instance.new("Folder")
	folder.Name = "Townsfolk"
	folder.Parent = workspace
	task.wait(3) -- let the map and BotService settle

	for _, path in WALKS do
		if #path == 2 then
			walker(path)
			task.wait(0.2)
		end
	end

	-- Coffee stand regulars: the prompt part BuffService uses (any part with a "coffee" prompt in the RV park)
	local park = workspace:FindFirstChild("RVPark")
	local counter: BasePart? = nil
	if park then
		for _, d in park:GetDescendants() do
			if d:IsA("ProximityPrompt") and string.find(string.lower(d.ActionText .. d.ObjectText), "coffee") then
				local p = d.Parent
				if p and p:IsA("BasePart") then
					counter = p
				end
			end
		end
	end
	if counter then
		local front = counter.CFrame.LookVector
		for i, side in { -1, 1 } do
			local spot = counter.Position + front * 7 + counter.CFrame.RightVector * side * (3 + i)
			stander(spot, counter.Position)
		end
	end

	-- Bench sitters: two benches from LifeBuilder
	local life = workspace:FindFirstChild("TownLife")
	local seats = {}
	if life then
		for _, d in life:GetDescendants() do
			if d:IsA("Seat") and d.Name == "BenchSeat" then
				table.insert(seats, d)
			end
		end
	end
	for _ = 1, math.min(2, #seats) do
		local seat = table.remove(seats, rng:NextInteger(1, #seats)) :: Seat
		local body, hum = person(seat.CFrame + Vector3.new(0, 3, 0))
		if body and hum then
			task.wait(0.3)
			seat:Sit(hum)
		end
	end
end

return Life
