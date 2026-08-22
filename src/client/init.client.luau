--!strict
--[[
	Client entry point. Owns the per-frame loop that drives sprint, flashlight,
	sanity, weapons and the HUD, and re-attaches them whenever the character
	respawns.

	Ordering matters here. Anything that can yield — waiting on a character
	part, waiting on a remote — must not sit between two pieces of setup, or a
	single slow wait silently kills everything after it. Setup that never yields
	runs first, and per-character work is pushed onto its own thread.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Ambience = require(script.Ambience)
local CameraController = require(script.CameraController)
local CoreUi = require(script.CoreUi)
local Flashlight = require(script.Flashlight)
local Hud = require(script.Hud)
local LightFlicker = require(script.LightFlicker)
local Recoil = require(script.Recoil)
local Sanity = require(script.Sanity)
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
local sanity = Sanity.new()
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
LightFlicker.start()

--- Runs on its own thread: `attach` waits on character parts that may not exist yet.
local function onCharacterAdded(character: Model)
	task.spawn(function()
		flashlight:attach(character)
		sprint:attach(character)
		sanity:reset()
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

RunService.RenderStepped:Connect(function(deltaTime)
	sprint:update(deltaTime)
	flashlight:update(deltaTime)
	sanity:update(deltaTime, player.Character, flashlight.enabled)
	weapons:update()
	hud:update(sanity.value, flashlight.battery, sprint.stamina)
	hud:setAmmoText(weapons:ammoText())
end)

print("[Client] ready — WASD move, Shift sprint, F flashlight, any mouse button fires, R reload")
