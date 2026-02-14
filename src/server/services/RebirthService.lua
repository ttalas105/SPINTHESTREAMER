--[[
	RebirthService.lua
	Handles rebirth: cost check, reset cash + potions,
	(equipped items return to inventory), increment rebirth.
	Max 7 rebirths. Each gives +5% coin bonus and unlocks the next case.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RebirthRequest = RemoteEvents:WaitForChild("RebirthRequest")
local RebirthResult = RemoteEvents:WaitForChild("RebirthResult")

local RebirthService = {}

local PlayerData
local BaseService
local PotionService

-------------------------------------------------
-- REBIRTH LOGIC
-------------------------------------------------

local function handleRebirth(player)
	if not PlayerData then return end
	local data = PlayerData.Get(player)
	if not data then return end

	-- Check max rebirths
	if data.rebirthCount >= Economy.MaxRebirths then
		RebirthResult:FireClient(player, {
			success = false,
			reason = "You have reached the maximum rebirth level!",
		})
		return
	end

	local cost = Economy.GetRebirthCost(data.rebirthCount)

	if data.cash < cost then
		RebirthResult:FireClient(player, {
			success = false,
			reason = "Not enough cash! Need $" .. tostring(cost),
		})
		return
	end

	-- Reset cash and equipped pads (items go back to inventory)
	PlayerData.ResetForRebirth(player)

	-- Clear active potions
	if PotionService then
		PotionService.ClearPotions(player)
	end

	-- Increment rebirth
	local newCount = data.rebirthCount + 1
	PlayerData.SetRebirthCount(player, newCount)

	-- Update base pads to reflect new unlock count
	if BaseService then
		BaseService.UpdateBasePads(player)
	end

	RebirthResult:FireClient(player, {
		success = true,
		newRebirthCount = newCount,
		nextCost = Economy.GetRebirthCost(newCount),
	})
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function RebirthService.Init(playerDataModule, baseServiceModule, potionServiceModule)
	PlayerData = playerDataModule
	BaseService = baseServiceModule
	PotionService = potionServiceModule

	RebirthRequest.OnServerEvent:Connect(function(player)
		handleRebirth(player)
	end)
end

return RebirthService
