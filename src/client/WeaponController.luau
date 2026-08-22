--!strict
--[[
	Turns input into fire requests and draws the feedback (tracers, impacts,
	hitmarker). Deliberately owns no authority: it never decides whether a shot
	landed, only what the player sees. Ammo counts come from the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local WeaponController = {}
WeaponController.__index = WeaponController

export type WeaponController = typeof(setmetatable(
	{} :: {
		weaponId: string?,
		magazine: number,
		reserve: number,
		reloading: boolean,
		_triggerHeld: boolean,
		_lastFire: number,
		_hitmarker: Frame?,
	},
	WeaponController
))

--- Any mouse button fires — left, right or middle. Right-click doesn't need to
--- rotate the camera because we're locked to first person.
local FIRE_BUTTONS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

local function tracer(from: Vector3, to: Vector3)
	local distance = (to - from).Magnitude
	if distance < 0.5 then
		return
	end

	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 226, 150)
	beam.Size = Vector3.new(0.08, 0.08, distance)
	beam.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
	beam.Transparency = 0.25
	beam.Parent = workspace
	Debris:AddItem(beam, 0.08)
end

local function impact(position: Vector3)
	local spark = Instance.new("Part")
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.Material = Enum.Material.Neon
	spark.Color = Color3.fromRGB(255, 200, 120)
	spark.Size = Vector3.new(0.3, 0.3, 0.3)
	spark.CFrame = CFrame.new(position)
	spark.Parent = workspace
	Debris:AddItem(spark, 0.12)
end

--- The tool the player is holding, if it's one of our weapons.
local function equippedWeaponId(): string?
	local character = player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local idTag = tool and tool:FindFirstChild("WeaponId") :: StringValue?
	return if idTag then idTag.Value else nil
end

function WeaponController.new(hitmarker: Frame?): WeaponController
	local self = setmetatable({
		weaponId = nil,
		magazine = 0,
		reserve = 0,
		reloading = false,
		_triggerHeld = false,
		_lastFire = 0,
		_hitmarker = hitmarker,
	}, WeaponController)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if FIRE_BUTTONS[input.UserInputType] then
			self:setTrigger(true)
		elseif input.KeyCode == Enum.KeyCode.R then
			self:requestReload()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if FIRE_BUTTONS[input.UserInputType] then
			self:setTrigger(false)
		end
	end)

	Remotes.AmmoChanged().OnClientEvent:Connect(function(weaponId, magazine, reserve, reloading)
		-- Only track the weapon actually in hand.
		if weaponId ~= equippedWeaponId() then
			return
		end
		self.weaponId = weaponId
		self.magazine = magazine
		self.reserve = reserve
		self.reloading = reloading
	end)

	Remotes.ShotFired().OnClientEvent:Connect(function(_shooter, from, to)
		tracer(from, to)
		impact(to)
	end)

	Remotes.HitConfirmed().OnClientEvent:Connect(function(_position, isHeadshot, killed)
		self:flashHitmarker(isHeadshot or killed)
	end)

	return self
end

--[[
	Trigger state, driven by whichever input source the player is using — mouse
	button on desktop, on-screen button on touch. Keeping this a method rather
	than a raw field is what lets both coexist without either knowing about the
	other.
]]
function WeaponController.setTrigger(self: WeaponController, held: boolean)
	self._triggerHeld = held
	if held then
		self:tryFire()
	end
end

function WeaponController.requestReload(_self: WeaponController)
	Remotes.ReloadWeapon():FireServer()
end

function WeaponController.flashHitmarker(self: WeaponController, strong: boolean)
	local marker = self._hitmarker
	if not marker then
		return
	end
	marker.BackgroundColor3 = if strong
		then Color3.fromRGB(255, 90, 80)
		else Color3.fromRGB(255, 255, 255)
	marker.Visible = true
	task.delay(0.12, function()
		marker.Visible = false
	end)
end

function WeaponController.tryFire(self: WeaponController)
	local weaponId = equippedWeaponId()
	if not weaponId then
		return
	end
	local stats = WeaponConfig.Weapons[weaponId]
	if not stats then
		return
	end

	local now = os.clock()
	if now - self._lastFire < 1 / stats.FireRate then
		return
	end
	if self.reloading or self.magazine <= 0 then
		return
	end
	self._lastFire = now

	-- Aim from the camera, which is what the player is actually pointing at.
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector.Unit
	Remotes.FireWeapon():FireServer(origin, direction)
end

--- Drives automatic fire; called every frame from the main loop.
function WeaponController.update(self: WeaponController)
	if not self._triggerHeld then
		return
	end
	local weaponId = equippedWeaponId()
	local stats = weaponId and WeaponConfig.Weapons[weaponId]
	if stats and stats.Automatic then
		self:tryFire()
	end
end

--- Text for the ammo readout, or nil when unarmed.
function WeaponController.ammoText(self: WeaponController): string?
	local weaponId = equippedWeaponId()
	if not weaponId then
		return nil
	end
	local stats = WeaponConfig.Weapons[weaponId]
	if self.reloading then
		return `{stats.Name}  ...reloading`
	end
	return `{stats.Name}  {self.magazine} / {self.reserve}`
end

return WeaponController
