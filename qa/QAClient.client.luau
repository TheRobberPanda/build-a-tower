--!strict
-- Client half of the Studio-only QA run (see QA.server.luau). Plays the game the
-- way a player would: fires the same remotes as the UI and moves the character.
-- Works in tower slot 3 and empties it again, so real towers are not touched.
-- Never publishes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")

if not game:GetService("RunService"):IsStudio() then
	return
end
if ReplicatedStorage:GetAttribute("QA") ~= true then
	ReplicatedStorage:GetAttributeChangedSignal("QA"):Wait()
end

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local player = Players.LocalPlayer
local G = 4

local results: { { step: string, ok: boolean, detail: string? } } = {}
local clientLog: { string } = {}
LogService.MessageOut:Connect(function(message, messageType)
	if messageType == Enum.MessageType.MessageError or messageType == Enum.MessageType.MessageWarning then
		if #clientLog < 60 then
			table.insert(clientLog, string.sub(message, 1, 300))
		end
	end
end)

local function record(step: string, ok: boolean, detail: any?)
	table.insert(results, { step = step, ok = ok, detail = if detail ~= nil then tostring(detail) else nil })
end

-- Runs fn; an error counts as a failed step.
local function step(name: string, fn: () -> (boolean, any?))
	local ok, passed, detail = pcall(fn)
	if not ok then
		record(name, false, "error: " .. tostring(passed))
	else
		record(name, passed == true, detail)
	end
end

-- Latest server state mirrored from events.
local tower: any = nil
local verified = false
local lastResult: { any }? = nil
local runStarted = false
local splits = 0
local progress: any = nil
Remotes.event("TowerChanged").OnClientEvent:Connect(function(t, v)
	tower = t
	verified = v == true
end)
Remotes.event("RunResult").OnClientEvent:Connect(function(...)
	lastResult = table.pack(...)
end)
Remotes.event("RunStarted").OnClientEvent:Connect(function()
	runStarted = true
end)
Remotes.event("Split").OnClientEvent:Connect(function()
	splits += 1
end)
Remotes.event("Progress").OnClientEvent:Connect(function(p)
	progress = p
end)

local function waitFor(cond: () -> boolean, timeout: number): boolean
	local t = os.clock()
	while os.clock() - t < timeout do
		if cond() then
			return true
		end
		task.wait(0.1)
	end
	return cond()
end

local function count(): number
	return if tower and tower.pieces then #tower.pieces else -1
end

local function plotOrigin(): Vector3
	local plot = workspace:WaitForChild("Plots"):WaitForChild("Plot_" .. player.UserId)
	return plot:GetAttribute("Origin") :: Vector3
end

local function cellCenter(x: number, y: number, z: number): Vector3
	return plotOrigin() + Vector3.new(x + 0.5, y + 0.5, z + 0.5) * G
end

local function place(t: number, x: number, y: number, z: number, r: number?, p: any?): boolean
	local before = count()
	Remotes.event("PlacePiece"):FireServer(t, x, y, z, r or 0, p)
	return waitFor(function()
		return count() == before + 1
	end, 3)
end

local function clearTower()
	local guard = 0
	while count() > 0 and guard < 200 do
		guard += 1
		local piece = tower.pieces[1]
		local before = count()
		Remotes.event("RemovePiece"):FireServer(piece.x, piece.y, piece.z)
		waitFor(function()
			return count() < before
		end, 2)
		task.wait(0.12) -- stay under the edit rate limit
	end
end

local function character(): (Model, Humanoid, BasePart)
	local char = player.Character or player.CharacterAdded:Wait()
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	return char, humanoid, root
end

-- Walks to a world position; returns true if within `radius` before the timeout.
local function walkTo(pos: Vector3, timeout: number, radius: number?): boolean
	local _, humanoid, root = character()
	local t = os.clock()
	while os.clock() - t < timeout do
		humanoid:MoveTo(pos)
		local flat = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z)
		if flat.Magnitude < (radius or 2) then
			return true
		end
		task.wait(0.2)
	end
	return false
end

local function startRun(): boolean
	runStarted = false
	lastResult = nil
	task.wait(3.5) -- run start rate limit
	Remotes.event("StartRun"):FireServer(player.UserId)
	return waitFor(function()
		return runStarted
	end, 5)
end

local function runResult(timeout: number): { any }?
	waitFor(function()
		return lastResult ~= nil
	end, timeout)
	return lastResult
end

local function invoke(name: string, ...: any): (boolean, any, any)
	local args = table.pack(...)
	local ok, a, b = pcall(function()
		return Remotes.func(name):InvokeServer(table.unpack(args, 1, args.n))
	end)
	return ok, a, b
end

---------------------------------------------------------------- the run

