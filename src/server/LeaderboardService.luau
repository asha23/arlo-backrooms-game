--!strict
--[[
	All-time high scores.

	Backed by an OrderedDataStore, which is the only Roblox store that can
	answer "give me the top N" without reading every key. Names are kept in a
	separate plain DataStore, since an OrderedDataStore can only hold integers.

	Everything here tolerates failure. DataStores are off by default in Studio
	(Game Settings → Security → Enable Studio Access to API Services) and can
	throttle in production, so every call is wrapped and an empty board is a
	normal outcome rather than an error state — a high score table that breaks
	the game when it can't reach the network is worse than no high score table.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ScoreService = require(script.Parent.ScoreService)

local TOP_COUNT = 5

local LeaderboardService = {}

local scores: OrderedDataStore? = nil
local names: DataStore? = nil
local cached: { { name: string, score: number } } = {}
local available = false

local function connect(): boolean
	local ok = pcall(function()
		scores = DataStoreService:GetOrderedDataStore("HighScores_v1")
		names = DataStoreService:GetDataStore("HighScoreNames_v1")
	end)
	if not ok then
		warn("[Leaderboard] datastores unavailable; high scores disabled this session")
	end
	return ok
end

--- Reads the top entries. Returns the cache unchanged if the read fails.
local function refresh()
	local store = scores
	local nameStore = names
	if not store or not nameStore then
		return
	end

	local ok, result = pcall(function()
		return store:GetSortedAsync(false, TOP_COUNT):GetCurrentPage()
	end)
	if not ok or typeof(result) ~= "table" then
		warn("[Leaderboard] read failed; keeping the previous board")
		return
	end

	local board = {}
	for _, entry in result :: { any } do
		local userId = entry.key
		local displayName = `Player {userId}`
		local nameOk, stored = pcall(function()
			return nameStore:GetAsync(userId)
		end)
		if nameOk and typeof(stored) == "string" then
			displayName = stored
		end
		table.insert(board, { name = displayName, score = entry.value })
	end

	cached = board
	available = true
end

--- Records a score if it beats what this player already has stored.
local function submit(player: Player)
	local store = scores
	local nameStore = names
	if not store or not nameStore then
		return
	end

	local record = ScoreService.recordFor(player)
	if record.score <= 0 then
		return
	end

	local key = tostring(player.UserId)

	-- UpdateAsync rather than SetAsync: two servers finishing at once would
	-- otherwise race, and the lower score could land last and win.
	local ok = pcall(function()
		store:UpdateAsync(key, function(previous)
			local best = previous or 0
			return if record.score > best then record.score else best
		end)
	end)
	if not ok then
		warn(`[Leaderboard] failed to save a score for {player.Name}`)
		return
	end

	pcall(function()
		nameStore:SetAsync(key, player.DisplayName)
	end)
end

--[[
	Banks a player's score now.

	Exposed so escaping can trigger a save. An escape is the one moment a run
	has been completed rather than merely interrupted, and waiting up to ninety
	seconds to record it means a crash or a disconnect in between loses it.
]]
function LeaderboardService.submit(player: Player)
	submit(player)
end

function LeaderboardService.top(): { { name: string, score: number } }
	return cached
end

function LeaderboardService.start()
	if RunService:IsStudio() then
		print(
			"[Leaderboard] in Studio: needs Game Settings -> Security -> Enable Studio Access to API Services"
		)
	end

	if not connect() then
		Remotes.RequestLeaderboard().OnServerEvent:Connect(function(player)
			Remotes.Leaderboard():FireClient(player, {}, false)
		end)
		return
	end

	task.spawn(refresh)

	Remotes.RequestLeaderboard().OnServerEvent:Connect(function(player)
		Remotes.Leaderboard():FireClient(player, cached, available)
	end)

	-- Save on the way out, which is when a run's score is final.
	Players.PlayerRemoving:Connect(function(player)
		submit(player)
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			submit(player)
		end
	end)

	--[[
		Escaping is the natural moment to bank a score — it is the only point at
		which a run has been completed rather than merely interrupted, and it
		means a player who never disconnects cleanly still gets on the board.
	]]
	task.spawn(function()
		while true do
			task.wait(90)
			for _, player in Players:GetPlayers() do
				submit(player)
			end
			refresh()
		end
	end)
end

return LeaderboardService
