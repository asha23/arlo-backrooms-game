--!strict
--[[
	Sets characters up when they spawn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerService = {}

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	-- MaxHealth first: setting Health above the current max is clamped.
	humanoid.MaxHealth = Config.Player.MaxHealth
	humanoid.Health = Config.Player.MaxHealth
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 42
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	-- CharacterAutoLoads is off, so the first spawn is ours to trigger.
	if player.Character then
		onCharacterAdded(player.Character)
	else
		player:LoadCharacterAsync()
	end
	Remotes.LevelReady():FireClient(player)
end

function PlayerService.start()
	--[[
		Respawning is driven by MatchService, not by Roblox's automatic timer.
		Dying should leave you on a death screen until you choose to go again,
		and then hand you the same count-in the match start uses.
	]]
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return PlayerService
