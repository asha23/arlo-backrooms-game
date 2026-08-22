--!strict
--[[
	Lazily creates (server) or waits for (client) the remote instances shared by
	both sides, so neither has to reach into ReplicatedStorage by hand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local function container(): Folder
	if IS_SERVER then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	-- Bounded wait: a missing folder is a bug worth shouting about, not
	-- something to hang the whole client script on.
	local folder = ReplicatedStorage:WaitForChild("Remotes", 10)
	assert(folder, "Remotes folder never replicated — did the server run Remotes.initialize()?")
	return folder :: Folder
end

local function get<T>(name: string, className: string): T
	local parent = container()
	if IS_SERVER then
		local existing = parent:FindFirstChild(name)
		if existing then
			return existing :: any
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = parent
		return remote :: any
	end
	local remote = parent:WaitForChild(name, 10)
	assert(remote, `Remote '{name}' never replicated — add it to Remotes.MANIFEST`)
	return remote :: any
end

--[[
	Every remote in the game, listed up front.

	The server MUST create all of these before any client asks for one. They
	used to be created lazily on first use, which meant a remote only fired
	during gameplay (a tracer, a hit) didn't exist at startup — so the client's
	WaitForChild blocked forever and every line after it in the client script
	never ran. Listing them here and calling `Remotes.initialize()` on the
	server makes that failure impossible to reintroduce.
]]
local MANIFEST: { [string]: string } = {
	LevelReady = "RemoteEvent",
	FireWeapon = "RemoteEvent",
	ReloadWeapon = "RemoteEvent",
	AmmoChanged = "RemoteEvent",
	ShotFired = "RemoteEvent",
	HitConfirmed = "RemoteEvent",
	ScoreChanged = "RemoteEvent",
	PlayerReady = "RemoteEvent",
	Countdown = "RemoteEvent",
	Died = "RemoteEvent",
	RequestRespawn = "RemoteEvent",
	Escaped = "RemoteEvent",
}

local Remotes = {}

--- Server-only. Creates every remote up front so no client can out-race one.
function Remotes.initialize()
	assert(IS_SERVER, "Remotes.initialize() must be called from the server")
	for name, className in MANIFEST do
		get(name, className)
	end
end

-- Server -> Client: the level finished generating; safe to start the HUD.
function Remotes.LevelReady(): RemoteEvent
	return get("LevelReady", "RemoteEvent")
end

-- Client -> Server: "I pulled the trigger, aiming down this ray." The server
-- re-does the raycast itself and decides what was hit; the client's ray is
-- treated as a request, never as a result.
function Remotes.FireWeapon(): RemoteEvent
	return get("FireWeapon", "RemoteEvent")
end

-- Client -> Server: request a reload of the currently equipped weapon.
function Remotes.ReloadWeapon(): RemoteEvent
	return get("ReloadWeapon", "RemoteEvent")
end

-- Server -> Client: authoritative ammo state for the equipped weapon.
function Remotes.AmmoChanged(): RemoteEvent
	return get("AmmoChanged", "RemoteEvent")
end

-- Server -> Client: a shot was fired somewhere; play the tracer and impact.
function Remotes.ShotFired(): RemoteEvent
	return get("ShotFired", "RemoteEvent")
end

-- Server -> Client: the local player damaged something (drives the hitmarker).
function Remotes.HitConfirmed(): RemoteEvent
	return get("HitConfirmed", "RemoteEvent")
end

-- Server -> Client: authoritative score, kills, headshots and cash.
function Remotes.ScoreChanged(): RemoteEvent
	return get("ScoreChanged", "RemoteEvent")
end

-- Client -> Server: "my loading screen has finished, I can see the level."
-- The match will not start until this arrives (or times out).
function Remotes.PlayerReady(): RemoteEvent
	return get("PlayerReady", "RemoteEvent")
end

-- Server -> Client: countdown text to show, and whether movement is unlocked.
function Remotes.Countdown(): RemoteEvent
	return get("Countdown", "RemoteEvent")
end

-- Server -> Client: you died; show the respawn prompt.
function Remotes.Died(): RemoteEvent
	return get("Died", "RemoteEvent")
end

-- Client -> Server: the player clicked to respawn.
function Remotes.RequestRespawn(): RemoteEvent
	return get("RequestRespawn", "RemoteEvent")
end

-- Server -> Client: you reached the exit.
function Remotes.Escaped(): RemoteEvent
	return get("Escaped", "RemoteEvent")
end

return Remotes
