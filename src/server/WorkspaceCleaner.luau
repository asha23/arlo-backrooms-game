--!strict
--[[
	Removes template content the level is going to sit on top of.

	Our own build puts nothing in Workspace at all — the maze, its floor and its
	spawn are all created at runtime. But a place made from a Roblox template
	ships a grey Baseplate and a default SpawnLocation, and Rojo syncs our
	scripts INTO whatever place is open rather than replacing it. The result is
	the level generating on top of a baseplate, with players spawning on
	Roblox's pad instead of at our entrance: the floor looks wrong and the
	spawn looks generic, because both of them are.

	Publishing into an existing experience hits exactly the same thing, so this
	is not only a Studio problem.

	Deliberately narrow. It removes the two specific things Roblox templates
	add, by class and by name, and logs each one — silently deleting things out
	of someone's Workspace would be far worse than leaving them.
]]

local WorkspaceCleaner = {}

--- Names Roblox's own templates use for the default ground.
local TEMPLATE_GROUND = {
	Baseplate = true,
	SpawnLocation = true,
}

function WorkspaceCleaner.run()
	local removed = 0

	for _, item in workspace:GetChildren() do
		--[[
			Anything inside our own folders is ours and is left alone; this only
			looks at the top level of Workspace, which is where a template's
			content sits.
		]]
		if item:IsA("SpawnLocation") then
			print(`[Cleanup] removing a stray SpawnLocation ('{item.Name}')`)
			item:Destroy()
			removed += 1
		elseif item:IsA("BasePart") and TEMPLATE_GROUND[item.Name] then
			print(`[Cleanup] removing template ground ('{item.Name}')`)
			item:Destroy()
			removed += 1
		end
	end

	if removed > 0 then
		print(`[Cleanup] removed {removed} item(s) left over from a place template`)
	end
end

return WorkspaceCleaner
