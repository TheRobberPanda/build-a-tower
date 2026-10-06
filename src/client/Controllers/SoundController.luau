--!strict
-- Client sounds driven by server events: place/delete (piece count changes),
-- run results, and the ambient loop. Jump pads play from MechanicsController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local SoundController = {}

local lastCount: number? = nil

function SoundController.start()
	Sounds.music("Ambient")
	Remotes.event("TowerChanged").OnClientEvent:Connect(function(tower)
		local count = if type(tower) == "table" and type(tower.pieces) == "table" then #tower.pieces else 0
		if lastCount then
			if count > lastCount then
				Sounds.play("Place")
			elseif count < lastCount then
				Sounds.play("Delete")
			end
		end
		lastCount = count
	end)
	Remotes.event("RunResult").OnClientEvent:Connect(function(ok, _ms, _improved, message)
		if ok == true then
			Sounds.play("Finish")
		elseif type(message) == "string" then
			Sounds.play("Fail")
		end
	end)
end

return SoundController
