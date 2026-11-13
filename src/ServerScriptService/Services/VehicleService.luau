--!strict
-- Drivable machines (the crew truck, the excavator).
-- Driving (2026-11-12, owner: driving felt bad): a player in the driver's seat gets network ownership, and the drive
-- model runs on their client (VehicleController) so the truck answers the pedals instantly. The model's attributes
-- (MaxFwd, MaxRev, Accel, Brake, Turn, Wheelbase, SpeedFactor) are the limits it drives by. The server still decides
-- who may drive and watches every client-driven vehicle (guard): faster than it can go, a jump, or flying ->
-- ownership is taken back, the vehicle is put back where it last was fine, and that driver waits 5 s.
-- Bots and empty vehicles stay server-owned and are driven here from the seat or Vehicle.Drive (bots).
-- Board with a tap: each vehicle has a "Drive" prompt on its door/cab (routed through JobService.RegisterPrompt).
-- Crew trucks: the rusty starter truck and the Work pickup (bought at the truck dealer). Each kind's Capacity
-- (Config/Vehicles) is how many bundles its bed holds. Loaded at the RV park dock, unloaded at a site's pad.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local ServerStorage = game:GetService("ServerStorage")
local VehiclesConfig = require(ServerStorage.Config.Vehicles)

local Vehicle = {}

export type Spec = {
	maxFwd: number,
	maxRev: number,
	accel: number,
	brake: number,
	turn: number, -- rad/s at speed
	role: string?, -- trade allowed to drive (nil = anyone in the crew)
	promptPart: BasePart?,
	promptText: string?,
}

export type Truck = {
	model: Model,
	chassis: BasePart,
	seat: VehicleSeat,
	bed: BasePart?, -- trucks only: the "Load truck" prompt lives here
	lv: LinearVelocity,
	av: AngularVelocity,
	spec: Spec,
	speed: number,
	cargo: { BasePart },
	kind: string, -- "StarterTruck", "WorkPickup", or "Machine" for equipment
	capacity: number, -- bundles the bed holds (0 = no bed)
	cargoSlot: ((number) -> (CFrame, Vector3))?, -- bundle i (0-based) -> spot in chassis space, size
	-- On-screen pedals/steering (touch). Only accepted from the current driver; expires quickly.
	padThrottle: number,
	padSteer: number,
	padAt: number,
	-- client driving (see setOwner / guard)
	owner: Player?,
	banUntil: number,
	lastGood: CFrame,
	winPos: Vector3,
	winAt: number,
	rider: Humanoid?, -- who sat in the seat last (to put them outside when they get out)
}

-- Top speeds raised 2026-11-12 (owner: "make these trucks faster"): starter 36 -> 58 studs/s (~40 mph on the
-- speedometer), the Work pickup is the faster upgrade at 68 (~46 mph).
local TRUCK_SPEC: Spec = { maxFwd = 58, maxRev = 18, accel = 26, brake = 60, turn = 1.4 }
local PICKUP_SPEC: Spec = { maxFwd = 68, maxRev = 18, accel = 30, brake = 64, turn = 1.25 } -- longer: turns wider
local PAD_TTL = 0.35 -- seconds a touch input stays valid without a refresh
local PAD_MAX_PER_SEC = 40

local S: any
local trucks: { Truck } = {}
local speedFactor = 1 -- chaos: mud during a rain delay slows every vehicle (1 = normal)
local GUARD_WINDOW = 1 -- seconds between the guard's distance checks
local GUARD_SLACK = 1.25 -- how much faster than its top speed a client-driven vehicle may seem to go (lag)

function Vehicle.Init(services)
	S = services
end

local C = Color3.fromRGB
local M = Enum.Material

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function material(name: string?): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and m then m else Enum.Material.WoodPlanks
end

-- Who simulates the vehicle: the player in the driver's seat (allowed to drive it, not on a guard timeout), else the
-- server. Called whenever the seat changes.
local function setOwner(t: Truck)
	local occ = t.seat.Occupant
	local pl = if occ then Players:GetPlayerFromCharacter(occ.Parent) else nil
	if pl and t.spec.role and not S.CrewService.CanDo(pl, t.spec.role) then
		pl = nil
	end
	if pl and os.clock() < t.banUntil then
		pl = nil
	end
	if pl ~= nil and pl == t.owner then
		return
	end
	t.owner = pl
	t.speed = 0
	t.lv.VectorVelocity = Vector3.zero
	t.av.AngularVelocity = Vector3.zero
	t.lastGood = t.chassis.CFrame
	t.winPos = t.chassis.Position
	t.winAt = os.clock()
	pcall(function()
		t.chassis:SetNetworkOwner(pl)
	end)
	t.model:SetAttribute("DriverId", if pl then pl.UserId else nil)
end

-- Getting out (2026-11-12, owner: "it dont let me get out the car"): jumping out of a cab used to bounce the player
-- off the roof back onto the seat, and seats grab whoever touches them. Now the player is put on the ground beside the
-- driver's door (else the other side, else behind the door, else on the roof) and the seat ignores everyone for 1.2 s.
local function placeOutside(t: Truck, hum: Humanoid)
	local char = hum.Parent
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not char:IsA("Model") or not root or hum.Health <= 0 then
		return
	end
	t.seat.Disabled = true
	task.delay(1.2, function()
		if t.seat.Parent then
			t.seat.Disabled = false
		end
	end)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { t.model, char }
	op.RespectCanCollide = true
	local base = t.seat.CFrame
	local groundY = t.chassis.Position.Y - t.chassis.Size.Y / 2 - 0.7 -- the ride balls sit ~0.7 below the chassis
	for _, off in { Vector3.new(-5.5, 0, 0), Vector3.new(5.5, 0, 0), Vector3.new(-5.5, 0, 4), Vector3.new(5.5, 0, 4) } do
		local p = (base * CFrame.new(off)).Position
		local spot = Vector3.new(p.X, groundY + 3.2, p.Z)
		if #workspace:GetPartBoundsInBox(CFrame.new(spot + Vector3.new(0, 0.3, 0)), Vector3.new(2, 4.6, 2), op) == 0 then
			char:PivotTo(CFrame.new(spot) * base.Rotation)
			return
		end
	end
	char:PivotTo(CFrame.new(base.Position + Vector3.new(0, 7, 0)) * base.Rotation) -- boxed in: out through the roof
