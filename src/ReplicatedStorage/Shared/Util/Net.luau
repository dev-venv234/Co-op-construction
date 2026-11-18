--!strict
-- Remote names live here so client and server agree. The server creates them; clients wait.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Names = {
	-- client -> server (requests only; the server validates everything)
	"Hello", "PickRole", "TimingTap", "ConnectSubmit", "CancelTask", "DropItem", "DriveInput",
	"QuickJoin", "Ping", "KickVote", "SaveSettings", "Company", "MachineInput", "TraceSubmit", "GaugeHold", "Shop",
	"Purchase", "CrewAction",
	-- server -> client
	"State", "TaskBegin", "TaskEnd", "Toast", "Payout", "PingShown", "Sfx", "CompanyData", "ShopData", "PurchaseData",
	"Crews",
}

local folder = ReplicatedStorage:WaitForChild("Remotes")

function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup is server only")
	for _, name in Net.Names do
		if not folder:FindFirstChild(name) then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = folder
		end
	end
end

function Net.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Server: a sound cue for everyone (a name from Shared/Config/Sounds, and where it happened; nil = not in the world).
-- Clients play it with their own volume settings (SoundController).
function Net.Cue(name: string, pos: Vector3?)
	local e = folder:FindFirstChild("Sfx")
	if e and e:IsA("RemoteEvent") then
		e:FireAllClients(name, pos)
	end
end

return Net
