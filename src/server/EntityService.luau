--!strict
--[[
	Spawns and drives the hostiles.

	Each entity is a plain Humanoid rig built from parts, so it takes damage
	through the same `Humanoid:TakeDamage` path a player would. Navigation uses
	PathfindingService, because a maze defeats naive "walk straight at the
	target" AI — it just grinds into a wall and stays there.
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EntitySounds = require(script.Parent.EntitySounds)

local SETTINGS = Config.Entity

export type Variant = typeof(SETTINGS.Variants[1])

local EntityService = {}

local openPositions: { Vector3 } = {}
local alive = 0
local rng = Random.new()

local function newPart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--[[
	Builds the rig.

	The part names matter: Roblox's Humanoid requires "HumanoidRootPart",
	"Torso" and "Head" spelled exactly this way to assemble and walk, and the
	headshot check in WeaponService keys off "Head".

	Proportions are deliberately wrong for a person — roughly ten studs tall on
	a torso less than a stud deep, with arms that reach the shins. Joint offsets
	are computed from the configured sizes rather than hardcoded, so the rig
	stays assembled if you retune the build in Config.
]]
local function buildRig(variant: Variant): Model
	local build = variant.Build

	local model = Instance.new("Model")
	model.Name = variant.Id

	local torsoSize = build.TorsoSize
	local headSize = build.HeadSize
	local armSize = build.ArmSize
	local legSize = build.LegSize

	-- The root must match the torso so the physics assembly lines up.
	local root = newPart("HumanoidRootPart", torsoSize, build.BodyColor, model)
	root.Transparency = 1
	root.CanCollide = false

	local torso = newPart("Torso", torsoSize, build.BodyColor, model)
	local head = newPart("Head", headSize, build.HeadColor, model)
	local leftArm = newPart("Left Arm", armSize, build.LimbColor, model)
	local rightArm = newPart("Right Arm", armSize, build.LimbColor, model)
	local leftLeg = newPart("Left Leg", legSize, build.LimbColor, model)
	local rightLeg = newPart("Right Leg", legSize, build.LimbColor, model)

	-- No face at all. A blank head is worse than an angry one.
	head.Material = Enum.Material.SmoothPlastic
	head.Reflectance = build.HeadReflectance

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = variant.Health
	humanoid.Health = variant.Health
	humanoid.WalkSpeed = variant.WalkSpeed
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HipHeight = legSize.Y - torsoSize.Y / 2
	humanoid.Parent = model

	local function joint(
		name: string,
		part0: BasePart,
		part1: BasePart,
		c0: CFrame,
		c1: CFrame
	): Motor6D
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = c0
		motor.C1 = c1
		motor.Parent = part0
		return motor
	end

	joint("RootJoint", root, torso, CFrame.identity, CFrame.identity)

	-- Head sits on top of the torso.
	joint("Neck", torso, head, CFrame.new(0, torsoSize.Y / 2, 0), CFrame.new(0, -headSize.Y / 2, 0))

	-- Arms hang from the shoulders, straight down.
	local shoulderY = torsoSize.Y / 2 - armSize.X / 2
	local shoulderX = torsoSize.X / 2 + armSize.X / 2
	local armDrop = CFrame.new(0, armSize.Y / 2 - armSize.X / 2, 0)
	joint("Left Shoulder", torso, leftArm, CFrame.new(-shoulderX, shoulderY, 0), armDrop)
	joint("Right Shoulder", torso, rightArm, CFrame.new(shoulderX, shoulderY, 0), armDrop)

	-- Legs hang from the hips.
	local hipX = legSize.X * 0.75
	local legDrop = CFrame.new(0, legSize.Y / 2, 0)
	joint("Left Hip", torso, leftLeg, CFrame.new(-hipX, -torsoSize.Y / 2, 0), legDrop)
	joint("Right Hip", torso, rightLeg, CFrame.new(hipX, -torsoSize.Y / 2, 0), legDrop)

	--[[
		Tendrils. Welded rather than jointed: they're scenery hanging off the
		back, not limbs the Humanoid should try to animate. Splayed slightly so
		the silhouette reads as more than one line, and long enough to trail
		near the floor.
	]]
	local tendrilCount = variant.Tendrils or 0
	if tendrilCount > 0 then
		local size = (variant :: any).TendrilSize :: Vector3
		local color = (variant :: any).TendrilColor :: Color3
		for index = 1, tendrilCount do
			-- Fan them across the back, alternating left and right.
			local spread = ((index - 1) / math.max(tendrilCount - 1, 1)) - 0.5
			local tendril = newPart(`Tendril{index}`, size, color, model)
			tendril.CanCollide = false
			tendril.Massless = true

			local offset = CFrame.new(
				spread * torsoSize.X * 1.4,
				-size.Y / 2 + torsoSize.Y / 2,
				torsoSize.Z
			) * CFrame.Angles(math.rad(-14), 0, math.rad(spread * 40))
			tendril.CFrame = torso.CFrame * offset

			local weld = Instance.new("Weld")
			weld.Part0 = torso
			weld.Part1 = tendril
			weld.C0 = offset
			weld.C1 = CFrame.identity
			weld.Parent = torso
		end
	end

	model.PrimaryPart = root
	return model
end

--[[
	A slow sway on the neck and shoulders. Costs one CFrame per joint per tick
	and does more for the impression of something alive than a walk cycle would:
	it never stops, even when the thing is standing still watching you.
]]
local function swayRig(model: Model)
	local torso = model:FindFirstChild("Torso") :: BasePart?
	if not torso then
		return
	end
	local neck = torso:FindFirstChild("Neck") :: Motor6D?
	local leftShoulder = torso:FindFirstChild("Left Shoulder") :: Motor6D?
	local rightShoulder = torso:FindFirstChild("Right Shoulder") :: Motor6D?

	local baseNeck = if neck then neck.C0 else nil
	local baseLeft = if leftShoulder then leftShoulder.C0 else nil
	local baseRight = if rightShoulder then rightShoulder.C0 else nil

	task.spawn(function()
		local elapsed = rng:NextNumber(0, SETTINGS.SwayPeriod)
		while model.Parent do
			local delta = task.wait(0.06)
			elapsed += delta
			local wave = math.sin((elapsed / SETTINGS.SwayPeriod) * math.pi * 2)
			local angle = math.rad(SETTINGS.SwayAngle) * wave

			if neck and baseNeck then
				neck.C0 = baseNeck * CFrame.Angles(0, angle * 0.6, angle * 0.4)
			end
			if leftShoulder and baseLeft then
				leftShoulder.C0 = baseLeft * CFrame.Angles(angle, 0, 0)
			end
			if rightShoulder and baseRight then
				rightShoulder.C0 = baseRight * CFrame.Angles(-angle, 0, 0)
			end
		end
	end)
end

local function nearestPlayer(position: Vector3): (Player?, number)
	local best: Player? = nil
	local bestDistance = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			continue
		end
		local distance = (root.Position - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = player, distance
		end
	end
	return best, bestDistance
end

--- Walks the entity along a computed path. Returns false if the path failed.
local function followPath(model: Model, humanoid: Humanoid, goal: Vector3): boolean
	local root = model.PrimaryPart
	if not root then
		return false
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 11,
		AgentCanJump = false,
	})

	local ok = pcall(function()
		path:ComputeAsync(root.Position, goal)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return false
	end

	for _, waypoint in path:GetWaypoints() do
		if humanoid.Health <= 0 or not model.Parent then
			return false
		end
		humanoid:MoveTo(waypoint.Position)
		local reached = humanoid.MoveToFinished:Wait()
		if not reached then
			return false -- blocked or timed out; recompute next tick
		end
	end
	return true
end

local function runAi(model: Model, sounds: EntitySounds.EntitySounds, variant: Variant)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart
	local lastAttack = 0
	local lastSeenAt: Vector3? = nil
	local lostAt = 0
	local lastTick = os.clock()

	while model.Parent and humanoid.Health > 0 do
		local target, distance = nearestPlayer(root.Position)
		local now = os.clock()
		sounds:update(now - lastTick, target ~= nil and distance <= SETTINGS.SightRange)
		lastTick = now

		if target and distance <= SETTINGS.SightRange then
			local character = target.Character
			local targetRoot = character
				and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if targetRoot then
				lastSeenAt = targetRoot.Position
				lostAt = os.clock()
				humanoid.WalkSpeed = variant.ChaseSpeed

				if distance <= SETTINGS.AttackRange then
					local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
					if targetHumanoid and os.clock() - lastAttack >= SETTINGS.AttackCooldown then
						lastAttack = os.clock()
						targetHumanoid:TakeDamage(SETTINGS.AttackDamage)
					end
					humanoid:MoveTo(targetRoot.Position)
					task.wait(0.2)
					continue
				end

				followPath(model, humanoid, targetRoot.Position)
				continue
			end
		end

		-- Lost them: search the last known position for a while, then wander.
		if lastSeenAt and os.clock() - lostAt < SETTINGS.SearchTime then
			followPath(model, humanoid, lastSeenAt)
		else
			lastSeenAt = nil
			humanoid.WalkSpeed = variant.WalkSpeed
			if #openPositions > 0 then
				followPath(model, humanoid, openPositions[rng:NextInteger(1, #openPositions)])
			else
				task.wait(1)
			end
		end
	end
end

--- Picks a spawn far enough from every player to not appear on top of them.
local function chooseSpawn(): Vector3?
	if #openPositions == 0 then
		return nil
	end
	for _ = 1, 40 do
		local candidate = openPositions[rng:NextInteger(1, #openPositions)]
		local _, distance = nearestPlayer(candidate)
		if distance >= SETTINGS.MinSpawnDistance and distance <= SETTINGS.MaxSpawnDistance then
			return candidate
		end
	end
	return nil
end

--- Picks a variant by relative weight.
local function chooseVariant(): Variant
	local total = 0
	for _, variant in SETTINGS.Variants do
		total += variant.Weight
	end
	local roll = rng:NextNumber(0, total)
	for _, variant in SETTINGS.Variants do
		roll -= variant.Weight
		if roll <= 0 then
			return variant
		end
	end
	return SETTINGS.Variants[1]
end

local function spawnOne(folder: Folder)
	local position = chooseSpawn()
	if not position then
		return
	end

	local variant = chooseVariant()
	local model = buildRig(variant)
	local standingHeight = variant.Build.LegSize.Y + variant.Build.TorsoSize.Y / 2
	model:PivotTo(CFrame.new(position + Vector3.new(0, standingHeight + 0.5, 0)))
	model.Parent = folder
	alive += 1

	local torso = model:FindFirstChild("Torso") :: BasePart
	local sounds = EntitySounds.attach(torso, variant.Id)
	swayRig(model)

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		alive -= 1
		sounds:playDeath()
		-- Long enough for the death cry to finish before the body vanishes.
		task.delay(SETTINGS.RespawnDelay, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end)

	task.spawn(runAi, model, sounds, variant)
end

--- `positions` are the world-space centres of open floor cells.
function EntityService.start(positions: { Vector3 })
	openPositions = positions

	local folder = Instance.new("Folder")
	folder.Name = "Entities"
	folder.Parent = workspace

	task.spawn(function()
		while true do
			task.wait(SETTINGS.SpawnInterval)
			-- Only populate the maze while somebody is in it.
			if alive < SETTINGS.MaxAlive and #Players:GetPlayers() > 0 then
				spawnOne(folder)
			end
		end
	end)

	print("[Entities] service started")
end

return EntityService
