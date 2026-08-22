--!strict
--[[
	A shuffled pool of open floor positions, handed out without repeats.

	Weapon pickups and health boxes both need somewhere to sit, and each
	shuffling the same list independently would sooner or later stack two
	pickups on the same tile. Drawing from one pool makes that impossible.
]]

local SpawnPoints = {}
SpawnPoints.__index = SpawnPoints

export type SpawnPoints = typeof(setmetatable(
	{} :: {
		_available: { Vector3 },
	},
	SpawnPoints
))

function SpawnPoints.new(positions: { Vector3 }, rng: Random): SpawnPoints
	local shuffled = table.clone(positions)
	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	return setmetatable({ _available = shuffled }, SpawnPoints)
end

--- Removes and returns up to `count` positions. Returns fewer if the pool runs
--- dry, which is a real possibility on a small grid with generous spawn counts.
function SpawnPoints.take(self: SpawnPoints, count: number): { Vector3 }
	local taken: { Vector3 } = {}
	for _ = 1, math.min(count, #self._available) do
		local position = table.remove(self._available)
		if position then
			table.insert(taken, position)
		end
	end
	return taken
end

function SpawnPoints.remaining(self: SpawnPoints): number
	return #self._available
end

return SpawnPoints
