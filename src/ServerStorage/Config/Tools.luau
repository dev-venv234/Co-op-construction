--!strict
-- AUTHORITATIVE tool shop catalog (server only; the client gets a copy when it opens the shop). 2026-11-13.
-- Tools only make a trade's mini-game a bit easier (wider green, more room off the seam, more time). They never do
-- the work and never finish a job (monetization rule), and every one is bought with cash earned on jobs.
-- Effect keys are what TaskEngine / EquipmentService ask for: timing, trace, connect, machine, gauge:<Style>.
return {
	Order = { "ProHammer", "LaserLevel", "Vibrator", "WeldHelmet", "Manifold", "Pliers", "Joysticks" },
	ProHammer = { Name = "Pro Framing Hammer", Trade = "Laborer & Foreman", Price = 1200,
		Effect = { timing = 1.2 }, Desc = "Nailing and every tap task: green zone 20% wider" },
	LaserLevel = { Name = "Laser Level", Trade = "Foreman", Price = 1500,
		Effect = { ["gauge:Level"] = 1.35 }, Desc = "Level check: the band between the lines is 35% wider" },
	Vibrator = { Name = "Concrete Vibrator", Trade = "Laborer", Price = 1500,
		Effect = { ["gauge:Pour"] = 1.35 }, Desc = "Pouring concrete: the fill line is 35% wider" },
	WeldHelmet = { Name = "Auto-Dark Welding Helmet", Trade = "Welder", Price = 1800,
		Effect = { trace = 1.3 }, Desc = "Welding: 30% more room either side of the seam" },
	Manifold = { Name = "Digital Manifold Gauges", Trade = "HVAC", Price = 1800,
		Effect = { ["gauge:Charge"] = 1.35 }, Desc = "Charging refrigerant: the green is 35% wider" },
	Pliers = { Name = "Insulated Lineman's Pliers", Trade = "Electrician", Price = 1400,
		Effect = { connect = 1.5, ["gauge:Voltage"] = 1.25 }, Desc = "Wiring puzzles: 50% more time for full marks; power on: wider green" },
	Joysticks = { Name = "Precision Joysticks", Trade = "Operator", Price = 2200,
		Effect = { machine = 1.3 }, Desc = "Crane and excavator controls move 30% faster" },
}
