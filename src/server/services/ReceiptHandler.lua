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
local EnhancedCases = require(ReplicatedStorage.Shared.Config.EnhancedCases)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)

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

		-- VIP (permanent 1.5x luck + 1.5x money)
		if productId == Economy.Products.VIP then
			PlayerData.SetVIP(player, true)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		-- X2 Luck (permanent 2x luck)
		elseif productId == Economy.Products.X2Luck then
			PlayerData.SetX2Luck(player, true)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		-- Expand Storage (permanent 200 → 1000)
		elseif productId == Economy.Products.ExpandStorage then
			PlayerData.SetExpandStorage(player, true)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		-- Auto Skip (permanent auto-skip during spins)
		elseif productId == Economy.Products.AutoSkip then
			PlayerData.SetAutoSkip(player, true)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted

		-- Store products (ServerLuck, Spins, DoubleCash, PremiumSlot)
		elseif productId == Economy.Products.ServerLuck then
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

		-- Premium Cases (Wraith / Starlight) — add to ownedCrates for later opening
		local premiumInfo = EnhancedCases.ProductToCase[productId]
		if premiumInfo then
			local data = PlayerData.Get(player)
			if data then
				if not data.ownedCrates then data.ownedCrates = {} end
				local key = premiumInfo.key
				data.ownedCrates[key] = (data.ownedCrates[key] or 0) + premiumInfo.amount
				PlayerData.Replicate(player)
			end
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		-- Gem packs
		for _, pack in ipairs(Economy.GemPacks) do
			if productId == Economy.Products[pack.key] then
				PlayerData.AddGems(player, pack.amount)
				task.spawn(trackRobux)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
		end

		-- Potion products (Divine packs)
		local potionAmount = Potions.ProductIdToAmount[productId]
		if potionAmount then
			local PotionService = require(script.Parent.PotionService)
			PotionService.GrantDivinePotions(player, potionAmount)
			task.spawn(trackRobux)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		warn("[ReceiptHandler] Unhandled product ID: " .. tostring(productId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	print("[Server] Unified ReceiptHandler installed")
end

return ReceiptHandler
