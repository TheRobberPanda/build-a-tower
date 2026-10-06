--!strict
-- Sound asset ids and a tiny player. An empty id means silent, so the game runs
-- before the audio is sourced. Log every asset in CREDITS.md.

local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.Ids = table.freeze({
	Place = "rbxassetid://76820444954643",
	Delete = "rbxassetid://138546948480498",
	JumpPad = "rbxassetid://121431627776116",
	Teleport = "rbxassetid://130698977470767",
	Finish = "rbxassetid://86004459095908",
	Fail = "rbxassetid://99974427251680",
	Ambient = "rbxassetid://140662085604483",
	Checkpoint = "rbxassetid://138773923531137",
	LevelUp = "rbxassetid://132886095093109",
	Crumble = "rbxassetid://109580080804011",
	Door = "rbxassetid://131464703611095", -- looped quietly on the client
	-- Round music and stings (APMOfficial / DistrokidOfficial / ProSoundEffects, licensed for Roblox)
	BuildMusic = "rbxassetid://80191016555521",
	RaceMusic = "rbxassetid://1843108763",
	RoundStart = "rbxassetid://1837769261",
	Victory = "rbxassetid://1836473422",
	Cheer = "rbxassetid://9112766176",
})

local VOLUME: { [string]: number } = {
	Place = 0.5,
	Delete = 0.5,
	JumpPad = 0.7,
	Teleport = 0.7,
	Finish = 0.8,
	Fail = 0.6,
	Ambient = 0.2,
	Checkpoint = 0.6,
	LevelUp = 0.8,
	Crumble = 0.6,
	Door = 0.6,
	BuildMusic = 0.25,
	RaceMusic = 0.3,
	RoundStart = 0.7,
	Victory = 0.7,
	Cheer = 0.5,
}

-- Plays a one-shot. With `at`, the sound is positional (heard by everyone nearby);
-- otherwise it plays locally, so call that form from the client.
function Sounds.play(name: string, at: BasePart?)
	local id = (Sounds.Ids :: any)[name]
	if type(id) ~= "string" or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = VOLUME[name] or 0.5
	if at then
		sound.Parent = at
		sound:Play()
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	else
		SoundService:PlayLocalSound(sound)
		sound:Destroy()
	end
end

-- Switches the looping music track (cross-fade free: stop old, start new).
local current: Sound? = nil
function Sounds.music(name: string)
	local id = (Sounds.Ids :: any)[name]
	if current and current.Name == name then
		return
	end
	if current then
		current:Destroy()
		current = nil
	end
	if type(id) ~= "string" or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = VOLUME[name] or 0.2
	sound.Looped = true
	sound.Parent = SoundService
	sound:Play()
	current = sound
end

return Sounds
