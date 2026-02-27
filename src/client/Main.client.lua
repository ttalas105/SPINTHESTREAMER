--[[
	Client Entry Point — Spin the Streamer
	Initializes all controllers, wires up navigation, data updates,
	inventory management, equip/unequip, sell, and remote events.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

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
local QuestController        = require(controllers.QuestController)
local UIHelper               = require(controllers.UIHelper)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local function showSystemToast(titleText, bodyText)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = titleText or "Spin the Streamer",
			Text = bodyText or "",
			Duration = 3,
		})
	end)
end

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
QuestController.Init()
SlotPadController.Init(HoldController, InventoryController)

-------------------------------------------------
-- DEBUG: Give all streamers button (Studio only)
-------------------------------------------------
if RunService:IsStudio() then
	task.defer(function()
		local debugRemote = RemoteEvents:FindFirstChild("DebugGiveAll")
		if not debugRemote then
			debugRemote = RemoteEvents:WaitForChild("DebugGiveAll", 5)
		end
		if debugRemote then
			local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
			local sg = Instance.new("ScreenGui")
			sg.Name = "DebugGui"; sg.ResetOnSpawn = false; sg.DisplayOrder = 100; sg.Parent = playerGui
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 160, 0, 36)
			btn.Position = UDim2.new(0, 10, 0, 10)
			btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
			btn.Text = "DEBUG: Give All"; btn.TextColor3 = Color3.new(1, 1, 1)
			btn.Font = Enum.Font.FredokaOne; btn.TextSize = 16; btn.BorderSizePixel = 0
			btn.Parent = sg
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
			btn.MouseButton1Click:Connect(function()
				btn.Text = "Giving..."
				debugRemote:FireServer()
				task.wait(1)
				btn.Text = "DEBUG: Give All"
			end)

			local skipBtn = Instance.new("TextButton")
			skipBtn.Size = UDim2.new(0, 160, 0, 36)
			skipBtn.Position = UDim2.new(0, 10, 0, 52)
			skipBtn.BackgroundColor3 = Color3.fromRGB(180, 120, 30)
			skipBtn.Text = "DEBUG: Skip Tutorial"; skipBtn.TextColor3 = Color3.new(1, 1, 1)
			skipBtn.Font = Enum.Font.FredokaOne; skipBtn.TextSize = 14; skipBtn.BorderSizePixel = 0
			skipBtn.Parent = sg
			Instance.new("UICorner", skipBtn).CornerRadius = UDim.new(0, 8)
			skipBtn.MouseButton1Click:Connect(function()
				skipBtn.Text = "Skipping..."
				TutorialController.ForceComplete()
				task.wait(0.5)
				skipBtn.Text = "Done!"
			end)
		end
	end)
end

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
-- CLOSE ALL MODALS (prevents stacking)
-------------------------------------------------

local function closeAllModals(except)
	if except ~= "Index"       and IndexController.IsOpen()          then IndexController.Close() end
	if except ~= "Storage"     and StorageController.IsOpen()        then StorageController.Close() end
	if except ~= "Store"       and StoreController.IsOpen()          then StoreController.Close() end
	if except ~= "SpinStand"   and SpinStandController.IsOpen()      then SpinStandController.Close() end
	if except ~= "Sell"        and SellStandController.IsOpen()      then SellStandController.Close() end
	if except ~= "Upgrade"     and UpgradeStandController.IsOpen()   then UpgradeStandController.Close() end
	if except ~= "Rebirth"     and RebirthController.IsOpen()        then RebirthController.Close() end
	if except ~= "Settings"    and SettingsController.IsOpen()       then SettingsController.Close() end
	if except ~= "Quests"      and QuestController.IsOpen()          then QuestController.Close() end
	if except ~= "Potion"      and PotionController.IsShopOpen()     then PotionController.CloseShop() end
	if except ~= "GemShop"     and GemShopController.IsOpen()        then GemShopController.Close() end
	if except ~= "Sacrifice"   and SacrificeController.IsOpen()      then SacrificeController.Close() end
	SpinController.Hide()
end

-------------------------------------------------
-- WIRE TOP NAV TABS (BASE / SHOP) — TELEPORT
-------------------------------------------------

TopNavController.OnTabChanged(function(tabName)
	closeAllModals()

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
	if TutorialController.IsActive() then return end
	if IndexController.IsOpen() then
		IndexController.Close()
	else
		closeAllModals("Index")
		IndexController.Open()
	end
end)

LeftSideNavController.OnClick("Storage", function()
	if TutorialController.IsActive() then return end
	if StorageController.IsOpen() then
		StorageController.Close()
	else
		closeAllModals("Storage")
		StorageController.Open()
	end
end)

LeftSideNavController.OnClick("Store", function()
	if TutorialController.IsActive() then return end
	if StoreController.IsOpen() then
		StoreController.Close()
	else
		closeAllModals("Store")
		StoreController.Open()
	end
end)

-------------------------------------------------
-- WIRE RIGHT SIDE NAV (Rebirth, Settings)
-------------------------------------------------

