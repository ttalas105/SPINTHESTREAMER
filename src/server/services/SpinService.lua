--[[
	SpinService.lua
	Handles spin requests: cost check, weighted RNG, server luck,
	add streamer to collection, notify client of result.
	Mythic pulls trigger a server-wide alert.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local SpinService = {}

-- Server-wide luck multiplier (1x or 2x from Robux purchase)
SpinService.ServerLuckMultiplier = Economy.DefaultLuckMultiplier

-- RemoteEvents
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SpinRequest = RemoteEvents:WaitForChild("SpinRequest")
local SpinResult = RemoteEvents:WaitForChild("SpinResult")
local MythicAlert = RemoteEvents:WaitForChild("MythicAlert")

-- Dependencies (set during Init)
local PlayerData

-------------------------------------------------
-- RNG
-------------------------------------------------

local rng = Random.new()

--- Pick a rarity based on weights, applying luck multiplier
--- Higher luck shifts weight toward rarer tiers
local function pickRarity(luckMultiplier: number): string
	-- Build adjusted weights
	local adjusted = {}
	local total = 0

	for i, tier in ipairs(Rarities.Tiers) do
		local w = tier.weight
		-- Luck multiplier boosts rarer tiers (index > 1)
		if i > 1 and luckMultiplier > 1 then
			w = w * (1 + (luckMultiplier - 1) * (i / #Rarities.Tiers))
		end
		-- Reduce common slightly when luck is active
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

	-- Fallback
	return "Common"
end

--- Pick a random streamer from the given rarity
local function pickStreamer(rarityName: string)
	local pool = Streamers.ByRarity[rarityName]
	if not pool or #pool == 0 then
		-- Fallback to Common
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
			-- Not enough cash
			SpinResult:FireClient(player, { success = false, reason = "Not enough cash!" })
			return
		end
	end

	-- Apply rebirth luck scaling (small bonus)
	local rebirthLuck = 1 + (data.rebirthCount * 0.02) -- 2% per rebirth
	local totalLuck = SpinService.ServerLuckMultiplier * rebirthLuck

	-- Roll
	local rarityName = pickRarity(totalLuck)
	local streamer = pickStreamer(rarityName)

	-- Add to collection
	PlayerData.AddStreamer(player, streamer.id)

	-- Auto-equip in slot 1 if nothing equipped
	local equipped = PlayerData.GetEquippedStreamers(player)
	if not equipped["1"] then
		PlayerData.EquipStreamer(player, 1, streamer.id)
	end

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
-- PUBLIC
-------------------------------------------------

function SpinService.Init(playerDataModule)
	PlayerData = playerDataModule

	SpinRequest.OnServerEvent:Connect(function(player)
		handleSpin(player)
	end)
end

function SpinService.SetServerLuck(multiplier: number)
	SpinService.ServerLuckMultiplier = multiplier
end

return SpinService
