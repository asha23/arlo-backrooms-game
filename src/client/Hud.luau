--!strict
--[[
	Three bars in the corner: stamina, flashlight battery, sanity. Built in code
	rather than as a .rbxmx so the whole UI stays reviewable in the diff.
]]

local Players = game:GetService("Players")

local Hud = {}
Hud.__index = Hud

type Bar = { fill: Frame, label: TextLabel }

export type Hud = typeof(setmetatable(
	{} :: {
		_bars: { [string]: Bar },
		_vignette: Frame,
	},
	Hud
))

local function makeBar(parent: Instance, name: string, order: number, color: Color3): Bar
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Size = UDim2.fromOffset(180, 14)
	holder.Position = UDim2.new(0, 24, 1, -24 - (order * 24))
	holder.AnchorPoint = Vector2.new(0, 1)
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

	return setmetatable({
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

function Hud.update(self: Hud, sanity: number, battery: number, stamina: number)
	setBar(self._bars.SANITY, sanity / 100)
	setBar(self._bars.BATTERY, battery / 100)
	setBar(self._bars.STAMINA, stamina / 100)

	-- Fully opaque at 0 sanity, invisible above 60.
	local dread = 1 - math.clamp(sanity / 60, 0, 1)
	self._vignette.BackgroundTransparency = 1 - (dread * 0.75)
end

return Hud
