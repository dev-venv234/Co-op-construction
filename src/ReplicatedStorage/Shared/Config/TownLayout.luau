--!strict
-- Town layout (studs). North = -Z. Ground surface is y = 0. All edges sit on the 4-stud terrain grid.
-- Used by the town builder (ServerStorage.DevTools.TownBuilder) and, later, by the session flow for
-- spawn points, site positions and driveway gates. No money here (site pay lives in ServerStorage config).
--
-- Drive distances from the RV park gate (0, -400), starter truck top speed 36 studs/s:
--   T1 Shed          ~1,010 studs, 0 turns  -> ~31 s
--   T2 Starter house ~1,560 studs, 2 turns  -> ~48 s
--   T3 Two-story     ~1,930 studs, 2 turns  -> ~59 s
--   T4 Luxury        ~2,630 studs, 2 turns  -> ~78 s
-- (distance / 36 + ~1 s to reach top speed + ~1 s per turn). Target from the design brief: 30-90 s.

local V2 = Vector2.new

return {
	RoadWidth = 32,
	SidewalkWidth = 8,
	Bounds = { MinX = -1400, MaxX = 1400, MinZ = -2800, MaxZ = 400 },

	-- Straight roads. Axis "X" runs east-west at z = At; Axis "Z" runs north-south at x = At.
	Roads = {
		{ Name = "Main St", Axis = "X", At = -400, From = -1000, To = 1100 },
		{ Name = "Oak Ave", Axis = "Z", At = 0, From = -2200, To = -400 },
		{ Name = "Pine Rd", Axis = "Z", At = -1000, From = -1400, To = -400 },
		{ Name = "Ridge Rd", Axis = "X", At = -1400, From = -1000, To = 1040 },
		{ Name = "Hilltop Dr", Axis = "X", At = -2200, From = -900, To = 0 },
	},

	-- Lots: Min/Max are x,z corners. Gate = where the driveway meets the road (Side -1 = north/west, +1 = south/east).
	Lots = {
		{ Id = "RVPark", Kind = "RVPark", Label = "RV PARK", Min = V2(-160, -372), Max = V2(160, -180),
			Gate = { Road = "Main St", At = 0, Side = 1, Width = 28 } },
		{ Id = "Site_T1", Kind = "Site", Tier = 1, Label = "SITE 1 - SHED", Min = V2(920, -372), Max = V2(1080, -212),
			Gate = { Road = "Main St", At = 1000, Side = 1, Width = 28 } },
		{ Id = "Site_T2", Kind = "Site", Tier = 2, Label = "SITE 2 - STARTER HOUSE", Min = V2(-972, -1052), Max = V2(-772, -852),
			Gate = { Road = "Pine Rd", At = -952, Side = 1, Width = 28 } },
		-- extra lots (2026-11-17, several crews per server): two more sheds west of Site 1 on Main St, two more starter
		-- houses north and south of Site 2 on Pine Rd
		{ Id = "Site_T1b", Kind = "Site", Tier = 1, Label = "SITE 1B - SHED", Min = V2(720, -372), Max = V2(880, -212),
			Gate = { Road = "Main St", At = 800, Side = 1, Width = 28 } },
		{ Id = "Site_T1c", Kind = "Site", Tier = 1, Label = "SITE 1C - SHED", Min = V2(520, -372), Max = V2(680, -212),
			Gate = { Road = "Main St", At = 600, Side = 1, Width = 28 } },
		{ Id = "Site_T2b", Kind = "Site", Tier = 2, Label = "SITE 2B - STARTER HOUSE", Min = V2(-972, -1292), Max = V2(-772, -1092),
			Gate = { Road = "Pine Rd", At = -1192, Side = 1, Width = 28 } },
		{ Id = "Site_T2c", Kind = "Site", Tier = 2, Label = "SITE 2C - STARTER HOUSE", Min = V2(-972, -812), Max = V2(-772, -612),
			Gate = { Road = "Pine Rd", At = -712, Side = 1, Width = 28 } },
		{ Id = "Site_T3", Kind = "Site", Tier = 3, Label = "SITE 3 - TWO-STORY", Min = V2(800, -1652), Max = V2(1040, -1428),
			Gate = { Road = "Ridge Rd", At = 920, Side = -1, Width = 28 } },
		{ Id = "Site_T4", Kind = "Site", Tier = 4, Label = "SITE 4 - LUXURY HOME", Min = V2(-960, -2512), Max = V2(-680, -2228),
			Gate = { Road = "Hilltop Dr", At = -820, Side = -1, Width = 28 } },
		{ Id = "GasStation", Kind = "Filler", Label = "GAS STATION", Min = V2(28, -548), Max = V2(148, -428),
			Gate = { Road = "Main St", At = 88, Side = -1, Width = 24 } },
		{ Id = "Hardware", Kind = "Filler", Label = "HARDWARE STORE", Min = V2(-176, -548), Max = V2(-28, -428),
			Gate = { Road = "Main St", At = -100, Side = -1, Width = 24 } },
		{ Id = "House_W1", Kind = "Filler", Label = "HOUSE", Min = V2(-108, -740), Max = V2(-28, -660),
			Gate = { Road = "Oak Ave", At = -700, Side = -1, Width = 16 } },
		{ Id = "House_W2", Kind = "Filler", Label = "HOUSE", Min = V2(-108, -940), Max = V2(-28, -860),
			Gate = { Road = "Oak Ave", At = -900, Side = -1, Width = 16 } },
		{ Id = "House_W3", Kind = "Filler", Label = "HOUSE", Min = V2(-108, -1140), Max = V2(-28, -1060),
			Gate = { Road = "Oak Ave", At = -1100, Side = -1, Width = 16 } },
		{ Id = "House_E1", Kind = "Filler", Label = "HOUSE", Min = V2(28, -740), Max = V2(108, -660),
			Gate = { Road = "Oak Ave", At = -700, Side = 1, Width = 16 } },
		{ Id = "House_E2", Kind = "Filler", Label = "HOUSE", Min = V2(28, -940), Max = V2(108, -860),
			Gate = { Road = "Oak Ave", At = -900, Side = 1, Width = 16 } },
		{ Id = "House_E3", Kind = "Filler", Label = "HOUSE", Min = V2(28, -1140), Max = V2(108, -1060),
			Gate = { Road = "Oak Ave", At = -1100, Side = 1, Width = 16 } },
	},

	-- Decorative grass hills around the edges (center y below ground so only a cap shows).
	Hills = {
		{ X = -700, Y = -70, Z = -2720, R = 130 },
		{ X = -350, Y = -80, Z = -2760, R = 150 },
		{ X = 300, Y = -70, Z = -2700, R = 140 },
		{ X = 1330, Y = -60, Z = -1900, R = 120 },
		{ X = 1320, Y = -70, Z = -900, R = 130 },
		{ X = -1330, Y = -60, Z = -1800, R = 120 },
		{ X = -1320, Y = -70, Z = -600, R = 120 },
		{ X = 700, Y = -60, Z = -2200, R = 110 },
	},

	-- Zebra crossings at the town center (Main St / Oak Ave).
	Crosswalks = {
		{ Road = "Main St", At = -24 },
		{ Road = "Main St", At = 24 },
		{ Road = "Oak Ave", At = -428 },
	},

	StreetlightSpacing = 120,
}
