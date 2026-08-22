--!strict
--[[
	Floating damage figures.

	Pooled, for the same reason the tracers are: the machine gun lands eleven
	hits a second and building a BillboardGui and a Part per hit would churn
	instances exactly as the old shot effects did. A fixed set is created once
	and cycled; a number still fading when its slot comes round is simply reset,
	which at that rate reads as one continuous stream anyway.

	Only the shooter sees their own numbers. Everyone's damage floating over
	everyone's targets would be noise, and the information is only useful to the
	person who caused it.
]]

local RunService = game:GetService("RunService")

local DamageNumbers = {}

local POOL_SIZE = 14
local RISE = 4.2 -- studs travelled while fading
local LIFETIME = 0.75

local NORMAL = Color3.fromRGB(255, 238, 200)
local CRITICAL = Color3.fromRGB(255, 96, 84)

type Marker = {
	part: Part,
	label: TextLabel,
	origin: Vector3,
	born: number,
	active: boolean,
}

local pool: { Marker } = {}
local nextIndex = 1
local started = false

local function makeMarker(): Marker
	local part = Instance.new("Part")
	part.Name = "DamageNumber"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 40)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 220
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0.35
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = billboard

	return { part = part, label = label, origin = Vector3.zero, born = 0, active = false }
end

--- Shows a figure at a world position. `critical` covers headshots and kills.
function DamageNumbers.show(position: Vector3, amount: number, critical: boolean)
	if not started then
		return
	end

	local marker = pool[nextIndex]
	nextIndex = nextIndex % #pool + 1

	-- A little horizontal scatter, so rapid hits on the same spot don't stack
	-- into one illegible smear.
	marker.origin = position + Vector3.new(math.random(-8, 8) / 10, 0, math.random(-8, 8) / 10)
	marker.born = os.clock()
	marker.active = true

	marker.label.Text = tostring(math.floor(amount + 0.5))
	marker.label.TextColor3 = if critical then CRITICAL else NORMAL
	marker.label.TextTransparency = 0
	marker.part.CFrame = CFrame.new(marker.origin)
end

function DamageNumbers.start()
	if started then
		return
	end
	for _ = 1, POOL_SIZE do
		table.insert(pool, makeMarker())
	end
	started = true

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for _, marker in pool do
			if not marker.active then
				continue
			end

			local age = (now - marker.born) / LIFETIME
			if age >= 1 then
				marker.active = false
				marker.label.TextTransparency = 1
				continue
			end

			-- Rises quickly then slows, and fades over the back half only, so
			-- the number is fully legible before it starts disappearing.
			local eased = 1 - (1 - age) * (1 - age)
			marker.part.CFrame = CFrame.new(marker.origin + Vector3.new(0, RISE * eased, 0))
			marker.label.TextTransparency = math.clamp((age - 0.45) / 0.55, 0, 1)
		end
	end)
end

return DamageNumbers
