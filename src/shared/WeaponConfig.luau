--!strict
--[[
	Stats for every weapon in the game. The server is the authority on all of
	these — the client reads them only to predict recoil and drive the HUD.
]]

--[[
	How the trigger behaves:
	  Semi  — one shot per press, however long you hold it.
	  Burst — a fixed run of shots per press, then a forced pause.
	  Auto  — fires continuously while held.
]]
export type FireMode = "Semi" | "Burst" | "Auto"

export type Weapon = {
	Name: string,
	Damage: number,
	HeadshotMultiplier: number,
	FireRate: number, -- rounds per second
	Mode: FireMode,
	BurstCount: number, -- rounds per burst; ignored unless Mode is "Burst"
	BurstCooldown: number, -- forced pause after a burst, in seconds
	-- Degrees of upward camera kick per shot. Decays back automatically.
	Recoil: number,
	--[[
		Optional telescopic sight. When present, holding right mouse zooms and
		shows the scope overlay instead of firing — the aim button takes
		priority over the fire button on a weapon that has one.
	]]
	Scope: { FieldOfView: number, Sensitivity: number }?,
	-- The id itself is shared (Config.WeaponAudio.FireSoundId); only the
	-- pitch and mix differ per weapon.
	FireSound: { Pitch: number, Volume: number, Range: number, Reverb: number },
	MagazineSize: number,
	ReserveAmmo: number,
	ReloadTime: number,
	Range: number, -- studs
	Spread: number, -- degrees of cone at the muzzle
	PelletsPerShot: number,
	HandleSize: Vector3,
	HandleColor: Color3,
}

local Weapons: { [string]: Weapon } = {
	Pistol = {
		Name = "Pistol",
		Damage = 24,
		HeadshotMultiplier = 2,
		FireRate = 5,
		Mode = "Semi",
		BurstCount = 0,
		BurstCooldown = 0,
		Recoil = 0.6,
		FireSound = {
			Pitch = 0.85,
			Volume = 0.75,
			Range = 220,
			Reverb = 1.8,
		},
		MagazineSize = 20,
		ReserveAmmo = 120,
		ReloadTime = 1.3,
		Range = 220,
		Spread = 1.4,
		PelletsPerShot = 1,
		HandleSize = Vector3.new(0.4, 0.9, 1.5),
		HandleColor = Color3.fromRGB(58, 58, 62),
	},

	MachineGun = {
		Name = "Machine Gun",
		Damage = 14,
		HeadshotMultiplier = 1.5,
		FireRate = 11,
		Mode = "Burst",
		BurstCount = 10,
		BurstCooldown = 0.4,
		Recoil = 0.25,
		FireSound = {
			Pitch = 1.15,
			Volume = 0.55,
			Range = 260,
			Reverb = 1.4,
		},
		MagazineSize = 80,
		ReserveAmmo = 320,
		ReloadTime = 2.4,
		Range = 300,
		Spread = 3.2,
		PelletsPerShot = 1,
		HandleSize = Vector3.new(0.5, 1.0, 3.2),
		HandleColor = Color3.fromRGB(42, 46, 42),
	},

	SniperRifle = {
		Name = "Sniper Rifle",
		Damage = 95,
		HeadshotMultiplier = 3,
		FireRate = 0.8,
		Mode = "Semi",
		BurstCount = 0,
		BurstCooldown = 0,
		Recoil = 1.5,
		-- 18 degrees against a default 70 is roughly 4x magnification, and the
		-- reduced sensitivity is what makes that magnification usable — at
		-- normal sensitivity a scoped view swings far too fast to aim with.
		-- 0.255 is 0.3 less 15%.
		Scope = { FieldOfView = 18, Sensitivity = 0.255 },
		FireSound = {
			Pitch = 0.42,
			Volume = 1,
			Range = 500,
			Reverb = 4.5,
		},
		MagazineSize = 10,
		ReserveAmmo = 40,
		ReloadTime = 3.2,
		Range = 900,
		Spread = 0.15,
		PelletsPerShot = 1,
		HandleSize = Vector3.new(0.45, 0.95, 4.6),
		HandleColor = Color3.fromRGB(70, 58, 40),
	},
}

local WeaponConfig = {
	Weapons = Weapons,
	-- Stable ordering, so spawn distribution doesn't depend on hash iteration.
	Order = { "Pistol", "MachineGun", "SniperRifle" },
}

return WeaponConfig
