--!strict
-- Trades playable in the gray box: display text and crew slot limits. No money in here.
local C = Color3.fromRGB

return {
	Order = { "Foreman", "Laborer", "Operator", "Electrician" },
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
	},
}
