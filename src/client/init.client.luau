--!strict
--[[
	Client entry point. Owns the per-frame loop that drives sprint, flashlight,
	weapons, score and the HUD, and re-attaches them whenever the character
	respawns.

	Ordering matters here. Anything that can yield — waiting on a character
	part, waiting on a remote — must not sit between two pieces of setup, or a
	single slow wait silently kills everything after it. Setup that never yields
	runs first, and per-character work is pushed onto its own thread.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local Ambience = require(script.Ambience)
local CameraController = require(script.CameraController)
local CoreUi = require(script.CoreUi)
local Flashlight = require(script.Flashlight)
local Hud = require(script.Hud)
local LightFlicker = require(script.LightFlicker)
local LightStreaming = require(script.LightStreaming)
local Minimap = require(script.Minimap)
local Recoil = require(script.Recoil)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local Sprint = require(script.Sprint)
local TouchControls = require(script.TouchControls)
local WeaponController = require(script.WeaponController)

local player = Players.LocalPlayer

-- Non-yielding setup first.
CoreUi.start()
CameraController.start()
Recoil.start()

local flashlight = Flashlight.new()
local sprint = Sprint.new()
local hud = Hud.new()
local weapons = WeaponController.new(hud:hitmarker())

TouchControls.start({
	onFireDown = function()
		weapons:setTrigger(true)
	end,
	onFireUp = function()
		weapons:setTrigger(false)
	end,
	onReload = function()
		weapons:requestReload()
	end,
	onSprintChanged = function(active)
		sprint.requested = active
	end,
	onFlashlight = function()
		flashlight:toggle()
	end,
})

Ambience.start()
Minimap.start()
LightStreaming.start()
LightFlicker.start()

--- Runs on its own thread: `attach` waits on character parts that may not exist yet.
local function onCharacterAdded(character: Model)
	task.spawn(function()
		flashlight:attach(character)
		sprint:attach(character)
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

-- Movement stays locked until the countdown says otherwise. Starting locked
-- means a client that somehow never receives the message can't run around
-- during a countdown that hasn't finished.
sprint.locked = true

Remotes.ScoreChanged().OnClientEvent:Connect(function(score, kills, headshots, cash, escapes)
	hud:setScore(score, kills, headshots, cash, escapes)
end)

Remotes.Escaped().OnClientEvent:Connect(function(bonusScore, bonusCash)
	hud:showEscape(bonusScore, bonusCash)
end)

Remotes.Countdown().OnClientEvent:Connect(function(text, unlocked)
	hud:setCountdown(text)
	hud:setDeathPrompt(nil)
	sprint.locked = not unlocked
end)

--[[
	Death screen. Any fire button requests the respawn, which is the button the
	player's hand is already on — asking them to find a different key at the
	moment they died is friction for no reason.
]]
local awaitingRespawn = false

Remotes.Died().OnClientEvent:Connect(function()
	awaitingRespawn = true
	sprint.locked = true
	hud:setDeathPrompt(Config.Respawn.PromptText)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not awaitingRespawn or processed then
		return
	end
	local isFire = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.MouseButton3
		or input.UserInputType == Enum.UserInputType.Touch
	if not isFire then
		return
	end
	awaitingRespawn = false
	hud:setDeathPrompt(nil)
	Remotes.RequestRespawn():FireServer()
end)

Remotes.HitConfirmed().OnClientEvent:Connect(function(_position, isHeadshot, _killed)
	if isHeadshot then
		hud:flashHeadshot()
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
	sprint:update(deltaTime)
	flashlight:update(deltaTime)
	weapons:update()

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local health = if humanoid then humanoid.Health else 0
	local maxHealth = if humanoid then humanoid.MaxHealth else 100

	hud:update(health, maxHealth, flashlight.battery, sprint.stamina)
	hud:setAmmoText(weapons:ammoText())
end)

print("[Client] ready — WASD move, Shift sprint, F flashlight, any mouse button fires, R reload")