local originalSlot = 1
step("profile loaded", function()
	local ok = waitFor(function()
		return tower ~= nil
	end, 45) -- a stale session lock can delay the load
	if progress then
		originalSlot = progress.activeSlot or 1
	end
	return ok,
		string.format(
			"pieces=%d level=%s slot=%s",
			count(),
			tostring(progress and progress.level),
			tostring(originalSlot)
		)
end)

local onSlot3 = false
step("switch to slot 3", function()
	if originalSlot == 3 then
		return false, "already on slot 3; QA refuses to touch it"
	end
	local _, switched = invoke("SwitchSlot", 3)
	onSlot3 = switched == true
		and waitFor(function()
			return progress ~= nil and progress.activeSlot == 3
		end, 5)
	return onSlot3, "pieces in slot 3: " .. count()
end)
-- Never edit a real tower: without slot 3 the run stops here.
if not onSlot3 then
	ReplicatedStorage:WaitForChild("QAReport"):FireServer({
		passed = 0,
		total = #results,
		steps = results,
		clientLog = clientLog,
		aborted = "could not switch to slot 3",
	})
	return
end
clearTower()

step("place a block", function()
	return place(1, 2, 0, 2), count()
end)
step("reject bad input (NaN, out of bounds, fractions, unknown type)", function()
	local before = count()
	Remotes.event("PlacePiece"):FireServer(1, 0 / 0, 0, 0, 0)
	Remotes.event("PlacePiece"):FireServer(1, 99, 0, 0, 0)
	Remotes.event("PlacePiece"):FireServer(1, 1.5, 0, 0, 0)
	Remotes.event("PlacePiece"):FireServer(200, 3, 0, 3, 0)
	task.wait(1.5)
	return count() == before, "count " .. before .. " -> " .. count()
end)
step("reject overlap", function()
	local before = count()
	Remotes.event("PlacePiece"):FireServer(1, 2, 0, 2, 0)
	task.wait(1)
	return count() == before
end)
step("delete a piece", function()
	local before = count()
	Remotes.event("RemovePiece"):FireServer(2, 0, 2)
	return waitFor(function()
		return count() == before - 1
	end, 3)
end)
step("undo reverts a place and a delete", function()
	local before = count()
	place(1, 6, 0, 2)
	Remotes.event("Undo"):FireServer()
	local undidPlace = waitFor(function()
		return count() == before
	end, 3)
	place(1, 6, 0, 2)
	task.wait(0.2)
	Remotes.event("RemovePiece"):FireServer(6, 0, 2)
	waitFor(function()
		return count() == before
	end, 3)
	Remotes.event("Undo"):FireServer()
	local undidRemove = waitFor(function()
		return count() == before + 1
	end, 3)
	Remotes.event("RemovePiece"):FireServer(6, 0, 2)
	waitFor(function()
		return count() == before
	end, 3)
	return undidPlace and undidRemove,
		string.format("place undone=%s remove undone=%s", tostring(undidPlace), tostring(undidRemove))
end)

step("parts rendered on the plot", function()
	place(2, 0, 0, 8)
	task.wait(0.5)
	local plot = workspace.Plots:FindFirstChild("Plot_" .. player.UserId)
	local pieces = plot and plot:FindFirstChild("Pieces")
	local n = if pieces then #pieces:GetChildren() else 0
	return n == count(), string.format("%d parts for %d pieces", n, count())
end)

-- A finish right in front of the spawn, and a test run that walks onto it.
step("test run verifies the tower", function()
	place(8, 8, 0, 6) -- Finish, far enough for a run over the 1 s minimum
	if not startRun() then
		return false, "RunStarted never arrived"
	end
	walkTo(cellCenter(8, 0, 6), 15, 1.5)
	local r = runResult(10)
	return r ~= nil and r[1] == true and waitFor(function()
		return verified
	end, 3),
		if r
			then string.format("ok=%s ms=%s msg=%s", tostring(r[1]), tostring(r[2]), tostring(r[4]))
			else "no result"
end)
step("any edit clears verification", function()
	place(1, 0, 0, 0)
	return waitFor(function()
		return not verified
	end, 3)
end)

step("jump pad launches without failing the run", function()
	place(4, 3, 0, 4, 0, { power = 3 }) -- off the straight line to the finish
	if not startRun() then
		return false, "no run"
	end
	local _, _, root = character()
	local peak = 0
	local conn = game:GetService("RunService").Heartbeat:Connect(function()
		peak = math.max(peak, root.AssemblyLinearVelocity.Y)
	end)
	walkTo(cellCenter(3, 0, 4), 10, 1)
	task.wait(3)
	conn:Disconnect()
	local failed = lastResult and lastResult[1] == false and tostring(lastResult[4] or "")
	walkTo(cellCenter(8, 0, 6), 15, 1.5)
	local r = runResult(10)
	return peak > 80 and r ~= nil and r[1] == true,
		string.format(
			"peak vy=%.0f, mid-run failure=%s, result=%s",
			peak,
			tostring(failed),
			tostring(r and r[1])
		)
end)

