--[[
	SpinService.lua
	Handles spin requests: cost check, weighted RNG, server luck.
	Spin results go to INVENTORY (not auto-equip).
	Mythic pulls trigger a server-wide alert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)

local PITY_RARITY_ORDER = { "Rare", "Epic", "Legendary", "Mythic" }

local SpinService = {}

SpinService.ServerLuckMultiplier = Economy.DefaultLuckMultiplier
local QuestService

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SpinRequest = RemoteEvents:WaitForChild("SpinRequest")
local SpinResult = RemoteEvents:WaitForChild("SpinResult")
local MythicAlert = RemoteEvents:WaitForChild("MythicAlert")
local BuyCrateRequest = RemoteEvents:WaitForChild("BuyCrateRequest")

local PlayerData
local BaseService
local PotionService

-- SECURITY FIX: Per-player spin cooldown to prevent spam/exploits
local SPIN_COOLDOWN = 1 -- seconds
local lastSpinTime = {} -- [userId] = os.clock()

-------------------------------------------------
-- RNG: TWO-PHASE RARITY-FIRST SYSTEM
-- Phase 1: Roll a RARITY TIER (luck crushes Common, boosts Rare+)
-- Phase 2: Roll a specific streamer within that tier (weighted by 1/odds)
--
-- Luck formula: 1 luck = 1%. Total luckPercent is passed as luckMultiplier.
-- luckMultiplier = 1 + (playerLuck/100) + crateLuckBonus
-- So 200 luck + Case7(250%) => luckMultiplier = 1 + 2.0 + 2.5 = 5.5
--
-- Rarity scaling (L = luckMultiplier):
--   Common:    baseWeight / L^3   (gets CRUSHED by luck)
--   Rare:      baseWeight * L^1   (scales up linearly)
--   Epic:      baseWeight * L^2   (scales up fast)
--   Legendary: baseWeight * L^3   (scales up very fast)
--   Mythic:    baseWeight * L^4   (scales up extremely fast)
--
-- At 0 luck (L=1): Common ~90%, Rare ~9%, Epic ~0.9%, Leg ~0.09%, Mythic ~0.009%
-- At 2000 luck + Case7 (L=5.5): Common ~0.4%, Rare ~39%, Epic ~27%, Leg ~18%, Mythic ~15%
-------------------------------------------------

local rng = Random.new()

local RARITY_BASE_WEIGHTS = {
	Common    = 1000,
	Rare      = 100,
	Epic      = 10,
	Legendary = 1,
	Mythic    = 0.1,
}

local RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

local RARITY_EXPONENTS = {
	Common    = -0.5,
	Rare      =  0.2,
	Epic      =  0.5,
	Legendary =  0.8,
	Mythic    =  1.0,
}

local function pickStreamerByOdds(luckMultiplier: number)
	local list = Streamers.List
	if not list or #list == 0 then
		return nil
	end

	local L = math.max(1, luckMultiplier or 1)

	-------------------------------------------------
	-- PHASE 1: Pick a RARITY TIER
	-------------------------------------------------
	local rarityWeights = {}
	local rarityTotal = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		local base = RARITY_BASE_WEIGHTS[rarity]
		local exp = RARITY_EXPONENTS[rarity]
		local w = base * (L ^ exp)
		rarityWeights[rarity] = w
		rarityTotal = rarityTotal + w
	end

	local roll = rng:NextNumber() * rarityTotal
	local cumulative = 0
	local chosenRarity = "Common"
	for _, rarity in ipairs(RARITY_ORDER) do
		cumulative = cumulative + rarityWeights[rarity]
		if roll <= cumulative then
			chosenRarity = rarity
			break
		end
	end

	-------------------------------------------------
	-- PHASE 2: Pick a streamer WITHIN that rarity
	-- Weighted by 1/odds (lower odds = more common within the tier)
	-------------------------------------------------
	local candidates = Streamers.ByRarity[chosenRarity]
	if not candidates or #candidates == 0 then
		-- Fallback: pick first streamer in list
		return list[1]
	end
	if #candidates == 1 then
		return candidates[1]
	end

	local streamerWeights = {}
	local streamerTotal = 0
	for i, s in ipairs(candidates) do
		local odds = type(s.odds) == "number" and s.odds or 100
		if odds < 1 then odds = 1 end
		local w = 1 / odds
		streamerWeights[i] = w
		streamerTotal = streamerTotal + w
	end

	local roll2 = rng:NextNumber() * streamerTotal
	cumulative = 0
	for i, w in ipairs(streamerWeights) do
		cumulative = cumulative + w
		if roll2 <= cumulative then
			return candidates[i]
		end
	end

	return candidates[1]
end

-------------------------------------------------
-- EFFECT ROLL
-- After picking a streamer, roll whether they get an effect (e.g. Acid).
-- Each effect has a base rollChance (0-1) divided by rarityMult.
-- So Acid (15% base, 2x harder) = 7.5% chance per pull.
-------------------------------------------------

local function rollEffect()
	for _, effect in ipairs(Effects.List) do
		local chance = (effect.rollChance or 0) / (effect.rarityMult or 1)
		if rng:NextNumber() < chance then
			return effect.name
		end
	end
	return nil
end

-------------------------------------------------
-- PITY SYSTEM
-- Each spin increments all pity counters.
-- If a counter reaches its threshold, that rarity is guaranteed.
-- When a rarity is obtained (naturally or via pity), reset that
-- counter and all lower-rarity counters.
-------------------------------------------------

local RARITY_RANK = { Common = 0, Rare = 1, Epic = 2, Legendary = 3, Mythic = 4 }

local function checkPityGuarantee(data)
	local pity = data.pityCounters
	if not pity then return nil end
	local bestRarity = nil
	local bestRank = -1
	for _, rarity in ipairs(PITY_RARITY_ORDER) do
		local threshold = Economy.PityThresholds[rarity]
		if threshold and (pity[rarity] or 0) >= threshold then
			local rank = RARITY_RANK[rarity] or 0
			if rank > bestRank then
				bestRarity = rarity
				bestRank = rank
			end
		end
	end
	return bestRarity
end

local function incrementPityCounters(data)
	if not data.pityCounters then
		data.pityCounters = { Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
	end
	for _, rarity in ipairs(PITY_RARITY_ORDER) do
		data.pityCounters[rarity] = (data.pityCounters[rarity] or 0) + 1
	end
end

local function resetPityForRarity(data, obtainedRarity)
	if not data.pityCounters then return end
	local rank = RARITY_RANK[obtainedRarity] or 0
	for _, rarity in ipairs(PITY_RARITY_ORDER) do
		if (RARITY_RANK[rarity] or 0) <= rank then
			data.pityCounters[rarity] = 0
		end
	end
end

local function pickStreamerFromRarity(rarity)
	local candidates = Streamers.ByRarity[rarity]
	if not candidates or #candidates == 0 then return nil end
	if #candidates == 1 then return candidates[1] end
	local weights = {}
	local total = 0
	for i, s in ipairs(candidates) do
		local odds = type(s.odds) == "number" and s.odds or 100
		if odds < 1 then odds = 1 end
		local w = 1 / odds
		weights[i] = w
		total = total + w
	end
	local roll = rng:NextNumber() * total
	local cum = 0
	for i, w in ipairs(weights) do
		cum = cum + w
		if roll <= cum then return candidates[i] end
	end
	return candidates[1]
end

-------------------------------------------------
-- SPIN LOGIC
-------------------------------------------------

local function handleSpin(player)
	if not PlayerData then return end
	-- SECURITY FIX: Rate limit spins (~1s cooldown)
	local now = os.clock()
	local userId = player.UserId
	if lastSpinTime[userId] and (now - lastSpinTime[userId]) < SPIN_COOLDOWN then
		SpinResult:FireClient(player, { success = false, reason = "Too fast! Wait a moment." })
		return
	end
	lastSpinTime[userId] = now

	local data = PlayerData.Get(player)
	if not data then return end

	-- Check cost: use spin credit first, then cash
	local usedCredit = PlayerData.UseSpinCredit(player)
	if not usedCredit then
		if not PlayerData.SpendCash(player, Economy.SpinCost) then
			SpinResult:FireClient(player, { success = false, reason = "Not enough cash!" })
			return
		end
	end

	-- Rebirth + personal luck (1 luck = +1%) + potion multiplier
	local rebirthLuck = 1 + (data.rebirthCount * 0.02)
	local playerLuck = data.luck or 0
	local playerLuckPercent = (playerLuck / 100)
	local potionLuckMult = PotionService and PotionService.GetLuckMultiplier(player) or 1
	local totalLuck = SpinService.ServerLuckMultiplier * rebirthLuck * (1 + playerLuckPercent) * potionLuckMult

	-- Increment pity counters
	incrementPityCounters(data)

	-- Check for pity guarantee
	local pityRarity = checkPityGuarantee(data)
	local streamer
	local isPityHit = false

	if pityRarity then
		streamer = pickStreamerFromRarity(pityRarity)
		isPityHit = true
	else
		streamer = pickStreamerByOdds(totalLuck)
	end

	if not streamer then
		SpinResult:FireClient(player, { success = false, reason = "Config error." })
		return
	end

	-- Reset pity for the obtained rarity (and all lower)
	resetPityForRarity(data, streamer.rarity)

	local effect = rollEffect()
	PlayerData.AddToInventory(player, streamer.id, effect)

	local displayName = streamer.displayName
	if effect then
		local effectInfo = Effects.ByName[effect]
		if effectInfo then
			displayName = effectInfo.prefix .. " " .. displayName
		end
	end

	local effectiveOdds = streamer.odds
	if effect then
		local ei = Effects.ByName[effect]
		if ei and ei.rarityMult then
			effectiveOdds = math.floor(effectiveOdds * ei.rarityMult)
		end
	end

	SpinResult:FireClient(player, {
		success = true,
		streamerId = streamer.id,
		displayName = displayName,
		rarity = streamer.rarity,
		odds = effectiveOdds,
		effect = effect,
		pity = isPityHit or nil,
	})

	PlayerData.IncrementStat(player, "totalSpins", 1)

	-- Quest tracking
	if QuestService then
		QuestService.Increment(player, "spins", 1)
		if streamer.rarity == "Epic" or streamer.rarity == "Legendary" or streamer.rarity == "Mythic" then
			QuestService.Increment(player, "epicPulls", 1)
		end
		if streamer.rarity == "Legendary" or streamer.rarity == "Mythic" then
			QuestService.Increment(player, "legendaryPulls", 1)
		end
		if streamer.rarity == "Mythic" then
			QuestService.Increment(player, "mythicPulls", 1)
		end
		if effect then
			QuestService.Increment(player, "effectPulls", 1)
		end
	end

	if streamer.rarity == "Mythic" then
		MythicAlert:FireAllClients({
			playerName = player.Name,
			streamerId = streamer.id,
			displayName = displayName,
			effect = effect,
		})
	end
end

-------------------------------------------------
-- CRATE SPIN (buy at spin stand: cost + luck bonus)
-------------------------------------------------

local function handleCrateSpin(player, crateId: number)
	if not PlayerData then return end
	-- SECURITY FIX: Rate limit crate spins (~1s cooldown)
	local now = os.clock()
	local userId = player.UserId
	if lastSpinTime[userId] and (now - lastSpinTime[userId]) < SPIN_COOLDOWN then
		SpinResult:FireClient(player, { success = false, reason = "Too fast! Wait a moment." })
		return
	end
	lastSpinTime[userId] = now

	-- SECURITY FIX: Validate crateId type
	if type(crateId) ~= "number" or crateId ~= math.floor(crateId) then
		SpinResult:FireClient(player, { success = false, reason = "Invalid crate!" })
		return
	end

	local data = PlayerData.Get(player)
	if not data then return end

	-- Check rebirth requirement
	local rebirthReq = Economy.GetCrateRebirthRequirement(crateId)
	if (data.rebirthCount or 0) < rebirthReq then
		SpinResult:FireClient(player, {
			success = false,
			reason = "You must be Rebirth " .. rebirthReq .. " to use this case!",
		})
		return
	end

	local cost = Economy.CrateCosts[crateId]
	local luckBonus = Economy.CrateLuckBonuses[crateId]
	if not cost or not luckBonus then
		SpinResult:FireClient(player, { success = false, reason = "Invalid crate!" })
		return
	end

	if not PlayerData.SpendCash(player, cost) then
		SpinResult:FireClient(player, { success = false, reason = "Not enough cash!" })
		return
	end

	-- Rebirth + personal luck (1 luck = +1%) + crate luck (additive) + potion multiplier
	local rebirthLuck = 1 + (data.rebirthCount * 0.02)
	local playerLuck = data.luck or 0
	local playerLuckPercent = (playerLuck / 100)
	local potionLuckMult = PotionService and PotionService.GetLuckMultiplier(player) or 1
	local totalLuck = SpinService.ServerLuckMultiplier * rebirthLuck * (1 + playerLuckPercent + luckBonus) * potionLuckMult

	-- Increment pity counters
	incrementPityCounters(data)

	-- Check for pity guarantee
	local pityRarity = checkPityGuarantee(data)
	local streamer
	local isPityHit = false

	if pityRarity then
		streamer = pickStreamerFromRarity(pityRarity)
		isPityHit = true
	else
		streamer = pickStreamerByOdds(totalLuck)
	end

	if not streamer then
		PlayerData.AddCash(player, cost)
		SpinResult:FireClient(player, { success = false, reason = "Config error." })
		return
	end

	-- Reset pity for the obtained rarity (and all lower)
	resetPityForRarity(data, streamer.rarity)

	local effect = rollEffect()
	PlayerData.AddToInventory(player, streamer.id, effect)

	local displayName = streamer.displayName
	if effect then
		local effectInfo = Effects.ByName[effect]
		if effectInfo then displayName = effectInfo.prefix .. " " .. displayName end
	end

	local effectiveOdds2 = streamer.odds
	if effect then
		local ei2 = Effects.ByName[effect]
		if ei2 and ei2.rarityMult then
			effectiveOdds2 = math.floor(effectiveOdds2 * ei2.rarityMult)
		end
	end

	SpinResult:FireClient(player, {
		success = true,
		streamerId = streamer.id,
		displayName = displayName,
		rarity = streamer.rarity,
		odds = effectiveOdds2,
		effect = effect,
		pity = isPityHit or nil,
	})

	PlayerData.IncrementStat(player, "totalSpins", 1)

	-- Quest tracking
	if QuestService then
		QuestService.Increment(player, "spins", 1)
		if streamer.rarity == "Epic" or streamer.rarity == "Legendary" or streamer.rarity == "Mythic" then
			QuestService.Increment(player, "epicPulls", 1)
		end
		if streamer.rarity == "Legendary" or streamer.rarity == "Mythic" then
			QuestService.Increment(player, "legendaryPulls", 1)
		end
		if streamer.rarity == "Mythic" then
			QuestService.Increment(player, "mythicPulls", 1)
		end
		if effect then
			QuestService.Increment(player, "effectPulls", 1)
		end
	end

	if streamer.rarity == "Mythic" then
		MythicAlert:FireAllClients({
			playerName = player.Name,
			streamerId = streamer.id,
			displayName = displayName,
			effect = effect,
		})
	end
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function SpinService.Init(playerDataModule, baseServiceModule, potionServiceModule, questServiceModule)
	PlayerData = playerDataModule
	BaseService = baseServiceModule
	PotionService = potionServiceModule
	QuestService = questServiceModule

	SpinRequest.OnServerEvent:Connect(function(player)
		handleSpin(player)
	end)

	BuyCrateRequest.OnServerEvent:Connect(function(player, crateId: number)
		handleCrateSpin(player, crateId)
	end)

	-- Cleanup cooldown tracking on leave
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player)
		lastSpinTime[player.UserId] = nil
	end)
end

function SpinService.SetServerLuck(multiplier: number)
	SpinService.ServerLuckMultiplier = multiplier
end

return SpinService
