--[[
	PlayerData.lua
	Manages per-player persistent data via DataStoreService.
	Stores: cash, collection (streamerId -> count), rebirthCount,
	        premiumSlotUnlocked, equippedStreamers, doubleCash.
	Replicates relevant state to the owning client.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)

local PlayerData = {}
PlayerData._cache = {} -- userId -> data table

local dataStore = DataStoreService:GetDataStore("SpinTheStreamer_v1")

local DEFAULT_DATA = {
	cash = 500,
	collection = {},          -- { [streamerId] = count }
	rebirthCount = 0,
	premiumSlotUnlocked = false,
	equippedStreamers = {},   -- { [slotIndex] = streamerId }
	doubleCash = false,
	spinCredits = 0,          -- from Robux purchases
}

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PlayerDataUpdate = RemoteEvents:WaitForChild("PlayerDataUpdate")

-------------------------------------------------
-- INTERNAL HELPERS
-------------------------------------------------

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function loadData(player)
	local success, result = pcall(function()
		return dataStore:GetAsync("Player_" .. player.UserId)
	end)

	local data
	if success and result then
		-- Merge with defaults for any missing keys
		data = deepCopy(DEFAULT_DATA)
		for k, v in pairs(result) do
			data[k] = v
		end
	else
		data = deepCopy(DEFAULT_DATA)
	end

	return data
end

local function saveData(player)
	local data = PlayerData._cache[player.UserId]
	if not data then return end

	local success, err = pcall(function()
		dataStore:SetAsync("Player_" .. player.UserId, data)
	end)

	if not success then
		warn("[PlayerData] Failed to save for " .. player.Name .. ": " .. tostring(err))
	end
end

-------------------------------------------------
-- REPLICATION
-------------------------------------------------

--- Send the full player data snapshot to client
function PlayerData.Replicate(player)
	local data = PlayerData._cache[player.UserId]
	if not data then return end

	-- Send a safe copy (strip anything non-serializable)
	local payload = {
		cash = data.cash,
		collection = data.collection,
		rebirthCount = data.rebirthCount,
		premiumSlotUnlocked = data.premiumSlotUnlocked,
		equippedStreamers = data.equippedStreamers,
		doubleCash = data.doubleCash,
		spinCredits = data.spinCredits,
		totalSlots = SlotsConfig.GetTotalSlots(data.rebirthCount, data.premiumSlotUnlocked),
	}

	PlayerDataUpdate:FireClient(player, payload)
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

function PlayerData.Init()
	Players.PlayerAdded:Connect(function(player)
		local data = loadData(player)
		PlayerData._cache[player.UserId] = data
		PlayerData.Replicate(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		saveData(player)
		PlayerData._cache[player.UserId] = nil
	end)

	-- Auto-save every 120 seconds
	task.spawn(function()
		while true do
			task.wait(120)
			for _, player in ipairs(Players:GetPlayers()) do
				saveData(player)
			end
		end
	end)

	-- Handle already-connected players (in case of late init)
	for _, player in ipairs(Players:GetPlayers()) do
		if not PlayerData._cache[player.UserId] then
			local data = loadData(player)
			PlayerData._cache[player.UserId] = data
			PlayerData.Replicate(player)
		end
	end
end

function PlayerData.Get(player)
	return PlayerData._cache[player.UserId]
end

function PlayerData.GetCash(player): number
	local data = PlayerData.Get(player)
	return data and data.cash or 0
end

function PlayerData.AddCash(player, amount: number)
	local data = PlayerData.Get(player)
	if not data then return end
	data.cash = data.cash + amount
	PlayerData.Replicate(player)
end

function PlayerData.SpendCash(player, amount: number): boolean
	local data = PlayerData.Get(player)
	if not data or data.cash < amount then return false end
	data.cash = data.cash - amount
	PlayerData.Replicate(player)
	return true
end

function PlayerData.AddStreamer(player, streamerId: string)
	local data = PlayerData.Get(player)
	if not data then return end
	data.collection[streamerId] = (data.collection[streamerId] or 0) + 1
	PlayerData.Replicate(player)
end

function PlayerData.RemoveStreamer(player, streamerId: string): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	local count = data.collection[streamerId] or 0
	if count < 2 then return false end -- keep at least 1
	data.collection[streamerId] = count - 1
	PlayerData.Replicate(player)
	return true
end

function PlayerData.HasStreamer(player, streamerId: string): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	return (data.collection[streamerId] or 0) > 0
end

function PlayerData.GetStreamerCount(player, streamerId: string): number
	local data = PlayerData.Get(player)
	if not data then return 0 end
	return data.collection[streamerId] or 0
end

function PlayerData.GetRebirthCount(player): number
	local data = PlayerData.Get(player)
	return data and data.rebirthCount or 0
end

function PlayerData.SetRebirthCount(player, count: number)
	local data = PlayerData.Get(player)
	if not data then return end
	data.rebirthCount = count
	PlayerData.Replicate(player)
end

function PlayerData.ResetForRebirth(player)
	local data = PlayerData.Get(player)
	if not data then return end
	data.cash = 0
	data.equippedStreamers = {}
	-- Collection is kept
	PlayerData.Replicate(player)
end

function PlayerData.SetPremiumSlot(player, unlocked: boolean)
	local data = PlayerData.Get(player)
	if not data then return end
	data.premiumSlotUnlocked = unlocked
	PlayerData.Replicate(player)
end

function PlayerData.EquipStreamer(player, slotIndex: number, streamerId: string): boolean
	local data = PlayerData.Get(player)
	if not data then return false end

	-- Check they own the streamer
	if (data.collection[streamerId] or 0) <= 0 then return false end

	-- Check slot is unlocked
	local totalSlots = SlotsConfig.GetTotalSlots(data.rebirthCount, data.premiumSlotUnlocked)
	if slotIndex < 1 or slotIndex > totalSlots then return false end

	data.equippedStreamers[tostring(slotIndex)] = streamerId
	PlayerData.Replicate(player)
	return true
end

function PlayerData.GetEquippedStreamers(player)
	local data = PlayerData.Get(player)
	if not data then return {} end
	return data.equippedStreamers
end

function PlayerData.AddSpinCredits(player, amount: number)
	local data = PlayerData.Get(player)
	if not data then return end
	data.spinCredits = (data.spinCredits or 0) + amount
	PlayerData.Replicate(player)
end

function PlayerData.UseSpinCredit(player): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	if (data.spinCredits or 0) <= 0 then return false end
	data.spinCredits = data.spinCredits - 1
	PlayerData.Replicate(player)
	return true
end

function PlayerData.SetDoubleCash(player, active: boolean)
	local data = PlayerData.Get(player)
	if not data then return end
	data.doubleCash = active
	PlayerData.Replicate(player)
end

function PlayerData.HasDoubleCash(player): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	return data.doubleCash == true
end

return PlayerData
