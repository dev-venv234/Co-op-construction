--!strict
-- Heavy equipment on the job sites, spawned with each job at the blueprint's Equipment spots:
--  * Excavator (tracked, drivable through VehicleService): digs pier/post holes.
--  * Mobile crane: lifts roof sections on the bigger houses. It arrives on its wheels ~50 studs from its CRANE PAD
--    (owner, 2026-11-12: "i wish the crane could be driveable"); the Operator drives it (Drive crane, VehicleService)
--    onto the glowing pad and stops, and it sets up on its outriggers. No room to arrive -> it starts set up.
-- Hands-on controls (owner, 2026-11-12: "we could control the movements of the crane and digger", chose full manual
-- with a guide): the machines move only from their operator's controls (MachineInput remote: swing / boom / hook for
-- the crane, arm for the excavator; client MachineController), simulated here on the server. Machine tasks are done
-- by hand:
--  * Dig: drive the excavator so the bucket reaches the glowing hole, lower the arm into it and lift it out, 3 times.
--  * Lift: lower the hook onto the roof section waiting on the ground (it hooks on), swing it over the glowing outline
--    and lower it; it sets down by itself once it's lined up.
-- The grade is how close the bucket / load was to the target (1.0 dead on, 0.5 at the edge of the tolerance). Bots use
-- the same controls through Autopilot, with some aim error. Machine tasks only start when the actor is in that
-- machine's seat and within its reach (server check).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Util.Net)

local Equipment = {}

type Rel = { part: BasePart, rel: CFrame }
export type Rig = {
	kind: string,
	model: Model,
	seat: Seat,
	anchor: BasePart,
	reach: number,
	busy: boolean,
	home: CFrame?, -- where it was parked at the start (bots park the excavator back here when its work is done)
	-- excavator
	base: BasePart?,
	armWeld: Weld?,
	armRest: CFrame?,
	digging: boolean?,
	vehicle: any, -- its VehicleService record (excavator; crane while on its wheels)
	boardPart: BasePart?, -- where the "Operate" prompt is
	pitch: number?, -- arm angle (0 = rest, down is negative)
	bucket: BasePart?, -- its bottom digs
	-- crane
	frame: CFrame?, -- turret pivot at rest (world)
	turretOffset: CFrame?,
	turret: { Rel }?,
	boom: { Rel }?,
	boomPivot: Vector3?, -- in turret space
	boomLen: number?,
	yaw: number?,
	luff: number?,
	drop: number?,
	hook: BasePart?,
	cable: BasePart?,
	load: BasePart?,
	loadTurn: number?, -- the load's heading relative to the boom
	restLuff: number?, -- boom angle when idle (a mesh look rests its boom stowed flat)
	hookPos: Vector3?, -- hook block center (updateCrane)
	tipY: number?, -- boom tip height (updateCrane)
	mode: string?, -- "drive" (on its wheels), "setting", "set" (on its outriggers: can lift)
	pad: BasePart?, -- the CRANE PAD it sets up on
	driveSeat: VehicleSeat?,
	driveParts: { Instance }?, -- welds and ride balls used while driving
	still: number?,
	lastPos: Vector3?,
	-- hands-on control
	input: { a: number, b: number, c: number, at: number }?,
	session: any?, -- the machine task being done by hand (see BeginManual)
	auto: boolean?, -- a canned motion is playing (controls ignored)
	attrAt: number?,
}

local S: any
local rigs: { Rig } = {}
local pads: { BasePart } = {}

local C = Color3.fromRGB
local M = Enum.Material
local YELLOW = C(236, 176, 28)
local DEEP_YELLOW = C(205, 145, 20)
local DARK = C(40, 40, 42)
local STEEL = C(120, 122, 126)
local CHROME = C(200, 200, 205)
local GLASS = C(110, 150, 175)
local WHITE = C(232, 232, 226)

-- hands-on controls
local INPUT_TTL = 0.35 -- seconds an input stays valid without a refresh
local INPUT_MAX_PER_SEC = 40
local SWING_RATE = 0.5 -- rad/s
local LUFF_RATE = 0.28 -- rad/s
local HOIST_RATE = 7 -- studs/s
local LUFF_MIN, LUFF_MAX = 0.2, 1.35
local ARM_RATE = 0.9 -- rad/s
local ARM_MIN, ARM_MAX = -0.55, 0.45
local SCOOPS = 3
local DIG_TOL = 3 -- studs: how close to the hole center the bucket has to go in
local LIFT_TOL = 2.5 -- studs: how close over the outline the load has to be to set down
local PAD_TOL = 7 -- studs: how close to its pad the crane has to stop to set up
local CARRIER_Y = 2.5 -- the carrier part's height above the crane's origin
local CRANE_DRIVE = { maxFwd = 28, maxRev = 10, accel = 12, brake = 36, turn = 0.8, role = "Operator" }

function Equipment.Init(services)
	S = services
end

