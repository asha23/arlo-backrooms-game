--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EntityService = require(script.EntityService)
local HealthService = require(script.HealthService)
local LevelGenerator = require(script.LevelGenerator)
local PlayerService = require(script.PlayerService)
local SpawnPoints = require(script.SpawnPoints)
local WeaponService = require(script.WeaponService)

-- Before anything else: clients block on these existing.
Remotes.initialize()

local grid = LevelGenerator.generate()
local openPositions = LevelGenerator.openPositions(grid)

-- Weapons and medkits draw from one shuffled pool so two pickups can never
-- land on the same tile. Entities may spawn anywhere open.
local pool = SpawnPoints.new(openPositions, Random.new())

PlayerService.start()
WeaponService.start()
WeaponService.spawnPickups(pool:take(Config.Weapons.SpawnCount))
HealthService.start(pool:take(Config.Health.SpawnCount))
EntityService.start(openPositions)

print("[Server] arlo-backrooms-game ready")
