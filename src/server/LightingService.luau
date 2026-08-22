--!strict
--[[
	Applies the level's lighting from Config at runtime.

	Ambient lives here rather than in default.project.json so that
	Config.Level.LightScale can reach it. Three separate things determine how
	bright this level looks — ambient, the fixture PointLights, and the emissive
	colour of the Neon panels — and every previous attempt to dim it adjusted
	one of the three in isolation. One dial has to reach all of them or the
	tuning never converges.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LEVEL = Config.Level

local LightingService = {}

--- Multiplies a colour's channels, clamped. Used to scale emissive panels and
--- ambient together from the single LightScale dial.
function LightingService.scaleColor(color: Color3, scale: number): Color3
	return Color3.new(
		math.clamp(color.R * scale, 0, 1),
		math.clamp(color.G * scale, 0, 1),
		math.clamp(color.B * scale, 0, 1)
	)
end

function LightingService.start()
	local ambient = LightingService.scaleColor(LEVEL.BaseAmbient, LEVEL.LightScale)
	Lighting.Ambient = ambient
	Lighting.OutdoorAmbient = ambient

	print(
		`[Lighting] scale {LEVEL.LightScale}, ambient {math.floor(ambient.R * 255)},`
			.. `{math.floor(ambient.G * 255)},{math.floor(ambient.B * 255)}`
	)
end

return LightingService
