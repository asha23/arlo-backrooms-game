--!strict
--[[
	Match start.

	The level generates the instant the server boots, but a player joining sees
	a half-streamed world for a second or two afterwards — and until now
	entities were already hunting during that window. This holds everything: no
	entity spawns, and nobody can move, until every connected client has
	reported that its loading screen finished and the level is actually on
	screen. Then it counts them in.

	Readiness is per-player and the countdown is per-player too, so somebody
	joining a running server gets their own 3-2-1 rather than being dropped
	into the middle of a fight.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LivesService = require(script.Parent.LivesService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SETTINGS = Config.Match

local MatchService = {}

-- Players who have finished their countdown and are actually playing.
local playing: { [Player]: boolean } = {}
local counting: { [Player]: boolean } = {}
-- Players sitting on the death screen, waiting to choose to go again.
local awaitingRespawn: { [Player]: boolean } = {}
-- Of those, the ones who ran out of lives: the same click restarts the run.
local outOfLives: { [Player]: boolean } = {}

--- True once at least one player is in the fight. Entity spawning waits on it.
function MatchService.isLive(): boolean
	for _ in playing do
		return true
	end
	return false
end

local function freeze(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end
end

--[[
	Runs 3 - 2 - 1 - FIGHT! for one player.

	The client is told both what to display and whether it may move. Movement is
	unlocked by the same message that shows "FIGHT!", so there is no window
	where the text says go and the legs don't work, or vice versa.
]]
local function countIn(player: Player, prefix: string?)
	if counting[player] or playing[player] then
		return
	end
	counting[player] = true

	local countdown = Remotes.Countdown()
	freeze(player)

	for _, step in SETTINGS.CountdownSteps do
		local label = if prefix then `{prefix} {step}` else step
		if not player.Parent then
			counting[player] = nil
			return
		end
		freeze(player) -- re-assert: a respawn mid-countdown resets the humanoid
		countdown:FireClient(player, label, false)
		task.wait(SETTINGS.StepSeconds)
	end

	if not player.Parent then
		counting[player] = nil
		return
	end

	playing[player] = true
	counting[player] = nil
	countdown:FireClient(player, SETTINGS.GoText, true)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.Player.WalkSpeed
		humanoid.JumpPower = 42
	end

	task.delay(SETTINGS.GoSeconds, function()
		if player.Parent then
			-- Empty text clears the banner; movement stays unlocked.
			countdown:FireClient(player, "", true)
		end
	end)
end

local function watch(player: Player)
	freeze(player)

	--[[
		Start counting when the client says it's ready, or when the timeout
		expires — a client that never reports (an old build, a broken load)
		must not be left frozen forever.
	]]
	task.delay(SETTINGS.ReadyTimeout, function()
		if player.Parent and not playing[player] then
			warn(`[Match] {player.Name} never reported ready; starting anyway`)
			countIn(player)
		end
	end)

	--[[
		Death handling.

		Roblox would normally respawn the character on its own timer. That is
		switched off (Players.CharacterAutoLoads is false in PlayerService) so
		that dying leaves you on a death screen until you actively choose to go
		again — and then you get the same count-in as the match start rather
		than being dropped straight back into whatever killed you.
	]]
	local function watchCharacter(character: Model)
		if not playing[player] then
			freeze(player)
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		humanoid.Died:Connect(function()
			playing[player] = nil

			--[[
				Spend a life. Running out ends the run rather than ejecting the
				player: score is already banked by the leaderboard's periodic
				save, they see GAME OVER, and then they start again with a full
				five. Being thrown out for losing is a worse experience than
				being asked to go again.
			]]
			local hasLivesLeft = LivesService.spend(player)
			if not hasLivesLeft then
				--[[
					Out of lives. The same click that would have respawned them
					restarts the run instead — waiting out a timer before being
					allowed to try again is friction with nothing behind it.
				]]
				outOfLives[player] = true
				awaitingRespawn[player] = true
				Remotes.GameOver():FireClient(player)
				return
			end

			awaitingRespawn[player] = true
			-- A beat before the prompt, so a death reads as a death.
			task.delay(Config.Respawn.PromptDelay, function()
				if player.Parent and awaitingRespawn[player] then
					Remotes.Died():FireClient(player)
				end
			end)
		end)
	end

	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

function MatchService.start()
	Remotes.PlayerReady().OnServerEvent:Connect(function(player)
		countIn(player)
	end)

	Remotes.RequestRespawn().OnServerEvent:Connect(function(player)
		if not awaitingRespawn[player] then
			return
		end
		awaitingRespawn[player] = nil

		-- A click after GAME OVER starts a fresh run with a full set of lives.
		if outOfLives[player] then
			outOfLives[player] = nil
			LivesService.reset(player)
		end

		player:LoadCharacterAsync()
		-- Count them back in, labelled so it reads as a respawn rather than as
		-- the match starting over.
		countIn(player, Config.Respawn.CountdownPrefix)
	end)

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		playing[player] = nil
		counting[player] = nil
		awaitingRespawn[player] = nil
		outOfLives[player] = nil
	end)
end

return MatchService
