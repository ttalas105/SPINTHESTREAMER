--[[
	CaseStockService.lua
	Manages per-player case stock with a 5-minute restock timer.
	Handles buying cases into player inventory and opening owned cases (triggering spin).
	Stock and restock timer persist per player across server restarts (leave/rejoin).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EnhancedCases = require(ReplicatedStorage.Shared.Config.EnhancedCases)

local CaseStockService = {}

local PlayerData
local SpinService
local QuestService

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local function getServerTime()
	return os.time()
end

local function rollStock18()
	local r = math.random()
	if r < 0.20 then return 0
	elseif r < 0.60 then return 6
	elseif r < 0.80 then return 12
	else return 18 end
end

local function rollStock12()
	local r = math.random()
	if r < 0.20 then return 0
	elseif r < 0.40 then return 4
	elseif r < 0.60 then return 6
	elseif r < 0.80 then return 8
	else return 12 end
end

local function buildFreshStock()
	local fresh = {}
	for i = 1, Economy.TotalCases do
		local maxStock = Economy.CrateMaxStock[i] or 50
		if i <= 6 then
			fresh[i] = maxStock
		elseif maxStock == 18 then
			fresh[i] = rollStock18()
		elseif maxStock == 12 then
			fresh[i] = rollStock12()
		else
			fresh[i] = maxStock
		end
	end
	return fresh
end

local function sanitizeStock(rawStock)
	local cleaned = {}
	for i = 1, Economy.TotalCases do
		local v = rawStock and (rawStock[i] or rawStock[tostring(i)])
		cleaned[i] = (type(v) == "number" and v >= 0) and math.floor(v) or (Economy.CrateMaxStock[i] or 50)
	end
	return cleaned
end

local function ensurePlayerStockData(data)
	if not data.caseShopStock or type(data.caseShopStock) ~= "table" then
		data.caseShopStock = buildFreshStock()
	end
	data.caseShopStock = sanitizeStock(data.caseShopStock)

	local n = tonumber(data.caseStockLastRestock)
	if type(n) ~= "number" or n <= 0 then
		data.caseStockLastRestock = getServerTime()
	end
end

local function restockPlayer(data)
	data.caseShopStock = buildFreshStock()
	data.caseStockLastRestock = getServerTime()
end

local function getSecondsUntilRestock(data)
	local elapsed = getServerTime() - (data.caseStockLastRestock or getServerTime())
	return math.max(0, Economy.RESTOCK_INTERVAL - elapsed)
end

local function checkAutoRestock(data)
	ensurePlayerStockData(data)
	if getSecondsUntilRestock(data) <= 0 then
		restockPlayer(data)
		return true
	end
	return false
end

local function sendStockToPlayer(player, justRestocked)
	local data = PlayerData.Get(player)
	if not data then return end
	ensurePlayerStockData(data)
	local payload = {
		stock = data.caseShopStock,
		restockIn = getSecondsUntilRestock(data),
		restocked = justRestocked == true,
	}
	local CaseStockUpdate = RemoteEvents:FindFirstChild("CaseStockUpdate")
	if CaseStockUpdate then
		CaseStockUpdate:FireClient(player, payload)
	end
end

-------------------------------------------------
-- BUY CRATE (into player's ownedCrates)
-------------------------------------------------

local function handleBuyCrate(player, crateId, amount)
	if type(crateId) ~= "number" or crateId ~= math.floor(crateId) then return end
	if crateId < 1 or crateId > Economy.TotalCases then return end
	if type(amount) ~= "number" or amount < 1 or amount ~= math.floor(amount) then return end
	amount = math.min(amount, 999)

	if not PlayerData.IsTutorialComplete(player) and crateId ~= 1 then
		local BuyCrateResult = RemoteEvents:FindFirstChild("BuyCrateResult")
		if BuyCrateResult then
			BuyCrateResult:FireClient(player, {
				success = false,
				crateId = crateId,
				reason = "Complete the tutorial first!",
			})
		end
		return
	end

	local data = PlayerData.Get(player)
	if not data then return end

	checkAutoRestock(data)

	local available = data.caseShopStock[crateId] or 0
	local toBuy = math.min(amount, available)
	if toBuy <= 0 then
		local BuyCrateResult = RemoteEvents:FindFirstChild("BuyCrateResult")
		if BuyCrateResult then
			BuyCrateResult:FireClient(player, {
				success = false,
				crateId = crateId,
				reason = "Out of stock!",
			})
		end
		return
	end

	local costPer = Economy.CrateCosts[crateId]
	if not costPer then return end

	local maxAffordable = math.floor((data.cash or 0) / costPer)
	toBuy = math.min(toBuy, maxAffordable)
	if toBuy <= 0 then
		local BuyCrateResult = RemoteEvents:FindFirstChild("BuyCrateResult")
		if BuyCrateResult then
			BuyCrateResult:FireClient(player, {
				success = false,
				crateId = crateId,
				reason = "Not enough cash!",
			})
		end
		return
	end

	local totalCost = costPer * toBuy
	data.cash = data.cash - totalCost
	data.caseShopStock[crateId] = (data.caseShopStock[crateId] or 0) - toBuy

	if not data.ownedCrates then data.ownedCrates = {} end
	local key = tostring(crateId)
	data.ownedCrates[key] = (data.ownedCrates[key] or 0) + toBuy

	PlayerData.Replicate(player)
	sendStockToPlayer(player, false)

	local BuyCrateResult = RemoteEvents:FindFirstChild("BuyCrateResult")
	if BuyCrateResult then
		BuyCrateResult:FireClient(player, {
			success = true,
			crateId = crateId,
			bought = toBuy,
			remaining = data.caseShopStock[crateId],
		})
	end
end

-------------------------------------------------
-- OPEN CRATE (from ownedCrates, triggers spin)
-------------------------------------------------

local function handleOpenCrate(player, crateId)
	if type(crateId) ~= "number" or crateId ~= math.floor(crateId) then return end
	if crateId < 1 or crateId > Economy.TotalCases then return end

	local data = PlayerData.Get(player)
	if not data then return end

	if not PlayerData.IsTutorialComplete(player) and crateId ~= 1 then
		local OpenCrateResult = RemoteEvents:FindFirstChild("OpenCrateResult")
		if OpenCrateResult then
			OpenCrateResult:FireClient(player, { success = false, reason = "Complete the tutorial first!" })
		end
		return
	end

	if not data.ownedCrates then data.ownedCrates = {} end
	local key = tostring(crateId)

	if (data.ownedCrates[key] or 0) <= 0 then
		local OpenCrateResult = RemoteEvents:FindFirstChild("OpenCrateResult")
		if OpenCrateResult then
			OpenCrateResult:FireClient(player, { success = false, reason = "You don't own any of this case!" })
		end
		return
	end

	local hasInventorySpace = (#(data.inventory or {}) < PlayerData.HOTBAR_MAX)
	local hasStorageSpace = (#(data.storage or {}) < PlayerData.GetStorageMax(player))
	if not hasInventorySpace and not hasStorageSpace then
		local OpenCrateResult = RemoteEvents:FindFirstChild("OpenCrateResult")
		if OpenCrateResult then
			OpenCrateResult:FireClient(player, { success = false, reason = "Inventory and storage are full!" })
		end
		return
	end

	data.ownedCrates[key] = data.ownedCrates[key] - 1
	if data.ownedCrates[key] <= 0 then
		data.ownedCrates[key] = nil
	end

	PlayerData.Replicate(player)

	SpinService._handleCrateOpen(player, crateId)
end

-------------------------------------------------
-- OPEN PREMIUM CRATE (Wraith / Starlight — from ownedCrates)
-------------------------------------------------

local function handleOpenPremiumCrate(player, caseKey)
	if type(caseKey) ~= "string" then return end
	local caseData = EnhancedCases.ByKey[caseKey]
	if not caseData then return end

	local data = PlayerData.Get(player)
	if not data then return end

	if not data.ownedCrates then data.ownedCrates = {} end
	if (data.ownedCrates[caseKey] or 0) <= 0 then
		local OpenCrateResult = RemoteEvents:FindFirstChild("OpenCrateResult")
		if OpenCrateResult then
			OpenCrateResult:FireClient(player, { success = false, reason = "You don't own any of this case!" })
		end
		return
	end

	local hasInventorySpace = (#(data.inventory or {}) < PlayerData.HOTBAR_MAX)
	local hasStorageSpace = (#(data.storage or {}) < PlayerData.GetStorageMax(player))
	if not hasInventorySpace and not hasStorageSpace then
		local SpinResult = RemoteEvents:FindFirstChild("SpinResult")
		if SpinResult then
			SpinResult:FireClient(player, { success = false, reason = "Inventory and storage are full!" })
		end
		return
	end

	data.ownedCrates[caseKey] = data.ownedCrates[caseKey] - 1
	if data.ownedCrates[caseKey] <= 0 then
		data.ownedCrates[caseKey] = nil
	end

	PlayerData.Replicate(player)

	SpinService._handlePremiumCrateOpen(player, caseKey)
end

-------------------------------------------------
-- GET STOCK (client request on join / shop open)
-------------------------------------------------

local function handleGetStock(player)
	local data = PlayerData.Get(player)
	if not data then return end
	checkAutoRestock(data)
	local GetCaseStock = RemoteEvents:FindFirstChild("GetCaseStock")
	if GetCaseStock then
		GetCaseStock:FireClient(player, {
			stock = data.caseShopStock,
			restockIn = getSecondsUntilRestock(data),
		})
	end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function CaseStockService.Init(playerDataModule, spinServiceModule, questServiceModule)
	PlayerData = playerDataModule
	SpinService = spinServiceModule
	QuestService = questServiceModule

	local BuyCrateStock = RemoteEvents:WaitForChild("BuyCrateStock")
	BuyCrateStock.OnServerEvent:Connect(function(player, crateId, amount)
		PlayerData.WithLock(player, function()
			handleBuyCrate(player, crateId, amount)
		end)
	end)

	local OpenOwnedCrate = RemoteEvents:WaitForChild("OpenOwnedCrate")
	OpenOwnedCrate.OnServerEvent:Connect(function(player, crateId)
		PlayerData.WithLock(player, function()
			handleOpenCrate(player, crateId)
		end)
	end)

	local OpenPremiumCrate = RemoteEvents:WaitForChild("OpenPremiumCrate")
	OpenPremiumCrate.OnServerEvent:Connect(function(player, caseKey)
		PlayerData.WithLock(player, function()
			handleOpenPremiumCrate(player, caseKey)
		end)
	end)

	local GetCaseStock = RemoteEvents:WaitForChild("GetCaseStock")
	GetCaseStock.OnServerEvent:Connect(function(player)
		PlayerData.WithLock(player, function()
			handleGetStock(player)
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				PlayerData.WithLock(player, function()
					local data = PlayerData.Get(player)
					if data and checkAutoRestock(data) then
						sendStockToPlayer(player, true)
					end
				end)
			end
		end
	end)
end

function CaseStockService.GetStock()
	return {}
end

function CaseStockService.GetRestockIn()
	return 0
end

return CaseStockService
