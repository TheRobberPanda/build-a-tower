--!strict
-- Runs TestEZ specs in Studio only. Output appears in the Output window.
if not game:GetService("RunService"):IsStudio() then
	return
end
local TestEZ =
	require(game:GetService("ServerStorage"):WaitForChild("DevPackages"):WaitForChild("TestEZ")) :: any
local results = TestEZ.TestBootstrap:run({ script.Parent })
if results.failureCount > 0 then
	warn(string.format("[Tests] %d failed", results.failureCount))
else
	print(string.format("[Tests] all %d passed", results.successCount))
end
