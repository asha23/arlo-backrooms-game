--!strict
--[[
	The way out.

	The exit sits at the open cell furthest from spawn, so escaping means
	crossing the level rather than walking out of the room you started in. It is
	the only green light in a yellow maze, which makes it readable from the far
	end of a corridor without needing a HUD marker.

	Reaching it is a win: a large score and cash bonus, a banner, and then back
	to the spawn for another run.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ScoreService = require(script.Parent.ScoreService)

local SETTINGS = Config.Escape

local EscapeService = {}

local exitPosition: Vector3? = nil
local homePosition: Vector3? = nil
local escaping: { [Player]: boolean } = {}

local function newPart(props: { [string]: any }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = SETTINGS.Color
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

--- Builds a lit doorway: a frame, a glowing threshold and a floor marker.
local function buildExit(position: Vector3, parent: Instance)
	local origin = CFrame.new(position)

	-- Uprights and lintel, forming a doorway.
	newPart({
		Name = "ExitLeft",
		Size = Vector3.new(0.5, 9, 0.5),
		CFrame = origin * CFrame.new(-2.6, 4.5, 0),
	}, parent)
	newPart({
		Name = "ExitRight",
		Size = Vector3.new(0.5, 9, 0.5),
		CFrame = origin * CFrame.new(2.6, 4.5, 0),
	}, parent)
	newPart({
		Name = "ExitTop",
		Size = Vector3.new(5.7, 0.5, 0.5),
		CFrame = origin * CFrame.new(0, 9, 0),
	}, parent)

	-- The threshold itself, brighter than everything else in the level.
	local pad = newPart({
		Name = "ExitPad",
		Size = Vector3.new(5.2, 0.15, 5.2),
		CFrame = origin * CFrame.new(0, 0.1, 0),
		Transparency = 0.25,
	}, parent)

	local glow = Instance.new("PointLight")
	glow.Color = SETTINGS.Color
	glow.Brightness = 2.4
	glow.Range = 34
	glow.Parent = pad

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 46)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 10.5, 0)
	billboard.MaxDistance = 250
	billboard.LightInfluence = 0
	billboard.Parent = pad

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = SETTINGS.Color
	label.TextStrokeTransparency = 0.35
	label.Text = "EXIT"
	label.Parent = billboard

	pad:AddTag("Exit")
end

local function onEscape(player: Player)
	if escaping[player] then
		return
	end
	escaping[player] = true

	ScoreService.registerEscape(player, SETTINGS.BonusScore)
	ScoreService.addCash(player, SETTINGS.BonusCash)

	local count = ScoreService.recordFor(player).escapes
	Remotes.Escaped():FireClient(player, SETTINGS.BonusScore, SETTINGS.BonusCash, count)

	task.delay(SETTINGS.CelebrationSeconds, function()
		escaping[player] = nil
		local character = player.Character
		local home = homePosition
		if character and home then
			-- Straight back to the entrance for another run. The level stays as
			-- it is: a fresh maze mid-session would mean tearing down every
			-- entity and pickup while other players are still using them.
			character:PivotTo(CFrame.new(home + Vector3.new(0, 4, 0)))
		end
	end)
end

--- `positions` are open floor cells; `home` is the spawn, which the exit is
--- placed as far from as the level allows.
function EscapeService.start(positions: { Vector3 }, home: Vector3)
	homePosition = home

	local furthest, best = nil, -1
	for _, candidate in positions do
		local distance = (candidate - home).Magnitude
		if distance > best then
			best, furthest = distance, candidate
		end
	end
	if not furthest then
		warn("[Escape] no open cell to place an exit in")
		return
	end
	exitPosition = furthest

	local folder = Instance.new("Folder")
	folder.Name = "Exit"
	folder.Parent = workspace
	buildExit(furthest, folder)

	print(`[Escape] exit placed {math.floor(best)} studs from spawn`)

	task.spawn(function()
		while true do
			task.wait(0.3)
			local target = exitPosition
			if not target then
				continue
			end
			for _, player in Players:GetPlayers() do
				if escaping[player] then
					continue
				end
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not root or not humanoid or humanoid.Health <= 0 then
					continue
				end
				if (root.Position - target).Magnitude <= SETTINGS.TriggerRadius then
					onEscape(player)
				end
			end
		end
	end)
end

return EscapeService
