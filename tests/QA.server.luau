--!strict
-- Studio-only end-to-end QA. Runs only when ServerStorage has the attribute
-- RunQA = true (set from Edit mode before starting a playtest). The client half
-- (QAClient) plays the game through the real remotes and reports here; this
-- script adds server-side errors and ends the test with StudioTestService:EndTest,
-- which hands the report back to the plugin that started the playtest.

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local mode = ServerStorage:GetAttribute("RunQA")
if not RunService:IsStudio() or (mode ~= true and mode ~= 2 and mode ~= "ui") then
	return
end
-- RunQA = "ui": show the round vote panel, then the results board, for screenshots.
if mode == "ui" then
	local Remotes = require(ReplicatedStorage.Shared.Remotes)
	game:GetService("Players").PlayerAdded:Wait()
	task.wait(8)
	local now = workspace:GetServerTimeNow()
	ServerStorage:SetAttribute("RoundFast", nil)
	Remotes.event("Round"):FireAllClients({
		phase = "vote",
		endsAt = now + 20,
		builder = 1,
		builderName = "Builderman",
		winnerName = "Guest",
		members = {},
	})
	task.wait(8)
	Remotes.event("RoundResults"):FireAllClients({
		{ name = "Builderman", coins = 95, valid = true, stars = 4.5, wins = 1 },
		{ name = "Guest", coins = 55, valid = true, stars = 3, wins = 1 },
		{ name = "Noob", coins = 0, valid = false, wins = 0 },
	})
	task.wait(8)
	game:GetService("StudioTestService"):EndTest("ui")
	return
end

local serverLog: { string } = {}
LogService.MessageOut:Connect(function(message, messageType)
	if
		messageType == Enum.MessageType.MessageError
		or messageType == Enum.MessageType.MessageWarning
		or string.sub(message, 1, 7) == "[Round]"
	then
		if #serverLog < 60 then
			table.insert(serverLog, string.sub(message, 1, 300))
		end
	end
end)

ServerStorage:SetAttribute("RoundFast", true) -- play-mode copy only; Edit keeps its value
ServerStorage:SetAttribute("QABuildSeconds", if mode == 2 then 30 else 200)
ReplicatedStorage:SetAttribute("QA2", mode == 2)
local remote = Instance.new("RemoteEvent")
remote.Name = "QAReport"
remote.Parent = ReplicatedStorage
ReplicatedStorage:SetAttribute("QA", true)

local report: any = nil
local reports = {}
remote.OnServerEvent:Connect(function(_player, data)
	table.insert(reports, data)
	report = if mode == 2 then (if #reports >= 2 then reports else nil) else data
end)

local started = os.clock()
while not report and os.clock() - started < 420 do
	task.wait(1)
end

-- EndTest stops the server without the normal leave/save path, so save and
-- release every profile first (otherwise the lock stays and the last save is a
-- mid-run autosave).
local ServerScriptService = game:GetService("ServerScriptService")
local DataService = require(ServerScriptService.Server.Services.DataService) :: any
DataService.releaseAll()

local result = {
	client = report or (if #reports > 0 then reports else "client report timed out"),
	players = #game:GetService("Players"):GetPlayers(),
	serverLog = serverLog,
	seconds = math.floor(os.clock() - started),
}
print("[QA] done")
local ok, err = pcall(function()
	-- JSON so the plugin passes it back as text.
	game:GetService("StudioTestService"):EndTest(game:GetService("HttpService"):JSONEncode(result))
end)
if not ok then
	warn("[QA] EndTest failed: " .. tostring(err))
end
