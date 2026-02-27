--[[
	GemShopService.lua
	Server handler for gem case spinning.
	Supports regular cases (fixed pools), effect cases (compression-based RNG),
	and the "All In" special case.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GemCases   = require(ReplicatedStorage.Shared.Config.GemCases)
local Streamers  = require(ReplicatedStorage.Shared.Config.Streamers)

local GemShopService = {}

local PlayerData -- set in Init
local QuestService

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyGemCase   = RemoteEvents:WaitForChild("BuyGemCase")
local GemCaseResult = RemoteEvents:WaitForChild("GemCaseResult")

-------------------------------------------------
-- ROLL HELPERS
-------------------------------------------------

-- Fixed-pool roll (regular cases, All In)
local function rollFixedPool(items)
	local totalWeight = 0
	for _, item in ipairs(items) do
		totalWeight = totalWeight + item.chance
	end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, item in ipairs(items) do
		cumulative = cumulative + item.chance
		if roll <= cumulative then
			return item
		end
	end
	return items[#items]
end

-- Compression-based roll for effect cases
-- weight = (1/odds) ^ compression   (lower compression = flatter distribution)
local function rollEffectCase(compression)
	local weights = {}
	local totalWeight = 0
	for i, s in ipairs(Streamers.List) do
		local w = (1 / s.odds) ^ compression
		weights[i] = w
		totalWeight = totalWeight + w
	end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for i, s in ipairs(Streamers.List) do
		cumulative = cumulative + weights[i]
		if roll <= cumulative then
			return s
		end
	end
	return Streamers.List[#Streamers.List]
end

-- Compute percentage for a given streamer in a compression pool (used client-side too)
-- Exported as a utility
function GemShopService.ComputeEffectPercentages(compression)
	local weights = {}
	local totalWeight = 0
	for i, s in ipairs(Streamers.List) do
		local w = (1 / s.odds) ^ compression
		weights[i] = w
		totalWeight = totalWeight + w
	end
	local result = {}
	for i, s in ipairs(Streamers.List) do
		result[i] = {
			streamerId  = s.id,
			displayName = s.displayName,
			rarity      = s.rarity,
			percent     = (weights[i] / totalWeight) * 100,
		}
	end
	return result
end

-------------------------------------------------
-- HANDLE PURCHASE
-------------------------------------------------

local function handleBuyGemCase(player, caseId)
	if not PlayerData.IsTutorialComplete(player) then
		GemCaseResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end
	if type(caseId) ~= "string" then
		GemCaseResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end

	local caseData = GemCases.ById[caseId]
	if not caseData then
		GemCaseResult:FireClient(player, { success = false, reason = "Unknown case." })
		return
	end

	local data = PlayerData.Get(player)
	if not data then
		GemCaseResult:FireClient(player, { success = false, reason = "Data not loaded." })
		return
	end

	if (data.gems or 0) < caseData.cost then
		GemCaseResult:FireClient(player, { success = false, reason = "Not enough gems! Need " .. caseData.cost .. " gems." })
		return
	end

	-- Deduct gems
	data.gems = data.gems - caseData.cost

	local wonStreamerId, wonDisplayName, wonRarity, wonEffect

	-- Determine case type
	if caseData.compression then
		-- EFFECT CASE (compression-based, all streamers with specific effect)
		local won = rollEffectCase(caseData.compression)
		wonStreamerId  = won.id
		wonDisplayName = caseData.effect .. " " .. won.displayName
		wonRarity      = won.rarity
		wonEffect      = caseData.effect

	elseif caseData.items then
		-- FIXED POOL (regular case or All In)
		local won = rollFixedPool(caseData.items)
		wonStreamerId  = won.streamerId
		wonEffect      = won.effect or nil

		local streamerInfo = Streamers.ById[wonStreamerId]
		wonDisplayName = won.displayName or (streamerInfo and streamerInfo.displayName) or wonStreamerId
		wonRarity      = (streamerInfo and streamerInfo.rarity) or "Common"
	else
		GemCaseResult:FireClient(player, { success = false, reason = "Invalid case configuration." })
		return
	end

	-- Add to inventory; SECURITY FIX: rollback gems if inventory is full
	local dest = PlayerData.AddToInventory(player, wonStreamerId, wonEffect)
	if dest == "full" then
		-- Rollback: restore gems since item couldn't be added
		data.gems = data.gems + caseData.cost
		PlayerData.Replicate(player)
		GemCaseResult:FireClient(player, { success = false, reason = "Inventory and storage are full!" })
		return
	end
	PlayerData.Replicate(player)

	GemCaseResult:FireClient(player, {
		success     = true,
		streamerId  = wonStreamerId,
		displayName = wonDisplayName,
		rarity      = wonRarity,
		effect      = wonEffect,
		caseId      = caseId,
	})
	if QuestService then
		QuestService.Increment(player, "casesOpened", 1)
	end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function GemShopService.Init(playerDataModule, questServiceModule)
	PlayerData = playerDataModule
	QuestService = questServiceModule

	-- SECURITY FIX: Wrap in per-player lock to prevent race conditions
	BuyGemCase.OnServerEvent:Connect(function(player, caseId)
		PlayerData.WithLock(player, function() handleBuyGemCase(player, caseId) end)
	end)
end

return GemShopService
