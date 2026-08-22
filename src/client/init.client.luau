--!strict
--[[
	Client entry point. Owns the per-frame loop that drives sprint, flashlight,
	sanity and the HUD, and re-attaches them whenever the character respawns.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Flashlight = require(script.Flashlight)
local Hud = require(script.Hud)
local LightFlicker = require(script.LightFlicker)
local Sanity = require(script.Sanity)
local Sprint = require(script.Sprint)

local player = Players.LocalPlayer

local flashlight = Flashlight.new()
local sprint = Sprint.new()
local sanity = Sanity.new()
local hud = Hud.new()

local function onCharacterAdded(character: Model)
	flashlight:attach(character)
	sprint:attach(character)
	sanity:reset()
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

LightFlicker.start()

RunService.RenderStepped:Connect(function(deltaTime)
	sprint:update(deltaTime)
	flashlight:update(deltaTime)
	sanity:update(deltaTime, player.Character, flashlight.enabled)
	hud:update(sanity.value, flashlight.battery, sprint.stamina)
end)

print("[Client] ready — WASD to move, Shift to sprint, F for flashlight")
