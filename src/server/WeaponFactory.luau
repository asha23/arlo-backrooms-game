--!strict
--[[
	Builds Tool instances for each weapon from primitives, so the repo has no
	binary model dependencies. Swap `buildModel` for a real mesh later without
	touching anything else.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local WeaponFactory = {}

local function part(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Metal
	p.CanCollide = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--- Welds a cosmetic part to the handle at the given offset.
local function attach(handle: BasePart, piece: BasePart, offset: CFrame)
	piece.CFrame = handle.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = piece
	weld.Parent = handle
end

function WeaponFactory.create(weaponId: string): Tool?
	local stats = WeaponConfig.Weapons[weaponId]
	if not stats then
		warn(`[WeaponFactory] unknown weapon '{weaponId}'`)
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = stats.Name
	tool.CanBeDropped = true
	tool.RequiresHandle = true
	tool.ToolTip = `{stats.Name} — {stats.Damage} dmg`
	-- Grip rotation so the barrel points forward out of the hand.
	tool.GripForward = Vector3.new(0, 0, -1)
	tool.GripRight = Vector3.new(1, 0, 0)
	tool.GripUp = Vector3.new(0, 1, 0)
	tool.GripPos = Vector3.new(0, -0.2, 0.4)

	-- The weapon id, so the server can look stats up from the tool alone.
	local idTag = Instance.new("StringValue")
	idTag.Name = "WeaponId"
	idTag.Value = weaponId
	idTag.Parent = tool

	local handle = part("Handle", stats.HandleSize, stats.HandleColor, tool)

	-- A barrel and a grip, purely so the three weapons read differently in hand.
	local barrel = part(
		"Barrel",
		Vector3.new(0.22, 0.22, stats.HandleSize.Z * 0.9),
		stats.HandleColor:Lerp(Color3.new(0, 0, 0), 0.4),
		tool
	)
	attach(handle, barrel, CFrame.new(0, stats.HandleSize.Y * 0.35, -stats.HandleSize.Z * 0.45))

	local grip = part("Grip", Vector3.new(0.3, 0.7, 0.4), Color3.fromRGB(30, 30, 32), tool)
	attach(handle, grip, CFrame.new(0, -stats.HandleSize.Y * 0.5, stats.HandleSize.Z * 0.3))

	-- Muzzle attachment: where tracers originate.
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, stats.HandleSize.Y * 0.35, -stats.HandleSize.Z * 0.95)
	muzzle.Parent = handle

	return tool
end

return WeaponFactory
