--[[
	LeftSideNavController.lua
	Left vertical icon menu — bubbly, kid-friendly:
	INDEX, PETS, STORE
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)
local UISounds = require(script.Parent.UISounds)

local LeftSideNavController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local buttons = {}
local onButtonClicked = {}

-------------------------------------------------
-- Nav button style
-------------------------------------------------
local BUTTON_W = 120
local BUTTON_H = 130
local BUTTON_PADDING = 30
local BUBBLE_CORNER = 22
local STROKE_THICKNESS = 1.5
local STROKE_COLOR = Color3.fromRGB(30, 25, 50)

local menuItems = {
	{ name = "Index",   icon = "\u{1F4D6}", imageId = "rbxassetid://113805125234370", color = Color3.fromRGB(100, 200, 255),  label = "Index"   },
	{ name = "Storage", icon = "\u{1F4E6}", imageId = "rbxassetid://86182968978837", color = Color3.fromRGB(255, 165, 50), label = "Storage" },
	{ name = "Store",   icon = "\u{1F6D2}", imageId = "rbxassetid://114090124339958", color = Color3.fromRGB(255, 90, 120),   label = "Store", bgColor = Color3.fromRGB(120, 210, 130) },
}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

local TOP_BAR_RESERVE = 70

local function layoutNav(container, btnFrames, viewportHeight)
	local count = #btnFrames
	local padding = BUTTON_PADDING
	local totalNatural = (count * BUTTON_H) + ((count - 1) * padding)

	local maxH = viewportHeight - TOP_BAR_RESERVE - 20
	local scale = 1
	if totalNatural > maxH and maxH > 0 then
		scale = maxH / totalNatural
	end

	local btnW = math.floor(BUTTON_W * scale)
	local btnH = math.floor(BUTTON_H * scale)
	local scaledPadding = math.floor(padding * scale)
	local totalH = (count * btnH) + ((count - 1) * scaledPadding)

	container.Size = UDim2.new(0, btnW + 12, 0, totalH)

	local centerY = TOP_BAR_RESERVE + (viewportHeight - TOP_BAR_RESERVE) * 0.5
	container.Position = UDim2.new(0, 12, 0, math.floor(centerY))
	container.AnchorPoint = Vector2.new(0, 0.5)

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("UIListLayout") then
			child.Padding = UDim.new(0, scaledPadding)
		end
	end

	for _, frame in ipairs(btnFrames) do
		frame.Size = UDim2.new(0, btnW, 0, btnH)
	end
end

function LeftSideNavController.Init()
	local screenGui = UIHelper.CreateScreenGui("LeftSideNavGui", 4)
	screenGui.Parent = playerGui

	local totalHeight = (#menuItems * BUTTON_H) + ((#menuItems - 1) * BUTTON_PADDING)
	local container = Instance.new("Frame")
	container.Name = "LeftSideContainer"
	container.Size = UDim2.new(0, BUTTON_W + 12, 0, totalHeight)
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

	local btnFrames = {}

	for _, item in ipairs(menuItems) do
		local hasImage = item.imageId ~= ""
		local iconBtn, clickZone = UIHelper.CreateIconButton({
			Name = item.name,
			Size = UDim2.new(0, BUTTON_W, 0, BUTTON_H),
			Color = item.color,
			HoverColor = Color3.new(
				math.min(item.color.R + 0.12, 1),
				math.min(item.color.G + 0.12, 1),
				math.min(item.color.B + 0.12, 1)
			),
			Icon = item.icon,
			ImageId = hasImage and item.imageId or nil,
			BgColor = item.bgColor,
			IconFont = Enum.Font.FredokaOne,
			LabelFont = Enum.Font.FredokaOne,
			Label = item.label,
			CornerRadius = UDim.new(0, BUBBLE_CORNER),
			Parent = container,
		})

		buttons[item.name] = iconBtn
		table.insert(btnFrames, iconBtn)

		clickZone.MouseEnter:Connect(function()
			UISounds.PlayHover()
		end)
		clickZone.MouseButton1Click:Connect(function()
			UISounds.PlayClick()
			if onButtonClicked[item.name] then
				onButtonClicked[item.name]()
			end
		end)
	end

	local camera = workspace.CurrentCamera
	local function onViewportChanged()
		layoutNav(container, btnFrames, camera.ViewportSize.Y)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
	onViewportChanged()
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
