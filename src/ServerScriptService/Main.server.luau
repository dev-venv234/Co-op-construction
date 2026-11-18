--!strict
-- Boots every server service in order: require all, Init all (wire references), then Start all.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Util.Net)
Net.Setup()

local Services = ServerScriptService:WaitForChild("Services")
local ORDER = {
	"EconomyService",
	"DataService",
	"ProgressionService",
	"QualityService",
	"MoveGuard",
	"CrewService",
	"VehicleService",
	"EquipmentService",
	"BlueprintService",
	"DetailService",
	"TaskEngine",
	"BuffService",
	"JobService",
	"DealerService",
	"ToolShopService",
	"CompanyService",
	"BotService",
	"LeagueService",
	"TownLifeService",
	"ChaosService",
	"InspectionService",
	"PurchaseService",
	"DayNightService",
	"SessionService",
}

local loaded: { [string]: any } = {}
for _, name in ORDER do
	loaded[name] = require(Services:WaitForChild(name) :: ModuleScript)
end
for _, name in ORDER do
	if loaded[name].Init then
		loaded[name].Init(loaded)
	end
end
for _, name in ORDER do
	if loaded[name].Start then
		task.spawn(loaded[name].Start)
	end
end
print("[Main] Co Op construction server started")