step("teleporter pair moves you and keeps the run valid", function()
	place(5, 12, 0, 1, 0, { ch = 2 })
	place(5, 12, 0, 12, 0, { ch = 2 })
	if not startRun() then
		return false, "no run"
	end
	walkTo(cellCenter(12, 0, 1), 12, 1)
	local _, _, root = character()
	local far = cellCenter(12, 0, 12)
	local arrived = waitFor(function()
		return (root.Position - far).Magnitude < 8
	end, 4)
	task.wait(1.5)
	local midFail = lastResult ~= nil
	Remotes.event("StopRun"):FireServer()
	task.wait(1)
	return arrived and not midFail,
		string.format("arrived=%s, run ended early=%s", tostring(arrived), tostring(midFail))
end)

step("checkpoint split, death respawns there, run continues", function()
	place(14, 4, 0, 1) -- checkpoint
	if not startRun() then
		return false, "no run"
	end
	splits = 0
	walkTo(cellCenter(4, 0, 1), 12, 1)
	local gotSplit = waitFor(function()
		return splits > 0
	end, 3)
	local _, humanoid = character()
	humanoid.Health = 0
	local newChar = player.CharacterAdded:Wait()
	local root = newChar:WaitForChild("HumanoidRootPart") :: BasePart
	task.wait(1)
	local nearCheckpoint = (root.Position - cellCenter(4, 0, 1)).Magnitude < 10
	local stillRunning = lastResult == nil
	walkTo(cellCenter(8, 0, 6), 15, 1.5)
	local r = runResult(10)
	return gotSplit and nearCheckpoint and stillRunning and r ~= nil and r[1] == true,
		string.format(
			"split=%s respawnNearCheckpoint=%s runSurvivedDeath=%s finished=%s",
			tostring(gotSplit),
			tostring(nearCheckpoint),
			tostring(stillRunning),
			tostring(r and r[1])
		)
end)

local function partAt(x: number, y: number, z: number): BasePart?
	local plot = workspace.Plots:FindFirstChild("Plot_" .. player.UserId)
	local pieces = plot and plot:FindFirstChild("Pieces")
	local target = cellCenter(x, y, z)
	local best, bestDist = nil, math.huge
	for _, part in if pieces then pieces:GetChildren() else {} do
		if part:IsA("BasePart") then
			local d = (part.Position - target).Magnitude
			if d < bestDist then
				best, bestDist = part, d
			end
		end
	end
	return if bestDist < 4 then best else nil
end

-- Stand on top of a cell (outside runs, so moving the character is fine).
local function standOn(x: number, y: number, z: number)
	local char = character()
	char:PivotTo(CFrame.new(cellCenter(x, y, z) + Vector3.new(0, G / 2 + 3, 0)))
end

step("fake wall: walk straight through it to the finish", function()
	place(6, 8, 0, 3) -- fake wall on the spawn -> finish line
	if not startRun() then
		return false, "no run"
	end
	walkTo(cellCenter(8, 0, 6), 15, 1.5)
	local r = runResult(10)
	return r ~= nil and r[1] == true, "result=" .. tostring(r and r[1])
end)

step("invisible platform is solid and invisible", function()
	place(7, 14, 0, 14)
	local part = partAt(14, 0, 14)
	return part ~= nil and part.Transparency == 1 and part.CanCollide, part and part.Name
end)

step("crumble falls after landing and comes back", function()
	place(9, 0, 0, 12)
	standOn(0, 0, 12)
	task.wait(1.5)
	local part = partAt(0, 0, 12)
	local fell = part ~= nil and part.CanCollide == false
	standOn(14, 0, 8) -- step off so it isn't touched again when it returns
	task.wait(3.5)
	local back = part ~= nil and part.CanCollide == true
	return fell and back, string.format("fell=%s back=%s", tostring(fell), tostring(back))
end)

step("conveyor carries a standing player", function()
	place(10, 12, 0, 4, 1) -- rotation 1
	-- Upstream end (the belt runs toward -X), measured from landing.
	standOn(13, 0, 4)
	local _, humanoid, root = character()
	waitFor(function()
		return humanoid.FloorMaterial ~= Enum.Material.Air
	end, 2)
	local start = root.Position
	task.wait(0.4)
	local moved = (root.Position - start) * Vector3.new(1, 0, 1)
	local belt = partAt(12, 0, 4)
	return moved.Magnitude > 3,
		string.format(
			"moved %.1f studs; belt=%s vel=%s dir=%s floor=%s anchored=%s pos=%s",
			moved.Magnitude,
			belt and belt.Name or "nil",
			belt and tostring(belt.AssemblyLinearVelocity) or "-",
			belt and tostring(belt:GetAttribute("Dir")) or "-",
			humanoid.FloorMaterial.Name,
			tostring(root.Anchored),
			tostring(root.Position - plotOrigin())
		)
end)

