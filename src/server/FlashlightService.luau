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
		Size = Vector3.new(0.55, 0.55, 1.9),
		Color = Color3.fromRGB(52, 52, 56),
		Anchored = anchored,
	}, model)

	local lens = newPart({
		Name = "Lens",
		Size = Vector3.new(0.46, 0.46, 0.16),
		Color = Color3.fromRGB(255, 246, 214),
		Material = Enum.Material.Neon,
		Anchored = anchored,
	}, model)
	lens.CFrame = body.CFrame * CFrame.new(0, 0, -1.0)

	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = lens
	weld.C0 = CFrame.new(0, 0, -1.0)
	weld.Parent = body

	model.PrimaryPart = body
	return model
end

--[[
	Where the torch goes, best option first.

	Players use their own Roblox avatar, and Roblox defaults new experiences to
	R15 — which has no part called "Left Arm". Looking only for the R6 name
	meant attach() quietly returned false for essentially every real player, so
	give() reported failure and the pickup was never consumed. That is the whole
	"I can't pick up the flashlight" bug: it was never picked up because the
	game could not find a hand to put it in.

	Each entry carries its own grip, because an R15 hand and an R6 whole-arm
	part have very different origins.
]]
local LEFT_HAND_PARTS = {
	{ name = "LeftHand", grip = CFrame.new(0, -0.25, -0.4) }, -- R15
	{ name = "LeftLowerArm", grip = CFrame.new(0, -0.55, -0.4) }, -- R15, no hand
	{ name = "Left Arm", grip = CFrame.new(0, -0.85, -0.35) }, -- R6
}

local function findGrip(character: Model): (BasePart?, CFrame)
	for _, candidate in LEFT_HAND_PARTS do
		local part = character:FindFirstChild(candidate.name)
		if part and part:IsA("BasePart") then
			return part, candidate.grip
		end
	end
	return nil, CFrame.identity
end

--- Attaches a torch to the player's left hand, on either rig.
local function attach(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local arm, grip = findGrip(character)
	if not arm then
		-- Worth shouting about: it means a rig this code does not understand.
		if not character:GetAttribute("TorchGripWarned") then
			character:SetAttribute("TorchGripWarned", true)
			warn(`[Flashlight] no left-hand part on {player.Name}'s character; cannot attach`)
		end
		return false
	end

	local torch = torchFor(player)
	if torch.model then
		return true
	end

	local model = buildTorch(false)
	local body = model.PrimaryPart :: BasePart

	body.CFrame = arm.CFrame * grip

	--[[
		Parent the model BEFORE welding. A Weld created while Part1 is still
		outside the world is not reliably honoured, and an unanchored massless
		part that fails to weld simply drops through the floor — which looks
		exactly like the torch never being picked up at all.
	]]
	model.Parent = character

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

	-- A second, wide, dim light so the torch lifts the whole area around you
	-- rather than only painting a disc on whatever it points at.
	local spill = Instance.new("PointLight")
	spill.Name = "Spill"
	spill.Range = SETTINGS.SpillRange
	spill.Brightness = SETTINGS.SpillBrightness
	spill.Color = Color3.fromRGB(255, 244, 214)
	spill.Shadows = false
	spill.Enabled = false
	spill.Parent = body

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

		--[[
			Measured from the player, and aimed along the CHARACTER's facing
			rather than the torch part's.

			The previous version negated the torch's LookVector. LookVector is
			already the front direction in Roblox, and a Part's Front face —
			where SpotLight.Face = Front shines — is that same -Z. Negating it
			pointed the scare cone directly behind the player: things behind
			fled, and the ones in front, which are the ones actually lit, kept
			coming. Using the root also means the cone matches where the player
			believes they are pointing, rather than wherever a swinging arm
			happens to be.
		]]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end

		local offset = position - root.Position
		local distance = offset.Magnitude
		if distance > SETTINGS.ScareRange or distance < 0.1 then
			continue
		end

		local facing = root.CFrame.LookVector
		-- Compare on the horizontal plane: a ten-stud entity's centre is well
		-- above the player's, and the vertical component would otherwise push
		-- a close entity out of the cone.
		local flat = Vector3.new(offset.X, 0, offset.Z)
		if flat.Magnitude > 0.1 and facing:Dot(flat.Unit) >= cosLimit then
			return root.Position
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
	local body = torch.model.PrimaryPart
	local spill = body and body:FindFirstChild("Spill")
	if spill and spill:IsA("PointLight") then
		spill.Enabled = on
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
