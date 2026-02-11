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

local SpinService = {}

SpinService.ServerLuckMultiplier = Economy.DefaultLuckMultiplier

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SpinRequest = RemoteEvents:WaitForChild("SpinRequest")
local SpinResult = RemoteEvents:WaitForChild("SpinResult")
local MythicAlert = RemoteEvents:WaitForChild("MythicAlert")
local BuyCrateRequest = RemoteEvents:WaitForChild("BuyCrateRequest")

local PlayerData
local BaseService

-------------------------------------------------
-- RNG: TWO-PHASE RARITY-FIRST SYSTEM
-- Phase 1: Roll a RARITY TIER (luck crushes Common, boosts Rare+)
-- Phase 2: Roll a specific streamer within that tier (weighted by 1/odds)
--
-- Luck formula: every 10 luck = 1%. Total luckPercent is passed as luckMultiplier.
-- luckMultiplier = 1 + (playerLuck/10/100) + crateLuckBonus
-- So 2000 luck + Case7(250%) => luckMultiplier = 1 + 2.0 + 2.5 = 5.5
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
	Common    = -3,  -- DIVIDED by L^3
	Rare      =  1,  -- multiplied by L^1
	Epic      =  2,  -- multiplied by L^2
	Legendary =  3,  -- multiplied by L^3
	Mythic    =  4,  -- multiplied by L^4
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
	return nil -- no effect (normal pull)
end

-------------------------------------------------
-- SPIN LOGIC
-------------------------------------------------

local function handleSpin(player)
	if not PlayerData then return end
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

	-- Rebirth + personal luck (every 10 luck = +1%)
	local rebirthLuck = 1 + (data.rebirthCount * 0.02)
	local playerLuck = data.luck or 0
	local playerLuckPercent = math.floor(playerLuck / 10) / 100
	local totalLuck = SpinService.ServerLuckMultiplier * rebirthLuck * (1 + playerLuckPercent)

	-- Roll using two-phase rarity-first system
	local streamer = pickStreamerByOdds(totalLuck)
	if not streamer then
		SpinResult:FireClient(player, { success = false, reason = "Config error." })
		return
	end

	-- Roll for an effect (e.g. Acid)
	local effect = rollEffect()

	-- Add to inventory with effect
	PlayerData.AddToInventory(player, streamer.id, effect)

	-- Build display name with effect prefix
	local displayName = streamer.displayName
	if effect then
		local effectInfo = Effects.ByName[effect]
		if effectInfo then
			displayName = effectInfo.prefix .. " " .. displayName
		end
	end

	-- Send result to client (include odds and effect for display)
	SpinResult:FireClient(player, {
		success = true,
		streamerId = streamer.id,
		displayName = displayName,
		rarity = streamer.rarity,
		odds = streamer.odds,
		effect = effect,
	})

	-- Mythic server-wide alert
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
	local data = PlayerData.Get(player)
	if not data then return end

	local crateCosts = {
		[1] = Economy.Crate1Cost,
		[2] = Economy.Crate2Cost,
		[3] = Economy.Crate3Cost,
		[4] = Economy.Crate4Cost,
		[5] = Economy.Crate5Cost,
		[6] = Economy.Crate6Cost,
		[7] = Economy.Crate7Cost,
	}
	local crateLuck = {
		[1] = Economy.Crate1LuckBonus,
		[2] = Economy.Crate2LuckBonus,
		[3] = Economy.Crate3LuckBonus,
		[4] = Economy.Crate4LuckBonus,
		[5] = Economy.Crate5LuckBonus,
		[6] = Economy.Crate6LuckBonus,
		[7] = Economy.Crate7LuckBonus,
	}
	local cost = crateCosts[crateId]
	local luckBonus = crateLuck[crateId]
	if not cost or not luckBonus then
		SpinResult:FireClient(player, { success = false, reason = "Invalid crate!" })
		return
	end

	if not PlayerData.SpendCash(player, cost) then
		SpinResult:FireClient(player, { success = false, reason = "Not enough cash!" })
		return
	end

	-- Rebirth + personal luck (every 10 = +1%) + crate luck (additive)
	local rebirthLuck = 1 + (data.rebirthCount * 0.02)
	local playerLuck = data.luck or 0
	local playerLuckPercent = math.floor(playerLuck / 10) / 100
	local totalLuck = SpinService.ServerLuckMultiplier * rebirthLuck * (1 + playerLuckPercent + luckBonus)

	local streamer = pickStreamerByOdds(totalLuck)
	if not streamer then
		PlayerData.AddCash(player, cost) -- Refund
		SpinResult:FireClient(player, { success = false, reason = "Config error." })
		return
	end

	-- Roll for effect
	local effect = rollEffect()
	PlayerData.AddToInventory(player, streamer.id, effect)

	local displayName = streamer.displayName
	if effect then
		local effectInfo = Effects.ByName[effect]
		if effectInfo then displayName = effectInfo.prefix .. " " .. displayName end
	end

	SpinResult:FireClient(player, {
		success = true,
		streamerId = streamer.id,
		displayName = displayName,
		rarity = streamer.rarity,
		odds = streamer.odds,
		effect = effect,
	})

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

function SpinService.Init(playerDataModule, baseServiceModule)
	PlayerData = playerDataModule
	BaseService = baseServiceModule

	SpinRequest.OnServerEvent:Connect(function(player)
		handleSpin(player)
	end)

	BuyCrateRequest.OnServerEvent:Connect(function(player, crateId: number)
		handleCrateSpin(player, crateId)
	end)
end

function SpinService.SetServerLuck(multiplier: number)
	SpinService.ServerLuckMultiplier = multiplier
end

return SpinService
