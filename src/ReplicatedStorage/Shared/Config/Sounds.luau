--!strict
-- Every sound the game plays (played on each client by SoundController, so each player's volume settings apply).
-- Sources: Pro Sound Effects and APM Music uploads are licensed by Roblox for every experience; the truck idle and
-- the metal crash are public uploads; rbxasset:// sounds ship with Roblox. All checked to load here (2026-11-11).
-- Group = which volume setting controls it (Master scales everything).
export type Def = { Id: string, Volume: number, Group: string, Loop: boolean? }

local Sounds: { [string]: any } = {
	-- machines: 3D loops on the seat, pitch follows speed
	EngineTruck = { Id = "rbxassetid://73621051922669", Volume = 0.5, Group = "Effects", Loop = true },
	EngineHeavy = { Id = "rbxassetid://9112754989", Volume = 0.45, Group = "Effects", Loop = true },
	-- building: 3D one-shots where the work happened (server cues)
	Hammer = { Id = "rbxassetid://9114756156", Volume = 0.8, Group = "Effects" },
	Place = { Id = "rbxassetid://9120870891", Volume = 0.7, Group = "Effects" },
	Spark = { Id = "rbxassetid://9116275998", Volume = 0.45, Group = "Effects" },
	Whistle = { Id = "rbxassetid://9118113825", Volume = 0.6, Group = "Effects" },
	CrashWood = { Id = "rbxassetid://9120963881", Volume = 0.9, Group = "Effects" },
	CrashMetal = { Id = "rbxassetid://17806435952", Volume = 0.9, Group = "Effects" },
	-- feedback: 2D
	Cash = { Id = "rbxassetid://120891770644830", Volume = 0.8, Group = "Effects" },
	Chime = { Id = "rbxassetid://9040193225", Volume = 0.45, Group = "Effects" },
	Click = { Id = "rbxasset://sounds/switch.wav", Volume = 0.5, Group = "Effects" },
	Ping = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Group = "Effects" },
	Miss = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.6, Group = "Effects" },
	-- world: 2D loops
	Birds = { Id = "rbxassetid://9112749254", Volume = 0.35, Group = "Ambient", Loop = true },
	Crickets = { Id = "rbxassetid://9112764040", Volume = 0.3, Group = "Ambient", Loop = true },
	Rain = { Id = "rbxassetid://9112853287", Volume = 0.6, Group = "Ambient", Loop = true },
	Thunder = { Id = "rbxassetid://4961240438", Volume = 0.6, Group = "Ambient" },
}

-- Music: a playlist, one track after another (APM Music).
Sounds.MusicTracks = { "rbxassetid://9047650745", "rbxassetid://1840629525", "rbxassetid://1835554544" }
Sounds.MusicVolume = 0.3

return Sounds
