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
local LeaderboardService = require(script.Parent.LeaderboardService)
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

--[[
	Wall arrows pointing the way out.

	A maze of identical corridors gives you nothing to navigate by, and the exit
	is deliberately placed as far from spawn as the level allows — without some
	signposting, finding it is a random walk rather than a journey.

	Each arrow is raycast onto a real wall rather than placed in mid-air, and
	yawed toward the exit. It points as the crow flies, not along the corridor:
	that is honest about what it knows, and following a straight-line bearing
	through a maze still gets you there.
]]
local function buildArrows(positions: { Vector3 }, target: Vector3, parent: Instance)
	local settings = SETTINGS
	local placed = 0
	local attempts = 0
	local rng = Random.new()

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { parent }

	while placed < settings.ArrowCount and attempts < settings.ArrowCount * 12 do
		attempts += 1
		local origin = positions[rng:NextInteger(1, #positions)]
			+ Vector3.new(0, settings.ArrowHeight, 0)

		-- Too close to the exit and an arrow is noise; you can already see it.
		if (origin - target).Magnitude < 40 then
			continue
		end

		-- Find a wall to mount on.
		local directions = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
		}
		local hit: RaycastResult? = nil
		for _, direction in directions do
			local result = workspace:Raycast(origin, direction * 6, params)
			if result and result.Instance.Name == "Wall" then
				hit = result
				break
			end
		end
		if not hit then
			continue
		end

		local flat = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
		if flat.Magnitude < 1 then
			continue
		end

		-- Sit just off the wall, facing out of it, yawed toward the exit.
		local face = CFrame.lookAt(hit.Position + hit.Normal * 0.12, hit.Position + hit.Normal * 2)
		local bearing = math.atan2(flat.X, flat.Z)
		local surfaceYaw = math.atan2(hit.Normal.X, hit.Normal.Z)
		local spin = bearing - surfaceYaw

		local shaft = newPart({
			Name = "ExitArrowShaft",
			Size = Vector3.new(0.28, 1.5, 0.08),
			CFrame = face * CFrame.Angles(0, 0, -spin) * CFrame.new(0, -0.35, 0),
			Color = settings.ArrowColor,
			Transparency = 0.15,
		}, parent)

		local head = Instance.new("WedgePart")
		head.Name = "ExitArrowHead"
		head.Anchored = true
		head.CanCollide = false
		head.CanTouch = false
		head.CanQuery = false
		head.Material = Enum.Material.Neon
		head.Color = settings.ArrowColor
		head.Transparency = 0.15
		head.Size = Vector3.new(0.1, 0.75, 0.95)
		head.CFrame = shaft.CFrame * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90))
		head.Parent = parent

		placed += 1
	end

	print(`[Escape] placed {placed} wall arrows`)
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

	-- Bank it immediately: a completed run should not be waiting on the next
	-- periodic save to survive a disconnect.
	task.spawn(LeaderboardService.submit, player)

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

	local arrows = Instance.new("Folder")
	arrows.Name = "ExitArrows"
	arrows.Parent = workspace
	buildArrows(positions, furthest, arrows)

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
