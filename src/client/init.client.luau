--!strict
--[[
	Client entry point. Owns the per-frame loop that drives sprint, flashlight,
	sanity and the HUD, and re-attaches them whenever the character respawns.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraController = require(script.CameraController)
local Flashlight = require(script.Flashlight)
local Hud = require(script.Hud)
local LightFlicker = require(script.LightFlicker)
local Sanity = require(script.Sanity)
local Sprint = require(script.Sprint)
local TouchControls = require(script.TouchControls)
local WeaponController = require(script.WeaponController)

local player = Players.LocalPlayer

local flashlight = Flashlight.new()
local sprint = Sprint.new()
local sanity = Sanity.new()
local hud = Hud.new()
local weapons = WeaponController.new(hud:hitmarker())

local function onCharacterAdded(character: Model)
	flashlight:attach(character)
	sprint:attach(character)
	sanity:reset()
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

CameraController.start()
LightFlicker.start()

-- Touch devices get on-screen action buttons wired to the same methods the
-- keyboard and mouse bindings use.
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

RunService.RenderStepped:Connect(function(deltaTime)
	sprint:update(deltaTime)
	flashlight:update(deltaTime)
	sanity:update(deltaTime, player.Character, flashlight.enabled)
	weapons:update()
	hud:update(sanity.value, flashlight.battery, sprint.stamina)
	hud:setAmmoText(weapons:ammoText())
end)

print("[Client] ready — WASD move, Shift sprint, F flashlight, LMB fire, R reload")
