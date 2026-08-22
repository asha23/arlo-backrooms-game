--!strict
--[[
	Builds "Level 0" — the yellow room maze.

	The layout lives on an odd-sized grid: odd coordinates are carve-able cells,
	even coordinates are the wall slabs between them. A randomised depth-first
	carve produces a perfect maze; we then knock through extra walls and stamp
	out open rooms, because a perfect maze reads as a puzzle while the Backrooms
	should read as an endless office floor you keep looping through.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LEVEL = Config.Level
local SIZE = LEVEL.GridSize
local CELL = LEVEL.CellSize
local HEIGHT = LEVEL.WallHeight

local WALLPAPER = Color3.fromRGB(213, 197, 128)
local CARPET = Color3.fromRGB(190, 175, 105)
local CEILING = Color3.fromRGB(226, 216, 172)

export type Grid = { { boolean } }

local LevelGenerator = {}

--- Grid coordinate (1-based) -> world position of that cell's centre.
local function cellToWorld(x: number, z: number): Vector3
	local offset = (SIZE + 1) / 2
	return Vector3.new((x - offset) * CELL, 0, (z - offset) * CELL)
end

-- Maze cells live on odd coordinates inset from the edge, leaving indices
-- 1..2 and SIZE-1..SIZE as a solid perimeter wall.
local MIN_CELL = 3
local MAX_CELL = SIZE - 2

local function isCell(x: number, z: number): boolean
	return x >= MIN_CELL and x <= MAX_CELL and z >= MIN_CELL and z <= MAX_CELL
end

--- Randomised depth-first carve over the odd-coordinate cells.
local function carveMaze(grid: Grid, rng: Random)
	local stack = { Vector2.new(MIN_CELL, MIN_CELL) }
	grid[MIN_CELL][MIN_CELL] = true

	local directions = {
		Vector2.new(2, 0),
		Vector2.new(-2, 0),
		Vector2.new(0, 2),
		Vector2.new(0, -2),
	}

	while #stack > 0 do
		local current = stack[#stack]

		-- Collect neighbours two cells away that haven't been carved yet.
		local unvisited = {}
		for _, dir in directions do
			local nx, nz = current.X + dir.X, current.Y + dir.Y
			if isCell(nx, nz) and not grid[nx][nz] then
				table.insert(unvisited, dir)
			end
		end

		if #unvisited == 0 then
			table.remove(stack)
			continue
		end

		local dir = unvisited[rng:NextInteger(1, #unvisited)]
		local nx, nz = current.X + dir.X, current.Y + dir.Y

		-- Open the wall between the two cells, then the cell itself.
		grid[current.X + dir.X // 2][current.Y + dir.Y // 2] = true
		grid[nx][nz] = true
		table.insert(stack, Vector2.new(nx, nz))
	end
end

--- Knock through extra walls so the maze loops back on itself.
local function addLoops(grid: Grid, rng: Random)
	for x = 2, SIZE - 1 do
		for z = 2, SIZE - 1 do
			if grid[x][z] then
				continue
			end
			-- Only walls with open cells on exactly one axis are worth opening;
			-- the others are pillar corners that hold the layout together.
			local horizontal = grid[x - 1][z] and grid[x + 1][z]
			local vertical = grid[x][z - 1] and grid[x][z + 1]
			if (horizontal or vertical) and rng:NextNumber() < LEVEL.LoopChance then
				grid[x][z] = true
			end
		end
	end
end

--- Stamp open halls into the maze.
local function addRooms(grid: Grid, rng: Random)
	local radius = LEVEL.RoomRadius
	for x = 1 + radius, SIZE - radius do
		for z = 1 + radius, SIZE - radius do
			if rng:NextNumber() >= LEVEL.RoomChance then
				continue
			end
			for dx = -radius, radius do
				for dz = -radius, radius do
					grid[x + dx][z + dz] = true
				end
			end
		end
	end
end

--- Seal the outer ring so players can't walk off the edge of the world.
local function sealBorder(grid: Grid)
	for i = 1, SIZE do
		grid[1][i] = false
		grid[SIZE][i] = false
		grid[i][1] = false
		grid[i][SIZE] = false
	end
end

local function newPart(props: { [string]: any }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

--[[
	Emit wall geometry. Adjacent wall cells in a row are merged into a single
	part — a 41x41 grid is ~800 wall cells, and merging runs cuts that to a few
	hundred parts, which matters for streaming and physics cost.
]]
local function buildWalls(grid: Grid, parent: Instance)
	for z = 1, SIZE do
		local runStart: number? = nil
		for x = 1, SIZE + 1 do
			local solid = x <= SIZE and not grid[x][z]
			if solid and runStart == nil then
				runStart = x
			elseif not solid and runStart ~= nil then
				local runLength = x - runStart
				local centreX = (runStart + x - 1) / 2
				local origin = cellToWorld(centreX, z)
				newPart({
					Name = "Wall",
					Size = Vector3.new(runLength * CELL, HEIGHT, CELL),
					CFrame = CFrame.new(origin + Vector3.new(0, HEIGHT / 2, 0)),
					Color = WALLPAPER,
					Material = Enum.Material.Fabric,
				}, parent)
				runStart = nil
			end
		end
	end
end

local function buildShell(parent: Instance)
	local span = SIZE * CELL

	newPart({
		Name = "Floor",
		Size = Vector3.new(span, 2, span),
		CFrame = CFrame.new(0, -1, 0),
		Color = CARPET,
		Material = Enum.Material.Fabric,
	}, parent)

	newPart({
		Name = "Ceiling",
		Size = Vector3.new(span, 2, span),
		CFrame = CFrame.new(0, HEIGHT + 1, 0),
		Color = CEILING,
		Material = Enum.Material.Concrete,
	}, parent)
end

--[[
	Ceiling fluorescents. Each one is tagged so the client-side flicker effect
	can find them without walking the whole workspace.
]]
local function buildLights(grid: Grid, parent: Instance, rng: Random)
	local spacing = LEVEL.LightSpacing
	for x = 1, SIZE, spacing do
		for z = 1, SIZE, spacing do
			if not grid[x][z] then
				continue
			end
			local origin = cellToWorld(x, z)
			local fixture = newPart({
				Name = "Fluorescent",
				Size = Vector3.new(CELL * 0.5, 0.4, 1.6),
				CFrame = CFrame.new(origin + Vector3.new(0, HEIGHT - 0.2, 0)),
				Color = Color3.fromRGB(255, 250, 220),
				Material = Enum.Material.Neon,
				CanCollide = false,
			}, parent)
			fixture:AddTag("Fluorescent")

			local light = Instance.new("PointLight")
			light.Brightness = rng:NextNumber(1.4, 2.2)
			light.Range = 34
			light.Color = Color3.fromRGB(255, 247, 214)
			light.Shadows = true
			light.Parent = fixture
		end
	end
end

--- Nearest open cell to the middle of the grid, used for the spawn point.
local function findSpawnCell(grid: Grid): Vector2
	local centre = (SIZE + 1) // 2
	for radius = 0, SIZE do
		for dx = -radius, radius do
			for dz = -radius, radius do
				local x, z = centre + dx, centre + dz
				if x >= 1 and x <= SIZE and z >= 1 and z <= SIZE and grid[x][z] then
					return Vector2.new(x, z)
				end
			end
		end
	end
	return Vector2.new(MIN_CELL, MIN_CELL)
end

--- Generates the level and parents it under Workspace. Returns the grid so
--- other systems (entity spawning, exits) can reason about the layout.
function LevelGenerator.generate(): Grid
	local seed = if LEVEL.Seed ~= 0 then LEVEL.Seed else os.time()
	local rng = Random.new(seed)
	print(`[Level] generating with seed {seed}`)

	local grid: Grid = table.create(SIZE)
	for x = 1, SIZE do
		grid[x] = table.create(SIZE, false)
	end

	carveMaze(grid, rng)
	addRooms(grid, rng)
	addLoops(grid, rng)
	sealBorder(grid)

	local existing = workspace:FindFirstChild("Level")
	if existing then
		existing:Destroy()
	end

	local level = Instance.new("Folder")
	level.Name = "Level"

	buildShell(level)
	buildWalls(grid, level)
	buildLights(grid, level, rng)
	level.Parent = workspace

	local spawnCell = findSpawnCell(grid)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Entry"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = CFrame.new(cellToWorld(spawnCell.X, spawnCell.Y) + Vector3.new(0, 0.5, 0))
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = level

	return grid
end

return LevelGenerator