end

-- Server check on a client-driven vehicle: every GUARD_WINDOW seconds, how far did it really go?
local function guard(t: Truck)
	local now = os.clock()
	local pos = t.chassis.Position
	local flat = (pos - t.winPos) * Vector3.new(1, 0, 1)
	local elapsed = now - t.winAt
	local bad: string? = nil
	if flat.Magnitude > 150 then
		bad = "jumped " .. math.floor(flat.Magnitude) .. " studs"
	elseif pos.Y > t.lastGood.Position.Y + 30 then
		bad = "flew up"
	elseif elapsed >= GUARD_WINDOW then
		local allowed = t.spec.maxFwd * speedFactor * GUARD_SLACK * elapsed + 12
		if flat.Magnitude > allowed then
			bad = ("went %d studs in %.1f s"):format(math.floor(flat.Magnitude), elapsed)
		end
	end
	if bad then
		warn("[Vehicle] took back", t.model.Name, "from", t.owner and t.owner.Name, ":", bad)
		local back = t.lastGood
		t.banUntil = now + 5
		setOwner(t)
		t.chassis.AssemblyLinearVelocity = Vector3.zero
		t.chassis.AssemblyAngularVelocity = Vector3.zero
		t.chassis.CFrame = back
		return
	end
	if elapsed >= GUARD_WINDOW then
		t.winPos = pos
		t.winAt = now
		t.lastGood = t.chassis.CFrame
	end
end

local function hookBoarding(t: Truck)
	local part = t.spec.promptPart
	if not part then
		return
	end
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "BoardPrompt"
	pp.ActionText = t.spec.promptText or "Drive"
	pp.ObjectText = t.model.Name
	pp.HoldDuration = 0.2
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.F
	pp.GamepadKeyCode = Enum.KeyCode.ButtonY
	pp.Parent = part
	S.JobService.RegisterPrompt(pp, function(p: Player)
		if not S.TaskEngine.Guard.Allow(p, "Board", 1) then
			return
		end
		local c = p.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or not root or hum.Health <= 0 or (root.Position - part.Position).Magnitude > 14 then
			return
		end
		local Toast = Net.Event("Toast")
		if t.spec.role and not S.CrewService.CanDo(p, t.spec.role) then
			Toast:FireClient(p, "Only the " .. t.spec.role .. " runs this machine")
			return
		end
		if t.seat.Occupant == hum then
			return -- already in it
		end
		if t.seat.Occupant then
			Toast:FireClient(p, "Someone is already in the seat")
			return
		end
		if S.TaskEngine.Carry.Holding(p) then
			Toast:FireClient(p, "Put down what you're carrying first")
			return
		end
		t.seat:Sit(hum)
	end)
end

-- Makes a built model drivable. The chassis is the physics root; every other part must already be welded to it.
function Vehicle.Register(model: Model, chassis: BasePart, seat: VehicleSeat, spec: Spec): Truck
	local att = Instance.new("Attachment")
	att.Parent = chassis
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(400000, 0, 400000)
	lv.VectorVelocity = Vector3.zero
	lv.Parent = chassis
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.MaxTorque = 10000000
	av.AngularVelocity = Vector3.zero
	av.Parent = chassis

	local t: Truck = {
		model = model,
		chassis = chassis,
		seat = seat,
		bed = nil,
		lv = lv,
		av = av,
		spec = spec,
		speed = 0,
		cargo = {},
		kind = "Machine",
		capacity = 0,
		cargoSlot = nil,
		padThrottle = 0,
		padSteer = 0,
		padAt = 0,
		owner = nil,
		banUntil = 0,
		lastGood = chassis.CFrame,
		winPos = chassis.Position,
		winAt = os.clock(),
		rider = nil,
	}
	table.insert(trucks, t)
	-- the client drive model reads its limits from here
	model:SetAttribute("MaxFwd", spec.maxFwd)
	model:SetAttribute("MaxRev", spec.maxRev)
	model:SetAttribute("Accel", spec.accel)
	model:SetAttribute("Brake", spec.brake)
	model:SetAttribute("Turn", spec.turn)
	model:SetAttribute("SpeedFactor", speedFactor)
	setOwner(t)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		t.padAt = 0
		-- Seats also seat whoever touches them: enforce the trade rule here too, not just on the prompt.
		local occ = seat.Occupant
		local prev = t.rider
		t.rider = occ
		if prev and not occ and Players:GetPlayerFromCharacter(prev.Parent) then
			task.defer(placeOutside, t, prev) -- players only: bots climb out on their own (BotService)
		end
		local pl = if occ then Players:GetPlayerFromCharacter(occ.Parent) else nil
		if pl and spec.role and not S.CrewService.CanDo(pl, spec.role) then
			local w = seat:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
			Net.Event("Toast"):FireClient(pl, "Only the " .. spec.role .. " runs this machine")
		end
		task.defer(setOwner, t)
	end)
	hookBoarding(t)
	return t
end

