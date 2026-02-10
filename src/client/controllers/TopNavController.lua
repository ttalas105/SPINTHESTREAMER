--[[
	TopNavController.lua
	Top-center navigation bar: SHOPS, BASE, SELL
	Matches the reference layout with colored tab buttons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)

local TopNavController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeTab = "BASE" -- default tab
local tabButtons = {}
local onTabChanged = {}

-------------------------------------------------
-- TAB DEFINITIONS (matches reference image)
-------------------------------------------------

local tabs = {
	{ name = "SHOPS",  color = Color3.fromRGB(60, 140, 255) },  -- blue
	{ name = "BASE",   color = Color3.fromRGB(255, 165, 40)  },  -- orange
	{ name = "SELL",   color = Color3.fromRGB(220, 200, 40)  },  -- yellow
}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function TopNavController.Init()
	local screenGui = UIHelper.CreateScreenGui("TopNavGui", 5)
	screenGui.Parent = playerGui

	-- Container
	local container = Instance.new("Frame")
	container.Name = "TopNavContainer"
	container.Size = UDim2.new(0.42, 0, 0, 48)
	container.Position = UDim2.new(0.5, 0, 0, 10)
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = screenGui

	-- Layout
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = container

	-- Create tab buttons
	for _, tabInfo in ipairs(tabs) do
		local isActive = tabInfo.name == activeTab

		local btn = UIHelper.CreateButton({
			Name = "Tab_" .. tabInfo.name,
			Size = UDim2.new(0, 130, 0, 44),
			Color = tabInfo.color,
			HoverColor = Color3.new(
				math.min(tabInfo.color.R + 0.1, 1),
				math.min(tabInfo.color.G + 0.1, 1),
				math.min(tabInfo.color.B + 0.1, 1)
			),
			TextColor = DesignConfig.Colors.White,
			Text = tabInfo.name,
			Font = DesignConfig.Fonts.Primary,
			TextSize = DesignConfig.FontSizes.Header,
			CornerRadius = UDim.new(0, 10),
			StrokeColor = Color3.new(
				math.min(tabInfo.color.R + 0.2, 1),
				math.min(tabInfo.color.G + 0.2, 1),
				math.min(tabInfo.color.B + 0.2, 1)
			),
			Parent = container,
		})

		-- Bold stroke on active
		local borderStroke = btn:FindFirstChildOfClass("UIStroke")
		if borderStroke then
			borderStroke.Thickness = isActive and 3 or 1.5
		end

		tabButtons[tabInfo.name] = {
			button = btn,
			color = tabInfo.color,
		}

		btn.MouseButton1Click:Connect(function()
			TopNavController.SetActiveTab(tabInfo.name)
		end)
	end
end

-------------------------------------------------
-- TAB STATE
-------------------------------------------------

function TopNavController.SetActiveTab(tabName: string)
	activeTab = tabName
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

	for name, data in pairs(tabButtons) do
		local isActive = name == tabName
		local stroke = data.button:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, tweenInfo, {
				Thickness = isActive and 3 or 1.5,
			}):Play()
		end
	end

	for _, callback in ipairs(onTabChanged) do
		task.spawn(callback, tabName)
	end
end

function TopNavController.GetActiveTab(): string
	return activeTab
end

function TopNavController.OnTabChanged(callback)
	table.insert(onTabChanged, callback)
end

return TopNavController
