--[[
	SacrificeService.lua
	Handles all sacrifice actions: gem trades, one-time quests,
	and elemental conversion.

	Queue-based flow:
	- Players add streamers to a per-sacrifice queue (a persistent storage spot).
	- Items leave inventory/storage and live in the queue until consumed or returned.
	- When the queue is full, the player can exchange for gems.
	- Queues persist across sessions via PlayerData.sacrificeQueues.
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
local SacrificeQueueAction = RemoteEvents:WaitForChild("SacrificeQueueAction")

local STORAGE_OFFSET = 1000

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function getItemId(item)
	if type(item) == "table" then return item.id end
	if type(item) == "string" then return item end
	return nil
end

local function getItemEffect(item)
	if type(item) ~= "table" then return nil end
	local e = item.effect
	if e == nil or e == "" then return nil end
	return e
end

local function itemMatchesRarity(item, rarity)
	local id = getItemId(item)
	local info = Streamers.ById[id]
	return info and info.rarity == rarity
end

local function itemMatchesExact(item, streamerId, effect)
	local id = getItemId(item)
	local eff = getItemEffect(item)
	if id ~= streamerId then return false end
	if effect ~= nil and eff ~= effect then return false end
	return true
end

local function itemMatchesEffect(item, effectName)
	local eff = getItemEffect(item)
	return eff == effectName
end

local function itemMatchesRarityAndEffect(item, rarity, effectName)
	local id = getItemId(item)
	local eff = getItemEffect(item)
	local info = Streamers.ById[id]
	if not info or info.rarity ~= rarity then return false end
	if effectName == nil then return eff == nil end
	return eff == effectName
end

local function randomStreamerOfRarity(rarity)
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
-- QUEUE MANAGEMENT (server-side)
-- Players add/remove items via SacrificeQueueAction remote.
-- Items are moved between inventory/storage and the queue.
-------------------------------------------------

local function countQueueItems(queue)
	local count = 0
	for _, v in ipairs(queue) do
		if v and v ~= false then count = count + 1 end
	end
	return count
end

local function handleQueueAdd(player, queueId, sourceType, sourceIndex, targetSlot)
	if type(queueId) ~= "string" or type(sourceType) ~= "string" or type(sourceIndex) ~= "number" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid queue request." })
		return
	end
	if sourceIndex ~= math.floor(sourceIndex) or sourceIndex < 1 then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid index." })
		return
	end
	if sourceType ~= "hotbar" and sourceType ~= "storage" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid source." })
		return
	end
	if targetSlot ~= nil and (type(targetSlot) ~= "number" or targetSlot ~= math.floor(targetSlot) or targetSlot < 1) then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid target slot." })
		return
	end

	local ok = PlayerData.AddToSacrificeQueue(player, queueId, sourceType, sourceIndex, targetSlot)
	if not ok then
		SacrificeResult:FireClient(player, { success = false, reason = "Could not add to queue." })
		return
	end
	SacrificeResult:FireClient(player, { success = true, action = "queueAdd", queueId = queueId })
end

local function handleQueueRemove(player, queueId, queueIndex)
	if type(queueId) ~= "string" or type(queueIndex) ~= "number" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid queue request." })
		return
	end
	if queueIndex ~= math.floor(queueIndex) or queueIndex < 1 then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid index." })
		return
	end

	local ok = PlayerData.RemoveFromSacrificeQueue(player, queueId, queueIndex)
	if not ok then
		SacrificeResult:FireClient(player, { success = false, reason = "Could not remove from queue. Inventory/storage may be full." })
		return
	end
	SacrificeResult:FireClient(player, { success = true, action = "queueRemove", queueId = queueId })
end

local function handleQueueClear(player, queueId)
	if type(queueId) ~= "string" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid queue request." })
		return
	end
	local ok, overflow = PlayerData.ClearSacrificeQueue(player, queueId)
	if not ok then
		SacrificeResult:FireClient(player, { success = false, action = "queueClear", reason = ("Not enough space! Free up %d inventory/storage slot%s first."):format(overflow, overflow == 1 and "" or "s") })
		return
	end
	SacrificeResult:FireClient(player, { success = true, action = "queueClear", queueId = queueId })
end

local function handleQueueAutoFill(player, queueId, filterType, filterArg1, filterArg2, maxCount)
	if type(queueId) ~= "string" or type(filterType) ~= "string" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid auto-fill request." })
		return
	end
	if type(maxCount) ~= "number" or maxCount < 1 then maxCount = 200 end
	maxCount = math.min(maxCount, 200)

	local data = PlayerData.Get(player)
	if not data then return end
	if not data.sacrificeQueues then data.sacrificeQueues = {} end
	if not data.sacrificeQueues[queueId] then data.sacrificeQueues[queueId] = {} end

	local queue = data.sacrificeQueues[queueId]
	local added = 0
	local existing = countQueueItems(queue)
	local remaining = maxCount - existing
	if remaining <= 0 then
		SacrificeResult:FireClient(player, { success = true, action = "queueAutoFill", queueId = queueId, added = 0 })
		return
	end

	local function matches(item)
		if filterType == "rarity" then
			return itemMatchesRarity(item, filterArg1)
		elseif filterType == "effect" then
			return itemMatchesEffect(item, filterArg1)
		elseif filterType == "exact" then
			return itemMatchesExact(item, filterArg1, filterArg2)
		elseif filterType == "rarityEffect" then
			return itemMatchesRarityAndEffect(item, filterArg1, filterArg2)
		end
		return false
	end

	local function placeInQueue(itm)
		for j = 1, #queue do
			if queue[j] == false then
				queue[j] = itm
				return
			end
		end
		table.insert(queue, itm)
	end

	for i = #data.inventory, 1, -1 do
		if added >= remaining then break end
		if matches(data.inventory[i]) then
			local item = table.remove(data.inventory, i)
			placeInQueue(item)
			added = added + 1
		end
	end

	if added < remaining and data.storage then
		for i = #data.storage, 1, -1 do
			if added >= remaining then break end
			if matches(data.storage[i]) then
				local item = table.remove(data.storage, i)
				placeInQueue(item)
				added = added + 1
			end
		end
	end

	PlayerData.Replicate(player)
	SacrificeResult:FireClient(player, { success = true, action = "queueAutoFill", queueId = queueId, added = added })
end

-------------------------------------------------
-- GEM TRADE (repeatable)
-------------------------------------------------
local function handleGemTrade(player, tradeIndex)
	if type(tradeIndex) ~= "number" or tradeIndex ~= math.floor(tradeIndex) then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid trade." })
		return
	end
	local trade = Sacrifice.GemTrades[tradeIndex]
	if not trade then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid trade." })
		return
	end

	local queueId = "GemTrade_" .. tradeIndex
	local queue = PlayerData.GetSacrificeQueue(player, queueId)
	local queueCount = countQueueItems(queue)

	if queueCount < trade.count then
		SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s in queue (you have %d)."):format(trade.count, trade.rarity, queueCount) })
		return
	end

	for _, item in ipairs(queue) do
		if item and item ~= false and not itemMatchesRarity(item, trade.rarity) then
			SacrificeResult:FireClient(player, { success = false, reason = "Queue contains items of the wrong rarity." })
			return
		end
	end

	local consumed = PlayerData.ConsumeSacrificeQueue(player, queueId)
	if #consumed > trade.count then
		for ei = trade.count + 1, #consumed do
			local item = consumed[ei]
			if item and item ~= false then
				local sid = type(item) == "table" and item.id or item
				local eff = type(item) == "table" and item.effect or nil
				PlayerData.AddToInventory(player, sid, eff)
			end
		end
	end
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

	local queueId = "OneTime_" .. oneTimeId
	local queue = PlayerData.GetSacrificeQueue(player, queueId)
	local queueCount = countQueueItems(queue)

	local totalNeeded = 0
	for _, r in ipairs(cfg.req) do totalNeeded = totalNeeded + (r.count or 1) end

	if queueCount < totalNeeded then
		SacrificeResult:FireClient(player, { success = false, reason = "Queue is not full yet." })
		return
	end

	local hasEffectReq = false
	local hasRarityReq = false
	local hasExactReq = false
	for _, r in ipairs(cfg.req) do
		if r.effectReq then hasEffectReq = true
		elseif r.rarity then hasRarityReq = true
		elseif r.streamerId then hasExactReq = true end
	end

	if hasEffectReq or hasRarityReq then
		local used = {}
		for _, r in ipairs(cfg.req) do
			local need = r.count or 1
			for qi, item in ipairs(queue) do
				if need <= 0 then break end
				if item and item ~= false and not used[qi] then
					local matches = false
					if r.effectReq then
						matches = itemMatchesEffect(item, r.effectReq)
					elseif r.rarity and r.effect then
						matches = itemMatchesRarityAndEffect(item, r.rarity, r.effect)
					elseif r.rarity then
						matches = itemMatchesRarity(item, r.rarity)
					end
					if matches then
						used[qi] = true
						need = need - 1
					end
				end
			end
			if need > 0 then
				SacrificeResult:FireClient(player, { success = false, reason = "Queue doesn't have the required streamers." })
				return
			end
		end
	elseif hasExactReq then
		local used = {}
		for _, r in ipairs(cfg.req) do
			local need = r.count or 1
			for qi, item in ipairs(queue) do
				if need <= 0 then break end
				if item and item ~= false and not used[qi] and itemMatchesExact(item, r.streamerId, r.effect) then
					used[qi] = true
					need = need - 1
				end
			end
			if need > 0 then
				SacrificeResult:FireClient(player, { success = false, reason = "Queue doesn't have the required streamers." })
				return
			end
		end
	end

	local consumed = PlayerData.ConsumeSacrificeQueue(player, queueId)
	if #consumed > totalNeeded then
		for ei = totalNeeded + 1, #consumed do
			local item = consumed[ei]
			if item and item ~= false then
				local sid = type(item) == "table" and item.id or item
				local eff = type(item) == "table" and item.effect or nil
				PlayerData.AddToInventory(player, sid, eff)
			end
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
-- ELEMENTAL (X of same effect+rarity -> 1 random of that rarity+effect)
-------------------------------------------------
local function handleElemental(player, effect, rarity)
	if type(effect) ~= "string" or type(rarity) ~= "string" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end
	local need = Sacrifice.ElementalRates[rarity]
	if not need then
		SacrificeResult:FireClient(player, { success = false, reason = "Mythic has no conversion." })
		return
	end

	local queueId = "Elemental_" .. effect .. "_" .. rarity
	local queue = PlayerData.GetSacrificeQueue(player, queueId)
	local queueCount = countQueueItems(queue)

	if queueCount < need then
		SacrificeResult:FireClient(player, { success = false, reason = ("Need %d %s %s in queue (you have %d)."):format(need, effect, rarity, queueCount) })
		return
	end

	for _, item in ipairs(queue) do
		if item and item ~= false and not itemMatchesRarityAndEffect(item, rarity, effect) then
			SacrificeResult:FireClient(player, { success = false, reason = "Queue contains items that don't match." })
			return
		end
	end

	local consumed = PlayerData.ConsumeSacrificeQueue(player, queueId)
	if #consumed > need then
		for ei = need + 1, #consumed do
			local item = consumed[ei]
			if item and item ~= false then
				local sid = type(item) == "table" and item.id or item
				local eff = type(item) == "table" and item.effect or nil
				PlayerData.AddToInventory(player, sid, eff)
			end
		end
	end
	local newId = randomStreamerOfRarity(rarity)
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
	if type(sacrificeType) ~= "string" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end
	if not PlayerData.IsTutorialComplete(player) then
		SacrificeResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end
	if sacrificeType == "GemTrade" then
		handleGemTrade(player, ...)
	elseif sacrificeType == "OneTime" then
		handleOneTime(player, ...)
	elseif sacrificeType == "Elemental" then
		handleElemental(player, ...)
	elseif sacrificeType == "FiftyFifty"
		or sacrificeType == "FeelingLucky"
		or sacrificeType == "DontDoIt"
		or sacrificeType == "GemRoulette"
	then
		SacrificeResult:FireClient(player, { success = false, reason = "Test Your Luck is disabled." })
	else
		SacrificeResult:FireClient(player, { success = false, reason = "Unknown type." })
	end
end

local function onQueueAction(player, action, ...)
	if type(action) ~= "string" then
		SacrificeResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end
	if not PlayerData.IsTutorialComplete(player) then
		SacrificeResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end
	if action == "add" then
		handleQueueAdd(player, ...)
	elseif action == "remove" then
		handleQueueRemove(player, ...)
	elseif action == "clear" then
		handleQueueClear(player, ...)
	elseif action == "autoFill" then
		handleQueueAutoFill(player, ...)
	elseif action == "fullSync" then
		-- Legacy: no-op
	elseif action == "returnAll" then
		-- Legacy: no-op
	else
		SacrificeResult:FireClient(player, { success = false, reason = "Unknown queue action." })
	end
end

-------------------------------------------------
-- INIT
-------------------------------------------------
function SacrificeService.Init(playerDataModule, potionServiceModule, questServiceModule)
	PlayerData = playerDataModule
	PotionService = potionServiceModule
	QuestService = questServiceModule

	SacrificeRequest.OnServerEvent:Connect(function(player, ...)
		local args = {...}
		PlayerData.WithLock(player, function() onSacrificeRequest(player, unpack(args)) end)
	end)

	SacrificeQueueAction.OnServerEvent:Connect(function(player, ...)
		local args = {...}
		PlayerData.WithLock(player, function() onQueueAction(player, unpack(args)) end)
	end)
end

return SacrificeService
