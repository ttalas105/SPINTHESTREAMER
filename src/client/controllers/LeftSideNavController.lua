--[[
	LeftSideNavController.lua
	Vertical icon menu on the left side of the screen:
	Store, Rebirth, Streamers, Index/Collection.
	Square buttons with bright icons and labels.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)

local LeftSideNavController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local buttons = {}
local onButtonClicked = {} -- { [buttonName] = callback }

-------------------------------------------------
-- BUTTON DEFINITIONS
-------------------------------------------------

local menuItems = {
	{ name = "Store",      icon = "$",  color = Color3.fromRGB(50, 200, 80)  },
	{ name = "Rebirth",    icon = "R",  color = Color3.fromRGB(255, 180, 40) },
	{ name = "Streamers",  icon = "S",  color = Color3.fromRGB(100, 140, 255) },
	{ name = "Collection", icon = "C",  color = Color3.fromRGB(200, 80, 255) },
}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function LeftSideNavController.Init()
	local screenGui = UIHelper.CreateScreenGui("LeftSideNavGui", 4)
	screenGui.Parent = playerGui

	-- Container
	local container = Instance.new("Frame")
	container.Name = "LeftSideContainer"
	container.Size = UDim2.new(0, 70, 0, (#menuItems * 70) + ((#menuItems - 1) * 8))
	container.Position = UDim2.new(0, 10, 0.5, 0)
	container.AnchorPoint = Vector2.new(0, 0.5)
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

function LeftSideNavController.OnClick(buttonName: string, callback)
	onButtonClicked[buttonName] = callback
end

function LeftSideNavController.SetBadge(buttonName: string, count: number)
	local btn = buttons[buttonName]
	if not btn then return end
	local badge = btn:FindFirstChild("Badge")
	if badge then
		badge.Visible = count > 0
		local countLabel = badge:FindFirstChild("Count")
		if countLabel then
			countLabel.Text = tostring(count)
		end
	end
end

return LeftSideNavController
