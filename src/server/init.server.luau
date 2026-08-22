--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CashService = require(script.CashService)
local EntityService = require(script.EntityService)
local EscapeService = require(script.EscapeService)
local FlashlightService = require(script.FlashlightService)
local HealthService = require(script.HealthService)
local LeaderboardService = require(script.LeaderboardService)
local LivesService = require(script.LivesService)
local MatchService = require(script.MatchService)
local LevelGenerator = require(script.LevelGenerator)
local LightingService = require(script.LightingService)
local PlayerService = require(script.PlayerService)
local ScoreService = require(script.ScoreService)
local SpawnPoints = require(script.SpawnPoints)
local WorkspaceCleaner = require(script.WorkspaceCleaner)
local WeaponService = require(script.WeaponService)

-- Before anything else: clients block on these existing.
Remotes.initialize()

--[[
	FIRST, before anything else runs.

	Roblox spawns characters automatically the moment a player is present, and
	that can happen while this script is still setting the level up. Until the
	maze exists there is nothing to stand on, so an auto-spawned character drops
	straight through the world — which only became visible once the cleanup
	started removing the template Baseplate that had been silently catching
	them. Nothing may spawn until we say so.
]]
Players.CharacterAutoLoads = false

-- Now it is safe to clear out template content the level would otherwise
-- generate on top of.
WorkspaceCleaner.run()

LightingService.start()

local grid = LevelGenerator.generate()
local openPositions = LevelGenerator.openPositions(grid)

-- Weapons and medkits draw from one shuffled pool so two pickups can never
-- land on the same tile. Entities may spawn anywhere open.
local pool = SpawnPoints.new(openPositions, Random.new())

PlayerService.spawnPosition = LevelGenerator.spawnPosition(grid)
PlayerService.start()
ScoreService.start()
LeaderboardService.start()
CashService.start()
LivesService.start()
MatchService.start()
FlashlightService.start()
WeaponService.start()
WeaponService.spawnPickups(pool:take(Config.Weapons.SpawnCount))
HealthService.start(pool:take(Config.Health.SpawnCount))
FlashlightService.spawnPickups(pool:take(Config.Flashlight.SpawnCount))
LivesService.spawnPickups(pool:take(Config.Lives.PickupCount))
EntityService.start(openPositions)
EscapeService.start(openPositions, LevelGenerator.spawnPosition(grid))

print("[Server] arlo-backrooms-game ready")
