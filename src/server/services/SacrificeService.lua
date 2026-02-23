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
local QuestService

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SacrificeRequest = RemoteEvents:WaitForChild("SacrificeRequest")
local SacrificeResult = RemoteEvents:WaitForChild("SacrificeResult")

local STORAGE_OFFSET = 1000

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

--- Build a combined list of {virtualIdx, item} from hotbar + storage
--- Hotbar items: virtualIdx = 1..#inv, storage items: virtualIdx = 1001..1000+#storage
local function getCombined(player)
	local inv = PlayerData.GetInventory(player)
	local sto = PlayerData.GetStorage(player)
	local combined = {}
	for i, item in ipairs(inv) do
		table.insert(combined, { vi = i, item = item })
	end
	for i, item in ipairs(sto) do
		table.insert(combined, { vi = STORAGE_OFFSET + i, item = item })
	end
	return combined
end

--- Remove items by virtual indices (hotbar < 1000, storage >= 1001)
local function removeByVirtualIndices(player, vIndices)
	local hotbarIndices = {}
	local storageIndices = {}
	for _, vi in ipairs(vIndices) do
		if vi > STORAGE_OFFSET then
			table.insert(storageIndices, vi - STORAGE_OFFSET)
		else
			table.insert(hotbarIndices, vi)
		end
	end
	if #hotbarIndices > 0 then PlayerData.RemoveFromInventoryIndices(player, hotbarIndices) end
	if #storageIndices > 0 then PlayerData.RemoveFromStorageIndices(player, storageIndices) end
end

--- Count combined items matching rarity (and optional effect)
local function countByRarity(combined, rarity, effect)
	local n = 0
	for _, entry in ipairs(combined) do
		local item = entry.item
		local id = type(item) == "table" and item.id or item
		local e = type(item) == "table" and item.effect or nil
		local info = Streamers.ById[id]
		if info and info.rarity == rarity and (effect == nil or e == effect) then
			n = n + 1
		end
	end
	return n
end

--- Collect virtual indices of up to `need` items matching rarity (and optional effect)
local function indicesByRarity(combined, rarity, need, effect)
	local list = {}
	for _, entry in ipairs(combined) do
		if need <= 0 then break end
		local item = entry.item
		local id = type(item) == "table" and item.id or item
		local e = type(item) == "table" and item.effect or nil
		local info = Streamers.ById[id]
		if info and info.rarity == rarity and (effect == nil or e == effect) then
			table.insert(list, entry.vi)
			need = need - 1
		end
	end
	return list
end

--- Check and remove exact requirements: streamerId + effect + count (from combined)
local function hasAndRemoveExact(player, reqList)
	local combined = getCombined(player)
	local toRemove = {}
	local used = {}
	for _, r in ipairs(reqList) do
		local need = r.count or 1
		for _, entry in ipairs(combined) do
			if need <= 0 then break end
			if not used[entry.vi] then
				local item = entry.item
				local id = type(item) == "table" and item.id or item
				local e = type(item) == "table" and item.effect or nil
				if r.streamerId and id == r.streamerId and (r.effect == nil or e == r.effect) then
					table.insert(toRemove, entry.vi)
					used[entry.vi] = true
					need = need - 1
				end
			end
		end
		if need > 0 then return false end
	end
	removeByVirtualIndices(player, toRemove)
	return true
end

--- Check and remove rarity-based requirements (e.g. 1 common, 1 rare, ...)
local function hasAndRemoveByRarity(player, reqList)
	local combined = getCombined(player)
	for _, r in ipairs(reqList) do
		if countByRarity(combined, r.rarity, nil) < (r.count or 1) then
			return false
		end
	end
	local allIndices = {}
	for _, r in ipairs(reqList) do
		local need = r.count or 1
		local indices = indicesByRarity(combined, r.rarity, need, nil)
		for _, idx in ipairs(indices) do
			table.insert(allIndices, idx)
		end
	end
	removeByVirtualIndices(player, allIndices)
	return true
end

--- Count combined items matching a specific effect (any rarity)
local function countByEffect(combined, effect)
	local n = 0
	for _, entry in ipairs(combined) do
		local e = type(entry.item) == "table" and entry.item.effect or nil
		if e == effect then n = n + 1 end
	end
	return n
end

--- Collect virtual indices of up to `need` items matching a specific effect
local function indicesByEffect(combined, effect, need)
	local list = {}
	for _, entry in ipairs(combined) do
		if need <= 0 then break end
		local e = type(entry.item) == "table" and entry.item.effect or nil
		if e == effect then
			table.insert(list, entry.vi)
			need = need - 1
		end
	end
	return list
end

--- Check and remove effect-based requirements (e.g. 20 Acid cards)
local function hasAndRemoveByEffect(player, reqList)
	local combined = getCombined(player)
	for _, r in ipairs(reqList) do
		if countByEffect(combined, r.effectReq) < (r.count or 1) then
			return false
		end
	end
	local allIndices = {}
	for _, r in ipairs(reqList) do
		local indices = indicesByEffect(combined, r.effectReq, r.count or 1)
		for _, idx in ipairs(indices) do
			table.insert(allIndices, idx)
		end
	end
	removeByVirtualIndices(player, allIndices)
	return true
