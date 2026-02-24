--[[
	ReceiptHandler.lua
	SECURITY FIX: Unified ProcessReceipt handler.
	Only ONE callback can be assigned to MarketplaceService.ProcessReceipt.
	This module dispatches to all services based on product ID.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Potions = require(ReplicatedStorage.Shared.Config.Potions)

local ReceiptHandler = {}

local PlayerData
local SpinService

function ReceiptHandler.Init(playerDataModule, spinServiceModule)
	PlayerData = playerDataModule
	SpinService = spinServiceModule

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local productId = receiptInfo.ProductId

		local function trackRobux()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end)
			if ok and info and info.PriceInRobux then
				PlayerData.IncrementStat(player, "robuxSpent", info.PriceInRobux)
			else
				PlayerData.IncrementStat(player, "robuxSpent", 1)
			end
		end

		-- Store products (ServerLuck, Spins, DoubleCash, PremiumSlot)
		if productId == Economy.Products.ServerLuck then
			if SpinService then
				SpinService.SetServerLuck(Economy.BoostedLuckMultiplier)
			end
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		elseif productId == Economy.Products.Buy5Spins then
			PlayerData.AddSpinCredits(player, 5)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		elseif productId == Economy.Products.Buy10Spins then
			PlayerData.AddSpinCredits(player, 10)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		elseif productId == Economy.Products.DoubleCash then
			PlayerData.SetDoubleCash(player, true)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		elseif productId == Economy.Products.PremiumSlot then
			PlayerData.SetPremiumSlot(player, true)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		-- Potion products (Prismatic packs)
		local potionAmount = Potions.ProductIdToAmount[productId]
		if potionAmount then
			local PotionService = require(script.Parent.PotionService)
			PotionService.GrantPrismaticPotions(player, potionAmount)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		warn("[ReceiptHandler] Unhandled product ID: " .. tostring(productId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	print("[Server] Unified ReceiptHandler installed")
end

return ReceiptHandler
