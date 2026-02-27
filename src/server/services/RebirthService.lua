--[[
	RebirthService.lua
	Handles rebirth: cost check, reset cash + potions, increment rebirth.
	Equipped streamers stay on base pads (no return to inventory).
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
local QuestService

-------------------------------------------------
-- REBIRTH LOGIC
-------------------------------------------------

local function handleRebirth(player)
	if not PlayerData then return end
	if not PlayerData.IsTutorialComplete(player) then
		RebirthResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end

	-- SECURITY FIX: Wrap rebirth in per-player lock and verify atomically
	PlayerData.WithLock(player, function()
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

		-- SECURITY FIX: Verify and deduct cost BEFORE any mutations (atomic check)
		if data.cash < cost then
			RebirthResult:FireClient(player, {
				success = false,
				reason = "Not enough cash! Need $" .. tostring(cost),
			})
			return
		end

		-- Deduct cost first, then reset
		data.cash = data.cash - cost

		-- Reset equipped pads (items go back to inventory); cash already deducted above
		-- Note: ResetForRebirth sets cash=0 which is fine since we already deducted
		PlayerData.ResetForRebirth(player)

		-- Clear active potions
		if PotionService then
			PotionService.ClearPotions(player)
		end

		-- Increment rebirth
		local newCount = data.rebirthCount + 1
		PlayerData.SetRebirthCount(player, newCount)

		-- Clear display models and pending keys, then update pads for new unlock count
		if BaseService then
			BaseService.ClearDisplaysForRebirth(player)
			BaseService.UpdateBasePads(player)
		end

		if QuestService then
			QuestService.Increment(player, "rebirths", 1)
		end

		RebirthResult:FireClient(player, {
			success = true,
			newRebirthCount = newCount,
			nextCost = Economy.GetRebirthCost(newCount),
		})
	end)
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function RebirthService.Init(playerDataModule, baseServiceModule, potionServiceModule, questServiceModule)
	PlayerData = playerDataModule
	BaseService = baseServiceModule
	PotionService = potionServiceModule
	QuestService = questServiceModule

	RebirthRequest.OnServerEvent:Connect(function(player)
		handleRebirth(player)
	end)
end

return RebirthService
