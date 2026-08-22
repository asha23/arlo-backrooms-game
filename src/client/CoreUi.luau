--!strict
--[[
	Hides the Roblox core UI we don't want. The chat window in particular breaks
	the mood and steals keyboard focus, which matters when movement is on WASD.
]]

local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local CoreUi = {}

function CoreUi.start()
	-- SetCore calls can fail if the CoreGui isn't ready yet, so retry briefly.
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
			end)
			if ok then
				break
			end
			task.wait(0.25)
		end
	end)

	-- Newer TextChatService places also need the window switched off directly.
	pcall(function()
		local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		if window then
			window.Enabled = false
		end
	end)
end

return CoreUi
