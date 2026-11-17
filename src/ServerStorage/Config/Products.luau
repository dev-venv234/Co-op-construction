--!strict
-- AUTHORITATIVE monetization catalog (server only; clients get a display copy when they open the store). 2026-11-16.
-- Id = the developer product id (Type "Boost" / "Cash") or game pass id (Type "Pass") from the Creator Dashboard.
-- Ids created in the Creator Dashboard on 2026-11-17 (all on sale, fixed prices, managed pricing off). An item with
-- Id 0 would show in the store but can't be bought ("not on sale yet"). Robux is display text only: Roblox charges
-- what the dashboard says, so change both together.
-- Monetization rule (CLAUDE.md): sell speed, style and status. Nothing here finishes a job without the crew.
--   Boost: a crew-wide helper used through the normal job systems. Bought with nothing to use it on, it is kept as a
--          saved credit (profile.Credits) and used later for free.
--   Cash:  in-game cash through EconomyService.AddCash.
--   Pass:  2x Pay, for the buyer only (EconomyService.PayBoost in the payout).
return {
	Order = { "RushDelivery", "HirePro", "RetryInspection", "DoublePay", "CashS", "CashM", "CashL", "CashXL" },
	Items = {
		RushDelivery = { Type = "Boost", Id = 3732927916, Robux = 39, Name = "Rush Delivery",
			Desc = "The supplier trucks the job's materials straight to the site for the whole crew. No hauling." },
		HirePro = { Type = "Boost", Id = 3732928088, Robux = 79, Name = "Hire a Pro",
			Desc = "A skilled bot takes an empty trade for this job: faster and more accurate than the regular bot." },
		RetryInspection = { Type = "Boost", Id = 3732928149, Robux = 35, Name = "Retry Inspection",
			Desc = "Failed the final inspection? Rebuild what fell and get inspected again instead of paying for it." },
		DoublePay = { Type = "Pass", Id = 2093810959, Robux = 299, Multiplier = 2, Name = "2x Pay",
			Desc = "Your paycheck is doubled on every job, forever. Only yours: the crew's pay doesn't change." },
		CashS = { Type = "Cash", Id = 3732928197, Robux = 49, Cash = 1500, Name = "Cash: Toolbox", Desc = "$1,500 for trucks and tools." },
		CashM = { Type = "Cash", Id = 3732928261, Robux = 149, Cash = 5000, Name = "Cash: Truckload", Desc = "$5,000 for trucks and tools." },
		CashL = { Type = "Cash", Id = 3732928337, Robux = 299, Cash = 11000, Name = "Cash: Payroll", Desc = "$11,000 for trucks and tools." },
		CashXL = { Type = "Cash", Id = 3732928414, Robux = 499, Cash = 20000, Name = "Cash: Contractor", Desc = "$20,000 for trucks and tools." },
	},
}
