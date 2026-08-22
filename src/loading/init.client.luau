--!strict
--[[
	Loading screen.

	Lives in ReplicatedFirst so it runs before anything else replicates. Without
	it the first thing a player sees is the inside of an unlit maze that hasn't
	finished streaming in — indistinguishable from a black screen, and it reads
	as the game being broken rather than as loading.

	It covers the screen until the level geometry, the character and the
	lighting are all genuinely present, then fades out.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

--[[
	Constants are inlined rather than read from Config: this runs in
	ReplicatedFirst before ReplicatedStorage is guaranteed to have replicated,
	and a bootstrap screen that can't start because it's waiting on a config
	module is worse than one with a couple of hardcoded numbers.
]]
-- Hold the screen at least this long even if everything is instantly ready.
-- Studio Play Solo satisfies every readiness check immediately, so without a
-- floor the screen flashes past and you arrive before the level has drawn.
local MINIMUM_SECONDS = 4
-- Rendered frames to let pass after everything is ready, so the first thing
-- revealed is a fully drawn, fully lit room rather than a half-streamed one.
local SETTLE_FRAMES = 60

local startedAt = os.clock()
local player = Players.LocalPlayer

-- Replace Roblox's own loading screen rather than sitting behind it.
ReplicatedFirst:RemoveDefaultLoadingScreen()

local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = playerGui

local cover = Instance.new("Frame")
cover.Name = "Cover"
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = Color3.fromRGB(12, 10, 8)
cover.BorderSizePixel = 0
cover.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 0, 96)
title.Position = UDim2.new(0, 40, 0.36, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 34
title.TextWrapped = true
title.TextColor3 = Color3.fromRGB(232, 126, 34)
title.Text = "GET READY TO EXPERIENCE THE BACKROOMS."
title.Parent = cover

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -80, 0, 26)
status.Position = UDim2.new(0, 40, 0.36, 104)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Code
status.TextSize = 16
status.TextColor3 = Color3.fromRGB(168, 160, 142)
status.Text = "PLEASE WAIT, JUST LOADING"
status.Parent = cover

-- The step being waited on, under the fixed "PLEASE WAIT" line, so the copy
-- stays put while the detail underneath changes.
local detail = Instance.new("TextLabel")
detail.Size = UDim2.new(1, -80, 0, 20)
detail.Position = UDim2.new(0, 40, 0.36, 134)
detail.BackgroundTransparency = 1
detail.Font = Enum.Font.Code
detail.TextSize = 13
detail.TextColor3 = Color3.fromRGB(110, 105, 94)
detail.Text = ""
detail.Parent = cover

local currentLabel = ""

--[[
	All-time top five, shown while the level finishes loading.

	The loading screen is the only moment a player is guaranteed to be standing
	still with nothing to do, which makes it the right place for a scoreboard —
	and it gives the wait a reason to exist beyond hiding a dark room.

	Requested rather than pushed: the server may not have read the board yet
	when this script starts, and an empty board is a perfectly normal answer.
]]
local function showLeaderboard(parent: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "HighScores"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0.60, 0)
	holder.Size = UDim2.fromOffset(360, 170)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, 0, 0, 20)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBold
	heading.TextSize = 14
	heading.TextColor3 = Color3.fromRGB(232, 126, 34)
	heading.Text = "ALL-TIME HIGH SCORES"
	heading.Parent = holder

	local rows = {}
	for index = 1, 5 do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 22)
		row.Position = UDim2.new(0, 0, 0, 8 + index * 24)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Code
		row.TextSize = 14
		row.TextColor3 = Color3.fromRGB(178, 170, 152)
		row.Text = ""
		row.Parent = holder
		rows[index] = row
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("Shared", 20)
	local module = remotesFolder and (remotesFolder :: Instance):FindFirstChild("Remotes")
	if not module then
		return
	end
	local Remotes = require(module) :: any

	Remotes.Leaderboard().OnClientEvent:Connect(function(board, ok)
		if not ok or #board == 0 then
			rows[1].Text = "no scores recorded yet"
			return
		end
		for index = 1, 5 do
			local entry = board[index]
			rows[index].Text = if entry
				then string.format("%d. %-18s %8d", index, entry.name, entry.score)
				else ""
		end
	end)

	Remotes.RequestLeaderboard():FireServer()
end

local function report(text: string)
	currentLabel = text
	detail.Text = text
end

