--[[
	CaseStockService.lua
	Manages global case stock (shared across all players) with a 5-minute restock timer.
	Handles buying cases into player inventory and opening owned cases (triggering spin).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local CaseStockService = {}

local PlayerData
local SpinService
local QuestService

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local stock = {}
local lastRestockTime = 0

local function getServerTime()
	return workspace:GetServerTimeNow()
end

local function restockAll()
	for i = 1, Economy.TotalCases do
		stock[i] = Economy.CrateMaxStock[i] or 50
	end
	lastRestockTime = getServerTime()
end

local function getSecondsUntilRestock()
	local elapsed = getServerTime() - lastRestockTime
	return math.max(0, Economy.RESTOCK_INTERVAL - elapsed)
end

local function checkAutoRestock()
	if getSecondsUntilRestock() <= 0 then
		restockAll()
	end
end

local function broadcastStock(justRestocked)
	local payload = {
		stock = stock,
		restockIn = getSecondsUntilRestock(),
		restocked = justRestocked == true,
	}
	for _, p in ipairs(Players:GetPlayers()) do
		local CaseStockUpdate = RemoteEvents:FindFirstChild("CaseStockUpdate")
		if CaseStockUpdate then
			CaseStockUpdate:FireClient(p, payload)
		end
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

	local rebirthReq = Economy.GetCrateRebirthRequirement(crateId)
	if (data.rebirthCount or 0) < rebirthReq then
		local BuyCrateResult = RemoteEvents:FindFirstChild("BuyCrateResult")
		if BuyCrateResult then
			BuyCrateResult:FireClient(player, {
				success = false,
				crateId = crateId,
				reason = "Requires Rebirth " .. rebirthReq .. "!",
			})
		end
		return
	end

	checkAutoRestock()

	local available = stock[crateId] or 0
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
	stock[crateId] = (stock[crateId] or 0) - toBuy

	if not data.ownedCrates then data.ownedCrates = {} end
	data.ownedCrates[crateId] = (data.ownedCrates[crateId] or 0) + toBuy

	PlayerData.Replicate(player)
	broadcastStock(false)

	local BuyCrateResult = RemoteEvents:FindFirstChild("BuyCrateResult")
	if BuyCrateResult then
		BuyCrateResult:FireClient(player, {
			success = true,
			crateId = crateId,
			bought = toBuy,
			remaining = stock[crateId],
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

	if not data.ownedCrates or (data.ownedCrates[crateId] or 0) <= 0 then
		local OpenCrateResult = RemoteEvents:FindFirstChild("OpenCrateResult")
		if OpenCrateResult then
			OpenCrateResult:FireClient(player, { success = false, reason = "You don't own any of this case!" })
		end
		return
	end

	local hasInventorySpace = (#(data.inventory or {}) < PlayerData.HOTBAR_MAX)
	local hasStorageSpace = (#(data.storage or {}) < PlayerData.STORAGE_MAX)
	if not hasInventorySpace and not hasStorageSpace then
		local OpenCrateResult = RemoteEvents:FindFirstChild("OpenCrateResult")
		if OpenCrateResult then
			OpenCrateResult:FireClient(player, { success = false, reason = "Inventory and storage are full!" })
		end
		return
	end

	data.ownedCrates[crateId] = data.ownedCrates[crateId] - 1
	if data.ownedCrates[crateId] <= 0 then
		data.ownedCrates[crateId] = nil
	end

	PlayerData.Replicate(player)

	SpinService._handleCrateOpen(player, crateId)
end

-------------------------------------------------
-- GET STOCK (client request on join / shop open)
-------------------------------------------------

local function handleGetStock(player)
	checkAutoRestock()
	local GetCaseStock = RemoteEvents:FindFirstChild("GetCaseStock")
	if GetCaseStock then
		GetCaseStock:FireClient(player, {
			stock = stock,
			restockIn = getSecondsUntilRestock(),
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

	restockAll()

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

	local GetCaseStock = RemoteEvents:WaitForChild("GetCaseStock")
	GetCaseStock.OnServerEvent:Connect(function(player)
		handleGetStock(player)
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local beforeRestock = getSecondsUntilRestock()
			if beforeRestock <= 0 then
				restockAll()
				broadcastStock(true)
			end
		end
	end)
end

function CaseStockService.GetStock()
	checkAutoRestock()
	return stock
end

function CaseStockService.GetRestockIn()
	return getSecondsUntilRestock()
end

return CaseStockService
