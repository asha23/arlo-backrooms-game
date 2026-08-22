--!strict
--[[
	Lives.

	Five, then the run is over. Death costing something is what makes medkits
	and flashlights worth detouring for — with unlimited respawns, walking into
	a pack and dying is a faster way to get somewhere than going round.

	Running out resets rather than ejects: the score is banked, a GAME OVER is
	shown, and the player starts again with a full five. Being thrown out of a
	game for losing is a worse experience than being asked to go again.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProximityService = require(script.Parent.ProximityService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)

local SETTINGS = Config.Lives

local LivesService = {}

local lives: { [Player]: number } = {}
local onGameOver: ((Player) -> ())? = nil

local function publish(player: Player)
	Remotes.LivesChanged():FireClient(player, lives[player] or 0, SETTINGS.Maximum)
end

function LivesService.remaining(player: Player): number
	return lives[player] or 0
end

--- Grants an extra life. Returns false at maximum, so a pickup isn't consumed.
function LivesService.grant(player: Player): boolean
	local current = lives[player] or 0
	if current >= SETTINGS.Maximum then
		return false
	end
	lives[player] = current + 1
	publish(player)
	return true
end

--- Spends one. Returns true if the player still has lives left.
function LivesService.spend(player: Player): boolean
	local current = math.max(0, (lives[player] or 0) - 1)
	lives[player] = current
	publish(player)
	return current > 0
end

function LivesService.reset(player: Player)
	lives[player] = SETTINGS.Starting
	publish(player)
end

--- MatchService supplies what to do when someone runs out.
function LivesService.setGameOverHandler(handler: (Player) -> ())
	onGameOver = handler
end

function LivesService.gameOver(player: Player)
	if onGameOver then
		onGameOver(player)
	end
end

function LivesService.start()
	local function setUp(player: Player)
		LivesService.reset(player)
	end

	Players.PlayerAdded:Connect(setUp)
	for _, player in Players:GetPlayers() do
		setUp(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lives[player] = nil
	end)
end

--- Scatters the extra-life pickups.
function LivesService.spawnPickups(positions: { Vector3 })
	local folder = Instance.new("Folder")
	folder.Name = "LivePickups"
	folder.Parent = workspace

	for _, position in positions do
		local origin = CFrame.new(position + Vector3.new(0, 1.4, 0))

		local heart = Instance.new("Part")
		heart.Name = "ExtraLife"
		heart.Anchored = true
		heart.CanCollide = false
		heart.CanTouch = false
		heart.CanQuery = false
		heart.Size = Vector3.new(1.3, 1.3, 1.3)
		heart.Shape = Enum.PartType.Ball
		heart.Material = Enum.Material.Neon
		heart.Color = SETTINGS.Color
		heart.CFrame = origin
		heart.Parent = folder

		local glow = Instance.new("PointLight")
		glow.Color = SETTINGS.Color
		glow.Brightness = 0.9
		glow.Range = 14
		glow.Parent = heart

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(140, 24)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0)
		billboard.MaxDistance = 80
		billboard.LightInfluence = 0
		billboard.Parent = heart

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = SETTINGS.Color
		label.TextStrokeTransparency = 0.4
		label.Text = "EXTRA LIFE"
		label.Parent = billboard

		--[[
			Bobbing is cosmetic and cheap; the pickup test itself goes through
			the shared proximity loop rather than this thread.
		]]
		task.spawn(function()
			local bob = 0
			while heart.Parent do
				task.wait(0.1)
				bob += 0.22
				heart.CFrame = origin
					* CFrame.new(0, math.sin(bob) * 0.35, 0)
					* CFrame.Angles(0, bob * 0.6, 0)
			end
		end)

		ProximityService.register(origin.Position, SETTINGS.PickupRadius, function(player)
			-- Left on the floor if they are already at maximum.
			if not LivesService.grant(player) then
				return false
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				SoundKit.playOnce(root, {
					Id = SETTINGS.FanfareId,
					Pitch = 1,
					Volume = SETTINGS.FanfareVolume,
					Range = 60,
				})
			end
			heart:Destroy()
			return true
		end)
	end
	print(`[Lives] placed {#positions} extra lives`)
end

return LivesService
