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
local SlotPadController      = require(controllers.SlotPadController)
local InventoryController    = require(controllers.InventoryController)
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
InventoryController.Init()
SlotPadController.Init(InventoryController)

-------------------------------------------------
-- BASE READY
-------------------------------------------------

local BaseReady = RemoteEvents:WaitForChild("BaseReady")
BaseReady.OnClientEvent:Connect(function(data)
	if data.position then
		SlotPadController.SetBasePosition(data.position)
		print("[Client] Base assigned at position: " .. tostring(data.position))
	end
end)

-------------------------------------------------
-- WIRE TOP NAV TABS (SHOPS / BASE / SELL)
-------------------------------------------------

-- Default: show nothing special (player walks around)
TopNavController.OnTabChanged(function(tabName)
	-- Hide spin wheel when switching tabs
	SpinController.Hide()
	if StoreController.IsOpen() then
		StoreController.Close()
	end

	if tabName == "SHOPS" then
		SpinController.Show()
	elseif tabName == "BASE" then
		-- BASE tab: player focuses on their base pads
		-- (just hides other UIs, pads are always visible in world)
	elseif tabName == "SELL" then
		-- SELL tab: sell from inventory
		-- For now, the sell button sells the selected inventory item
		local selIdx, selId = InventoryController.GetSelectedItem()
		if selId then
			InventoryController.SellSelected()
		end
	end
end)

-------------------------------------------------
-- WIRE LEFT SIDE NAV
-------------------------------------------------

LeftSideNavController.OnClick("Store", function()
	if StoreController.IsOpen() then
		StoreController.Close()
	else
		StoreController.Open()
	end
end)

LeftSideNavController.OnClick("Rebirth", function()
	local RebirthRequest = RemoteEvents:WaitForChild("RebirthRequest")
	RebirthRequest:FireServer()
end)

LeftSideNavController.OnClick("Pets", function()
	print("[Client] Pets not yet implemented")
end)

LeftSideNavController.OnClick("Index", function()
	print("[Client] Index/Collection not yet implemented")
end)

LeftSideNavController.OnClick("Settings", function()
	print("[Client] Settings not yet implemented")
end)

-------------------------------------------------
-- WIRE RIGHT SIDE NAV
-------------------------------------------------

RightSideNavController.OnClick("Invite", function()
	print("[Client] Invite not yet implemented")
end)
RightSideNavController.OnClick("Daily", function()
	print("[Client] Daily rewards not yet implemented")
end)
RightSideNavController.OnClick("Playtime", function()
	print("[Client] Playtime rewards not yet implemented")
end)

-------------------------------------------------
-- DATA UPDATES -> INVENTORY + PADS
-------------------------------------------------

HUDController.OnDataUpdated(function(data)
	-- Update inventory bar
	InventoryController.UpdateInventory(data.inventory)
	-- Update pad controller cache
	SlotPadController.Refresh(data)
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

-------------------------------------------------
-- REBIRTH RESULT
-------------------------------------------------

local RebirthResult = RemoteEvents:WaitForChild("RebirthResult")
RebirthResult.OnClientEvent:Connect(function(data)
	if data.success then
		print("[Client] Rebirth! Now at: " .. data.newRebirthCount)
	else
		print("[Client] Rebirth failed: " .. (data.reason or "unknown"))
	end
end)

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
