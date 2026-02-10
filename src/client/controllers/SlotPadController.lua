--[[
	SlotPadController.lua
	Manages interaction with the player's base pads.
	Handles click-to-equip from inventory and click-to-unequip.
	Pads are built by the server (BaseService) — this controller
	just finds them and wires up click detection.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local SlotsConfig = require(ReplicatedStorage.Shared.Config.SlotsConfig)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local EquipRequest = RemoteEvents:WaitForChild("EquipRequest")
local UnequipRequest = RemoteEvents:WaitForChild("UnequipRequest")

local SlotPadController = {}

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- References
local basePosition = nil
local pads = {}          -- padIndex -> Part
local playerData = nil   -- cached from HUDController updates

-- Dependency: InventoryController (set during init)
local InventoryController

-------------------------------------------------
-- FIND PADS
-------------------------------------------------

local function findPads()
	local basesFolder = Workspace:WaitForChild("PlayerBases", 15)
	if not basesFolder then
		warn("[SlotPadController] PlayerBases folder not found!")
		return
	end

	local baseName = "Base_" .. player.UserId
	local baseModel = basesFolder:WaitForChild(baseName, 15)
	if not baseModel then
		warn("[SlotPadController] Base not found for player: " .. player.Name)
		return
	end

	local padsFolder = baseModel:WaitForChild("Pads", 10)
	if not padsFolder then
		warn("[SlotPadController] Pads folder not found in base!")
		return
	end

	for _, pad in ipairs(padsFolder:GetChildren()) do
		if pad:IsA("BasePart") and pad.Name:match("^Pad_") then
			local indexStr = pad.Name:match("Pad_(%d+)")
			local index = tonumber(indexStr)
			if index then
				pads[index] = pad
			end
		end
	end

	print("[SlotPadController] Found " .. tostring(#pads) .. " pads in base")
end

-------------------------------------------------
-- PAD CLICK DETECTION
-------------------------------------------------

local function setupClickDetection()
	mouse.Button1Down:Connect(function()
		local target = mouse.Target
		if not target then return end

		-- Check if clicked on a pad (or pad's child)
		local padPart = nil
		local padIndex = nil

		-- Direct pad click
		if target.Name:match("^Pad_") then
			padPart = target
		elseif target.Parent and target.Parent.Name:match("^Pad_") then
			padPart = target.Parent
		end

		if not padPart then return end

		local indexStr = padPart.Name:match("Pad_(%d+)")
		padIndex = tonumber(indexStr)
		if not padIndex then return end

		-- Verify this pad belongs to our base
		local isOurPad = false
		for idx, p in pairs(pads) do
			if p == padPart and idx == padIndex then
				isOurPad = true
				break
			end
		end
		if not isOurPad then return end

		-- Check if pad is unlocked
		if not playerData then return end
		local totalSlots = playerData.totalSlots or 1
		if padIndex > totalSlots then
			print("[SlotPadController] Pad " .. padIndex .. " is locked!")
			return
		end

		-- Check if we have something selected in inventory
		if InventoryController then
			local selIdx, selStreamerId = InventoryController.GetSelectedItem()
			if selStreamerId then
				-- Equip selected item to this pad
				EquipRequest:FireServer(selStreamerId, padIndex)
				InventoryController.ClearSelection()
				return
			end
		end

		-- If no item selected and pad has something, unequip it
		local equipped = playerData.equippedPads or {}
		if equipped[tostring(padIndex)] then
			UnequipRequest:FireServer(padIndex)
		end
	end)
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function SlotPadController.Init(inventoryCtrl)
	InventoryController = inventoryCtrl

	-- Wait for base to be built, then find pads
	task.spawn(function()
		task.wait(3) -- give BaseService time to build
		findPads()
		setupClickDetection()
	end)
end

function SlotPadController.SetBasePosition(pos)
	basePosition = pos
end

function SlotPadController.Refresh(data)
	playerData = data
	-- Pad visuals are updated server-side by BaseService
	-- We just cache the data for click logic
end

return SlotPadController
