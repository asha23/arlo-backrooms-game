--!strict
--[[
	Camera kick.

	Roblox's own camera scripts rewrite Camera.CFrame every frame, so anything
	that touches it earlier is simply discarded. This binds at
	RenderPriority.Camera + 1 — after the camera has been positioned — and
	applies the kick as an offset on top of whatever it decided.

	The kick is stored as an angle that decays towards zero, rather than a queue
	of impulses, so rapid fire accumulates smoothly instead of stuttering.
]]

local RunService = game:GetService("RunService")

local Recoil = {}

local camera = workspace.CurrentCamera

-- Current offset, in radians.
local pitch = 0
local yaw = 0

-- How fast the kick returns to centre. Higher settles faster.
local RECOVERY = 9

local rng = Random.new()

function Recoil.start()
	RunService:BindToRenderStep("Recoil", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
		if pitch == 0 and yaw == 0 then
			return
		end

		-- Exponential decay, framerate-independent.
		local decay = math.exp(-RECOVERY * deltaTime)
		pitch *= decay
		yaw *= decay
		if math.abs(pitch) < 1e-5 and math.abs(yaw) < 1e-5 then
			pitch, yaw = 0, 0
		end

		local current = workspace.CurrentCamera
		if not current then
			return
		end
		camera = current
		camera.CFrame = camera.CFrame * CFrame.Angles(pitch, yaw, 0)
	end)
end

--- Kicks the view up by `degrees`, with a little horizontal scatter so repeated
--- shots don't climb in a perfectly straight line.
function Recoil.kick(degrees: number)
	pitch += math.rad(degrees)
	yaw += math.rad(degrees * rng:NextNumber(-0.35, 0.35))
end

return Recoil
