--!strict
--[[
	Stats for every weapon in the game. The server is the authority on all of
	these — the client reads them only to predict recoil and drive the HUD.
]]

export type Weapon = {
	Name: string,
	Damage: number,
	HeadshotMultiplier: number,
	FireRate: number, -- rounds per second
	Automatic: boolean, -- true = hold to keep firing
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
		Automatic = false,
		MagazineSize = 12,
		ReserveAmmo = 96,
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
		Automatic = true,
		MagazineSize = 45,
		ReserveAmmo = 270,
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
		Automatic = false,
		MagazineSize = 5,
		ReserveAmmo = 30,
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
