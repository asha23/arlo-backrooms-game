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
local SoundKit = require(ReplicatedStorage.Shared.SoundKit)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local ScoreService = require(script.Parent.ScoreService)
local WeaponFactory = require(script.Parent.WeaponFactory)

local SETTINGS = Config.Weapons

-- How far the client's claimed muzzle position may be from its character
-- before we reject the shot outright.
local MAX_ORIGIN_ERROR = 14

-- One colour per weapon, so the beacon says what it is before you reach it.
local PICKUP_COLORS: { [string]: Color3 } = {
	Pistol = Color3.fromRGB(120, 220, 255),
	MachineGun = Color3.fromRGB(120, 255, 150),
	SniperRifle = Color3.fromRGB(255, 170, 90),
}
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

	--[[
		Head parts carry an IsHead attribute rather than being matched by name.
		The entity's eyes stand proud of the face, so a shot placed exactly
		between them hits a part named "Eye" — testing the name alone meant the
		most deliberate headshot available scored as a body shot. The name test
		remains as a fallback for anything without the attribute.
	]]
	local isHeadshot = hitPart:GetAttribute("IsHead") == true or hitPart.Name == "Head"

	--[[
		Lethality is a rule about hits, not about damage numbers. See
		Config.Combat: a headshot kills outright and five body shots kill,
		whatever you are holding and whatever you hit. Body damage is derived
		from the target's own MaxHealth so it holds for any variant.
	]]
	local combat = Config.Combat
	local damage: number
	if combat.UniformLethality then
		if isHeadshot and combat.HeadshotIsLethal then
			damage = humanoid.MaxHealth
		else
			damage = humanoid.MaxHealth / combat.BodyShotsToKill
		end
	else
		damage = stats.Damage * (if isHeadshot then stats.HeadshotMultiplier else 1)
	end

	humanoid:TakeDamage(damage)

	local killed = humanoid.Health <= 0

	--[[
		The kill's value is read off the rig rather than looked up by name here,
		so adding a variant scores correctly without touching this file.
	]]
	local worth = victim and victim:FindFirstChild("ScoreValue") :: IntValue?
	ScoreService.registerHit(player, if worth then worth.Value else 0, isHeadshot, killed)

	Remotes.HitConfirmed():FireClient(player, hitPosition, isHeadshot, killed)
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

--[[
	The only path by which a player receives a weapon.

	Every weapon is unique: holding a Pistol means there is exactly one Pistol
	instance across your Backpack and your character, forever. Routing all
	grants through here is what makes that true — a check duplicated at each
	call site drifts, and this is exactly how the starter pistol ended up
	stacking on respawn.

	Returns the tool the player now owns (existing or newly created) and whether
	it was newly created, so callers can tell "here you go" from "you already
	have one" without repeating the ownership check themselves.
]]
local function giveWeapon(player: Player, weaponId: string): (Tool?, boolean)
	local stats = WeaponConfig.Weapons[weaponId]
	if not stats then
		return nil, false
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil, false
	end

	-- Already held, either stowed or in hand.
	local held = backpack:FindFirstChild(stats.Name)
	if held and held:IsA("Tool") then
		return held, false
	end
	local character = player.Character
	local equipped = character and character:FindFirstChild(stats.Name)
	if equipped and equipped:IsA("Tool") then
		return equipped, false
	end

	local tool = WeaponFactory.create(weaponId)
	if not tool then
		return nil, false
	end
	tool.Parent = backpack

	-- Re-send on every equip. The grant-time push can arrive before the client
	-- knows the weapon exists, and a stale HUD reading 0 is indistinguishable
	-- from being genuinely out of ammo.
	tool.Equipped:Connect(function()
		pushAmmo(player, weaponId)
	end)

	pushAmmo(player, weaponId)
	return tool, true
end

--[[
	Builds the thing that sits on the floor waiting to be collected.

	Critically this is a plain Model, NOT a Tool. A Tool parented into the
	Workspace with a Handle gets Roblox's built-in pickup behaviour for free:
	touching the handle equips it directly. That bypassed every ownership check
	in this file (so weapons stacked up) and handed the player a Handle that was
	still Anchored — welding the character to an immovable part and stopping
	them dead. The floor display must be scenery and nothing else.
]]
local function buildDisplay(template: Tool, name: string): Model?
	local model = Instance.new("Model")
	model.Name = name

	local handle: BasePart? = nil
	for _, child in template:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		local clone = child:Clone()
		-- Strip anything that could make it interactive.
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("Weld") or descendant:IsA("WeldConstraint") then
				descendant:Destroy()
			end
		end
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		clone.Parent = model
		if child.Name == "Handle" then
			handle = clone
		end
	end

	if not handle then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = handle
	return model
