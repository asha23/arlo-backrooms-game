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
	-- For a custom rig this is the gap between the bottom of the RootPart and
	-- the floor, which is exactly the leg length.
	humanoid.HipHeight = legSize.Y
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

--[[
	Every entity currently alive, so a sighting by one can be shared with the
	rest. This is what makes them hunt as a pack rather than as a scattering of
	independent wanderers.
]]
type Brain = {
	lastSeenAt: Vector3?,
	lostAt: number,
	alerted: boolean,
}

local brains: { [Model]: Brain } = {}

--- Tells every nearby entity where a player was just seen.
local function broadcastAlert(origin: Vector3, position: Vector3, source: Model)
	local radiusSquared = SETTINGS.AlertRadius ^ 2
	for model, brain in brains do
		if model == source or not model.Parent then
			continue
		end
		local root = model.PrimaryPart
		if not root or (root.Position - origin).Magnitude ^ 2 > radiusSquared then
			continue
		end
		brain.lastSeenAt = position
		brain.lostAt = os.clock()
		brain.alerted = true
	end
end

--[[
	Walks the entity towards `goal`.

	AgentHeight is the headroom the NAVMESH needs, not the entity's visual
	height. It was previously set to the entity's own height (11 studs) inside a
	level with exactly 12 studs of clearance, so ComputeAsync failed almost
	everywhere — and a failed path left the entity standing still, which is
	exactly the "they don't move" symptom. It is now sized to the space.

	When pathfinding fails anyway we fall back to walking straight at the goal.
	That's wrong in a maze but right in a corridor, and something moving badly
	beats something not moving at all. The fallback yields, so a caller looping
	on this can never spin.

	Returns false if the walk was interrupted, so the caller can re-plan.
]]
local function followPath(model: Model, humanoid: Humanoid, goal: Vector3): boolean
	local root = model.PrimaryPart
	if not root then
		return false
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = 1.8,
		AgentHeight = 5,
		AgentCanJump = false,
		WaypointSpacing = 6,
	})

	local ok = pcall(function()
		path:ComputeAsync(root.Position, goal)
	end)

	if not ok or path.Status ~= Enum.PathStatus.Success then
		humanoid:MoveTo(goal)
		task.wait(0.35)
		return false
	end

	for index, waypoint in path:GetWaypoints() do
		if humanoid.Health <= 0 or not model.Parent then
			return false
		end

		humanoid:MoveTo(waypoint.Position)
		if not humanoid.MoveToFinished:Wait() then
			return false -- blocked or timed out; re-plan next tick
		end

		--[[
			Re-plan partway rather than walking the path out. A route computed
			to where someone stood five seconds ago is stale, and following it
			to the end makes the entity look like it's patrolling rather than
			chasing.
		]]
		if index >= 3 then
			return true
		end
	end
	return true
end

local function runAi(model: Model, sounds: EntitySounds.EntitySounds, variant: Variant)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart
	local brain: Brain = { lastSeenAt = nil, lostAt = 0, alerted = false }
	brains[model] = brain

	local lastAttack = 0
	local lastTick = os.clock()

	while model.Parent and humanoid.Health > 0 do
		local target, distance = nearestPlayer(root.Position)
		local now = os.clock()
		local canSee = target ~= nil and distance <= SETTINGS.SightRange
		sounds:update(now - lastTick, canSee or brain.alerted)
		lastTick = now

		local character = target and target.Character
		local targetRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

		if canSee and targetRoot then
			brain.lastSeenAt = targetRoot.Position
			brain.lostAt = now
			brain.alerted = true
			-- Bring the pack.
			broadcastAlert(root.Position, targetRoot.Position, model)
			humanoid.WalkSpeed = variant.ChaseSpeed

			if distance <= SETTINGS.AttackRange then
				local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
				if targetHumanoid and now - lastAttack >= SETTINGS.AttackCooldown then
					lastAttack = now
					targetHumanoid:TakeDamage(SETTINGS.AttackDamage)
				end
				humanoid:MoveTo(targetRoot.Position)
				task.wait(0.25)
				continue
			end

			followPath(model, humanoid, targetRoot.Position)
			continue
		end

		--[[
			Nobody in view. Either converge on the last known position — which
			may have come from another entity's sighting, and is what makes a
			group arrive together — or wander.
		]]
		local memory = brain.lastSeenAt
		if memory and now - brain.lostAt < SETTINGS.SearchTime then
			humanoid.WalkSpeed = variant.ChaseSpeed
			followPath(model, humanoid, memory)
		else
			brain.lastSeenAt = nil
			brain.alerted = false
			humanoid.WalkSpeed = variant.WalkSpeed
			if #openPositions > 0 then
				followPath(model, humanoid, openPositions[rng:NextInteger(1, #openPositions)])
			else
				task.wait(1)
			end
		end

		-- Guaranteed yield. Without it, any path that fails without yielding
		-- turns this loop into a tight spin that starves the scheduler.
		task.wait(0.05)
	end

	brains[model] = nil
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

local function spawnOne(folder: Folder, position: Vector3)
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

--[[
	Spawns a small group in one place rather than one entity somewhere random.

	Meeting three of them coming down the same corridor is a different
	experience from meeting one, and it's the group that makes the alert
	broadcast worth having — a pack that already starts together converges
	faster than one assembled from across the level.
]]
local function spawnGroup(folder: Folder)
	local anchor = chooseSpawn()
	if not anchor then
		return
	end

	local size = rng:NextInteger(SETTINGS.GroupSize[1], SETTINGS.GroupSize[2])
	size = math.min(size, SETTINGS.MaxAlive - alive)
	if size <= 0 then
		return
	end

	-- Open cells near the anchor, gathered once. Snapping to a real cell is
	-- what keeps a group member from starting inside a wall.
	local nearby: { Vector3 } = {}
	local radiusSquared = SETTINGS.GroupRadius ^ 2
	for _, candidate in openPositions do
		if (candidate - anchor).Magnitude ^ 2 <= radiusSquared then
			table.insert(nearby, candidate)
		end
	end

	for _ = 1, size do
		local position = if #nearby > 0 then nearby[rng:NextInteger(1, #nearby)] else anchor
		spawnOne(folder, position)
	end
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
				spawnGroup(folder)
			end
		end
	end)

	print("[Entities] service started")
end

return EntityService