-- The crew's rusty single-cab pickup. Local frame: -Z is the front, the chassis center is the origin.
-- Returns model, chassis, seat, load bed (prompt part), driver's door. Unparented and not yet drivable.
local function buildStarter(cf: CFrame): (Model, BasePart, VehicleSeat, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = "CrewTruck"
	local body = C(150, 70, 45)
	local dark = C(38, 38, 40)
	local chrome = C(195, 195, 200)
	local glass = C(120, 160, 190)

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(6.2, 0.8, 14.6)
	chassis.CFrame = cf
	chassis.Color = dark
	chassis.Material = M.Metal
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1.5, 0, 0, 100, 0)
	chassis.Parent = model

	local function add(name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf * lcf
		p.Color = color
		p.Material = mat
		p.Massless = true
		p.CanCollide = collide ~= false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		weld(chassis, p)
		return p
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end

	-- Low, frictionless skid is what touches the ground; the wheels are visual.
	local skid = add("Skid", Vector3.new(6.6, 0.4, 13), at(0, -0.9, 0), dark, M.Metal)
	skid.Transparency = 1
	skid.Massless = false
	skid.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 100, 0)

	-- Wheels: tire, rim, hub, plus fender arches
	for _, wz in { -4.7, 4.6 } do
		for _, side in { -1, 1 } do
			local tire = add("Tire", Vector3.new(1.1, 2.3, 2.3), at(side * 3.35, -0.05, wz), dark, M.Rubber, false)
			tire.Shape = Enum.PartType.Cylinder
			local rim = add("Rim", Vector3.new(1.15, 1.35, 1.35), at(side * 3.36, -0.05, wz), chrome, M.Metal, false)
			rim.Shape = Enum.PartType.Cylinder
			local hub = add("Hub", Vector3.new(1.2, 0.5, 0.5), at(side * 3.37, -0.05, wz), dark, M.Metal, false)
			hub.Shape = Enum.PartType.Cylinder
			add("Fender", Vector3.new(1.3, 0.35, 3.0), at(side * 3.35, 1.3, wz), body, M.Metal)
		end
	end

	-- Front end: hood, grille, bumper, headlights
	add("Hood", Vector3.new(6.2, 1.4, 4.4), at(0, 1.1, -5.0), body, M.Metal)
	add("Grille", Vector3.new(4.8, 1.2, 0.15), at(0, 1.0, -7.25), C(55, 55, 58), M.DiamondPlate)
	add("FrontBumper", Vector3.new(6.8, 0.6, 0.5), at(0, 0.15, -7.5), chrome, M.Metal)
	for _, side in { -1, 1 } do
		add("HeadlightGlass", Vector3.new(1.1, 0.8, 0.12), at(side * 2.35, 1.3, -7.27), glass, M.Glass, false).Transparency = 0.3
		local lamp = add("Headlight", Vector3.new(0.85, 0.55, 0.1), at(side * 2.35, 1.3, -7.22), C(255, 245, 220), M.Neon, false)
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Range = 45
		beam.Angle = 65
		beam.Brightness = 2
		beam.Color = C(255, 240, 215)
		beam.Shadows = false
		beam.Parent = lamp
	end

	-- Cab: back wall, roof, pillars, windshield, doors with windows, dash, wheel, mirrors, seats
	add("CabBack", Vector3.new(6.2, 4.8, 0.3), at(0, 2.8, 0.85), body, M.Metal)
	add("CabRoof", Vector3.new(6.2, 0.3, 4.0), at(0, 5.2, -0.9), body, M.Metal)
	add("Cowl", Vector3.new(6.2, 0.6, 0.3), at(0, 2.1, -2.75), body, M.Metal)
	add("Windshield", Vector3.new(5.8, 2.6, 0.2), at(0, 3.75, -2.75), glass, M.Glass).Transparency = 0.5
	for _, side in { -1, 1 } do
		add("APillar", Vector3.new(0.3, 3.2, 0.3), at(side * 3.0, 3.6, -2.75), body, M.Metal)
		add("BPillar", Vector3.new(0.3, 4.8, 0.3), at(side * 3.0, 2.8, 0.75), body, M.Metal)
		add("Door", Vector3.new(0.25, 2.2, 3.2), at(side * 3.1, 1.5, -0.95), body, M.Metal)
		add("SideWindow", Vector3.new(0.2, 2.4, 3.2), at(side * 3.1, 3.8, -0.95), glass, M.Glass).Transparency = 0.55
		add("DoorHandle", Vector3.new(0.15, 0.15, 0.5), at(side * 3.25, 2.2, 0.2), chrome, M.Metal, false)
		add("MirrorArm", Vector3.new(0.6, 0.1, 0.1), at(side * 3.35, 3.4, -2.5), dark, M.Metal, false)
		add("Mirror", Vector3.new(0.2, 0.7, 0.45), at(side * 3.7, 3.4, -2.5), dark, M.Metal, false)
	end
	add("Dashboard", Vector3.new(5.8, 0.8, 0.7), at(0, 2.4, -2.3), C(45, 45, 48), M.Rubber, false)
	add("SteeringWheel", Vector3.new(0.15, 1.3, 1.3), at(-1.4, 2.9, -1.8) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, 0.5),
		dark, M.Rubber, false).Shape = Enum.PartType.Cylinder
	add("Bench", Vector3.new(2.2, 1, 2), at(1.4, 0.9, -0.9), C(90, 60, 45), M.Fabric, false)
	add("Backrest", Vector3.new(5.6, 1.8, 0.4), at(0, 2.2, 0.5), C(90, 60, 45), M.Fabric, false)
	-- Rust patches (it's the starter truck)
	for _, side in { -1, 1 } do
		add("Rust", Vector3.new(0.04, 0.7, 1.1), at(side * 3.24, 1.0, -1.7), C(120, 70, 40), M.CorrodedMetal, false)
	end
	add("Rust", Vector3.new(1.5, 0.04, 1.2), at(1.4, 1.82, -5.6), C(120, 70, 40), M.CorrodedMetal, false)
	add("Rust", Vector3.new(0.04, 0.6, 1.4), at(-3.27, 1.0, 5.6), C(120, 70, 40), M.CorrodedMetal, false)

	-- Bed: floor, sides with rails, front wall, tailgate, taillights, bumper, plate, exhaust
	add("BedFloor", Vector3.new(6.0, 0.3, 6.4), at(0, 0.55, 4.2), C(70, 70, 72), M.DiamondPlate)
	for _, side in { -1, 1 } do
		add("BedSide", Vector3.new(0.3, 1.6, 6.4), at(side * 3.1, 1.5, 4.2), body, M.Metal)
		add("BedRail", Vector3.new(0.4, 0.15, 6.4), at(side * 3.1, 2.35, 4.2), chrome, M.Metal, false)
		add("Taillight", Vector3.new(0.4, 0.9, 0.15), at(side * 3.0, 1.6, 7.47), C(220, 30, 30), M.Neon, false)
	end
	add("BedFront", Vector3.new(6.2, 1.6, 0.3), at(0, 1.5, 1.15), body, M.Metal)
	add("Tailgate", Vector3.new(6.2, 1.6, 0.3), at(0, 1.5, 7.3), body, M.Metal)
	add("TailgateHandle", Vector3.new(1, 0.2, 0.1), at(0, 2.0, 7.47), chrome, M.Metal, false)
	add("RearBumper", Vector3.new(6.6, 0.5, 0.5), at(0, 0.15, 7.6), chrome, M.Metal)
	local plate = add("Plate", Vector3.new(1.8, 0.9, 0.08), at(0, 0.75, 7.88), C(240, 240, 235), M.Metal, false)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = C(30, 50, 120)
	text.Text = "CREW 01"
	text.Parent = sg
	sg.Parent = plate
	add("Exhaust", Vector3.new(2.5, 0.35, 0.35), at(2.3, -0.45, 6.2) * CFrame.Angles(0, math.pi / 2, 0), C(90, 90, 92), M.Metal, false).Shape =
		Enum.PartType.Cylinder

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = cf * at(-1.4, 0.9, -0.9)
	seat.Color = C(90, 60, 45)
	seat.Material = M.Fabric
	seat.HeadsUpDisplay = false
	seat.Massless = true
	seat.Parent = model
	weld(chassis, seat)

	local bed = add("LoadBed", Vector3.new(6.0, 3, 6.4), at(0, 2.2, 4.2), dark, M.Metal, false)
	bed.Transparency = 1
	bed.CanQuery = false
	bed.CanTouch = false

	local door = model:FindFirstChild("Door") :: BasePart
	for _, d in model:GetChildren() do
		if d.Name == "Door" and d:IsA("BasePart") and (cf:PointToObjectSpace(d.Position)).X < 0 then
			door = d -- driver's (left) door
		end
	end

	model.PrimaryPart = chassis
	return model, chassis, seat, bed, door
end

-- The Work pickup: white crew cab, orange stripe, roof light bar, headache rack, wooden stake-side flatbed with
-- underbody toolboxes. Same local frame and ride height as the starter truck (skid at y -0.9).
local function buildWorkPickup(cf: CFrame): (Model, BasePart, VehicleSeat, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = "CrewTruck"
	local body = C(236, 236, 230)
	local stripe = C(240, 130, 30)
	local dark = C(36, 36, 38)
	local steel = C(170, 172, 176)
	local glass = C(110, 150, 180)

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(6.6, 0.8, 18)
	chassis.CFrame = cf
	chassis.Color = dark
	chassis.Material = M.Metal
	chassis.CustomPhysicalProperties = PhysicalProperties.new(1.5, 0, 0, 100, 0)
	chassis.Parent = model

	local function add(name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf * lcf
		p.Color = color
		p.Material = mat
		p.Massless = true
		p.CanCollide = collide ~= false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		weld(chassis, p)
		return p
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end
	local function label(part: BasePart, face: Enum.NormalId, text: string, color: Color3)
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.LightInfluence = 0.4
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = color
		t.Text = text
		t.Parent = sg
		sg.Parent = part
	end

	local skid = add("Skid", Vector3.new(7, 0.4, 16.4), at(0, -0.9, 0), dark, M.Metal)
	skid.Transparency = 1
	skid.Massless = false
	skid.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 100, 0)

	-- Wheels (bigger all-terrain tires), front fender flares, mud flaps
	for _, wz in { -5.9, 5.4 } do
		for _, side in { -1, 1 } do
			local tire = add("Tire", Vector3.new(1.25, 2.5, 2.5), at(side * 3.5, 0.05, wz), dark, M.Rubber, false)
			tire.Shape = Enum.PartType.Cylinder
			local rim = add("Rim", Vector3.new(1.3, 1.5, 1.5), at(side * 3.51, 0.05, wz), steel, M.Metal, false)
			rim.Shape = Enum.PartType.Cylinder
			local hub = add("Hub", Vector3.new(1.35, 0.55, 0.55), at(side * 3.52, 0.05, wz), dark, M.Metal, false)
			hub.Shape = Enum.PartType.Cylinder
		end
	end
	for _, side in { -1, 1 } do
		add("FenderFlare", Vector3.new(1.4, 0.4, 3.3), at(side * 3.45, 1.5, -5.9), dark, M.Rubber)
		add("MudFlap", Vector3.new(1.2, 1.2, 0.1), at(side * 3.5, 0.25, 7.0), dark, M.Rubber, false)
	end

	-- Front end: hood, grille, steel ranch bumper with red tow hooks, headlights
	add("Hood", Vector3.new(6.6, 1.7, 4.4), at(0, 1.35, -6.7), body, M.Metal)
	add("HoodScoop", Vector3.new(2.2, 0.25, 1.6), at(0, 2.3, -6.4), body, M.Metal, false)
	add("Grille", Vector3.new(5.0, 1.3, 0.15), at(0, 1.3, -8.95), C(50, 50, 54), M.DiamondPlate)
	add("FrontBumper", Vector3.new(7.2, 0.8, 0.6), at(0, 0.3, -9.25), dark, M.Metal)
	for _, side in { -1, 1 } do
		add("TowHook", Vector3.new(0.3, 0.5, 0.35), at(side * 2.2, 0.3, -9.65), C(200, 30, 30), M.Metal, false)
		add("HeadlightGlass", Vector3.new(1.2, 0.8, 0.12), at(side * 2.45, 1.6, -8.98), glass, M.Glass, false).Transparency = 0.3
		local lamp = add("Headlight", Vector3.new(0.95, 0.55, 0.1), at(side * 2.45, 1.6, -8.93), C(255, 245, 220), M.Neon, false)
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Range = 50
		beam.Angle = 65
		beam.Brightness = 2.2
		beam.Color = C(255, 240, 215)
		beam.Shadows = false
		beam.Parent = lamp
		add("HoodStripe", Vector3.new(0.05, 0.3, 4.2), at(side * 3.31, 1.75, -6.7), stripe, M.Metal, false)
	end

	-- Crew cab: 4 doors, rear window, roof light bar, tow mirrors, step bars
	add("Cowl", Vector3.new(6.6, 0.6, 0.3), at(0, 2.35, -4.5), body, M.Metal)
	add("Windshield", Vector3.new(6.2, 2.6, 0.2), at(0, 3.95, -4.5), glass, M.Glass).Transparency = 0.5
	add("CabRoof", Vector3.new(6.6, 0.3, 6.0), at(0, 5.4, -1.4), body, M.Metal)
	add("CabBackLower", Vector3.new(6.6, 3.2, 0.3), at(0, 2.0, 1.75), body, M.Metal)
	add("RearWindow", Vector3.new(4.4, 1.6, 0.2), at(0, 4.45, 1.75), glass, M.Glass).Transparency = 0.5
	for _, side in { -1, 1 } do
		add("CabBackSide", Vector3.new(1.1, 1.6, 0.3), at(side * 2.75, 4.45, 1.75), body, M.Metal)
		add("APillar", Vector3.new(0.3, 3.2, 0.3), at(side * 3.2, 3.8, -4.5), body, M.Metal)
		add("BPillar", Vector3.new(0.3, 5.0, 0.3), at(side * 3.2, 2.9, -1.35), body, M.Metal)
		add("Door", Vector3.new(0.25, 2.3, 3.0), at(side * 3.3, 1.6, -2.9), body, M.Metal)
		add("SideWindow", Vector3.new(0.2, 2.4, 3.0), at(side * 3.3, 3.95, -2.9), glass, M.Glass).Transparency = 0.55
		add("RearDoor", Vector3.new(0.25, 2.3, 2.9), at(side * 3.3, 1.6, 0.2), body, M.Metal)
		add("RearSideWindow", Vector3.new(0.2, 2.4, 2.9), at(side * 3.3, 3.95, 0.2), glass, M.Glass).Transparency = 0.55
		add("DoorHandle", Vector3.new(0.15, 0.15, 0.5), at(side * 3.45, 2.3, -1.8), steel, M.Metal, false)
		add("RearDoorHandle", Vector3.new(0.15, 0.15, 0.5), at(side * 3.45, 2.3, 1.2), steel, M.Metal, false)
		add("Stripe", Vector3.new(0.05, 0.3, 5.9), at(side * 3.44, 2.55, -1.35), stripe, M.Metal, false)
		local decal = add("DoorDecal", Vector3.new(0.05, 0.9, 2.6), at(side * 3.44, 1.55, -2.9), body, M.Metal, false)
		decal.Transparency = 1
		label(decal, if side < 0 then Enum.NormalId.Left else Enum.NormalId.Right, "CO-OP\nCONSTRUCTION", stripe)
		add("StepBar", Vector3.new(0.5, 0.25, 6.0), at(side * 3.7, 0.3, -1.3), dark, M.Metal)
		add("MirrorArm", Vector3.new(0.8, 0.1, 0.1), at(side * 3.6, 3.5, -4.1), dark, M.Metal, false)
		add("TowMirror", Vector3.new(0.2, 1.1, 0.6), at(side * 4.05, 3.5, -4.1), dark, M.Metal, false)
	end
	add("LightBarBase", Vector3.new(4.4, 0.25, 0.6), at(0, 5.65, -3.6), dark, M.Metal, false)
	for _, x in { -1.6, -0.55, 0.55, 1.6 } do
		add("LightBar", Vector3.new(0.9, 0.3, 0.45), at(x, 5.9, -3.6), C(255, 160, 30), M.Neon, false)
	end
	-- Interior
	add("Dashboard", Vector3.new(6.2, 0.8, 0.7), at(0, 2.5, -4.1), C(45, 45, 48), M.Rubber, false)
	add("SteeringWheel", Vector3.new(0.15, 1.3, 1.3), at(-1.5, 3.0, -3.5) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, 0.5),
		dark, M.Rubber, false).Shape = Enum.PartType.Cylinder
	add("PassengerSeat", Vector3.new(2.2, 1, 2), at(1.5, 1.0, -2.6), C(60, 62, 68), M.Fabric, false)
	for _, x in { -1.5, 1.5 } do
		add("FrontBackrest", Vector3.new(2.2, 1.8, 0.4), at(x, 2.3, -1.5), C(60, 62, 68), M.Fabric, false)
	end
	add("RearBench", Vector3.new(5.8, 1, 1.8), at(0, 1.0, 0.4), C(60, 62, 68), M.Fabric, false)
	add("RearBackrest", Vector3.new(5.8, 1.8, 0.4), at(0, 2.3, 1.4), C(60, 62, 68), M.Fabric, false)

	-- Headache rack with two work lights
	for _, side in { -1, 1 } do
		add("RackPost", Vector3.new(0.3, 4.4, 0.3), at(side * 3.15, 3.9, 2.25), dark, M.Metal)
	end
	add("RackTop", Vector3.new(6.6, 0.3, 0.3), at(0, 6.1, 2.25), dark, M.Metal)
	for _, y in { 2.6, 3.5, 4.4, 5.3 } do
		add("RackBar", Vector3.new(6.0, 0.15, 0.15), at(0, y, 2.25), dark, M.Metal, false)
	end
	for _, side in { -1, 1 } do
		add("WorkLight", Vector3.new(0.7, 0.5, 0.3), at(side * 2.2, 6.45, 2.25), C(255, 245, 225), M.Neon, false)
	end

	-- Stake-side flatbed: wooden deck on frame rails, stake posts and rails, toolboxes under the deck
	add("Deck", Vector3.new(7.2, 0.3, 7.4), at(0, 1.55, 5.65), C(140, 100, 60), M.WoodPlanks)
	for _, x in { -2.6, 2.6 } do
		add("FrameRail", Vector3.new(0.4, 0.4, 7.4), at(x, 1.2, 5.65), dark, M.Metal, false)
	end
	for _, side in { -1, 1 } do
		for _, z in { 2.3, 4.5, 6.8, 9.0 } do
			add("StakePost", Vector3.new(0.3, 1.7, 0.3), at(side * 3.45, 2.55, z), C(120, 85, 50), M.Wood)
		end
		for _, y in { 2.3, 3.2 } do
			add("StakeRail", Vector3.new(0.2, 0.3, 7.0), at(side * 3.45, y, 5.65), C(120, 85, 50), M.Wood)
		end
		local box = add("Toolbox", Vector3.new(0.9, 1.0, 2.0), at(side * 3.25, 0.8, 3.0), steel, M.DiamondPlate)
		add("ToolboxHandle", Vector3.new(0.1, 0.12, 0.6), at(side * 3.72, 1.05, 3.0), dark, M.Metal, false)
		box.Name = "Toolbox"
		add("Taillight", Vector3.new(0.4, 0.6, 0.15), at(side * 3.3, 1.2, 9.4), C(220, 30, 30), M.Neon, false)
	end
	add("RearBumper", Vector3.new(7.2, 0.6, 0.5), at(0, 0.4, 9.5), dark, M.Metal)
	add("Hitch", Vector3.new(0.5, 0.5, 0.8), at(0, 0.4, 9.95), dark, M.Metal, false)
	local plate = add("Plate", Vector3.new(1.8, 0.7, 0.08), at(0, 1.05, 9.42), C(240, 240, 235), M.Metal, false)
	label(plate, Enum.NormalId.Back, "CREW 02", C(30, 50, 120))
	add("Exhaust", Vector3.new(2.5, 0.35, 0.35), at(2.4, -0.45, 7.8) * CFrame.Angles(0, math.pi / 2, 0), C(90, 90, 92), M.Metal, false).Shape =
		Enum.PartType.Cylinder

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = cf * at(-1.5, 1.0, -2.6)
	seat.Color = C(60, 62, 68)
	seat.Material = M.Fabric
	seat.HeadsUpDisplay = false
	seat.Massless = true
	seat.Parent = model
	weld(chassis, seat)

	local bed = add("LoadBed", Vector3.new(7.2, 3, 7.4), at(0, 3.2, 5.65), dark, M.Metal, false)
	bed.Transparency = 1
	bed.CanQuery = false
	bed.CanTouch = false

	local door = model:FindFirstChild("Door") :: BasePart
	for _, d in model:GetChildren() do
		if d.Name == "Door" and d:IsA("BasePart") and (cf:PointToObjectSpace(d.Position)).X < 0 then
			door = d -- driver's (front left) door
		end
	end
	model.PrimaryPart = chassis
	return model, chassis, seat, bed, door
end

-- Truck kinds: builder, driving spec, where bundle i sits on the bed (chassis space) and its size.
type Kind = {
	build: (CFrame) -> (Model, BasePart, VehicleSeat, BasePart, BasePart),
	spec: Spec,
	cargo: (number) -> (CFrame, Vector3),
}
local KINDS: { [string]: Kind } = {
	StarterTruck = {
		build = buildStarter,
		spec = TRUCK_SPEC,
		cargo = function(i: number): (CFrame, Vector3) -- 2 side by side, stacked
			local layer, side = i // 2, i % 2
			return CFrame.new(if side == 0 then -1.45 else 1.45, 1.2 + layer * 1.05, 4.2), Vector3.new(2.7, 1, 6.0)
		end,
	},
	WorkPickup = {
		build = buildWorkPickup,
		spec = PICKUP_SPEC,
		cargo = function(i: number): (CFrame, Vector3) -- 3 across on the flatbed, stacked
			local layer, col = i // 3, i % 3
			return CFrame.new((col - 1) * 2.2, 2.2 + layer * 1.05, 5.65), Vector3.new(2.1, 1, 6.0)
		end,
	},
}

-- Real (mesh) looks: ServerStorage.VehicleModels holds one Model per look, placed so its pivot is the rig's local
-- origin (front = -Z). Skin clones one onto `frame`; its parts don't collide and weigh nothing, so the part-built
-- rig underneath still does the physics, seats, prompts and hitboxes. Returns nil when there's no such model
-- (the part-built look stays).
function Vehicle.Skin(name: string, frame: CFrame, parent: Instance): (Model?, { BasePart })
	local folder = ServerStorage:FindFirstChild("VehicleModels")
	local template = folder and folder:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil, {}
	end
	local m = template:Clone()
	m.Name = "Skin_" .. name
	m:PivotTo(frame)
	local parts: { BasePart } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			table.insert(parts, d)
		end
	end
	m.Parent = parent
	return m, parts
end

-- A look's settings (its attributes, e.g. the crane's turret axis and boom hinge), or nil when there's no such model.
function Vehicle.SkinInfo(name: string): { [string]: any }?
	local folder = ServerStorage:FindFirstChild("VehicleModels")
	local template = folder and folder:FindFirstChild(name)
	return if template then template:GetAttributes() else nil
