--!strict
--[[
	Score, three status bars, crosshair and hit feedback. Built in code
	rather than as a .rbxmx so the whole UI stays reviewable in the diff.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

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
		_deathPrompt: TextLabel,
		_torchWarning: TextLabel,
		_lives: { ImageLabel },
	},
	Hud
))

local function makeBar(parent: Instance, name: string, order: number, color: Color3): Bar
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Size = UDim2.fromOffset(180, 14)
	if TOUCH_LAYOUT then
		-- Below the score block, which occupies roughly y 24-100.
		holder.Position = UDim2.new(0, 24, 0, 112 + (order * 22))
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

	-- Death prompt, under the countdown banner.
	local deathPrompt = Instance.new("TextLabel")
	deathPrompt.Name = "DeathPrompt"
	deathPrompt.Size = UDim2.new(1, 0, 0, 40)
	deathPrompt.Position = UDim2.new(0, 0, 0.5, 20)
	deathPrompt.BackgroundTransparency = 1
	deathPrompt.Font = Enum.Font.GothamBold
	deathPrompt.TextSize = 26
	deathPrompt.TextColor3 = Color3.fromRGB(235, 230, 218)
	deathPrompt.TextStrokeTransparency = 0.4
	deathPrompt.Text = ""
	deathPrompt.Visible = false
	deathPrompt.ZIndex = 10
	deathPrompt.Parent = gui

	-- Low battery warning. Sits under the crosshair so it's unmissable without
	-- covering what you're aiming at.
	local torchWarning = Instance.new("TextLabel")
	torchWarning.Name = "FlashlightWarning"
	torchWarning.Size = UDim2.new(1, 0, 0, 26)
	torchWarning.Position = UDim2.new(0, 0, 0.5, 60)
	torchWarning.BackgroundTransparency = 1
	torchWarning.Font = Enum.Font.GothamBold
	torchWarning.TextSize = 20
	torchWarning.TextColor3 = Color3.fromRGB(255, 190, 70)
	torchWarning.TextStrokeTransparency = 0.4
	torchWarning.Text = "FLASHLIGHT LOW!"
	torchWarning.Visible = false
	torchWarning.ZIndex = 8
	torchWarning.Parent = gui

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

	--[[
		Lives, bottom right, drawn as copies of the player's own avatar head.

		GetUserThumbnailAsync yields and can fail (it is a web request), so the
		icons are created immediately as plain coloured squares and the portrait
		is filled in when it arrives. A HUD element that only appears if a
		network call succeeds is a HUD element that sometimes isn't there.
	]]
	local livesIcons: { ImageLabel } = {}
	local maxLives = Config.Lives.Maximum
	for index = 1, maxLives do
		local icon = Instance.new("ImageLabel")
		icon.Name = `Life{index}`
		icon.Size = UDim2.fromOffset(30, 30)
		icon.AnchorPoint = Vector2.new(1, 1)
		icon.Position = UDim2.new(1, -24 - (maxLives - index) * 34, 1, -56)
		icon.BackgroundColor3 = Color3.fromRGB(60, 56, 50)
		icon.BackgroundTransparency = 0.25
		icon.BorderSizePixel = 0
		icon.Parent = gui

		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = icon

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Config.Lives.Color
		stroke.Parent = icon

		table.insert(livesIcons, icon)
	end

	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				Players.LocalPlayer.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if not ok then
			return -- the plain squares stand in perfectly well
		end
		for _, icon in livesIcons do
			icon.Image = image
		end
	end)

	local ammo = Instance.new("TextLabel")
	ammo.Name = "Ammo"
	ammo.Size = UDim2.fromOffset(280, 24)
	if TOUCH_LAYOUT then
		--[[
			Top centre on touch. The bottom-right is the fire button, the
			bottom-left is Roblox's thumbstick, the top-left is the score block
			and the top-right is now the radar — centre is the only clear space
			left, and it was previously overlapping the radar.
		]]
		ammo.Position = UDim2.new(0.5, 0, 0, 26)
		ammo.AnchorPoint = Vector2.new(0.5, 0)
		ammo.TextXAlignment = Enum.TextXAlignment.Center
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
		_deathPrompt = deathPrompt,
		_torchWarning = torchWarning,
		_lives = livesIcons,
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

function Hud.setScore(
	self: Hud,
	score: number,
	kills: number,
	headshots: number,
	cash: number,
	escapes: number?
)
	self._score.Text = tostring(score)
	local suffix = if escapes and escapes > 0 then `  {escapes} escapes` else ""
	self._kills.Text = `{kills} kills  {headshots} headshots{suffix}`
	self._cash.Text = `${cash}`
end

--- Victory banner. Uses the countdown slot, which is already centred and above
--- everything else, rather than adding a second full-screen element.
--- Full-screen GAME OVER, reusing the countdown slot.
function Hud.showGameOver(self: Hud)
	local label = self._countdown
	label.TextColor3 = Color3.fromRGB(235, 70, 60)
	label.TextSize = 76
	label.Text = "GAME OVER"
	label.TextTransparency = 0
	-- The prompt IS the restart: one click starts a fresh run.
	self:setDeathPrompt("CLICK TO PLAY AGAIN")

	task.delay(3.2, function()
		if label.Text == "GAME OVER" then
			label.Text = ""
		end
	end)
end

function Hud.showEscape(self: Hud, bonusScore: number, bonusCash: number, escapes: number?)
	local label = self._countdown
	label.TextColor3 = Color3.fromRGB(90, 240, 130)
	label.TextSize = 64
	-- Number the escapes, so a repeat run reads as progress rather than as the
	-- same message again.
	label.Text = if escapes and escapes > 1 then `ESCAPE #{escapes}` else "YOU ESCAPED"
	label.TextTransparency = 0

	self:setDeathPrompt(`+{bonusScore} SCORE   +${bonusCash}   GO AGAIN`)

	task.delay(3.4, function()
		if label.Text == "YOU ESCAPED" then
			label.Text = ""
			self:setDeathPrompt(nil)
		end
	end)
end

--[[
	Shows one step of the countdown. "FIGHT!" gets a colour and a size of its
	own so the go signal is unmistakable at a glance — you should not have to
	read the word to know the count has ended.
]]
--[[
	Lives remaining. Spent lives dim rather than disappear, so the count of what
	you started with stays visible — five faded icons reads as "you are on your
	last" far faster than one icon does.
]]
function Hud.setLives(self: Hud, remaining: number)
	for index, icon in self._lives do
		local alive = index <= remaining
		icon.ImageTransparency = if alive then 0 else 0.78
		icon.BackgroundTransparency = if alive then 0.25 else 0.75
		local stroke = icon:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = if alive then 0 else 0.7
		end
	end
end

--- Shows or clears the death prompt.
function Hud.setDeathPrompt(self: Hud, text: string?)
	local label = self._deathPrompt
	label.Text = text or ""
	label.Visible = text ~= nil and text ~= ""
end

--[[
	Low-battery warning. Pulsed rather than static: a warning that just sits
	there stops being read after the first few seconds.
]]
function Hud.setFlashlightWarning(self: Hud, low: boolean)
	local label = self._torchWarning
	if not low then
		label.Visible = false
		return
	end
	label.Visible = true
	label.TextTransparency = 0.25 + 0.35 * math.abs(math.sin(os.clock() * 4))
end

function Hud.setCountdown(self: Hud, text: string)
	local label = self._countdown
	label.Text = text
	if text == "" then
		return
	end

	-- Only the bare go word counts as the go signal; "RESPAWN IN 3" also
	-- contains letters but is still a counting step.
	local isGo = text:match("%d") == nil
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
