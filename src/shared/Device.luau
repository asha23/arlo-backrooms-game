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
	Whether to BUILD the on-screen controls.

	Strict: a laptop with a touchscreen has a keyboard and mouse already, and
	does not want a fire button drawn over its game.
]]
function Device.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

--[[
	Whether to LAY OUT the HUD for thumbs.

	Deliberately looser than isTouch: a touchscreen alone is enough.

	The two questions are not the same, and treating them as one was the bug.
	MouseEnabled can report true on a device that is being played with thumbs —
	Studio's emulator with a real mouse attached is the obvious case — and when
	that happened the lives row stayed in the bottom-right corner underneath the
	fire button. Getting this wrong on a tablet leaves controls stacked on top of
	each other; getting it wrong on a touchscreen laptop moves a health bar a few
	pixels. Those costs are not close, so this errs toward the touch layout.
]]
function Device.usesTouchLayout(): boolean
	return UserInputService.TouchEnabled
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
