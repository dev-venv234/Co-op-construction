--!strict
-- DISPLAY copy of the job sites (signs, site board). Authoritative pay and unlock rules live in
-- ServerStorage.Config. Release: "Launch" sites are playable at launch; "Update" sites come later.
return {
	{ Tier = 1, Name = "Shed", Lot = "Site_T1", Minutes = 8, Pay = "$500", Unlock = "Open to everyone", Release = "Launch" },
	{ Tier = 2, Name = "Starter House", Lot = "Site_T2", Minutes = 15, Pay = "$1,500", Unlock = "Trade level 3", Release = "Launch" },
	{ Tier = 3, Name = "Two-Story Home", Lot = "Site_T3", Minutes = 25, Pay = "$4,000", Unlock = "Trade level 8 + mid truck", Release = "Update" },
	{ Tier = 4, Name = "Luxury Home", Lot = "Site_T4", Minutes = 35, Pay = "$10,000", Unlock = "Trade level 15", Release = "Update" },
}
