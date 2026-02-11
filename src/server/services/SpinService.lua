--[[
	SpinService.lua
	Handles spin requests: cost check, weighted RNG, server luck.
	Spin results go to INVENTORY (not auto-equip).
	Mythic pulls trigger a server-wide alert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local SpinService = {}

SpinService.ServerLuckMultiplier = Economy.DefaultLuckMultiplier

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SpinRequest = RemoteEvents:WaitForChild("SpinRequest")
local SpinResult = RemoteEvents:WaitForChild("SpinResult")
local MythicAlert = RemoteEvents:WaitForChild("MythicAlert")
local BuyCrateRequest = RemoteEvents:WaitForChild("BuyCrateRequest")

local PlayerData
local BaseService

-------------------------------------------------
-- RNG (per-streamer odds: 1 in N)
-------------------------------------------------

local rng = Random.new()

-- Pick streamer using custom odds. Weight for each = 1/odds (higher weight = more likely).
-- luckMultiplier makes RARER streamers (higher odds) more likely: we apply luck^(1 + rarityFactor)
-- so common stays ~luck^1 and mythic gets ~luck^2, making rare drops actually easier with luck.
local LOG_MAX_ODDS = math.log(10000000)
local function pickStreamerByOdds(luckMultiplier: number)
	local list = Streamers.List
	if not list or #list == 0 then
		return nil
	end
	local totalWeight = 0
	local weights = {}
	for i, s in ipairs(list) do
		local odds = type(s.odds) == "number" and s.odds or 100
		if odds < 1 then odds = 100 end
		local w = 1 / odds
		if luckMultiplier and luckMultiplier > 1 then
			-- Rarity factor 0..1: higher odds (rarer) -> bigger luck exponent
			local rarityFactor = math.log(math.max(odds, 1)) / LOG_MAX_ODDS
			rarityFactor = math.max(0, math.min(1, rarityFactor))
			w = w * (luckMultiplier ^ (1 + rarityFactor))
		end
		weights[i] = w
		totalWeight = totalWeight + w
	end
	if totalWeight <= 0 then
		return list[1]
	end
	local roll = rng:NextNumber() * totalWeight
	local cumulative = 0
	for i, w in ipairs(weights) do
		cumulative = cumulative + w
		if roll <= cumulative then
			return list[i]
		end
	end
	return list[1]
end

-------------------------------------------------
-- SPIN LOGIC
-------------------------------------------------

local function handleSpin(player)
	if not PlayerData then return end
	local data = PlayerData.Get(player)
	if not data then return end

	-- Check cost: use spin credit first, then cash
	local usedCredit = PlayerData.UseSpinCredit(player)
	if not usedCredit then
		if not PlayerData.SpendCash(player, Economy.SpinCost) then
			SpinResult:FireClient(player, { success = false, reason = "Not enough cash!" })
			return
		end
	end

	-- Rebirth + personal luck (every 20 luck = +1%)
	local rebirthLuck = 1 + (data.rebirthCount * 0.02)
	local playerLuck = data.luck or 0
	local playerLuckPercent = math.floor(playerLuck / 20) / 100
	local totalLuck = SpinService.ServerLuckMultiplier * rebirthLuck * (1 + playerLuckPercent)

	-- Roll using per-streamer odds
	local streamer = pickStreamerByOdds(totalLuck)
	if not streamer then
		SpinResult:FireClient(player, { success = false, reason = "Config error." })
		return
	end

	-- Add to inventory (not auto-equip)
	PlayerData.AddToInventory(player, streamer.id)

	-- Send result to client (include odds for display)
	SpinResult:FireClient(player, {
		success = true,
		streamerId = streamer.id,
		displayName = streamer.displayName,
		rarity = streamer.rarity,
		odds = streamer.odds,
	})

	-- Mythic server-wide alert
	if streamer.rarity == "Mythic" then
		MythicAlert:FireAllClients({
			playerName = player.Name,
			streamerId = streamer.id,
			displayName = streamer.displayName,
		})
	end
end

-------------------------------------------------
-- CRATE SPIN (buy at spin stand: cost + luck bonus)
-------------------------------------------------

local function handleCrateSpin(player, crateId: number)
	if not PlayerData then return end
	local data = PlayerData.Get(player)
	if not data then return end

	local crateCosts = {
		[1] = Economy.Crate1Cost,
		[2] = Economy.Crate2Cost,
		[3] = Economy.Crate3Cost,
		[4] = Economy.Crate4Cost,
		[5] = Economy.Crate5Cost,
		[6] = Economy.Crate6Cost,
		[7] = Economy.Crate7Cost,
	}
	local crateLuck = {
		[1] = Economy.Crate1LuckBonus,
		[2] = Economy.Crate2LuckBonus,
		[3] = Economy.Crate3LuckBonus,
		[4] = Economy.Crate4LuckBonus,
		[5] = Economy.Crate5LuckBonus,
		[6] = Economy.Crate6LuckBonus,
		[7] = Economy.Crate7LuckBonus,
	}
	local cost = crateCosts[crateId]
	local luckBonus = crateLuck[crateId]
	if not cost or not luckBonus then
		SpinResult:FireClient(player, { success = false, reason = "Invalid crate!" })
		return
	end

	if not PlayerData.SpendCash(player, cost) then
		SpinResult:FireClient(player, { success = false, reason = "Not enough cash!" })
		return
	end

	-- Rebirth + personal luck (every 20 = +1%) + crate luck (additive)
	local rebirthLuck = 1 + (data.rebirthCount * 0.02)
	local playerLuck = data.luck or 0
	local playerLuckPercent = math.floor(playerLuck / 20) / 100
	local totalLuck = SpinService.ServerLuckMultiplier * rebirthLuck * (1 + playerLuckPercent + luckBonus)

	local streamer = pickStreamerByOdds(totalLuck)
	if not streamer then
		PlayerData.AddCash(player, cost) -- Refund
		SpinResult:FireClient(player, { success = false, reason = "Config error." })
		return
	end

	PlayerData.AddToInventory(player, streamer.id)

	SpinResult:FireClient(player, {
		success = true,
		streamerId = streamer.id,
		displayName = streamer.displayName,
		rarity = streamer.rarity,
		odds = streamer.odds,
	})

	if streamer.rarity == "Mythic" then
		MythicAlert:FireAllClients({
			playerName = player.Name,
			streamerId = streamer.id,
			displayName = streamer.displayName,
		})
	end
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function SpinService.Init(playerDataModule, baseServiceModule)
	PlayerData = playerDataModule
	BaseService = baseServiceModule

	SpinRequest.OnServerEvent:Connect(function(player)
		handleSpin(player)
	end)

	BuyCrateRequest.OnServerEvent:Connect(function(player, crateId: number)
		handleCrateSpin(player, crateId)
	end)
end

function SpinService.SetServerLuck(multiplier: number)
	SpinService.ServerLuckMultiplier = multiplier
end

return SpinService
