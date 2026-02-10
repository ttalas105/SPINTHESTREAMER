--[[
	RebirthService.lua
	Handles rebirth: cost check, reset cash/equipped, increment rebirth,
	unlock additional slots.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RebirthRequest = RemoteEvents:WaitForChild("RebirthRequest")
local RebirthResult = RemoteEvents:WaitForChild("RebirthResult")

local RebirthService = {}

local PlayerData -- set in Init

-------------------------------------------------
-- REBIRTH LOGIC
-------------------------------------------------

local function handleRebirth(player)
	if not PlayerData then return end
	local data = PlayerData.Get(player)
	if not data then return end

	local cost = Economy.GetRebirthCost(data.rebirthCount)

	if data.cash < cost then
		RebirthResult:FireClient(player, {
			success = false,
			reason = "Not enough cash! Need " .. tostring(cost),
		})
		return
	end

	-- Reset cash and equipped (collection kept)
	PlayerData.ResetForRebirth(player)

	-- Increment rebirth
	local newCount = data.rebirthCount + 1
	PlayerData.SetRebirthCount(player, newCount)

	RebirthResult:FireClient(player, {
		success = true,
		newRebirthCount = newCount,
		nextCost = Economy.GetRebirthCost(newCount),
	})
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function RebirthService.Init(playerDataModule)
	PlayerData = playerDataModule

	RebirthRequest.OnServerEvent:Connect(function(player)
		handleRebirth(player)
	end)
end

return RebirthService
