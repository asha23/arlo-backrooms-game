--!strict
--[[
	Randomly stutters the ceiling fluorescents.

	Driven by a single loop that picks a nearby fixture every so often, rather
	than one coroutine per fixture. The old shape spawned a thread for every
	one of roughly 280 fixtures, each sleeping and waking forever — a lot of
	scheduler traffic to produce an effect the player can only ever see a few
	of at a time. Flickering only what's near the camera costs a fraction as
	much and puts the effect where it's actually noticed.

	A stuttering fixture DIMS rather than switching off. Somewhere you genuinely
	cannot see reads as a broken game rather than as atmosphere, so nowhere in
	the level ever goes fully black.

	Only `Brightness` is touched here. LightStreaming owns `Enabled`, so the two
	never fight over the same property.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LEVEL = Config.Level

-- These are the Neon panel colours, not light brightness. See the note on
-- Config.Level.FixtureColor: a Neon part's apparent brightness IS its colour.
local ON_COLOR = LEVEL.FixtureColor
local DIM_COLOR = LEVEL.FixtureDimColor

-- How often a new flicker starts, and how far away a fixture may be to qualify.
local ATTEMPT_INTERVAL = 0.8
local NEARBY_RADIUS = 90

local LightFlicker = {}

local rng = Random.new()

--- Stutters one fixture, then restores it.
local function flicker(part: BasePart, light: PointLight)
	local full = light.Brightness
	local dim = false

	for _ = 1, rng:NextInteger(2, 8) do
		if not part.Parent then
			return
		end
		dim = not dim
		light.Brightness = if dim then LEVEL.FlickerDimBrightness else full
		part.Color = if dim then DIM_COLOR else ON_COLOR
		task.wait(rng:NextNumber(0.04, 0.16))
	end

	if part.Parent then
		light.Brightness = full
		part.Color = ON_COLOR
	end
end

function LightFlicker.start()
	task.spawn(function()
		while true do
			task.wait(ATTEMPT_INTERVAL)

			local camera = workspace.CurrentCamera
			if not camera then
				continue
			end
			local origin = camera.CFrame.Position

			-- Candidates: tagged, nearby, currently lit, and not spawn lighting
			-- (which is tagged Stable precisely so it never cuts out).
			local candidates: { BasePart } = {}
			for _, tagged in CollectionService:GetTagged("Fluorescent") do
				if not tagged:IsA("BasePart") or tagged:HasTag("Stable") then
					continue
				end
				local light = tagged:FindFirstChildOfClass("PointLight")
				if not light or not light.Enabled then
					continue
				end
				if (tagged.Position - origin).Magnitude <= NEARBY_RADIUS then
					table.insert(candidates, tagged)
				end
			end

			if #candidates == 0 then
				continue
			end

			local part = candidates[rng:NextInteger(1, #candidates)]
			local light = part:FindFirstChildOfClass("PointLight")
			if light then
				task.spawn(flicker, part, light)
			end
		end
	end)
end

return LightFlicker