end

-- Hides a rig's part-built look once a skin covers it. The parts keep colliding (they are the hitbox); their text
-- and decals are hidden too. Instances in `skip` (the skins, the crane hook...) are left alone.
function Vehicle.HideBuilt(model: Instance, skip: { [Instance]: boolean })
	local function walk(inst: Instance)
		for _, d in inst:GetChildren() do
			if skip[d] then
				continue
			end
			if d:IsA("BasePart") then
				d.Transparency = 1
				d.CastShadow = false
			elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
				d.Enabled = false
			elseif d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 1
			end
			walk(d)
		end
	end
	walk(model)
end

-- A wheel mesh (Wheel_FL / FR / RL / RR in the look) hangs on a Motor6D whose frame is the chassis axes at the wheel
-- center, so a client can spin it (about X) and steer the front ones (about Y) with Motor6D.Transform
-- (WheelController). Radius and Front ride along as attributes.
local function wheelMotor(chassis: BasePart, wheel: BasePart)
	local axle = chassis.CFrame.Rotation + wheel.Position
	local m = Instance.new("Motor6D")
	m.Name = "WheelMotor"
	m.Part0 = chassis
	m.Part1 = wheel
	m.C0 = chassis.CFrame:ToObjectSpace(axle)
	m.C1 = wheel.CFrame:ToObjectSpace(axle)
	m:SetAttribute("Front", wheel.Name == "Wheel_FL" or wheel.Name == "Wheel_FR")
	m:SetAttribute("Radius", math.max(wheel.Size.Y, wheel.Size.Z) / 2)
	m.Parent = wheel