local function mk(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weldTo(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function cylinderBetween(a: Vector3, b: Vector3, dia: number): (Vector3, CFrame)
	local mid = (a + b) / 2
	return Vector3.new(dia, dia, (b - a).Magnitude), CFrame.lookAt(mid, b)
end

local function flat(v: Vector3): number
	return Vector2.new(v.X, v.Z).Magnitude
end

-- 1.0 dead on, 0.5 at the edge of the tolerance
local function grade(err: number, tol: number): number
	return math.clamp(1 - 0.5 * err / tol, 0.5, 1)
end

-- What the operator's panel shows (client MachineController reads these model attributes).
local function setInfo(rig: Rig, target: Vector3?, hint: string?)
	if target then
		rig.model:SetAttribute("TargetPos", target)
	end
	if hint then
		rig.model:SetAttribute("Hint", hint)
	end
end

local function clearInfo(rig: Rig)
	for _, k in { "Session", "TargetPos", "Hint", "Err", "Scoops", "ScoopsNeed" } do
		rig.model:SetAttribute(k, nil)
	end
end

local function actorHumanoid(actor: Instance): Humanoid?
	local c = if actor:IsA("Player") then actor.Character else actor
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function boardPrompt(rig: Rig, part: BasePart, text: string)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "BoardPrompt"
	pp.ActionText = text
	pp.ObjectText = rig.kind
	pp:SetAttribute("Machine", rig.kind) -- for the client guide
	pp.HoldDuration = 0.2
	pp.MaxActivationDistance = 10
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
		if not hum or not root or hum.Health <= 0 or (root.Position - part.Position).Magnitude > 16 then
			return
		end
		local Toast = Net.Event("Toast")
		if not S.CrewService.CanDo(p, "Operator") then
			Toast:FireClient(p, "Only the Operator runs the " .. string.lower(rig.kind))
			return
		end
		if rig.kind == "Crane" and rig.mode ~= "set" then
			Toast:FireClient(p, "Drive the crane onto its glowing CRANE PAD first: tap Drive crane at its front cab")
			return
		end
		if rig.seat.Occupant == hum then
			return -- already in it
		end
		if rig.seat.Occupant then
			Toast:FireClient(p, "Someone is already operating it")
			return
		end
		if S.TaskEngine.Carry.Holding(p) then
			Toast:FireClient(p, "Put down what you're carrying first")
			return
		end
		rig.seat:Sit(hum)
	end)
end

---------------------------------------------------------------------------------------------------------------
-- Excavator
---------------------------------------------------------------------------------------------------------------

local ARM_PIVOT = CFrame.new(0.9, 2.6, -2.7)

local function spawnExcavator(cf: CFrame, parent: Instance): Rig
	local m = Instance.new("Model")
	m.Name = "Excavator"
	local base = mk("Undercarriage", Vector3.new(5.6, 1.2, 9.6), cf, DARK, M.Metal, m)
	base.CustomPhysicalProperties = PhysicalProperties.new(2, 0, 0, 100, 0)

	local function add(name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): BasePart
		local p = mk(name, size, cf * lcf, color, mat, m)
		p.Massless = true
		p.CanCollide = collide ~= false
		weldTo(base, p)
		return p
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end

	local skid = add("Skid", Vector3.new(7.6, 0.4, 10.4), at(0, -1.25, 0), DARK, M.Metal)
	skid.Transparency = 1
	skid.Massless = false
	skid.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 100, 0)

	-- Tracks with sprockets, idlers, rollers and track shoes
	for _, side in { -1, 1 } do
		add("Track", Vector3.new(1.9, 2.2, 10.6), at(side * 3.3, -0.35, 0), C(30, 30, 32), M.Rubber, false)
		for _, z in { -4.9, 4.9 } do
			local wheel = add("Sprocket", Vector3.new(2.0, 2.0, 2.0), at(side * 3.3, -0.35, z), STEEL, M.Metal, false)
			wheel.Shape = Enum.PartType.Cylinder
		end
		for _, z in { -2.5, 0, 2.5 } do
			local roller = add("Roller", Vector3.new(2.05, 0.9, 0.9), at(side * 3.3, -1.0, z), STEEL, M.Metal, false)
			roller.Shape = Enum.PartType.Cylinder
		end
		for z = -4.5, 4.5, 1.5 do
			add("Shoe", Vector3.new(2.0, 0.2, 0.35), at(side * 3.3, 0.8, z), C(55, 55, 58), M.Metal, false)
		end
		add("TrackGuard", Vector3.new(0.3, 0.5, 7.6), at(side * 4.3, 0.55, 0), YELLOW, M.Metal, false)
	end

	-- Upper house: turntable, deck, engine cover with grille and exhaust, counterweight
	local ring = add("Turntable", Vector3.new(0.6, 5.2, 5.2), at(0, 0.6, 0.3) * CFrame.Angles(0, 0, math.pi / 2), DARK, M.Metal, false)
	ring.Shape = Enum.PartType.Cylinder
	add("Deck", Vector3.new(5.6, 1.4, 6.8), at(0.2, 1.45, 0.6), YELLOW, M.Metal)
	add("EngineCover", Vector3.new(5.6, 1.5, 3.4), at(0.2, 2.9, 2.3), YELLOW, M.Metal)
	add("EngineGrille", Vector3.new(3.8, 1.0, 0.1), at(0.2, 2.9, 4.03), C(60, 60, 62), M.DiamondPlate, false)
	add("Counterweight", Vector3.new(5.8, 2.4, 1.6), at(0.2, 2.1, 4.75), DEEP_YELLOW, M.Metal)
	local stack = add("Exhaust", Vector3.new(1.4, 0.35, 0.35), at(1.9, 4.2, 2.6) * CFrame.Angles(0, 0, math.pi / 2), C(70, 70, 72), M.Metal, false)
	stack.Shape = Enum.PartType.Cylinder
	add("Handrail", Vector3.new(0.15, 0.15, 3.2), at(2.9, 3.9, 2.3), CHROME, M.Metal, false)
	add("Beacon", Vector3.new(0.5, 0.4, 0.5), at(-1.4, 7.2, -0.2), C(255, 150, 20), M.Neon, false)

	-- Cab (front-left), open on the left side so the operator can climb in
	local cx, cz = -1.4, -1.3
	add("CabRoof", Vector3.new(2.7, 0.25, 2.9), at(cx, 6.9, cz), YELLOW, M.Metal)
	local cabBack = add("CabBack", Vector3.new(2.6, 4.6, 0.2), at(cx, 4.5, cz + 1.4), YELLOW, M.Metal)
	add("Windshield", Vector3.new(2.4, 4.0, 0.15), at(cx, 4.6, cz - 1.4), GLASS, M.Glass).Transparency = 0.45
	add("SideGlass", Vector3.new(0.15, 4.0, 2.6), at(cx + 1.3, 4.6, cz), GLASS, M.Glass).Transparency = 0.45
	for _, p in { Vector3.new(cx - 1.3, 4.5, cz - 1.4), Vector3.new(cx + 1.3, 4.5, cz - 1.4), Vector3.new(cx - 1.3, 4.5, cz + 1.4) } do
		add("Pillar", Vector3.new(0.2, 4.6, 0.2), CFrame.new(p), DARK, M.Metal)
	end
	add("Joystick", Vector3.new(0.2, 0.7, 0.2), at(cx - 0.8, 3.0, cz - 0.4), DARK, M.Rubber, false)
	add("Joystick", Vector3.new(0.2, 0.7, 0.2), at(cx + 0.8, 3.0, cz - 0.4), DARK, M.Rubber, false)
	add("CabStep", Vector3.new(0.8, 0.2, 1.4), at(cx - 1.9, 1.2, cz), DARK, M.DiamondPlate, false)

	local seat = Instance.new("VehicleSeat")
	seat.Name = "OperatorSeat"
	seat.Size = Vector3.new(1.6, 0.8, 1.6)
	seat.CFrame = cf * at(cx, 2.55, cz + 0.2)
	seat.Color = C(45, 45, 48)
	seat.Material = M.Fabric
	seat.HeadsUpDisplay = false
	seat.Massless = true
	seat.Parent = m
	weldTo(base, seat)

	-- Arm: everything hangs off ArmRoot, which is attached to the undercarriage by a Weld we can bend (C0).
	local armRoot = mk("ArmRoot", Vector3.new(0.6, 0.6, 0.6), cf * ARM_PIVOT, DARK, M.Metal, m)
	armRoot.Transparency = 1
	armRoot.Massless = true
	armRoot.CanCollide = false
	local armWeld = Instance.new("Weld")
	armWeld.Name = "ArmWeld"
	armWeld.Part0 = base
	armWeld.Part1 = armRoot
	armWeld.C0 = ARM_PIVOT
	armWeld.Parent = armRoot
	local function arm(name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material): BasePart
		local p = mk(name, size, armRoot.CFrame * lcf, color, mat, m)
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		weldTo(armRoot, p)
		return p
	end
	local A, B, Ctip = Vector3.new(0, 0, 0), Vector3.new(0, 5, -6.5), Vector3.new(0, -0.2, -8.8)
	local s1, c1 = cylinderBetween(A, B, 1.1)
	arm("Boom", Vector3.new(1.0, 1.2, s1.Z), c1, YELLOW, M.Metal)
	local s2, c2 = cylinderBetween(B, Ctip, 0.9)
	arm("Stick", Vector3.new(0.8, 0.9, s2.Z), c2, YELLOW, M.Metal)
	local s3, c3 = cylinderBetween(Vector3.new(0, 0.5, -0.9), Vector3.new(0, 3.4, -4.4), 0.45)
	arm("BoomCylinder", s3, c3, CHROME, M.Metal)
	local s4, c4 = cylinderBetween(Vector3.new(0, 5.8, -5.6), Vector3.new(0, 4.2, -8.2), 0.4)
	arm("StickCylinder", s4, c4, CHROME, M.Metal)
	for _, p in { A, B } do
		arm("Pin", Vector3.new(1.4, 0.6, 0.6), CFrame.new(p) * CFrame.Angles(0, 0, 0), DARK, M.Metal).Shape = Enum.PartType.Cylinder
	end
	local bucket = arm("Bucket", Vector3.new(2.4, 1.6, 1.8), CFrame.new(0, -0.7, -9.1), C(55, 55, 58), M.Metal)
	for i = -1, 1 do
		arm("Tooth", Vector3.new(0.35, 0.35, 0.6), CFrame.new(i * 0.8, -1.55, -9.9), C(80, 80, 82), M.Metal)
	end

	-- Mesh look (ServerStorage.VehicleModels): body welded to the undercarriage, arm to ArmRoot so it still digs.
	-- The body's ArmHinge attribute moves the arm pivot onto the mesh's own hinge.
	local armRest = ARM_PIVOT
	local bodySkin, bodyParts = S.VehicleService.Skin("Excavator", cf, m)
	local armSkin, armParts = nil, {}
	if bodySkin then
		local hinge = bodySkin:GetAttribute("ArmHinge")
		if typeof(hinge) == "Vector3" then
			armRest = CFrame.new(hinge)
			armWeld.C0 = armRest
		end
		-- placed on ArmRoot's own frame, so the arm follows the hinge wherever the weld puts ArmRoot
		armSkin, armParts = S.VehicleService.Skin("ExcavatorArm", armRoot.CFrame, m)
	end
	if bodySkin and armSkin then
		S.VehicleService.HideBuilt(m, { [bodySkin] = true, [armSkin] = true })
		for _, p in bodyParts do
			weldTo(base, p)
		end
		for _, p in armParts do
			weldTo(armRoot, p)
		end
	else
		for _, s in { bodySkin, armSkin } do
			if s then
				s:Destroy()
			end
		end
		armRest = ARM_PIVOT
		armWeld.C0 = ARM_PIVOT
	end

	-- moving tread loops (client TrackController): where the tracks are, in the undercarriage's space
	local tracks: BasePart? = nil
	if bodySkin then
		for _, d in bodySkin:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "crawler_tracks" then
				tracks = d
			end
		end
	end
	if tracks then
		m:SetAttribute("TrackGauge", tracks.Size.X / 2 - 0.95)
		m:SetAttribute("TrackY", cf:ToObjectSpace(tracks.CFrame).Y)
		m:SetAttribute("TrackLength", tracks.Size.Z)
		m:SetAttribute("TrackHeight", tracks.Size.Y)
	else
		m:SetAttribute("TrackGauge", 3.3)
		m:SetAttribute("TrackY", -0.35)
		m:SetAttribute("TrackLength", 10.6)
		m:SetAttribute("TrackHeight", 2.2)
	end
	m:SetAttribute("TrackWidth", 1.9)
	CollectionService:AddTag(m, "SpinTracks")

	-- it rides on 4 frictionless balls under the tracks (not the flat skid), so it rolls over footings and turns freely
	S.VehicleService.AddRideBalls(m, base, {
		(cf * CFrame.new(-2.9, -0.15, -3.6)).Position,
		(cf * CFrame.new(2.9, -0.15, -3.6)).Position,
		(cf * CFrame.new(-2.9, -0.15, 3.6)).Position,
		(cf * CFrame.new(2.9, -0.15, 3.6)).Position,
	}, 2.6)
	skid.CanCollide = false

	m.PrimaryPart = base
	m.Parent = parent
	local vehicle = S.VehicleService.Register(m, base, seat, { maxFwd = 11, maxRev = 6, accel = 8, brake = 20, turn = 0.9, role = "Operator" })

	local rig: Rig = {
		kind = "Excavator",
		model = m,
		seat = seat :: any,
		anchor = seat,
		reach = 14,
		busy = false,
		base = base,
		armWeld = armWeld,
		armRest = armRest,
		vehicle = vehicle,
		boardPart = cabBack,
		home = cf,
		pitch = 0,
		bucket = bucket,
	}
	boardPrompt(rig, cabBack, "Operate excavator")
	return rig
