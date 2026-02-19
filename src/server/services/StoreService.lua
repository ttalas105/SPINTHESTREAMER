--[[
	StoreService.lua
	Handles Robux purchases via Developer Products and GamePasses.
	Products: Server Luck, 5 Spins, 10 Spins, 2x Cash, Premium Slot.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local StoreService = {}

local PlayerData   -- set in Init
local SpinService  -- set in Init

-------------------------------------------------
-- PROCESS RECEIPT
-------------------------------------------------

local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productId = receiptInfo.ProductId

	if productId == Economy.Products.ServerLuck then
		-- Boost server luck for everyone (session-based)
		if SpinService then
			SpinService.SetServerLuck(Economy.BoostedLuckMultiplier)
		end
		-- Announce (could fire a remote for server-wide notification)
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

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function StoreService.Init(playerDataModule, spinServiceModule)
	PlayerData = playerDataModule
	SpinService = spinServiceModule

	-- SECURITY FIX: ProcessReceipt is now handled by ReceiptHandler.lua
	-- Do NOT set MarketplaceService.ProcessReceipt here (only one callback allowed)
end

return StoreService
