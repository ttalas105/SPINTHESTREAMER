--[[
	LeftSideNavController.lua
	Left vertical icon menu — bubbly, kid-friendly:
	INDEX, PETS, STORE
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)

local LeftSideNavController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local buttons = {}
local onButtonClicked = {}

-------------------------------------------------
-- Bubbly kid-friendly button style
-------------------------------------------------
local BUTTON_SIZE = 74
local BUTTON_PADDING = 14
local BUBBLE_CORNER = 22
local STROKE_THICKNESS = 3
local STROKE_COLOR = Color3.fromRGB(30, 25, 50)

-------------------------------------------------
-- LEFT: Index, Pets, Store (cartoon emoji icons for kids)
-------------------------------------------------

local menuItems = {
	{ name = "Index",  icon = "📖", color = Color3.fromRGB(100, 200, 255),  label = "Index" },
	{ name = "Pets",   icon = "🐾", color = Color3.fromRGB(255, 165, 50),   label = "Pets" },
	{ name = "Store",  icon = "🛒", color = Color3.fromRGB(255, 90, 120),   label = "Store" },
}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function LeftSideNavController.Init()
	local screenGui = UIHelper.CreateScreenGui("LeftSideNavGui", 4)
	screenGui.Parent = playerGui

	local totalHeight = (#menuItems * BUTTON_SIZE) + ((#menuItems - 1) * BUTTON_PADDING)
	local container = Instance.new("Frame")
	container.Name = "LeftSideContainer"
	container.Size = UDim2.new(0, BUTTON_SIZE + 12, 0, totalHeight)
	container.Position = UDim2.new(0, 12, 0.5, 0)
	container.AnchorPoint = Vector2.new(0, 0.5)
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
			IconFont = Enum.Font.Cartoon,
			LabelFont = Enum.Font.Cartoon,
			Label = item.label,
			CornerRadius = UDim.new(0, BUBBLE_CORNER),
			Parent = container,
		})

		-- Bold cartoon outline for bubbly look
		local stroke = Instance.new("UIStroke")
		stroke.Color = STROKE_COLOR
		stroke.Thickness = STROKE_THICKNESS
		stroke.Parent = iconBtn

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
