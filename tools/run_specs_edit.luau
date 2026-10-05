-- Runs every TestEZ spec in Edit mode with fresh module loads (Studio caches
-- `require`, so plain require would test stale code). No playtest needed.
-- Paste into the command bar, or send through the MCP execute_luau tool.
local cache = {}
local freshRequire
local function load(module)
	if cache[module] ~= nil then return cache[module] end
	if module:IsDescendantOf(game.ServerStorage.DevPackages) then cache[module] = require(module) return cache[module] end
	local fn, err = loadstring(module.Source, module:GetFullName())
	assert(fn, err)
	setfenv(fn, setmetatable({ script = module, require = freshRequire }, { __index = getfenv(1) }))
	local result = fn()
	cache[module] = result
	return result
end
freshRequire = function(target)
	if typeof(target) == "Instance" and target:IsA("ModuleScript") then return load(target) end
	return require(target)
end
local TestEZ = require(game.ServerStorage.DevPackages.TestEZ)
local list = {}
for _, m in game.ServerScriptService.Tests:GetChildren() do
	if m.Name:match("%.spec$") then
		table.insert(list, { method = load(m), path = { m.Name }, pathStringForSorting = m.Name })
	end
end
local results = TestEZ.TestRunner.runPlan(TestEZ.TestPlanner.createPlan(list))
local lines = {}
local function walk(node)
	for _, child in node.children do
		if child.status == "Failure" then table.insert(lines, "FAIL " .. child.planNode.phrase .. ": " .. table.concat(child.errors, " | "):sub(1, 400)) end
		walk(child)
	end
end
walk(results)
table.insert(lines, string.format("passed %d failed %d", results.successCount, results.failureCount))
print(table.concat(lines, "\n"))
return table.concat(lines, "\n")
