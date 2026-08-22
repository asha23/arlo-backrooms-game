--!strict
--[[
	Turns input into fire requests and draws the feedback (tracers, impacts,
	hitmarker). Deliberately owns no authority: it never decides whether a shot
	landed, only what the player sees. Ammo counts come from the server.
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.Config)
local Recoil = require(script.Parent.Recoil)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local WeaponController = {}
WeaponController.__index = WeaponController

type AmmoState = { magazine: number, reserve: number, reloading: boolean }

export type WeaponController = typeof(setmetatable(
	{} :: {
		-- Ammo for every weapon owned, keyed by weapon id.
		--
		-- This used to be a single set of fields for "the equipped weapon",
		-- updated only when the incoming weapon id matched what was in hand.
		-- The server pushes ammo when a weapon is GRANTED, which happens before
		-- it is equipped, so that update was always discarded and the local
		-- magazine sat at zero — which the fire check then read as "empty", so
		-- no shot was ever requested. Keyed state has no such window.
		ammo: { [string]: AmmoState },
		_triggerHeld: boolean,
		_lastFire: number,
		_lastDryFire: number,
		-- Rounds left in the current burst, and when the forced pause ends.
		_burstRemaining: number,
		_burstReadyAt: number,
		_hitmarker: Frame?,
		_dryFire: Sound,
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

--- The weapon id a given player currently has equipped, if any.
local function weaponIdOf(subject: Player): string?
	local character = subject.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local idTag = tool and tool:FindFirstChild("WeaponId") :: StringValue?
	return if idTag then idTag.Value else nil
end

--- World position of the equipped weapon's muzzle attachment.
local function muzzlePosition(subject: Player): Vector3?
	local character = subject.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local handle = tool and tool:FindFirstChild("Handle") :: BasePart?
	if not handle then
		return nil
	end
	local muzzle = handle:FindFirstChild("Muzzle") :: Attachment?
	return if muzzle then muzzle.WorldPosition else handle.Position
end

--[[
	Gunfire, from a pool of one reusable Sound per weapon.

	Deliberately NOT one Sound instance per shot. If an id ever fails to
	resolve, Roblox retries the fetch for every instance created — ten rounds a
	second becomes ten hanging HTTP requests a second, which is what previously
	took Studio down. Three pooled sounds means a bad id costs three failed
	fetches in total, whatever happens afterwards.

	The trade-off is that a sound restarts rather than overlapping itself on
	rapid fire, which for a machine gun is close to what you want anyway.
]]
local firePool: { [string]: Sound } = {}
local fireEmitter: Part? = nil

local function playFireSound(weaponId: string, position: Vector3)
	local stats = WeaponConfig.Weapons[weaponId]
	if not stats or not Config.Audio.Enabled or Config.WeaponAudio.FireSoundId == "" then
		return
	end

	-- One shared emitter part, moved to each muzzle, so the sound stays
	-- positional without churning instances.
	local existing = fireEmitter
	local emitter: Part
	if existing and existing.Parent then
		emitter = existing
	else
		emitter = Instance.new("Part")
		emitter.Name = "FireEmitter"
		emitter.Anchored = true
		emitter.CanCollide = false
		emitter.CanQuery = false
		emitter.CanTouch = false
		emitter.Transparency = 1
		emitter.Size = Vector3.one
		emitter.Parent = workspace
		fireEmitter = emitter
		-- Pooled sounds were parented to the old emitter; start fresh.
		table.clear(firePool)
	end
	emitter.CFrame = CFrame.new(position)

	local sound = firePool[weaponId]
	if not sound then
		local created = SoundKit.create(emitter, {
			Id = Config.WeaponAudio.FireSoundId,
			Pitch = stats.FireSound.Pitch,
			Volume = stats.FireSound.Volume,
			Range = stats.FireSound.Range,
			Reverb = stats.FireSound.Reverb,
		})
		if not created then
			return
		end
		created.Name = `Fire_{weaponId}`
		firePool[weaponId] = created
		sound = created
	end

	-- Slight per-shot pitch variation so repeated fire doesn't sound looped.
	sound.PlaybackSpeed = stats.FireSound.Pitch * (0.94 + math.random() * 0.12)
	sound.TimePosition = 0
	sound:Play()
end

--- A brief bright flare at the muzzle.
local function muzzleFlash(position: Vector3)
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 231, 168)
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.one * 0.9
	flash.CFrame = CFrame.new(position)
	flash.Parent = workspace

	local light = Instance.new("PointLight")
	light.Brightness = 2.2
	light.Range = 14
	light.Color = Color3.fromRGB(255, 226, 160)
	light.Parent = flash

	Debris:AddItem(flash, 0.06)
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
	--[[
		See Config.Audio. This Sound is created once and reused, but it still
		must not exist with an id that cannot resolve — Roblox would retry the
		fetch on every Play().
	]]
	local audio = Config.WeaponAudio
	local dryFire = Instance.new("Sound")
	if Config.Audio.Enabled and audio.DryFireId ~= "" then
		dryFire.Name = "DryFire"
		dryFire.SoundId = audio.DryFireId
		dryFire.PlaybackSpeed = audio.DryFirePitch
		dryFire.Volume = audio.DryFireVolume
		dryFire.Parent = SoundService
	end

	local self = setmetatable({
		ammo = {},
		_triggerHeld = false,
		_lastFire = 0,
		_lastDryFire = 0,
		_burstRemaining = 0,
		_burstReadyAt = 0,
		_hitmarker = hitmarker,
		_dryFire = dryFire,
	}, WeaponController)

	--[[
		Two independent paths drive the trigger, because either one alone has a
		hole.

		Raw InputBegan is the only way to catch the middle and right buttons,
		but it can be swallowed: `gameProcessedEvent` is true whenever anything
		in the UI layer claims the click, and a locked first-person cursor sits
		permanently over the centre of the screen. So mouse buttons here are
		deliberately NOT gated on `processed` — only keyboard input is, so that
		typing somewhere doesn't trigger a reload.

		Tool.Activated is Roblox's own "the player used the thing in their hand"
		signal. It survives cases raw input doesn't and covers touch and gamepad
		for free, but only reports the primary button.

		Double-firing isn't a risk: tryFire is rate-limited, so two triggers in
		the same frame produce one shot.
	]]
	UserInputService.InputBegan:Connect(function(input, processed)
		if FIRE_BUTTONS[input.UserInputType] then
			self:setTrigger(true)
		elseif not processed and input.KeyCode == Enum.KeyCode.R then
			self:requestReload()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if FIRE_BUTTONS[input.UserInputType] then
			self:setTrigger(false)
		end
	end)

	-- Bind Tool.Activated/Deactivated on whatever weapon gets equipped.
	local function bindTool(tool: Tool)
		if not tool:FindFirstChild("WeaponId") then
			return
		end
		tool.Activated:Connect(function()
			self:setTrigger(true)
		end)
		tool.Deactivated:Connect(function()
			self:setTrigger(false)
		end)
	end

	local function watchCharacter(character: Model)
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				bindTool(child)
			end
		end
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				bindTool(child)
			end
		end)
	end

	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end

	Remotes.AmmoChanged().OnClientEvent:Connect(function(weaponId, magazine, reserve, reloading)
		self.ammo[weaponId] = {
			magazine = magazine,
			reserve = reserve,
			reloading = reloading,
		}
	end)

	Remotes.ShotFired().OnClientEvent:Connect(function(shooter, from, to)
		tracer(from, to)
		impact(to)

		--[[
			Sound and flash come from the shooter's muzzle, not from `from` —
			`from` is the camera position, which for the local player is inside
			their own head. Falling back to `from` covers a shooter whose tool
			hasn't replicated yet.
		]]
		local muzzle = muzzlePosition(shooter) or from
		local weaponId = weaponIdOf(shooter)
		if weaponId then
			playFireSound(weaponId, muzzle)
		end

		muzzleFlash(muzzle)
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
	if not held then
		return
	end

	local weaponId = equippedWeaponId()
	local stats = weaponId and WeaponConfig.Weapons[weaponId]
	if not stats then
		return
	end

	if stats.Mode == "Burst" then
		-- Start a burst, unless we're still in the forced pause after the last.
		if self._burstRemaining <= 0 and os.clock() >= self._burstReadyAt then
			self._burstRemaining = stats.BurstCount
		end
		return
	end

	-- Semi and Auto both fire immediately on the press; Auto then continues in
	-- update() while the trigger is held, Semi does not.
	self:tryFire()
end

function WeaponController.requestReload(_self: WeaponController)
	Remotes.ReloadWeapon():FireServer()
end

--- Click on an empty magazine, rate-limited so holding the trigger clicks once.
function WeaponController.playDryFire(self: WeaponController)
	local now = os.clock()
	if now - self._lastDryFire < Config.WeaponAudio.DryFireCooldown then
		return
	end
	self._lastDryFire = now
	-- Left unparented when audio is off or unconfigured; playing it would be a
	-- no-op, but not calling Play at all is clearer about the intent.
	if self._dryFire.Parent then
		self._dryFire:Play()
	end
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

--- Returns true if a shot was actually requested.
function WeaponController.tryFire(self: WeaponController): boolean
	local weaponId = equippedWeaponId()
	if not weaponId then
		return false
	end
	local stats = WeaponConfig.Weapons[weaponId]
	if not stats then
		return false
	end

	local now = os.clock()
	if now - self._lastFire < 1 / stats.FireRate then
		return false
	end

	--[[
		The local ammo check is an optimisation to avoid spamming the server,
		not a rule. If we have no state for this weapon yet the request goes
		anyway and the server decides — a client that hasn't heard about its
		own ammo must never be locked out of firing.
	]]
	local state = self.ammo[weaponId]
	if state and state.reloading then
		return false
	end
	if state and state.magazine <= 0 then
		self:playDryFire()
		-- An empty gun ends the burst; it shouldn't resume when reloaded.
		self._burstRemaining = 0
		return false
	end
	self._lastFire = now

	-- Aim from the camera, which is what the player is actually pointing at.
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector.Unit
	Remotes.FireWeapon():FireServer(origin, direction)
	Recoil.kick(stats.Recoil)
	return true
end

--- Drives automatic and burst fire; called every frame from the main loop.
function WeaponController.update(self: WeaponController)
	local weaponId = equippedWeaponId()
	local stats = weaponId and WeaponConfig.Weapons[weaponId]
	if not stats then
		return
	end

	if stats.Mode == "Burst" then
		-- A burst runs to completion on its own, whether or not the trigger is
		-- still held — that's what makes it read as a burst rather than as a
		-- very short spell of automatic fire.
		if self._burstRemaining > 0 then
			if self:tryFire() then
				self._burstRemaining -= 1
				if self._burstRemaining <= 0 then
					self._burstReadyAt = os.clock() + stats.BurstCooldown
				end
			end
		elseif self._triggerHeld and os.clock() >= self._burstReadyAt then
			self._burstRemaining = stats.BurstCount
		end
		return
	end

	if stats.Mode == "Auto" and self._triggerHeld then
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
	local state = self.ammo[weaponId]
	if not state then
		return `{stats.Name}  --`
	end
	if state.reloading then
		return `{stats.Name}  ...reloading`
	end
	return `{stats.Name}  {state.magazine} / {state.reserve}`
end

return WeaponController