RightSideNavController.OnClick("Rebirth", function()
	if TutorialController.IsActive() then return end
	if RebirthController.IsOpen() then
		RebirthController.Close()
	else
		closeAllModals("Rebirth")
		RebirthController.Open()
	end
end)

RightSideNavController.OnClick("Settings", function()
	if TutorialController.IsActive() then return end
	if SettingsController.IsOpen() then
		SettingsController.Close()
	else
		closeAllModals("Settings")
		SettingsController.Open()
	end
end)

RightSideNavController.OnClick("Quests", function()
	if TutorialController.IsActive() then return end
	if QuestController.IsOpen() then
		QuestController.Close()
	else
		closeAllModals("Quests")
		QuestController.Open()
	end
end)

-------------------------------------------------
-- DATA UPDATES -> INVENTORY + PADS
-------------------------------------------------

local tutorialStarted = false
local pendingInventoryData = nil

HUDController.OnDataUpdated(function(data)
	if SpinController.IsAnimating() then
		pendingInventoryData = data
	else
		InventoryController.UpdateInventory(data.inventory, data.storage)
		StorageController.Refresh()
	end
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

-- Safety fallback: if the initial data arrived before the callback was registered,
-- check now so the tutorial still triggers for new players.
task.defer(function()
	local data = HUDController.Data
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
	-- Flush deferred inventory update now that animation is done
	if pendingInventoryData then
		InventoryController.UpdateInventory(pendingInventoryData.inventory, pendingInventoryData.storage)
		StorageController.Refresh()
		pendingInventoryData = nil
	end
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
		showSystemToast("Base Slot", tostring(data.reason))
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
-- ENHANCED CASE RESULT (uses same spin animation)
-------------------------------------------------

local EnhancedCaseResult = RemoteEvents:WaitForChild("EnhancedCaseResult")
EnhancedCaseResult.OnClientEvent:Connect(function(data)
	if data.success then
		StoreController.Close()
		closeAllModals("EnhancedCase")

		SpinController._startSpin({
			success = true,
			streamerId = data.streamerId,
			displayName = data.displayName,
			rarity = data.rarity,
			effect = data.effect,
		})
	end
end)

-------------------------------------------------
-- CLOSE OTHER MODALS WHEN STANDS OPEN
-------------------------------------------------

RemoteEvents:WaitForChild("OpenSpinStandGui").OnClientEvent:Connect(function()
	closeAllModals("SpinStand")
end)
RemoteEvents:WaitForChild("OpenSellStandGui").OnClientEvent:Connect(function()
	if TutorialController.IsActive() then return end
	closeAllModals("Sell")
end)
RemoteEvents:WaitForChild("OpenUpgradeStandGui").OnClientEvent:Connect(function()
	if TutorialController.IsActive() then return end
	closeAllModals("Upgrade")
end)
RemoteEvents:WaitForChild("OpenPotionStandGui").OnClientEvent:Connect(function()
	if TutorialController.IsActive() then return end
	closeAllModals("Potion")
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

-------------------------------------------------
-- AUTO-CLOSE STALL UIs WHEN PLAYER WALKS AWAY
-------------------------------------------------

local STALL_CLOSE_DISTANCE = 40

local stallUIMap = {
	{ stallName = "Stall_Spin",      isOpen = function() return SpinStandController.IsOpen() end, close = function() SpinStandController.Close(); SpinController.Hide() end },
	{ stallName = "Stall_Sell",      isOpen = function() return SellStandController.IsOpen() end, close = function() SellStandController.Close() end },
	{ stallName = "Stall_Upgrades",  isOpen = function() return UpgradeStandController.IsOpen() end, close = function() UpgradeStandController.Close() end },
	{ stallName = "Stall_Potions",   isOpen = function() return PotionController.IsShopOpen() end, close = function() PotionController.CloseShop() end },
	{ stallName = "Stall_Gems",      isOpen = function() return GemShopController.IsOpen() end, close = function() GemShopController.Close() end },
	{ stallName = "Stall_Sacrifice", isOpen = function() return SacrificeController.IsOpen() end, close = function() SacrificeController.Close() end },
}

local distCheckTimer = 0
RunService.Heartbeat:Connect(function(dt)
	distCheckTimer = distCheckTimer + dt
	if distCheckTimer < 0.5 then return end
	distCheckTimer = 0

	local character = Players.LocalPlayer.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local playerPos = rootPart.Position

	local hub = workspace:FindFirstChild("Hub")
	if not hub then return end

	for _, entry in ipairs(stallUIMap) do
		if entry.isOpen() then
			local stall = hub:FindFirstChild(entry.stallName)
			if stall then
				local stallPos
				if stall:IsA("Model") then
					local cf = stall:GetBoundingBox()
					stallPos = cf.Position
				elseif stall:IsA("BasePart") then
					stallPos = stall.Position
				end
				if stallPos and (playerPos - stallPos).Magnitude > STALL_CLOSE_DISTANCE then
					entry.close()
				end
			end
		end
	end
end)

print("[Client] Spin the Streamer initialized!")