end

-- The truck rides on 4 invisible, frictionless balls at its wheels instead of the flat Skid box: a ball rolls up over
-- a curb or a bump where a box edge catches and stops dead. (The drive model sets the velocity, so no slipping.)
local function rideOnBalls(model: Model, chassis: BasePart, parts: { BasePart })
	for _, p in parts do
		if string.sub(p.Name, 1, 6) == "Wheel_" then
			local ball = Instance.new("Part")
			ball.Name = "RideBall"
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.one * p.Size.Y
			ball.CFrame = CFrame.new(p.Position)
			ball.Transparency = 1
			ball.CanQuery = false
			ball.CanTouch = false
			ball.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 100)
			ball.Parent = model
			weld(chassis, ball)
		end
	end
	local skid = model:FindFirstChild("Skid", true)
	if skid and skid:IsA("BasePart") then
		skid.CanCollide = false
	end
end

-- Invisible frictionless ride balls (one per point, welded to the chassis) for any drivable rig, e.g. the crane while
-- it's on its wheels (EquipmentService). Returns the balls.
function Vehicle.AddRideBalls(model: Model, chassis: BasePart, points: { Vector3 }, diameter: number): { BasePart }
	local out = {}
	for _, at in points do
		local ball = Instance.new("Part")
		ball.Name = "RideBall"
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * diameter
		ball.CFrame = CFrame.new(at)
		ball.Transparency = 1
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 100)
		ball.Parent = model
		weld(chassis, ball)
		table.insert(out, ball)
	end
	return out
