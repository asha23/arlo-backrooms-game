--!strict
--[[
	Spawns and drives the hostiles.

	Each entity is a plain Humanoid rig built from parts, so it takes damage
	through the same `Humanoid:TakeDamage` path a player would. Navigation uses
	PathfindingService, because a maze defeats naive "walk straight at the
	target" AI — it just grinds into a wall and stays there.
]]

local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashService = require(script.Parent.CashService)
local Config = require(ReplicatedStorage.Shared.Config)
local EntitySounds = require(script.Parent.EntitySounds)
local MatchService = require(script.Parent.MatchService)

local SETTINGS = Config.Entity

export type Variant = typeof(SETTINGS.Variants[1])

local EntityService = {}

local openPositions: { Vector3 } = {}
local alive = 0
local rng = Random.new()

--[[
	Entities collide with the level and with players, but never with each other.

	Without this, two of them meeting in a nine-stud corridor shove each other
	around, and — far worse — two spawning on the same tile stack vertically,
	which is what put them up by the ceiling.
]]
local COLLISION_GROUP = "Entities"

local function ensureCollisionGroup()
	-- Registering twice throws, and this may run on a warm server.
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
	end)
end

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

	--[[
		The root is the ONLY collider. Every visual limb is CanCollide false and
		massless.

		With colliding legs the Humanoid fights its own geometry: it tries to
		hold the root at HipHeight above the floor while the leg parts prop the
		body up from below, and the two settle at different heights. The result
		is a rig that hovers, jitters, or sinks. One collider and cosmetic limbs
		is the standard shape for a custom-proportioned rig.
	]]
	local root = newPart("HumanoidRootPart", torsoSize, build.BodyColor, model)
	root.Transparency = 1
	root.CanCollide = true
	root.CollisionGroup = COLLISION_GROUP

	local torso = newPart("Torso", torsoSize, build.BodyColor, model)
	local head = newPart("Head", headSize, build.HeadColor, model)
	local leftArm = newPart("Left Arm", armSize, build.LimbColor, model)
	local rightArm = newPart("Right Arm", armSize, build.LimbColor, model)
	local leftLeg = newPart("Left Leg", legSize, build.LimbColor, model)
	local rightLeg = newPart("Right Leg", legSize, build.LimbColor, model)

	for _, limb in { torso, head, leftArm, rightArm, leftLeg, rightLeg } do
		limb.CanCollide = false
		limb.Massless = true
	end

	head.Material = Enum.Material.SmoothPlastic
	head.Reflectance = build.HeadReflectance

	--[[
		Eyes, and nothing else — no mouth, no nose. Two marks on an otherwise
		blank head suggest a face without providing one, which is worse.

		"Auto" chooses by the head's own brightness: a dark head gets eyes that
		glow out of it, a pale head gets eyes that read as holes punched into
		it. Rec. 709 luma, because a green head and a blue head of the same
		numeric value do not look equally bright.
	]]
	local luma = 0.2126 * build.HeadColor.R
		+ 0.7152 * build.HeadColor.G
		+ 0.0722 * build.HeadColor.B
	local glowing = if build.EyeStyle == "Glow"
		then true
		elseif build.EyeStyle == "Black" then false
		else luma < 0.45

	for _, side in { -1, 1 } do
		local eye = newPart(
			"Eye",
			Vector3.new(headSize.X * 0.22, headSize.Y * 0.16, 0.08),
			if glowing then build.EyeGlowColor else Color3.fromRGB(6, 6, 8),
			model
		)
		eye.CanCollide = false
		eye.Massless = true
		eye.Material = if glowing then Enum.Material.Neon else Enum.Material.SmoothPlastic

		-- Front face of the head is -Z.
		local offset =
			CFrame.new(side * headSize.X * 0.24, headSize.Y * 0.12, -headSize.Z / 2 - 0.04)
		eye.CFrame = head.CFrame * offset

		local weld = Instance.new("Weld")
		weld.Part0 = head
		weld.Part1 = eye
		weld.C0 = offset
		weld.C1 = CFrame.identity
		weld.Parent = head

		if glowing then
			-- Just enough to catch on the wall beside it in a dark corridor.
			local light = Instance.new("PointLight")
			light.Color = build.EyeGlowColor
			light.Brightness = 0.7
			light.Range = 7
			light.Parent = eye
		end
	end

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

	local worth = Instance.new("IntValue")
	worth.Name = "ScoreValue"
	worth.Value = variant.Score
	worth.Parent = model

	model.PrimaryPart = root
	return model
end

