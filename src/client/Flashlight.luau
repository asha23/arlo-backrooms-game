--!strict
--[[
	A head-mounted spotlight toggled with F, with a battery that drains while on.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local SETTINGS = Config.Flashlight

local Flashlight = {}
Flashlight.__index = Flashlight

export type Flashlight = typeof(setmetatable(
	{} :: {
		enabled: boolean,
		battery: number,
		_light: SpotLight?,
	},
	Flashlight
))

function Flashlight.new(): Flashlight
	local self = setmetatable({
		enabled = false,
		battery = SETTINGS.MaxBattery,
		_light = nil,
	}, Flashlight)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.F then
			return
		end
		self:toggle()
	end)

	return self
end

--- Re-parents the light to the new character's head. Call on every respawn.
function Flashlight.attach(self: Flashlight, character: Model)
	local head = character:WaitForChild("Head", 10) :: BasePart?
	if not head then
		return
	end

	local light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Face = Enum.NormalId.Front
	light.Range = SETTINGS.Range
	light.Angle = SETTINGS.Angle
	light.Brightness = SETTINGS.Brightness
	light.Shadows = true
	light.Enabled = self.enabled and self.battery > 0
	light.Parent = head

	self._light = light
end

function Flashlight.toggle(self: Flashlight)
	if self.battery <= 0 then
		return
	end
	self.enabled = not self.enabled
	if self._light then
		self._light.Enabled = self.enabled
	end
end

function Flashlight.update(self: Flashlight, deltaTime: number)
	if not self.enabled then
		return
	end
	self.battery = math.max(0, self.battery - SETTINGS.BatteryDrain * deltaTime)
	if self.battery <= 0 then
		self.enabled = false
		if self._light then
			self._light.Enabled = false
		end
	end
end

return Flashlight
