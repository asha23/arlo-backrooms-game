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

local BODY_COLOR = Color3.fromRGB(228, 222, 205)
local LIMB_COLOR = Color3.fromRGB(198, 190, 172)

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
	Builds a minimal R6-shaped rig. The part names matter: Roblox's Humanoid
	requires "HumanoidRootPart", "Torso" and "Head" to be named exactly this to
	assemble and walk, and our headshot check keys off "Head".
]]
local function buildRig(): Model
	local model = Instance.new("Model")
	model.Name = "Wanderer"

	local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), BODY_COLOR, model)
	root.Transparency = 1
	root.CanCollide = false

	local torso = newPart("Torso", Vector3.new(2, 2, 1), BODY_COLOR, model)
	local head = newPart("Head", Vector3.new(1.4, 1.4, 1.4), BODY_COLOR, model)
	local leftArm = newPart("Left Arm", Vector3.new(1, 2, 1), LIMB_COLOR, model)
	local rightArm = newPart("Right Arm", Vector3.new(1, 2, 1), LIMB_COLOR, model)
	local leftLeg = newPart("Left Leg", Vector3.new(1, 2, 1), LIMB_COLOR, model)
	local rightLeg = newPart("Right Leg", Vector3.new(1, 2, 1), LIMB_COLOR, model)

	-- Faceless: two dark voids where eyes would be.
	for _, side in { -0.35, 0.35 } do
		local eye = newPart("Eye", Vector3.new(0.28, 0.4, 0.1), Color3.fromRGB(12, 12, 12), head)
		eye.CanCollide = false
		eye.Massless = true
		eye.CFrame = head.CFrame * CFrame.new(side, 0.15, -0.72)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = eye
		weld.Parent = head
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = SETTINGS.Health
	humanoid.Health = SETTINGS.Health
	humanoid.WalkSpeed = SETTINGS.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	-- Standard R6 joint layout.
	local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = c0
		motor.C1 = c1
		motor.Parent = part0
	end

	joint("RootJoint", root, torso, CFrame.new(), CFrame.new())
	joint("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.7, 0))
	joint("Left Shoulder", torso, leftArm, CFrame.new(-1.5, 0, 0), CFrame.new())
	joint("Right Shoulder", torso, rightArm, CFrame.new(1.5, 0, 0), CFrame.new())
	joint("Left Hip", torso, leftLeg, CFrame.new(-0.5, -2, 0), CFrame.new())
	joint("Right Hip", torso, rightLeg, CFrame.new(0.5, -2, 0), CFrame.new())

	model.PrimaryPart = root
	return model
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
		AgentHeight = 5,
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

local function runAi(model: Model, sounds: EntitySounds.EntitySounds)
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
				humanoid.WalkSpeed = SETTINGS.ChaseSpeed

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
			humanoid.WalkSpeed = SETTINGS.WalkSpeed
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

local function spawnOne(folder: Folder)
	local position = chooseSpawn()
	if not position then
		return
	end

	local model = buildRig()
	model:PivotTo(CFrame.new(position + Vector3.new(0, 3.5, 0)))
	model.Parent = folder
	alive += 1

	local torso = model:FindFirstChild("Torso") :: BasePart
	local sounds = EntitySounds.attach(torso)

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

	task.spawn(runAi, model, sounds)
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
