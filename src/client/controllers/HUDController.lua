--[[
	HUDController.lua
	Heads-up display showing: cash, rebirth count, spin credits.
	Updates in real time when PlayerDataUpdate fires from server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)

local HUDController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Cached references
local cashLabel
local rebirthLabel
local spinCreditsLabel

-- Local data mirror
HUDController.Data = {
	cash = 0,
	rebirthCount = 0,
	spinCredits = 0,
	collection = {},
	equippedStreamers = {},
	totalSlots = 1,
	premiumSlotUnlocked = false,
	doubleCash = false,
}

local onDataUpdated = {} -- callback list

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function HUDController.Init()
	local screenGui = UIHelper.CreateScreenGui("HUDGui", 3)
	screenGui.Parent = playerGui

	-- Top-left currency display
	local hudContainer = UIHelper.CreateRoundedFrame({
		Name = "HUDContainer",
		Size = UDim2.new(0, 220, 0, 90),
		Position = UDim2.new(0, 12, 0, 70),
		AnchorPoint = Vector2.new(0, 0),
		Color = DesignConfig.Colors.NavBackground,
		CornerRadius = DesignConfig.Layout.PanelCorner,
		StrokeColor = Color3.fromRGB(60, 60, 90),
		Parent = screenGui,
	})

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = hudContainer

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = hudContainer

	-- Cash
	cashLabel = UIHelper.CreateLabel({
		Name = "CashLabel",
		Size = UDim2.new(1, 0, 0, 24),
		Text = "$ 500",
		TextColor = DesignConfig.Colors.Accent,
		Font = DesignConfig.Fonts.Primary,
		TextSize = DesignConfig.FontSizes.Header,
		Parent = hudContainer,
	})
	cashLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Rebirth
	rebirthLabel = UIHelper.CreateLabel({
		Name = "RebirthLabel",
		Size = UDim2.new(1, 0, 0, 20),
		Text = "Rebirth: 0",
		TextColor = Color3.fromRGB(255, 200, 60),
		Font = DesignConfig.Fonts.Secondary,
		TextSize = DesignConfig.FontSizes.Caption,
		Parent = hudContainer,
	})
	rebirthLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Spin credits
	spinCreditsLabel = UIHelper.CreateLabel({
		Name = "SpinCreditsLabel",
		Size = UDim2.new(1, 0, 0, 20),
		Text = "Spins: 0",
		TextColor = Color3.fromRGB(200, 120, 255),
		Font = DesignConfig.Fonts.Secondary,
		TextSize = DesignConfig.FontSizes.Caption,
		Parent = hudContainer,
	})
	spinCreditsLabel.TextXAlignment = Enum.TextXAlignment.Left

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
	for key, value in pairs(payload) do
		HUDController.Data[key] = value
	end

	-- Animate cash change
	if cashLabel then
		cashLabel.Text = "$ " .. tostring(HUDController.Data.cash)
		-- Quick flash on change
		local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
		TweenService:Create(cashLabel, tweenInfo, {
			TextSize = DesignConfig.FontSizes.Header + 4,
		}):Play()
		task.delay(0.15, function()
			TweenService:Create(cashLabel, tweenInfo, {
				TextSize = DesignConfig.FontSizes.Header,
			}):Play()
		end)
	end

	if rebirthLabel then
		rebirthLabel.Text = "Rebirth: " .. tostring(HUDController.Data.rebirthCount)
	end

	if spinCreditsLabel then
		spinCreditsLabel.Text = "Spins: " .. tostring(HUDController.Data.spinCredits)
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
