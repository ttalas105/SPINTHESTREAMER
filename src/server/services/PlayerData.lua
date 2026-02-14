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
local RunService = game:GetService("RunService")

local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)

local PlayerData = {}
PlayerData._cache = {} -- userId -> data table

-- In Studio, DataStore API is blocked by default (StudioAccessToApisNotAllowed).
-- Use an in-memory mock so we never call the real API and no error is shown.
local studioMemoryStore = {} -- key -> saved data (only when RunService:IsStudio())

local dataStore
if RunService:IsStudio() then
	-- Avoid calling GetDataStore/GetAsync/SetAsync at all in Studio
	dataStore = {
		GetAsync = function(key)
			return studioMemoryStore[key]
		end,
		SetAsync = function(key, value)
			studioMemoryStore[key] = value
		end,
	}
else
	local ok, err = pcall(function()
		dataStore = DataStoreService:GetDataStore("SpinTheStreamer_v2")
	end)
	if not ok then
		print("[PlayerData] DataStore unavailable; using local data. " .. tostring(err))
		dataStore = {
			GetAsync = function() return nil end,
			SetAsync = function() end,
		}
	end
end

local DEFAULT_DATA = {
	cash = 1000000,
	inventory = {
		{ id = "XQC", effect = "Glitchy" },
		{ id = "Jynxzi", effect = "Solar" },
		{ id = "Kai Cenat", effect = "Void" },
	},
	equippedPads = {},
	collection = { ["XQC"] = true, ["Jynxzi"] = true, ["Kai Cenat"] = true },
	rebirthCount = 0,
	luck = 200,               -- personal luck stat; 1 luck = +1% drop luck (stacked with crate luck)
	cashUpgrade = 0,          -- coin multiplier upgrade count; each +1 = +2% cash production
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
		-- Migration: convert old string-based inventory to {id, effect} tables
		if data.inventory and #data.inventory > 0 and type(data.inventory[1]) == "string" then
			local newInv = {}
			for _, id in ipairs(data.inventory) do
				table.insert(newInv, { id = id })
			end
			data.inventory = newInv
		end
		-- Migration: convert old string-based equippedPads to {id, effect} tables
		if data.equippedPads then
			for key, val in pairs(data.equippedPads) do
				if type(val) == "string" then
					data.equippedPads[key] = { id = val }
				end
			end
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
		cashUpgrade = data.cashUpgrade or 0,
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
-- INVENTORY (items are tables: {id = "Rakai", effect = "Acid" or nil})
-- Helper to get the streamer ID from an item (supports old string format too)
-------------------------------------------------

local function itemId(item)
	if type(item) == "table" then return item.id end
	if type(item) == "string" then return item end
	return nil
end

--- Add a streamer to the player's inventory (with optional effect)
function PlayerData.AddToInventory(player, streamerId: string, effect: string?)
	local data = PlayerData.Get(player)
	if not data then return end
	local item = { id = streamerId }
	if effect then item.effect = effect end
	table.insert(data.inventory, item)
	-- Also mark as discovered in collection
	data.collection[streamerId] = true
	PlayerData.Replicate(player)
end

--- Remove a streamer from inventory by index
function PlayerData.RemoveFromInventory(player, inventoryIndex: number)
	local data = PlayerData.Get(player)
	if not data then return nil end
	if inventoryIndex < 1 or inventoryIndex > #data.inventory then return nil end
	local item = table.remove(data.inventory, inventoryIndex)
	PlayerData.Replicate(player)
	return item
end

--- Remove the first occurrence of a streamer ID from inventory (matches id only, ignores effect)
function PlayerData.RemoveStreamerFromInventory(player, streamerId: string): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	for i, item in ipairs(data.inventory) do
		if itemId(item) == streamerId then
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
	for _, item in ipairs(data.inventory) do
		if itemId(item) == streamerId then count = count + 1 end
	end
	return count
end

-------------------------------------------------
-- EQUIP / UNEQUIP (pad slots — items are {id, effect} tables)
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

	-- Find and remove from inventory (match by id)
	local foundItem = nil
	local foundIndex = nil
	for i, item in ipairs(data.inventory) do
		if itemId(item) == streamerId then
			foundItem = item
			foundIndex = i
			break
		end
	end
	if not foundItem then return false end
	table.remove(data.inventory, foundIndex)

	-- If something is already on this pad, put it back in inventory
	local existing = data.equippedPads[tostring(padSlot)]
	if existing then
		table.insert(data.inventory, existing)
	end

	data.equippedPads[tostring(padSlot)] = foundItem
	PlayerData.Replicate(player)
	return true
end

--- Unequip a streamer from a pad slot back to inventory
function PlayerData.UnequipFromPad(player, padSlot: number): boolean
	local data = PlayerData.Get(player)
	if not data then return false end

	local key = tostring(padSlot)
	local item = data.equippedPads[key]
	if not item then return false end

	-- Move back to inventory
	table.insert(data.inventory, item)
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
	for key, item in pairs(data.equippedPads) do
		table.insert(data.inventory, item)
	end
	data.equippedPads = {}
	-- Inventory and collection are kept; potions are cleared by PotionService
	PlayerData.Replicate(player)
end

-------------------------------------------------
-- LUCK (personal stat: 1 luck = +1% drop luck, stacks with crate luck)
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
-- CASH UPGRADE (coin multiplier: each level = +2% cash production)
-------------------------------------------------

function PlayerData.GetCashUpgrade(player): number
	local data = PlayerData.Get(player)
	return data and (data.cashUpgrade or 0) or 0
end

function PlayerData.AddCashUpgrade(player, amount: number)
	local data = PlayerData.Get(player)
	if not data then return end
	data.cashUpgrade = math.max(0, (data.cashUpgrade or 0) + amount)
	PlayerData.Replicate(player)
end

--- Get the cash upgrade multiplier (1.0 + cashUpgrade * 0.02)
function PlayerData.GetCashUpgradeMultiplier(player): number
	local upgrades = PlayerData.GetCashUpgrade(player)
	return 1 + (upgrades * 0.02)
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
