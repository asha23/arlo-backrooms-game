--!strict
--[[
	Telescopic sight.

	Built from plain Frames, so it needs no uploaded image assets.

	The occluder is sized in PIXELS from the viewport rather than in scale.
	Scale is the obvious way to write it and it is wrong: a left panel of width
	0.5 and a right panel of width 0.5 together cover the entire screen, which
	is exactly what the first version did — the scope zoomed correctly and then
	painted black over everything it had zoomed. Deriving the panel widths from
	the actual viewport is the only way the aperture is guaranteed to survive.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

-- Aperture diameter as a fraction of viewport height.
local APERTURE = 0.66

local Scope = {}
Scope.__index = Scope

export type Scope = typeof(setmetatable(
	{} :: {
		active: boolean,
		_gui: ScreenGui,
		_baseFov: number,
	},
	Scope
))

local BLACK = Color3.new(0, 0, 0)

local function panel(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = BLACK
	f.BorderSizePixel = 0
	f.ZIndex = 2
	f.Parent = parent
	return f
end

function Scope.new(): Scope
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Scope"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = false
	gui.Parent = playerGui

	local top = panel(gui, "Top")
	local bottom = panel(gui, "Bottom")
	local left = panel(gui, "Left")
	local right = panel(gui, "Right")

	-- Corner fillets, sized from the aperture so they can never grow to cover
	-- the view. They cut the square aperture into an octagon; the ring drawn
	-- over the top reads as a circle in motion.
	local fillets = {}
	for index = 1, 4 do
		local f = panel(gui, `Fillet{index}`)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Rotation = 45
		table.insert(fillets, f)
	end

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 3
	ring.Parent = gui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = ring

	local edge = Instance.new("UIStroke")
	edge.Thickness = 3
	edge.Color = Color3.fromRGB(20, 20, 19)
	edge.Parent = ring

	local function hair(name: string): Frame
		local h = Instance.new("Frame")
		h.Name = name
		h.AnchorPoint = Vector2.new(0.5, 0.5)
		h.BackgroundColor3 = Color3.fromRGB(18, 18, 17)
		h.BorderSizePixel = 0
		h.ZIndex = 4
		h.Parent = gui
		return h
	end

	local hairs = {
		left = hair("HairLeft"),
		right = hair("HairRight"),
		up = hair("HairUp"),
		down = hair("HairDown"),
	}
	local ticks = {}
	for index = 1, 3 do
		table.insert(ticks, hair(`Tick{index}`))
	end

	--- Lays everything out from the current viewport size.
	local function layout()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local view = camera.ViewportSize
		local aperture = math.min(view.Y * APERTURE, view.X * 0.9)
		local sideW = math.max(0, (view.X - aperture) / 2)
		local sideH = math.max(0, (view.Y - aperture) / 2)

		top.Size = UDim2.fromOffset(math.ceil(view.X), math.ceil(sideH) + 1)
		top.Position = UDim2.fromOffset(0, 0)

		bottom.Size = UDim2.fromOffset(math.ceil(view.X), math.ceil(sideH) + 1)
		bottom.Position = UDim2.fromOffset(0, math.floor(view.Y - sideH))

		left.Size = UDim2.fromOffset(math.ceil(sideW) + 1, math.ceil(aperture) + 2)
		left.Position = UDim2.fromOffset(0, math.floor(sideH))

		right.Size = UDim2.fromOffset(math.ceil(sideW) + 1, math.ceil(aperture) + 2)
		right.Position = UDim2.fromOffset(math.floor(view.X - sideW), math.floor(sideH))

		local half = aperture / 2
		local filletSize = aperture * 0.46
		local offset = half + filletSize * 0.32
		local centres = {
			Vector2.new(-offset, -offset),
			Vector2.new(offset, -offset),
			Vector2.new(-offset, offset),
			Vector2.new(offset, offset),
		}
		for index, f in fillets do
			f.Size = UDim2.fromOffset(math.ceil(filletSize), math.ceil(filletSize))
			f.Position = UDim2.new(0.5, centres[index].X, 0.5, centres[index].Y)
		end

		ring.Size = UDim2.fromOffset(math.ceil(aperture), math.ceil(aperture))

		local gap = aperture * 0.055
		local arm = aperture * 0.30
		hairs.left.Size = UDim2.fromOffset(math.ceil(arm), 2)
		hairs.left.Position = UDim2.new(0.5, -(gap + arm / 2), 0.5, 0)
		hairs.right.Size = UDim2.fromOffset(math.ceil(arm), 2)
		hairs.right.Position = UDim2.new(0.5, gap + arm / 2, 0.5, 0)
		hairs.up.Size = UDim2.fromOffset(2, math.ceil(arm))
		hairs.up.Position = UDim2.new(0.5, 0, 0.5, -(gap + arm / 2))
		hairs.down.Size = UDim2.fromOffset(2, math.ceil(arm))
		hairs.down.Position = UDim2.new(0.5, 0, 0.5, gap + arm / 2)

		for index, t in ticks do
			t.Size = UDim2.fromOffset(12, 2)
			t.Position = UDim2.new(0.5, 0, 0.5, math.floor(gap + arm + index * aperture * 0.055))
		end
	end

	layout()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end

	return setmetatable({
		active = false,
		_gui = gui,
		_baseFov = if camera then camera.FieldOfView else 70,
	}, Scope)
end

--- Enters or leaves the scope. Safe to call repeatedly with the same value.
function Scope.set(
	self: Scope,
	active: boolean,
	stats: { FieldOfView: number, Sensitivity: number }?
)
	if active == self.active then
		return
	end
	self.active = active

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if active and stats then
		self._gui.Enabled = true
		UserInputService.MouseDeltaSensitivity = Config.Camera.Sensitivity * stats.Sensitivity
		TweenService:Create(camera, TweenInfo.new(0.16), { FieldOfView = stats.FieldOfView }):Play()
	else
		self._gui.Enabled = false
		UserInputService.MouseDeltaSensitivity = Config.Camera.Sensitivity
		TweenService:Create(camera, TweenInfo.new(0.14), { FieldOfView = self._baseFov }):Play()
	end
end

--- Drops the scope if the weapon is put away or the character dies.
function Scope.enforce(self: Scope, stillValid: boolean)
	if self.active and not stillValid then
		self:set(false)
	end
end

return Scope
