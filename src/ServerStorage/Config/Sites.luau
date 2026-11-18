--!strict
-- AUTHORITATIVE site table (server only). Each key is a job tier on the RV park board ("Site 1" = the shed job);
-- Lots are the lots in Shared.Config.TownLayout where that job can be built. Several crews can work the same tier at
-- once, one lot each (2026-11-17: up to 6 crews per server, 8 lots). The blueprint is turned so its front (local -Z)
-- faces the lot's road gate (JobService works that out from the gate).
-- MinLevel: best trade level needed to start the site. DriveSeconds: drive from the RV park (sunrise length).
-- Release "Update" sites (tiers 3-4) can only be started in Studio until they ship.
-- Truck: the site needs that truck owned by whoever starts it ("trade lvl 8 + mid truck"); the job then uses it.
return {
	Order = { "Site_T1", "Site_T2", "Site_T3", "Site_T4" },
	Site_T1 = { Tier = 1, Job = "Shed", Release = "Launch", MinLevel = 1, DriveSeconds = 31,
		Lots = { "Site_T1", "Site_T1b", "Site_T1c" } }, -- Main St, gates north
	Site_T2 = { Tier = 2, Job = "StarterHouse", Release = "Launch", MinLevel = 3, DriveSeconds = 48,
		Lots = { "Site_T2", "Site_T2b", "Site_T2c" } }, -- Pine Rd, gates west
	Site_T3 = { Tier = 3, Job = "TwoStory", Release = "Update", MinLevel = 8, DriveSeconds = 59, Truck = "WorkPickup",
		Lots = { "Site_T3" } }, -- Ridge Rd, gate south
	Site_T4 = { Tier = 4, Job = "Luxury", Release = "Update", MinLevel = 15, DriveSeconds = 78, Truck = "WorkPickup",
		Lots = { "Site_T4" } }, -- Hilltop Dr, gate south
}