end

-- Puts a truck's mesh look on: welded to the chassis (wheels on motors), or anchored for the showroom copy.
-- Returns the wheelbase (front to rear axle) when the look has wheels.
local function skinTruck(model: Model, chassis: BasePart, kind: string, anchored: boolean): number?
	local skin, parts = Vehicle.Skin(kind, chassis.CFrame, model)
	if not skin then
		return nil
	end
	Vehicle.HideBuilt(model, { [skin] = true })
	local front, rear = {}, {}
	for _, p in parts do
		if anchored then
			p.Anchored = true
		elseif string.sub(p.Name, 1, 6) == "Wheel_" then
			wheelMotor(chassis, p)
			local z = chassis.CFrame:PointToObjectSpace(p.Position).Z
			table.insert(if z < 0 then front else rear, z)
		else
			weld(chassis, p)
		end
	end
	if #front > 0 and #rear > 0 then
		CollectionService:AddTag(model, "SpinWheels")
		if not anchored then
			rideOnBalls(model, chassis, parts)
		end
		return math.abs(rear[1] - front[1])
	end
	return nil
end

-- Spawns a drivable crew truck of `kind` (default: the starter truck).
function Vehicle.SpawnTruck(cf: CFrame, parent: Instance, kind: string?): Truck
	local k = if kind and KINDS[kind] and VehiclesConfig[kind] then kind else "StarterTruck"
	local def = KINDS[k]
	local model, chassis, seat, bed, door = def.build(cf)
	local wheelbase = skinTruck(model, chassis, k, false)
	model:SetAttribute("TruckKind", k)
	model:SetAttribute("Wheelbase", wheelbase or 9) -- the client turns trucks like a car (bicycle model)
	model.Parent = parent
	local spec = table.clone(def.spec)
	spec.promptPart = door
	spec.promptText = "Drive truck"
	local t = Vehicle.Register(model, chassis, seat, spec)
	t.bed = bed
	t.kind = k
	t.capacity = VehiclesConfig[k].Capacity
	t.cargoSlot = def.cargo
	return t
