--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CashService = require(script.CashService)
local EntityService = require(script.EntityService)
local EscapeService = require(script.EscapeService)
local FlashlightService = require(script.FlashlightService)
local HealthService = require(script.HealthService)
local LeaderboardService = require(script.LeaderboardService)
local MatchService = require(script.MatchService)
local LevelGenerator = require(script.LevelGenerator)
local LightingService = require(script.LightingService)
local PlayerService = require(script.PlayerService)
local ScoreService = require(script.ScoreService)
local SpawnPoints = require(script.SpawnPoints)
local WeaponService = require(script.WeaponService)

-- Before anything else: clients block on these existing.
Remotes.initialize()

LightingService.start()

local grid = LevelGenerator.generate()
local openPositions = LevelGenerator.openPositions(grid)

-- Weapons and medkits draw from one shuffled pool so two pickups can never
-- land on the same tile. Entities may spawn anywhere open.
local pool = SpawnPoints.new(openPositions, Random.new())

PlayerService.start()
ScoreService.start()
LeaderboardService.start()
CashService.start()
MatchService.start()
FlashlightService.start()
WeaponService.start()
WeaponService.spawnPickups(pool:take(Config.Weapons.SpawnCount))
HealthService.start(pool:take(Config.Health.SpawnCount))
FlashlightService.spawnPickups(pool:take(Config.Flashlight.SpawnCount))
EntityService.start(openPositions)
EscapeService.start(openPositions, LevelGenerator.spawnPosition(grid))

print("[Server] arlo-backrooms-game ready")
