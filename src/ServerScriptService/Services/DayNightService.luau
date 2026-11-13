--!strict
-- Day/night for the shift: 4:00 AM start in the dark at the RV park, the sun comes up while the crew drives to the
-- site (sunrise length = that site's drive time), morning light while working, then back to 4:00 AM for the next
-- shift. Night lights (parts with the NightLight attribute, plus streetlights) switch with the time of day.
-- Server-only: Lighting changes replicate to every client.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Layout = require(ReplicatedStorage.Shared.Config.TownLayout)
local SitesConfig = require(ServerStorage.Config.Sites)

local DayNight = {}

local NIGHT = 4.0 -- shift start
local PREDAWN_MAX = 5.3 -- creeps up to here while the crew is still at the RV park
local MORNING = 7.0 -- after the sunrise drive
local DAY_MAX = 11.5 -- slow drift while working
local LIGHTS_OFF = 6.4
local UPDATE_EVERY = 0.2

local S: any
local mode = "predawn" -- predawn | sunrise | day
local sunrise = { from = NIGHT, to = MORNING, t0 = 0, dur = 1 }
local lights: { { light: Light, lens: BasePart? } } = {}
local lightsOn: boolean? = nil

function DayNight.Init(services)
	S = services
end

function DayNight.Mode(): string
	return mode
end

local function collectLights()
	table.clear(lights)
	for _, d in workspace:GetDescendants() do
		if d:IsA("Light") then
			local part = d.Parent
			if part and part:IsA("BasePart") then
				local street = part.Parent ~= nil and part.Parent:GetAttribute("Streetlight") == true
				if part:GetAttribute("NightLight") == true or street then
					table.insert(lights, { light = d, lens = if part.Material == Enum.Material.Neon then part else nil })
				end
			end
		end
	end
end

local function setLights(on: boolean)
	if lightsOn == on then
		return
	end
	lightsOn = on
	for _, l in lights do
		if l.light.Parent then
			l.light.Enabled = on
			if l.lens then
				l.lens.Material = if on then Enum.Material.Neon else Enum.Material.Glass
			end
		end
	end
end

local NIGHT_AMBIENT = Color3.fromRGB(85, 90, 115) -- dark, but readable on a phone
local DAY_AMBIENT = Color3.fromRGB(128, 128, 128)

local function applyLook(clock: number)
	local day = math.clamp((clock - 5) / 2, 0, 1)
	Lighting.OutdoorAmbient = NIGHT_AMBIENT:Lerp(DAY_AMBIENT, day)
	setLights(clock < LIGHTS_OFF or clock > 18.5)
end

function DayNight.NewShift()
	mode = "predawn"
	Lighting.ClockTime = NIGHT
	applyLook(NIGHT)
end

function DayNight.Morning()
	mode = "day"
	Lighting.ClockTime = MORNING
	applyLook(MORNING)
end

function DayNight.Sunrise(seconds: number)
	if mode ~= "predawn" then
		return
	end
	mode = "sunrise"
	sunrise = { from = Lighting.ClockTime, to = MORNING, t0 = os.clock(), dur = math.max(5, seconds) }
end

local function insideRVPark(pos: Vector3): boolean
	for _, lot in Layout.Lots do
		if lot.Id == "RVPark" then
			return pos.X >= lot.Min.X - 6 and pos.X <= lot.Max.X + 6 and pos.Z >= lot.Min.Y - 6 and pos.Z <= lot.Max.Y + 6
		end
	end
	return false
end

-- After a crew starts a job from the RV park, the sun starts rising when their truck leaves the park.
local function watchDrive(siteId: string)
	local site = SitesConfig[siteId]
	local cur = S.JobService.Current()
	task.spawn(function()
		while S.JobService.Current() == cur and cur and not cur.finishing and mode == "predawn" do
			if cur.truck and not insideRVPark(S.VehicleService.Position(cur.truck)) then
				DayNight.Sunrise(site and site.DriveSeconds or 45)
				break
			end
			task.wait(0.5)
		end
	end)
end

function DayNight.Start()
	collectLights()
	DayNight.NewShift()
	S.JobService.Started.Event:Connect(function(siteId: string, dropIn: boolean)
		if dropIn then
			DayNight.Morning() -- first-timers start in morning light
		else
			watchDrive(siteId)
		end
	end)
	S.JobService.Cleared.Event:Connect(DayNight.NewShift)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < UPDATE_EVERY then
			return
		end
		local step = acc
		acc = 0
		local clock = Lighting.ClockTime
		if mode == "predawn" then
			clock = math.min(PREDAWN_MAX, clock + step / 360) -- 1 game hour per 6 real minutes
		elseif mode == "sunrise" then
			local a = math.clamp((os.clock() - sunrise.t0) / sunrise.dur, 0, 1)
			local eased = a * a * (3 - 2 * a)
			clock = sunrise.from + (sunrise.to - sunrise.from) * eased
			if a >= 1 then
				mode = "day"
			end
		else
			clock = math.min(DAY_MAX, clock + step / 450) -- 1 game hour per 7.5 real minutes
		end
		Lighting.ClockTime = clock
		applyLook(clock)
	end)
end

return DayNight
