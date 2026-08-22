--!strict
--[[
	Scoring.

	Kept server-side and authoritative: the client is told its score, never
	asked for it. Values are exposed both through a remote (for the HUD) and as
	`leaderstats`, which is the folder name Roblox's built-in leaderboard looks
	for — so the player list doubles as a scoreboard with no extra UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SETTINGS = Config.Score

export type Record = {
	score: number,
	kills: number,
	headshots: number,
	escapes: number,
}

local ScoreService = {}

local records: { [Player]: Record } = {}

--[[
	Cash is deliberately its own table rather than a field on Record.

	It's earned differently (picked up off the floor, not awarded for the kill),
	it's spendable where score isn't, and keeping the two apart means a future
	shop can drain cash without ever touching the scoreboard.
]]
local cash: { [Player]: number } = {}

local stats: { [Player]: { score: IntValue, kills: IntValue, cash: IntValue } } = {}

--- Exposed so the leaderboard can read a final score without duplicating the
--- bookkeeping.
local function recordFor(player: Player): Record
	local record = records[player]
	if not record then
		record = { score = 0, kills = 0, headshots = 0, escapes = 0 }
		records[player] = record
	end
	return record
end

local function publish(player: Player)
	local record = recordFor(player)
	local wallet = cash[player] or 0
	local stat = stats[player]
	if stat then
		stat.score.Value = record.score
		stat.kills.Value = record.kills
		stat.cash.Value = wallet
	end
	Remotes.ScoreChanged()
		:FireClient(player, record.score, record.kills, record.headshots, wallet, record.escapes)
end

local function setUpPlayer(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Parent = leaderstats

	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = leaderstats

	local wallet = Instance.new("IntValue")
	wallet.Name = "Cash"
	wallet.Parent = leaderstats

	leaderstats.Parent = player
	stats[player] = { score = score, kills = kills, cash = wallet }
	cash[player] = cash[player] or 0
	publish(player)
end

--[[
	Records a hit. `killed` and `headshot` come from the weapon service, which
	is the only thing that knows how the damage was delivered.

	`value` is the entity's worth, read off the rig rather than looked up by
	name, so a new variant scores correctly without touching this file.
]]
function ScoreService.registerHit(player: Player, value: number, headshot: boolean, killed: boolean)
	local record = recordFor(player)

	if headshot and not killed then
		record.score += SETTINGS.HeadshotBonus
	end

	if killed then
		record.kills += 1
		local award = value
		if headshot then
			record.headshots += 1
			award *= SETTINGS.HeadshotMultiplier
		end
		record.score += math.floor(award)
	end

	publish(player)
end

--- Awards the escape bonus. Counted separately from kills so the scoreboard
--- distinguishes someone who fought their way out from someone who ran.
function ScoreService.registerEscape(player: Player, bonus: number)
	local record = recordFor(player)
	record.score += bonus
	record.escapes += 1
	publish(player)
end

--- Adds to a player's wallet. Cash is never deducted for dying.
function ScoreService.addCash(player: Player, amount: number)
	cash[player] = (cash[player] or 0) + amount
	publish(player)
end

--- Current wallet balance, for anything that will eventually spend it.
function ScoreService.cashFor(player: Player): number
	return cash[player] or 0
end

function ScoreService.recordFor(player: Player): Record
	return recordFor(player)
end

function ScoreService.start()
	Players.PlayerAdded:Connect(setUpPlayer)
	for _, player in Players:GetPlayers() do
		setUpPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		records[player] = nil
		cash[player] = nil
		stats[player] = nil
	end)
end

return ScoreService