step("button opens doors on its channel, then they close", function()
	place(13, 4, 0, 14, 0, { ch = 3 }) -- door
	task.wait(0.2)
	place(12, 2, 0, 14, 0, { ch = 3 }) -- button
	local door = partAt(4, 0, 14) or partAt(4, 1, 14)
	standOn(2, 0, 14)
	task.wait(1)
	local opened = door ~= nil and door.CanCollide == false
	standOn(10, 0, 14) -- step away
	task.wait(6.5)
	local closed = door ~= nil and door.CanCollide == true
	return opened and closed, string.format("opened=%s closed=%s", tostring(opened), tostring(closed))
end)

step("one-way wall: passable from behind, solid from the front", function()
	place(11, 6, 0, 10, 0) -- rotation 0: pass direction is -Z
	local wall = partAt(6, 0, 10) or partAt(6, 1, 10)
	if not wall then
		return false, "no part"
	end
	standOn(6, 0, 12) -- behind (entry side)
	task.wait(0.5)
	local passable = wall.CanCollide == false
	standOn(6, 0, 7) -- in front (exit side)
	task.wait(0.5)
	local solid = wall.CanCollide == true
	return passable and solid,
		string.format("behind passable=%s front solid=%s", tostring(passable), tostring(solid))
end)

step("decorations don't count toward the budget", function()
	local before = progress and progress.budget
	local ok = place(15, 15, 0, 0) -- plant
	local plant = partAt(15, 0, 0)
	return ok and plant ~= nil and plant.CanCollide == false, "budget " .. tostring(before)
end)

step("progress carries the tutorial flag", function()
	return progress ~= nil and type(progress.tutorialDone) == "boolean",
		tostring(progress and progress.tutorialDone)
end)

step("browse tabs and search answer", function()
	local details = {}
	local all = true
	for _, tab in { "featured", "contest", "new", "popular", "hard", "friends" } do
		local ok, list = invoke("Browse", tab)
		all = all and ok and type(list) == "table"
		table.insert(details, tab .. "=" .. (if ok and type(list) == "table" then #list else "ERR"))
		task.wait(0.3)
	end
	return all, table.concat(details, " ")
end)
step("leaderboard (all time + monthly) and replay lookups answer", function()
	local ok1, list1 = invoke("Leaderboard", player.UserId, false)
	task.wait(0.3)
	local ok2, list2 = invoke("Leaderboard", player.UserId, true)
	local ok3 = invoke("GetReplay", player.UserId, 0)
	return ok1 and ok2 and ok3 and type(list1) == "table" and type(list2) == "table"
end)
step("contest info answers", function()
	local ok, info = invoke("ContestInfo")
	return ok, if type(info) == "table" then tostring(info.phase) else "no contest now"
end)
step("material: plastic ok, marble needs Bricks", function()
	local _, okPlastic = invoke("SetMaterial", "plastic")
	task.wait(0.3)
	local _, okMarble, err = invoke("BuyMaterial", "marble")
	local bricks = progress and progress.bricks or 0
	return okPlastic == true and (okMarble == (bricks >= 300)),
		string.format("bricks=%d marble=%s (%s)", bricks, tostring(okMarble), tostring(err))
end)
step("trail purchase refused without Bricks", function()
	local bricks = progress and progress.bricks or 0
	local _, ok, err = invoke("BuyTrail", "trail_spark")
	return ok == (bricks >= 200), tostring(err)
end)
step("cannot like or report your own tower", function()
	local _, liked = invoke("LikeTower", player.UserId)
	local _, reported = invoke("ReportTower", player.UserId)
	return liked == false and reported == false
end)

-- Leave slot 3 empty and go back.
step("clean up and switch back", function()
	clearTower()
	task.wait(0.5)
	if count() ~= 0 then
		return false, "slot 3 not empty; staying on it so nothing else is touched"
	end
	local _, switched = invoke("SwitchSlot", originalSlot)
	return switched == true and count() >= 0,
		"back on slot " .. originalSlot .. " with " .. count() .. " pieces"
end)

local passed = 0
for _, r in results do
	if r.ok then
		passed += 1
	end
end
ReplicatedStorage:WaitForChild("QAReport"):FireServer({
	passed = passed,
	total = #results,
	steps = results,
	clientLog = clientLog,
})
