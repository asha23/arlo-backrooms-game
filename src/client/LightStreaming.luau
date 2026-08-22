--!strict
--[[
	Keeps only the nearest handful of ceiling lights switched on.

	Roblox's renderer has a fixed budget for local lights. The level builds
	roughly 280 fixtures, which is far beyond it — and when the budget is
	exceeded the engine doesn't dim gracefully, it drops lights. Which lights
	get dropped isn't something you control, so the fixture directly above the
	player is as likely to go as one on the far side of the map. That is what
	made the level read as pitch black despite obviously having lights in it.

	Culling to a small active set guarantees the budget is spent on the
	fixtures near the camera. It's also a large win on its own: a few dozen
	lights instead of hundreds.

	This only touches `Enabled`. LightFlicker drives `Brightness`, so the two
	can run side by side without fighting over the same property.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LEVEL = Config.Level

local LightStreaming = {}

type Fixture = {
	part: BasePart,
	light: PointLight,
}

local function gather(): { Fixture }
	local fixtures: { Fixture } = {}
	for _, tagged in CollectionService:GetTagged("Fluorescent") do
		if not tagged:IsA("BasePart") then
			continue
		end
		local light = tagged:FindFirstChildOfClass("PointLight")
		if light then
			table.insert(fixtures, { part = tagged, light = light })
		end
	end
	return fixtures
end

function LightStreaming.start()
	local radiusSquared = LEVEL.ActiveLightRadius ^ 2
	local budget = LEVEL.MaxActiveLights

	--[[
		The fixture list is rebuilt when tagged parts appear or disappear rather
		than on every pass. With StreamingEnabled the level's parts stream in
		and out as the player moves, so the set genuinely does change — but far
		less often than the four-times-a-second distance sort.
	]]
	local fixtures = gather()
	local dirty = false

	CollectionService:GetInstanceAddedSignal("Fluorescent"):Connect(function()
		dirty = true
	end)
	CollectionService:GetInstanceRemovedSignal("Fluorescent"):Connect(function()
		dirty = true
	end)

	--[[
		A single pass, factored out so the first one can run immediately rather
		than a quarter of a second after the player is already standing there.
		Before the first pass every fixture is Enabled by default, which is the
		state that overruns the renderer's light budget — so "before the first
		pass" is exactly when the level looks wrong.
	]]
	local candidates: { { fixture: Fixture, distance: number } } = {}

	local function pass()
		do
			if dirty then
				dirty = false
				fixtures = gather()
			end

			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local origin = camera.CFrame.Position

			table.clear(candidates)
			for _, fixture in fixtures do
				if not fixture.part.Parent then
					dirty = true
					continue
				end
				local distance = (fixture.part.Position - origin).Magnitude ^ 2
				if distance <= radiusSquared then
					table.insert(candidates, { fixture = fixture, distance = distance })
				else
					fixture.light.Enabled = false
				end
			end

			table.sort(candidates, function(a, b)
				return a.distance < b.distance
			end)

			for index, entry in candidates do
				entry.fixture.light.Enabled = index <= budget
			end
		end
	end

	--[[
		Run once up front, then publish a flag. The loading screen waits on this
		before it fades: revealing the level while every fixture is still in its
		default state is what made the game appear to start in the dark.
	]]
	pass()
	Players.LocalPlayer:SetAttribute("LightsReady", true)

	task.spawn(function()
		while true do
			task.wait(LEVEL.LightStreamInterval)
			pass()
		end
	end)
end

return LightStreaming
