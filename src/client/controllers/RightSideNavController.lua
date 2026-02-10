--[[
	RightSideNavController.lua
	Vertical icon menu on the right side of the screen:
	Friends, Rewards, Quests, Settings.
	Rounded-square icons, cartoony style.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)

local RightSideNavController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local buttons = {}
local onButtonClicked = {}

-------------------------------------------------
-- BUTTON DEFINITIONS
-------------------------------------------------

local menuItems = {
	{ name = "Friends",  icon = "F",  color = Color3.fromRGB(80, 180, 255) },
	{ name = "Rewards",  icon = "!",  color = Color3.fromRGB(255, 200, 50) },
	{ name = "Quests",   icon = "Q",  color = Color3.fromRGB(80, 220, 140) },
	{ name = "Settings", icon = "G",  color = Color3.fromRGB(140, 140, 170) },
}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function RightSideNavController.Init()
	local screenGui = UIHelper.CreateScreenGui("RightSideNavGui", 4)
	screenGui.Parent = playerGui

	-- Container
	local container = Instance.new("Frame")
	container.Name = "RightSideContainer"
	container.Size = UDim2.new(0, 70, 0, (#menuItems * 70) + ((#menuItems - 1) * 8))
	container.Position = UDim2.new(1, -10, 0.5, 0)
	container.AnchorPoint = Vector2.new(1, 0.5)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = container

	for _, item in ipairs(menuItems) do
		local iconBtn, clickZone = UIHelper.CreateIconButton({
			Name = item.name,
			Size = UDim2.new(0, 64, 0, 64),
			Color = item.color,
			HoverColor = Color3.new(
				math.min(item.color.R + 0.15, 1),
				math.min(item.color.G + 0.15, 1),
				math.min(item.color.B + 0.15, 1)
			),
			Icon = item.icon,
			Label = item.name,
			CornerRadius = DesignConfig.Layout.ButtonCorner,
			Parent = container,
		})

		buttons[item.name] = iconBtn

		clickZone.MouseButton1Click:Connect(function()
			if onButtonClicked[item.name] then
				onButtonClicked[item.name]()
			end
		end)
	end
end

-------------------------------------------------
-- PUBLIC API
-------------------------------------------------

function RightSideNavController.OnClick(buttonName: string, callback)
	onButtonClicked[buttonName] = callback
end

return RightSideNavController
