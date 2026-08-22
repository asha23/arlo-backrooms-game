--!strict
--[[
	On-screen controls for touch devices.

	Roblox already supplies the movement thumbstick, the jump button and
	drag-to-look on the right of the screen, so this only adds the actions it
	does not know about: fire, aim, reload, sprint and the flashlight.

	Two things here follow mobile-shooter convention rather than being the
	obvious implementation:

	1. FIRE and AIM are NOT buttons. A GuiButton consumes the touch that starts
	   on it, and Roblox drives the look camera from drags on the right of the
	   screen — so a fire button sitting there means you cannot aim while you
	   are shooting, which every mobile shooter lets you do. They are
	   non-interactive Frames instead, with touches matched against their
	   rectangle by UserInputService. The touch is never consumed, so the same
	   thumb both fires and turns the camera.

	2. Everything is sized against the viewport rather than in fixed pixels. A
	   84-pixel button is comfortable on a phone and a postage stamp on a
	   tablet.

	Everything drives the same methods the keyboard and mouse bindings do, so
	touch is never a second implementation of the game's rules.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local TouchControls = {}

type Handlers = {
	onFireDown: () -> (),
	onFireUp: () -> (),
	onReload: () -> (),
	onSprintChanged: (boolean) -> (),
	onFlashlight: () -> (),
	onAimDown: () -> (),
	onAimUp: () -> (),
}

local ACTIVE = Color3.fromRGB(232, 126, 34)
local IDLE = Color3.fromRGB(28, 28, 30)
local TEXT = Color3.fromRGB(240, 236, 228)

--[[
	Reference height the pixel figures below are written against. Everything is
	multiplied by viewport.Y / this, clamped so a very tall or very short
	display still gets something sensible.
]]
local REFERENCE_HEIGHT = 720
local MIN_SCALE, MAX_SCALE = 0.8, 1.7

local function scaleFor(): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else REFERENCE_HEIGHT
	return math.clamp(height / REFERENCE_HEIGHT, MIN_SCALE, MAX_SCALE)
end

local function style(frame: GuiObject, label: string)
	frame.BackgroundColor3 = IDLE
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(120, 112, 96)
	stroke.Transparency = 0.4
	stroke.Parent = frame

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = TEXT
	text.Text = label
	text.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = text
end

--[[
	A hold zone that does not consume the touch.

	`Active = false` keeps the Frame out of the input chain entirely, so the
	touch still reaches Roblox's camera and the player can turn while holding
	it. Matching is done against the frame's absolute rectangle, and the
	specific InputObject is tracked so a finger that slides off still counts as
	held — and so releasing it elsewhere still ends the hold.
]]
local function makeHoldZone(
	parent: Instance,
	name: string,
	label: string,
	onDown: () -> (),
	onUp: () -> ()
): Frame
	local zone = Instance.new("Frame")
	zone.Name = name
	zone.AnchorPoint = Vector2.new(1, 1)
	zone.Active = false
	zone.Parent = parent
	style(zone, label)

	local held: InputObject? = nil

	local function inside(position: Vector3): boolean
		local topLeft = zone.AbsolutePosition
		local size = zone.AbsoluteSize
		return position.X >= topLeft.X
			and position.X <= topLeft.X + size.X
			and position.Y >= topLeft.Y
			and position.Y <= topLeft.Y + size.Y
	end

	UserInputService.TouchStarted:Connect(function(input)
		if held or not zone.Visible or not inside(input.Position) then
			return
		end
		held = input
		zone.BackgroundColor3 = ACTIVE
		onDown()
	end)

	UserInputService.TouchEnded:Connect(function(input)
		if input ~= held then
			return
		end
		held = nil
		zone.BackgroundColor3 = IDLE
		onUp()
	end)

	return zone
end

--- A plain tap button. Consuming the touch is fine for these: nobody needs to
--- turn the camera with the thumb they reload with.
local function makeTapButton(
	parent: Instance,
	name: string,
	label: string,
	onTap: () -> ()
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent
	style(button, label)

	button.Activated:Connect(function()
		button.BackgroundColor3 = ACTIVE
		task.delay(0.1, function()
			button.BackgroundColor3 = IDLE
		end)
		onTap()
	end)

	return button
end

--- A tap button that latches on and off.
local function makeToggle(
	parent: Instance,
	name: string,
	label: string,
	onChanged: (boolean) -> ()
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent
	style(button, label)

	local state = false
	button.Activated:Connect(function()
		state = not state
		button.BackgroundColor3 = if state then ACTIVE else IDLE
		onChanged(state)
	end)

	return button
end

--- Builds the touch UI. Returns false (and builds nothing) on non-touch devices.
function TouchControls.start(handlers: Handlers): boolean
	-- A device with a mouse does not need these, even if it also has a
	-- touchscreen; the keyboard bindings already cover it.
	if not UserInputService.TouchEnabled or UserInputService.MouseEnabled then
		return false
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	--[[
		Keeps everything clear of notches, rounded corners and the home
		indicator, on every device, without hand-measuring insets.
	]]
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 2
	gui.Parent = playerGui

	local fire = makeHoldZone(gui, "Fire", "FIRE", handlers.onFireDown, handlers.onFireUp)
	local aim = makeHoldZone(gui, "Aim", "AIM", handlers.onAimDown, handlers.onAimUp)
	local reload = makeTapButton(gui, "Reload", "RELOAD", handlers.onReload)
	local light = makeTapButton(gui, "Flashlight", "LIGHT", handlers.onFlashlight)
	local sprint = makeToggle(gui, "Sprint", "SPRINT", handlers.onSprintChanged)

	--[[
		Layout, recomputed whenever the viewport changes — rotation, a resized
		emulator window, a foldable opening.

		Right thumb: FIRE at the corner with AIM beside it and RELOAD above,
		which is where a shooter's right hand expects them.

		Left thumb: SPRINT and LIGHT, stacked above the movement thumbstick.
		Putting them on the right would crowd the area the same thumb needs for
		looking, which is the one thing that side has to stay clear for.
	]]
	local function layout()
		local s = scaleFor()
		local pad = math.floor(18 * s)
		local fireSize = math.floor(112 * s)
		local aimSize = math.floor(76 * s)
		local tapW, tapH = math.floor(88 * s), math.floor(58 * s)

		fire.Size = UDim2.fromOffset(fireSize, fireSize)
		fire.Position = UDim2.new(1, -pad, 1, -pad)

		aim.Size = UDim2.fromOffset(aimSize, aimSize)
		aim.Position = UDim2.new(1, -(pad + fireSize + math.floor(12 * s)), 1, -pad)

		reload.Size = UDim2.fromOffset(tapW, tapH)
		reload.Position = UDim2.new(1, -pad, 1, -(pad + fireSize + math.floor(12 * s)))

		-- Left cluster. AnchorPoint is (1,1), so these are positioned by their
		-- bottom-right corner measured from the left edge.
		local leftX = pad + tapW
		sprint.Size = UDim2.fromOffset(tapW, tapH)
		sprint.Position = UDim2.new(0, leftX, 1, -(pad + math.floor(190 * s)))

		light.Size = UDim2.fromOffset(tapW, tapH)
		light.Position =
			UDim2.new(0, leftX, 1, -(pad + math.floor(190 * s) + tapH + math.floor(12 * s)))
	end

	layout()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end

	return true
end

return TouchControls
