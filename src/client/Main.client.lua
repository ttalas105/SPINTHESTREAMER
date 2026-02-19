--[[
	Client Entry Point — Spin the Streamer
	Initializes all controllers, wires up navigation, data updates,
	inventory management, equip/unequip, sell, and remote events.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for shared modules
ReplicatedStorage:WaitForChild("Shared")

local controllers = script.Parent.controllers

-- Controllers
local TopNavController       = require(controllers.TopNavController)
local LeftSideNavController  = require(controllers.LeftSideNavController)
local RightSideNavController = require(controllers.RightSideNavController)
local HUDController          = require(controllers.HUDController)
local StoreController        = require(controllers.StoreController)
local SpinController         = require(controllers.SpinController)
local SpinStandController    = require(controllers.SpinStandController)
local UpgradeStandController = require(controllers.UpgradeStandController)
local SellStandController    = require(controllers.SellStandController)
local PotionController       = require(controllers.PotionController)
local RebirthController      = require(controllers.RebirthController)
local HoldController         = require(controllers.HoldController)
local SlotPadController      = require(controllers.SlotPadController)
local InventoryController    = require(controllers.InventoryController)
local IndexController        = require(controllers.IndexController)
local GemShopController      = require(controllers.GemShopController)
local SacrificeController    = require(controllers.SacrificeController)
local StorageController      = require(controllers.StorageController)
local MusicController        = require(controllers.MusicController)
local SettingsController     = require(controllers.SettingsController)
local UIHelper               = require(controllers.UIHelper)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-------------------------------------------------
-- INITIALIZE ALL CONTROLLERS
-------------------------------------------------

HUDController.Init()
TopNavController.Init()
LeftSideNavController.Init()
RightSideNavController.Init()
StoreController.Init()
SpinController.Init()
SpinStandController.Init()
UpgradeStandController.Init()
SellStandController.Init()
PotionController.Init()
RebirthController.Init()
HoldController.Init()
InventoryController.Init()
IndexController.Init()
GemShopController.Init()
SacrificeController.Init()
StorageController.Init()
MusicController.Init()
SettingsController.Init()
SlotPadController.Init(HoldController, InventoryController)

-------------------------------------------------
-- HIDE PLAYER HEALTH BARS
-------------------------------------------------

local function hideCharacterHealth(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
end

local localPlayer = Players.LocalPlayer
if localPlayer.Character then
	hideCharacterHealth(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(function(char)
	hideCharacterHealth(char)
end)

-------------------------------------------------
-- TELEPORT + BASE TRACKING
-------------------------------------------------

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local myBasePosition = nil

local BaseReady = RemoteEvents:WaitForChild("BaseReady")
BaseReady.OnClientEvent:Connect(function(data)
	if data.position then
		myBasePosition = data.position
		SlotPadController.SetBasePosition(data.position)
		print("[Client] Base assigned at position: " .. tostring(data.position))
	end
end)

-------------------------------------------------
-- WIRE TOP NAV TABS (BASE / SHOP) — TELEPORT
-------------------------------------------------

TopNavController.OnTabChanged(function(tabName)
	SpinController.Hide()
	if StoreController.IsOpen() then
		StoreController.Close()
	end

	local character = Players.LocalPlayer.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	if tabName == "BASE" then
		if myBasePosition then
			rootPart.CFrame = CFrame.new(myBasePosition + Vector3.new(0, 5, 0))
		end
	elseif tabName == "SHOP" then
		-- Shop area = gamepasses (Store button opens the Store modal)
		local shopPos = DesignConfig.HubCenter + Vector3.new(0, 5, 15)
		rootPart.CFrame = CFrame.new(shopPos)
	end
end)

-------------------------------------------------
-- WIRE LEFT SIDE NAV (Index, Pets, Store)
-------------------------------------------------

LeftSideNavController.OnClick("Index", function()
	IndexController.Open()
end)

LeftSideNavController.OnClick("Storage", function()
	if StorageController.IsOpen() then
		StorageController.Close()
	else
		StorageController.Open()
	end
end)

LeftSideNavController.OnClick("Store", function()
	if StoreController.IsOpen() then
		StoreController.Close()
	else
		StoreController.Open()
	end
end)

-------------------------------------------------
-- WIRE RIGHT SIDE NAV (Rebirth, Settings)
-------------------------------------------------

RightSideNavController.OnClick("Rebirth", function()
	RebirthController.Open()
end)

RightSideNavController.OnClick("Settings", function()
	if SettingsController.IsOpen() then
		SettingsController.Close()
	else
		SettingsController.Open()
	end
end)

-------------------------------------------------
-- DATA UPDATES -> INVENTORY + PADS
-------------------------------------------------

HUDController.OnDataUpdated(function(data)
	-- Update inventory bar
	InventoryController.UpdateInventory(data.inventory, data.storage)
	-- Update storage UI if open
	StorageController.Refresh()
	-- Update pad controller cache
	SlotPadController.Refresh(data)
end)

-- When sacrifice queues change, refresh inventory/storage visuals
SacrificeController.OnQueueChanged(function()
	InventoryController.RefreshVisuals()
	StorageController.Refresh()
end)

-- Music: pause lobby / start sacrifice music on open, reverse on close
SacrificeController.OnOpen(function()
	MusicController.OnSacrificeOpen()
end)
SacrificeController.OnClose(function()
	MusicController.OnSacrificeClose()
end)

-------------------------------------------------
-- INVENTORY SELECTION -> HOLD MODEL
-------------------------------------------------

InventoryController.OnSelectionChanged(function(slotIndex, item)
	if slotIndex and item then
		-- Player selected an inventory item — hold it in hand
		HoldController.Hold(item)
	else
		-- Player deselected — drop the held model
		HoldController.Drop()
	end
end)

-------------------------------------------------
-- SPIN RESULT -> INVENTORY FLASH
-------------------------------------------------

SpinController.OnSpinResult(function(data)
	-- Flash the newly added item in inventory
	if data.streamerId then
		InventoryController.FlashNewItem(data.streamerId)
	end
end)

-------------------------------------------------
-- EQUIP / UNEQUIP RESULTS
-------------------------------------------------

local EquipResult = RemoteEvents:WaitForChild("EquipResult")
EquipResult.OnClientEvent:Connect(function(data)
	if data.success then
		print("[Client] Equipped " .. (data.streamerId or "?") .. " to pad " .. (data.padSlot or "?"))
		InventoryController.ClearSelection()
	else
		print("[Client] Equip failed: " .. (data.reason or "unknown"))
	end
end)

local UnequipResult = RemoteEvents:WaitForChild("UnequipResult")
UnequipResult.OnClientEvent:Connect(function(data)
	if data.success then
		print("[Client] Unequipped from pad " .. (data.padSlot or "?"))
	else
		print("[Client] Unequip failed: " .. (data.reason or "unknown"))
	end
end)

-- Rebirth result is handled by RebirthController

-------------------------------------------------
-- SELL RESULT
-------------------------------------------------

local SellResult = RemoteEvents:WaitForChild("SellResult")
SellResult.OnClientEvent:Connect(function(data)
	if data.success then
		print("[Client] Sold! +$" .. data.cashEarned)
	else
		print("[Client] Sell failed: " .. (data.reason or "unknown"))
	end
end)

print("[Client] Spin the Streamer initialized!")
