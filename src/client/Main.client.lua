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
local TutorialController     = require(controllers.TutorialController)
local DailyRewardController  = require(controllers.DailyRewardController)
local QuestController        = require(controllers.QuestController)
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
TutorialController.Init()
DailyRewardController.Init()
QuestController.Init()
SlotPadController.Init(HoldController, InventoryController)

-------------------------------------------------
-- HIDE PLAYER HEALTH BARS + MOVEMENT SPEED
-------------------------------------------------

local DEFAULT_WALKSPEED = 16
local WALKSPEED_MULTIPLIER = 1.30  -- 30% faster

local function setupCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.WalkSpeed = math.floor(DEFAULT_WALKSPEED * WALKSPEED_MULTIPLIER + 0.5)  -- 20
	end
end

local localPlayer = Players.LocalPlayer
if localPlayer.Character then
	setupCharacter(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(function(char)
	setupCharacter(char)
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
		TutorialController.OnBaseReady(data)
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

	if TutorialController.IsActive() then
		TutorialController.OnTabChanged(tabName)
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

RightSideNavController.OnClick("Quests", function()
	if QuestController.IsOpen() then
		QuestController.Close()
	else
		QuestController.Open()
	end
end)

-------------------------------------------------
-- DATA UPDATES -> INVENTORY + PADS
-------------------------------------------------

local tutorialStarted = false
HUDController.OnDataUpdated(function(data)
	InventoryController.UpdateInventory(data.inventory, data.storage)
	StorageController.Refresh()
	SlotPadController.Refresh(data)

	if not tutorialStarted and data.tutorialComplete ~= nil then
		tutorialStarted = true
		if TutorialController.ShouldStart(data) then
			task.delay(1.5, function()
				TutorialController.Start()
			end)
		end
	end
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
	if data.streamerId then
		InventoryController.FlashNewItem(data.streamerId)
	end
	if TutorialController.IsActive() then
		TutorialController.OnSpinResult(data)
	end
end)

-- Base single-slot place/remove result handling
local EquipResult = RemoteEvents:WaitForChild("EquipResult")
EquipResult.OnClientEvent:Connect(function(data)
	if data and data.success then
		InventoryController.ClearSelection()
		HoldController.Drop()
	elseif data and data.reason then
		warn("[Client] Place failed: " .. tostring(data.reason))
	end
	if TutorialController.IsActive() then
		TutorialController.OnEquipResult(data)
	end
end)

local UnequipResult = RemoteEvents:WaitForChild("UnequipResult")
UnequipResult.OnClientEvent:Connect(function(data)
	if data and data.success and data.streamerId then
		-- Remove action: also select returned item in inventory.
		local selected = InventoryController.SelectByItem(data.streamerId, data.effect)
		if not selected then
			-- Fallback in case inventory replication arrives slightly later.
			HoldController.Hold({
				id = data.streamerId,
				effect = data.effect,
			})
			task.delay(0.12, function()
				InventoryController.SelectByItem(data.streamerId, data.effect)
			end)
		end
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

-------------------------------------------------
-- TUTORIAL HOOKS
-------------------------------------------------

local OpenSpinStandGuiTutorial = RemoteEvents:WaitForChild("OpenSpinStandGui")
OpenSpinStandGuiTutorial.OnClientEvent:Connect(function()
	if TutorialController.IsActive() then
		TutorialController.OnSpinStandOpened()
	end
end)

print("[Client] Spin the Streamer initialized!")
