--!strict
--[[
	Telescopic sight for weapons that have one.

	Built from plain Frames rather than an image, so it needs no uploaded
	assets. The occluder is an octagon — four frames boxing in a square hole,
	plus four more rotated 45 degrees to cut the corners off — with a circular
	ring stroked on top. A true circular mask isn't possible without an image
	with an alpha channel, and an octagon behind a drawn ring is
	indistinguishable from one in motion.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

local Scope = {}
Scope.__index = Scope

export type Scope = typeof(setmetatable(
	{} :: {
		active: boolean,
		_gui: ScreenGui,
		_baseFov: number,
		_baseSensitivity: number,
	},
	Scope
))

local BLACK = Color3.new(0, 0, 0)

local function frame(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = BLACK
	f.BorderSizePixel = 0
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

	-- The hole is a square of side `2 * HOLE` scale units, centred.
	local HOLE = 0.30 -- half-height of the aperture, in scale units

	-- Sides. Left and right are sized in scale so they work at any aspect.
	local top = frame(gui, "Top")
	top.Size = UDim2.new(1, 0, 0.5 - HOLE, 0)
	top.Position = UDim2.new(0, 0, 0, 0)

	local bottom = frame(gui, "Bottom")
	bottom.Size = UDim2.new(1, 0, 0.5 - HOLE, 0)
	bottom.Position = UDim2.new(0, 0, 0.5 + HOLE, 0)

	local left = frame(gui, "Left")
	left.Size = UDim2.new(0.5, 0, 2 * HOLE, 0)
	left.Position = UDim2.new(0, 0, 0.5 - HOLE, 0)
	left.AnchorPoint = Vector2.new(0, 0)

	local right = frame(gui, "Right")
	right.Size = UDim2.new(0.5, 0, 2 * HOLE, 0)
	right.Position = UDim2.new(1, 0, 0.5 - HOLE, 0)
	right.AnchorPoint = Vector2.new(1, 0)

	--[[
		The aperture is square at this point. These four bars sit at 45 degrees
		across each corner of it, turning the square into an octagon that reads
		as round once the ring is drawn over it.
	]]
	for index, rotation in { 45, -45, 45, -45 } do
		local corner = frame(gui, `Corner{index}`)
		corner.AnchorPoint = Vector2.new(0.5, 0.5)
		corner.Size = UDim2.new(0, 4000, 0, 4000)
		corner.Rotation = rotation
		local x = if index <= 2 then -1 else 1
		local y = if index % 2 == 1 then -1 else 1
		-- Push each bar out along its diagonal so only its edge crosses the
		-- corner of the aperture.
		corner.Position = UDim2.new(0.5, x * 2000 + x * 30, 0.5, y * 2000 + y * 30)
	end

	-- Aperture edge and reticle sit above the occluder.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(2 * HOLE, 0, 2 * HOLE, 0)
	ring.SizeConstraint = Enum.SizeConstraint.RelativeYY
	ring.BackgroundTransparency = 1
	ring.ZIndex = 3
	ring.Parent = gui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 26
	stroke.Color = BLACK
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring

	local edge = Instance.new("UIStroke")
	edge.Thickness = 2
	edge.Color = Color3.fromRGB(28, 28, 26)
	edge.Parent = ring

	-- Crosshair: two hairlines with a gap at the centre, plus range ticks.
	local function hair(name: string, size: UDim2, position: UDim2)
		local h = Instance.new("Frame")
		h.Name = name
		h.AnchorPoint = Vector2.new(0.5, 0.5)
		h.Size = size
		h.Position = position
		h.BackgroundColor3 = Color3.fromRGB(16, 16, 15)
		h.BorderSizePixel = 0
		h.ZIndex = 4
		h.Parent = gui
	end

	hair("HairLeft", UDim2.new(0.24, 0, 0, 2), UDim2.fromScale(0.38, 0.5))
	hair("HairRight", UDim2.new(0.24, 0, 0, 2), UDim2.fromScale(0.62, 0.5))
	hair("HairTop", UDim2.new(0, 2, 0.20, 0), UDim2.fromScale(0.5, 0.38))
	hair("HairBottom", UDim2.new(0, 2, 0.20, 0), UDim2.fromScale(0.5, 0.62))

	for i = 1, 3 do
		hair(`Tick{i}`, UDim2.new(0, 14, 0, 2), UDim2.fromScale(0.5, 0.5 + i * 0.045))
	end

	local camera = workspace.CurrentCamera
	return setmetatable({
		active = false,
		_gui = gui,
		_baseFov = if camera then camera.FieldOfView else 70,
		_baseSensitivity = UserInputService.MouseDeltaSensitivity,
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
		TweenService:Create(camera, TweenInfo.new(0.16), {
			FieldOfView = stats.FieldOfView,
		}):Play()
	else
		self._gui.Enabled = false
		UserInputService.MouseDeltaSensitivity = Config.Camera.Sensitivity
		TweenService:Create(camera, TweenInfo.new(0.14), {
			FieldOfView = self._baseFov,
		}):Play()
	end
end

--- Drops the scope if the weapon is put away or the character dies.
function Scope.enforce(self: Scope, stillValid: boolean)
	if self.active and not stillValid then
		self:set(false)
	end
end

return Scope
