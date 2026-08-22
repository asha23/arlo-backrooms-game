--!strict
--[[
	One answer to "is this a touch device?", shared by everything that lays out
	UI.

	It was decided independently in four files — the HUD, the radar, the camera
	and the touch controls — each writing the same expression. Four copies of a
	predicate is four chances for them to disagree, and when they do the result
	is a HUD laid out for one device and controls laid out for another, sitting
	on top of each other.
]]

local UserInputService = game:GetService("UserInputService")

local Device = {}

--[[
	True on anything with a touchscreen and no mouse.

	The mouse test matters: a laptop with a touchscreen reports TouchEnabled,
	and it should keep the desktop layout and its keyboard bindings.
]]
function Device.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

--[[
	Scale factor for UI sized in pixels, against a 720-tall reference.

	Clamped, because a phone and a large tablet differ in screen size far more
	than they differ in how big a comfortable touch target is.
]]
function Device.uiScale(minimum: number?, maximum: number?): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 720
	return math.clamp(height / 720, minimum or 0.85, maximum or 1.6)
end

return Device
