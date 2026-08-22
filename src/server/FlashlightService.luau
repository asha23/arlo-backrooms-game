--!strict
--[[
	The flashlight: a scarce pickup that keeps the entities off you.

	Server-authoritative, because the entities react to it. A client-owned torch
	would mean a client deciding when the monsters run away.

	It is welded to the character's LEFT arm rather than being a Tool. Roblox
	Tools equip to the right hand, so making this a Tool would force a choice
	between carrying light and carrying a weapon — in a game about shooting
	things in the dark, that is the wrong choice to impose.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SETTINGS = Config.Flashlight

local FlashlightService = {}

type Torch = {
	battery: number,
	on: boolean,
	model: Model?,
	light: SpotLight?,
}

local torches: { [Player]: Torch } = {}

local function torchFor(player: Player): Torch
	local torch = torches[player]
	if not torch then
		torch = { battery = 0, on = false, model = nil, light = nil }
		torches[player] = torch
	end
	return torch
end

local function publish(player: Player)
	local torch = torchFor(player)
	Remotes.FlashlightState()
		:FireClient(player, torch.model ~= nil, torch.on, torch.battery, SETTINGS.MaxBattery)
end

local function newPart(props: { [string]: any }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

--- Builds the torch body. `anchored` for the version sitting on the floor.
local function buildTorch(anchored: boolean): Model
	local model = Instance.new("Model")
	model.Name = "Flashlight"

	local body = newPart({
		Name = "Body",
		Size = Vector3.new(0.42, 0.42, 1.5),
		Color = Color3.fromRGB(52, 52, 56),
		Anchored = anchored,
	}, model)

	local lens = newPart({
		Name = "Lens",
		Size = Vector3.new(0.34, 0.34, 0.12),
		Color = Color3.fromRGB(255, 246, 214),
		Material = Enum.Material.Neon,
		Anchored = anchored,
	}, model)
	lens.CFrame = body.CFrame * CFrame.new(0, 0, -0.8)

	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = lens
	weld.C0 = CFrame.new(0, 0, -0.8)
	weld.Parent = body

	model.PrimaryPart = body
	return model
end

--- Attaches a torch to the player's left arm.
local function attach(player: Player): boolean
	local character = player.Character
	local arm = character and character:FindFirstChild("Left Arm") :: BasePart?
	if not character or not arm then
		return false
	end

	local torch = torchFor(player)
	if torch.model then
		return true
	end

	local model = buildTorch(false)
	local body = model.PrimaryPart :: BasePart

	-- Held pointing forward, at the bottom of the arm where a hand would be.
	local grip = CFrame.new(0, -0.85, -0.35)
	body.CFrame = arm.CFrame * grip

	local weld = Instance.new("Weld")
	weld.Part0 = arm
	weld.Part1 = body
	weld.C0 = grip
	weld.Parent = arm

	local light = Instance.new("SpotLight")
	light.Name = "Beam"
	light.Face = Enum.NormalId.Front
	light.Range = SETTINGS.Range
	light.Angle = SETTINGS.Angle
	light.Brightness = SETTINGS.Brightness
	light.Color = Color3.fromRGB(255, 247, 222)
	light.Shadows = false
	light.Enabled = false
	light.Parent = body

	model.Parent = character
	torch.model = model
	torch.light = light
	return true
end

--- Gives a torch, or tops up an existing one. Returns whether anything changed.
function FlashlightService.give(player: Player): boolean
	local torch = torchFor(player)
	local full = torch.battery >= SETTINGS.MaxBattery
	if torch.model and full then
		return false
	end

	if not torch.model and not attach(player) then
		return false
	end
	torch.battery = SETTINGS.MaxBattery
	publish(player)
	return true
end

--[[
	The position an entity at `position` should be running away from, if any.

	An entity counts as caught when it is inside the beam's range AND inside its
	cone. Range alone would mean a torch scared things behind you, which makes
	it a bubble rather than a beam and removes any reason to point it.
]]
function FlashlightService.threatFor(position: Vector3): Vector3?
	local cosLimit = math.cos(math.rad(SETTINGS.ScareAngle))

	for player, torch in torches do
		if not torch.on or torch.battery <= 0 or not torch.model then
			continue
		end
		local body = torch.model.PrimaryPart
		if not body then
			continue
		end

		local offset = position - body.Position
		local distance = offset.Magnitude
		if distance > SETTINGS.ScareRange or distance < 0.1 then
			continue
		end

		-- The arm's -Z is where the beam points, matching SpotLight Face.Front.
		local facing = -body.CFrame.LookVector
		if facing:Dot(offset.Unit) >= cosLimit then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			return if root then root.Position else body.Position
		end
	end
	return nil
end

local function setOn(player: Player, on: boolean)
	local torch = torchFor(player)
	if not torch.model or (on and torch.battery <= 0) then
		return
	end
	torch.on = on
	if torch.light then
		torch.light.Enabled = on
	end
	local lens = torch.model:FindFirstChild("Lens") :: BasePart?
	if lens then
		lens.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	publish(player)
end

function FlashlightService.start()
	Remotes.ToggleFlashlight().OnServerEvent:Connect(function(player)
		local torch = torchFor(player)
		setOn(player, not torch.on)
	end)

	-- The torch is welded to the character, so it dies with it. Re-attach on
	-- respawn if there is still charge left, rather than making the player
	-- find another one after every death.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local torch = torchFor(player)
			torch.model = nil
			torch.light = nil
			torch.on = false
			if torch.battery > 0 then
				attach(player)
			end
			publish(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		torches[player] = nil
	end)

	-- Battery drain.
	task.spawn(function()
		local step = 0.25
		while true do
			task.wait(step)
			for player, torch in torches do
				if not torch.on or torch.battery <= 0 then
					continue
				end
				torch.battery = math.max(0, torch.battery - SETTINGS.DrainRate * step)
				if torch.battery <= 0 then
					setOn(player, false)
				else
					publish(player)
				end
			end
		end
	end)
end

--- Scatters the floor pickups.
function FlashlightService.spawnPickups(positions: { Vector3 })
	local folder = Instance.new("Folder")
	folder.Name = "FlashlightPickups"
	folder.Parent = workspace

	for _, position in positions do
		local origin = CFrame.new(position + Vector3.new(0, 1.1, 0))
		local display = buildTorch(true)
		display:PivotTo(origin)
		display.Parent = folder

		local body = display.PrimaryPart :: BasePart
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 240, 200)
		glow.Brightness = 1
		glow.Range = 16
		glow.Parent = body

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(150, 24)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
		billboard.MaxDistance = 80
		billboard.LightInfluence = 0
		billboard.Parent = body

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 240, 200)
		label.TextStrokeTransparency = 0.4
		label.Text = "FLASHLIGHT"
		label.Parent = billboard

		task.spawn(function()
			local spin = 0
			while display.Parent do
				task.wait(0.12)
				spin += 0.3
				display:PivotTo(origin * CFrame.Angles(0, spin, 0))

				for _, player in Players:GetPlayers() do
					local character = player.Character
					local root = character
						and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if not root or (root.Position - origin.Position).Magnitude > 7 then
						continue
					end
					if FlashlightService.give(player) then
						display:Destroy()
						return
					end
				end
			end
		end)
	end
	print(`[Flashlight] placed {#positions} pickups`)
end

return FlashlightService
