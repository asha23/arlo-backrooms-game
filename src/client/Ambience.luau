--!strict
--[[
	The soundtrack.

	Roblox ships sound effects with the client but no music, so rather than
	depend on an uploaded asset that may not exist, the default is a synthesised
	drone bed: the same low tone layered at several pitches with each layer's
	volume drifting on its own slow cycle. Because the cycles have coprime-ish
	periods they never quite line up, so the bed keeps shifting instead of
	looping audibly.

	Point `Config.Ambience.MusicId` at a real track and that plays instead.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local SETTINGS = Config.Ambience

local Ambience = {}

local rng = Random.new()

--- See Config.Audio. Returns nil rather than a Sound with an id that can't
--- resolve, which would cost a hanging HTTP request per instance.
local function newSound(name: string, id: string, parent: Instance): Sound?
	if not Config.Audio.Enabled or id == "" then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Parent = parent
	return sound
end

local function playMusicTrack(parent: Instance)
	local music = newSound("Music", SETTINGS.MusicId, parent)
	if not music then
		return
	end
	music.Looped = true
	music.Volume = SETTINGS.MusicVolume
	music:Play()
end

local function startDroneBed(parent: Instance)
	local layers: { { sound: Sound, base: number, period: number, phase: number } } = {}

	for index, layer in SETTINGS.DroneLayers do
		local sound = newSound(`Drone{index}`, SETTINGS.DroneId, parent)
		if not sound then
			continue
		end
		sound.Looped = true
		sound.PlaybackSpeed = layer.Pitch
		sound.Volume = layer.Volume
		sound:Play()

		table.insert(layers, {
			sound = sound,
			base = layer.Volume,
			period = SETTINGS.DronePeriods[index] or 30,
			-- Random starting phase so two clients don't swell in lockstep.
			phase = rng:NextNumber(0, math.pi * 2),
		})
	end

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		elapsed += deltaTime
		for _, layer in layers do
			-- Drift between 35% and 100% of the layer's base volume.
			local wave = math.sin((elapsed / layer.period) * math.pi * 2 + layer.phase)
			layer.sound.Volume = layer.base * (0.675 + 0.325 * wave)
		end
	end)
end

local function startStingers(parent: Instance)
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(SETTINGS.StingerGap[1], SETTINGS.StingerGap[2]))

			local id = SETTINGS.StingerIds[rng:NextInteger(1, #SETTINGS.StingerIds)]
			local stinger = newSound("Stinger", id, parent)
			if not stinger then
				continue
			end
			stinger.Volume = SETTINGS.StingerVolume
			stinger.PlaybackSpeed =
				rng:NextNumber(SETTINGS.StingerPitch[1], SETTINGS.StingerPitch[2])

			local reverb = Instance.new("ReverbSoundEffect")
			reverb.DecayTime = 4
			reverb.WetLevel = 2
			reverb.DryLevel = -6
			reverb.Parent = stinger

			stinger:Play()
			stinger.Ended:Once(function()
				stinger:Destroy()
			end)
		end
	end)
end

--[[
	Heartbeat that tracks the nearest entity.

	A drone tells you something is out there; it does not tell you how close.
	Tying rate and volume to the nearest entity turns "something is nearby" into
	"it is nearly on you" with no UI at all — and it goes silent the moment
	nothing is in range, so it reads as information rather than as decoration.

	Polled ten times a second rather than on RenderStepped. It walks the entity
	list to find the closest one, and doing that sixty times a second to drive
	something whose entire output is a beat rate is wasted work — at 10Hz it is
	indistinguishable and costs a sixth as much.
]]
local function startHeartbeat(parent: Instance)
	if SETTINGS.HeartbeatId == "" then
		return
	end

	local heart = newSound("Heartbeat", SETTINGS.HeartbeatId, parent)
	if not heart then
		return
	end
	heart.Looped = true
	heart.Volume = 0

	local player = Players.LocalPlayer

	local function silence()
		heart.Volume = 0
		if heart.IsPlaying then
			heart:Stop()
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.1)

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local entities = workspace:FindFirstChild("Entities")
			if not root or not root:IsA("BasePart") or not entities then
				silence()
				continue
			end

			local origin = root.Position
			local closest = math.huge
			for _, model in entities:GetChildren() do
				local part = model:IsA("Model") and model.PrimaryPart
				if part then
					closest = math.min(closest, (part.Position - origin).Magnitude)
				end
			end

			if closest > SETTINGS.HeartbeatRange then
				silence()
				continue
			end

			-- 0 at the edge of the range, 1 when it is on top of you.
			local intensity = 1 - math.clamp(closest / SETTINGS.HeartbeatRange, 0, 1)
			heart.Volume = SETTINGS.HeartbeatVolume * intensity
			heart.PlaybackSpeed = SETTINGS.HeartbeatPitch[1]
				+ (SETTINGS.HeartbeatPitch[2] - SETTINGS.HeartbeatPitch[1]) * intensity
			if not heart.IsPlaying then
				heart:Play()
			end
		end
	end)
end

--[[
	Exit proximity radar.

	Beeps faster the closer you are, like a metal detector. The interval is
	interpolated on a curve rather than linearly, so most of the acceleration
	happens in the last stretch — a beep rate that changes evenly over 220 studs
	is not something anyone can read, whereas one that suddenly quickens as you
	round the right corner is unmistakable.
]]
local function startExitRadar(parent: Instance)
	local escape = Config.Escape
	if escape.BeepId == "" then
		return
	end

	local beep = newSound("ExitRadar", escape.BeepId, parent)
	if not beep then
		return
	end
	beep.Volume = escape.BeepVolume

	local player = Players.LocalPlayer

	task.spawn(function()
		while true do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local exitFolder = workspace:FindFirstChild("Exit")
			local pad = exitFolder and exitFolder:FindFirstChild("ExitPad")

			if not root or not root:IsA("BasePart") or not pad or not pad:IsA("BasePart") then
				task.wait(0.5)
				continue
			end

			local distance = (pad.Position - root.Position).Magnitude
			if distance > escape.BeepRange then
				task.wait(0.5)
				continue
			end

			-- Squared so the quickening is concentrated near the exit.
			local closeness = 1 - math.clamp(distance / escape.BeepRange, 0, 1)
			local far, near = escape.BeepInterval[1], escape.BeepInterval[2]
			local interval = far + (near - far) * (closeness * closeness)

			beep.PlaybackSpeed = 1 + closeness * 0.6
			beep.Volume = escape.BeepVolume * (0.5 + 0.5 * closeness)
			beep:Play()
			task.wait(interval)
		end
	end)
end

function Ambience.start()
	-- Parented to SoundService so it's non-positional: the score follows the
	-- player rather than coming from a point in the level.
	local folder = Instance.new("Folder")
	folder.Name = "Ambience"
	folder.Parent = SoundService

	if SETTINGS.MusicId ~= "" then
		playMusicTrack(folder)
	else
		startDroneBed(folder)
	end

	startStingers(folder)
	startHeartbeat(folder)
	startExitRadar(folder)
end

return Ambience
