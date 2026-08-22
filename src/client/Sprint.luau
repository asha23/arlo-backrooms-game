--!strict
--[[
	Hold Shift (or the on-screen sprint button) to sprint until stamina runs out. Stamina regenerates whenever
	you're not sprinting, so the pacing is "run between rooms, not through them".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local SETTINGS = Config.Player

local Sprint = {}
Sprint.__index = Sprint

export type Sprint = typeof(setmetatable(
	{} :: {
		stamina: number,
		sprinting: boolean,
		-- Set by the on-screen sprint button on touch devices; ORed with Shift
		-- so both input sources work on a device that has both.
		requested: boolean,
		-- Set while the match countdown is running. Sprint writes WalkSpeed
		-- every frame, so a server-side freeze alone would be overwritten
		-- immediately — the lock has to live here too.
		locked: boolean,
		_humanoid: Humanoid?,
	},
	Sprint
))

function Sprint.new(): Sprint
	return setmetatable({
		stamina = SETTINGS.MaxStamina,
		sprinting = false,
		requested = false,
		locked = false,
		_humanoid = nil,
	}, Sprint)
end

function Sprint.attach(self: Sprint, character: Model)
	self._humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
end

local function isHoldingShift(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

function Sprint.update(self: Sprint, deltaTime: number)
	local humanoid = self._humanoid
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local held = isHoldingShift() or self.requested
	if self.locked then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		self.sprinting = false
		return
	end

	local wantsToSprint = held and humanoid.MoveDirection.Magnitude > 0
	if self.sprinting then
		-- Keep sprinting until stamina is fully spent.
		self.sprinting = wantsToSprint and self.stamina > 0
	else
		self.sprinting = wantsToSprint and self.stamina >= SETTINGS.SprintMinStamina
	end

	if self.sprinting then
		self.stamina = math.max(0, self.stamina - SETTINGS.StaminaDrain * deltaTime)
	else
		self.stamina =
			math.min(SETTINGS.MaxStamina, self.stamina + SETTINGS.StaminaRegen * deltaTime)
	end

	humanoid.WalkSpeed = if self.sprinting then SETTINGS.SprintSpeed else SETTINGS.WalkSpeed
end

return Sprint
