--!strict
--[[
	Puts the player in a first-person, mouse-locked camera.

	Roblox's default camera is a third-person orbit where the mouse only turns
	you while right-drag is held — unusable for aiming. `LockFirstPerson` pins
	the cursor to the centre of the screen and turns the character with raw
	mouse movement, so the crosshair always points where you're aiming.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local SETTINGS = Config.Camera

local player = Players.LocalPlayer

local CameraController = {}

local function applyCameraMode()
	if SETTINGS.FirstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 18
	end
end

function CameraController.start()
	UserInputService.MouseDeltaSensitivity = SETTINGS.Sensitivity
	applyCameraMode()

	-- CameraMode survives respawns, but a dying character can reset the zoom
	-- clamps, so re-assert them each time.
	player.CharacterAdded:Connect(applyCameraMode)

	-- On touch devices Roblox supplies its own drag-to-look camera, so we leave
	-- the mouse lock alone there.
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
	end
end

--- Lets the settings menu (or a console command) flip perspective at runtime.
function CameraController.setFirstPerson(enabled: boolean)
	SETTINGS.FirstPerson = enabled
	applyCameraMode()
end

return CameraController
