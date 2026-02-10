--[[
	RightSideNavController.lua
	Right vertical icon menu with real image icons:
	INVITE, DAILY, PLAYTIME
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
-- BUTTON DEFINITIONS with real Roblox asset icons
-------------------------------------------------

local menuItems = {
	{ name = "Invite",   imageId = "rbxassetid://11385395257",  color = Color3.fromRGB(255, 165, 40), label = "Invite" },
	{ name = "Daily",    imageId = "rbxassetid://13569499711",   color = Color3.fromRGB(100, 160, 255), label = "Daily" },
	{ name = "Playtime", imageId = "rbxassetid://15254183851",   color = Color3.fromRGB(220, 60, 60),  label = "Playtime" },
}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function RightSideNavController.Init()
	local screenGui = UIHelper.CreateScreenGui("RightSideNavGui", 4)
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Name = "RightSideContainer"
	container.Size = UDim2.new(0, 70, 0, (#menuItems * 72) + ((#menuItems - 1) * 4))
	container.Position = UDim2.new(1, -8, 0.5, 0)
	container.AnchorPoint = Vector2.new(1, 0.5)
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

function RightSideNavController.OnClick(buttonName: string, callback)
	onButtonClicked[buttonName] = callback
end

return RightSideNavController
