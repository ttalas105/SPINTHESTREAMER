--[[
	StoreController.lua
	Store popup = Game Passes only (VIP, Auto Spin, Luck Boost, 2x Cash).
	Crates/cases live in the Spin shop (TopNav Spin tab).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)

local StoreController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui
local modalFrame
local overlay
local isOpen = false

-------------------------------------------------
-- PASSES SECTION (Game Passes only)
-------------------------------------------------

local function createPassesSection(parent)
	local section = UIHelper.CreateRoundedFrame({
		Name = "PassesSection",
		Size = UDim2.new(1, -20, 0, 180),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = DesignConfig.Colors.BackgroundLight,
		CornerRadius = DesignConfig.Layout.PanelCorner,
		Parent = parent,
	})

	UIHelper.CreateLabel({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 35),
		Position = UDim2.new(0, 10, 0, 5),
		Text = "GAME PASSES",
		TextColor = DesignConfig.Colors.White,
		Font = DesignConfig.Fonts.Accent,
		TextSize = DesignConfig.FontSizes.Header,
		Parent = section,
	}).TextXAlignment = Enum.TextXAlignment.Left

	local passCards = {
		{ name = "VIP",        icon = "V", color = Color3.fromRGB(255, 200, 40), desc = "VIP Access"  },
		{ name = "Auto Spin",  icon = "A", color = Color3.fromRGB(100, 200, 255), desc = "Auto Spin"  },
		{ name = "Luck Boost", icon = "L", color = Color3.fromRGB(80, 255, 120),  desc = "2x Luck"    },
		{ name = "2x Cash",    icon = "$", color = Color3.fromRGB(0, 200, 100),   desc = "Double Cash" },
	}

	local cardsContainer = Instance.new("Frame")
	cardsContainer.Name = "PassCards"
	cardsContainer.Size = UDim2.new(1, -20, 0, 120)
	cardsContainer.Position = UDim2.new(0.5, 0, 0, 45)
	cardsContainer.AnchorPoint = Vector2.new(0.5, 0)
	cardsContainer.BackgroundTransparency = 1
	cardsContainer.Parent = section

	local cardLayout = Instance.new("UIListLayout")
	cardLayout.FillDirection = Enum.FillDirection.Horizontal
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cardLayout.Padding = UDim.new(0, 10)
	cardLayout.Parent = cardsContainer

	for _, pass in ipairs(passCards) do
		local card = UIHelper.CreateRoundedFrame({
			Name = "Pass_" .. pass.name,
			Size = UDim2.new(0, 110, 0, 110),
			Color = DesignConfig.Colors.Background,
			CornerRadius = DesignConfig.Layout.ButtonCorner,
			StrokeColor = pass.color,
			Parent = cardsContainer,
		})

		-- Icon
		UIHelper.CreateLabel({
			Name = "Icon",
			Size = UDim2.new(1, 0, 0.5, 0),
			Text = pass.icon,
			TextColor = pass.color,
			Font = DesignConfig.Fonts.Accent,
			TextSize = 32,
			Parent = card,
		})

		-- Label
		UIHelper.CreateLabel({
			Name = "PassLabel",
			Size = UDim2.new(1, 0, 0.25, 0),
			Position = UDim2.new(0, 0, 0.5, 0),
			Text = pass.desc,
			TextColor = DesignConfig.Colors.TextSecondary,
			Font = DesignConfig.Fonts.Secondary,
			TextSize = DesignConfig.FontSizes.Small,
			Parent = card,
		})

		-- Robux button
		local robuxBtn = UIHelper.CreateButton({
			Name = "RobuxBtn",
			Size = UDim2.new(0.8, 0, 0, 24),
			Position = UDim2.new(0.5, 0, 1, -30),
			AnchorPoint = Vector2.new(0.5, 0),
			Color = Color3.fromRGB(0, 160, 0),
			HoverColor = Color3.fromRGB(0, 200, 0),
			Text = "R$ BUY",
			TextColor = DesignConfig.Colors.White,
			Font = DesignConfig.Fonts.Primary,
			TextSize = DesignConfig.FontSizes.Small,
			Parent = card,
		})

		robuxBtn.MouseButton1Click:Connect(function()
			-- Prompt Robux purchase (placeholder product ids)
			-- MarketplaceService:PromptProductPurchase(player, productId)
			print("[Store] Would prompt purchase for: " .. pass.name)
		end)
	end

	return section
end

-------------------------------------------------
-- BUILD MODAL
-------------------------------------------------

function StoreController.Init()
	screenGui = UIHelper.CreateScreenGui("StoreGui", 20)
	screenGui.Parent = playerGui

	-- Overlay
	overlay = UIHelper.CreateModalOverlay(screenGui, function()
		StoreController.Close()
	end)
	overlay.Visible = false

	-- Modal panel
	modalFrame = UIHelper.CreateRoundedFrame({
		Name = "StoreModal",
		Size = UDim2.new(0.65, 0, 0.7, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = DesignConfig.Colors.Background,
		CornerRadius = DesignConfig.Layout.ModalCorner,
		StrokeColor = Color3.fromRGB(80, 80, 120),
		Parent = screenGui,
	})
	modalFrame.ZIndex = 15
	modalFrame.Visible = false

	-- Title bar
	UIHelper.CreateLabel({
		Name = "StoreTitle",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "STORE",
		TextColor = DesignConfig.Colors.White,
		Font = DesignConfig.Fonts.Accent,
		TextSize = DesignConfig.FontSizes.Title,
		Parent = modalFrame,
	})

	-- Close button (red X)
	local closeBtn = UIHelper.CreateButton({
		Name = "CloseBtn",
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(1, -10, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Color = DesignConfig.Colors.Danger,
		HoverColor = Color3.fromRGB(255, 80, 80),
		Text = "X",
		TextColor = DesignConfig.Colors.White,
		Font = DesignConfig.Fonts.Primary,
		TextSize = DesignConfig.FontSizes.Body,
		CornerRadius = UDim.new(1, 0),
		Parent = modalFrame,
	})
	closeBtn.ZIndex = 16

	closeBtn.MouseButton1Click:Connect(function()
		StoreController.Close()
	end)

	-- Content scrolling frame
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -20, 1, -60)
	content.Position = UDim2.new(0.5, 0, 0, 55)
	content.AnchorPoint = Vector2.new(0.5, 0)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 220)
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 140)
	content.Parent = modalFrame

	-- Game Passes only (crates are in Spin shop)
	createPassesSection(content)
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function StoreController.Open()
	if isOpen then return end
	isOpen = true

	overlay.Visible = true
	modalFrame.Visible = true
	UIHelper.ScaleIn(modalFrame, 0.3)
end

function StoreController.Close()
	if not isOpen then return end
	isOpen = false

	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(modalFrame, tweenInfo, {
		Size = UDim2.new(
			modalFrame.Size.X.Scale * 0.8, 0,
			modalFrame.Size.Y.Scale * 0.8, 0
		),
	})
	tween:Play()
	tween.Completed:Connect(function()
		modalFrame.Visible = false
		overlay.Visible = false
		-- Restore size
		modalFrame.Size = UDim2.new(0.65, 0, 0.7, 0)
	end)
end

function StoreController.IsOpen(): boolean
	return isOpen
end

return StoreController
