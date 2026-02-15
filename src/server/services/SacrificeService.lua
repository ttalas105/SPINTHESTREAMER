--[[
	SacrificeService.lua
	Handles all sacrifice actions: gem trades, one-time quests,
	50/50, Feeling Lucky, Don't do it, and elemental conversion.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sacrifice = require(ReplicatedStorage.Shared.Config.Sacrifice)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)

local SacrificeService = {}

local PlayerData
local PotionService

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SacrificeRequest = RemoteEvents:WaitForChild("SacrificeRequest")
local SacrificeResult = RemoteEvents:WaitForChild("SacrificeResult")

local function getSellPrice(item)
	local id = type(item) == "table" and item.id or item
	local effect = type(item) == "table" and item.effect or nil
	local info = Streamers.ById[id]
	if not info then return 0 end
	local p = info.cashPerSecond or 0
	if effect then
		local ei = Effects.ByName[effect]
		if ei and ei.cashMultiplier then p = p * ei.cashMultiplier end
	end
	return math.floor(p)
end

--- Count inventory items matching rarity (and optional effect)
local function countByRarity(inventory, rarity, effect)
	local n = 0
	for _, item in ipairs(inventory) do
		local id = type(item) == "table" and item.id or item
		local e = type(item) == "table" and item.effect or nil
		local info = Streamers.ById[id]
		if info and info.rarity == rarity and (effect == nil or e == effect) then
			n = n + 1
		end
	end
	return n
end

--- Collect indices of up to `need` items matching rarity (and optional effect)
local function indicesByRarity(inventory, rarity, need, effect)
	local list = {}
	for i, item in ipairs(inventory) do
		if need <= 0 then break end
		local id = type(item) == "table" and item.id or item
		local e = type(item) == "table" and item.effect or nil
		local info = Streamers.ById[id]
		if info and info.rarity == rarity and (effect == nil or e == effect) then
			table.insert(list, i)
			need = need - 1
		end
	end
	return list
end

--- Check and remove exact requirements: streamerId + effect + count (from inventory in order)
local function hasAndRemoveExact(player, reqList)
	local inv = PlayerData.GetInventory(player)
	local toRemove = {}
	for _, r in ipairs(reqList) do
		local need = r.count or 1
		for i, item in ipairs(inv) do
			if need <= 0 then break end
			local id = type(item) == "table" and item.id or item
			local e = type(item) == "table" and item.effect or nil
			if r.streamerId and id == r.streamerId and (r.effect == nil or e == r.effect) then
				table.insert(toRemove, i)
				need = need - 1
			end
		end
		if need > 0 then return false end
	end
	PlayerData.RemoveFromInventoryIndices(player, toRemove)
	return true
end

--- Check and remove rarity-based requirements (e.g. 1 common, 1 rare, ...)
local function hasAndRemoveByRarity(player, reqList)
	local inv = PlayerData.GetInventory(player)
	for _, r in ipairs(reqList) do
		if countByRarity(inv, r.rarity, nil) < (r.count or 1) then
			return false
		end
	end
	local allIndices = {}
	for _, r in ipairs(reqList) do
		local need = r.count or 1
		local indices = indicesByRarity(inv, r.rarity, need, nil)
		for _, idx in ipairs(indices) do
			table.insert(allIndices, idx)
		end
	end
	PlayerData.RemoveFromInventoryIndices(player, allIndices)
	return true
end

--- Count inventory items matching a specific effect (any rarity)
local function countByEffect(inventory, effect)
	local n = 0
	for _, item in ipairs(inventory) do
		local e = type(item) == "table" and item.effect or nil
		if e == effect then n = n + 1 end
	end
	return n
end

--- Collect indices of up to `need` items matching a specific effect
local function indicesByEffect(inventory, effect, need)
	local list = {}
	for i, item in ipairs(inventory) do
		if need <= 0 then break end
		local e = type(item) == "table" and item.effect or nil
		if e == effect then
			table.insert(list, i)
			need = need - 1
		end
	end
	return list
end

--- Check and remove effect-based requirements (e.g. 20 Acid cards)
local function hasAndRemoveByEffect(player, reqList)
	local inv = PlayerData.GetInventory(player)
	for _, r in ipairs(reqList) do
		if countByEffect(inv, r.effectReq) < (r.count or 1) then
			return false
		end
	end
	local allIndices = {}
	for _, r in ipairs(reqList) do
		local indices = indicesByEffect(inv, r.effectReq, r.count or 1)
		for _, idx in ipairs(indices) do
			table.insert(allIndices, idx)
		end
	end
	PlayerData.RemoveFromInventoryIndices(player, allIndices)
	return true
end

--- Get the inventory index with the highest sell price
local function getHighestEarningIndex(inventory)
	local bestIdx, bestPrice = nil, -1
	for i, item in ipairs(inventory) do
		local p = getSellPrice(item)
		if p > bestPrice then bestIdx = i; bestPrice = p end
	end
	return bestIdx
end

--- Pick random streamer of given rarity (optionally with effect)
local function randomStreamerOfRarity(rarity, effect)
	local list = Streamers.ByRarity[rarity]
	if not list or #list == 0 then return nil end
	return list[math.random(1, #list)].id
end

local RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
local function nextRarity(rarity)
	for i, r in ipairs(RARITY_ORDER) do
		if r == rarity and i < #RARITY_ORDER then
			return RARITY_ORDER[i + 1]
		end
	end
	return nil
end

-------------------------------------------------
-- GEM TRADE (repeatable)
-------------------------------------------------
local function handleGemTrade(player, tradeIndex)
	local trade = Sacrifice.GemTrades[tradeIndex]
	if not trade then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid trade." })
		return
	end
	local inv = PlayerData.GetInventory(player)
	local count = countByRarity(inv, trade.rarity, nil)
	if count < trade.count then
		SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s (you have %d)."):format(trade.count, trade.rarity, count) })
		return
	end
	local indices = indicesByRarity(inv, trade.rarity, trade.count, nil)
	PlayerData.RemoveFromInventoryIndices(player, indices)
	PlayerData.AddGems(player, trade.gems)
	SacrificeResult:FireClient(player, { success = true, sacrificeType = "GemTrade", gems = trade.gems })
end

-------------------------------------------------
-- ONE-TIME
-------------------------------------------------
local function handleOneTime(player, oneTimeId)
	local cfg = Sacrifice.OneTime[oneTimeId]
	if not cfg then
		SacrificeResult:FireClient(player, { success = false, reason = "Unknown sacrifice." })
		return
	end
	if PlayerData.GetSacrificeOneTimeCompleted(player)[oneTimeId] then
		SacrificeResult:FireClient(player, { success = false, reason = "Already completed!" })
		return
	end
	-- Requirements can be exact (streamerId), by rarity (Rainbow), or by effect (elemental one-time)
	local isEffectReq = cfg.req[1] and cfg.req[1].effectReq ~= nil
	local isRarityReq = cfg.req[1] and cfg.req[1].rarity ~= nil
	if isEffectReq then
		if not hasAndRemoveByEffect(player, cfg.req) then
			local r = cfg.req[1]
			SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s cards (any rarity)."):format(r.count or 1, r.effectReq) })
			return
		end
	elseif isRarityReq then
		if not hasAndRemoveByRarity(player, cfg.req) then
			SacrificeResult:FireClient(player, { success = false, reason = "You don't have the required streamers (1 of each rarity)." })
			return
		end
	else
		if not hasAndRemoveExact(player, cfg.req) then
			SacrificeResult:FireClient(player, { success = false, reason = "You don't have the required streamers." })
			return
		end
	end
	PlayerData.SetSacrificeOneTimeCompleted(player, oneTimeId)
	PlayerData.AddGems(player, cfg.gems)
	SacrificeResult:FireClient(player, { success = true, sacrificeType = "OneTime", oneTimeId = oneTimeId, gems = cfg.gems })
end

-------------------------------------------------
-- 50/50
-------------------------------------------------
local function handleFiftyFifty(player)
	local cfg = Sacrifice.FiftyFifty
	local rechargeSec = cfg.rechargeMinutes * 60
	local charges = PlayerData.GetSacrificeChargeCount(player, "FiftyFifty", cfg.maxCharges, rechargeSec)
	if charges <= 0 then
		SacrificeResult:FireClient(player, { success = false, reason = "No charges! 1 charge every " .. cfg.rechargeMinutes .. " min." })
		return
	end
	local inv = PlayerData.GetInventory(player)
	for _, r in ipairs(cfg.req) do
		if countByRarity(inv, r.rarity, nil) < r.count then
			SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s."):format(r.count, r.rarity) })
			return
		end
	end
	-- Consume resources and charge
	for _, r in ipairs(cfg.req) do
		local indices = indicesByRarity(PlayerData.GetInventory(player), r.rarity, r.count, nil)
		PlayerData.RemoveFromInventoryIndices(player, indices)
	end
	PlayerData.UseSacrificeCharge(player, "FiftyFifty", rechargeSec, cfg.maxCharges)
	-- Roll
	local cash = PlayerData.GetCash(player)
	local half = math.floor(cash / 2)
	local double = cash * 2
	if math.random() < 0.5 then
		PlayerData.SpendCash(player, cash - half)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "FiftyFifty", outcome = "half", newCash = half })
	else
		PlayerData.AddCash(player, cash)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "FiftyFifty", outcome = "double", newCash = double })
	end
