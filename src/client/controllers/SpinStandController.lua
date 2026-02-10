--[[
	SpinStandController.lua
	Crate shop UI that opens when the player interacts with the Spin stand.
	Kid-friendly: bubbly cards, Crate 1 ($50, +10% luck), Crate 2 ($200, +30% luck).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UIHelper = require(script.Parent.UIHelper)

local SpinStandController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyCrateRequest = RemoteEvents:WaitForChild("BuyCrateRequest")
local OpenSpinStandGui = RemoteEvents:WaitForChild("OpenSpinStandGui")

local screenGui
local modalFrame
local overlay
local isOpen = false

-------------------------------------------------
-- BUBBLY STYLE (kid-friendly)
-------------------------------------------------
local BUBBLE_CORNER = 24
local CARD_CORNER = 20
local STROKE_THICK = 3
local STROKE_DARK = Color3.fromRGB(25, 20, 45)
local CARTOON_FONT = Enum.Font.Cartoon

-------------------------------------------------
-- CRATE DEFINITIONS
-------------------------------------------------
local crates = {
	{
		id = 1,
		name = "Crate 1",
		emoji = "📦",
		cost = Economy.Crate1Cost,
		luckPercent = 10,
		desc = "Luck: +10%",
		color = Color3.fromRGB(100, 200, 255),
		strokeColor = Color3.fromRGB(40, 120, 180),
	},
	{
		id = 2,
		name = "Crate 2",
		emoji = "🎁",
		cost = Economy.Crate2Cost,
		luckPercent = 30,
		desc = "Luck: +30%",
		color = Color3.fromRGB(255, 140, 180),
		strokeColor = Color3.fromRGB(180, 60, 100),
	},
}

-------------------------------------------------
-- BUILD CRATE CARD (one card per crate)
-------------------------------------------------
local function buildCrateCard(crate, parent)
	local card = UIHelper.CreateRoundedFrame({
		Name = "CrateCard_" .. crate.id,
		Size = UDim2.new(0, 200, 0, 220),
		Color = crate.color,
		CornerRadius = UDim.new(0, CARD_CORNER),
		StrokeColor = crate.strokeColor,
		StrokeThickness = STROKE_THICK,
		Parent = parent,
	})

	local cardStroke = card:FindFirstChildOfClass("UIStroke")
	if cardStroke then
		cardStroke.Color = STROKE_DARK
		cardStroke.Thickness = STROKE_THICK
	end

	-- Big emoji icon
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, 0, 0.35, 0)
	icon.Position = UDim2.new(0, 0, 0.05, 0)
	icon.BackgroundTransparency = 1
	icon.Text = crate.emoji
	icon.TextColor3 = DesignConfig.Colors.White
	icon.Font = CARTOON_FONT
	icon.TextScaled = true
	icon.Parent = card

	-- Crate name
	UIHelper.CreateLabel({
		Name = "Name",
		Size = UDim2.new(1, -16, 0, 32),
		Position = UDim2.new(0, 8, 0.38, 0),
		Text = crate.name,
		TextColor = DesignConfig.Colors.White,
		Font = CARTOON_FONT,
		TextSize = 26,
		Parent = card,
	})

	-- Luck description (eye-catching)
	local luckLabel = UIHelper.CreateLabel({
		Name = "Luck",
		Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.new(0, 8, 0.52, 0),
		Text = crate.desc,
		TextColor = Color3.fromRGB(255, 255, 200),
		Font = CARTOON_FONT,
		TextSize = 20,
		Parent = card,
	})
	local luckStroke = Instance.new("UIStroke")
	luckStroke.Color = Color3.fromRGB(40, 30, 20)
	luckStroke.Thickness = 1.5
	luckStroke.Parent = luckLabel

	-- Price
	UIHelper.CreateLabel({
		Name = "Price",
		Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.new(0, 8, 0.66, 0),
		Text = "$" .. tostring(crate.cost),
		TextColor = Color3.fromRGB(80, 255, 120),
		Font = CARTOON_FONT,
		TextSize = 24,
		Parent = card,
	})

	-- BUY button (bubbly green)
	local buyBtn = UIHelper.CreateButton({
		Name = "BuyBtn",
		Size = UDim2.new(0.85, 0, 0, 44),
		Position = UDim2.new(0.5, 0, 1, -50),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = Color3.fromRGB(60, 220, 100),
		HoverColor = Color3.fromRGB(100, 255, 140),
		Text = "BUY",
		TextColor = DesignConfig.Colors.White,
		Font = CARTOON_FONT,
		TextSize = 22,
		CornerRadius = UDim.new(0, 16),
		StrokeColor = Color3.fromRGB(20, 100, 50),
		StrokeThickness = 2,
		Parent = card,
	})

	buyBtn.MouseButton1Click:Connect(function()
		BuyCrateRequest:FireServer(crate.id)
		SpinStandController.Close()
		-- Show spin wheel so player sees the result (SpinResult will fire from server)
		local SpinController = require(script.Parent.SpinController)
		SpinController.Show()
	end)

	return card
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function SpinStandController.Open()
	if isOpen then return end
	isOpen = true
	overlay.Visible = true
	modalFrame.Visible = true
	UIHelper.ScaleIn(modalFrame, 0.35)
end

function SpinStandController.Close()
	if not isOpen then return end
	isOpen = false
	overlay.Visible = false
	modalFrame.Visible = false
end

function SpinStandController.IsOpen(): boolean
	return isOpen
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function SpinStandController.Init()
	screenGui = UIHelper.CreateScreenGui("SpinStandGui", 18)
	screenGui.Parent = playerGui

	-- Dark overlay (tap to close optional)
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	-- Modal: bubbly panel
	modalFrame = UIHelper.CreateRoundedFrame({
		Name = "CrateShopModal",
		Size = UDim2.new(0, 480, 0, 340),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(55, 45, 85),
		CornerRadius = UDim.new(0, BUBBLE_CORNER),
		StrokeColor = Color3.fromRGB(180, 120, 255),
		StrokeThickness = STROKE_THICK,
		Parent = screenGui,
	})
	modalFrame.ZIndex = 2
	modalFrame.Visible = false

	local modalStroke = modalFrame:FindFirstChildOfClass("UIStroke")
	if modalStroke then
		modalStroke.Color = STROKE_DARK
	end

	-- Title
	local title = UIHelper.CreateLabel({
		Name = "Title",
		Size = UDim2.new(1, -80, 0, 50),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "🎰 Pick a Crate! 🎰",
		TextColor = Color3.fromRGB(255, 240, 120),
		Font = CARTOON_FONT,
		TextSize = 32,
		Parent = modalFrame,
	})

	-- Subtitle
	UIHelper.CreateLabel({
		Name = "Subtitle",
		Size = UDim2.new(1, -40, 0, 24),
		Position = UDim2.new(0.5, 0, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Better luck = rarer drops!",
		TextColor = DesignConfig.Colors.TextSecondary,
		Font = CARTOON_FONT,
		TextSize = 18,
		Parent = modalFrame,
	})

	-- Cards container
	local cardsFrame = Instance.new("Frame")
	cardsFrame.Name = "CardsFrame"
	cardsFrame.Size = UDim2.new(1, -40, 0, 230)
	cardsFrame.Position = UDim2.new(0, 20, 0, 90)
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.ZIndex = 2
	cardsFrame.Parent = modalFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 24)
	listLayout.Parent = cardsFrame

	for _, crate in ipairs(crates) do
		buildCrateCard(crate, cardsFrame)
	end

	-- Close button (bubbly X)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 44, 0, 44)
	closeBtn.Position = UDim2.new(1, -52, 0, -8)
	closeBtn.AnchorPoint = Vector2.new(0, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = DesignConfig.Colors.White
	closeBtn.Font = CARTOON_FONT
	closeBtn.TextSize = 28
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 3
	closeBtn.Parent = modalFrame

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeBtn

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(120, 30, 30)
	closeStroke.Thickness = 2
	closeStroke.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		SpinStandController.Close()
	end)

	-- Listen for server telling us to open (when player uses ProximityPrompt at spin stand)
	OpenSpinStandGui.OnClientEvent:Connect(function()
		SpinStandController.Open()
	end)
end

return SpinStandController
