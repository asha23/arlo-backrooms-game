--!strict
--[[
	Randomly stutters the ceiling fluorescents. Purely cosmetic and client-side,
	so every player sees a slightly different room — which is unsettling in a way
	a synchronised flicker isn't.

	A stuttering fixture DIMS rather than switching off. Somewhere you genuinely
	cannot see reads as a broken game rather than as atmosphere, so nowhere in
	the level ever goes fully black.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LightFlicker = {}

local ON_COLOR = Color3.fromRGB(255, 250, 220)
local DIM_COLOR = Color3.fromRGB(96, 92, 76)
local DIM_BRIGHTNESS = Config.Level.FlickerDimBrightness

local function driveFixture(fixture: Instance)
	if not fixture:IsA("BasePart") then
		return
	end
	-- Spawn lighting is tagged Stable and must never cut out.
	if fixture:HasTag("Stable") then
		return
	end
	local light = fixture:FindFirstChildOfClass("PointLight")
	if not light then
		return
	end

	local fullBrightness = light.Brightness

	task.spawn(function()
		while fixture.Parent do
			-- Long stable stretch, then a short burst of stutter.
			task.wait(math.random(6, 25) + math.random())
			local dim = false
			for _ = 1, math.random(2, 8) do
				dim = not dim
				light.Brightness = if dim then DIM_BRIGHTNESS else fullBrightness
				fixture.Color = if dim then DIM_COLOR else ON_COLOR
				task.wait(math.random(4, 16) / 100)
			end
			light.Brightness = fullBrightness
			fixture.Color = ON_COLOR
		end
	end)
end

function LightFlicker.start()
	for _, fixture in CollectionService:GetTagged("Fluorescent") do
		driveFixture(fixture)
	end
	CollectionService:GetInstanceAddedSignal("Fluorescent"):Connect(driveFixture)
end

return LightFlicker
