--!strict
-- Tier 2: one-story starter house (15 min). Generated from the shared house blueprint.
local House = require(script.Parent.House)

return House.Make({ Id = "StarterHouse", DisplayName = "Starter House", W = 28, D = 20, Floors = 1, HouseZ = 10 })