end

--- Get the virtual index of the highest earning item across hotbar+storage
local function getHighestEarningIndex(player)
	local combined = getCombined(player)
	local bestVI, bestPrice = nil, -1
	for _, entry in ipairs(combined) do
		local p = getSellPrice(entry.item)
		if p > bestPrice then bestVI = entry.vi; bestPrice = p end
	end
	return bestVI
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
	-- SECURITY FIX: Validate input
	if type(tradeIndex) ~= "number" or tradeIndex ~= math.floor(tradeIndex) then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid trade." })
		return
	end
	local trade = Sacrifice.GemTrades[tradeIndex]
	if not trade then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid trade." })
		return
	end
	local combined = getCombined(player)
	local count = countByRarity(combined, trade.rarity, nil)
	if count < trade.count then
		SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s (you have %d)."):format(trade.count, trade.rarity, count) })
		return
	end
	local indices = indicesByRarity(combined, trade.rarity, trade.count, nil)
	removeByVirtualIndices(player, indices)
	PlayerData.AddGems(player, trade.gems)
	SacrificeResult:FireClient(player, { success = true, sacrificeType = "GemTrade", gems = trade.gems })
	if QuestService then
		QuestService.Increment(player, "sacrificesDone", 1)
	end
end

-------------------------------------------------
-- ONE-TIME
-------------------------------------------------
local function handleOneTime(player, oneTimeId)
	-- SECURITY FIX: Validate input
	if type(oneTimeId) ~= "string" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end
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
	if QuestService then
		QuestService.Increment(player, "sacrificesDone", 1)
	end
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
	local combined = getCombined(player)
	for _, r in ipairs(cfg.req) do
		if countByRarity(combined, r.rarity, nil) < r.count then
			SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s."):format(r.count, r.rarity) })
			return
		end
	end
	-- Consume resources and charge
	for _, r in ipairs(cfg.req) do
		local freshCombined = getCombined(player)
		local indices = indicesByRarity(freshCombined, r.rarity, r.count, nil)
		removeByVirtualIndices(player, indices)
	end
	PlayerData.UseSacrificeCharge(player, "FiftyFifty", rechargeSec, cfg.maxCharges)
	-- Roll
	local cash = PlayerData.GetCash(player)
	local half = math.floor(cash / 2)
	local double = cash * 2
	if math.random() < 0.5 then
		PlayerData.SpendCash(player, cash - half)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "FiftyFifty", outcome = "half", newCash = half })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
	else
		PlayerData.AddCash(player, cash)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "FiftyFifty", outcome = "double", newCash = double })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
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
	local combined = getCombined(player)
	for _, r in ipairs(cfg.req) do
		if countByRarity(combined, r.rarity, nil) < r.count then
			SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s."):format(r.count, r.rarity) })
			return
		end
	end
	for _, r in ipairs(cfg.req) do
		local freshCombined = getCombined(player)
		local indices = indicesByRarity(freshCombined, r.rarity, r.count, nil)
		removeByVirtualIndices(player, indices)
	end
	PlayerData.UseSacrificeCharge(player, "FeelingLucky", rechargeSec, cfg.maxCharges)
	local mult = math.random() < 0.5 and 2 or 0
	PotionService.SetSacrificeLuck(player, mult, cfg.durationSeconds)
	SacrificeResult:FireClient(player, { success = true, sacrificeType = "FeelingLucky", outcome = mult == 2 and "buff" or "debuff", duration = cfg.durationSeconds })
	if QuestService then
		QuestService.Increment(player, "sacrificesDone", 1)
	end
end

-------------------------------------------------
-- STREAMER SACRIFICE (formerly "Don't Do It")
-- Player picks which streamer to sacrifice.
-------------------------------------------------
local function handleDontDoIt(player, chosenVI)
	local cfg = Sacrifice.DontDoIt
	if not chosenVI or type(chosenVI) ~= "number" then
		SacrificeResult:FireClient(player, { success = false, reason = "Pick a streamer to sacrifice!" })
		return
	end
	local item1
	if chosenVI > STORAGE_OFFSET then
		local sto = PlayerData.GetStorage(player)
		item1 = sto[chosenVI - STORAGE_OFFSET]
	else
		local inv = PlayerData.GetInventory(player)
		item1 = inv[chosenVI]
	end
	if not item1 then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid streamer!" })
		return
	end
	local id1 = type(item1) == "table" and item1.id or item1
	local info1 = Streamers.ById[id1]
	if not info1 then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid streamer." })
		return
	end
	-- Remove the player's chosen streamer
	removeByVirtualIndices(player, { chosenVI })
	local baseRarity = info1.rarity
	local chance = cfg.upgradeChances[baseRarity]
	if not chance then
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = false, reason = "Already Mythic!" })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
		return
	end
	local roll = math.random(1, 100)
	if roll > chance then
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = false })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
		return
	end
	local nextR = nextRarity(baseRarity)
	if not nextR then
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = false })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
		return
	end
	-- Preserve effect (Acid, Void, etc.) from the sacrificed streamer
	local baseEffect = type(item1) == "table" and item1.effect or nil
	local newId = randomStreamerOfRarity(nextR, nil)
	if newId then
		PlayerData.AddToInventory(player, newId, baseEffect)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = true, streamerId = newId, rarity = nextR, effect = baseEffect })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
	else
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "DontDoIt", upgraded = false })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
	end
