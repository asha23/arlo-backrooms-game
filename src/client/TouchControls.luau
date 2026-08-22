--!strict
--[[
	On-screen controls for touch devices.

	Roblox already supplies the movement thumbstick, the jump button and
	drag-to-look on the right half of the screen, so this only adds the actions
	it doesn't know about: fire, reload, sprint and the flashlight.

	Everything here drives the same methods the keyboard and mouse bindings do,
	so touch is never a second implementation of the game's rules.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local TouchControls = {}

type Handlers = {
	onFireDown: () -> (),
	onFireUp: () -> (),
	onReload: () -> (),
	onSprintChanged: (boolean) -> (),
	onFlashlight: () -> (),
	-- Aim is a momentary hold, matching right-mouse on desktop.
	onAimDown: () -> (),
	onAimUp: () -> (),
}

local ACTIVE = Color3.fromRGB(232, 126, 34)
local IDLE = Color3.fromRGB(28, 28, 30)
local TEXT = Color3.fromRGB(240, 236, 228)

local function roundify(frame: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
end

--- Creates the styled button shell, with no input behaviour attached.
local function makeShell(
	parent: Instance,
	name: string,
	label: string,
	size: UDim2,
	position: UDim2
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.AnchorPoint = Vector2.new(1, 1)
	button.BackgroundColor3 = IDLE
	button.BackgroundTransparency = 0.25
	button.AutoButtonColor = false
	button.Text = label
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = TEXT
	button.BorderSizePixel = 0
	button.Parent = parent
	roundify(button, 12)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = button

	return button
end

--[[
	A momentary button: fires `onDown` as soon as it's pressed and `onUp` when
	released. Using InputBegan/InputEnded rather than Activated is what makes
	hold-to-fire work — Activated only fires on a completed tap.

	The release is tracked against the specific InputObject that started the
	press, and watched on UserInputService rather than on the button. A finger
	that slides off the button before lifting ends the input somewhere else
	entirely, and the button's own InputEnded never fires — which would leave
	the weapon firing forever.
]]
local function makeButton(
	parent: Instance,
	name: string,
	label: string,
	size: UDim2,
	position: UDim2,
	onDown: () -> (),
	onUp: (() -> ())?
): TextButton
	local button = makeShell(parent, name, label, size, position)

	local activeInput: InputObject? = nil

	local function release()
		if not activeInput then
			return
		end
		activeInput = nil
		button.BackgroundColor3 = IDLE
		if onUp then
			onUp()
		end
	end

	button.InputBegan:Connect(function(input)
		if activeInput then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
		then
			return
		end
		activeInput = input
		button.BackgroundColor3 = ACTIVE
		onDown()
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input == activeInput then
			release()
		end
	end)

	return button
end

--- A button that flips between two states rather than acting as a momentary.
local function makeToggle(
	parent: Instance,
	name: string,
	label: string,
	size: UDim2,
	position: UDim2,
	onChanged: (boolean) -> ()
): TextButton
	local button = makeShell(parent, name, label, size, position)
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
	-- A device with a mouse doesn't need these, even if it also has a
	-- touchscreen; the keyboard bindings already cover it.
	if not UserInputService.TouchEnabled or UserInputService.MouseEnabled then
		return false
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	-- Sit above the HUD but below Roblox's own touch controls.
	gui.DisplayOrder = 2
	gui.Parent = playerGui

	-- Keep the buttons clear of a notch or home indicator.
	local inset = GuiService:GetGuiInset()
	local safe = Instance.new("Frame")
	safe.Name = "SafeArea"
	safe.Size = UDim2.new(1, -16, 1, -(16 + inset.Y))
	safe.Position = UDim2.fromOffset(8, 8)
	safe.BackgroundTransparency = 1
	safe.Parent = gui

	-- Fire sits under the right thumb, where the look-drag area already is;
	-- it's the largest target because it's the most used.
	makeButton(
		safe,
		"Fire",
		"FIRE",
		UDim2.fromOffset(110, 110),
		UDim2.new(1, 0, 1, 0),
		handlers.onFireDown,
		handlers.onFireUp
	)

	--[[
		Aim, for the sniper's scope. Without this the telescopic sight is simply
		unreachable on a touch device — there is no right mouse button to hold.
		It sits next to Fire so both are under the same thumb.
	]]
	makeButton(
		safe,
		"Aim",
		"AIM",
		UDim2.fromOffset(84, 84),
		UDim2.new(1, -122, 1, 0),
		handlers.onAimDown,
		handlers.onAimUp
	)

	makeButton(
		safe,
		"Reload",
		"RELOAD",
		UDim2.fromOffset(84, 56),
		UDim2.new(1, -122, 1, -96),
		handlers.onReload,
		nil
	)

	makeToggle(
		safe,
		"Sprint",
		"SPRINT",
		UDim2.fromOffset(84, 56),
		UDim2.new(1, 0, 1, -122),
		handlers.onSprintChanged
	)

	makeButton(
		safe,
		"Flashlight",
		"LIGHT",
		UDim2.fromOffset(84, 56),
		UDim2.new(1, 0, 1, -186),
		handlers.onFlashlight,
		nil
	)

	return true
end

return TouchControls
