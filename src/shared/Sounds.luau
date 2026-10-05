--!strict
-- Sound asset ids and a tiny player. An empty id means silent, so the game runs
-- before the audio is sourced. Log every asset in CREDITS.md.

local SoundService = game:GetService("SoundService")

local Sounds = {}

Sounds.Ids = table.freeze({
	Place = "",
	Delete = "",
	JumpPad = "",
	Teleport = "",
	Finish = "",
	Fail = "",
	Ambient = "", -- looped quietly on the client
})

local VOLUME: { [string]: number } = {
	Place = 0.5,
	Delete = 0.5,
	JumpPad = 0.7,
	Teleport = 0.7,
	Finish = 0.8,
	Fail = 0.6,
	Ambient = 0.2,
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

-- Starts the looping ambient track; returns nil when no id is set.
function Sounds.startAmbient(): Sound?
	if Sounds.Ids.Ambient == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Ambient"
	sound.SoundId = Sounds.Ids.Ambient
	sound.Volume = VOLUME.Ambient
	sound.Looped = true
	sound.Parent = SoundService
	sound:Play()
	return sound
end

return Sounds
