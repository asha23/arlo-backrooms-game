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

		-- Surfaces. SmoothPlastic keeps the walls flat and untextured; swap to
		-- Fabric/Concrete if you ever want the grimier look back.
		WallColor = Color3.fromRGB(232, 126, 34),
		WallMaterial = Enum.Material.SmoothPlastic,
		FloorColor = Color3.fromRGB(186, 100, 26),
		FloorMaterial = Enum.Material.SmoothPlastic,
		CeilingColor = Color3.fromRGB(240, 233, 214),
		CeilingMaterial = Enum.Material.SmoothPlastic,
	},

	Player = {
		WalkSpeed = 20,
		SprintSpeed = 34,
		MaxStamina = 100,
		StaminaDrain = 14, -- per second while sprinting
		StaminaRegen = 12, -- per second while not sprinting
		SprintMinStamina = 10, -- can't start a sprint below this
	},

	Sanity = {
		Max = 100,
		DrainInDark = 3.5, -- per second with no nearby light
		RegenInLight = 6, -- per second while lit
		LightRadius = 26, -- studs; how close a light must be to count as "lit"
	},

	Fog = {
		Start = 90,
		End = 340,
	},

	Entity = {
		MaxAlive = 8,
		SpawnInterval = 6, -- seconds between spawn attempts
		-- Never spawn one closer than this to a player, so they don't just
		-- appear in your face.
		MinSpawnDistance = 70,
		MaxSpawnDistance = 260,
		Health = 120,
		WalkSpeed = 13,
		ChaseSpeed = 19,
		SightRange = 90,
		AttackRange = 6,
		AttackDamage = 18,
		AttackCooldown = 1.2,
		-- How long it keeps chasing your last known position after losing you.
		SearchTime = 6,
		RespawnDelay = 4,
	},

	Weapons = {
		-- Weapon pickups scattered through the maze at generation time.
		SpawnCount = 26,
		RespawnDelay = 25,
		PickupRadius = 7,
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