end

-------------------------------------------------
-- FEELING LUCKY
-------------------------------------------------
local function handleFeelingLucky(player)
	local cfg = Sacrifice.FeelingLucky
	local rechargeSec = cfg.rechargeMinutes * 60
	local charges = PlayerData.GetSacrificeChargeCount(player, "FeelingLucky", cfg.maxCharges, rechargeSec)
	if charges <= 0 then
		SacrificeResult:FireClient(player, { success = false, reason = "No charges! Recharges in " .. cfg.rechargeMinutes .. " min." })
		return
	end
	local inv = PlayerData.GetInventory(player)
	for _, r in ipairs(cfg.req) do
		if countByRarity(inv, r.rarity, nil) < r.count then
			SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s."):format(r.count, r.rarity) })
			return
		end
	end
	for _, r in ipairs(cfg.req) do
		local indices = indicesByRarity(PlayerData.GetInventory(player), r.rarity, r.count, nil)
		PlayerData.RemoveFromInventoryIndices(player, indices)
	end
	PlayerData.UseSacrificeCharge(player, "FeelingLucky", rechargeSec, cfg.maxCharges)
	local mult = math.random() < 0.5 and 2 or 0
	PotionService.SetSacrificeLuck(player, mult, cfg.durationSeconds)
	SacrificeResult:FireClient(player, { success = true, sacrificeType = "FeelingLucky", outcome = mult == 2 and "buff" or "debuff", duration = cfg.durationSeconds })
