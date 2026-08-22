--!strict
local LevelGenerator = require(script.LevelGenerator)
local PlayerService = require(script.PlayerService)

LevelGenerator.generate()
PlayerService.start()

print("[Server] arlo-backrooms-game ready")
