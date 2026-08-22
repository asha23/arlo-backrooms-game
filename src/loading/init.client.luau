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
title.Size = UDim2.new(1, 0, 0, 44)
title.Position = UDim2.new(0, 0, 0.42, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 30
title.TextColor3 = Color3.fromRGB(232, 126, 34)
title.Text = "LEVEL 0"
title.Parent = cover

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, 0, 0, 22)
status.Position = UDim2.new(0, 0, 0.42, 48)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Code
status.TextSize = 14
status.TextColor3 = Color3.fromRGB(150, 144, 130)
status.Text = "connecting..."
status.Parent = cover

local function report(text: string)
	status.Text = text
end

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

waitFor("loading assets...", 30, function()
	return game:IsLoaded()
end)

waitFor("building level...", 30, function()
	local level = workspace:FindFirstChild("Level")
	-- The floor is the first thing the generator emits; if it's there with a
	-- decent number of walls alongside it, geometry has arrived.
	return level ~= nil and level:FindFirstChild("Floor") ~= nil and #level:GetChildren() > 50
end)

waitFor("waiting for lighting...", 15, function()
	-- Spawn lighting is what guarantees you can see on arrival.
	local level = workspace:FindFirstChild("Level")
	return level ~= nil and level:FindFirstChild("SpawnLight") ~= nil
end)

waitFor("entering...", 30, function()
	local character = player.Character
	return character ~= nil
		and character:FindFirstChild("HumanoidRootPart") ~= nil
		and character:FindFirstChildOfClass("Humanoid") ~= nil
end)

-- A beat on a lit frame before the fade, so the reveal isn't mid-stream.
report("")
task.wait(0.6)

local fade = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(cover, fade, { BackgroundTransparency = 1 }):Play()
TweenService:Create(title, fade, { TextTransparency = 1 }):Play()
TweenService:Create(status, fade, { TextTransparency = 1 }):Play()

task.delay(1.3, function()
	gui:Destroy()
end)
