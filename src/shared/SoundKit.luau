--!strict
--[[
	One-shot sound helper.

	Playing a sound in Roblox means creating an instance, configuring rolloff,
	parenting it to something spatial, playing it and then cleaning it up. Doing
	that inline in five different modules is how the settings drift apart, so it
	lives here once.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Spec = {
	Id: string,
	Pitch: number?,
	Volume: number?,
	-- Rolloff distance in studs. Omit for a non-positional sound.
	Range: number?,
	-- Reverb decay in seconds. Omit for a dry sound.
	Reverb: number?,
	-- Random pitch variation, as a +/- fraction. 0.1 means +/-10%.
	PitchJitter: number?,
}

local SoundKit = {}

local rng = Random.new()

--[[
	True when a sound may actually be created.

	A Sound with an unresolvable SoundId is not merely silent: Roblox tries to
	fetch it over HTTP, and a weapon firing a ten-round burst starts ten hanging
	requests in under a second. That is what previously crashed Studio, so this
	is a hard gate rather than a preference.
]]
local function playable(spec: Spec): boolean
	return Config.Audio.Enabled and spec.Id ~= nil and spec.Id ~= ""
end

--- Creates a configured, unplayed Sound, or nil if audio is off or unset.
function SoundKit.create(parent: Instance, spec: Spec): Sound?
	if not playable(spec) then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume or 1

	local pitch = spec.Pitch or 1
	if spec.PitchJitter then
		pitch *= 1 + rng:NextNumber(-spec.PitchJitter, spec.PitchJitter)
	end
	sound.PlaybackSpeed = pitch

	if spec.Range then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 8
		sound.RollOffMaxDistance = spec.Range
	end

	if spec.Reverb then
		local reverb = Instance.new("ReverbSoundEffect")
		reverb.DecayTime = spec.Reverb
		reverb.Density = 0.9
		reverb.Diffusion = 0.8
		reverb.DryLevel = -2
		reverb.WetLevel = 1
		reverb.Parent = sound
	end

	sound.Parent = parent
	return sound
end

--- Plays a sound once and cleans it up afterwards. No-op when audio is off.
function SoundKit.playOnce(parent: Instance, spec: Spec): Sound?
	local sound = SoundKit.create(parent, spec)
	if not sound then
		return nil
	end
	sound:Play()
	-- Debris rather than the Ended signal: Ended never fires if the parent is
	-- destroyed mid-playback, which would leak the instance.
	Debris:AddItem(sound, 8)
	return sound
end

return SoundKit
