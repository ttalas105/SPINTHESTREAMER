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

		-- Store products (ServerLuck, Spins, DoubleCash, PremiumSlot)
		if productId == Economy.Products.ServerLuck then
			if SpinService then
				SpinService.SetServerLuck(Economy.BoostedLuckMultiplier)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted

		elseif productId == Economy.Products.Buy5Spins then
			PlayerData.AddSpinCredits(player, 5)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		elseif productId == Economy.Products.Buy10Spins then
			PlayerData.AddSpinCredits(player, 10)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		elseif productId == Economy.Products.DoubleCash then
			PlayerData.SetDoubleCash(player, true)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		elseif productId == Economy.Products.PremiumSlot then
			PlayerData.SetPremiumSlot(player, true)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		-- Potion products (Prismatic packs)
		local potionAmount = Potions.ProductIdToAmount[productId]
		if potionAmount then
			-- Delegate to PotionService via its public grant function
			local PotionService = require(script.Parent.PotionService)
			PotionService.GrantPrismaticPotions(player, potionAmount)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		warn("[ReceiptHandler] Unhandled product ID: " .. tostring(productId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	print("[Server] Unified ReceiptHandler installed")
end

return ReceiptHandler
