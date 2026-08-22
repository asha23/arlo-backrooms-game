--!strict
--[[
	Cash drops.

	Every entity killed leaves a note on the floor. Like the weapon and health
	pickups these are inert anchored Models with CanTouch off, collected by a
	distance check rather than a Touched event — Touched is unreliable at speed
	and a fast player can tunnel straight past a thin part without firing it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ScoreService = require(script.Parent.ScoreService)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)

local SETTINGS = Config.Cash

local CashService = {}

local folder: Folder? = nil

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

local function buildNote(origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Cash"

	local note = newPart({
		Name = "Note",
		Size = Vector3.new(1.8, 0.08, 0.9),
		CFrame = origin,
		Color = SETTINGS.Color,
		Material = Enum.Material.Neon,
	}, model)

	local glow = Instance.new("PointLight")
	glow.Color = SETTINGS.Color
	glow.Brightness = 0.45
	glow.Range = 12
	glow.Parent = note

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(90, 24)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Parent = note

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = SETTINGS.Color
	label.TextStrokeTransparency = 0.4
	label.Text = `${SETTINGS.DropValue}`
	label.Parent = billboard

	model.PrimaryPart = note
	return model
end

--- Drops a note where something died.
function CashService.drop(position: Vector3)
	local parent = folder
	if not parent then
		return
	end

	local origin = CFrame.new(position + Vector3.new(0, 1, 0))
	local note = buildNote(origin)
	note.Parent = parent

	local collected = false
	local expiresAt = os.clock() + SETTINGS.Lifetime

	task.spawn(function()
		-- Slow spin, so it catches the eye in a dark corridor.
		local spin = 0
		while note.Parent and not collected do
			task.wait(0.1)
			spin += 0.35
			local primary = note.PrimaryPart
			if primary then
				primary.CFrame = origin * CFrame.Angles(0, spin, 0)
			end

			if os.clock() > expiresAt then
				note:Destroy()
				return
			end

			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not root then
					continue
				end
				if (root.Position - origin.Position).Magnitude > SETTINGS.PickupRadius then
					continue
				end

				collected = true
				ScoreService.addCash(player, SETTINGS.DropValue)
				SoundKit.playOnce(root, {
					Id = "rbxasset://sounds/electronicpingshort.wav",
					Pitch = 1.2,
					Volume = 0.8,
					Range = 40,
				})
				note:Destroy()
				return
			end
		end
	end)
end

function CashService.start()
	local created = Instance.new("Folder")
	created.Name = "CashDrops"
	created.Parent = workspace
	folder = created
end

return CashService
