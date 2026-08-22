--!strict
--[[
	Standing in the dark drains sanity; standing under a working light (or with
	the flashlight on) restores it. Hitting zero is fatal — the server enforces
	that when it receives the value.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SETTINGS = Config.Sanity

local Sanity = {}
Sanity.__index = Sanity

export type Sanity = typeof(setmetatable(
	{} :: {
		value: number,
		lit: boolean,
		_reportAccumulator: number,
		_lastReported: number,
	},
	Sanity
))

function Sanity.new(): Sanity
	return setmetatable({
		value = SETTINGS.Max,
		lit = true,
		_reportAccumulator = 0,
		_lastReported = SETTINGS.Max,
	}, Sanity)
end

--[[
	True if any ceiling light within LightRadius is burning at full brightness.

	The brightness test matters: flickering fixtures dim rather than switch off,
	so that no corner of the level is ever pitch black. Testing Enabled alone
	would mean a stuttering light still counted as safety.
]]
local function isNearWorkingLight(position: Vector3): boolean
	local radiusSquared = SETTINGS.LightRadius ^ 2
	for _, fixture in CollectionService:GetTagged("Fluorescent") do
		if not fixture:IsA("BasePart") then
			continue
		end
		local light = fixture:FindFirstChildOfClass("PointLight")
		if not light or not light.Enabled or light.Brightness < SETTINGS.LitBrightness then
			continue
		end
		if (fixture.Position - position).Magnitude ^ 2 <= radiusSquared then
			return true
		end
	end
	return false
end

function Sanity.update(self: Sanity, deltaTime: number, character: Model?, flashlightOn: boolean)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	self.lit = flashlightOn or isNearWorkingLight(root.Position)

	if self.lit then
		self.value = math.min(SETTINGS.Max, self.value + SETTINGS.RegenInLight * deltaTime)
	else
		self.value = math.max(0, self.value - SETTINGS.DrainInDark * deltaTime)
	end

	-- Throttle replication: the server only needs a coarse value, and zero.
	self._reportAccumulator += deltaTime
	local crossedZero = self.value <= 0 and self._lastReported > 0
	if crossedZero or self._reportAccumulator >= 1 then
		self._reportAccumulator = 0
		self._lastReported = self.value
		Remotes.SanityChanged():FireServer(self.value)
	end
end

function Sanity.reset(self: Sanity)
	self.value = SETTINGS.Max
	self._lastReported = SETTINGS.Max
end

return Sanity