end

local function setArm(rig: Rig, pitch: number)
	if rig.armWeld and rig.armWeld.Parent then
		rig.armWeld.C0 = (rig.armRest :: CFrame) * CFrame.Angles(pitch, 0, 0)
	end
end

-- The bottom of the bucket (it digs when this goes under the ground).
local function bucketTip(rig: Rig): Vector3
	local b = rig.bucket :: BasePart
	return b.Position - Vector3.new(0, 0.8, 0)
end

---------------------------------------------------------------------------------------------------------------
-- Mobile crane
---------------------------------------------------------------------------------------------------------------

local BOOM_LEN = 60
local TURRET_OFFSET = CFrame.new(0, 3.8, 2) -- turret pivot above the carrier
local BOOM_PIVOT = Vector3.new(0.8, 2.6, -1.2) -- in turret space
local REST_YAW, REST_LUFF, REST_DROP = 0, 0.9, 10

local function updateCrane(rig: Rig)
	local T = (rig.frame :: CFrame) * CFrame.Angles(0, rig.yaw :: number, 0)
	for _, r in rig.turret :: { Rel } do
		r.part.CFrame = T * r.rel
	end
	local boomFrame = T * CFrame.new(rig.boomPivot :: Vector3) * CFrame.Angles(rig.luff :: number, 0, 0)
	for _, r in rig.boom :: { Rel } do
		r.part.CFrame = boomFrame * r.rel
	end
	local tip = (boomFrame * CFrame.new(0, 0, -(rig.boomLen :: number))).Position
	local drop = rig.drop :: number
	local hookPos = tip - Vector3.new(0, drop, 0)
	rig.hookPos = hookPos
	rig.tipY = tip.Y
	local cable = rig.cable :: BasePart
	cable.Size = Vector3.new(0.15, math.max(0.2, drop - 0.8), 0.15)
	cable.CFrame = CFrame.new(tip - Vector3.new(0, drop / 2, 0))
	local hook = rig.hook :: BasePart
	hook.CFrame = CFrame.new(hookPos) * CFrame.Angles(0, rig.yaw :: number, 0)
	if rig.load and rig.load.Parent then
		rig.load.CFrame = CFrame.new(hookPos - Vector3.new(0, 1.4 + rig.load.Size.Y / 2, 0))
			* CFrame.Angles(0, (rig.yaw :: number) + (rig.loadTurn or 0), 0)
	end
end

