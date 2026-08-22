--!strict
--[[
	Medkits. Roll over one and you're restored to full.

	Like the weapon pickups, the floor object is inert scenery — anchored, with
	CanTouch and CanQuery off — and collection is driven by a distance check
	rather than a Touched event. Touched fires unpredictably at speed and can
	miss entirely when a fast-moving character tunnels past a thin part.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProximityService = require(script.Parent.ProximityService)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)

local SETTINGS = Config.Health

local CROSS_COLOR = Color3.fromRGB(240, 245, 245)
local CASE_COLOR = Color3.fromRGB(190, 40, 45)

local HealthService = {}

local function newPart(props: { [string]: any }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

--- A red case with a white cross on top, so it reads at a glance in the dark.
local function buildBox(origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Medkit"

	local case = newPart({
		Name = "Case",
		Size = Vector3.new(2.2, 1.4, 1.6),
		CFrame = origin,
		Color = CASE_COLOR,
	}, model)

	newPart({
		Name = "CrossV",
		Size = Vector3.new(0.35, 0.1, 1.1),
		CFrame = origin * CFrame.new(0, 0.72, 0),
		Color = CROSS_COLOR,
		Material = Enum.Material.Neon,
	}, model)

	newPart({
		Name = "CrossH",
		Size = Vector3.new(1.2, 0.1, 0.35),
		CFrame = origin * CFrame.new(0, 0.72, 0),
		Color = CROSS_COLOR,
		Material = Enum.Material.Neon,
	}, model)

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 120, 120)
	glow.Brightness = 0.4
	glow.Range = 11
	glow.Parent = case

	model.PrimaryPart = case
	return model
end

local function placeBox(position: Vector3, parent: Instance)
	local origin = CFrame.new(position + Vector3.new(0, 1.2, 0))
	local box = buildBox(origin)
	box.Parent = parent

	local function setVisible(visible: boolean)
		for _, part in box:GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			part.Transparency = if visible then 0 else 1
			local light = part:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = visible
			end
		end
	end

	--[[
		Registered with the shared proximity loop rather than polling from its
		own thread. See ProximityService: fourteen of these each waking three
		times a second to walk the player list is a cost that scales with loot
		rather than with players.
	]]
	local handle: ProximityService.Handle
	handle = ProximityService.register(origin.Position, SETTINGS.PickupRadius, function(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or not root:IsA("BasePart") then
			return false
		end
		-- Left on the floor for someone who actually needs it.
		if humanoid.Health >= humanoid.MaxHealth then
			return false
		end

		humanoid.Health = humanoid.MaxHealth

		--[[
			Sparkle: one ping plus a short ascending run of quieter, higher ones
			a few hundredths apart. A single ping reads as a UI blip; the run
			reads as something good happening.
		]]
		local audio = Config.PickupAudio
		SoundKit.playOnce(root, {
			Id = audio.Health.Id,
			Pitch = audio.Health.Pitch,
			Volume = audio.Health.Volume,
			Range = audio.Health.Range,
		})
		for _, sparkle in audio.HealthSparkles do
			task.delay(sparkle.Delay, function()
				if root.Parent then
					SoundKit.playOnce(root, {
						Id = audio.Health.Id,
						Pitch = sparkle.Pitch,
						Volume = sparkle.Volume,
						Range = audio.Health.Range,
					})
				end
			end)
		end

		setVisible(false)
		task.delay(SETTINGS.RespawnDelay, function()
			if box.Parent then
				setVisible(true)
				handle:setActive(true)
			end
		end)
		return true
	end)
end

function HealthService.start(positions: { Vector3 })
	local folder = Instance.new("Folder")
	folder.Name = "Medkits"
	folder.Parent = workspace

	for _, position in positions do
		placeBox(position, folder)
	end
	print(`[Health] placed {#positions} medkits`)
end

return HealthService
