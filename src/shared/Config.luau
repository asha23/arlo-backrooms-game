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
		-- The spawn room is deliberately over-lit: arriving in pitch darkness
		-- with no bearings reads as a bug rather than as atmosphere.
		SpawnLightRadius = 3, -- cells around spawn that get guaranteed lighting
		SpawnLightBrightness = 5,
		SpawnLightRange = 70,
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

	Ambience = {
		--[[
			Roblox's built-in `rbxasset://` library has sound effects but no
			music, so by default we synthesise a drone bed instead: several
			copies of the same low tone at different pitches, with volumes
			drifting slowly against each other. It's tonal and unsettling and
			needs no uploads.

			Set MusicId to an `rbxassetid://` of your own track to use that
			instead — the drone bed is switched off automatically.
		]]
		MusicId = "",
		MusicVolume = 0.5,

		DroneId = "rbxasset://sounds/bass.mp3",
		-- Pitch and base volume for each layer of the bed.
		DroneLayers = {
			{ Pitch = 0.18, Volume = 0.34 },
			{ Pitch = 0.27, Volume = 0.24 },
			{ Pitch = 0.41, Volume = 0.15 },
		},
		-- Seconds for a layer's volume to complete one slow swell.
		DronePeriods = { 23, 37, 53 },

		-- Occasional distant noises, so the level isn't only a flat drone.
		StingerIds = {
			"rbxasset://sounds/snap.mp3",
			"rbxasset://sounds/metal.ogg",
			"rbxasset://sounds/electronicpingshort.wav",
		},
		StingerGap = { 18, 48 },
		StingerVolume = 0.3,
		StingerPitch = { 0.3, 0.65 },
	},

	Camera = {
		-- First person locks the mouse to the centre of the screen and aims
		-- where you look, which is what makes a shooter feel like a shooter.
		-- Set false to fall back to Roblox's third-person orbit camera.
		FirstPerson = true,
		-- Multiplier on raw mouse/trackpad movement. Trackpads generally want
		-- a higher value than a mouse.
		Sensitivity = 1,
		-- Touch look sensitivity, in degrees of turn per pixel dragged.
		TouchSensitivity = 0.28,
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

		--[[
			Variants.

			The silhouette is what frightens at the far end of a corridor, long
			before any detail resolves — so the variants differ mainly in
			proportion. All sizes are in studs; the ceiling is 14, so the tallest
			of these clears the lights by a hand's width.

			Weight is relative spawn frequency, not a percentage.
		]]
		Variants = {
			{
				Id = "Wanderer",
				Weight = 3,
				Health = 120,
				WalkSpeed = 13,
				ChaseSpeed = 19,
				Tendrils = 0,
				Build = {
					TorsoSize = Vector3.new(1.9, 3.4, 0.75),
					HeadSize = Vector3.new(1.05, 1.5, 1.05),
					ArmSize = Vector3.new(0.42, 4.6, 0.42),
					LegSize = Vector3.new(0.55, 4.7, 0.55),
					HeadColor = Color3.fromRGB(226, 222, 210),
					BodyColor = Color3.fromRGB(18, 17, 20),
					LimbColor = Color3.fromRGB(24, 23, 26),
					HeadReflectance = 0.04,
				},
			},
			{
				-- Slender: rarer, taller, slower to start and faster once it has
				-- you. Black suit, a featureless white head, and tendrils that
				-- only unfurl properly when it moves.
				Id = "Slender",
				Weight = 1,
				Health = 240,
				WalkSpeed = 10,
				ChaseSpeed = 21,
				Tendrils = 4,
				Build = {
					TorsoSize = Vector3.new(1.7, 4.2, 0.6),
					HeadSize = Vector3.new(1.0, 1.35, 1.0),
					ArmSize = Vector3.new(0.34, 6.2, 0.34),
					LegSize = Vector3.new(0.46, 5.6, 0.46),
					-- Bright white, and slightly glossy so it catches the flashlight
					-- from across a room.
					HeadColor = Color3.fromRGB(248, 248, 246),
					BodyColor = Color3.fromRGB(8, 8, 10),
					LimbColor = Color3.fromRGB(10, 10, 12),
					HeadReflectance = 0.18,
				},
				TendrilSize = Vector3.new(0.22, 7.5, 0.22),
				TendrilColor = Color3.fromRGB(6, 6, 8),
			},
		},

		-- Slow idle sway, so they never look like a static prop. It never stops,
		-- even while one is standing still watching you.
		SwayAngle = 5, -- degrees
		SwayPeriod = 4.5, -- seconds per cycle

		SightRange = 90,
		AttackRange = 6,
		AttackDamage = 18,
		AttackCooldown = 1.2,
		-- How long it keeps chasing your last known position after losing you.
		SearchTime = 6,
		RespawnDelay = 4,

		--[[
			Sounds use `rbxasset://` paths, which are the audio files that ship
			with the Roblox client itself. That means they work immediately with
			no uploads and no moderation wait — but they're stock sounds doing a
			job they weren't written for. Pitch is dragged well down to make them
			sit right. Replace the ids with `rbxassetid://<your upload>` when you
			have proper audio.
		]]
		Sounds = {
			-- Constant low drone that gives the thing away before you see it.
			Drone = {
				Id = "rbxasset://sounds/bass.mp3",
				Pitch = 0.28,
				Volume = 0.55,
				Range = 70,
			},
			-- Occasional vocalisation while it wanders.
			Idle = {
				Id = "rbxasset://sounds/uuhhh.mp3",
				Pitch = 0.42,
				Volume = 0.7,
				Range = 85,
			},
			-- Fires once, the moment it spots you.
			Alert = {
				Id = "rbxasset://sounds/halt.wav",
				Pitch = 0.5,
				Volume = 1,
				Range = 120,
			},
			-- Rhythmic scrape while chasing.
			Chase = {
				Id = "rbxasset://sounds/swoosh.mp3",
				Pitch = 0.55,
				Volume = 0.8,
				Range = 95,
			},
		},

		--[[
			The death scream.

			One sample can't scream. This stacks several copies of the same cry
			at different pitches and starts them a beat apart, then slides every
			one of them downwards while it plays — so it starts as a shriek,
			detunes against itself into something that isn't a voice any more,
			and drops away. The layers are deliberately not harmonically
			related; the beating between them is what makes it unpleasant.
		]]
		DeathScream = {
			Id = "rbxasset://sounds/uuhhh.mp3",
			Range = 220,
			-- StartPitch -> EndPitch over SlideTime, per layer.
			Layers = {
				{ StartPitch = 1.35, EndPitch = 0.22, Volume = 1, Delay = 0 },
				{ StartPitch = 0.94, EndPitch = 0.16, Volume = 0.9, Delay = 0.06 },
				{ StartPitch = 0.61, EndPitch = 0.11, Volume = 0.85, Delay = 0.13 },
				{ StartPitch = 1.72, EndPitch = 0.4, Volume = 0.55, Delay = 0.21 },
			},
			SlideTime = 2.4,
		},
		-- Seconds between idle vocalisations, randomised in this range.
		IdleSoundGap = { 7, 19 },
		ChaseSoundGap = { 1.6, 3.2 },
	},

	Health = {
		-- Medkits scattered through the maze. Rolling over one restores you to
		-- full, so they're deliberately sparser than weapons.
		SpawnCount = 14,
		RespawnDelay = 40,
		PickupRadius = 6,
	},

	Weapons = {
		-- Weapon pickups scattered through the maze at generation time.
		SpawnCount = 26,
		RespawnDelay = 25,
		PickupRadius = 7,
	},

	PickupAudio = {
		-- A magazine seating home when you collect a weapon.
		Weapon = {
			Id = "rbxasset://sounds/switch3.wav",
			Pitch = 0.75,
			Volume = 1,
			Range = 45,
		},
		-- Second click a beat later, so it reads as a magazine rather than a
		-- light switch.
		WeaponSecondClick = {
			Id = "rbxasset://sounds/switch3.wav",
			Pitch = 1.1,
			Volume = 0.8,
			Range = 45,
			Delay = 0.11,
		},
		-- Bright ascending sparkle for health.
		Health = {
			Id = "rbxasset://sounds/electronicpingshort.wav",
			Pitch = 1.5,
			Volume = 0.9,
			Range = 45,
		},
		HealthSparkles = {
			-- Extra pings layered above, each delayed slightly, to sparkle.
			{ Pitch = 2.1, Volume = 0.6, Delay = 0.07 },
			{ Pitch = 2.8, Volume = 0.45, Delay = 0.14 },
			{ Pitch = 3.4, Volume = 0.3, Delay = 0.2 },
		},
	},

	WeaponAudio = {
		-- Dry fire: a bare mechanical click so an empty magazine is instantly
		-- distinguishable from the game simply not registering the input.
		DryFireId = "rbxasset://sounds/switch3.wav",
		DryFirePitch = 1.6,
		DryFireVolume = 0.55,
		-- Minimum gap between clicks, so holding the trigger on an empty gun
		-- makes one click rather than a machine-gun of them.
		DryFireCooldown = 0.35,
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
