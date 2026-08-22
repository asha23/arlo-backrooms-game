--!strict
--[[
	Sets characters up when they spawn and reacts to sanity hitting zero.
	Sanity itself is simulated on the client (it's driven by what the player can
	see); the server only receives the value and owns the consequences.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerService = {}

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 42
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
	Remotes.LevelReady():FireClient(player)
end

function PlayerService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	local sanityChanged = Remotes.SanityChanged()
	sanityChanged.OnServerEvent:Connect(function(player, sanity)
		if typeof(sanity) ~= "number" or sanity ~= sanity then
			return
		end
		if sanity > 0 then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end)
end

return PlayerService