-- Pulse the label so a long wait doesn't look like a hang.
task.spawn(function()
	while gui.Parent do
		for alpha = 0, 1, 0.05 do
			if currentLabel == "" then
				status.TextTransparency = 0
				break
			end
			status.TextTransparency = 0.15 + 0.35 * math.abs(math.sin(alpha * math.pi))
			RunService.Heartbeat:Wait()
		end
		RunService.Heartbeat:Wait()
	end
end)

--- Waits until `predicate` is true or the budget runs out. Returns whether it
--- succeeded, so a stall can be reported rather than hanging the screen forever.
local function waitFor(label: string, budget: number, predicate: () -> boolean): boolean
	report(label)
	local deadline = os.clock() + budget
	while not predicate() do
		if os.clock() > deadline then
			warn(`[Loading] timed out waiting for: {label}`)
			return false
		end
		RunService.Heartbeat:Wait()
	end
	return true
end

showLeaderboard(cover)

waitFor("loading assets", 30, function()
	return game:IsLoaded()
end)

waitFor("building level", 30, function()
	--[[
		The floor is the first thing the generator emits, and the walls follow
		it. Waiting for a healthy child count means the fade reveals a built
		level rather than a floor in a void.
	]]
	local level = workspace:FindFirstChild("Level")
	return level ~= nil and level:FindFirstChild("Floor") ~= nil and #level:GetChildren() > 100
end)

waitFor("placing fixtures", 15, function()
	-- Spawn lighting is what guarantees you can see on arrival.
	local level = workspace:FindFirstChild("Level")
	return level ~= nil and level:FindFirstChild("SpawnLight") ~= nil
end)

waitFor("finding a way in", 30, function()
	local character = player.Character
	return character ~= nil
		and character:FindFirstChild("HumanoidRootPart") ~= nil
		and character:FindFirstChildOfClass("Humanoid") ~= nil
end)

--[[
	Wait until the corridor around the player is genuinely lit.

	Every check above confirms that instances EXIST. None of them confirm that
	anything is switched on — and until LightStreaming has run its first pass,
	every fixture in the level is Enabled by default, which overruns the
	renderer's light budget and makes the level render dark. Revealing the game
	at that moment is exactly the "starts in the dark" problem.

	So: wait for the streaming pass to publish its flag, and then verify
	directly that there are lit fixtures near the player rather than trusting
	the flag alone.
]]
waitFor("switching on", 20, function()
	return player:GetAttribute("LightsReady") == true
end)

waitFor("lighting the corridor", 20, function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local lit = 0
	for _, fixture in CollectionService:GetTagged("Fluorescent") do
		if not fixture:IsA("BasePart") then
			continue
		end
		local light = fixture:FindFirstChildOfClass("PointLight")
		if light and light.Enabled and (fixture.Position - root.Position).Magnitude <= 70 then
			lit += 1
			if lit >= 3 then
				return true
			end
		end
	end
	return false
end)

--[[
	Everything reports ready — but "ready" means the instances exist, not that
	they have been drawn. Let real frames go by, then hold until the minimum
	duration is up, so the fade always reveals a finished scene.
]]
report("rendering")
for _ = 1, SETTLE_FRAMES do
	RunService.RenderStepped:Wait()
end

local elapsed = os.clock() - startedAt
if elapsed < MINIMUM_SECONDS then
	task.wait(MINIMUM_SECONDS - elapsed)
end

report("")

--[[
	Tell the server we can see the level. Nothing spawns and nobody moves until
	this arrives, so it must be sent even if some readiness check above timed
	out — a client stuck behind its own loading screen forever is worse than one
	that starts a moment early.

	ReplicatedStorage is definitely replicated by now; this script runs from
	ReplicatedFirst, which is why the remote is fetched here rather than at the
	top of the file.
]]
local remotes = ReplicatedStorage:WaitForChild("Shared", 20)
if remotes then
	local module = (remotes :: Instance):FindFirstChild("Remotes")
	if module then
		local Remotes = require(module) :: any
		Remotes.PlayerReady():FireServer()
	end
end

local fade = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(cover, fade, { BackgroundTransparency = 1 }):Play()
TweenService:Create(title, fade, { TextTransparency = 1 }):Play()
TweenService:Create(status, fade, { TextTransparency = 1 }):Play()
TweenService:Create(detail, fade, { TextTransparency = 1 }):Play()
for _, descendant in cover:GetDescendants() do
	if descendant:IsA("TextLabel") then
		TweenService:Create(descendant, fade, { TextTransparency = 1 }):Play()
	end
end

task.delay(1.3, function()
	gui:Destroy()
end)
