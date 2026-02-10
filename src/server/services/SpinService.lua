--[[
	SpinService.lua
	Handles spin requests: cost check, weighted RNG, server luck.
	Spin results go to INVENTORY (not auto-equip).
	Mythic pulls trigger a server-wide alert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
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
-- RNG
-------------------------------------------------

local rng = Random.new()

local function pickRarity(luckMultiplier: number): string
	local adjusted = {}
	local total = 0

	for i, tier in ipairs(Rarities.Tiers) do
		local w = tier.weight
		if i > 1 and luckMultiplier > 1 then
			w = w * (1 + (luckMultiplier - 1) * (i / #Rarities.Tiers))
		end
		if i == 1 and luckMultiplier > 1 then
			w = w * (1 / luckMultiplier)
		end
		adjusted[i] = w
		total = total + w
	end

	local roll = rng:NextNumber() * total
	local cumulative = 0
	for i, w in ipairs(adjusted) do
		cumulative = cumulative + w
		if roll <= cumulative then
			return Rarities.Tiers[i].name
		end
	end

	return "Common"
end

local function pickStreamer(rarityName: string)
	local pool = Streamers.ByRarity[rarityName]
	if not pool or #pool == 0 then
		pool = Streamers.ByRarity["Common"]
	end
	return pool[rng:NextInteger(1, #pool)]
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

	-- Apply rebirth luck scaling
	local rebirthLuck = 1 + (data.rebirthCount * 0.02)
	local totalLuck = SpinService.ServerLuckMultiplier * rebirthLuck

	-- Roll
	local rarityName = pickRarity(totalLuck)
	local streamer = pickStreamer(rarityName)

	-- Add to inventory (not auto-equip)
	PlayerData.AddToInventory(player, streamer.id)

	-- Send result to client
	SpinResult:FireClient(player, {
		success = true,
		streamerId = streamer.id,
		displayName = streamer.displayName,
		rarity = rarityName,
	})

	-- Mythic server-wide alert
	if rarityName == "Mythic" then
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

	local cost, luckBonus
	if crateId == 1 then
		cost = Economy.Crate1Cost
		luckBonus = Economy.Crate1LuckBonus
	elseif crateId == 2 then
		cost = Economy.Crate2Cost
		luckBonus = Economy.Crate2LuckBonus
	else
		SpinResult:FireClient(player, { success = false, reason = "Invalid crate!" })
		return
	end

	if not PlayerData.SpendCash(player, cost) then
		SpinResult:FireClient(player, { success = false, reason = "Not enough cash!" })
		return
	end

	-- Rebirth luck + server luck + crate bonus
	local rebirthLuck = 1 + (data.rebirthCount * 0.02)
	local totalLuck = SpinService.ServerLuckMultiplier * rebirthLuck * (1 + luckBonus)

	local rarityName = pickRarity(totalLuck)
	local streamer = pickStreamer(rarityName)

	PlayerData.AddToInventory(player, streamer.id)

	SpinResult:FireClient(player, {
		success = true,
		streamerId = streamer.id,
		displayName = streamer.displayName,
		rarity = rarityName,
	})

	if rarityName == "Mythic" then
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