local function spawnCrane(cf: CFrame, parent: Instance, pad: BasePart?): Rig
	local m = Instance.new("Model")
	m.Name = "Crane"
	-- A mesh look (ServerStorage.VehicleModels.CraneCarrier) brings its own turret axis, boom hinge and rest pose.
	local look = S.VehicleService.SkinInfo("CraneCarrier")
	local turretOffset = if look and typeof(look.TurretOffset) == "Vector3" then CFrame.new(look.TurretOffset) else TURRET_OFFSET
	local boomPivot = if look and typeof(look.BoomPivot) == "Vector3" then look.BoomPivot else BOOM_PIVOT
	local restLuff = if look and typeof(look.RestLuff) == "number" then look.RestLuff else REST_LUFF
	local function fixed(name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material): BasePart
		local p = mk(name, size, cf * lcf, color, mat, m)
		p.Anchored = true
		return p
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end

	-- Carrier truck (outriggers drawn out: the mesh look hides all of this anyway)
	fixed("Carrier", Vector3.new(7, 1.4, 20), at(0, CARRIER_Y, 0), WHITE, M.Metal)
	fixed("CarrierStripe", Vector3.new(7.1, 0.4, 20.1), at(0, 2.0, 0), C(200, 60, 40), M.Metal)
	local driveCab = fixed("DriveCab", Vector3.new(6.6, 3.4, 3.6), at(0, 4.6, -8.4), WHITE, M.Metal)
	local ws = fixed("DriveWindshield", Vector3.new(6.0, 1.8, 0.15), at(0, 5.3, -10.25), GLASS, M.Glass)
	ws.Transparency = 0.4
	fixed("Bumper", Vector3.new(7.2, 0.6, 0.5), at(0, 1.6, -10.3), CHROME, M.Metal)
	for _, z in { -7, -3.5, 2.5, 5.5, 8.5 } do
		for _, side in { -1, 1 } do
			local tire = fixed("Tire", Vector3.new(1.2, 3.0, 3.0), at(side * 3.6, 1.5, z), C(30, 30, 32), M.Rubber)
			tire.Shape = Enum.PartType.Cylinder
			local rim = fixed("Rim", Vector3.new(1.25, 1.6, 1.6), at(side * 3.62, 1.5, z), STEEL, M.Metal)
			rim.Shape = Enum.PartType.Cylinder
		end
	end
	for _, z in { -6.6, 7.2 } do
		for _, side in { -1, 1 } do
			fixed("OutriggerBeam", Vector3.new(4.4, 0.6, 0.8), at(side * 5.6, 1.7, z), YELLOW, M.Metal)
			fixed("OutriggerJack", Vector3.new(0.6, 1.4, 0.6), at(side * 7.6, 1.0, z), DARK, M.Metal)
			fixed("Cribbing", Vector3.new(2.2, 0.4, 2.2), at(side * 7.6, 0.2, z), C(150, 115, 75), M.WoodPlanks)
		end
	end
	local ringPart = fixed("Slewing", Vector3.new(0.6, 5, 5), turretOffset * CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.pi / 2), DARK, M.Metal)
	ringPart.Shape = Enum.PartType.Cylinder

	-- Driver's seat in the front cab (used while it's on its wheels)
	local driveSeat = Instance.new("VehicleSeat")
	driveSeat.Name = "DriverSeat"
	driveSeat.Size = Vector3.new(1.6, 0.6, 1.6)
	driveSeat.CFrame = cf * at(-1.4, 3.5, -8.2)
	driveSeat.Anchored = true
	driveSeat.HeadsUpDisplay = false
	driveSeat.Transparency = 1
	driveSeat.Parent = m

	-- Turret (rotates): body, counterweight, operator cab with seat. Boom (rotates + luffs): sections, sheave.
	local frame = cf * turretOffset
	local turret: { Rel } = {}
	local function tpart(name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): BasePart
		local p = mk(name, size, frame * lcf, color, mat, m)
		p.Anchored = true
		p.CanCollide = collide == true
		table.insert(turret, { part = p, rel = lcf })
		return p
	end
	tpart("TurretBody", Vector3.new(4.8, 2.6, 6.4), at(0.6, 1.3, 1.2), YELLOW, M.Metal, true)
	tpart("Counterweight", Vector3.new(5.4, 2.6, 2.2), at(0.6, 1.4, 4.9), DARK, M.Metal, true)
	tpart("WinchDrum", Vector3.new(3.4, 1.6, 1.6), at(0.6, 3.1, 1.6), STEEL, M.Metal).Shape = Enum.PartType.Cylinder
	local ox, oz = -2.5, -0.6
	tpart("OpCabFloor", Vector3.new(2.6, 0.3, 3.0), at(ox, 0.15, oz), DARK, M.DiamondPlate, true)
	tpart("OpCabRoof", Vector3.new(2.6, 0.25, 3.0), at(ox, 4.4, oz), YELLOW, M.Metal)
	tpart("OpCabFront", Vector3.new(2.4, 3.6, 0.15), at(ox, 2.3, oz - 1.45), GLASS, M.Glass).Transparency = 0.4
	tpart("OpCabSide", Vector3.new(0.15, 3.6, 2.8), at(ox + 1.25, 2.3, oz), GLASS, M.Glass).Transparency = 0.4
	local cabBack = tpart("OpCabBack", Vector3.new(2.6, 4.2, 0.2), at(ox, 2.2, oz + 1.45), YELLOW, M.Metal, true)
	tpart("Beacon", Vector3.new(0.5, 0.4, 0.5), at(ox, 4.7, oz + 1), C(255, 150, 20), M.Neon)

	local seat = Instance.new("Seat")
	seat.Name = "CraneSeat"
	seat.Size = Vector3.new(1.4, 0.6, 1.4)
	seat.CFrame = frame * at(ox, 0.6, oz + 0.2)
	seat.Anchored = true
	seat.Color = C(45, 45, 48)
	seat.Material = M.Fabric
	seat.Parent = m
	table.insert(turret, { part = seat, rel = at(ox, 0.6, oz + 0.2) })

	local boom: { Rel } = {}
	local function bpart(name: string, size: Vector3, lcf: CFrame, color: Color3, mat: Enum.Material): BasePart
		local p = mk(name, size, frame * lcf, color, mat, m)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		table.insert(boom, { part = p, rel = lcf })
		return p
	end
	bpart("BoomBase", Vector3.new(1.9, 1.9, BOOM_LEN * 0.55), at(0, 0, -BOOM_LEN * 0.275), YELLOW, M.Metal)
	bpart("BoomMid", Vector3.new(1.5, 1.5, BOOM_LEN * 0.3), at(0, 0, -BOOM_LEN * 0.68), DEEP_YELLOW, M.Metal)
	bpart("BoomTip", Vector3.new(1.1, 1.1, BOOM_LEN * 0.2), at(0, 0, -BOOM_LEN * 0.9), YELLOW, M.Metal)
	for k = 1, 8 do
		bpart("BoomBand", Vector3.new(2.0, 2.0, 0.25), at(0, 0, -k * BOOM_LEN * 0.06), DARK, M.Metal)
	end
	bpart("Sheave", Vector3.new(0.6, 1.6, 1.6), at(0, -0.3, -BOOM_LEN), STEEL, M.Metal).Shape = Enum.PartType.Cylinder
	bpart("BoomFoot", Vector3.new(2.4, 1.2, 1.2), at(0, 0, 0), DARK, M.Metal).Shape = Enum.PartType.Cylinder

	-- Mesh look: carrier (fixed), turret (swings with the turret parts), boom (swings and luffs with the boom parts).
	-- (A turret look is optional: the generated carrier carries its own base housing.)
	local boomFrame0 = frame * CFrame.new(boomPivot)
	local carrierSkin, carrierParts = S.VehicleService.Skin("CraneCarrier", cf, m)
	local turretSkin, turretParts = S.VehicleService.Skin("CraneTurret", frame, m)
	local boomSkin, boomParts = S.VehicleService.Skin("CraneBoom", boomFrame0, m)
	if carrierSkin and boomSkin then
		local skip: { [Instance]: boolean } = { [carrierSkin] = true, [boomSkin] = true }
		if turretSkin then
			skip[turretSkin] = true
		end
		S.VehicleService.HideBuilt(m, skip)
		local carrierPart = m:FindFirstChild("Carrier") :: BasePart
		local spins = false
		for _, p in carrierParts do
			p.Anchored = true
			if string.sub(p.Name, 1, 6) == "Wheel_" then
				-- an axle of the mesh: on a Motor6D so clients roll it (WheelController), no steering
				local axle = carrierPart.CFrame.Rotation + p.Position
				local motor = Instance.new("Motor6D")
				motor.Name = "WheelMotor"
				motor.Part0 = carrierPart
				motor.Part1 = p
				motor.C0 = carrierPart.CFrame:ToObjectSpace(axle)
				motor.C1 = p.CFrame:ToObjectSpace(axle)
				motor:SetAttribute("Front", false)
				motor:SetAttribute("Radius", math.max(p.Size.Y, p.Size.Z) / 2)
				motor.Parent = p
				spins = true
			end
		end
		if spins then
			CollectionService:AddTag(m, "SpinWheels")
		end
		for _, p in turretParts do
			p.Anchored = true
			table.insert(turret, { part = p, rel = frame:ToObjectSpace(p.CFrame) })
		end
		for _, p in boomParts do
			p.Anchored = true
			table.insert(boom, { part = p, rel = boomFrame0:ToObjectSpace(p.CFrame) })
		end
	else
		for _, s in { carrierSkin, turretSkin, boomSkin } do
			if s then
				s:Destroy()
			end
		end
	end

	local cable = mk("Cable", Vector3.new(0.15, 4, 0.15), frame, C(30, 30, 30), M.Metal, m)
	cable.Anchored = true
	cable.CanCollide = false
	cable.CanQuery = false
	local hook = mk("HookBlock", Vector3.new(1.4, 1.8, 1.0), frame, YELLOW, M.Metal, m)
	hook.Anchored = true
	hook.CanCollide = false

	m.PrimaryPart = (m:FindFirstChild("Carrier") :: BasePart)
	m.Parent = parent
	-- Boom part frames (rel) are measured from the boom pivot; updateCrane places them on the luffed boom frame.

	local rig: Rig = {
		kind = "Crane",
		model = m,
		seat = seat,
		anchor = seat,
		reach = BOOM_LEN * 0.95,
		busy = false,
		frame = frame,
		turretOffset = turretOffset,
		turret = turret,
		boom = boom,
		boomPivot = boomPivot,
		boomLen = BOOM_LEN,
		yaw = REST_YAW,
		luff = restLuff,
		restLuff = restLuff,
		drop = REST_DROP,
		hook = hook,
		cable = cable,
		boardPart = cabBack,
		driveSeat = driveSeat,
		mode = "set",
	}
	updateCrane(rig)
	boardPrompt(rig, cabBack, "Operate crane")
	-- Seats also seat whoever touches them: only the Operator (or anyone, if nobody is Operator) may stay.
	-- Climbing out: the cab sits up on the turret, so put the player down on the ground beside the carrier.
	local rider: Humanoid? = nil
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		local prev = rider
		rider = occ
		if prev and not occ then
			local pl = Players:GetPlayerFromCharacter(prev.Parent)
			local char = prev.Parent
			if pl and char and char:IsA("Model") and prev.Health > 0 then
				seat.Disabled = true
				task.delay(1.2, function()
					if seat.Parent and rig.mode == "set" then
						seat.Disabled = false
					end
				end)
				local carrier = m.PrimaryPart :: BasePart
				local side = carrier.CFrame.RightVector * -6.5
				local spot = Vector3.new(seat.Position.X, 0, seat.Position.Z) + Vector3.new(side.X, 3.2, side.Z)
				task.defer(function()
					char:PivotTo(CFrame.new(spot) * carrier.CFrame.Rotation)
				end)
			end
		end
		local pl = if occ then Players:GetPlayerFromCharacter(occ.Parent) else nil
		if pl and not S.CrewService.CanDo(pl, "Operator") then
			local w = seat:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
			Net.Event("Toast"):FireClient(pl, "Only the Operator runs the crane")
		end
	end)

	if pad then
		-- arrives on its wheels: weld it all to the carrier and make it drivable until it sets up on its pad
		rig.pad = pad
		local carrier = m.PrimaryPart :: BasePart
		local origin = carrier.CFrame * CFrame.new(0, -CARRIER_Y, 0)
		local parts: { Instance } = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d ~= carrier then
				d.Anchored = false
				d.Massless = true
				if d:FindFirstChild("WheelMotor") then
					d.CanCollide = false
					continue -- the axle meshes hang on their motors
				end
				local c = d.CFrame
				local halfY = math.abs(c.RightVector.Y) * d.Size.X / 2 + math.abs(c.UpVector.Y) * d.Size.Y / 2
					+ math.abs(c.LookVector.Y) * d.Size.Z / 2
				if d.Position.Y - halfY - origin.Y < 1 then
					d.CanCollide = false -- tires, cribbing: the ride balls carry it
				end
				local w = Instance.new("WeldConstraint")
				w.Part0 = carrier
				w.Part1 = d
				w.Parent = d
				table.insert(parts, w)
			end
		end
		carrier.Anchored = false
		local balls = S.VehicleService.AddRideBalls(m, carrier, {
			(origin * CFrame.new(-3.6, 1.5, -7)).Position,
			(origin * CFrame.new(3.6, 1.5, -7)).Position,
			(origin * CFrame.new(-3.6, 1.5, 8.5)).Position,
			(origin * CFrame.new(3.6, 1.5, 8.5)).Position,
		}, 3)
		for _, b in balls do
			table.insert(parts, b)
		end
		rig.driveParts = parts
		seat.Disabled = true -- the crane cab works once it's set up
		local spec = table.clone(CRANE_DRIVE) :: any
		spec.promptPart = driveCab
		spec.promptText = "Drive crane"
		rig.vehicle = S.VehicleService.Register(m, carrier, driveSeat, spec)
		m:SetAttribute("Wheelbase", 15.5)
		rig.mode = "drive"
	else
		driveSeat.Disabled = true
	end
	m:SetAttribute("Mode", rig.mode)
	return rig
