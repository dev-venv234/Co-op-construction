--!strict
-- AUTHORITATIVE site table (server only). Each site is a lot in Shared.Config.TownLayout.
-- Yaw turns the blueprint so its front (local -Z) faces the site's road gate.
-- MinLevel: best trade level needed to start the site. DriveSeconds: drive from the RV park (sunrise length).
-- Release "Update" sites (tiers 3-4) can only be started in Studio until they ship.
-- Truck: the site needs that truck owned by whoever starts it ("trade lvl 8 + mid truck"); the job then uses it.
return {
	Order = { "Site_T1", "Site_T2", "Site_T3", "Site_T4" },
	Site_T1 = { Tier = 1, Job = "Shed", Yaw = 0, Release = "Launch", MinLevel = 1, DriveSeconds = 31 }, -- gate north (Main St)
	Site_T2 = { Tier = 2, Job = "StarterHouse", Yaw = math.pi / 2, Release = "Launch", MinLevel = 3, DriveSeconds = 48 }, -- gate west (Pine Rd)
	Site_T3 = { Tier = 3, Job = "TwoStory", Yaw = math.pi, Release = "Update", MinLevel = 8, DriveSeconds = 59, Truck = "WorkPickup" }, -- gate south (Ridge Rd)
	Site_T4 = { Tier = 4, Job = "Luxury", Yaw = math.pi, Release = "Update", MinLevel = 15, DriveSeconds = 78, Truck = "WorkPickup" }, -- gate south (Hilltop Dr)
}
