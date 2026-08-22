--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EntityService = require(script.EntityService)
local LevelGenerator = require(script.LevelGenerator)
local PlayerService = require(script.PlayerService)
local WeaponService = require(script.WeaponService)

-- Before anything else: clients block on these existing.
Remotes.initialize()

local grid = LevelGenerator.generate()
local openPositions = LevelGenerator.openPositions(grid)

PlayerService.start()
WeaponService.start()
WeaponService.spawnPickups(openPositions)
EntityService.start(openPositions)

print("[Server] arlo-backrooms-game ready")
