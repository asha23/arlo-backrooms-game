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
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SETTINGS = Config.Match

local MatchService = {}

-- Players who have finished their countdown and are actually playing.
local playing: { [Player]: boolean } = {}
local counting: { [Player]: boolean } = {}

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
local function countIn(player: Player)
	if counting[player] or playing[player] then
		return
	end
	counting[player] = true

	local countdown = Remotes.Countdown()
	freeze(player)

	for _, step in SETTINGS.CountdownSteps do
		if not player.Parent then
			counting[player] = nil
			return
		end
		freeze(player) -- re-assert: a respawn mid-countdown resets the humanoid
		countdown:FireClient(player, step, false)
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

	-- Freeze again on every respawn until they're in the fight.
	player.CharacterAdded:Connect(function()
		if not playing[player] then
			freeze(player)
		end
	end)
end

function MatchService.start()
	Remotes.PlayerReady().OnServerEvent:Connect(function(player)
		countIn(player)
	end)

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		playing[player] = nil
		counting[player] = nil
	end)
end

return MatchService
