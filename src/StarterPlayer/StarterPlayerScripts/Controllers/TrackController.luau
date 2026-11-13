--!strict
-- Moving tracks (2026-11-12, owner: "the tracks on the digger ... make them move"). Every machine tagged
-- "SpinTracks" (EquipmentService: the excavator, with TrackGauge / TrackY / TrackLength / TrackHeight / TrackWidth
-- attributes in its undercarriage's space) gets a loop of tread plates around each track, drawn on this client only.
-- The plates roll by how far the machine really moved: both tracks forward / back together, and in opposite
-- directions when it turns on the spot (the bottom run stays put on the ground, like real tracks).
-- Looks only: no collisions, no physics. Skipped past 250 studs.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Track = {}

local FAR = 250
local SPACING = 0.66 -- studs between plates

type Rig = {
	model: Model,
	folder: Folder?,
	plates: { BasePart },
	sides: { number }, -- per plate: -1 left track, 1 right track
	base: { number }, -- per plate: its spot on the loop at zero travel
	distL: number,
	distR: number,
	lastPos: Vector3?,
	lastLook: Vector3?,
	geo: { gauge: number, y: number, r: number, sx: number, per: number }?,
}

local rigs: { [Model]: Rig } = {}

local function num(m: Model, key: string, default: number): number
	local v = m:GetAttribute(key)
	return if typeof(v) == "number" then v else default
end

local function build(r: Rig)
	local m = r.model
	local len, h = num(m, "TrackLength", 8.4), num(m, "TrackHeight", 2.6)
	local width = num(m, "TrackWidth", 1.9)
	local radius = h / 2 + 0.03
	local sx = math.max(0.5, len / 2 - h / 2)
	local per = 4 * sx + 2 * math.pi * radius
	local n = math.max(8, math.floor(per / SPACING))
	r.geo = { gauge = num(m, "TrackGauge", 2.9), y = num(m, "TrackY", -0.1), r = radius, sx = sx, per = per }
	local folder = Instance.new("Folder")
	folder.Name = "Tracks_" .. m.Name
	for _, side in { -1, 1 } do
		for i = 0, n - 1 do
			local p = Instance.new("Part")
			p.Name = "TreadPlate"
			p.Size = Vector3.new(width, 0.18, per / n * 0.8)
			p.Color = Color3.fromRGB(46, 46, 49)
			p.Material = Enum.Material.Metal
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = folder
			table.insert(r.plates, p)
			table.insert(r.sides, side)
			table.insert(r.base, i * per / n)
		end
	end
	r.folder = folder
end

-- A spot on the loop (track space: Z along the track, Y up) and the plate's tilt. s grows the way the plates move
-- when the machine drives forward: along the bottom toward the back, up and over the top toward the front.
local function onLoop(s: number, sx: number, r: number): (Vector3, number)
	local bottom = 2 * sx
	local arc = math.pi * r
	if s < bottom then
		return Vector3.new(0, -r, -sx + s), math.pi
	end
	s -= bottom
	if s < arc then
		local u = s / r
		return Vector3.new(0, -r * math.cos(u), sx + r * math.sin(u)), math.atan2(math.sin(u), -math.cos(u))
	end
	s -= arc
	if s < bottom then
		return Vector3.new(0, r, sx - s), 0
	end
	s -= bottom
	local u = s / r
	return Vector3.new(0, r * math.cos(u), -sx - r * math.sin(u)), math.atan2(-math.sin(u), math.cos(u))
end

local cframes: { CFrame } = {}

local function step()
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	for m, r in rigs do
		local root = m.PrimaryPart
		if not m:IsDescendantOf(workspace) then
			if r.folder then
				r.folder:Destroy()
			end
			rigs[m] = nil
			continue
		end
		if not root then
			continue
		end
		local cf = root.CFrame
		if (cf.Position - camPos).Magnitude > FAR then
			if r.folder then
				r.folder.Parent = nil
			end
			r.lastPos = nil
			continue
		end
		if not r.geo then
			build(r)
		end
		local geo = r.geo :: any
		local pos, look = cf.Position, cf.LookVector
		local moved = false
		if r.lastPos and r.lastLook then
			local d = (pos - r.lastPos :: Vector3):Dot(look)
			local turned = -math.asin(math.clamp((r.lastLook :: Vector3):Cross(look).Y, -1, 1)) -- + = right
			if math.abs(d) > 20 then
				d = 0 -- a teleport, not driving
			end
			if d ~= 0 or turned ~= 0 then
				r.distL += d + turned * geo.gauge
				r.distR += d - turned * geo.gauge
				moved = true
			end
		end
		local first = r.lastPos == nil or (r.folder :: Folder).Parent == nil
		r.lastPos, r.lastLook = pos, look
		if not moved and not first then
			continue
		end
		(r.folder :: Folder).Parent = workspace
		table.clear(cframes)
		for i, p in r.plates do
			local side = r.sides[i]
			local dist = if side < 0 then r.distL else r.distR
			local s = (r.base[i] + dist) % geo.per
			local at, tilt = onLoop(s, geo.sx, geo.r)
			cframes[i] = cf * CFrame.new(side * geo.gauge, geo.y, 0) * CFrame.new(at) * CFrame.Angles(tilt, 0, 0)
		end
		workspace:BulkMoveTo(r.plates, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function add(m: Instance)
	if m:IsA("Model") and not rigs[m] then
		rigs[m] = { model = m, plates = {}, sides = {}, base = {}, distL = 0, distR = 0 }
	end
end

function Track.Start()
	for _, m in CollectionService:GetTagged("SpinTracks") do
		add(m)
	end
	CollectionService:GetInstanceAddedSignal("SpinTracks"):Connect(add)
	RunService.Heartbeat:Connect(step)
end

return Track
