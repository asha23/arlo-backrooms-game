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

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
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
local SETTLE_FRAMES = 45

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

waitFor("loading assets", 30, function()
	return game:IsLoaded()
end)

waitFor("building level", 30, function()
	local level = workspace:FindFirstChild("Level")
	-- The floor is the first thing the generator emits; if it's there with a
	-- decent number of walls alongside it, geometry has arrived.
	return level ~= nil and level:FindFirstChild("Floor") ~= nil and #level:GetChildren() > 50
end)

waitFor("lighting corridors", 15, function()
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

local fade = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(cover, fade, { BackgroundTransparency = 1 }):Play()
TweenService:Create(title, fade, { TextTransparency = 1 }):Play()
TweenService:Create(status, fade, { TextTransparency = 1 }):Play()
TweenService:Create(detail, fade, { TextTransparency = 1 }):Play()

task.delay(1.3, function()
	gui:Destroy()
end)
