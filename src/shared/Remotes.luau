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
	return ReplicatedStorage:WaitForChild("Remotes") :: Folder
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
	return parent:WaitForChild(name) :: any
end

local Remotes = {}

-- Client -> Server: report the player's current sanity so the server can react
-- (spawn events, kill the player at zero, etc).
function Remotes.SanityChanged(): RemoteEvent
	return get("SanityChanged", "RemoteEvent")
end

-- Server -> Client: the level finished generating; safe to start the HUD.
function Remotes.LevelReady(): RemoteEvent
	return get("LevelReady", "RemoteEvent")
end

return Remotes
