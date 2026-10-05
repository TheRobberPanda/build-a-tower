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

if not RunService:IsStudio() or ServerStorage:GetAttribute("RunQA") ~= true then
	return
end

local serverLog: { string } = {}
LogService.MessageOut:Connect(function(message, messageType)
	if messageType == Enum.MessageType.MessageError or messageType == Enum.MessageType.MessageWarning then
		if #serverLog < 60 then
			table.insert(serverLog, string.sub(message, 1, 300))
		end
	end
end)

local remote = Instance.new("RemoteEvent")
remote.Name = "QAReport"
remote.Parent = ReplicatedStorage
ReplicatedStorage:SetAttribute("QA", true)

local report: any = nil
remote.OnServerEvent:Connect(function(_player, data)
	report = data
end)

local started = os.clock()
while not report and os.clock() - started < 240 do
	task.wait(1)
end

local result = {
	client = report or "client report timed out",
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
