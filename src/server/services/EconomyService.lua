--[[
	EconomyService.lua
	Handles economy: passive income, selling from inventory, cash multipliers.
	Sell flow: player selects item from inventory -> sell for cash.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SellRequest = RemoteEvents:WaitForChild("SellRequest")
local SellResult = RemoteEvents:WaitForChild("SellResult")
local UpgradeLuckRequest = RemoteEvents:WaitForChild("UpgradeLuckRequest")
local UpgradeLuckResult = RemoteEvents:WaitForChild("UpgradeLuckResult")

local EconomyService = {}

local PlayerData

-------------------------------------------------
-- SELL FROM INVENTORY
-------------------------------------------------

local function handleSell(player, streamerId: string)
	if not PlayerData then return end
	if typeof(streamerId) ~= "string" then return end

	local streamerInfo = Streamers.ById[streamerId]
	if not streamerInfo then
		SellResult:FireClient(player, { success = false, reason = "Unknown streamer." })
		return
	end

	-- Remove from inventory (first occurrence)
	local removed = PlayerData.RemoveStreamerFromInventory(player, streamerId)
	if not removed then
		SellResult:FireClient(player, { success = false, reason = "Not in your inventory!" })
		return
	end

	-- Calculate sell price
	local price = Economy.SellPrices[streamerInfo.rarity] or Economy.SellPrices.Common
	if PlayerData.HasDoubleCash(player) then
		price = price * Economy.DoubleCashMultiplier
	end

	PlayerData.AddCash(player, price)
	SellResult:FireClient(player, {
		success = true,
		streamerId = streamerId,
		cashEarned = price,
	})
end

-------------------------------------------------
-- LUCK UPGRADE (spend cash for +1 luck; every 20 luck = +1% drop luck)
-------------------------------------------------

local function handleUpgradeLuck(player)
	if not PlayerData then return end
	local currentLuck = PlayerData.GetLuck(player)
	local cost = Economy.GetLuckUpgradeCost(currentLuck)
	if not PlayerData.SpendCash(player, cost) then
		UpgradeLuckResult:FireClient(player, { success = false, reason = "Not enough cash!" })
		return
	end
	PlayerData.AddLuck(player, 1)
	UpgradeLuckResult:FireClient(player, { success = true, newLuck = PlayerData.GetLuck(player) })
end

-------------------------------------------------
-- PASSIVE INCOME
-------------------------------------------------

local function startPassiveIncome()
	task.spawn(function()
		while true do
			task.wait(Economy.PassiveIncomeInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				if PlayerData.Get(player) then
					local amount = Economy.PassiveIncomeRate
					if PlayerData.HasDoubleCash(player) then
						amount = amount * Economy.DoubleCashMultiplier
					end
					PlayerData.AddCash(player, amount)
				end
			end
		end
	end)
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function EconomyService.Init(playerDataModule)
	PlayerData = playerDataModule

	SellRequest.OnServerEvent:Connect(function(player, streamerId)
		handleSell(player, streamerId)
	end)

	UpgradeLuckRequest.OnServerEvent:Connect(function(player)
		handleUpgradeLuck(player)
	end)

	startPassiveIncome()
end

return EconomyService
