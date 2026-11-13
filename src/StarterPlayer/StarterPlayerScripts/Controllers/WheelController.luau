--!strict
-- Spinning, steering wheels (2026-11-12). Every truck tagged "SpinWheels" (VehicleService puts its wheel meshes on
-- Motor6Ds named WheelMotor) gets its wheels turned here, on each client, by how far the truck actually moved: they
-- roll forward and back with it, and the front ones steer. For the truck this player drives, the steering angle comes
-- from the drive model (LocalSteer); for everyone else's it is worked out from how fast the truck is turning.
-- Looks only: Motor6D.Transform is local to this client and nothing here touches physics. Skipped past 350 studs.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WheelController = {}

local player = Players.LocalPlayer
local FAR = 350
local MAX_STEER = math.rad(36)

type Rig = {
	motors: { Motor6D },
	scanAt: number,
	dist: number, -- studs rolled (forward +)
	steer: number,
	lastPos: Vector3?,
	lastLook: Vector3?,
}

local rigs: { [Model]: Rig } = {}

local function add(m: Instance)
	if m:IsA("Model") and not rigs[m] then
		rigs[m] = { motors = {}, scanAt = 0, dist = 0, steer = 0, lastPos = nil, lastLook = nil }
	end
end

-- Wheel motors stream in with the truck: look for them again now and then until all four are there.
local function scan(m: Model, r: Rig)
	local now = os.clock()
	if #r.motors >= 4 or now - r.scanAt < 1 then
		return
	end
	r.scanAt = now
	table.clear(r.motors)
	for _, d in m:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == "WheelMotor" then
			table.insert(r.motors, d)
		end
	end
end

local function step(dt: number)
	if dt <= 0 then
		return
	end
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	for m, r in rigs do
		if not m.Parent then
			rigs[m] = nil
			continue
		end
		scan(m, r)
		local first = r.motors[1]
		local root = first and first.Part0
		if not root then
			continue
		end
		local cf = root.CFrame
		local pos, look = cf.Position, cf.LookVector
		local mine = m:GetAttribute("DriverId") == player.UserId
		if not mine and (pos - camPos).Magnitude > FAR then
			r.lastPos, r.lastLook = nil, nil
			continue
		end
		local moved = if r.lastPos then (pos - r.lastPos :: Vector3):Dot(look) else 0
		if math.abs(moved) > 20 then
			moved = 0 -- a teleport (respawn, PivotTo), not driving
		end
		r.dist += moved
		local speed = moved / dt
		-- steering angle: ours from the drive model, others' from how fast they turn (bicycle model backwards)
		local wanted = 0
		local localSteer = m:GetAttribute("LocalSteer")
		if mine and typeof(localSteer) == "number" then
			wanted = localSteer
		elseif r.lastLook and math.abs(speed) > 1 then
			local turned = -math.asin(math.clamp((r.lastLook :: Vector3):Cross(look).Y, -1, 1)) -- + = right
			local wb = m:GetAttribute("Wheelbase")
			local yawRate = turned / dt
			wanted = math.atan(yawRate * (if typeof(wb) == "number" then wb else 9) / speed)
		end
		wanted = math.clamp(wanted, -MAX_STEER, MAX_STEER)
		r.steer += (wanted - r.steer) * math.min(1, dt * (if mine then 30 else 8))
		r.lastPos, r.lastLook = pos, look

		for _, motor in r.motors do
			local radius = motor:GetAttribute("Radius")
			local spin = r.dist / (if typeof(radius) == "number" and radius > 0 then radius else 1.4)
			local roll = CFrame.Angles(-spin, 0, 0) -- forward = the top of the wheel moves toward the nose (-Z)
			if motor:GetAttribute("Front") == true then
				motor.Transform = CFrame.Angles(0, -r.steer, 0) * roll
			else
				motor.Transform = roll
			end
		end
	end
end

function WheelController.Start()
	for _, m in CollectionService:GetTagged("SpinWheels") do
		add(m)
	end
	CollectionService:GetInstanceAddedSignal("SpinWheels"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("SpinWheels"):Connect(function(m)
		if m:IsA("Model") then
			rigs[m] = nil
		end
	end)
	RunService.Stepped:Connect(function(_, dt)
		step(dt)
	end)
end

return WheelController