end

--[[
	Tops a weapon back up to a full magazine and full reserve.

	Returns whether anything actually changed, so a pickup isn't consumed by
	somebody walking over it already fully loaded.
]]
local function refillAmmo(player: Player, weaponId: string): boolean
	local stats = WeaponConfig.Weapons[weaponId]
	if not stats then
		return false
	end
	local state = ammoFor(player, weaponId)
	if state.magazine >= stats.MagazineSize and state.reserve >= stats.ReserveAmmo then
		return false
	end
	state.magazine = stats.MagazineSize
	state.reserve = stats.ReserveAmmo
	state.reloading = false
	pushAmmo(player, weaponId)
	return true
end

--- The magazine-seating click when a weapon is collected.
local function playPickupSound(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local audio = Config.PickupAudio
	SoundKit.playOnce(root, {
		Id = audio.Weapon.Id,
		Pitch = audio.Weapon.Pitch,
		Volume = audio.Weapon.Volume,
		Range = audio.Weapon.Range,
	})
	task.delay(audio.WeaponSecondClick.Delay, function()
		if root.Parent then
			SoundKit.playOnce(root, {
				Id = audio.WeaponSecondClick.Id,
				Pitch = audio.WeaponSecondClick.Pitch,
				Volume = audio.WeaponSecondClick.Volume,
				Range = audio.WeaponSecondClick.Range,
			})
		end
	end)
end

--- Drops a pickup at a world position that respawns after being taken.
local function placePickup(weaponId: string, position: Vector3, parent: Instance)
	local template = WeaponFactory.create(weaponId)
	if not template then
		return
	end
	local weaponName = template.Name

	local pedestal = Instance.new("Part")
	pedestal.Name = `Pickup_{weaponId}`
	pedestal.Anchored = true
	pedestal.CanCollide = false
	pedestal.CanTouch = false
	pedestal.CanQuery = false
	pedestal.Size = Vector3.new(3, 0.2, 3)
	pedestal.Transparency = 1
	pedestal.CFrame = CFrame.new(position)
	pedestal.Parent = parent

	local display = buildDisplay(template, `Display_{weaponId}`)
	template:Destroy() -- only ever a blueprint; giveWeapon builds its own.
	if not display then
		return
	end
	display:PivotTo(pedestal.CFrame * CFrame.new(0, 1.2, 0))

	--[[
		Findability. All three weapons are built from the same primitives and
		differ only in size, so on a dark floor they read as the same grey
		shape — "I never see any machine guns" is a discovery problem, not a
		spawning one. Each type gets its own beacon colour and a name that
		floats above it, legible from the far end of a corridor.
	]]
	local tint = PICKUP_COLORS[weaponId] or Color3.fromRGB(120, 220, 255)

	local beacon = Instance.new("PointLight")
	beacon.Color = tint
	beacon.Brightness = 0.45
	beacon.Range = 14
	beacon.Parent = pedestal

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(150, 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	billboard.Parent = pedestal

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = tint
	label.TextStrokeTransparency = 0.4
	label.Text = weaponName
	label.Parent = billboard

	local available = true
	display.Parent = pedestal

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

				--[[
					Rolling over a weapon always tops it up to full, whether or
					not you already own it — a gun you can't shoot is the same
					as no gun. The pickup is only consumed if something actually
					changed, so walking over one while fully loaded and already
					armed leaves it on the floor for someone else.
				]]
				local tool = giveWeapon(player, weaponId)
				if not tool then
					continue
				end
				local refilled = refillAmmo(player, weaponId)

				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local wasEquipped = character ~= nil and character:FindFirstChild(tool.Name) ~= nil
				if not refilled and wasEquipped then
					continue
				end

				-- Equip straight away: rolling over a gun should arm you, not
				-- put a thing in a menu you then have to go and find.
				if humanoid then
					humanoid:EquipTool(tool)
				end
				if character then
					playPickupSound(character)
				end

				available = false
				display.Parent = nil
				beacon.Enabled = false
				billboard.Enabled = false
				task.delay(SETTINGS.RespawnDelay, function()
					if pedestal.Parent then
						available = true
						display.Parent = pedestal
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
		if not player:WaitForChild("Backpack", 10) then
			return
		end

		-- giveWeapon returns the existing pistol on a respawn rather than
		-- adding a second one.
		local pistol = giveWeapon(player, "Pistol")
		if not pistol then
			return
		end

		-- Equip it straight away so players start armed rather than having to
		-- find the hotbar.
		local character = player.Character or player.CharacterAdded:Wait()
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid:EquipTool(pistol)
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