end

-- A showroom copy (anchored, no seat, not drivable) for the truck dealer.
function Vehicle.BuildDisplay(kind: string, cf: CFrame, parent: Instance): Model?
	local def = KINDS[kind]
	if not def then
		return nil
	end
	local model, chassis, seat, bed = def.build(cf)
	seat:Destroy()
	bed:Destroy()
	skinTruck(model, chassis, kind, true)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("SpotLight") then
			d.Enabled = false
		end
	end
	model.Name = "Display_" .. kind
	model.Parent = parent
	return model
end

function Vehicle.Capacity(t: Truck): number
	return t.capacity
end

-- Chaos: mud during a rain delay slows every vehicle (1 = normal). Client-driven ones read the attribute.
function Vehicle.SetSpeedFactor(f: number)
	speedFactor = math.clamp(f, 0.2, 1)
	for _, t in trucks do
		t.model:SetAttribute("SpeedFactor", speedFactor)
	end
end

-- Autopilot input for bots: the same throttle/steer path as the on-screen pedals (expires after PAD_TTL).
function Vehicle.Drive(t: Truck, throttle: number, steer: number)
	t.padThrottle = math.clamp(throttle, -1, 1)
	t.padSteer = math.clamp(steer, -1, 1)
	t.padAt = os.clock()
