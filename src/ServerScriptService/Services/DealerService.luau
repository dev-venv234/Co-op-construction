--!strict
-- Truck dealer in the RV park truck lot (stall 6): a showroom Work pickup, a sign and a kiosk prompt.
-- Opens after the first paycheck (CLAUDE.md: "truck dealer ... unlock after the first payout").
-- One tap does the right thing for that player: buy it (price from Config/Vehicles, paid on the server), or switch
-- which truck their jobs spawn with. The client only rewrites the prompt text (DealerController).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Net = require(ReplicatedStorage.Shared.Util.Net)
local VehiclesConfig = require(ServerStorage.Config.Vehicles)

local Dealer = {}

local KIND = "WorkPickup"
local STALL = "Stall_6"
local REACH = 12

local S: any
local Toast: RemoteEvent
local kiosk: BasePart? = nil

local C = Color3.fromRGB
local M = Enum.Material

function Dealer.Init(services)
	S = services
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function signText(p: BasePart, face: Enum.NormalId, lines: { { string | number | Color3 } })
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0.3
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sg
	for i, line in lines do
		local t = Instance.new("TextLabel")
		t.LayoutOrder = i
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, line[2] :: number, 0)
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = line[3] :: Color3
		t.Text = line[1] :: string
		t.Parent = sg
	end
	sg.Parent = p
end

local function onTap(p: Player)
	if not S.TaskEngine.Guard.Allow(p, "Dealer", 1) then
		return
	end
	local c = p.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not kiosk or not root or (root.Position - kiosk.Position).Magnitude > REACH then
		return
	end
	local prof = S.DataService.Get(p)
	if not prof then
		Toast:FireClient(p, "Still loading your profile, try again in a moment")
		return
	end
	if not prof.FirstPayout then
		Toast:FireClient(p, "The truck dealer opens after your first paycheck")
		return
	end
	local cfg = VehiclesConfig[KIND]
	local starter = VehiclesConfig.StarterTruck
	if S.DataService.OwnsVehicle(p, KIND) then
		if S.DataService.SelectedTruck(p) == KIND then
			S.DataService.SetSelectedTruck(p, "StarterTruck")
			Toast:FireClient(p, ("Your next job uses the %s (holds %d)"):format(starter.DisplayName, starter.Capacity))
		else
			S.DataService.SetSelectedTruck(p, KIND)
			Toast:FireClient(p, ("Your next job uses the %s (holds %d)"):format(cfg.DisplayName, cfg.Capacity))
		end
		task.spawn(S.DataService.Save, p, false)
		return
	end
	if not S.EconomyService.TrySpend(p, cfg.Price, "Bought " .. cfg.DisplayName) then
		local ls = p:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Cash") :: IntValue?
		Toast:FireClient(p, ("The %s costs $%d. You have $%d: keep working!"):format(cfg.DisplayName, cfg.Price, if cash then cash.Value else 0))
		return
	end
	S.DataService.GrantVehicle(p, KIND)
	S.DataService.SetSelectedTruck(p, KIND)
	task.spawn(S.DataService.Save, p, false)
	Toast:FireClient(p, ("You bought the %s! It holds %d bundles, so big loads go in one trip. Your next job uses it."):format(
		cfg.DisplayName, cfg.Capacity))
end

local function build(lot: Instance, stall: BasePart)
	local old = lot:FindFirstChild("TruckDealer")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "TruckDealer"
	m.Parent = lot
	local cfg = VehiclesConfig[KIND]
	local starter = VehiclesConfig.StarterTruck
	local base = stall.Position

	S.VehicleService.BuildDisplay(KIND, stall.CFrame, m)

	-- Sign behind the stall, facing the lot aisle (north, -Z)
	local signPos = Vector3.new(base.X, 9.5, base.Z + 13.5)
	local board = part("DealerSign", Vector3.new(16, 6, 0.5), CFrame.lookAt(signPos, signPos + Vector3.new(0, 0, -1)), C(30, 34, 40), M.Metal, m)
	signText(board, Enum.NormalId.Front, {
		{ "TRUCK DEALER", 0.3, C(255, 200, 60) },
		{ ("%s  $%d"):format(string.upper(cfg.DisplayName), cfg.Price), 0.24, C(245, 245, 240) },
		{ ("Holds %d bundles (starter truck: %d)"):format(cfg.Capacity, starter.Capacity), 0.18, C(170, 205, 235) },
		{ "Opens after your first paycheck", 0.14, C(200, 200, 200) },
	})
	part("SignTrim", Vector3.new(16.4, 0.4, 0.7), CFrame.new(signPos + Vector3.new(0, 3.2, 0)), C(240, 130, 30), M.Metal, m)
	for _, dx in { -7.5, 7.5 } do
		part("SignPost", Vector3.new(0.6, 12.5, 0.6), CFrame.new(base.X + dx, 6.25, base.Z + 13.9), C(70, 72, 76), M.Metal, m)
	end
	local glow = part("SignLight", Vector3.new(12, 0.2, 0.3), CFrame.new(signPos + Vector3.new(0, 3.5, -0.6)), C(255, 225, 170), M.Neon, m)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 14
	light.Angle = 100
	light.Brightness = 1.5
	light.Parent = glow

	-- Kiosk at the truck's front-left corner with the buy / switch prompt
	local k = part("DealerKiosk", Vector3.new(1.2, 3.6, 1.2), CFrame.new(base.X - 5.4, 1.8, base.Z - 7), C(60, 62, 68), M.Metal, m)
	local screen = part("KioskScreen", Vector3.new(1.0, 0.8, 0.1), CFrame.new(base.X - 5.4, 3.0, base.Z - 7.62), C(255, 200, 60), M.Neon, m)
	screen.CanCollide = false
	kiosk = k
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "DealerPrompt"
	pp.ActionText = ("Buy $%d"):format(cfg.Price)
	pp.ObjectText = ("%s (holds %d)"):format(cfg.DisplayName, cfg.Capacity)
	pp.HoldDuration = 0.8
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.GamepadKeyCode = Enum.KeyCode.ButtonX
	pp:SetAttribute("DealerTruck", KIND)
	pp:SetAttribute("Price", cfg.Price)
	pp:SetAttribute("Capacity", cfg.Capacity)
	pp:SetAttribute("DisplayName", cfg.DisplayName)
	pp.Parent = k
	S.JobService.RegisterPrompt(pp, onTap)
end

function Dealer.Start()
	Toast = Net.Event("Toast")
	local park = workspace:WaitForChild("RVPark", 10)
	local stall = park and park:FindFirstChild(STALL, true)
	if not park or not stall or not stall:IsA("BasePart") then
		warn("[Dealer] no RV park stall for the truck dealer")
		return
	end
	build(stall.Parent :: Instance, stall)
end

return Dealer
