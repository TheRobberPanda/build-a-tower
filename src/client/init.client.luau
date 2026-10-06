--!strict
-- Client entry point. Two-phase bootstrap: init() every controller, then start().

local Controllers = script:FindFirstChild("Controllers")

local loaded: { [string]: any } = {}
if Controllers then
	for _, child in Controllers:GetChildren() do
		if child:IsA("ModuleScript") then
			loaded[child.Name] = require(child) :: any
		end
	end
end

-- One controller failing to init must not stop the others (pieces would lose
-- their client behaviour).
for name, controller in loaded do
	if typeof(controller.init) == "function" then
		local ok, err = pcall(controller.init)
		if not ok then
			warn(string.format("[Client] %s.init failed: %s", name, tostring(err)))
		end
	end
end

for _, controller in loaded do
	if typeof(controller.start) == "function" then
		task.spawn(controller.start)
	end
end