end

-------------------------------------------------
-- GEM ROULETTE (wager gems, 50/50 double or lose all)
-------------------------------------------------
local function handleGemRoulette(player, wagerAmount)
	if type(wagerAmount) ~= "number" or wagerAmount <= 0 or wagerAmount ~= math.floor(wagerAmount) then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid wager amount." })
		return
	end
	local cfg = Sacrifice.GemRoulette
	local rechargeSec = cfg.rechargeMinutes * 60
	local charges = PlayerData.GetSacrificeChargeCount(player, "GemRoulette", cfg.maxCharges, rechargeSec)
	if charges <= 0 then
		SacrificeResult:FireClient(player, { success = false, reason = "No charges! 1 charge every " .. cfg.rechargeMinutes .. " min." })
		return
	end
	local data = PlayerData.Get(player)
	if not data then
		SacrificeResult:FireClient(player, { success = false, reason = "Data not loaded." })
		return
	end
	if (data.gems or 0) < wagerAmount then
		SacrificeResult:FireClient(player, { success = false, reason = "Not enough gems! You have " .. (data.gems or 0) .. "." })
		return
	end
	-- Consume charge
	PlayerData.UseSacrificeCharge(player, "GemRoulette", rechargeSec, cfg.maxCharges)
	-- Roll 50/50
	if math.random() < 0.5 then
		-- DOUBLE: add wagerAmount more gems (player keeps original + gains same amount)
		PlayerData.AddGems(player, wagerAmount)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "GemRoulette", outcome = "double", wager = wagerAmount, newGems = (data.gems or 0) + wagerAmount })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
	else
		-- GONE: remove the wagered gems
		data.gems = math.max(0, (data.gems or 0) - wagerAmount)
		PlayerData.Replicate(player)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "GemRoulette", outcome = "gone", wager = wagerAmount, newGems = data.gems })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
	end
end

-------------------------------------------------
-- ELEMENTAL (X of same effect+rarity → 1 random of that rarity+effect)
-------------------------------------------------
local function handleElemental(player, effect, rarity)
	-- SECURITY FIX: Validate inputs
	if type(effect) ~= "string" or type(rarity) ~= "string" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end
	local need = Sacrifice.ElementalRates[rarity]
	if not need then
		SacrificeResult:FireClient(player, { success = false, reason = "Mythic has no conversion." })
		return
	end
	local combined = getCombined(player)
	local count = countByRarity(combined, rarity, effect)
	if count < need then
		SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s %s (you have %d)."):format(need, effect or "Default", rarity, count) })
		return
	end
	local indices = indicesByRarity(combined, rarity, need, effect)
	removeByVirtualIndices(player, indices)
	local newId = randomStreamerOfRarity(rarity, nil)
	if newId then
		PlayerData.AddToInventory(player, newId, effect)
		SacrificeResult:FireClient(player, { success = true, sacrificeType = "Elemental", streamerId = newId, effect = effect, rarity = rarity })
		if QuestService then
			QuestService.Increment(player, "sacrificesDone", 1)
		end
	else
		SacrificeResult:FireClient(player, { success = false, reason = "No streamer for that rarity." })
	end
end

-------------------------------------------------
-- REQUEST HANDLER
-------------------------------------------------
local function onSacrificeRequest(player, sacrificeType, ...)
	-- SECURITY FIX: Validate sacrificeType is a string
	if type(sacrificeType) ~= "string" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end
	if sacrificeType == "GemTrade" then
		handleGemTrade(player, ...)
	elseif sacrificeType == "OneTime" then
		handleOneTime(player, ...)
	elseif sacrificeType == "FiftyFifty" then
		handleFiftyFifty(player)
	elseif sacrificeType == "FeelingLucky" then
		handleFeelingLucky(player)
	elseif sacrificeType == "DontDoIt" then
		handleDontDoIt(player, ...)
	elseif sacrificeType == "GemRoulette" then
		handleGemRoulette(player, ...)
	elseif sacrificeType == "Elemental" then
		handleElemental(player, ...)
	else
		SacrificeResult:FireClient(player, { success = false, reason = "Unknown type." })
	end
end

-------------------------------------------------
-- INIT
-------------------------------------------------
function SacrificeService.Init(playerDataModule, potionServiceModule, questServiceModule)
	PlayerData = playerDataModule
	PotionService = potionServiceModule
	QuestService = questServiceModule
	-- SECURITY FIX: Wrap sacrifice handler in per-player lock to prevent race conditions
	SacrificeRequest.OnServerEvent:Connect(function(player, ...)
		local args = {...}
		PlayerData.WithLock(player, function() onSacrificeRequest(player, unpack(args)) end)
	end)
end

return SacrificeService
