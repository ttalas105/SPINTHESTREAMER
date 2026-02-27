--[[
	PlayerData.lua
	Manages per-player persistent data via DataStoreService.
	Stores: cash, inventory (hotbar, max 9), storage (overflow, max 200),
	        equippedPads, collection (discovered unique streamers), rebirthCount,
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

-------------------------------------------------
-- SECURITY FIX: Per-player operation mutex/queue
-- Prevents race conditions when concurrent remote events
-- mutate the same player's data simultaneously.
-- Usage: PlayerData.WithLock(player, function() ... end)
-------------------------------------------------
local playerLocks = {} -- [userId] = {locked = bool, queue = { BindableEvent }}

function PlayerData.WithLock(player, fn)
	local userId = player.UserId
	if not playerLocks[userId] then
		playerLocks[userId] = { locked = false, queue = {} }
	end
	local lock = playerLocks[userId]

	if lock.locked then
		-- Queue this operation and wait until it's our turn.
		-- BindableEvent-based waiting is more robust than coroutine handoff.
		local waiter = Instance.new("BindableEvent")
		table.insert(lock.queue, waiter)
		waiter.Event:Wait()
		waiter:Destroy()
	end

	lock.locked = true
	local ok, err = pcall(fn)
	lock.locked = false

	-- Resume next queued operation
	if #lock.queue > 0 then
		local nextWaiter = table.remove(lock.queue, 1)
		if nextWaiter then
			nextWaiter:Fire()
		end
	end

	if not ok then
		warn("[PlayerData] WithLock error for " .. player.Name .. ": " .. tostring(err))
	end
end

-- Capacity constants
PlayerData.HOTBAR_MAX  = 9
PlayerData.STORAGE_MAX = 200

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
	cash = 200,
	gems = 0,
	inventory = {},
	storage = {},  -- overflow storage (max 200 items, same {id, effect} format)
	equippedPads = {},
	collection = {},
	-- Index collection: tracks every unique streamer+effect combo the player has pulled
	-- Key = "StreamerId" for base, "Effect:StreamerId" for effect variants
	-- Value = true (unlocked) or "claimed" (gems already collected)
	indexCollection = {},
	rebirthCount = 0,
	luck = 0,                 -- personal luck stat; 1 luck = +1% drop luck (stacked with crate luck)
	cashUpgrade = 0,          -- coin multiplier upgrade count; each +1 = +2% cash production
	premiumSlotUnlocked = false,
	doubleCash = false,
	hasVIP = false,
	hasX2Luck = false,
	spinCredits = 0,
	-- Sacrifice: one-time completed, charge slots (rechargeAt times)
	sacrificeOneTime = {},
	sacrificeCharges = { FiftyFifty = {}, FeelingLucky = {} },
	tutorialComplete = false,
	-- Pity system: tracks spins since last rarity hit
	pityCounters = {
		Rare = 0,
		Epic = 0,
		Legendary = 0,
		Mythic = 0,
	},
	-- Daily login streak
	dailyLoginStreak = 0,
	lastLoginDay = 0,
	-- Quests
	questProgress = {},
	questClaimed = {},
	-- Owned crates: { [crateId] = count } — bought from Case Shop, opened separately
	ownedCrates = {},
	-- Lifetime stats (for global leaderboards)
	totalSpins = 0,
	totalCashEarned = 0,
	timePlayed = 0,
	robuxSpent = 0,
}

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PlayerDataUpdate = RemoteEvents:WaitForChild("PlayerDataUpdate")

-- OPTIMIZATION: Track last replicated state per player for delta replication
local lastReplicated = {} -- [userId] = {field = value, ...}

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
		-- Migration: ensure storage exists
		if not data.storage then data.storage = {} end
		-- Migration: if inventory has more than HOTBAR_MAX items, move overflow to storage
		if data.inventory and #data.inventory > PlayerData.HOTBAR_MAX then
			local overflow = {}
			for i = #data.inventory, PlayerData.HOTBAR_MAX + 1, -1 do
				table.insert(overflow, 1, table.remove(data.inventory, i))
			end
			for _, item in ipairs(overflow) do
				if #data.storage < PlayerData.STORAGE_MAX then
					table.insert(data.storage, item)
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

-- OPTIMIZATION: Build full payload (used for initial send and delta comparison)
local function buildFullPayload(player, data)
	return {
		cash = data.cash,
		gems = data.gems or 0,
		inventory = data.inventory,
		storage = data.storage or {},
		equippedPads = data.equippedPads,
		collection = data.collection,
		indexCollection = data.indexCollection or {},
		rebirthCount = data.rebirthCount,
		luck = data.luck or 0,
		cashUpgrade = data.cashUpgrade or 0,
		premiumSlotUnlocked = data.premiumSlotUnlocked,
		doubleCash = data.doubleCash,
		hasVIP = data.hasVIP or false,
		hasX2Luck = data.hasX2Luck or false,
		spinCredits = data.spinCredits,
		totalSlots = SlotsConfig.GetTotalSlots(data.rebirthCount, data.premiumSlotUnlocked),
		tutorialComplete = data.tutorialComplete or false,
		sacrificeOneTime = data.sacrificeOneTime or {},
		sacrificeCharges = data.sacrificeCharges or { FiftyFifty = {}, FeelingLucky = {} },
		sacrificeChargeState = {
			FiftyFifty = {
				count = PlayerData.GetSacrificeChargeCount(player, "FiftyFifty", 3, 600),
				nextAt = PlayerData.GetSacrificeNextRechargeAt(player, "FiftyFifty", 3),
			},
			FeelingLucky = {
				count = PlayerData.GetSacrificeChargeCount(player, "FeelingLucky", 1, 1200),
				nextAt = PlayerData.GetSacrificeNextRechargeAt(player, "FeelingLucky", 1),
			},
		},
		ownedCrates = data.ownedCrates or {},
	}
end

-- OPTIMIZATION: Only send changed top-level fields (delta replication)
-- Scalar fields use == comparison; tables always resend (cheap enough for correctness)
local SCALAR_FIELDS = {
	"cash", "gems", "rebirthCount", "luck", "cashUpgrade",
	"premiumSlotUnlocked", "doubleCash", "hasVIP", "hasX2Luck",
	"spinCredits", "totalSlots", "tutorialComplete",
}
local SCALAR_SET = {}
for _, f in ipairs(SCALAR_FIELDS) do SCALAR_SET[f] = true end

function PlayerData.Replicate(player)
	local data = PlayerData._cache[player.UserId]
	if not data then return end

	local full = buildFullPayload(player, data)
	local userId = player.UserId
	local prev = lastReplicated[userId]

	if not prev then
		-- First replication: send everything
		lastReplicated[userId] = full
		PlayerDataUpdate:FireClient(player, full)
		return
	end

	-- Build delta: only changed fields
	local delta = {}
	local hasChange = false
	for key, val in pairs(full) do
		if SCALAR_SET[key] then
			if prev[key] ~= val then
				delta[key] = val
				hasChange = true
			end
		else
			-- Table fields: always include (comparing tables is expensive and error-prone)
			delta[key] = val
			hasChange = true
		end
	end

	if hasChange then
		lastReplicated[userId] = full
		PlayerDataUpdate:FireClient(player, delta)
	end
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
		playerLocks[player.UserId] = nil
		lastReplicated[player.UserId] = nil
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

function PlayerData.IsTutorialComplete(player)
	local data = PlayerData._cache[player.UserId]
	if not data then return true end
	return data.tutorialComplete ~= false
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

local function itemEffect(item)
	if type(item) ~= "table" then return nil end
	local e = item.effect
	if e == nil or e == "" then return nil end
	return e
end

--- Add a streamer to the player's hotbar or storage (with optional effect).
--- Returns "hotbar", "storage", or "full" depending on where the item went.
function PlayerData.AddToInventory(player, streamerId: string, effect: string?): string
	local data = PlayerData.Get(player)
	if not data then return "full" end
	local item = { id = streamerId }
	if effect then item.effect = effect end
	if not data.storage then data.storage = {} end
	local dest
	if #data.inventory < PlayerData.HOTBAR_MAX then
		table.insert(data.inventory, item)
		dest = "hotbar"
	elseif #data.storage < PlayerData.STORAGE_MAX then
		table.insert(data.storage, item)
		dest = "storage"
	else
		dest = "full"
	end
	-- Always mark as discovered even if storage is full
	data.collection[streamerId] = true
	if not data.indexCollection then data.indexCollection = {} end
	local indexKey = effect and (effect .. ":" .. streamerId) or streamerId
	if not data.indexCollection[indexKey] then
		data.indexCollection[indexKey] = true
	end
	PlayerData.Replicate(player)
	return dest
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

--- Remove multiple items by indices (indices 1-based; remove from highest to lowest to avoid shift)
function PlayerData.RemoveFromInventoryIndices(player, indices: { number })
	local data = PlayerData.Get(player)
	if not data then return end
	table.sort(indices, function(a, b) return a > b end)
	for _, idx in ipairs(indices) do
		if idx >= 1 and idx <= #data.inventory then
			table.remove(data.inventory, idx)
		end
	end
	PlayerData.Replicate(player)
end

-------------------------------------------------
-- STORAGE (overflow inventory, max 200)
-------------------------------------------------

--- Get storage array
function PlayerData.GetStorage(player)
	local data = PlayerData.Get(player)
	if not data then return {} end
	if not data.storage then data.storage = {} end
	return data.storage
end

--- Add directly to storage
function PlayerData.AddToStorage(player, streamerId: string, effect: string?): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	if not data.storage then data.storage = {} end
	if #data.storage >= PlayerData.STORAGE_MAX then return false end
	local item = { id = streamerId }
	if effect then item.effect = effect end
	table.insert(data.storage, item)
	PlayerData.Replicate(player)
	return true
end

--- Remove from storage by index
function PlayerData.RemoveFromStorage(player, storageIndex: number)
	local data = PlayerData.Get(player)
	if not data or not data.storage then return nil end
	if storageIndex < 1 or storageIndex > #data.storage then return nil end
	local item = table.remove(data.storage, storageIndex)
	PlayerData.Replicate(player)
	return item
end

--- Remove multiple items from storage by indices (highest to lowest to avoid shift)
function PlayerData.RemoveFromStorageIndices(player, indices: { number })
	local data = PlayerData.Get(player)
	if not data or not data.storage then return end
	table.sort(indices, function(a, b) return a > b end)
	for _, idx in ipairs(indices) do
		if idx >= 1 and idx <= #data.storage then
			table.remove(data.storage, idx)
		end
	end
	PlayerData.Replicate(player)
end

--- Swap an item between hotbar and storage
function PlayerData.SwapHotbarStorage(player, hotbarIndex: number, storageIndex: number): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	if not data.storage then data.storage = {} end
	if hotbarIndex < 1 or hotbarIndex > #data.inventory then return false end
	if storageIndex < 1 or storageIndex > #data.storage then return false end
	data.inventory[hotbarIndex], data.storage[storageIndex] = data.storage[storageIndex], data.inventory[hotbarIndex]
	PlayerData.Replicate(player)
	return true
end

--- Move from storage to an empty hotbar slot (or swap if hotbar slot occupied)
function PlayerData.MoveStorageToHotbar(player, storageIndex: number, hotbarIndex: number?): boolean
	local data = PlayerData.Get(player)
	if not data or not data.storage then return false end
	if storageIndex < 1 or storageIndex > #data.storage then return false end
	if #data.inventory >= PlayerData.HOTBAR_MAX then return false end
	if hotbarIndex then
		if hotbarIndex < 1 or hotbarIndex > PlayerData.HOTBAR_MAX then return false end
		if hotbarIndex <= #data.inventory then
			-- Occupied slot: swap
			data.inventory[hotbarIndex], data.storage[storageIndex] = data.storage[storageIndex], data.inventory[hotbarIndex]
		else
			-- Empty target slot: append to the next valid contiguous hotbar slot.
			-- We intentionally avoid sparse-array insertion to prevent item loss.
			local item = data.storage[storageIndex]
			if not item then return false end
			table.remove(data.storage, storageIndex)
			table.insert(data.inventory, item)
		end
	else
		-- No specific slot: append to hotbar if space
		local item = table.remove(data.storage, storageIndex)
		table.insert(data.inventory, item)
	end
	PlayerData.Replicate(player)
	return true
end

--- Move from hotbar to storage
function PlayerData.MoveHotbarToStorage(player, hotbarIndex: number): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	if not data.storage then data.storage = {} end
	if hotbarIndex < 1 or hotbarIndex > #data.inventory then return false end
	if #data.storage >= PlayerData.STORAGE_MAX then return false end
	local item = table.remove(data.inventory, hotbarIndex)
	table.insert(data.storage, item)
	PlayerData.Replicate(player)
	return true
end

-------------------------------------------------
-- SACRIFICE (one-time completed, charges)
-------------------------------------------------

function PlayerData.GetSacrificeOneTimeCompleted(player)
	local data = PlayerData.Get(player)
	return data and (data.sacrificeOneTime or {}) or {}
end

function PlayerData.SetSacrificeOneTimeCompleted(player, id: string)
	local data = PlayerData.Get(player)
	if not data then return end
	if not data.sacrificeOneTime then data.sacrificeOneTime = {} end
	data.sacrificeOneTime[id] = true
	PlayerData.Replicate(player)
end

function PlayerData.GetSacrificeChargesRaw(player, key: string)
	local data = PlayerData.Get(player)
	if not data or not data.sacrificeCharges then return {} end
	return data.sacrificeCharges[key] or {}
end

--- Use one charge; rechargeSeconds = time until this slot refills. maxSlots = 3 or 1. Returns true if had a charge.
function PlayerData.UseSacrificeCharge(player, key: string, rechargeSeconds: number, maxSlots: number): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	if not data.sacrificeCharges then data.sacrificeCharges = {} end
	local slots = data.sacrificeCharges[key]
	if not slots then slots = {}; data.sacrificeCharges[key] = slots end
	local now = os.time()
	local limit = maxSlots or 3
	for i = 1, limit do
		if not slots[i] or slots[i] <= now then
			slots[i] = now + rechargeSeconds
			PlayerData.Replicate(player)
			return true
		end
	end
	return false
end

--- Get current charge count (filled slots that are recharged)
function PlayerData.GetSacrificeChargeCount(player, key: string, maxCharges: number, rechargeSeconds: number): number
	local slots = PlayerData.GetSacrificeChargesRaw(player, key)
	local now = os.time()
	local count = 0
	for i = 1, maxCharges do
		if slots[i] and slots[i] <= now then count = count + 1 end
	end
	return count
end

--- Get next recharge time (when the next used slot will refill)
function PlayerData.GetSacrificeNextRechargeAt(player, key: string, maxCharges: number): number?
	local slots = PlayerData.GetSacrificeChargesRaw(player, key)
	local now = os.time()
	local nextAt = nil
	for i = 1, maxCharges do
		if slots[i] and slots[i] > now then
			if not nextAt or slots[i] < nextAt then nextAt = slots[i] end
		end
	end
	return nextAt
end

-------------------------------------------------
-- EQUIP / UNEQUIP (pad slots — items are {id, effect} tables)
-------------------------------------------------

--- Equip a streamer from inventory to a pad slot.
--- effect: optional; if provided, matches the specific instance (e.g. Acid Cinna vs base Cinna).
function PlayerData.EquipToPad(player, streamerId: string, padSlot: number, ignoreUnlockCheck: boolean?, effect: string?): boolean
	local data = PlayerData.Get(player)
	if not data then return false end

	-- Check slot is unlocked
	if not ignoreUnlockCheck and not SlotsConfig.IsSlotUnlocked(data.rebirthCount or 0, data.premiumSlotUnlocked == true, padSlot) then
		return false
	end

	local wantEffect = (effect == nil or effect == "") and nil or effect
	-- Find and remove from inventory (match by id AND effect so we remove the one in hand, not first match)
	local foundItem = nil
	local foundIndex = nil
	for i, item in ipairs(data.inventory) do
		if itemId(item) == streamerId and itemEffect(item) == wantEffect then
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
	task.defer(function()
		PlayerData.Replicate(player)
	end)
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
	task.defer(function()
		PlayerData.Replicate(player)
	end)
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
	if not data.storage then data.storage = {} end
	-- Keep equippedPads: streamers stay on base pads across rebirth (no return to inventory)
	-- Inventory, storage, collection, and equippedPads are kept; potions are cleared by PotionService
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
-- GEMS
-------------------------------------------------

function PlayerData.GetGems(player): number
	local data = PlayerData.Get(player)
	return data and (data.gems or 0) or 0
end

function PlayerData.AddGems(player, amount: number)
	local data = PlayerData.Get(player)
	if not data then return end
	data.gems = math.max(0, (data.gems or 0) + amount)
	PlayerData.Replicate(player)
end

function PlayerData.SpendGems(player, amount: number): boolean
	local data = PlayerData.Get(player)
	if not data or (data.gems or 0) < amount then return false end
	data.gems = data.gems - amount
	PlayerData.Replicate(player)
	return true
end

-------------------------------------------------
-- INDEX COLLECTION (streamer+effect discovery)
-------------------------------------------------

--- Get the index collection key for a streamer+effect combo
function PlayerData.GetIndexKey(streamerId: string, effect: string?): string
	if effect then return effect .. ":" .. streamerId end
	return streamerId
end

--- Check if a streamer+effect combo has been discovered
function PlayerData.HasIndexEntry(player, streamerId: string, effect: string?): boolean
	local data = PlayerData.Get(player)
	if not data or not data.indexCollection then return false end
	local key = PlayerData.GetIndexKey(streamerId, effect)
	return data.indexCollection[key] ~= nil
end

--- Check if gems have been claimed for this entry
function PlayerData.HasClaimedIndexGems(player, streamerId: string, effect: string?): boolean
	local data = PlayerData.Get(player)
	if not data or not data.indexCollection then return false end
	local key = PlayerData.GetIndexKey(streamerId, effect)
	return data.indexCollection[key] == "claimed"
end

--- Mark gems as claimed for an index entry
function PlayerData.ClaimIndexGems(player, streamerId: string, effect: string?): boolean
	local data = PlayerData.Get(player)
	if not data or not data.indexCollection then return false end
	local key = PlayerData.GetIndexKey(streamerId, effect)
	if data.indexCollection[key] ~= true then return false end -- not unlocked or already claimed
	data.indexCollection[key] = "claimed"
	PlayerData.Replicate(player)
	return true
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

function PlayerData.SetVIP(player, active: boolean)
	local data = PlayerData.Get(player)
	if not data then return end
	data.hasVIP = active
	PlayerData.Replicate(player)
end

function PlayerData.HasVIP(player): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	return data.hasVIP == true
end

function PlayerData.SetX2Luck(player, active: boolean)
	local data = PlayerData.Get(player)
	if not data then return end
	data.hasX2Luck = active
	PlayerData.Replicate(player)
end

function PlayerData.HasX2Luck(player): boolean
	local data = PlayerData.Get(player)
	if not data then return false end
	return data.hasX2Luck == true
end

function PlayerData.IncrementStat(player, statName: string, amount: number)
	local data = PlayerData.Get(player)
	if not data then return end
	data[statName] = (data[statName] or 0) + amount
end

function PlayerData.GetStat(player, statName: string): number
	local data = PlayerData.Get(player)
	if not data then return 0 end
	return data[statName] or 0
end

return PlayerData
