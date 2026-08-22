--!strict
--[[
	Randomly stutters the ceiling fluorescents. Purely cosmetic and client-side,
	so every player sees a slightly different room — which is unsettling in a way
	a synchronised flicker isn't.
]]

local CollectionService = game:GetService("CollectionService")

local LightFlicker = {}

local ON_COLOR = Color3.fromRGB(255, 250, 220)
local OFF_COLOR = Color3.fromRGB(70, 68, 58)

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

	task.spawn(function()
		while fixture.Parent do
			-- Long stable stretch, then a short burst of stutter.
			task.wait(math.random(6, 25) + math.random())
			for _ = 1, math.random(2, 8) do
				light.Enabled = not light.Enabled
				fixture.Color = if light.Enabled then ON_COLOR else OFF_COLOR
				task.wait(math.random(4, 16) / 100)
			end
			light.Enabled = true
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
