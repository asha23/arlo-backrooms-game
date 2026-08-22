--!strict
--[[
	Radar in the top-right corner.

	Deliberately a radar rather than a rendered map. Drawing the maze would mean
	a frame per cell — 2401 of them on a 49x49 grid — and this project has
	already been bitten by doing per-instance work at that scale. Blips are
	pooled: a fixed number of frames are created once and reused, so the cost
	does not grow with how much is out there.

	Everything it shows is read from replicated Workspace folders, so it needs
	no extra network traffic: the client already has these instances.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Device = require(ReplicatedStorage.Shared.Device)

local SETTINGS = Config.Minimap

-- Smaller on phones, where 190px is a large fraction of the screen.
local TOUCH = Device.isTouch()

local player = Players.LocalPlayer

local Minimap = {}

type Blip = Frame

local COLORS = {
	entity = Color3.fromRGB(232, 74, 60),
	weapon = Color3.fromRGB(120, 200, 255),
	health = Color3.fromRGB(240, 90, 95),
	cash = Color3.fromRGB(120, 235, 130),
	exit = Color3.fromRGB(90, 240, 130),
	flashlight = Color3.fromRGB(255, 236, 150),
	life = Color3.fromRGB(255, 96, 120),
}

--[[
	Blip diameters in pixels. Every blip is a circle (UICorner at 0.5).

	Lives and flashlights are drawn noticeably larger than the rest because
	there are only four and five of them in the entire level — they are the
	things worth crossing the map for, and at the same size as a cash drop they
	were lost among a dozen identical dots.
]]
local SIZES = {
	entity = 7,
	weapon = 6,
	health = 6,
	cash = 5,
	exit = 30,
	flashlight = 12,
	life = 12,
}

local function makeBlip(parent: Instance): Blip
	local blip = Instance.new("Frame")
	blip.AnchorPoint = Vector2.new(0.5, 0.5)
	blip.BorderSizePixel = 0
	blip.Visible = false
	blip.ZIndex = 3
	blip.Parent = parent

	local round = Instance.new("UICorner")
	round.Name = "Round"
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = blip

	return blip
end

--[[
	Everything worth showing, as {position, kind} pairs.

	Writes into a caller-supplied table and reuses the entry tables inside it,
	so a loop running seven times a second allocates nothing. It previously
	built a fresh outer table and a fresh table per blip on every tick, which
	is a steady drip of garbage for a readout that mostly does not change.
]]
local scratch: { { position: Vector3, kind: string } } = {}
local scratchUsed = 0

local function add(position: Vector3, kind: string)
	scratchUsed += 1
	local entry = scratch[scratchUsed]
	if entry then
		entry.position = position
		entry.kind = kind
	else
		scratch[scratchUsed] = { position = position, kind = kind }
	end
end

local folderCache: { [string]: Instance } = {}

local function gather(): number
	scratchUsed = 0

	local function scan(folderName: string, kind: string)
		local folder = folderCache[folderName]
		if not folder or not folder.Parent then
			folder = workspace:FindFirstChild(folderName)
			if not folder then
				return
			end
			folderCache[folderName] = folder
		end
		for _, item in folder:GetChildren() do
			local part = if item:IsA("BasePart")
				then item
				elseif item:IsA("Model") then item.PrimaryPart or item:FindFirstChildWhichIsA(
					"BasePart"
				)
				else nil
			if part then
				add(part.Position, kind)
			end
		end
	end

	scan("Entities", "entity")
	scan("WeaponPickups", "weapon")
	scan("Medkits", "health")
	scan("CashDrops", "cash")
	scan("FlashlightPickups", "flashlight")
	scan("LivePickups", "life")
	scan("Exit", "exit")

	return scratchUsed
end

function Minimap.start()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Minimap"
	-- Clear of notches, rounded corners and the home indicator on every device.
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 3
	gui.Parent = playerGui

	--[[
		Scaled to the device rather than a fixed pixel figure. A 190px radar is
		a reasonable corner of a desktop monitor and a third of a phone screen,
		so touch gets a smaller base and everything is then scaled against the
		viewport height.
	]]
	local startCamera = workspace.CurrentCamera
	local viewportY = if startCamera then startCamera.ViewportSize.Y else 720
	local deviceScale = math.clamp(viewportY / 720, 0.8, 1.6)
	-- Only touch scales: a desktop window is already a known quantity and the
	-- configured figure is chosen for it.
	local size = if TOUCH then math.floor(SETTINGS.Size * 0.62 * deviceScale) else SETTINGS.Size
	local frame = Instance.new("Frame")
	frame.Name = "Radar"
	frame.Size = UDim2.fromOffset(size, size)
	frame.Position = UDim2.new(1, -20, 0, 20)
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(14, 13, 11)
	frame.BackgroundTransparency = 0.28
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = gui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 10)
	round.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(70, 64, 50)
	stroke.Transparency = 0.3
	stroke.Parent = frame

	-- Crosshair rules, so distances read at a glance.
	for _, spec in
		{
			{ UDim2.new(1, 0, 0, 1), UDim2.fromScale(0.5, 0.5) },
			{ UDim2.new(0, 1, 1, 0), UDim2.fromScale(0.5, 0.5) },
		}
	do
		local rule = Instance.new("Frame")
		rule.AnchorPoint = Vector2.new(0.5, 0.5)
		rule.Size = spec[1]
		rule.Position = spec[2]
		rule.BackgroundColor3 = Color3.fromRGB(90, 84, 66)
		rule.BackgroundTransparency = 0.6
		rule.BorderSizePixel = 0
		rule.Parent = frame
	end

	-- The player, always dead centre.
	local you = Instance.new("Frame")
	you.Name = "You"
	you.AnchorPoint = Vector2.new(0.5, 0.5)
	you.Position = UDim2.fromScale(0.5, 0.5)
	you.Size = UDim2.fromOffset(8, 8)
	you.BackgroundColor3 = Color3.fromRGB(245, 240, 225)
	you.BorderSizePixel = 0
	you.ZIndex = 5
	you.Rotation = 45 -- a diamond, so it reads differently from the round blips
	you.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 14)
	label.Position = UDim2.new(0, 0, 1, -16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 10
	label.TextColor3 = Color3.fromRGB(150, 144, 130)
	label.Text = "RADAR"
	label.ZIndex = 4
	label.Parent = frame

	-- Fixed pool. Never grows, so a busy moment can't spike instance count.
	local pool: { Blip } = {}
	for _ = 1, SETTINGS.MaxBlips do
		table.insert(pool, makeBlip(frame))
	end

	task.spawn(function()
		while true do
			task.wait(SETTINGS.UpdateInterval)

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local camera = workspace.CurrentCamera
			if not root or not camera then
				for _, blip in pool do
					blip.Visible = false
				end
				continue
			end

			--[[
				Rotate the world into camera space so "up" on the radar is
				where the player is looking. A north-up radar in a maze of
				identical corridors is far harder to read than a heading-up one.
			]]
			local forward = camera.CFrame.LookVector
			local yaw = math.atan2(forward.X, forward.Z)
			local cos, sin = math.cos(yaw), math.sin(yaw)

			local half = size / 2
			local scale = half / SETTINGS.Range
			local origin = root.Position

			local used = 0
			local found = gather()
			for index = 1, found do
				local item = scratch[index]
				if used >= #pool then
					break
				end

				local dx = item.position.X - origin.X
				local dz = item.position.Z - origin.Z

				--[[
					The exit is never hidden. Everything else disappears beyond
					the radar's range; the exit is clamped to the rim instead,
					so it always shows which way out is — that is the one thing
					the player needs to be able to see from anywhere.
				]]
				local outOfRange = dx * dx + dz * dz > SETTINGS.Range ^ 2
				if outOfRange and item.kind ~= "exit" then
					continue
				end

				-- Rotate by -yaw, then flip Z so forward points up the screen.
				local rx = dx * cos - dz * sin
				local rz = dx * sin + dz * cos

				used += 1
				local blip = pool[used]
				local px = SETTINGS.RotateWithCamera and rx or dx
				local py = SETTINGS.RotateWithCamera and rz or dz

				if outOfRange then
					-- Pin it to the rim, keeping the bearing.
					local length = math.sqrt(px * px + py * py)
					px, py = px / length * SETTINGS.Range, py / length * SETTINGS.Range
				end

				local dot = SIZES[item.kind] or 6
				if item.kind == "exit" then
					--[[
						A large pulsing SQUARE, not a dot. It has to be findable
						at a glance among a dozen circular blips, so it differs
						in shape, size and motion all at once.
					]]
					dot = math.floor(dot * (0.78 + 0.22 * math.abs(math.sin(os.clock() * 3))))
					local corner = blip:FindFirstChild("Round")
					if corner and corner:IsA("UICorner") then
						corner.CornerRadius = UDim.new(0, 3)
					end
					blip.ZIndex = 4
				else
					local corner = blip:FindFirstChild("Round")
					if corner and corner:IsA("UICorner") then
						corner.CornerRadius = UDim.new(0.5, 0)
					end
					blip.ZIndex = 3
				end

				blip.Size = UDim2.fromOffset(dot, dot)
				blip.BackgroundColor3 = COLORS[item.kind] or Color3.new(1, 1, 1)
				blip.Position = UDim2.new(0.5, px * scale, 0.5, -py * scale)
				blip.Visible = true
			end

			for index = used + 1, #pool do
				pool[index].Visible = false
			end
		end
	end)
end

return Minimap
