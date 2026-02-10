--[[
	Client Entry Point — Spin the Streamer
	Initializes all controllers, wires up navigation, data updates,
	sell/rebirth handlers, and remote event listeners.
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
local UIHelper               = require(controllers.UIHelper)

-------------------------------------------------
-- INITIALIZE ALL CONTROLLERS
-------------------------------------------------

HUDController.Init()
TopNavController.Init()
LeftSideNavController.Init()
RightSideNavController.Init()
StoreController.Init()
SpinController.Init()
SlotPadController.Init()

-------------------------------------------------
-- WIRE TOP NAV TABS
-------------------------------------------------

SpinController.Show()

TopNavController.OnTabChanged(function(tabName)
	SpinController.Hide()
	if StoreController.IsOpen() then
		StoreController.Close()
	end

	if tabName == "SPIN" then
		SpinController.Show()
	elseif tabName == "SHOPS" then
		StoreController.Open()
	elseif tabName == "PLOT" then
		-- Plot: just hide spin, pads visible in world
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
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local RebirthRequest = RemoteEvents:WaitForChild("RebirthRequest")
	RebirthRequest:FireServer()
end)

LeftSideNavController.OnClick("Streamers", function()
	if SpinController.IsVisible() then
		SpinController.Hide()
	else
		SpinController.Show()
	end
end)

LeftSideNavController.OnClick("Collection", function()
	print("[Client] Collection UI not yet implemented")
end)

-------------------------------------------------
-- WIRE RIGHT SIDE NAV
-------------------------------------------------

RightSideNavController.OnClick("Friends", function()
	print("[Client] Friends not yet implemented")
end)
RightSideNavController.OnClick("Rewards", function()
	print("[Client] Rewards not yet implemented")
end)
RightSideNavController.OnClick("Quests", function()
	print("[Client] Quests not yet implemented")
end)
RightSideNavController.OnClick("Settings", function()
	print("[Client] Settings not yet implemented")
end)

-------------------------------------------------
-- DATA UPDATES -> PAD REFRESH
-------------------------------------------------

HUDController.OnDataUpdated(function(data)
	SlotPadController.Refresh(data)
end)

-------------------------------------------------
-- REBIRTH RESULT
-------------------------------------------------

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
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
