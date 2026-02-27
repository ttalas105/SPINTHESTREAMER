--[[
	EconomyService.lua
	Handles economy: passive income, selling from inventory, cash multipliers.
	Sell flow: player selects item from inventory -> sell for cash.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SellRequest = RemoteEvents:WaitForChild("SellRequest")
local SellResult = RemoteEvents:WaitForChild("SellResult")
local SellByIndexRequest = RemoteEvents:WaitForChild("SellByIndexRequest")
local SellAllRequest = RemoteEvents:WaitForChild("SellAllRequest")
local UpgradeLuckRequest = RemoteEvents:WaitForChild("UpgradeLuckRequest")
local UpgradeLuckResult = RemoteEvents:WaitForChild("UpgradeLuckResult")
local UpgradeCashRequest = RemoteEvents:WaitForChild("UpgradeCashRequest")
local UpgradeCashResult = RemoteEvents:WaitForChild("UpgradeCashResult")

local EconomyService = {}

local PlayerData
local PotionService
local QuestService

-------------------------------------------------
-- SELL HELPERS
-------------------------------------------------

-- Calculate sell price for an inventory item (rarity-based + effect bonus)
local function getSellPrice(item)
	local streamerId = type(item) == "table" and item.id or item
	local effect = type(item) == "table" and item.effect or nil
	local info = Streamers.ById[streamerId]
	if not info then return 0 end

	local price = Economy.SellPrices[info.rarity] or Economy.SellPrices.Common
	if effect and effect ~= "" then
		price = price * (Economy.EffectSellMultiplier or 1.5)
	end
	return math.floor(price)
end

-------------------------------------------------
-- SELL FROM INVENTORY (legacy: by streamer ID)
-------------------------------------------------

local function handleSell(player, streamerId: string)
	if not PlayerData then return end
	if typeof(streamerId) ~= "string" then return end
	if not PlayerData.IsTutorialComplete(player) then
		SellResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end

	local streamerInfo = Streamers.ById[streamerId]
	if not streamerInfo then
		SellResult:FireClient(player, { success = false, reason = "Unknown streamer." })
		return
	end

	-- Find item in inventory to calculate price before removing
	local data = PlayerData.Get(player)
	if not data then return end
	local price = 0
	for i, item in ipairs(data.inventory) do
		local id = type(item) == "table" and item.id or item
		if id == streamerId then
			price = getSellPrice(item)
			break
		end
	end

	local removed = PlayerData.RemoveStreamerFromInventory(player, streamerId)
	if not removed then
		SellResult:FireClient(player, { success = false, reason = "Not in your inventory!" })
		return
	end

	if PlayerData.HasDoubleCash(player) then
		price = price * Economy.DoubleCashMultiplier
	end
	if PlayerData.HasVIP(player) then
		price = math.floor(price * (Economy.VIPCashMultiplier or 1.5))
	end

	PlayerData.AddCash(player, price)
	PlayerData.IncrementStat(player, "totalCashEarned", price)
	SellResult:FireClient(player, {
		success = true,
		streamerId = streamerId,
		cashEarned = price,
	})
	if QuestService then
		QuestService.Increment(player, "sells", 1)
		QuestService.Increment(player, "cashEarned", price)
	end
end

-------------------------------------------------
-- SELL BY INDEX (sell a specific item from inventory or storage)
-------------------------------------------------

local function handleSellByIndex(player, itemIndex: number, source: string?)
	if not PlayerData then return end
	if typeof(itemIndex) ~= "number" then return end
	if source ~= nil and typeof(source) ~= "string" then return end
	if not PlayerData.IsTutorialComplete(player) then
		SellResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end

	local data = PlayerData.Get(player)
	if not data then return end
	local fromStorage = source == "storage"
	local item
	local removed
	if fromStorage then
		if itemIndex < 1 or itemIndex > #data.storage then
			SellResult:FireClient(player, { success = false, reason = "Invalid index." })
			return
		end
		item = data.storage[itemIndex]
		removed = PlayerData.RemoveFromStorage(player, itemIndex)
	else
		if itemIndex < 1 or itemIndex > #data.inventory then
			SellResult:FireClient(player, { success = false, reason = "Invalid index." })
			return
		end
		item = data.inventory[itemIndex]
		removed = PlayerData.RemoveFromInventory(player, itemIndex)
	end
	local price = getSellPrice(item)

	if not removed then
		SellResult:FireClient(player, { success = false, reason = "Could not sell item." })
		return
	end

	if PlayerData.HasDoubleCash(player) then
		price = price * Economy.DoubleCashMultiplier
	end
	if PlayerData.HasVIP(player) then
		price = math.floor(price * (Economy.VIPCashMultiplier or 1.5))
	end

	PlayerData.AddCash(player, price)
	PlayerData.IncrementStat(player, "totalCashEarned", price)
	SellResult:FireClient(player, {
		success = true,
		streamerId = type(item) == "table" and item.id or item,
		cashEarned = price,
	})
	if QuestService then
		QuestService.Increment(player, "sells", 1)
		QuestService.Increment(player, "cashEarned", price)
	end
end

-------------------------------------------------
-- SELL ALL (sell every item in the selected section)
-------------------------------------------------

local function handleSellAll(player, source: string?)
	if not PlayerData then return end
	if source ~= nil and typeof(source) ~= "string" then
		SellResult:FireClient(player, { success = false, reason = "Invalid request." })
		return
	end
	if not PlayerData.IsTutorialComplete(player) then
		SellResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end
	local data = PlayerData.Get(player)
	if not data then return end
	local section = (source == "storage") and "storage" or "hotbar"

	local totalCash = 0
	local count = 0

	if section == "storage" then
		count = #data.storage
		if count == 0 then
			SellResult:FireClient(player, { success = false, reason = "Storage is empty!" })
			return
		end
		for _, item in ipairs(data.storage) do
			totalCash = totalCash + getSellPrice(item)
		end
	else
		count = #data.inventory
		if count == 0 then
			SellResult:FireClient(player, { success = false, reason = "Hotbar is empty!" })
			return
		end
		for _, item in ipairs(data.inventory) do
			totalCash = totalCash + getSellPrice(item)
		end
	end

	if PlayerData.HasDoubleCash(player) then
		totalCash = totalCash * Economy.DoubleCashMultiplier
	end
	if PlayerData.HasVIP(player) then
		totalCash = math.floor(totalCash * (Economy.VIPCashMultiplier or 1.5))
	end

	-- Clear only the requested section
	if section == "storage" then
		data.storage = {}
	else
		data.inventory = {}
	end
	PlayerData.AddCash(player, math.floor(totalCash))
	PlayerData.IncrementStat(player, "totalCashEarned", math.floor(totalCash))
	PlayerData.Replicate(player)

	SellResult:FireClient(player, {
		success = true,
		cashEarned = math.floor(totalCash),
		soldCount = count,
		sellAll = true,
		source = section,
	})
	if QuestService then
		QuestService.Increment(player, "sells", count)
		QuestService.Increment(player, "cashEarned", math.floor(totalCash))
	end
end

-------------------------------------------------
-- LUCK UPGRADE (spend cash for +5 luck; 1 luck = +1% drop luck)
-------------------------------------------------

local LUCK_PER_UPGRADE = 5

local function handleUpgradeLuck(player)
	if not PlayerData then return end
	if not PlayerData.IsTutorialComplete(player) then
		UpgradeLuckResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end
	local currentLuck = PlayerData.GetLuck(player)
	local cost = Economy.GetLuckUpgradeCost(currentLuck)
	if not PlayerData.SpendCash(player, cost) then
		UpgradeLuckResult:FireClient(player, { success = false, reason = "Not enough cash!" })
		return
	end
	PlayerData.AddLuck(player, LUCK_PER_UPGRADE)
	UpgradeLuckResult:FireClient(player, { success = true, newLuck = PlayerData.GetLuck(player) })
end

-------------------------------------------------
-- CASH MULTIPLIER UPGRADE (spend cash for +2% cash production)
-------------------------------------------------

local function handleUpgradeCash(player)
	if not PlayerData then return end
	if not PlayerData.IsTutorialComplete(player) then
		UpgradeCashResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		return
	end
	local currentLevel = PlayerData.GetCashUpgrade(player)
	local cost = Economy.GetCashUpgradeCost(currentLevel)
	if not PlayerData.SpendCash(player, cost) then
		UpgradeCashResult:FireClient(player, { success = false, reason = "Not enough cash!" })
		return
	end
	PlayerData.AddCashUpgrade(player, 1)
	UpgradeCashResult:FireClient(player, { success = true, newLevel = PlayerData.GetCashUpgrade(player) })
end

-------------------------------------------------
-- PASSIVE INCOME (flat base rate only; equipped streamer income
-- is now accumulated on display pads and collected manually
-- via BaseService key collection pads)
-------------------------------------------------

local function startPassiveIncome()
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerData.Get(player)
				if data then
					local flatIncome = Economy.PassiveIncomeRate / Economy.PassiveIncomeInterval
					if flatIncome > 0 then
						local total = flatIncome
						if PlayerData.HasDoubleCash(player) then
							total = total * Economy.DoubleCashMultiplier
						end
						local rebirthMult = Economy.GetRebirthCoinMultiplier(PlayerData.GetRebirthCount(player))
						total = total * rebirthMult
						local cashUpgradeMult = PlayerData.GetCashUpgradeMultiplier(player)
						total = total * cashUpgradeMult
						local potionCashMult = PotionService and PotionService.GetCashMultiplier(player) or 1
						total = total * potionCashMult
						PlayerData.AddCash(player, math.floor(total))
					end
				end
			end
		end
	end)
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function EconomyService.Init(playerDataModule, potionServiceModule, questServiceModule)
	PlayerData = playerDataModule
	PotionService = potionServiceModule
	QuestService = questServiceModule

	-- SECURITY FIX: Wrap inventory-mutating handlers in per-player locks
	SellRequest.OnServerEvent:Connect(function(player, streamerId)
		PlayerData.WithLock(player, function() handleSell(player, streamerId) end)
	end)

	SellByIndexRequest.OnServerEvent:Connect(function(player, itemIndex, source)
		PlayerData.WithLock(player, function() handleSellByIndex(player, itemIndex, source) end)
	end)

	SellAllRequest.OnServerEvent:Connect(function(player, source)
		PlayerData.WithLock(player, function() handleSellAll(player, source) end)
	end)

	UpgradeLuckRequest.OnServerEvent:Connect(function(player)
		PlayerData.WithLock(player, function() handleUpgradeLuck(player) end)
	end)

	UpgradeCashRequest.OnServerEvent:Connect(function(player)
		PlayerData.WithLock(player, function() handleUpgradeCash(player) end)
	end)

	startPassiveIncome()
end

-- Expose income calculation for UI or other services
-- (streamer income is now handled by BaseService key accumulation)
function EconomyService.GetPlayerBaseIncome(player): number
	if not PlayerData then return 0 end
	local data = PlayerData.Get(player)
	if not data then return 0 end
	local total = 0
	for _, item in pairs(data.equippedPads) do
		local streamerId = type(item) == "table" and item.id or item
		local effect = type(item) == "table" and item.effect or nil
		local info = Streamers.ById[streamerId]
		if info and info.cashPerSecond then
			local income = info.cashPerSecond
			if effect then
				local effectInfo = Effects.ByName[effect]
				if effectInfo and effectInfo.cashMultiplier then
					income = income * effectInfo.cashMultiplier
				end
			end
			total = total + income
		end
	end
	return total
end

return EconomyService
