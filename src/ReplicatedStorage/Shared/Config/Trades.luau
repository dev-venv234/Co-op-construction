--!strict
-- Trades: display text and crew slot limits. No money in here.
local C = Color3.fromRGB

return {
	-- Welder and HVAC added 2026-11-13 (owner request; PLAN.md had 4 launch trades)
	Order = { "Foreman", "Laborer", "Operator", "Electrician", "Welder", "HVAC" },
	Info = {
		Foreman = {
			Max = 1,
			Color = C(255, 170, 40),
			Description = "Drives stakes, checks level, braces walls. Calls the inspection.",
		},
		Laborer = {
			Max = 6,
			Color = C(80, 200, 120),
			Description = "Carries and places posts, lumber and roof sheets. Pours and nails.",
		},
		Operator = {
			Max = 1,
			Color = C(80, 160, 255),
			Description = "Drives the truck, digs holes with the excavator, runs the crane.",
		},
		Electrician = {
			Max = 2,
			Color = C(240, 200, 40),
			Description = "Sets outlet boxes, runs circuits, mounts the panel and lights. Powers it on.",
		},
		Welder = {
			Max = 2,
			Color = C(235, 110, 50),
			Description = "Welds the steel: pier plates, roof brackets, railings and hinges. Trace the seam.",
		},
		HVAC = {
			Max = 2,
			Color = C(70, 190, 200),
			Description = "Runs the ductwork, sets the vents, places the AC unit and charges it.",
		},
	},
}
