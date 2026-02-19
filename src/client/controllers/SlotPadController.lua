--[[
	SlotPadController.lua
	Manages interaction with the player's base display pads.
	Uses ProximityPrompts (press E) to place/remove streamers.
	Pads are built by the server (BaseService) — this controller
	finds them and wires up the ProximityPrompt interaction.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local DisplayInteract = RemoteEvents:WaitForChild("DisplayInteract")
local CollectKeysResult = RemoteEvents:WaitForChild("CollectKeysResult")

local SlotPadController = {}

local player = Players.LocalPlayer
local pads = {}
local basePosition = nil
local playerData = nil

local HoldController
local InventoryController

-------------------------------------------------
-- FIND PADS & WIRE PROMPTS
-------------------------------------------------

local function findPadsAndConnect()
	local basesFolder = Workspace:WaitForChild("PlayerBaseData", 15)
	if not basesFolder then
		warn("[SlotPadController] PlayerBaseData folder not found!")
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

				local prompt = pad:FindFirstChild("DisplayPrompt")
				if prompt and prompt:IsA("ProximityPrompt") then
					prompt.Triggered:Connect(function()
						local streamerId, effect = nil, nil
						if HoldController and HoldController.IsHolding() then
							streamerId, effect = HoldController.GetHeld()
						end

						DisplayInteract:FireServer(index, streamerId, effect)
					end)
				end
			end
		end
	end

	print("[SlotPadController] Found " .. tostring(#pads) .. " pads, prompts wired")
end

-------------------------------------------------
-- COLLECT KEYS FEEDBACK
-------------------------------------------------

local function setupCollectFeedback()
	CollectKeysResult.OnClientEvent:Connect(function(data)
		if data.success and data.amount and data.amount > 0 then
			print("[SlotPadController] Collected $" .. tostring(data.amount) .. " from display " .. tostring(data.padSlot or "?"))
		end
	end)
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function SlotPadController.Init(holdCtrl, inventoryCtrl)
	HoldController = holdCtrl
	InventoryController = inventoryCtrl

	setupCollectFeedback()

	task.spawn(function()
		task.wait(3)
		findPadsAndConnect()
	end)
end

function SlotPadController.SetBasePosition(pos)
	basePosition = pos
end

function SlotPadController.Refresh(data)
	playerData = data
end

return SlotPadController
