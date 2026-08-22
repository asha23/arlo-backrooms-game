--!strict
--[[
	Client half of the flashlight.

	Deliberately thin: the server owns whether you have a torch, whether it is
	lit and how much charge is left, because the entities react to all three. A
	client that decided when its own torch was on would be a client that decided
	when the monsters ran away.

	This just sends the toggle and mirrors what comes back for the HUD.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SETTINGS = Config.Flashlight

local Flashlight = {}
Flashlight.__index = Flashlight

export type Flashlight = typeof(setmetatable(
	{} :: {
		held: boolean,
		enabled: boolean,
		battery: number,
		maxBattery: number,
	},
	Flashlight
))

function Flashlight.new(): Flashlight
	local self = setmetatable({
		held = false,
		enabled = false,
		battery = 0,
		maxBattery = SETTINGS.MaxBattery,
	}, Flashlight)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.F then
			return
		end
		self:toggle()
	end)

	Remotes.FlashlightState().OnClientEvent:Connect(function(held, enabled, battery, maxBattery)
		self.held = held
		self.enabled = enabled
		self.battery = battery
		self.maxBattery = maxBattery
	end)

	return self
end

--- Asks the server to flip the torch. Ignored if you don't have one.
function Flashlight.toggle(self: Flashlight)
	if not self.held then
		return
	end
	Remotes.ToggleFlashlight():FireServer()
end

--- Battery as a fraction, for the HUD bar.
function Flashlight.fraction(self: Flashlight): number
	if self.maxBattery <= 0 then
		return 0
	end
	return math.clamp(self.battery / self.maxBattery, 0, 1)
end

--- True when the player should be warned. Only while it's actually lit — a
--- warning about a torch you aren't using is noise.
function Flashlight.isLow(self: Flashlight): boolean
	return self.held and self.enabled and self:fraction() <= SETTINGS.LowBatteryAt
end

return Flashlight
