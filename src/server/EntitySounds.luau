--!strict
--[[
	Audio for the hostiles.

	Sounds are parented to the entity's torso so Roblox spatialises them: you
	hear a wanderer round a corner before you see it, and the direction is real
	rather than a guess. Every sound gets a reverb effect, because a dry sample
	in a big empty corridor sounds like a menu click rather than a thing in a
	room with you.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
		death: Sound?,
		_wasChasing: boolean,
		_nextIdle: number,
		_nextChase: number,
	},
	EntitySounds
))

local function build(parent: BasePart, name: string, spec: SoundSpec, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume
	sound.PlaybackSpeed = spec.Pitch
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
function EntitySounds.attach(torso: BasePart): EntitySounds
	local specs = SETTINGS.Sounds

	local self = setmetatable({
		drone = build(torso, "Drone", specs.Drone, true),
		idle = build(torso, "Idle", specs.Idle, false),
		alert = build(torso, "Alert", specs.Alert, false),
		chase = build(torso, "Chase", specs.Chase, false),
		death = build(torso, "Death", specs.Death, false),
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

--- Stops the loop and plays the death cry. The torso outlives the entity long
--- enough for the sound to finish.
function EntitySounds.playDeath(self: EntitySounds)
	if self.drone then
		self.drone:Stop()
	end
	if self.death then
		self.death:Play()
	end
end

return EntitySounds
