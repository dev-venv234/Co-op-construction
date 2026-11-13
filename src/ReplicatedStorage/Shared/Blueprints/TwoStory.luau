--!strict
-- Tier 3: two-story family home (25 min). Generated from the shared house blueprint. Release: update.
local House = require(script.Parent.House)

return House.Make({ Id = "TwoStory", DisplayName = "Two-Story Home", W = 32, D = 24, Floors = 2, HouseZ = 10 })
