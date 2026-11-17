--!strict
-- AUTHORITATIVE job economy numbers. Server only (ServerStorage is invisible to clients).
-- Pay is per player. EarlyBonus applies when the job ends with EarlyThreshold seconds or more left.
-- Load: bundles the crew hauls from the RV park dock. A load bigger than the truck's Capacity (Config/Vehicles:
-- starter 4, Work pickup 8) takes more than one trip. The first unload of each item at the site's delivery pad
-- creates its material pile; other materials (stakes, posts) wait at the site.
local function job(blueprint: string, pay: number, minutes: number, earlyThreshold: number, load: { [string]: number })
	return {
		Blueprint = blueprint,
		BasePay = pay,
		Deadline = minutes * 60,
		EarlyBonus = 0.25,
		EarlyThreshold = earlyThreshold,
		MinQuality = 0.5,
		MaxQuality = 1.5,
		-- A full paycheck needs a fair share of the job (EconomyService.PayShare): ShareTasks of the job's tasks
		-- (never fewer than ShareTasksMin or more than ShareTasksMax), and being on the server for SharePresent
		-- of the job's length. Less than that pays in proportion.
		ShareTasks = 0.1,
		ShareTasksMin = 3,
		ShareTasksMax = 10,
		SharePresent = 0.5,
		Load = load,
	}
end

return {
	Shed = job("Shed", 500, 8, 60, { Lumber = 2, Sheet = 1 }),
	StarterHouse = job("StarterHouse", 1500, 15, 120, { Lumber = 4, Sheet = 2 }), -- 6: starter truck 2 trips, pickup 1
	TwoStory = job("TwoStory", 4000, 25, 180, { Lumber = 5, Sheet = 3 }), -- 8
	Luxury = job("Luxury", 10000, 35, 240, { Lumber = 5, Sheet = 3 }), -- 8
}