--[[
	Corrects the rig's standing height from measured geometry.

	The joint maths says HipHeight should equal the leg length, and on paper the
	feet land exactly on the floor. But R6's handling of HipHeight is not
	something to take on trust with non-standard proportions, so rather than
	assume, this measures: raycast down for the real floor, find the lowest
	point of the assembled rig, and close the gap. It converges in a couple of
	passes and costs nothing afterwards.

	It also means retuning proportions in Config can't silently leave entities
	hovering — the correction just absorbs it.
]]
local function groundRig(model: Model, humanoid: Humanoid)
	local root = model.PrimaryPart
	if not root then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }

	for _ = 1, 6 do
		task.wait(0.15)
		if not model.Parent or humanoid.Health <= 0 then
			return
		end

		local hit = workspace:Raycast(root.Position, Vector3.new(0, -40, 0), params)
		if not hit then
			continue
		end

		-- Lowest point of anything visible, so the feet are what land.
		local lowest = math.huge
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2)
			end
		end
		if lowest == math.huge then
			return
		end

		local gap = lowest - hit.Position.Y
		if math.abs(gap) < 0.2 then
			return -- standing correctly
		end
		humanoid.HipHeight = math.max(0, humanoid.HipHeight - gap)
	end
end

--[[
	Procedural walk cycle.

	Roblox will only animate a rig given an Animator plus an uploaded animation
	asset. Driving the Motor6D joints directly needs neither, and because the
	phase advances with distance travelled rather than with time, the stride
	stays correct whether the thing is ambling or sprinting at you.

	Standing still falls back to a slow sway, so an idle entity never reads as
	a prop.
]]
local function animateRig(model: Model, humanoid: Humanoid)
	local torso = model:FindFirstChild("Torso") :: BasePart?
	local root = model.PrimaryPart
	if not torso or not root then
		return
	end

	local joints = {
		leftHip = torso:FindFirstChild("Left Hip") :: Motor6D?,
		rightHip = torso:FindFirstChild("Right Hip") :: Motor6D?,
		leftShoulder = torso:FindFirstChild("Left Shoulder") :: Motor6D?,
		rightShoulder = torso:FindFirstChild("Right Shoulder") :: Motor6D?,
		neck = torso:FindFirstChild("Neck") :: Motor6D?,
	}

	-- Rest pose, captured before anything is animated. Written out rather than
	-- looped so each field keeps its type.
	local base = {
		leftHip = if joints.leftHip then joints.leftHip.C0 else nil,
		rightHip = if joints.rightHip then joints.rightHip.C0 else nil,
		leftShoulder = if joints.leftShoulder then joints.leftShoulder.C0 else nil,
		rightShoulder = if joints.rightShoulder then joints.rightShoulder.C0 else nil,
		neck = if joints.neck then joints.neck.C0 else nil,
	}

	local swing = math.rad(SETTINGS.SwingAngle)
	local armRatio = SETTINGS.ArmSwingRatio
	local stride = SETTINGS.StrideLength

	task.spawn(function()
		local phase = rng:NextNumber(0, math.pi * 2)
		local swayClock = rng:NextNumber(0, SETTINGS.SwayPeriod)
		local lastPosition = root.Position

		while model.Parent and humanoid.Health > 0 do
			local delta = task.wait(0.04)
			local position = root.Position
			-- Horizontal distance only; falling shouldn't drive a walk cycle.
			local travelled = (Vector3.new(position.X, 0, position.Z) - Vector3.new(
				lastPosition.X,
				0,
				lastPosition.Z
			)).Magnitude
			lastPosition = position

			if travelled > 0.02 then
				phase += (travelled / stride) * math.pi
				local wave = math.sin(phase)

				-- Legs swing in opposition; arms counter-swing against them.
				if joints.leftHip and base.leftHip then
					joints.leftHip.C0 = base.leftHip * CFrame.Angles(swing * wave, 0, 0)
				end
				if joints.rightHip and base.rightHip then
					joints.rightHip.C0 = base.rightHip * CFrame.Angles(-swing * wave, 0, 0)
				end
				if joints.leftShoulder and base.leftShoulder then
					joints.leftShoulder.C0 = base.leftShoulder
						* CFrame.Angles(-swing * armRatio * wave, 0, 0)
				end
				if joints.rightShoulder and base.rightShoulder then
					joints.rightShoulder.C0 = base.rightShoulder
						* CFrame.Angles(swing * armRatio * wave, 0, 0)
				end
				if joints.neck and base.neck then
					-- A small bob, a quarter of the leg swing and twice as fast.
					joints.neck.C0 = base.neck
						* CFrame.Angles(0, 0, swing * 0.12 * math.sin(phase * 2))
				end
			else
				swayClock += delta
				local wave = math.sin((swayClock / SETTINGS.SwayPeriod) * math.pi * 2)
				local angle = math.rad(SETTINGS.SwayAngle) * wave
				if joints.neck and base.neck then
					joints.neck.C0 = base.neck * CFrame.Angles(0, angle * 0.6, angle * 0.4)
				end
				if joints.leftShoulder and base.leftShoulder then
					joints.leftShoulder.C0 = base.leftShoulder * CFrame.Angles(angle, 0, 0)
				end
				if joints.rightShoulder and base.rightShoulder then
					joints.rightShoulder.C0 = base.rightShoulder * CFrame.Angles(-angle, 0, 0)
				end
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

		--[[
			Cull anything that has drifted out of everyone's world. Pathfinding
			an empty corridor nobody can see is pure server cost, and the freed
			slot gets respawned somewhere a player will actually meet it.
		]]
		if distance > SETTINGS.DespawnDistance then
			brains[model] = nil
			alive -= 1
			model:Destroy()
			return
		end

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

			--[[
				Attack range is measured horizontally. These things stand ten
				studs tall, so their root sits well above the player's — a
				straight 3D distance would keep reporting them as out of reach
				while they were standing right on top of someone.
			]]
			local flat = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(
				targetRoot.Position.X,
				0,
				targetRoot.Position.Z
			)).Magnitude

			if flat <= SETTINGS.AttackRange then
				local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
				if targetHumanoid and now - lastAttack >= SETTINGS.AttackCooldown then
					lastAttack = now
					targetHumanoid:TakeDamage(SETTINGS.AttackDamage)
				end
				humanoid:MoveTo(targetRoot.Position)
				task.wait(0.15)
				continue
			end

			--[[
				Close in: stop pathfinding and simply come at them. Computing a
				route every few studs is both expensive and slow to react, and
				at this range there is rarely a wall in the way — the hesitation
				it caused was the main reason they never actually reached
				anyone.
			]]
			if flat <= SETTINGS.LungeRange then
				humanoid:MoveTo(targetRoot.Position)
				task.wait(0.12)
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

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	animateRig(model, humanoid)
	task.spawn(groundRig, model, humanoid)

	humanoid.Died:Connect(function()
		alive -= 1
		sounds:playDeath()

		-- Drop the bounty where it fell, at floor level rather than at the
		-- root, which on a ten-stud rig is chest height on a ladder.
		local root = model.PrimaryPart
		if root then
			CashService.drop(Vector3.new(root.Position.X, position.Y, root.Position.Z))
		end
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

	--[[
		Open cells near the anchor, gathered once. Snapping to a real cell keeps
		a group member from starting inside a wall.

		Cells are then drawn WITHOUT replacement. Drawing with replacement meant
		two members of a group routinely got the same tile — and since the root
		is the collider, the second one spawned inside the first and popped out
		on top of it. A few of those stacked and they ended up at the ceiling.
	]]
	local nearby: { Vector3 } = {}
	local radiusSquared = SETTINGS.GroupRadius ^ 2
	for _, candidate in openPositions do
		if (candidate - anchor).Magnitude ^ 2 <= radiusSquared then
			table.insert(nearby, candidate)
		end
	end

	-- Don't reuse a tile something is already standing on.
	for model in brains do
		local root = model.PrimaryPart
		if not root then
			continue
		end
		for index = #nearby, 1, -1 do
			if (nearby[index] - root.Position).Magnitude < 6 then
				table.remove(nearby, index)
			end
		end
	end

	for _ = 1, size do
		if #nearby == 0 then
			break -- no clear tile left nearby; better to spawn fewer
		end
		local index = rng:NextInteger(1, #nearby)
		local position = nearby[index]
		table.remove(nearby, index)
		spawnOne(folder, position)
	end
end

--- `positions` are the world-space centres of open floor cells.
function EntityService.start(positions: { Vector3 })
	openPositions = positions
	ensureCollisionGroup()

	local folder = Instance.new("Folder")
	folder.Name = "Entities"
	folder.Parent = workspace

	task.spawn(function()
		while true do
			task.wait(SETTINGS.SpawnInterval)
			--[[
				Nothing spawns until the countdown has finished for at least
				one player. Hunting somebody who is still watching a loading
				screen is not a fair start.
			]]
			if alive < SETTINGS.MaxAlive and MatchService.isLive() then
				spawnGroup(folder)
			end
		end
	end)

	print("[Entities] service started")
end

return EntityService