end

-- Sets the crane up where it stands (or on its pad with `snap`): levels it, locks it in place, and the crane cab
-- takes over. Whoever is driving climbs out.
local function setUp(rig: Rig, snap: boolean?)
	if rig.kind ~= "Crane" or (rig.mode ~= "drive" and rig.mode ~= "setting") then
		return
	end
	rig.mode = "setting"
	local m = rig.model
	local carrier = m.PrimaryPart :: BasePart
	local ds = rig.driveSeat
	local driver: Humanoid? = nil
	if ds then
		driver = ds.Occupant
		local w = ds:FindFirstChild("SeatWeld")
		if w then
			w:Destroy()
		end
		ds.Disabled = true
	end
	task.wait(0.15)
	if not m.Parent then
		return
	end
	local look = carrier.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local pos = carrier.Position
	local pad = rig.pad
	local groundY = if pad then pad.Position.Y - pad.Size.Y / 2 else 0
	if snap and pad then
		pos = pad.Position
		local pl = pad.CFrame.LookVector
		yaw = math.atan2(-pl.X, -pl.Z)
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
		end
	end
	m:PivotTo(CFrame.new(pos.X, groundY + CARRIER_Y, pos.Z) * CFrame.Angles(0, yaw, 0))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	for _, x in rig.driveParts or {} do
		x:Destroy()
	end
	rig.driveParts = nil
	local cab = m:FindFirstChild("DriveCab")
	local drivePrompt = cab and cab:FindFirstChild("BoardPrompt")
	if drivePrompt then
		drivePrompt:Destroy()
	end
	rig.frame = carrier.CFrame * CFrame.new(0, -CARRIER_Y, 0) * (rig.turretOffset :: CFrame)
	rig.mode = "set"
	rig.seat.Disabled = false
	if pad then
		pad:Destroy()
		rig.pad = nil
	end
	m:SetAttribute("Mode", "set")
	m:SetAttribute("Wheelbase", nil)
	updateCrane(rig)
	-- the driver climbs down beside the carrier (first clear spot), and the drive seat is retired
	local char = driver and driver.Parent
	if char and char:IsA("Model") then
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = { m, char }
		op.RespectCanCollide = true
		local c = carrier.CFrame
		for _, off in { Vector3.new(-9.5, 0, -6), Vector3.new(9.5, 0, -6), Vector3.new(-9.5, 0, 2), Vector3.new(9.5, 0, 2), Vector3.new(0, 0, -14) } do
			local p = (c * CFrame.new(off)).Position
			local spot = Vector3.new(p.X, groundY + 3.2, p.Z)
			if #workspace:GetPartBoundsInBox(CFrame.new(spot + Vector3.new(0, 0.3, 0)), Vector3.new(2, 4.6, 2), op) == 0 then
				char:PivotTo(CFrame.new(spot) * c.Rotation)
				break
			end
		end
	end
	if ds then
		ds:Destroy()
		rig.driveSeat = nil
	end
	Net.Cue("CrashMetal", carrier.Position)
	Net.Event("Toast"):FireAllClients("Crane set up on its outriggers! Operator: climb into the crane cab (Operate crane)")
end

-- On its wheels: standing still on its pad for a second sets it up.
local function checkSetUp(rig: Rig, dt: number)
	local carrier = rig.model.PrimaryPart
	local pad = rig.pad
	if not carrier or not pad or dt <= 0 then
		return
	end
	local pos = carrier.Position
	local speed = if rig.lastPos then flat(pos - rig.lastPos :: Vector3) / dt else 99
	rig.lastPos = pos
	if flat(pos - pad.Position) < PAD_TOL and speed < 1.5 then
		rig.still = (rig.still or 0) + dt
	else
		rig.still = 0
	end
	if (rig.still :: number) > 1 then
		rig.still = 0
		rig.mode = "setting"
		task.spawn(setUp, rig, false)
	end
end

-- Smoothly move the crane to a pose (yaw, luff, drop) over `seconds`.
local function moveCrane(rig: Rig, yaw: number, luff: number, drop: number, seconds: number)
	local y0, l0, d0 = rig.yaw :: number, rig.luff :: number, rig.drop :: number
	local dy = (yaw - y0 + math.pi) % (2 * math.pi) - math.pi -- shortest way round
	local t = 0
	while t < seconds and rig.model.Parent do
		t += task.wait(0.03)
		local a = math.clamp(t / seconds, 0, 1)
		local e = a * a * (3 - 2 * a)
		rig.yaw = y0 + dy * e
		rig.luff = l0 + (luff - l0) * e
		rig.drop = d0 + (drop - d0) * e
		updateCrane(rig)
	end
end

-- Pose that puts the hook above `target` with `clearance` studs under the load (or under the hook, unloaded).
local function poseFor(rig: Rig, target: Vector3, clearance: number): (number, number, number)
	local local_ = (rig.frame :: CFrame):PointToObjectSpace(target)
	local yaw = math.atan2(-local_.X, -local_.Z)
	-- the boom pivot sits ahead of the turret center, so measure the reach from there
	local horiz = Vector2.new(local_.X, local_.Z).Magnitude + (rig.boomPivot :: Vector3).Z
	local luff = math.acos(math.clamp(horiz / (rig.boomLen :: number), 0.15, 0.97))
	local T = (rig.frame :: CFrame) * CFrame.Angles(0, yaw, 0)
	local tip = (T * CFrame.new(rig.boomPivot :: Vector3) * CFrame.Angles(luff, 0, 0) * CFrame.new(0, 0, -(rig.boomLen :: number))).Position
	-- the load's center hangs 1.4 + half its height under the hook; clearance 0 lands it on the slot
	local loadH = if rig.load then rig.load.Size.Y else 0
	local drop = math.max(3, tip.Y - (target.Y + clearance + 1.4 + loadH / 2))
	return yaw, luff, drop
