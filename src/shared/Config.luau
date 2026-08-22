--!strict
--[[
	Central tuning values. Everything a designer might want to tweak lives here
	so gameplay code stays free of magic numbers.
]]

local Config = {
	Level = {
		-- The maze is generated on an odd-sized grid where odd coordinates are
		-- carve-able cells and even coordinates are the walls between them.
		GridSize = 49, -- must be odd
		CellSize = 9, -- studs per grid cell; tighter corridors
		-- Low enough to feel oppressive, high enough that the tallest entity
		-- still clears it. Check Config.Entity.Variants before lowering this.
		WallHeight = 12,
		--[[
			Chance to knock through an extra wall after carving.

			This is the main claustrophobia dial. High values open the maze into
			connected halls; low values leave it as narrow corridors and dead
			ends with walls close on both sides. Enough loops remain that it
			still reads as the Backrooms rather than as a puzzle maze.
		]]
		LoopChance = 0.05,
		-- Chance a carved cell becomes part of a wider room, and how wide.
		-- Kept rare and small: open space is a relief, and relief is not what
		-- this level is for.
		RoomChance = 0.012,
		RoomRadius = 1,
		LightSpacing = 3, -- place a ceiling light every N cells

		--[[
			Light streaming.

			Roblox's renderer has a hard budget for local lights, and a far
			smaller one for lights that cast shadows. The level creates roughly
			280 fixtures; with all of them live the engine silently drops most —
			including, routinely, the one directly above you, which is why the
			level could read as pitch black despite obviously having lights.

			The client keeps only the nearest few enabled. Everything past
			ActiveLightRadius is switched off, so the budget is always spent on
			the fixtures you can actually see.
		]]
		--[[
			Budget and reach for the active set.

			Sized against the numbers rather than guessed: fixtures sit roughly
			one per 690 square studs, so a 150-stud radius holds about 100 of
			them and this budget keeps the nearest 64. Since each fixture's own
			Range is 28 studs, anything culled at that distance could not have
			lit a surface you can see anyway. Now that these no longer cast
			shadows they are cheap enough to afford this many.
		]]
		MaxActiveLights = 64,
		ActiveLightRadius = 150,

		--[[
			Master brightness dial for every light the level builds.

			One number rather than five scattered constants, because "the
			lighting is too bright/too dark" is a single judgement and it should
			be a single edit. Halve this and the whole level dims coherently —
			fixtures, dead fixtures and spawn lighting keep their relationship
			to each other.
		]]
		LightScale = 1,

		--[[
			Emissive colour of the fixture panels themselves.

			These are Neon parts, which are fully self-illuminated: their
			apparent brightness comes from their COLOUR and nothing else. No
			PointLight setting, no Ambient value and no LightScale affects them.
			A ceiling of near-white Neon panels reads as a blindingly bright
			room no matter how far the actual lights are turned down, which is
			exactly what happened here — every brightness reduction was being
			applied to something that wasn't the thing glowing.

			Keep these dark. They are lamps seen from below, not light sources.
		]]
		FixtureColor = Color3.fromRGB(198, 192, 165),
		DeadFixtureColor = Color3.fromRGB(74, 70, 62),
		FixtureDimColor = Color3.fromRGB(96, 92, 80),
		SpawnFixtureColor = Color3.fromRGB(214, 208, 180),
		-- How often the active set is recalculated. Four times a second is
		-- imperceptible while walking and costs almost nothing.
		LightStreamInterval = 0.25,
		-- The spawn room is deliberately over-lit: arriving in pitch darkness
		-- with no bearings reads as a bug rather than as atmosphere.
		--[[
			Flicker floor.

			Fluorescents dim rather than cut out, so no part of the level is
			ever genuinely unlit — being unable to see at all reads as a bug,
			not as atmosphere.
		]]
		FlickerDimBrightness = 0.05,

		--[[
			Proportion of fixtures that are simply dead.

			A light every three cells means nowhere is unlit — which is what we
			want, but it also flattens the level into uniform brightness. Dead
			fixtures break that up: they glow just enough to make out the walls,
			leaving long stretches where the flashlight actually matters.
		]]
		DeadLightChance = 0.28,
		-- Dead fixtures get no PointLight at all; their faint glow comes from
		-- the Neon panel alone. That removes roughly a quarter of the level's
		-- lights outright at no visual cost.
		DeadLightBrightness = 0,

		SpawnLightRadius = 3, -- cells around spawn that get guaranteed lighting
		SpawnLightBrightness = 2.4,
		SpawnLightRange = 40,
		Seed = 0, -- 0 = random each server start

		-- Surfaces. SmoothPlastic keeps the walls flat and untextured; swap to
		-- Fabric/Concrete if you ever want the grimier look back.
		WallColor = Color3.fromRGB(232, 126, 34),
		WallMaterial = Enum.Material.SmoothPlastic,
		FloorColor = Color3.fromRGB(186, 100, 26),
		FloorMaterial = Enum.Material.SmoothPlastic,
		-- The ceiling is the same surface as the walls. It was previously a
		-- near-white slab spanning the whole level, which read as one enormous
		-- area light and washed everything out. Only the fixtures should look
		-- like light sources.
		CeilingColor = Color3.fromRGB(196, 106, 29),
		CeilingMaterial = Enum.Material.SmoothPlastic,
	},

	Player = {
		WalkSpeed = 26,
		SprintSpeed = 42,
		MaxStamina = 100,
		StaminaDrain = 14, -- per second while sprinting
		StaminaRegen = 12, -- per second while not sprinting
		SprintMinStamina = 10, -- can't start a sprint below this
	},

	Entity = {
		MaxAlive = 10,
		SpawnInterval = 3, -- seconds between spawn attempts
		-- They arrive in groups rather than one at a time, so you meet a pack
		-- in a corridor instead of a lone figure.
		GroupSize = { 2, 4 },
		GroupRadius = 20, -- how far apart a group spawns
		-- One that spots you tells everything within this range where you are.
		-- This is what turns a scattering of wanderers into a hunt.
		AlertRadius = 130,
		-- Never spawn one closer than this to a player, so they don't just
		-- appear in your face.
		MinSpawnDistance = 55,
		--[[
			Entities only exist near a player. Spawning across the whole level
			meant most of them were pathfinding around empty corridors nobody
			would ever see — pure server cost. Anything that drifts past
			DespawnDistance is removed and its budget reused somewhere it
			matters.
		]]
		MaxSpawnDistance = 150,
		DespawnDistance = 260,

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
				WalkSpeed = 15,
				ChaseSpeed = 29,
				Score = 100,
				Tendrils = 0,
				Build = {
					TorsoSize = Vector3.new(1.9, 3.1, 0.75),
					HeadSize = Vector3.new(1.05, 1.4, 1.05),
					ArmSize = Vector3.new(0.42, 4.1, 0.42),
					LegSize = Vector3.new(0.55, 4.1, 0.55),
					HeadColor = Color3.fromRGB(226, 222, 210),
					BodyColor = Color3.fromRGB(18, 17, 20),
					LimbColor = Color3.fromRGB(24, 23, 26),
					HeadReflectance = 0.04,
					-- "Auto" picks black or glowing from the head's own
					-- brightness: dark heads get eyes that glow, pale heads get
					-- eyes that read as holes. Either way the eyes are the one
					-- part of the face that exists.
					EyeStyle = "Auto",
					EyeGlowColor = Color3.fromRGB(255, 150, 60),
				},
			},
			{
				-- Slender: rarer, taller, slower to start and faster once it has
				-- you. Black suit, a featureless white head, and tendrils that
				-- only unfurl properly when it moves.
				Id = "Slender",
				Weight = 1,
				Health = 240,
				WalkSpeed = 13,
				ChaseSpeed = 31,
				Score = 300,
				Tendrils = 4,
				Build = {
					TorsoSize = Vector3.new(1.7, 3.8, 0.6),
					HeadSize = Vector3.new(1.0, 1.3, 1.0),
					ArmSize = Vector3.new(0.34, 5.4, 0.34),
					LegSize = Vector3.new(0.46, 4.9, 0.46),
					-- Bright white, and slightly glossy so it catches the flashlight
					-- from across a room.
					HeadColor = Color3.fromRGB(248, 248, 246),
					BodyColor = Color3.fromRGB(8, 8, 10),
					LimbColor = Color3.fromRGB(10, 10, 12),
					HeadReflectance = 0.18,
					-- Forced rather than Auto: two burning points on a blank
					-- white head is a better silhouette than two dark dots.
					EyeStyle = "Glow",
					EyeGlowColor = Color3.fromRGB(255, 62, 48),
				},
				TendrilSize = Vector3.new(0.22, 6.4, 0.22),
				TendrilColor = Color3.fromRGB(6, 6, 8),
			},
		},

		--[[
			Limb animation. Roblox only animates a rig you give an Animator and
			an uploaded animation asset; a procedural cycle driven straight off
			the Motor6D joints needs neither, and reads correctly at any walk
			speed because the phase advances with distance travelled.
		]]
		SwingAngle = 34, -- degrees of leg swing at full stride
		ArmSwingRatio = 0.75, -- arms swing this fraction of the legs
		StrideLength = 4.6, -- studs travelled per half-cycle
		-- Idle sway, so a standing entity never reads as a static prop.
		SwayAngle = 5,
		SwayPeriod = 4.5,

		SightRange = 150,
		-- Inside this range it stops pathfinding and simply comes at you.
		-- Pathfinding latency is what made them hesitate at close quarters.
		LungeRange = 22,
		AttackRange = 9,
		AttackDamage = 22,
		AttackCooldown = 0.75,
		-- How long it keeps chasing your last known position after losing you.
		SearchTime = 12,
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
				Id = "",
				Pitch = 0.28,
				Volume = 0.55,
				Range = 70,
			},
			-- Occasional vocalisation while it wanders.
			Idle = {
				Id = "",
				Pitch = 0.42,
				Volume = 0.7,
				Range = 85,
			},
			-- Fires once, the moment it spots you.
			Alert = {
				Id = "",
				Pitch = 0.5,
				Volume = 1,
				Range = 120,
			},
			-- Rhythmic scrape while chasing.
			Chase = {
				Id = "",
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
			Id = "",
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

	Match = {
		--[[
			The start sequence.

			Nothing spawns and nobody can move until every client reports that
			it has finished loading. Dropping a player into a half-streamed
			level and letting entities hunt them immediately is the difference
			between a game starting and a game already having gone wrong.
		]]
		CountdownSteps = { "3", "2", "1" },
		StepSeconds = 0.85,
		GoText = "FIGHT!",
		GoSeconds = 1.1,
		-- Give up waiting for a client that never reports ready, so one bad
		-- connection can't hold the server open forever.
		ReadyTimeout = 45,
	},

	Cash = {
		-- Dropped by every entity killed.
		DropValue = 50,
		PickupRadius = 7,
		-- Drops vanish eventually so a long session doesn't litter the level
		-- with hundreds of collectables.
		Lifetime = 60,
		Color = Color3.fromRGB(120, 235, 130),
	},

	Score = {
		-- Multiplier applied to a kill's value when the killing shot was a
		-- headshot. Kill value itself is per-variant, in Entity.Variants.
		HeadshotMultiplier = 2,
		-- Awarded for a headshot that doesn't kill, so precision always pays.
		HeadshotBonus = 25,
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
		-- The maze got a great deal tighter, so a given pickup is much harder
		-- to stumble across; this is per weapon type rather than in total.
		SpawnCount = 45,
		RespawnDelay = 25,
		PickupRadius = 7,
	},

	PickupAudio = {
		-- A magazine seating home when you collect a weapon.
		Weapon = {
			Id = "",
			Pitch = 0.75,
			Volume = 1,
			Range = 45,
		},
		-- Second click a beat later, so it reads as a magazine rather than a
		-- light switch.
		WeaponSecondClick = {
			Id = "",
			Pitch = 1.1,
			Volume = 0.8,
			Range = 45,
			Delay = 0.11,
		},
		-- Bright ascending sparkle for health.
		Match = {
			--[[
			The start sequence.

			Nothing spawns and nobody can move until every client reports that
			it has finished loading. Dropping a player into a half-streamed
			level and letting entities hunt them immediately is the difference
			between a game starting and a game already having gone wrong.
		]]
			CountdownSteps = { "3", "2", "1" },
			StepSeconds = 0.85,
			GoText = "FIGHT!",
			GoSeconds = 1.1,
			-- Give up waiting for a client that never reports ready, so one bad
			-- connection can't hold the server open forever.
			ReadyTimeout = 45,
		},

		Cash = {
			-- Dropped by every entity killed.
			DropValue = 50,
			PickupRadius = 7,
			-- Drops vanish eventually so a long session doesn't litter the level
			-- with hundreds of collectables.
			Lifetime = 60,
			Color = Color3.fromRGB(120, 235, 130),
		},

		Score = {
			-- Multiplier applied to a kill's value when the killing shot was a
			-- headshot. Kill value itself is per-variant, in Entity.Variants.
			HeadshotMultiplier = 2,
			-- Awarded for a headshot that doesn't kill, so precision always pays.
			HeadshotBonus = 25,
		},

		Health = {
			Id = "",
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
		DryFireId = "",
		DryFirePitch = 1.6,
		DryFireVolume = 0.55,
		-- Minimum gap between clicks, so holding the trigger on an empty gun
		-- makes one click rather than a machine-gun of them.
		DryFireCooldown = 0.35,
	},

	--[[
		AUDIO IS OFF BY DEFAULT, AND EVERY SOUND ID IS EMPTY.

		The project previously used `rbxasset://sounds/...` paths on the
		assumption that those ship with the Roblox client and need no upload.
		They do not resolve locally: Roblox fetches them over HTTP from
		assetdelivery.roblox.com, and here every one of them failed —
		"Asset is not approved", then connection timeouts after 5 seconds each.

		That is not merely silent, it is dangerous. Firing a burst weapon
		creates ten Sound instances in under a second, each starting its own
		hanging HTTP request. Eighty failed loads in one session was enough to
		take Studio down completely.

		So: no sound is created at all unless Enabled is true AND the specific
		id is non-empty. To add audio, upload your files to Roblox, paste the
		`rbxassetid://...` values into the fields below, and set Enabled = true.
		Anything you leave empty simply stays silent.
	]]
	Audio = {
		Enabled = false,
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

		DroneId = "",
		-- Pitch and base volume for each layer of the bed.
		DroneLayers = {
			{ Pitch = 0.18, Volume = 0.34 },
			{ Pitch = 0.27, Volume = 0.24 },
			{ Pitch = 0.41, Volume = 0.15 },
		},
		-- Seconds for a layer's volume to complete one slow swell. The periods
		-- don't divide into each other, so the bed never audibly loops.
		DronePeriods = { 23, 37, 53 },

		-- Occasional distant noises, so the level isn't only a flat drone.
		StingerIds = {
			"",
			"",
			"",
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

	Flashlight = {
		Range = 60,
		Angle = 55,
		Brightness = 2,
		MaxBattery = 100,
		BatteryDrain = 1.2, -- per second while on
	},
}

return Config
