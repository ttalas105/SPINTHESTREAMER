--[[
	TopNavController.lua
	Top-center navigation bar: BASE and SHOP teleport buttons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)
local UISounds = require(script.Parent.UISounds)

local TopNavController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeTab = "BASE" -- default tab
local tabButtons = {}
local onTabChanged = {}

-------------------------------------------------
-- TAB DEFINITIONS — BASE / SHOP teleport only
-------------------------------------------------

local tabs = {
	{ name = "BASE",  color = Color3.fromRGB(120, 210, 120) },  -- green
	{ name = "SHOP",  color = Color3.fromRGB(255, 180, 60) },   -- warm orange
}

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function TopNavController.Init()
	local screenGui = UIHelper.CreateScreenGui("TopNavGui", 5)
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Name = "TopNavContainer"
	container.Size = UDim2.new(0, 460, 0, 72)
	container.Position = UDim2.new(0.5, 0, 0, 8)
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local camera = workspace.CurrentCamera
	local function fitTopNav()
		local uiScale = UIHelper.GetScale()
		if uiScale <= 0 then uiScale = 1 end
		local availW = (camera.ViewportSize.X / uiScale) * 0.5
		local naturalW = 460
		if naturalW > availW and availW > 0 then
			container.Size = UDim2.new(0, math.floor(availW), 0, 72)
		else
			container.Size = UDim2.new(0, naturalW, 0, 72)
		end
	end
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitTopNav)
		fitTopNav()
	end

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 14)
	listLayout.Parent = container

	for _, tabInfo in ipairs(tabs) do
		local isActive = tabInfo.name == activeTab

		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. tabInfo.name
		btn.Size = UDim2.new(0, 210, 0, 62)
		btn.BackgroundColor3 = tabInfo.color
		btn.BorderSizePixel = 0
		btn.Text = tabInfo.name
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.FredokaOne
		btn.TextSize = 34
		btn.AutoButtonColor = false
		btn.Parent = container

		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 26)

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = Color3.fromRGB(255, 255, 255)
		btnStroke.Thickness = isActive and 1.5 or 0.5
		btnStroke.Transparency = 0.7
		btnStroke.Parent = btn

		local textStroke = Instance.new("UIStroke")
		textStroke.Color = Color3.fromRGB(30, 30, 30)
		textStroke.Thickness = 2
		textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		textStroke.Parent = btn

		local bounceTween = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local idleSize = btn.Size
		local hoverSize = UDim2.new(0, 220, 0, 66)
		local hoverColor = Color3.new(
			math.min(tabInfo.color.R + 0.1, 1),
			math.min(tabInfo.color.G + 0.1, 1),
			math.min(tabInfo.color.B + 0.1, 1)
		)

		btn.MouseEnter:Connect(function()
			UISounds.PlayHover()
			TweenService:Create(btn, bounceTween, { Size = hoverSize, BackgroundColor3 = hoverColor }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, bounceTween, { Size = idleSize, BackgroundColor3 = tabInfo.color }):Play()
		end)

		tabButtons[tabInfo.name] = {
			button = btn,
			color = tabInfo.color,
		}

		btn.MouseButton1Click:Connect(function()
			UISounds.PlayClick()
			TopNavController.SetActiveTab(tabInfo.name)
		end)
	end
end

-------------------------------------------------
-- TAB STATE
-------------------------------------------------

function TopNavController.SetActiveTab(tabName: string)
	local ok, TutorialController = pcall(require, script.Parent.TutorialController)
	if ok and TutorialController.IsActive() then
		if tabName == "SHOP" then
			TutorialController.OnBlockedMainInput()
			return
		end
		local STATES = TutorialController.STATES
		if STATES and tabName == "BASE" and TutorialController.GetState() ~= STATES.GO_TO_BASE then
			TutorialController.OnBlockedMainInput()
			return
		end
	end

	activeTab = tabName
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

	for name, data in pairs(tabButtons) do
		local isActive = name == tabName
		for _, child in ipairs(data.button:GetChildren()) do
			if child:IsA("UIStroke") and child.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
				TweenService:Create(child, tweenInfo, {
					Thickness = isActive and 1.5 or 0.5,
					Transparency = isActive and 0.55 or 0.7,
				}):Play()
			end
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
