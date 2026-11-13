--!strict
-- AUTHORITATIVE crew trucks (server only). Capacity = material bundles the bed holds; a job whose load is bigger
-- than that takes more than one trip from the RV park dock. Price is paid at the truck dealer (RV park lot),
-- which opens after the first paycheck. The best truck must stay earnable by grinding (CLAUDE.md).
return {
	Order = { "StarterTruck", "WorkPickup" },
	StarterTruck = { DisplayName = "Rusty starter truck", Price = 0, Capacity = 4 },
	WorkPickup = { DisplayName = "Work pickup", Price = 3000, Capacity = 8 },
}
