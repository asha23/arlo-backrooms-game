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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

	task.spawn(function()
		-- Scratch table reused between passes so a 4Hz loop doesn't allocate.
		local candidates: { { fixture: Fixture, distance: number } } = {}

		while true do
			task.wait(LEVEL.LightStreamInterval)

			if dirty then
				dirty = false
				fixtures = gather()
			end

			local camera = workspace.CurrentCamera
			if not camera then
				continue
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
	end)

	-- Run one pass immediately so the first frame after the loading screen is
	-- already lit, rather than lighting up a quarter-second later.
	RunService.Heartbeat:Wait()
end

return LightStreaming
