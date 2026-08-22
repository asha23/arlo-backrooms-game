--!strict
--[[
	Score, three status bars, crosshair and hit feedback. Built in code
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
		_score: TextLabel,
		_kills: TextLabel,
		_cash: TextLabel,
		_headshot: TextLabel,
		_countdown: TextLabel,
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

	-- Darkens the screen edges as health falls.
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

	-- Score, top-left. Large enough to read without looking away from centre.
	local score = Instance.new("TextLabel")
	score.Name = "Score"
	score.Size = UDim2.fromOffset(260, 34)
	score.Position = UDim2.new(0, 24, 0, 24)
	score.BackgroundTransparency = 1
	score.Font = Enum.Font.GothamBold
	score.TextSize = 28
	score.TextColor3 = Color3.fromRGB(240, 236, 224)
	score.TextStrokeTransparency = 0.5
	score.TextXAlignment = Enum.TextXAlignment.Left
	score.Text = "0"
	score.Parent = gui

	local kills = Instance.new("TextLabel")
	kills.Name = "Kills"
	kills.Size = UDim2.fromOffset(260, 18)
	kills.Position = UDim2.new(0, 24, 0, 56)
	kills.BackgroundTransparency = 1
	kills.Font = Enum.Font.Code
	kills.TextSize = 13
	kills.TextColor3 = Color3.fromRGB(150, 144, 130)
	kills.TextXAlignment = Enum.TextXAlignment.Left
	kills.Text = "0 kills  0 headshots"
	kills.Parent = gui

	local wallet = Instance.new("TextLabel")
	wallet.Name = "Cash"
	wallet.Size = UDim2.fromOffset(260, 22)
	wallet.Position = UDim2.new(0, 24, 0, 76)
	wallet.BackgroundTransparency = 1
	wallet.Font = Enum.Font.GothamBold
	wallet.TextSize = 18
	wallet.TextColor3 = Color3.fromRGB(120, 235, 130)
	wallet.TextStrokeTransparency = 0.6
	wallet.TextXAlignment = Enum.TextXAlignment.Left
	wallet.Text = "$0"
	wallet.Parent = gui

	-- Countdown banner, dead centre and above everything else.
	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.Size = UDim2.new(1, 0, 0, 110)
	countdown.Position = UDim2.new(0, 0, 0.34, 0)
	countdown.BackgroundTransparency = 1
	countdown.Font = Enum.Font.GothamBold
	countdown.TextSize = 88
	countdown.TextColor3 = Color3.fromRGB(232, 126, 34)
	countdown.TextStrokeTransparency = 0.35
	countdown.Text = ""
	countdown.ZIndex = 10
	countdown.Parent = gui

	-- Headshot callout, just above the crosshair.
	local headshot = Instance.new("TextLabel")
	headshot.Name = "Headshot"
	headshot.Size = UDim2.fromOffset(300, 24)
	headshot.Position = UDim2.new(0.5, -150, 0.5, -70)
	headshot.BackgroundTransparency = 1
	headshot.Font = Enum.Font.GothamBold
	headshot.TextSize = 20
	headshot.TextColor3 = Color3.fromRGB(255, 90, 80)
	headshot.TextStrokeTransparency = 0.4
	headshot.Text = "HEADSHOT!"
	headshot.TextTransparency = 1
	headshot.Parent = gui

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
		_score = score,
		_kills = kills,
		_cash = wallet,
		_headshot = headshot,
		_countdown = countdown,
		_bars = {
			HEALTH = makeBar(gui, "HEALTH", 0, Color3.fromRGB(200, 70, 65)),
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

function Hud.setScore(self: Hud, score: number, kills: number, headshots: number, cash: number)
	self._score.Text = tostring(score)
	self._kills.Text = `{kills} kills  {headshots} headshots`
	self._cash.Text = `${cash}`
end

--[[
	Shows one step of the countdown. "FIGHT!" gets a colour and a size of its
	own so the go signal is unmistakable at a glance — you should not have to
	read the word to know the count has ended.
]]
function Hud.setCountdown(self: Hud, text: string)
	local label = self._countdown
	label.Text = text
	if text == "" then
		return
	end

	local isGo = text:match("%a") ~= nil
	label.TextColor3 = if isGo then Color3.fromRGB(255, 80, 60) else Color3.fromRGB(232, 126, 34)
	label.TextSize = if isGo then 72 else 88

	-- Punch in: start oversized and settle, so each step reads as a beat.
	label.TextTransparency = 0
	task.spawn(function()
		local target = label.TextSize
		for step = 0, 1, 0.12 do
			label.TextSize = math.floor(target * (1.35 - 0.35 * step))
			task.wait(0.015)
		end
		label.TextSize = target
	end)
end

--- Flashes the HEADSHOT callout. Fades itself out; safe to call repeatedly.
function Hud.flashHeadshot(self: Hud)
	local label = self._headshot
	label.TextTransparency = 0
	task.spawn(function()
		for alpha = 0, 1, 0.06 do
			label.TextTransparency = alpha
			task.wait(0.02)
		end
		label.TextTransparency = 1
	end)
end

function Hud.update(self: Hud, health: number, maxHealth: number, battery: number, stamina: number)
	setBar(self._bars.HEALTH, if maxHealth > 0 then health / maxHealth else 0)
	setBar(self._bars.BATTERY, battery / 100)
	setBar(self._bars.STAMINA, stamina / 100)

	-- The vignette tracks health: it closes in as you
	-- get closer to dying, which is the thing worth signalling.
	local hurt = 1 - math.clamp(if maxHealth > 0 then health / maxHealth else 0, 0, 1)
	self._vignette.BackgroundColor3 = Color3.fromRGB(40, 0, 0)
	self._vignette.BackgroundTransparency = 1 - (hurt * 0.6)
end

return Hud
