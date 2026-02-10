--[[
	LeftSideNavController.lua
	Left vertical icon menu with real image icons:
	STORE, REBIRTH, PETS, INDEX, SETTINGS
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
-- BUTTON DEFINITIONS with real Roblox asset icons
-------------------------------------------------

local menuItems = {
	{ name = "Store",    imageId = "rbxassetid://11385419687", color = Color3.fromRGB(220, 50, 70),  label = "Store" },
	{ name = "Rebirth",  imageId = "rbxassetid://8729314720",  color = Color3.fromRGB(220, 50, 70),  label = "Rebirth" },
	{ name = "Pets",     imageId = "rbxassetid://13001190578",  color = Color3.fromRGB(255, 165, 40), label = "Pets" },
	{ name = "Index",    imageId = "rbxassetid://6867518950",   color = Color3.fromRGB(220, 50, 70),  label = "Index" },
	{ name = "Settings", imageId = "rbxassetid://7059346386",   color = Color3.fromRGB(100, 130, 180), label = "Settings" },
}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function LeftSideNavController.Init()
	local screenGui = UIHelper.CreateScreenGui("LeftSideNavGui", 4)
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Name = "LeftSideContainer"
	container.Size = UDim2.new(0, 70, 0, (#menuItems * 72) + ((#menuItems - 1) * 4))
	container.Position = UDim2.new(0, 8, 0.5, 0)
	container.AnchorPoint = Vector2.new(0, 0.5)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = container

	for _, item in ipairs(menuItems) do
		local iconBtn, clickZone = UIHelper.CreateIconButton({
			Name = item.name,
			Size = UDim2.new(0, 66, 0, 66),
			Color = item.color,
			HoverColor = Color3.new(
				math.min(item.color.R + 0.15, 1),
				math.min(item.color.G + 0.15, 1),
				math.min(item.color.B + 0.15, 1)
			),
			ImageId = item.imageId,
			Label = item.label,
			CornerRadius = UDim.new(0, 10),
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
