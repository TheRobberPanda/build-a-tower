--!strict
-- Studio-only: lets tools end a playtest remotely. Edit mode writes the current
-- os.time() to DataStore QA_v1 key "stop" (tools/stop_playtest.sh); the running
-- server sees a newer value than its own start time and ends the test.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local store = game:GetService("DataStoreService"):GetDataStore("QA_v1")
local startedAt = os.time()
while true do
	task.wait(3)
	local ok, value = pcall(function()
		return store:GetAsync("stop")
	end)
	if ok and type(value) == "number" and value >= startedAt then
		local DataService = require(game:GetService("ServerScriptService").Server.Services.DataService) :: any
		DataService.releaseAll() -- same save + unlock as a normal shutdown
		pcall(function()
			game:GetService("StudioTestService"):EndTest("stopped")
		end)
		return
	end
end
