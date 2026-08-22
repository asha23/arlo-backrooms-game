--!strict
--[[
	Three bars in the corner: stamina, flashlight battery, sanity. Built in code
	rather than as a .rbxmx so the whole UI stays reviewable in the diff.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- On touch devices the bottom-left is Roblox's movement thumbstick and the
-- bottom-right is our fire button, so the readouts move to the top.
local TOUCH_LAYOUT = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local Hud = {}
Hud.__index = Hud

type Bar = { fill: Frame, label: TextLabel }

export type Hud = typeof(setmetatable(
	{} :: {
		_bars: { [string]: Bar },
		_vignette: Frame,
		_ammo: TextLabel,
		_hitmarker: Frame,
	},
	Hud
))

local function makeBar(parent: Instance, name: string, order: number, color: Color3): Bar
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Size = UDim2.fromOffset(180, 14)
	if TOUCH_LAYOUT then
		holder.Position = UDim2.new(0, 24, 0, 70 + (order * 22))
		holder.AnchorPoint = Vector2.new(0, 0)
	else
		holder.Position = UDim2.new(0, 24, 1, -24 - (order * 24))
		holder.AnchorPoint = Vector2.new(0, 1)
	end
	holder.BackgroundColor3 = Color3.fromRGB(18, 18, 16)
	holder.BackgroundTransparency = 0.35
	holder.BorderSizePixel = 0
	holder.Parent = parent

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = holder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(235, 232, 220)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ` {name}`
	label.Parent = holder

	return { fill = fill, label = label }
end

function Hud.new(): Hud
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BackroomsHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	-- Darkens the screen edges as sanity falls.
	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.new(0, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.ZIndex = 0
	vignette.Parent = gui

	-- Centre crosshair: four ticks around a gap, so it stays readable against the walls.
	for _, spec in
		{
			{ UDim2.fromOffset(2, 10), UDim2.new(0.5, -1, 0.5, -18) },
			{ UDim2.fromOffset(2, 10), UDim2.new(0.5, -1, 0.5, 8) },
			{ UDim2.fromOffset(10, 2), UDim2.new(0.5, -18, 0.5, -1) },
			{ UDim2.fromOffset(10, 2), UDim2.new(0.5, 8, 0.5, -1) },
		}
	do
		local tick = Instance.new("Frame")
		tick.Size = spec[1]
		tick.Position = spec[2]
		tick.BackgroundColor3 = Color3.fromRGB(240, 240, 235)
		tick.BackgroundTransparency = 0.25
		tick.BorderSizePixel = 0
		tick.Parent = gui
	end

	local hitmarker = Instance.new("Frame")
	hitmarker.Name = "Hitmarker"
	hitmarker.Size = UDim2.fromOffset(8, 8)
	hitmarker.Position = UDim2.new(0.5, -4, 0.5, -4)
	hitmarker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hitmarker.BorderSizePixel = 0
	hitmarker.Visible = false
	hitmarker.Parent = gui

	local ammo = Instance.new("TextLabel")
	ammo.Name = "Ammo"
	ammo.Size = UDim2.fromOffset(280, 24)
	if TOUCH_LAYOUT then
		ammo.Position = UDim2.new(1, -24, 0, 70)
		ammo.AnchorPoint = Vector2.new(1, 0)
	else
		ammo.Position = UDim2.new(1, -24, 1, -24)
		ammo.AnchorPoint = Vector2.new(1, 1)
	end
	ammo.BackgroundTransparency = 1
	ammo.Font = Enum.Font.Code
	ammo.TextSize = 18
	ammo.TextColor3 = Color3.fromRGB(240, 236, 224)
	ammo.TextStrokeTransparency = 0.4
	ammo.TextXAlignment = Enum.TextXAlignment.Right
	ammo.Text = ""
	ammo.Parent = gui

	return setmetatable({
		_ammo = ammo,
		_hitmarker = hitmarker,
		_bars = {
			SANITY = makeBar(gui, "SANITY", 0, Color3.fromRGB(190, 175, 105)),
			BATTERY = makeBar(gui, "BATTERY", 1, Color3.fromRGB(120, 170, 220)),
			STAMINA = makeBar(gui, "STAMINA", 2, Color3.fromRGB(200, 200, 200)),
		},
		_vignette = vignette,
	}, Hud)
end

local function setBar(bar: Bar, alpha: number)
	bar.fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
end

--- The hitmarker frame, handed to the weapon controller to flash on a hit.
function Hud.hitmarker(self: Hud): Frame
	return self._hitmarker
end

function Hud.setAmmoText(self: Hud, text: string?)
	self._ammo.Text = text or ""
end

function Hud.update(self: Hud, sanity: number, battery: number, stamina: number)
	setBar(self._bars.SANITY, sanity / 100)
	setBar(self._bars.BATTERY, battery / 100)
	setBar(self._bars.STAMINA, stamina / 100)

	-- Fully opaque at 0 sanity, invisible above 60.
	local dread = 1 - math.clamp(sanity / 60, 0, 1)
	self._vignette.BackgroundTransparency = 1 - (dread * 0.75)
end

return Hud
