--[[
	TopNavController.lua
	Top-center navigation bar: SHOPS, PLOT, SPIN
	Rounded buttons with glow, highlight on active tab.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)

local TopNavController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeTab = "SPIN" -- default tab
local tabButtons = {}
local onTabChanged = {} -- callback list

-------------------------------------------------
-- TAB DEFINITIONS
-------------------------------------------------

local tabs = {
	{ name = "SHOPS",   color = Color3.fromRGB(60, 140, 255) },
	{ name = "PLOT",    color = Color3.fromRGB(100, 220, 80) },
	{ name = "SPIN",    color = Color3.fromRGB(200, 60, 255) },
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
	container.Size = UDim2.new(0.5, 0, 0, 50)
	container.Position = UDim2.new(0.5, 0, 0, 12)
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.BackgroundColor3 = DesignConfig.Colors.NavBackground
	container.BackgroundTransparency = 0.2
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = DesignConfig.Layout.PanelCorner
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 120)
	stroke.Thickness = 1.5
	stroke.Parent = container

	-- Layout
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = container

	-- Create tab buttons
	for _, tabInfo in ipairs(tabs) do
		local isActive = tabInfo.name == activeTab
		local btnColor = isActive and tabInfo.color or DesignConfig.Colors.NavInactive

		local btn = UIHelper.CreateButton({
			Name = "Tab_" .. tabInfo.name,
			Size = UDim2.new(0.3, -6, 1, -12),
			Color = btnColor,
			HoverColor = tabInfo.color,
			TextColor = DesignConfig.Colors.White,
			Text = tabInfo.name,
			Font = DesignConfig.Fonts.Primary,
			TextSize = DesignConfig.FontSizes.Body,
			CornerRadius = DesignConfig.Layout.ButtonCorner,
			Parent = container,
		})

		-- Glow stroke on active
		local glowStroke = Instance.new("UIStroke")
		glowStroke.Name = "GlowStroke"
		glowStroke.Color = tabInfo.color
		glowStroke.Thickness = isActive and 2 or 0
		glowStroke.Transparency = isActive and 0.3 or 1
		glowStroke.Parent = btn

		tabButtons[tabInfo.name] = {
			button = btn,
			color = tabInfo.color,
			glowStroke = glowStroke,
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
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad)

	for name, data in pairs(tabButtons) do
		local isActive = name == tabName
		TweenService:Create(data.button, tweenInfo, {
			BackgroundColor3 = isActive and data.color or DesignConfig.Colors.NavInactive,
		}):Play()
		TweenService:Create(data.glowStroke, tweenInfo, {
			Thickness = isActive and 2 or 0,
			Transparency = isActive and 0.3 or 1,
		}):Play()
	end

	-- Fire callbacks
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
