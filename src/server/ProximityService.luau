--!strict
--[[
	One loop for every "is a player standing on this?" check in the game.

	Weapons, medkits, torches, extra lives, cash and the exit each used to spawn
	their own coroutine, and each of those woke several times a second to walk
	the whole player list. With a full level that is seventy-odd threads doing
	the same work at slightly different times — a constant background cost that
	scales with how much loot is lying around rather than with how many players
	there are.

	This runs a single loop instead, and buckets registrations by position so a
	player is only tested against the handful of things near them rather than
	against everything in the level. Cost now scales with players, not pickups.
]]

local Players = game:GetService("Players")

local ProximityService = {}

-- Bucket edge in studs. Wide enough that a pickup's radius never spans more
-- than the 3x3 block searched around a player, small enough to stay selective.
local BUCKET = 32
local TICK = 0.15

export type Entry = {
	position: Vector3,
	radius: number,
	--- Return true if the player consumed this; the entry is then deactivated.
	onReach: (Player) -> boolean,
	active: boolean,
	_key: string,
}

local buckets: { [string]: { Entry } } = {}

local function keyFor(position: Vector3): string
	return `{math.floor(position.X / BUCKET)},{math.floor(position.Z / BUCKET)}`
end

--- Handle returned by `register`, for enabling, disabling and removing.
export type Handle = {
	setActive: (Handle, boolean) -> (),
	destroy: (Handle) -> (),
}

--- Adds an entry and hands back a handle for enabling, disabling and removing.
function ProximityService.register(
	position: Vector3,
	radius: number,
	onReach: (Player) -> boolean
): Handle
	local entry: Entry = {
		position = position,
		radius = radius,
		onReach = onReach,
		active = true,
		_key = keyFor(position),
	}

	local bucket = buckets[entry._key]
	if not bucket then
		bucket = {}
		buckets[entry._key] = bucket
	end
	table.insert(bucket, entry)

	local handle: Handle
	handle = {
		setActive = function(_self: Handle, active: boolean)
			entry.active = active
		end,
		destroy = function(_self: Handle)
			entry.active = false
			local list = buckets[entry._key]
			if not list then
				return
			end
			local index = table.find(list, entry)
			if index then
				table.remove(list, index)
			end
		end,
	}
	return handle
end

function ProximityService.start()
	task.spawn(function()
		-- Scratch tables reused between ticks so a 7Hz loop never allocates.
		local nearby: { Entry } = {}

		while true do
			task.wait(TICK)

			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
					continue
				end

				local origin = root.Position
				local bx = math.floor(origin.X / BUCKET)
				local bz = math.floor(origin.Z / BUCKET)

				table.clear(nearby)
				for dx = -1, 1 do
					for dz = -1, 1 do
						local bucket = buckets[`{bx + dx},{bz + dz}`]
						if not bucket then
							continue
						end
						for _, entry in bucket do
							if entry.active then
								table.insert(nearby, entry)
							end
						end
					end
				end

				for _, entry in nearby do
					if not entry.active then
						continue
					end
					if (entry.position - origin).Magnitude > entry.radius then
						continue
					end
					if entry.onReach(player) then
						entry.active = false
					end
				end
			end
		end
	end)
end

return ProximityService
