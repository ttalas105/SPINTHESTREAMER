--[[
	RightSideNavController.lua
	Right vertical icon menu — bubbly, kid-friendly:
	REBIRTH, SETTINGS
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
-- Bubbly kid-friendly button style (match left nav)
-------------------------------------------------
local BUTTON_SIZE = 74
local BUTTON_PADDING = 14
local BUBBLE_CORNER = 22
local STROKE_THICKNESS = 3
local STROKE_COLOR = Color3.fromRGB(30, 25, 50)

-------------------------------------------------
-- RIGHT: Rebirth, Settings (cartoon emoji icons for kids)
-------------------------------------------------

local menuItems = {
	{ name = "Rebirth",  icon = "✨", imageId = "", color = Color3.fromRGB(255, 100, 140),  label = "Rebirth"  }, -- Replace imageId with rbxassetid://YOUR_ICON_ID
	{ name = "Settings", icon = "⚙️", imageId = "rbxassetid://136970465147454", color = Color3.fromRGB(100, 160, 220),  label = "Settings" },
}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function RightSideNavController.Init()
	local screenGui = UIHelper.CreateScreenGui("RightSideNavGui", 4)
	screenGui.Parent = playerGui

	local totalHeight = (#menuItems * BUTTON_SIZE) + ((#menuItems - 1) * BUTTON_PADDING)
	local container = Instance.new("Frame")
	container.Name = "RightSideContainer"
	container.Size = UDim2.new(0, BUTTON_SIZE + 12, 0, totalHeight)
	container.Position = UDim2.new(1, -12, 0.5, 0)
	container.AnchorPoint = Vector2.new(1, 0.5)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Padding = UDim.new(0, BUTTON_PADDING)
	listLayout.Parent = container

	for _, item in ipairs(menuItems) do
		local iconBtn, clickZone = UIHelper.CreateIconButton({
			Name = item.name,
			Size = UDim2.new(0, BUTTON_SIZE, 0, BUTTON_SIZE),
			Color = item.color,
			HoverColor = Color3.new(
				math.min(item.color.R + 0.12, 1),
				math.min(item.color.G + 0.12, 1),
				math.min(item.color.B + 0.12, 1)
			),
			Icon = item.icon,
			ImageId = (item.imageId ~= "") and item.imageId or nil,
			IconFont = Enum.Font.Cartoon,
			LabelFont = Enum.Font.Cartoon,
			Label = item.label,
			CornerRadius = UDim.new(0, BUBBLE_CORNER),
			Parent = container,
		})

		local stroke = Instance.new("UIStroke")
		stroke.Color = STROKE_COLOR
		stroke.Thickness = STROKE_THICKNESS
		stroke.Transparency = 0.15
		stroke.Parent = iconBtn

		UIHelper.CreateShadow(iconBtn)

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
