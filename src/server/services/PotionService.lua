--[[
	PotionService.lua
	Server-side potion management.
	Tracks active luck/cash/divine potions per player with expiry times.
	Time stacks (Luck/Cash +5 min per use, Divine +15 min per use, max 3 hours).
	Divine (Robux) boosts both luck and cash simultaneously (x5).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Potions = require(ReplicatedStorage.Shared.Config.Potions)

local PotionService = {}

local PlayerData
local QuestService

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyPotionRequest = RemoteEvents:WaitForChild("BuyPotionRequest")
local BuyPotionResult = RemoteEvents:WaitForChild("BuyPotionResult")
local PotionUpdate = RemoteEvents:WaitForChild("PotionUpdate")
local GetPotionStock = RemoteEvents:WaitForChild("GetPotionStock")
local PotionStockUpdate = RemoteEvents:WaitForChild("PotionStockUpdate")
local BuyPotionStock = RemoteEvents:WaitForChild("BuyPotionStock")
local UseOwnedPotion = RemoteEvents:WaitForChild("UseOwnedPotion")

local MAX_STOCK_PER_POTION = 8
local STOCK_RESTOCK_INTERVAL = 5 * 60

local activeEffects = {}     -- [userId] = { Luck/Cash/Divine/SacrificeLuck }
local divineInventory = {}   -- [userId] = count
local ownedPotions = {}      -- [userId] = { Luck = { [tier] = count }, Cash = { [tier] = count } }

local stock = {}             -- ["Luck_1"] = 8, ...
local lastRestockTime = 0

local function getServerTime()
	return workspace:GetServerTimeNow()
end

local function getEffects(userId)
	if not activeEffects[userId] then
		activeEffects[userId] = {}
	end
	return activeEffects[userId]
end

local function getOwned(userId)
	if not ownedPotions[userId] then
		ownedPotions[userId] = { Luck = {}, Cash = {} }
	end
	return ownedPotions[userId]
end

local function stockKey(potionType, tier)
	return tostring(potionType) .. "_" .. tostring(tier)
end

local function restockAllStock()
	for _, potionType in ipairs({ "Luck", "Cash" }) do
		local list = Potions.Types[potionType] or {}
		for _, potion in ipairs(list) do
			stock[stockKey(potionType, potion.tier)] = MAX_STOCK_PER_POTION
		end
	end
	lastRestockTime = getServerTime()
end

local function getSecondsUntilRestock()
	local elapsed = getServerTime() - lastRestockTime
	return math.max(0, STOCK_RESTOCK_INTERVAL - elapsed)
end

local function checkAutoRestock()
	if getSecondsUntilRestock() <= 0 then
		restockAllStock()
		return true
	end
	return false
end

local function buildOwnedPayload(userId)
	local owned = getOwned(userId)
	local payload = { Luck = {}, Cash = {} }
	for _, potionType in ipairs({ "Luck", "Cash" }) do
		for tier, count in pairs(owned[potionType] or {}) do
			if count and count > 0 then
				payload[potionType][tostring(tier)] = count
			end
		end
	end
	return payload
end

local function persistPotionState(player)
	local data = PlayerData and PlayerData.Get(player)
	if not data then return end

	local userId = player.UserId
	local now = os.time()
	local effects = activeEffects[userId] or {}
	local savedEffects = {}

	for potionType, info in pairs(effects) do
		if (potionType == "Luck" or potionType == "Cash" or potionType == "Divine")
			and type(info) == "table"
			and type(info.expiresAt) == "number"
			and info.expiresAt > now then
			savedEffects[potionType] = {
				multiplier = tonumber(info.multiplier) or 1,
				tier = tonumber(info.tier) or 0,
				expiresAt = math.floor(info.expiresAt),
			}
		end
	end

	data.activePotionEffects = savedEffects
	data.divinePotionCount = math.max(0, math.floor(divineInventory[userId] or 0))
	data.potionInventory = buildOwnedPayload(userId)
end

local function sendPotionUpdate(player)
	local userId = player.UserId
	local effects = getEffects(userId)
	local now = os.time()
	local payload = {}

	for potionType, info in pairs(effects) do
		if info.expiresAt and info.expiresAt > now then
			payload[potionType] = {
				multiplier = info.multiplier,
				tier = info.tier,
				remaining = math.ceil(info.expiresAt - now),
			}
		end
	end

	payload._divineCount = divineInventory[userId] or 0
	payload._ownedPotions = buildOwnedPayload(userId)
	PotionUpdate:FireClient(player, payload)
end

local function broadcastPotionStock(justRestocked)
	local payload = {
		stock = stock,
		restockIn = getSecondsUntilRestock(),
		restocked = justRestocked == true,
		maxStock = MAX_STOCK_PER_POTION,
	}
	for _, p in ipairs(Players:GetPlayers()) do
		PotionStockUpdate:FireClient(p, payload)
	end
end

local function loadPotionState(player)
	local data = PlayerData and PlayerData.Get(player)
	if not data then return end

	local userId = player.UserId
	local now = os.time()

	activeEffects[userId] = {}
	local savedEffects = type(data.activePotionEffects) == "table" and data.activePotionEffects or {}
	for potionType, info in pairs(savedEffects) do
		if (potionType == "Luck" or potionType == "Cash" or potionType == "Divine")
			and type(info) == "table"
			and type(info.expiresAt) == "number"
			and info.expiresAt > now then
			activeEffects[userId][potionType] = {
				multiplier = tonumber(info.multiplier) or 1,
				tier = tonumber(info.tier) or 0,
				expiresAt = math.floor(info.expiresAt),
			}
		end
	end

	divineInventory[userId] = math.max(0, math.floor(tonumber(data.divinePotionCount) or 0))
	ownedPotions[userId] = { Luck = {}, Cash = {} }
	local savedOwned = type(data.potionInventory) == "table" and data.potionInventory or {}
	for _, potionType in ipairs({ "Luck", "Cash" }) do
		local src = type(savedOwned[potionType]) == "table" and savedOwned[potionType] or {}
		for tier, count in pairs(src) do
			local nTier = tonumber(tier)
			local nCount = math.max(0, math.floor(tonumber(count) or 0))
			if nTier and nCount > 0 then
				ownedPotions[userId][potionType][nTier] = nCount
			end
		end
	end

	sendPotionUpdate(player)
end

local function fail(player, reason, potionType, tier)
	BuyPotionResult:FireClient(player, {
		success = false,
		reason = reason,
		potionType = potionType,
		tier = tier,
	})
end

local function activateOwnedPotion(player, potionType, tier)
	local potionInfo = Potions.Get(potionType, tier)
	if not potionInfo then
		fail(player, "Unknown potion.", potionType, tier)
		return
	end

	local userId = player.UserId
	local effects = getEffects(userId)
	local now = os.time()

	local existing = effects[potionType]
	if existing and existing.expiresAt > now and existing.tier ~= tier then
		fail(player, "You already have " .. potionType .. " Potion " .. tostring(existing.tier) .. " active!", potionType, tier)
		return
	end

	local owned = getOwned(userId)
	local count = (owned[potionType] and owned[potionType][tier]) or 0
	if count <= 0 then
		fail(player, "You don't own this potion yet.", potionType, tier)
		return
	end

	owned[potionType][tier] = count - 1
	if owned[potionType][tier] <= 0 then
		owned[potionType][tier] = nil
	end

	if existing and existing.expiresAt > now then
		local currentRemaining = existing.expiresAt - now
		local newRemaining = math.min(currentRemaining + Potions.DURATION_PER_USE, Potions.MAX_DURATION)
		existing.expiresAt = now + newRemaining
	else
		effects[potionType] = {
			multiplier = potionInfo.multiplier,
			tier = potionInfo.tier,
			expiresAt = now + Potions.DURATION_PER_USE,
		}
	end

	PlayerData.Replicate(player)
	persistPotionState(player)
	sendPotionUpdate(player)
	BuyPotionResult:FireClient(player, {
		success = true,
		potionType = potionType,
		tier = tier,
		name = potionInfo.name,
		action = "used",
	})
end

local function buyPotionStock(player, potionType, tier, amount)
	if not PlayerData.IsTutorialComplete(player) then
		fail(player, "Complete the tutorial first!", potionType, tier)
		return
	end

	if type(potionType) ~= "string" or type(tier) ~= "number" then
		fail(player, "Invalid request.", potionType, tier)
		return
	end
	if potionType ~= "Luck" and potionType ~= "Cash" then
		fail(player, "Only Luck/Money potions use stock.", potionType, tier)
		return
	end

	local potionInfo = Potions.Get(potionType, tier)
	if not potionInfo then
		fail(player, "Unknown potion.", potionType, tier)
		return
	end

	checkAutoRestock()

	local data = PlayerData.Get(player)
	if not data then
		fail(player, "Data not loaded.", potionType, tier)
		return
	end

	local rebirthRequired = potionInfo.rebirthRequired or 0
	if rebirthRequired > 0 and (data.rebirthCount or 0) < rebirthRequired then
		fail(player, "Requires Rebirth " .. rebirthRequired .. "!", potionType, tier)
		return
	end

	local requested = math.max(1, math.floor(tonumber(amount) or 1))
	if requested > 999 then requested = 999 end

	local key = stockKey(potionType, tier)
	local available = stock[key] or 0
	local toBuy = math.min(requested, available)
	if toBuy <= 0 then
		fail(player, "Out of stock!", potionType, tier)
		return
	end

	local maxAffordable = math.floor((data.cash or 0) / (potionInfo.cost or 1))
	toBuy = math.min(toBuy, maxAffordable)
	if toBuy <= 0 then
		fail(player, "Not enough cash!", potionType, tier)
		return
	end

	data.cash = (data.cash or 0) - potionInfo.cost * toBuy
	stock[key] = available - toBuy

	local owned = getOwned(player.UserId)
	owned[potionType][tier] = (owned[potionType][tier] or 0) + toBuy

	PlayerData.Replicate(player)
	persistPotionState(player)
	sendPotionUpdate(player)
	broadcastPotionStock(false)
	BuyPotionResult:FireClient(player, {
		success = true,
		potionType = potionType,
		tier = tier,
		bought = toBuy,
		remaining = stock[key],
		action = "bought",
	})
	if QuestService then
		QuestService.Increment(player, "potionsBought", toBuy)
	end
end

local function handleUseDivine(player)
	local userId = player.UserId
	local count = divineInventory[userId] or 0
	if count <= 0 then
		fail(player, "You have no Divine Potions! Purchase some first.", "Divine", 0)
		return
	end

	local effects = getEffects(userId)
	local now = os.time()

	divineInventory[userId] = count - 1
	local divineDuration = Potions.DIVINE_DURATION_PER_USE or Potions.DURATION_PER_USE
	local existing = effects.Divine
	if existing and existing.expiresAt > now then
		local currentRemaining = existing.expiresAt - now
		local newRemaining = math.min(currentRemaining + divineDuration, Potions.MAX_DURATION)
		existing.expiresAt = now + newRemaining
	else
		effects.Divine = {
			multiplier = Potions.Divine.multiplier,
			tier = 0,
			expiresAt = now + divineDuration,
		}
	end

	persistPotionState(player)
	sendPotionUpdate(player)
	BuyPotionResult:FireClient(player, {
		success = true,
		potionType = "Divine",
		tier = 0,
		name = Potions.Divine.name,
		action = "used",
	})
end

local function grantDivinePotions(player, amount)
	local userId = player.UserId
	divineInventory[userId] = (divineInventory[userId] or 0) + amount
	persistPotionState(player)
	sendPotionUpdate(player)
	BuyPotionResult:FireClient(player, {
		success = true,
		potionType = "DivinePurchase",
		tier = 0,
		name = amount .. "x Divine Potion" .. (amount > 1 and "s" or ""),
		amount = amount,
		action = "bought",
	})
	if QuestService then
		QuestService.Increment(player, "potionsBought", amount)
	end
end

function PotionService.SetQuestService(qs)
	QuestService = qs
end

function PotionService.GetLuckMultiplier(player): number
	local effects = activeEffects[player.UserId]
	if not effects then return 1 end
	local now = os.time()

	if effects.SacrificeLuck and effects.SacrificeLuck.expiresAt > now then
		return effects.SacrificeLuck.multiplier
	end
	if effects.SacrificeLuck and effects.SacrificeLuck.expiresAt <= now then
		effects.SacrificeLuck = nil
	end
	local divineMult = 0
	local luckMult = 0
	if effects.Divine and effects.Divine.expiresAt > now then
		divineMult = effects.Divine.multiplier or 0
	end
	if effects.Luck and effects.Luck.expiresAt > now then
		luckMult = effects.Luck.multiplier or 0
	end
	if effects.Luck and effects.Luck.expiresAt <= now then effects.Luck = nil end
	if effects.Divine and effects.Divine.expiresAt <= now then effects.Divine = nil end
	if divineMult > 0 or luckMult > 0 then
		return divineMult + luckMult
	end
	return 1
end

function PotionService.SetSacrificeLuck(player, multiplier: number, durationSeconds: number)
	local effects = getEffects(player.UserId)
	effects.SacrificeLuck = {
		multiplier = multiplier,
		expiresAt = os.time() + durationSeconds,
	}
	sendPotionUpdate(player)
end

function PotionService.GetCashMultiplier(player): number
	local effects = activeEffects[player.UserId]
	if not effects then return 1 end
	local now = os.time()
	local divineMult = 0
	local cashMult = 0
	if effects.Divine and effects.Divine.expiresAt > now then
		divineMult = effects.Divine.multiplier or 0
	end
	if effects.Cash and effects.Cash.expiresAt > now then
		cashMult = effects.Cash.multiplier or 0
	end
	if effects.Cash and effects.Cash.expiresAt <= now then effects.Cash = nil end
	if effects.Divine and effects.Divine.expiresAt <= now then effects.Divine = nil end
	if divineMult > 0 or cashMult > 0 then
		return divineMult + cashMult
	end
	return 1
end

function PotionService.GrantDivinePotions(player, amount)
	grantDivinePotions(player, amount)
end

function PotionService.ClearPotions(player)
	local userId = player.UserId
	activeEffects[userId] = {}
	ownedPotions[userId] = { Luck = {}, Cash = {} }
	divineInventory[userId] = 0
	persistPotionState(player)
	sendPotionUpdate(player)
end

-- Rebirth: reset non-divine potions (owned + active), preserve Divine timer/inventory.
function PotionService.ClearPotionsForRebirth(player)
	local userId = player.UserId
	local preservedDivine = activeEffects[userId] and activeEffects[userId].Divine or nil
	activeEffects[userId] = {}
	if preservedDivine and preservedDivine.expiresAt and preservedDivine.expiresAt > os.time() then
		activeEffects[userId].Divine = preservedDivine
	end
	ownedPotions[userId] = { Luck = {}, Cash = {} }
	persistPotionState(player)
	sendPotionUpdate(player)
end

function PotionService.Init(playerDataModule)
	PlayerData = playerDataModule

	restockAllStock()

	Players.PlayerAdded:Connect(function(player)
		loadPotionState(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		loadPotionState(player)
	end

	BuyPotionRequest.OnServerEvent:Connect(function(player, potionType, tier)
		PlayerData.WithLock(player, function()
			if potionType == "UseDivine" then
				handleUseDivine(player)
			end
		end)
	end)

	BuyPotionStock.OnServerEvent:Connect(function(player, potionType, tier, amount)
		PlayerData.WithLock(player, function()
			buyPotionStock(player, potionType, tier, amount)
		end)
	end)

	UseOwnedPotion.OnServerEvent:Connect(function(player, potionType, tier)
		PlayerData.WithLock(player, function()
			activateOwnedPotion(player, potionType, tier)
		end)
	end)

	GetPotionStock.OnServerEvent:Connect(function(player)
		checkAutoRestock()
		GetPotionStock:FireClient(player, {
			stock = stock,
			restockIn = getSecondsUntilRestock(),
			maxStock = MAX_STOCK_PER_POTION,
		})
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			if checkAutoRestock() then
				broadcastPotionStock(true)
			end
			for _, player in ipairs(Players:GetPlayers()) do
				if activeEffects[player.UserId] or (divineInventory[player.UserId] or 0) > 0 then
					persistPotionState(player)
					sendPotionUpdate(player)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		activeEffects[player.UserId] = nil
		divineInventory[player.UserId] = nil
		ownedPotions[player.UserId] = nil
	end)
end

return PotionService
