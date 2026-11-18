--!strict
-- Day/night for each crew's shift (2026-11-17: several crews per server, so the sky is per crew and drawn on each
-- player's own client by DayNightController). 4:00 AM in the dark at the RV park, the sun comes up while the crew
-- drives to its site (sunrise length = that site's drive time), morning light while working, then back to 4:00 AM
-- for the next shift. This service only decides each job's sky (cur.sky, sent with the crew's state):
--   predawn: the job has started, the truck is still at the RV park
--   sunrise: the truck left the park at t0 (server time); the sun is up after dur seconds
--   day:     morning light (drop-in starter jobs begin here)
-- Players without a running job are in the predawn shift. Night lights are switched on each client too.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Layout = require(ReplicatedStorage.Shared.Config.TownLayout)
local SitesConfig = require(ServerStorage.Config.Sites)

local DayNight = {}

local S: any

function DayNight.Init(services)
	S = services
end

local function insideRVPark(pos: Vector3): boolean
	for _, lot in Layout.Lots do
		if lot.Id == "RVPark" then
			return pos.X >= lot.Min.X - 6 and pos.X <= lot.Max.X + 6 and pos.Z >= lot.Min.Y - 6 and pos.Z <= lot.Max.Y + 6
		end
	end
	return false
end

local function setSky(cur: any, mode: string, dur: number?)
	cur.sky = { mode = mode, t0 = workspace:GetServerTimeNow(), dur = dur or 0 }
	S.JobService.Broadcast()
end

-- After a crew starts a job from the RV park, its sun starts rising when its truck leaves the park.
local function watchDrive(cur: any)
	local site = SitesConfig[cur.siteId]
	task.spawn(function()
		while S.JobService.Live(cur) and not cur.finishing and cur.sky and cur.sky.mode == "predawn" do
			if cur.truck and not insideRVPark(S.VehicleService.Position(cur.truck)) then
				setSky(cur, "sunrise", math.max(5, site and site.DriveSeconds or 45))
				break
			end
			task.wait(0.5)
		end
	end)
end

function DayNight.Start()
	S.JobService.Started.Event:Connect(function(cur, dropIn: boolean)
		if dropIn then
			setSky(cur, "day") -- first-timers start in morning light
		else
			setSky(cur, "predawn")
			watchDrive(cur)
		end
	end)
end

return DayNight
