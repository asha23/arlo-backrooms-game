--!strict
--[[
	Sets characters up when they spawn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerService = {}

--- Where to put anyone who falls out of the world. Set by the bootstrap once
--- the level knows where its entrance is.
PlayerService.spawnPosition = Vector3.zero

--[[
	Anyone who ends up below the world is put back at the entrance.

	A last resort rather than a mechanism. Falling out of the level is
	unrecoverable and looks like the game breaking, so it is worth catching even
	though the ordering fix above should mean it never happens.
]]
local function watchForFalling(character: Model, humanoid: Humanoid)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	task.spawn(function()
		while character.Parent and humanoid.Health > 0 do
			task.wait(0.5)
			if root.Position.Y < -60 then
				warn(`[Player] rescuing {character.Name} from below the level`)
				local home = PlayerService.spawnPosition
				character:PivotTo(CFrame.new(home + Vector3.new(0, 5, 0)))
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end)
end

local function onCharacterAdded(character: Model)
	-- Bounded: a character without a Humanoid is a broken character, and this
	-- thread hanging forever would take the fall-rescue watcher with it.
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		warn(`[Player] {character.Name} spawned without a Humanoid`)
		return
	end
	-- MaxHealth first: setting Health above the current max is clamped.
	humanoid.MaxHealth = Config.Player.MaxHealth
	humanoid.Health = Config.Player.MaxHealth
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 42

	watchForFalling(character, humanoid)
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
		CharacterAutoLoads is switched off in the server bootstrap rather than
		here: by the time this runs the level has already been built, and there
		is a window before that in which Roblox would happily spawn someone into
		an empty world.
	]]

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return PlayerService
