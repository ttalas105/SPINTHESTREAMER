--[[
	HUDController.lua
	Bottom-left currency display showing: cash, rebirth count, spin credits.
	Matches reference: hearts (rebirth) + cash in bottom-left corner.
	Updates in real time when PlayerDataUpdate fires from server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)

local HUDController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Cached references
local cashLabel

-- Local data mirror
HUDController.Data = {
	cash = 0,
	inventory = {},
	equippedPads = {},
	collection = {},
	rebirthCount = 0,
	totalSlots = 1,
	premiumSlotUnlocked = false,
	doubleCash = false,
	spinCredits = 0,
}

local onDataUpdated = {}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function HUDController.Init()
	-- Hide default Roblox health bar; we show our own HUD instead.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	local screenGui = UIHelper.CreateScreenGui("HUDGui", 3)
	screenGui.Parent = playerGui

	-- Bottom-left currency display (cash only)
	local hudContainer = Instance.new("Frame")
	hudContainer.Name = "HUDContainer"
	hudContainer.Size = UDim2.new(0, 160, 0, 32)
	hudContainer.Position = UDim2.new(0, 12, 1, -12)
	hudContainer.AnchorPoint = Vector2.new(0, 1)
	hudContainer.BackgroundTransparency = 1
	hudContainer.BorderSizePixel = 0
	hudContainer.Parent = screenGui

	-- Cash
	cashLabel = Instance.new("TextLabel")
	cashLabel.Name = "CashLabel"
	cashLabel.Size = UDim2.new(1, 0, 0, 26)
	cashLabel.BackgroundTransparency = 1
	cashLabel.TextColor3 = DesignConfig.Colors.Accent
	cashLabel.Font = DesignConfig.Fonts.Primary
	cashLabel.TextSize = DesignConfig.FontSizes.Header
	cashLabel.Text = "$100"
	cashLabel.TextXAlignment = Enum.TextXAlignment.Left
	cashLabel.Parent = hudContainer

	-- Listen for data updates from server
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local PlayerDataUpdate = RemoteEvents:WaitForChild("PlayerDataUpdate")

	PlayerDataUpdate.OnClientEvent:Connect(function(payload)
		HUDController.UpdateData(payload)
	end)
end

-------------------------------------------------
-- DATA UPDATE
-------------------------------------------------

function HUDController.UpdateData(payload)
	local previousCash = HUDController.Data.cash

	for key, value in pairs(payload) do
		HUDController.Data[key] = value
	end

	-- Update cash display
	if cashLabel then
		cashLabel.Text = "$" .. tostring(HUDController.Data.cash)

		-- Flash on change
		if HUDController.Data.cash ~= previousCash then
			local flashColor = HUDController.Data.cash > previousCash
				and Color3.fromRGB(100, 255, 100)
				or Color3.fromRGB(255, 100, 100)
			cashLabel.TextColor3 = flashColor
			task.delay(0.2, function()
				TweenService:Create(cashLabel, TweenInfo.new(0.3), {
					TextColor3 = DesignConfig.Colors.Accent,
				}):Play()
			end)
		end
	end

	-- Fire data update callbacks
	for _, callback in ipairs(onDataUpdated) do
		task.spawn(callback, HUDController.Data)
	end
end

function HUDController.OnDataUpdated(callback)
	table.insert(onDataUpdated, callback)
end

return HUDController
