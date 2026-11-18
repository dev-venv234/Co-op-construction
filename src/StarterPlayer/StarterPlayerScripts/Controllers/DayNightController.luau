--!strict
-- Each player's own sky (2026-11-17: several crews per server, each on its own shift). The server only says what the
-- crew's sky is doing (state.sky from DayNightService); this draws it locally:
--   no job / predawn: 4:00 AM in the dark, creeping toward 5:20 while the crew is at the RV park
--   sunrise: the sun comes up over the drive (t0, dur in server time), to 7:00
--   day: morning light, drifting slowly toward 11:30 while working
-- Night lights (parts with the NightLight attribute, and streetlights) switch on this client with the time of day, and
-- a rain delay on my crew's job (player attribute RainUntil) darkens the sky. Looks only.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = require(script.Parent.UIController)

local DayNight = {}

local player = Players.LocalPlayer
local NIGHT = 4.0 -- shift start
local PREDAWN_MAX = 5.3 -- creeps up to here while the crew is still at the RV park
local MORNING = 7.0 -- after the sunrise drive
local DAY_MAX = 11.5 -- slow drift while working
local LIGHTS_OFF = 6.4
local NIGHT_AMBIENT = Color3.fromRGB(85, 90, 115) -- dark, but readable on a phone
local DAY_AMBIENT = Color3.fromRGB(128, 128, 128)

type Lamp = { light: Light, lens: BasePart? }
local lamps: { [Light]: Lamp } = {}
local lightsOn: boolean? = nil
local predawnSince = os.clock()
local lastMode = "predawn"

local function consider(d: Instance)
	if not d:IsA("Light") then
		return
	end
	local part = d.Parent
	if not part or not part:IsA("BasePart") then
		return
	end
	local street = part.Parent ~= nil and part.Parent:GetAttribute("Streetlight") == true
	if part:GetAttribute("NightLight") == true or street then
		lamps[d] = { light = d, lens = if part.Material == Enum.Material.Neon then part else nil }
		if lightsOn ~= nil then
			d.Enabled = lightsOn
		end
		d.Destroying:Connect(function()
			lamps[d] = nil
		end)
	end
end

local function setLights(on: boolean)
	if lightsOn == on then
		return
	end
	lightsOn = on
	for l, lamp in lamps do
		if l.Parent then
			l.Enabled = on
			if lamp.lens then
				lamp.lens.Material = if on then Enum.Material.Neon else Enum.Material.Glass
			end
		end
	end
end

-- The clock for my crew's sky right now.
local function clockNow(): number
	local s = UI.State
	local sky = if s.active then s.sky else nil
	local mode = if typeof(sky) == "table" and typeof(sky.mode) == "string" then sky.mode else "predawn"
	if mode ~= lastMode then
		if mode == "predawn" then
			predawnSince = os.clock()
		end
		lastMode = mode
	end
	local predawn = math.min(PREDAWN_MAX, NIGHT + (os.clock() - predawnSince) / 360) -- 1 game hour per 6 real minutes
	if mode == "predawn" then
		return predawn
	end
	local now = workspace:GetServerTimeNow()
	local t0 = if typeof(sky.t0) == "number" then sky.t0 else now
	local dur = if typeof(sky.dur) == "number" then sky.dur else 0
	if mode == "sunrise" and now < t0 + dur then
		local a = math.clamp((now - t0) / math.max(dur, 1), 0, 1)
		local eased = a * a * (3 - 2 * a)
		return predawn + (MORNING - predawn) * eased
	end
	return math.min(DAY_MAX, MORNING + math.max(0, now - (t0 + dur)) / 450) -- 1 game hour per 7.5 real minutes
end

function DayNight.Start()
	for _, d in workspace:GetDescendants() do
		consider(d)
	end
	workspace.DescendantAdded:Connect(consider) -- streamed-in streetlights

	-- the place's own look, for the storm to darken and restore
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local base = {
		brightness = Lighting.Brightness,
		density = if atmo then atmo.Density else 0,
		haze = if atmo then atmo.Haze else 0,
		color = if atmo then atmo.Color else Color3.new(1, 1, 1),
	}
	local stormy = false
	local function setStorm(on: boolean)
		if stormy == on then
			return
		end
		stormy = on
		Lighting.Brightness = if on then base.brightness * 0.55 else base.brightness
		if atmo then
			atmo.Density = if on then math.max(base.density, 0.45) else base.density
			atmo.Haze = if on then math.max(base.haze, 2.5) else base.haze
			atmo.Color = if on then Color3.fromRGB(150, 155, 165) else base.color
		end
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local clock = clockNow()
		Lighting.ClockTime = clock
		Lighting.OutdoorAmbient = NIGHT_AMBIENT:Lerp(DAY_AMBIENT, math.clamp((clock - 5) / 2, 0, 1))
		setLights(clock < LIGHTS_OFF or clock > 18.5)
		local rain = player:GetAttribute("RainUntil")
		setStorm(typeof(rain) == "number" and rain > workspace:GetServerTimeNow())
	end)
end

return DayNight
