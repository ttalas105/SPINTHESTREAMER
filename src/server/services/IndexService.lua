--[[
	IndexService.lua
	Server-side handler for the Index/Collection system.
	Players can claim gem rewards for each unique streamer+effect combo
	they've discovered. Each combo can only be claimed once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)

local IndexService = {}

local PlayerData
local QuestService

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ClaimIndexGems = RemoteEvents:WaitForChild("ClaimIndexGems")
local ClaimIndexResult = RemoteEvents:WaitForChild("ClaimIndexResult")

-------------------------------------------------
-- CLAIM GEMS
-------------------------------------------------

local function handleClaimGems(player, streamerId, effect)
	if type(streamerId) ~= "string" then
		ClaimIndexResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end
	if effect ~= nil and type(effect) ~= "string" then
		ClaimIndexResult:FireClient(player, { success = false, reason = "Invalid effect." })
		return
	end

	-- Verify streamer exists
	local info = Streamers.ById[streamerId]
	if not info then
		ClaimIndexResult:FireClient(player, { success = false, reason = "Unknown streamer." })
		return
	end

	-- Check if unlocked
	if not PlayerData.HasIndexEntry(player, streamerId, effect) then
		ClaimIndexResult:FireClient(player, { success = false, reason = "You haven't discovered this one yet!" })
		return
	end

	-- Check if already claimed
	if PlayerData.HasClaimedIndexGems(player, streamerId, effect) then
		ClaimIndexResult:FireClient(player, { success = false, reason = "Gems already collected!" })
		return
	end

	-- Calculate gem reward: base by rarity, then x2 for Acid, x3 for Snow, ... x10 for Void
	local gemReward = Economy.GetIndexGemReward(info.rarity, effect)

	-- Claim
	local claimed = PlayerData.ClaimIndexGems(player, streamerId, effect)
	if not claimed then
		ClaimIndexResult:FireClient(player, { success = false, reason = "Could not claim gems." })
		return
	end

	PlayerData.AddGems(player, gemReward)

	ClaimIndexResult:FireClient(player, {
		success = true,
		streamerId = streamerId,
		effect = effect,
		gemsEarned = gemReward,
		totalGems = PlayerData.GetGems(player),
	})
	if QuestService then
		QuestService.Increment(player, "indexClaimed", 1)
		QuestService.Increment(player, "gemsEarned", gemReward)
		local effectKey = (effect and effect ~= "") and effect or "Default"
		QuestService.Increment(player, "index" .. effectKey, 1)
	end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function IndexService.Init(playerDataModule, questServiceModule)
	PlayerData = playerDataModule
	QuestService = questServiceModule

	ClaimIndexGems.OnServerEvent:Connect(function(player, streamerId, effect)
		handleClaimGems(player, streamerId, effect)
	end)
end

return IndexService
