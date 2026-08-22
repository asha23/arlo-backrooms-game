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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

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
--[[
	Capped well below the raw viewport ratio.

	A tablet is a much larger screen but not a much larger thumb. Scaling
	buttons linearly with height gave a 190-pixel fire button on an iPad, which
	is both bigger than it needs to be and — because the gaps scaled by the same
	factor — left everything crowded against everything else. Buttons grow a
	little on a big screen; the SPACE between them grows more.
]]
local MIN_SCALE, MAX_SCALE = 0.85, 1.25

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

--[[
	Roblox's own jump button, moved out of the way.

	It is created by the PlayerModule at the bottom right — the same corner as
	FIRE and AIM, so by default it sits underneath them. It is not ours to
	rebuild, but it is ours to reposition: we find the instance and re-anchor
	it to the left of our cluster.

	The PlayerModule builds it asynchronously and rebuilds it on respawn, so
	this retries for a while and is re-applied on every layout pass rather than
	being set once.
]]
local function findJumpButton(): GuiObject?
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	return if jump and jump:IsA("GuiObject") then jump else nil
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
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local s = scaleFor()

		--[[
			Gaps come from the SCREEN, not from the button scale.

			Tying spacing to the button scale means everything grows together,
			so a tablet gets fatter targets with the same visual gap between
			them — which is what made it feel cramped. Deriving the gap from
			viewport height means a bigger screen actually spreads out.
		]]
		local gap = math.floor(math.clamp(viewport.Y * 0.045, 16, 46))
		local edge = math.floor(math.clamp(viewport.Y * 0.04, 16, 44))

		--[[
			Everything sits ABOVE the lives row, which is drawn bottom-right by
			the HUD. Its geometry is shared through Config.Hud so the two files
			cannot disagree about where it ends.
		]]
		local hud = Config.Hud
		local hudScale = math.clamp(viewport.Y / hud.ReferenceHeight, 0.85, 1.6)
		local livesTop = math.floor((hud.LivesBottomOffset + hud.LivesIconSize) * hudScale)
		local floorY = livesTop + gap

		local fireSize = math.floor(112 * s)
		local aimSize = math.floor(78 * s)
		local jumpSize = math.floor(78 * s)
		local tapW, tapH = math.floor(92 * s), math.floor(58 * s)

		-- Bottom row, right to left: FIRE, AIM, JUMP.
		fire.Size = UDim2.fromOffset(fireSize, fireSize)
		fire.Position = UDim2.new(1, -edge, 1, -floorY)

		aim.Size = UDim2.fromOffset(aimSize, aimSize)
		aim.Position = UDim2.new(1, -(edge + fireSize + gap), 1, -floorY)

		reload.Size = UDim2.fromOffset(tapW, tapH)
		reload.Position = UDim2.new(1, -edge, 1, -(floorY + fireSize + gap))

		--[[
			Roblox's own jump button is drawn in the bottom-right corner, which
			is where FIRE is — so by default they overlap. It is not ours to
			rebuild, but it is ours to move: it joins the row to the left of
			AIM. The PlayerModule creates it asynchronously and rebuilds it on
			respawn, which is why this runs on every layout pass rather than
			once.
		]]
		local jump = findJumpButton()
		if jump then
			jump.AnchorPoint = Vector2.new(1, 1)
			jump.Size = UDim2.fromOffset(jumpSize, jumpSize)
			jump.Position = UDim2.new(1, -(edge + fireSize + gap + aimSize + gap), 1, -floorY)
		end

		-- Left cluster, positioned by its bottom-right corner from the left
		-- edge, and lifted clear of Roblox's movement thumbstick.
		local leftX = edge + tapW
		local stickClearance = math.floor(math.clamp(viewport.Y * 0.30, 150, 340))
		sprint.Size = UDim2.fromOffset(tapW, tapH)
		sprint.Position = UDim2.new(0, leftX, 1, -(floorY + stickClearance))

		light.Size = UDim2.fromOffset(tapW, tapH)
		light.Position = UDim2.new(0, leftX, 1, -(floorY + stickClearance + tapH + gap))
	end

	layout()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end

	--[[
		The jump button may not exist yet, and the PlayerModule rebuilds it on
		respawn — so keep re-applying rather than positioning it once. Cheap:
		a handful of property writes, twice a second, and only on touch.
	]]
	task.spawn(function()
		while true do
			task.wait(0.5)
			layout()
		end
	end)

	return true
end

return TouchControls