end

-- The hook (or its load) can't go into the ground, or through the roof unless it's lined up over the outline.
local function craneLimits(rig: Rig)
	local tipY, hp = rig.tipY, rig.hookPos
	if not tipY or not hp then
		return
	end
	local s = rig.session
	local maxDrop: number
	if rig.load then
		local H = rig.load.Size.Y
		maxDrop = tipY - 1.5 - H
		if s and s.slot and s.slot.part.Parent then
			local t = s.slot.part.Position
			local err = flat(hp - t)
			if err < 10 then
				local lowest = if err < LIFT_TOL then t.Y - 0.8 else t.Y + 0.9 -- lowest the load's center may go
				maxDrop = math.min(maxDrop, tipY - 1.4 - H / 2 - lowest)
			end
		end
	else
		maxDrop = tipY - 1.2
		local g = s and s.ground
		if g and g.Parent and flat(hp - g.Position) < math.max(g.Size.X, g.Size.Z) / 2 + 1 then
			maxDrop = math.min(maxDrop, tipY - (g.Position.Y + g.Size.Y / 2 + 0.9 + 0.3))
		end
	end
	rig.drop = math.clamp(rig.drop :: number, 3, math.max(3, maxDrop))
end

-- The roof section waiting for the hook: on clear ground about 20 studs out from the crane, off to the side of the
-- line to the house.
local function groundLoad(rig: Rig, slot: any): BasePart
	local size = slot.part.Size * Vector3.new(0.95, 1, 0.95)
	local fp = (rig.frame :: CFrame).Position
	local to = slot.part.Position - fp
	local dir = if flat(to) > 0.1 then Vector3.new(to.X, 0, to.Z).Unit else Vector3.new(0, 0, -1)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { rig.model, workspace.Terrain }
	op.RespectCanCollide = true
	local best: CFrame? = nil
	for _, deg in { 75, -75, 105, -105, 50, -50, 130, -130, 160, -160 } do
		for _, r in { 20, 26, 16 } do
			local d = CFrame.Angles(0, math.rad(deg), 0) * dir
			local pos = fp + d * r
			local cf = CFrame.lookAt(Vector3.new(pos.X, size.Y / 2 + 0.05, pos.Z), Vector3.new(fp.X, size.Y / 2 + 0.05, fp.Z))
			best = best or cf
			if #workspace:GetPartBoundsInBox(cf * CFrame.new(0, 1.2, 0), size + Vector3.new(1, 2, 1), op) == 0 then
				best = cf
				break
			end
		end
		if best and #workspace:GetPartBoundsInBox((best :: CFrame) * CFrame.new(0, 1.2, 0), size + Vector3.new(1, 2, 1), op) == 0 then
			break
		end
	end
	local load = mk("RoofSection", size, best :: CFrame, C(190, 150, 100), M.WoodPlanks, rig.model)
	load.Anchored = true
	load.CanCollide = false
	return load
end

---------------------------------------------------------------------------------------------------------------
-- Hands-on work (players and bots)
---------------------------------------------------------------------------------------------------------------

local function craneStep(rig: Rig)
	local s = rig.session
	if not s or s.finished then
		return
	end
	local hp = rig.hookPos :: Vector3
	if not rig.load then
		local g = s.ground :: BasePart?
		if not g or not g.Parent then
			return
		end
		local top = g.Position.Y + g.Size.Y / 2
		s.err = flat(hp - g.Position)
		if s.err < LIFT_TOL and hp.Y - 0.9 - top < 0.6 then
			rig.load = g
			g.Name = "CraneLoad"
			local gl = g.CFrame.LookVector
			rig.loadTurn = math.atan2(-gl.X, -gl.Z) - (rig.yaw :: number)
			s.ground = nil
			Net.Cue("Place", g.Position)
			setInfo(rig, s.slot.part.Position, "Hooked! Swing it over the glowing outline and lower it onto it")
		end
	else
		local t = s.slot.part.Position
		local lc = rig.load.Position
		s.err = flat(lc - t)
		if s.err < LIFT_TOL and math.abs(lc.Y - t.Y) < 0.9 then
			s.finished = true
			rig.session = nil
			clearInfo(rig)
			s.done(grade(s.err, LIFT_TOL))
		end
	end
end

local function growMound(s: any)
	local hole = s.slot.part.Position
	local m = s.mound :: BasePart?
	if not m or not m.Parent then
		local mound = mk("DirtMound", Vector3.new(1.6, 0.8, 1.6), CFrame.new(hole + Vector3.new(2.8, 0.2, 0)), C(95, 70, 45), M.Ground,
			s.slot.part.Parent or workspace)
		mound.Shape = Enum.PartType.Ball
		mound.Anchored = true
		mound.CanCollide = false
		mound.CanQuery = false
		s.mound = mound
		m = mound
	end
	local k = s.scoops :: number
	;(m :: BasePart).Size = Vector3.new(1.4 + 0.6 * k, 0.6 + 0.35 * k, 1.4 + 0.6 * k)
end

