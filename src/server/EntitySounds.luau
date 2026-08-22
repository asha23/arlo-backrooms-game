--!strict
--[[
	Audio for the hostiles.

	Sounds are parented to the entity's torso so Roblox spatialises them: you
	hear a wanderer round a corner before you see it, and the direction is real
	rather than a guess. Every sound gets a reverb effect, because a dry sample
	in a big empty corridor sounds like a menu click rather than a thing in a
	room with you.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local SETTINGS = Config.Entity

export type SoundSpec = {
	Id: string,
	Pitch: number,
	Volume: number,
	Range: number,
}

local EntitySounds = {}
EntitySounds.__index = EntitySounds

export type EntitySounds = typeof(setmetatable(
	{} :: {
		drone: Sound?,
		idle: Sound?,
		alert: Sound?,
		chase: Sound?,
		_emitter: BasePart,
		_pitchScale: number,
		_wasChasing: boolean,
		_nextIdle: number,
		_nextChase: number,
	},
	EntitySounds
))

local function build(
	parent: BasePart,
	name: string,
	spec: SoundSpec,
	looped: boolean,
	pitchScale: number?
): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume
	sound.PlaybackSpeed = spec.Pitch * (pitchScale or 1)
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = spec.Range
	sound.Parent = parent

	local reverb = Instance.new("ReverbSoundEffect")
	reverb.DecayTime = 2.6
	reverb.Density = 0.9
	reverb.Diffusion = 0.8
	reverb.DryLevel = -3
	reverb.WetLevel = 1
	reverb.Parent = sound

	return sound
end

local rng = Random.new()

local function randomIn(range: { number }): number
	return rng:NextNumber(range[1], range[2])
end

--- Attaches the full sound set to an entity. `torso` is the emitter.
function EntitySounds.attach(torso: BasePart, variantId: string?): EntitySounds
	local specs = SETTINGS.Sounds
	-- Bigger things sound lower. Slender is the tallest, so it gets dragged
	-- down further than the others.
	local pitchScale = if variantId == "Slender" then 0.78 else 1

	local self = setmetatable({
		drone = build(torso, "Drone", specs.Drone, true, pitchScale),
		idle = build(torso, "Idle", specs.Idle, false, pitchScale),
		alert = build(torso, "Alert", specs.Alert, false, pitchScale),
		chase = build(torso, "Chase", specs.Chase, false, pitchScale),
		_emitter = torso,
		_pitchScale = pitchScale,
		_wasChasing = false,
		_nextIdle = randomIn(SETTINGS.IdleSoundGap),
		_nextChase = 0,
	}, EntitySounds)

	if self.drone then
		self.drone:Play()
	end

	return self
end

--[[
	Called each AI tick. `chasing` drives the transition sting: the alert only
	fires on the edge, when it goes from not-chasing to chasing, rather than
	every tick it can see you.
]]
function EntitySounds.update(self: EntitySounds, deltaTime: number, chasing: boolean)
	if chasing and not self._wasChasing then
		if self.alert then
			self.alert:Play()
		end
		self._nextChase = randomIn(SETTINGS.ChaseSoundGap)
	end
	self._wasChasing = chasing

	if chasing then
		self._nextChase -= deltaTime
		if self._nextChase <= 0 then
			self._nextChase = randomIn(SETTINGS.ChaseSoundGap)
			if self.chase then
				self.chase:Play()
			end
		end
		return
	end

	self._nextIdle -= deltaTime
	if self._nextIdle <= 0 then
		self._nextIdle = randomIn(SETTINGS.IdleSoundGap)
		if self.idle then
			-- Vary the pitch a little so repeats don't read as the same clip.
			self.idle.PlaybackSpeed = SETTINGS.Sounds.Idle.Pitch * rng:NextNumber(0.9, 1.15)
			self.idle:Play()
		end
	end
end

--[[
	Stops everything and screams.

	Each layer is its own Sound so they can slide independently, and each is
	parented to the emitter for spatialisation. They're handed to Debris rather
	than tracked, because the entity's body is destroyed shortly after death and
	the scream has to outlive it.
]]
function EntitySounds.playDeath(self: EntitySounds)
	for _, sound in { self.drone, self.idle, self.alert, self.chase } do
		if sound then
			sound:Stop()
		end
	end

	local scream = SETTINGS.DeathScream
	local emitter = self._emitter

	for index, layer in scream.Layers do
		task.delay(layer.Delay, function()
			if not emitter.Parent then
				return
			end

			local sound = Instance.new("Sound")
			sound.Name = `Scream{index}`
			sound.SoundId = scream.Id
			sound.Volume = layer.Volume
			sound.PlaybackSpeed = layer.StartPitch * self._pitchScale
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = 10
			sound.RollOffMaxDistance = scream.Range
			sound.Parent = emitter

			local reverb = Instance.new("ReverbSoundEffect")
			reverb.DecayTime = 5
			reverb.Density = 1
			reverb.Diffusion = 0.9
			reverb.DryLevel = -1
			reverb.WetLevel = 3
			reverb.Parent = sound

			-- A distortion that grows as the pitch falls, so the tail stops
			-- sounding like a voice at all.
			local distortion = Instance.new("DistortionSoundEffect")
			distortion.Level = 0.35
			distortion.Parent = sound

			sound:Play()

			local slide =
				TweenInfo.new(scream.SlideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(sound, slide, {
				PlaybackSpeed = layer.EndPitch * self._pitchScale,
				Volume = 0,
			}):Play()
			TweenService:Create(distortion, slide, { Level = 0.85 }):Play()

			Debris:AddItem(sound, scream.SlideTime + 0.5)
		end)
	end
end

return EntitySounds
