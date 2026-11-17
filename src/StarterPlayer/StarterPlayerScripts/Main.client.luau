--!strict
-- Boots every client controller in order.
local Controllers = script.Parent:WaitForChild("Controllers")
local TaskControllers = Controllers:WaitForChild("TaskControllers")
local RoleControllers = Controllers:WaitForChild("RoleControllers")

local list: { Instance } = {
	Controllers:WaitForChild("InputController"),
	Controllers:WaitForChild("UIController"),
	Controllers:WaitForChild("SettingsController"), -- before the controllers that read settings
	TaskControllers:WaitForChild("Timing"),
	TaskControllers:WaitForChild("Connect"),
	TaskControllers:WaitForChild("Trace"),
	TaskControllers:WaitForChild("Gauge"),
	Controllers:WaitForChild("VehicleController"),
	Controllers:WaitForChild("WheelController"),
	Controllers:WaitForChild("TrackController"),
	Controllers:WaitForChild("MachineController"),
	Controllers:WaitForChild("SiteBoardController"),
	Controllers:WaitForChild("RainController"),
	Controllers:WaitForChild("DealerController"),
	Controllers:WaitForChild("ToolShopController"),
	Controllers:WaitForChild("StoreController"),
	RoleControllers:WaitForChild("PromptFilter"),
	Controllers:WaitForChild("GuideController"),
	Controllers:WaitForChild("CrewController"),
	Controllers:WaitForChild("SoundController"),
	Controllers:WaitForChild("TrafficController"),
	Controllers:WaitForChild("CompanyController"),
}

for _, m in list do
	local c = require(m :: ModuleScript) :: any
	if c.Start then
		c.Start()
	end
end
