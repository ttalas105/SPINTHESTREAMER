--[[
	PlayerData.lua
	Manages per-player persistent data via DataStoreService.
	Stores: cash, inventory (list of streamer IDs), equippedPads,
	        collection (discovered unique streamers), rebirthCount,
	        premiumSlotUnlocked, doubleCash, spinCredits.
	Replicates relevant state to the owning client.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)

local PlayerData = {}
PlayerData._cache = {} -- userId -> data table

local dataStore
local ok, err = pcall(function()
	dataStore = DataStoreService:GetDataStore("SpinTheStreamer_v2")
end)
if not ok then
	-- Normal in Studio until the place is published to the web
	print("[PlayerData] DataStore unavailable (normal in Studio); using local data. " .. tostring(err))
	-- Create a mock so the game still runs without persistence
	dataStore = {
		GetAsync = function() return nil end,
		SetAsync = function() end,
	}
end

local DEFAULT_DATA = {
	cash = 1000000,
	inventory = {},           -- { "Marlon", "XQC", "Ninja", ... } list of streamer IDs
	equippedPads = {},        -- { ["1"] = "KaiCenat", ["2"] = "Speed" } pad slot -> streamer ID
	collection = {},          -- { ["Marlon"] = true, ["XQC"] = true } discovered uniques
	rebirthCount = 0,
	luck = 0,                 -- personal luck stat; every 20 = +1% drop luck (stacked with crate luck)
	premiumSlotUnlocked = false,
	doubleCash = false,
	spinCredits = 0,
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
		data = deepCopy(DEFAULT_DATA)
		for k, v in pairs(result) do
			data[k] = v
		end
		-- Migration: if old format had "collection" as {id = count}, convert
		if data.collection and next(data.collection) then
			local firstVal = select(2, next(data.collection))
			if type(firstVal) == "number" then
				-- Old format: migrate to new
				local newCollection = {}
				local newInventory = data.inventory or {}
				for streamerId, count in pairs(data.collection) do
					newCollection[streamerId] = true
					for _ = 1, count do
						table.insert(newInventory, streamerId)
					end
				end
				data.collection = newCollection
				data.inventory = newInventory
			end
		end
		-- Migration: if old format had "equippedStreamers", move to equippedPads
		if data.equippedStreamers and not data.equippedPads then
			data.equippedPads = data.equippedStreamers
			data.equippedStreamers = nil
		end
		if data.luck == nil then
			data.luck = 0
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

function PlayerData.Replicate(player)
	local data = PlayerData._cache[player.UserId]
	if not data then return end

	local payload = {
		cash = data.cash,
		inventory = data.inventory,
		equippedPads = data.equippedPads,
		collection = data.collection,
		rebirthCount = data.rebirthCount,
		luck = data.luck or 0,
		premiumSlotUnlocked = data.premiumSlotUnlocked,
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

	-- Handle already-connected players
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

-------------------------------------------------
-- CASH
-------------------------------------------------

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

-------------------------------------------------
-- INVENTORY (new system)
-------------------------------------------------

--- Add a streamer to the player's inventory
function PlayerData.AddToInventory(player, streamerId: string)
	local data = PlayerData.Get(player)
	if not data then return end
	table.insert(data.inventory, streamerId)
	-- Also mark as discovered in collection
	data.collection[streamerId] = true
	PlayerData.Replicate(player)
end

--- Remove a streamer from inventory by index
function PlayerData.RemoveFromInventory(player, inventoryIndex: number): string?
	local data = PlayerData.Get(player)
	if not data then return nil end
	if inventoryIndex < 1 or inventoryIndex > #data.inventory then return nil end
	local streamerId = table.remove(data.inventory, inventoryIndex)
	PlayerData.Replicate(player)
	return streamerId
end

--- Remove the first occurrence of a streamer ID from inventory
function PlayerData.RemoveStreamerFromInventory(player, streamerId: string): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	for i, id in ipairs(data.inventory) do
		if id == streamerId then
			table.remove(data.inventory, i)
			PlayerData.Replicate(player)
			return true
		end
	end
	return false
end

--- Get inventory
function PlayerData.GetInventory(player)
	local data = PlayerData.Get(player)
	if not data then return {} end
	return data.inventory
end

--- Count how many of a specific streamer are in inventory
function PlayerData.CountInInventory(player, streamerId: string): number
	local data = PlayerData.Get(player)
	if not data then return 0 end
	local count = 0
	for _, id in ipairs(data.inventory) do
		if id == streamerId then count = count + 1 end
	end
	return count
end

-------------------------------------------------
-- EQUIP / UNEQUIP (pad slots)
-------------------------------------------------

--- Equip a streamer from inventory to a pad slot
function PlayerData.EquipToPad(player, streamerId: string, padSlot: number): boolean
	local data = PlayerData.Get(player)
	if not data then return false end

	-- Check slot is unlocked
	local totalSlots = SlotsConfig.GetTotalSlots(data.rebirthCount, data.premiumSlotUnlocked)
	if padSlot < 1 or padSlot > totalSlots then return false end

	-- Check premium slot
	if padSlot == SlotsConfig.PremiumSlotIndex and not data.premiumSlotUnlocked then
		return false
	end

	-- Find and remove from inventory
	local found = false
	for i, id in ipairs(data.inventory) do
		if id == streamerId then
			table.remove(data.inventory, i)
			found = true
			break
		end
	end
	if not found then return false end

	-- If something is already on this pad, put it back in inventory
	local existing = data.equippedPads[tostring(padSlot)]
	if existing then
		table.insert(data.inventory, existing)
	end

	data.equippedPads[tostring(padSlot)] = streamerId
	PlayerData.Replicate(player)
	return true
end

--- Unequip a streamer from a pad slot back to inventory
function PlayerData.UnequipFromPad(player, padSlot: number): boolean
	local data = PlayerData.Get(player)
	if not data then return false end

	local key = tostring(padSlot)
	local streamerId = data.equippedPads[key]
	if not streamerId then return false end

	-- Move back to inventory
	table.insert(data.inventory, streamerId)
	data.equippedPads[key] = nil
	PlayerData.Replicate(player)
	return true
end

--- Get equipped pads
function PlayerData.GetEquippedPads(player)
	local data = PlayerData.Get(player)
	if not data then return {} end
	return data.equippedPads
end

-------------------------------------------------
-- COLLECTION (index of discovered uniques)
-------------------------------------------------

function PlayerData.HasDiscovered(player, streamerId: string): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	return data.collection[streamerId] == true
end

-------------------------------------------------
-- REBIRTH
-------------------------------------------------

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
	-- Clear equipped pads, put equipped streamers back into inventory
	for key, streamerId in pairs(data.equippedPads) do
		table.insert(data.inventory, streamerId)
	end
	data.equippedPads = {}
	-- Inventory and collection are kept
	PlayerData.Replicate(player)
end

-------------------------------------------------
-- LUCK (personal stat: every 20 = +1% drop luck, stacks with crate luck)
-------------------------------------------------

function PlayerData.GetLuck(player): number
	local data = PlayerData.Get(player)
	return data and (data.luck or 0) or 0
end

function PlayerData.SetLuck(player, amount: number)
	local data = PlayerData.Get(player)
	if not data then return end
	data.luck = math.max(0, amount)
	PlayerData.Replicate(player)
end

function PlayerData.AddLuck(player, amount: number)
	local data = PlayerData.Get(player)
	if not data then return end
	data.luck = math.max(0, (data.luck or 0) + amount)
	PlayerData.Replicate(player)
end

-------------------------------------------------
-- PREMIUM & PASSES
-------------------------------------------------

function PlayerData.SetPremiumSlot(player, unlocked: boolean)
	local data = PlayerData.Get(player)
	if not data then return end
	data.premiumSlotUnlocked = unlocked
	PlayerData.Replicate(player)
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