end

-- Stacks one bundle in the bed (layout per truck kind). Returns false when the truck is full.
function Vehicle.AddCargo(t: Truck, item: string, def: any): boolean
	local slot = t.cargoSlot
	if not slot or #t.cargo >= t.capacity then
		return false
	end
	local lcf, size = slot(#t.cargo)
	local c = Instance.new("Part")
	c.Name = "Cargo"
	c.Size = size
	c.CFrame = t.chassis.CFrame * lcf
	c.Color = def.Color
	c.Material = material(def.Material)
	c.Massless = true
	c:SetAttribute("Item", item)
	c.Parent = t.model
	weld(t.chassis, c)
	table.insert(t.cargo, c)
	return true
end

function Vehicle.CargoCounts(t: Truck): { [string]: number }
	local out: { [string]: number } = {}
	for _, c in t.cargo do
		local item = c:GetAttribute("Item")
		if c.Parent and typeof(item) == "string" then
			out[item] = (out[item] or 0) + 1
		end
	end
	return out
end

function Vehicle.HasCargo(t: Truck): boolean
	return #t.cargo > 0
end

-- Empties the bed and returns what was in it.
function Vehicle.UnloadAll(t: Truck): { [string]: number }
	local out = Vehicle.CargoCounts(t)
	for _, c in t.cargo do
		c:Destroy()
	end
	table.clear(t.cargo)
	return out
end

function Vehicle.Position(t: Truck): Vector3
	return t.chassis.Position
end

function Vehicle.DespawnAll()
	for _, t in trucks do
		t.model:Destroy()
	end
	table.clear(trucks)
end

local function moveToward(a: number, b: number, step: number): number
	if a < b then
		return math.min(a + step, b)
	end
	return math.max(a - step, b)
end

local function driverOf(t: Truck): Player?
	local occ = t.seat.Occupant
	return if occ then Players:GetPlayerFromCharacter(occ.Parent) else nil
end

local function axis(v: unknown): number?
	if typeof(v) ~= "number" or v ~= v then
		return nil
	end
	return math.clamp(v, -1, 1)
end

local budget: { [Player]: { t: number, n: number } } = {}
local function allowPad(p: Player): boolean
	local now = os.clock()
	local b = budget[p]
	if not b or now - b.t >= 1 then
		budget[p] = { t = now, n = 1 }
		return true
	end
	b.n += 1
	return b.n <= PAD_MAX_PER_SEC
end

function Vehicle.Start()
	Net.Event("DriveInput").OnServerEvent:Connect(function(p: Player, throttle: unknown, steer: unknown)
		if not allowPad(p) then
			return
		end
		local th, st = axis(throttle), axis(steer)
		if th == nil or st == nil then
			warn("[Vehicle] bad DriveInput from", p.Name)
			return
		end
		for _, t in trucks do
			if driverOf(t) == p then
				t.padThrottle = th
				t.padSteer = st
				t.padAt = os.clock()
				return
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		budget[p] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		for i = #trucks, 1, -1 do
			local t = trucks[i]
			if not t.model.Parent then
				table.remove(trucks, i)
				continue
			end
			local spec = t.spec
			local driven = t.seat.Occupant ~= nil
			if t.owner then
				-- a player drives it on their client: just watch
				if not driven or t.owner.Parent == nil then
					setOwner(t)
				else
					guard(t)
				end
				continue
			elseif driven and t.banUntil > 0 and os.clock() >= t.banUntil then
				t.banUntil = 0
				setOwner(t) -- guard timeout over: hand it back
			end
			local throttle = if driven then t.seat.ThrottleFloat else 0
			local steer = if driven then t.seat.SteerFloat else 0
			if driven and os.clock() - t.padAt < PAD_TTL then
				if t.padThrottle ~= 0 then
					throttle = t.padThrottle
				end
				if t.padSteer ~= 0 then
					steer = t.padSteer
				end
			end
			local target = (if throttle > 0 then throttle * spec.maxFwd else throttle * spec.maxRev) * speedFactor
			local braking = target == 0 or (t.speed ~= 0 and math.sign(target) ~= math.sign(t.speed))
			t.speed = moveToward(t.speed, target, (if braking then spec.brake else spec.accel) * dt)

			local look = t.chassis.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.01 then
				flat = flat.Unit
			end
			t.lv.VectorVelocity = flat * t.speed
			-- wheels need speed to turn; tracks (machines without a wheelbase) turn on the spot
			local grip = if t.kind == "Machine" and t.model:GetAttribute("Wheelbase") == nil then 1
				else math.clamp(math.abs(t.speed) / 6, 0, 1)
			local dir = if t.speed >= 0 then 1 else -1
			t.av.AngularVelocity = Vector3.new(0, -steer * spec.turn * grip * dir, 0)
		end
	end)
end

return Vehicle