end

-------------------------------------------------
-- DON'T DO IT
-------------------------------------------------
local function handleDontDoIt(player)
	local cfg = Sacrifice.DontDoIt
	local inv = PlayerData.GetInventory(player)
	local bestIdx = getHighestEarningIndex(inv)
	if not bestIdx then
		SacrificeResult:FireClient(player, { success = false, reason = "You need at least 1 streamer!" })
		return
	end
	local item1 = inv[bestIdx]
	local id1 = type(item1) == "table" and item1.id or item1
	local info1 = Streamers.ById[id1]
	if not info1 then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid streamer." })
		return
	end
	-- Remove the single highest-earning streamer
	PlayerData.RemoveFromInventory(player, bestIdx)
	local baseRarity = info1.rarity
	local chance = cfg.upgradeChances[baseRarity]
	if not chance then
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = false, reason = "Already Mythic!" })
		return
	end
	local roll = math.random(1, 100)
	if roll > chance then
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = false })
		return
	end
	local nextR = nextRarity(baseRarity)
	if not nextR then
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = false })
		return
	end
	-- Preserve effect (Acid, Void, etc.) from the sacrificed streamer
	local baseEffect = type(item1) == "table" and item1.effect or nil
	local newId = randomStreamerOfRarity(nextR, nil)
	if newId then
		PlayerData.AddToInventory(player, newId, baseEffect)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = true, streamerId = newId, rarity = nextR, effect = baseEffect })
	else
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = false })
	end
end

-------------------------------------------------
-- ELEMENTAL (X of same effect+rarity → 1 random of that rarity+effect)
-------------------------------------------------
local function handleElemental(player, effect, rarity)
	local need = Sacrifice.ElementalRates[rarity]
	if not need then
		SacrificeResult:FireClient(player, { success = false, reason = "Mythic has no conversion." })
		return
	end
	local inv = PlayerData.GetInventory(player)
	local count = countByRarity(inv, rarity, effect)
	if count < need then
		SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s %s (you have %d)."):format(need, effect or "Default", rarity, count) })
		return
	end
	local indices = indicesByRarity(inv, rarity, need, effect)
	PlayerData.RemoveFromInventoryIndices(player, indices)
	local newId = randomStreamerOfRarity(rarity, nil)
	if newId then
		PlayerData.AddToInventory(player, newId, effect)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "Elemental", streamerId = newId, effect = effect, rarity = rarity })
	else
		SacrificeResult:FireClient(player, { success = false, reason = "No streamer for that rarity." })
	end
end

-------------------------------------------------
-- REQUEST HANDLER
-------------------------------------------------
local function onSacrificeRequest(player, sacrificeType, ...)
	if sacrificeType == "GemTrade" then
		handleGemTrade(player, ...)
	elseif sacrificeType == "OneTime" then
		handleOneTime(player, ...)
	elseif sacrificeType == "FiftyFifty" then
		handleFiftyFifty(player)
	elseif sacrificeType == "FeelingLucky" then
		handleFeelingLucky(player)
	elseif sacrificeType == "DontDoIt" then
		handleDontDoIt(player)
	elseif sacrificeType == "Elemental" then
		handleElemental(player, ...)
	else
		SacrificeResult:FireClient(player, { success = false, reason = "Unknown type." })
	end
end

-------------------------------------------------
-- INIT
-------------------------------------------------
function SacrificeService.Init(playerDataModule, potionServiceModule)
	PlayerData = playerDataModule
	PotionService = potionServiceModule
	SacrificeRequest.OnServerEvent:Connect(onSacrificeRequest)
end

return SacrificeService
