--!strict
--[[
	Central tuning values. Everything a designer might want to tweak lives here
	so gameplay code stays free of magic numbers.
]]

local Config = {
	Level = {
		-- The maze is generated on an odd-sized grid where odd coordinates are
		-- carve-able cells and even coordinates are the walls between them.
		GridSize = 41, -- must be odd
		CellSize = 12, -- studs per grid cell
		WallHeight = 14,
		-- Chance to knock through an extra wall after carving. Higher = more
		-- loops and open halls, which is what makes it feel like the Backrooms
		-- rather than a puzzle maze.
		LoopChance = 0.16,
		-- Chance a carved cell becomes part of a wide open room.
		RoomChance = 0.05,
		RoomRadius = 2,
		LightSpacing = 4, -- place a ceiling light every N cells
		Seed = 0, -- 0 = random each server start
	},

	Player = {
		WalkSpeed = 12,
		SprintSpeed = 22,
		MaxStamina = 100,
		StaminaDrain = 18, -- per second while sprinting
		StaminaRegen = 10, -- per second while not sprinting
		SprintMinStamina = 10, -- can't start a sprint below this
	},

	Sanity = {
		Max = 100,
		DrainInDark = 3.5, -- per second with no nearby light
		RegenInLight = 6, -- per second while lit
		LightRadius = 26, -- studs; how close a light must be to count as "lit"
	},

	Flashlight = {
		Range = 60,
		Angle = 55,
		Brightness = 2,
		MaxBattery = 100,
		BatteryDrain = 1.2, -- per second while on
	},
}

return Config