local function digStep(rig: Rig)
	local s = rig.session
	if not s or s.finished or not rig.bucket then
		return
	end
	local tip = bucketTip(rig)
	local hole = s.slot.part.Position
	s.err = flat(tip - hole)
	if not s.inGround then
		if tip.Y < -0.3 then
			if s.err < DIG_TOL then
				s.inGround = true
				s.bite = s.err
				Net.Cue("Place", hole)
			elseif os.clock() - (s.warnAt or 0) > 3 then
				s.warnAt = os.clock()
				setInfo(rig, nil, "That's not the hole: line the bucket up with the glowing marker")
			end
		end
	elseif tip.Y > 1.2 then
		s.inGround = false
		s.scoops += 1
		table.insert(s.errs, s.bite)
		growMound(s)
		rig.model:SetAttribute("Scoops", s.scoops)
		if s.scoops >= SCOOPS then
			local sum = 0
			for _, e in s.errs do
				sum += grade(e, DIG_TOL)
			end
			s.finished = true
			rig.session = nil
			clearInfo(rig)
			s.done(sum / #s.errs)
		else
			setInfo(rig, nil, ("Scoop %d of %d out: dig again"):format(s.scoops, SCOOPS))
		end
	end
end

function Equipment.SetInput(rig: Rig, a: number, b: number, c: number)
	rig.input = { a = math.clamp(a, -1, 1), b = math.clamp(b, -1, 1), c = math.clamp(c, -1, 1), at = os.clock() }
end

local function step(dt: number)
	local now = os.clock()
	for _, rig in rigs do
		if not rig.model.Parent then
			continue
		end
		local inp = rig.input
		local live = inp ~= nil and now - inp.at < INPUT_TTL
		local a = if live then (inp :: any).a else 0
		local b = if live then (inp :: any).b else 0
		local c = if live then (inp :: any).c else 0
		if rig.kind == "Crane" then
			if rig.mode == "drive" then
				checkSetUp(rig, dt)
			elseif rig.mode == "set" and not rig.auto then
				if a ~= 0 or b ~= 0 or c ~= 0 then
					rig.yaw = (rig.yaw :: number) - a * SWING_RATE * dt -- + = swing right
					rig.luff = math.clamp((rig.luff :: number) + b * LUFF_RATE * dt, LUFF_MIN, LUFF_MAX)
					rig.drop = (rig.drop :: number) - c * HOIST_RATE * dt -- + = hook up
					updateCrane(rig)
					craneLimits(rig)
					updateCrane(rig)
				end
				craneStep(rig)
			end
		elseif rig.kind == "Excavator" then
			if a ~= 0 and not rig.auto then
				rig.pitch = math.clamp((rig.pitch or 0) + a * ARM_RATE * dt, ARM_MIN, ARM_MAX) -- + = arm up
				setArm(rig, rig.pitch :: number)
			end
			digStep(rig)
		end
		-- the operator left the seat mid-task: it's called off
		local s = rig.session
		if s and not s.finished then
			local hum = actorHumanoid(s.actor)
			if not hum or rig.seat.Occupant ~= hum then
				s.finished = true -- (once)
				task.spawn(s.cancelled)
			elseif now - (rig.attrAt or 0) > 0.12 then
				rig.attrAt = now
				rig.model:SetAttribute("Err", math.floor((s.err or 0) * 10 + 0.5) / 10)
			end
		end
	end
end

-- Starts a machine task done by hand. done(accuracy) when it's done, cancelled() if the operator gives up.
function Equipment.BeginManual(rig: Rig, slot: any, actor: Instance, done: (number) -> (), cancelled: () -> ())
	rig.busy = true
	local s: { [string]: any } = { slot = slot, actor = actor, done = done, cancelled = cancelled, scoops = 0, errs = {},
		err = 99, inGround = false }
	rig.session = s
	if rig.kind == "Crane" then
		s.ground = groundLoad(rig, slot)
		rig.model:SetAttribute("Session", "Lift")
		local g = s.ground :: BasePart
		setInfo(rig, g.Position + Vector3.new(0, g.Size.Y / 2, 0), "Lower the hook onto the roof section on the ground to hook it")
	else
		rig.model:SetAttribute("Session", "Dig")
		rig.model:SetAttribute("Scoops", 0)
		rig.model:SetAttribute("ScoopsNeed", SCOOPS)
		setInfo(rig, slot.part.Position, ("Lower the arm into the glowing hole, then lift it out (%d scoops)"):format(SCOOPS))
	end
end

-- Bots run the machine through the same controls. Returns true once the task is done; false if it gave up.
-- aimError: studs the bot is off the target (it doesn't line up perfectly).
function Equipment.Autopilot(rig: Rig, alive: () -> boolean, aimError: number): boolean
	local s = rig.session
	if not s then
		return false
	end
	local rng = Random.new()
	local ang = rng:NextNumber(0, 2 * math.pi)
	local off = Vector3.new(math.cos(ang), 0, math.sin(ang)) * rng:NextNumber(0, aimError)
	local t0 = os.clock()
	local phase = "aim"
	local standoff: Vector3? = nil -- excavator: the digging spot it drives to (picked once per approach)
	local aimSince = os.clock()
	while rig.session == s and alive() and rig.model.Parent and os.clock() - t0 < 90 do
		if rig.kind == "Crane" then
			local target: Vector3
			if rig.load then
				target = s.slot.part.Position + off
			else
				local g = s.ground :: BasePart
				if not g or not g.Parent then
					break
				end
				target = g.Position + Vector3.new(0, g.Size.Y / 2, 0) + off * 0.4
			end
			local yawD, luffD, dropD = poseFor(rig, target, 0)
			local yawErr = (yawD - (rig.yaw :: number) + math.pi) % (2 * math.pi) - math.pi
			local luffErr = math.clamp(luffD, LUFF_MIN, LUFF_MAX) - (rig.luff :: number)
			local aligned = math.abs(yawErr) < 0.03 and math.abs(luffErr) < 0.02
			local wantDrop = math.max(3, if aligned then dropD else math.min(rig.drop :: number, dropD - 10))
			Equipment.SetInput(rig, math.clamp(-yawErr / 0.1, -1, 1), math.clamp(luffErr / 0.06, -1, 1),
				math.clamp(((rig.drop :: number) - wantDrop) / 1.5, -1, 1))
		else
			local base = rig.base :: BasePart
			local hole = s.slot.part.Position + off
			local lp = base.CFrame:PointToObjectSpace(hole)
			local turn = math.atan2(lp.X - 0.9, -lp.Z) -- + = the hole is to the right of the arm's line
			local dist = -lp.Z - 10.6 -- + = too far away (the bucket bites ~10.6 studs ahead)
			local tip = bucketTip(rig)
			-- lined up: the bucket bites within ~1.2 studs of the hole; after 6 s of trying (blocked by footings), close
			-- enough that it still reaches the hole will do
			local lateral = math.abs(lp.X - 0.9)
			local placed = (lateral < 1.2 and math.abs(dist) < 1.4)
				or (os.clock() - aimSince > 6 and lateral < DIG_TOL - 0.6 and math.abs(dist) < 2)
			if phase == "aim" then
				Equipment.SetInput(rig, math.clamp((0.15 - (rig.pitch or 0)) / 0.1, -1, 1), 0, 0)
				if rig.vehicle then
					-- first get to a digging spot ~10.6 studs from the hole on the side it came from (sitting on the
					-- hole: drive straight off it first), turning on the spot before driving; then face the hole
					local bp = base.Position
					local toHole = Vector3.new(hole.X - bp.X, 0, hole.Z - bp.Z)
					local throttle, steer = 0, 0
					if toHole.Magnitude < 5 and not placed then
						throttle = if lp.Z < 0 then -0.6 else 0.6
						standoff = nil
						S.VehicleService.Drive(rig.vehicle, throttle, 0)
						task.wait(0.05)
						continue
					end
					if not standoff then
						standoff = Vector3.new(hole.X, bp.Y, hole.Z) - toHole.Unit * 10.6
					end
					local spot = standoff :: Vector3
					local toSpot = Vector3.new(spot.X - bp.X, 0, spot.Z - bp.Z)
					if toSpot.Magnitude > 1.6 and not placed then
						local ls = base.CFrame:VectorToObjectSpace(toSpot)
						local head = math.atan2(ls.X, -ls.Z) -- + = the spot is to the right
						steer = math.clamp(head / 0.3, -1, 1)
						throttle = if math.abs(head) < 0.3 then math.clamp(toSpot.Magnitude / 3, 0.3, 0.7) else 0
					else
						steer = math.clamp(turn / 0.3, -1, 1)
						throttle = if math.abs(turn) < 0.25 then math.clamp(dist / 2, -0.4, 0.4) else 0
					end
					S.VehicleService.Drive(rig.vehicle, throttle, steer)
				end
				if placed or not rig.vehicle then
					phase = "down"
				end
			elseif phase == "down" then
				if rig.vehicle then
					S.VehicleService.Drive(rig.vehicle, 0, 0)
				end
				Equipment.SetInput(rig, -1, 0, 0)
				if s.inGround then
					phase = "up"
				elseif tip.Y < -0.3 or (rig.pitch or 0) <= ARM_MIN + 0.01 then
					phase = "lift" -- missed the hole: come back up and line up again
				end
			elseif phase == "up" then
				Equipment.SetInput(rig, 1, 0, 0)
				if not s.inGround then
					phase = "down"
				end
			else -- "lift"
				Equipment.SetInput(rig, 1, 0, 0)
				if tip.Y > 1.4 then
					phase = "aim"
					standoff = nil
					aimSince = os.clock()
				end
			end
		end
		task.wait(0.05)
	end
	Equipment.SetInput(rig, 0, 0, 0)
	if rig.vehicle and rig.kind == "Excavator" then
		S.VehicleService.Drive(rig.vehicle, 0, 0)
	end
	return s.finished == true
end

---------------------------------------------------------------------------------------------------------------
-- API used by JobService / BotService
---------------------------------------------------------------------------------------------------------------

-- The glowing CRANE PAD the crane sets up on (with a prompt that sets it up when the crane is on it).
local function makePad(cf: CFrame, parent: Instance): BasePart
	local pad = mk("CranePad", Vector3.new(9, 0.12, 21), cf * CFrame.new(0, 0.06, 0), YELLOW, M.Neon, parent)
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.Transparency = 0.55
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Text = "CRANE\nPAD"
	t.Rotation = 90
	t.Parent = sg
	sg.Parent = pad
	table.insert(pads, pad)
	return pad
end

function Equipment.SpawnFor(bp: any, originCF: CFrame, parent: Instance)
	if not bp.Equipment then
		return
	end
	-- excavator first, so the crane's arrival lane steers clear of it
	for _, kind in { "Excavator", "Crane" } do
		local lcf = bp.Equipment[kind]
		if not lcf then
			continue
		end
		local world = originCF * lcf
		if kind == "Excavator" then
			table.insert(rigs, spawnExcavator(world, parent))
		elseif kind == "Crane" then
			-- arrive 32-48 studs from the pad, facing it, with a clear lane to drive in (toward the road first,
			-- then the other sides); no room anywhere -> it starts set up on the pad
			local op = OverlapParams.new()
			op.FilterType = Enum.RaycastFilterType.Exclude
			op.FilterDescendantsInstances = { workspace.Terrain }
			op.RespectCanCollide = true
			local start: CFrame? = nil
			for _, side in { 0, math.pi / 2, -math.pi / 2, math.pi } do
				for _, d in { 48, 40, 32 } do
					local cf = world * CFrame.Angles(0, side, 0) * CFrame.new(0, 0, -d) * CFrame.Angles(0, math.pi, 0)
					local lane = world * CFrame.Angles(0, side, 0) * CFrame.new(0, 4, -d / 2)
					if #workspace:GetPartBoundsInBox(cf * CFrame.new(0, 4.5, 0), Vector3.new(16, 7, 23), op) == 0
						and #workspace:GetPartBoundsInBox(lane, Vector3.new(10, 5.5, d + 20), op) == 0 then
						start = cf
						break
					end
				end
				if start then
					break
				end
			end
			if start then
				local pad = makePad(world, parent)
				local rig = spawnCrane(start, parent, pad)
				table.insert(rigs, rig)
				local pp = Instance.new("ProximityPrompt")
				pp.ActionText = "Set up crane here"
				pp.ObjectText = "Crane pad"
				pp.HoldDuration = 0.3
				pp.MaxActivationDistance = 30
				pp.RequiresLineOfSight = false
				pp:SetAttribute("CranePad", true) -- for the client guide
				pp.Parent = pad
				S.JobService.RegisterPrompt(pp, function(p: Player)
					local carrier = rig.model.PrimaryPart
					if rig.mode ~= "drive" or not carrier then
						return
					end
					if flat(carrier.Position - pad.Position) > PAD_TOL then
						Net.Event("Toast"):FireClient(p, "Drive the crane onto the glowing pad first")
						return
					end
					task.spawn(setUp, rig, false)
				end)
			else
				table.insert(rigs, spawnCrane(world, parent, nil))
			end
		end
	end
end

function Equipment.Clear()
	for _, r in rigs do
		r.digging = false
		r.session = nil
		if r.model.Parent then
			r.model:Destroy()
		end
	end
	table.clear(rigs)
	for _, p in pads do
		p:Destroy()
	end
	table.clear(pads)
end

-- Sets the crane up on its pad (bots, when their drive didn't stop it there).
function Equipment.SetUp(rig: Rig)
	setUp(rig, true)
end

-- Is this player operating a machine of `kind` that can reach `target`? Returns the rig or a reason.
function Equipment.CheckOperator(p: Instance, kind: string, target: Vector3): (Rig?, string?)
	local c = if p:IsA("Player") then p.Character else p -- players and bots
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local seatPart = hum and hum.SeatPart
	for _, r in rigs do
		if r.kind == kind and r.model.Parent and seatPart ~= nil and seatPart == r.driveSeat and r.mode ~= "set" then
			return nil, "Drive the crane onto the glowing CRANE PAD and stop: it sets itself up"
		end
		if r.kind == kind and r.model.Parent and seatPart == r.seat then
			if r.busy then
				return nil, "The " .. string.lower(kind) .. " is still working"
			end
			local from = if kind == "Crane" then (r.frame :: CFrame).Position else (r.base :: BasePart).Position
			local d = Vector2.new(target.X - from.X, target.Z - from.Z).Magnitude
			if kind == "Excavator" and d > r.reach then
				return nil, "Drive the excavator closer to the hole"
			end
			if kind == "Crane" and (d > r.reach or d < 6) then
				return nil, "That's out of the crane's reach"
			end
			return r, nil
		end
	end
	if kind == "Crane" then
		return nil, "Use the crane for this: tap Operate crane at its cab"
	end
	return nil, "Dig this with the excavator: tap Operate excavator, then drive up to the hole"
end

-- The site's machine of this kind, if any (bots look it up to climb in).
function Equipment.Find(kind: string): Rig?
	for _, r in rigs do
		if r.kind == kind and r.model.Parent then
			return r
		end
	end
	return nil
end

-- Chaos (crane mishap): the badly rigged load swings on the hook, slips and drops beside the slot.
-- Returns the dropped load (left on the site as debris).
local function dropLoad(rig: Rig, slot: any): BasePart?
	local load = rig.load
	if not load then
		return nil
	end
	local yaw = rig.yaw :: number
	for _, sway in { 0.22, -0.22, 0.16, -0.16 } do
		moveCrane(rig, yaw + sway, rig.luff :: number, rig.drop :: number, 0.45)
	end
	rig.load = nil
	local frame = (rig.frame :: CFrame).Position
	local at = slot.part.Position
	local toward = Vector3.new(frame.X - at.X, 0, frame.Z - at.Z)
	local dir = if toward.Magnitude > 0.1 then toward.Unit else Vector3.new(1, 0, 0)
	local land = Vector3.new(at.X, 0.75, at.Z) + dir * (slot.part.Size.X / 2 + 6)
	load.Name = "DroppedLoad"
	load.Parent = slot.part.Parent or rig.model
	local tw = TweenService:Create(load, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(land) * CFrame.Angles(0.12, yaw + 0.6, -0.08),
		Size = Vector3.new(8, 1.5, 6),
	})
	tw:Play()
	tw.Completed:Wait()
	load.CanCollide = true
	return load
end

-- The task is done: complete it (`andThen`). With `onMishap` (ChaosService armed a crane mishap) the load drops
-- instead and onMishap gets the debris.
function Equipment.FinishWork(rig: Rig, slot: any, andThen: () -> (), onMishap: ((BasePart?) -> ())?)
	task.spawn(function()
		if rig.kind == "Excavator" then
			andThen()
		elseif onMishap then
			rig.auto = true
			local debris = dropLoad(rig, slot)
			onMishap(debris)
			moveCrane(rig, rig.yaw :: number, rig.luff :: number, math.max(3, (rig.drop :: number) - 8), 0.8)
			rig.auto = false
		else
			if rig.load then
				rig.load:Destroy()
				rig.load = nil
			end
			andThen()
		end
		rig.busy = false
	end)
end

function Equipment.CancelWork(rig: Rig)
	rig.digging = false
	local s = rig.session
	rig.session = nil
	if s and s.ground then
		s.ground:Destroy()
	end
	if rig.load then
		rig.load:Destroy()
		rig.load = nil
	end
	clearInfo(rig)
	rig.busy = false
end

-- MachineInput remote: the operator's controls (each -1..1). Crane: swing (+ right), boom (+ up), hook (+ up).
-- Excavator: arm (+ up). Only from whoever sits in that machine's operator seat; rate-limited.
local budget: { [Player]: { t: number, n: number } } = {}
local function onInput(p: Player, a: unknown, b: unknown, c: unknown)
	local now = os.clock()
	local bud = budget[p]
	if not bud or now - bud.t >= 1 then
		budget[p] = { t = now, n = 1 }
	else
		bud.n += 1
		if bud.n > INPUT_MAX_PER_SEC then
			return
		end
	end
	local function axis(v: unknown): number?
		if typeof(v) ~= "number" or v ~= v then
			return nil
		end
		return math.clamp(v, -1, 1)
	end
	local A, B, Cc = axis(a), axis(b), axis(c)
	if A == nil or B == nil or Cc == nil then
		return
	end
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	local seatPart = hum and hum.SeatPart
	if not seatPart then
		return
	end
	for _, r in rigs do
		if r.seat == seatPart and r.model.Parent then
			Equipment.SetInput(r, A :: number, B :: number, Cc :: number)
			return
		end
	end
end

function Equipment.Start()
	Net.Event("MachineInput").OnServerEvent:Connect(onInput)
	Players.PlayerRemoving:Connect(function(p)
		budget[p] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return Equipment
