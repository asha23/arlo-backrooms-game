--!strict
--[[
	Server-authoritative shooting.

	The client sends the ray it was aiming down; the server re-casts that ray
	itself, sanity-checks the origin against the shooter's actual position, and
	enforces fire rate and ammo. A client that lies about its aim can still only
	hit things that are genuinely in front of it, and can never fire faster or
	with more ammo than its weapon allows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local WeaponFactory = require(script.Parent.WeaponFactory)

local SETTINGS = Config.Weapons

-- How far the client's claimed muzzle position may be from its character
-- before we reject the shot outright.
local MAX_ORIGIN_ERROR = 14
-- Fire-rate tolerance, to absorb network jitter without allowing rapid fire.
local RATE_TOLERANCE = 0.9

type AmmoState = { magazine: number, reserve: number, reloading: boolean }

local WeaponService = {}

-- [player] = { [weaponId] = AmmoState }
local ammoByPlayer: { [Player]: { [string]: AmmoState } } = {}
-- [player] = os.clock() of last accepted shot
local lastShotAt: { [Player]: number } = {}

local function statsFor(tool: Tool): (string?, WeaponConfig.Weapon?)
	local idTag = tool:FindFirstChild("WeaponId") :: StringValue?
	if not idTag then
		return nil, nil
	end
	return idTag.Value, WeaponConfig.Weapons[idTag.Value]
end

local function ammoFor(player: Player, weaponId: string): AmmoState
	local perWeapon = ammoByPlayer[player]
	if not perWeapon then
		perWeapon = {}
		ammoByPlayer[player] = perWeapon
	end
	local state = perWeapon[weaponId]
	if not state then
		local stats = WeaponConfig.Weapons[weaponId]
		state = { magazine = stats.MagazineSize, reserve = stats.ReserveAmmo, reloading = false }
		perWeapon[weaponId] = state
	end
	return state
end

local function pushAmmo(player: Player, weaponId: string)
	local state = ammoFor(player, weaponId)
	Remotes.AmmoChanged()
		:FireClient(player, weaponId, state.magazine, state.reserve, state.reloading)
end

--- The tool the player currently has equipped, if it's one of ours.
local function equippedTool(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and tool:FindFirstChild("WeaponId") then
		return tool
	end
	return nil
end

--- Applies spread deterministically on the server so the client can't cheat it away.
local function applySpread(direction: Vector3, spreadDegrees: number, rng: Random): Vector3
	if spreadDegrees <= 0 then
		return direction
	end
	local radians = math.rad(spreadDegrees)
	local angle = rng:NextNumber(0, math.pi * 2)
	local magnitude = rng:NextNumber(0, radians)
	-- Build a basis around the aim direction and tilt within the cone.
	local up = if math.abs(direction.Y) > 0.99 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	local right = direction:Cross(up).Unit
	local trueUp = right:Cross(direction).Unit
	local offset = (right * math.cos(angle) + trueUp * math.sin(angle)) * math.tan(magnitude)
	return (direction + offset).Unit
end

local rng = Random.new()

local function resolveShot(
	player: Player,
	origin: Vector3,
	direction: Vector3,
	stats: WeaponConfig.Weapon
)
	local character = player.Character
	if not character then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local aim = applySpread(direction, stats.Spread, rng)
	local result = workspace:Raycast(origin, aim * stats.Range, params)
	local hitPosition = if result then result.Position else origin + aim * stats.Range

	-- Everyone sees the tracer; only the shooter gets the hitmarker.
	Remotes.ShotFired():FireAllClients(player, origin, hitPosition)

	if not result then
		return
	end

	local hitPart = result.Instance
	local victim = hitPart:FindFirstAncestorOfClass("Model")
	local humanoid = victim and victim:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Don't let players shoot each other; this is a PvE game for now.
	if Players:GetPlayerFromCharacter(victim) then
		return
	end

	local isHeadshot = hitPart.Name == "Head"
	local damage = stats.Damage * (if isHeadshot then stats.HeadshotMultiplier else 1)
	humanoid:TakeDamage(damage)

	Remotes.HitConfirmed():FireClient(player, hitPosition, isHeadshot, humanoid.Health <= 0)
end

local function onFire(player: Player, origin: unknown, direction: unknown)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if direction.Magnitude < 0.1 or direction.Magnitude > 1.1 then
		return -- must be (near) a unit vector
	end

	local tool = equippedTool(player)
	if not tool then
		return
	end
	local weaponId, stats = statsFor(tool)
	if not weaponId or not stats then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Reject shots claiming to come from somewhere the shooter isn't.
	if (origin - root.Position).Magnitude > MAX_ORIGIN_ERROR then
		return
	end

	local now = os.clock()
	local minInterval = (1 / stats.FireRate) * RATE_TOLERANCE
	if now - (lastShotAt[player] or 0) < minInterval then
		return
	end

	local state = ammoFor(player, weaponId)
	if state.reloading or state.magazine <= 0 then
		return
	end

	lastShotAt[player] = now
	state.magazine -= 1
	pushAmmo(player, weaponId)

	for _ = 1, stats.PelletsPerShot do
		resolveShot(player, origin, direction.Unit, stats)
	end
end

local function onReload(player: Player)
	local tool = equippedTool(player)
	if not tool then
		return
	end
	local weaponId, stats = statsFor(tool)
	if not weaponId or not stats then
		return
	end

	local state = ammoFor(player, weaponId)
	if state.reloading or state.magazine >= stats.MagazineSize or state.reserve <= 0 then
		return
	end

	state.reloading = true
	pushAmmo(player, weaponId)

	task.delay(stats.ReloadTime, function()
		-- Re-read: the player may have died or swapped weapons mid-reload.
		local current = ammoFor(player, weaponId)
		local wanted = math.min(stats.MagazineSize - current.magazine, current.reserve)
		current.magazine += wanted
		current.reserve -= wanted
		current.reloading = false
		if player.Parent then
			pushAmmo(player, weaponId)
		end
	end)
end

--- Drops a pickup at a world position that respawns after being taken.
local function placePickup(weaponId: string, position: Vector3, parent: Instance)
	local pedestal = Instance.new("Part")
	pedestal.Name = `Pickup_{weaponId}`
	pedestal.Anchored = true
	pedestal.CanCollide = false
	pedestal.Size = Vector3.new(3, 0.2, 3)
	pedestal.Transparency = 1
	pedestal.CFrame = CFrame.new(position)
	pedestal.Parent = parent

	local template = WeaponFactory.create(weaponId)
	if not template then
		return
	end

	local display = template:Clone()
	local displayHandle = display:FindFirstChild("Handle") :: BasePart?

	local function show()
		display.Parent = pedestal
		if displayHandle then
			displayHandle.Anchored = true
			displayHandle.CFrame = pedestal.CFrame * CFrame.new(0, 1.2, 0)
		end
	end

	-- A glow so pickups are findable in a dark maze.
	local beacon = Instance.new("PointLight")
	beacon.Color = Color3.fromRGB(120, 220, 255)
	beacon.Brightness = 1.6
	beacon.Range = 16
	beacon.Parent = pedestal

	local available = true
	show()

	task.spawn(function()
		while pedestal.Parent do
			task.wait(0.35)
			if not available then
				continue
			end
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if
					not root
					or (root.Position - pedestal.Position).Magnitude > SETTINGS.PickupRadius
				then
					continue
				end

				local backpack = player:FindFirstChildOfClass("Backpack")
				if not backpack then
					continue
				end
				-- One of each weapon is enough.
				local alreadyHas = backpack:FindFirstChild(template.Name)
					or (character and character:FindFirstChild(template.Name))
				if alreadyHas then
					continue
				end

				local given = template:Clone()
				given.Parent = backpack
				pushAmmo(player, weaponId)

				available = false
				display.Parent = nil
				beacon.Enabled = false
				task.delay(SETTINGS.RespawnDelay, function()
					if pedestal.Parent then
						available = true
						show()
						beacon.Enabled = true
					end
				end)
				break
			end
		end
	end)
end

--- Scatters pickups across open floor cells.
function WeaponService.spawnPickups(openPositions: { Vector3 })
	if #openPositions == 0 then
		warn("[WeaponService] no open positions to spawn weapons in")
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "WeaponPickups"
	folder.Parent = workspace

	local order = WeaponConfig.Order
	local shuffled = table.clone(openPositions)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	local count = math.min(SETTINGS.SpawnCount, #shuffled)
	for i = 1, count do
		-- Round-robin the weapon types so every kind is reliably findable.
		local weaponId = order[((i - 1) % #order) + 1]
		placePickup(weaponId, shuffled[i] + Vector3.new(0, 1, 0), folder)
	end
	print(`[Weapons] placed {count} pickups`)
end

function WeaponService.start()
	Remotes.FireWeapon().OnServerEvent:Connect(onFire)
	Remotes.ReloadWeapon().OnServerEvent:Connect(function(player)
		onReload(player)
	end)

	-- Give everyone a pistol to start with, so nobody is defenceless on spawn.
	local function grantStarterWeapon(player: Player)
		local backpack = player:WaitForChild("Backpack", 10)
		if not backpack then
			return
		end
		-- Backpack contents survive a respawn, so without this check every
		-- death would add another pistol to the hotbar.
		local existing = backpack:FindFirstChild("Pistol")
		local pistol = existing :: Tool? or WeaponFactory.create("Pistol")
		if pistol then
			pistol.Parent = backpack
			-- Equip it straight away so players start armed rather than having
			-- to find the hotbar. EquipTool needs the character's Humanoid, and
			-- the character may not have finished loading yet.
			local character = player.Character or player.CharacterAdded:Wait()
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				humanoid:EquipTool(pistol)
			end
		end
		pushAmmo(player, "Pistol")
	end

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			grantStarterWeapon(player)
		end)
		if player.Character then
			grantStarterWeapon(player)
		end
	end

	Players.PlayerAdded:Connect(watch)
	-- Players may already be in-game if this service starts after a join.
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		ammoByPlayer[player] = nil
		lastShotAt[player] = nil
	end)
end

return WeaponService
