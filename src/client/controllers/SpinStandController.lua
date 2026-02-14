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
	{ id = 1, name = "Crate 1", emoji = "📦", cost = Economy.Crate1Cost, luckPercent = 10,  desc = "Luck: +10%",  color = Color3.fromRGB(100, 200, 255), strokeColor = Color3.fromRGB(40, 120, 180) },
	{ id = 2, name = "Crate 2", emoji = "🎁", cost = Economy.Crate2Cost, luckPercent = 30,  desc = "Luck: +30%",  color = Color3.fromRGB(255, 140, 180), strokeColor = Color3.fromRGB(180, 60, 100) },
	{ id = 3, name = "Crate 3", emoji = "📫", cost = Economy.Crate3Cost, luckPercent = 60,  desc = "Luck: +60%",  color = Color3.fromRGB(160, 255, 160), strokeColor = Color3.fromRGB(40, 160, 60) },
	{ id = 4, name = "Crate 4", emoji = "🎀", cost = Economy.Crate4Cost, luckPercent = 100, desc = "Luck: +100%", color = Color3.fromRGB(255, 200, 100), strokeColor = Color3.fromRGB(200, 140, 40) },
	{ id = 5, name = "Crate 5", emoji = "✨", cost = Economy.Crate5Cost, luckPercent = 200, desc = "Luck: +200%", color = Color3.fromRGB(200, 150, 255), strokeColor = Color3.fromRGB(120, 60, 200) },
	{ id = 6, name = "Crate 6", emoji = "🌟", cost = Economy.Crate6Cost, luckPercent = 150, desc = "Luck: +150%", color = Color3.fromRGB(255, 220, 140), strokeColor = Color3.fromRGB(200, 120, 30) },
	{ id = 7, name = "Crate 7", emoji = "💎", cost = Economy.Crate7Cost, luckPercent = 250, desc = "Luck: +250%", color = Color3.fromRGB(180, 220, 255), strokeColor = Color3.fromRGB(60, 120, 200) },
}

-- Cached card refs for dynamic lock/unlock updates
local cardRefs = {} -- crateId -> { card, buyBtn, lockOverlay }

-------------------------------------------------
-- Helper: get current rebirth count from HUDController
-------------------------------------------------
local function getRebirthCount()
	local HUDController = require(script.Parent.HUDController)
	return HUDController.Data.rebirthCount or 0
end

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

	-- Lock overlay (semi-transparent dark cover with lock icon)
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	lockOverlay.BackgroundTransparency = 0.4
	lockOverlay.BorderSizePixel = 0
	lockOverlay.ZIndex = 5
	lockOverlay.Visible = false
	lockOverlay.Parent = card
	local lockCorner = Instance.new("UICorner")
	lockCorner.CornerRadius = UDim.new(0, CARD_CORNER)
	lockCorner.Parent = lockOverlay

	local lockIcon = Instance.new("TextLabel")
	lockIcon.Name = "LockIcon"
	lockIcon.Size = UDim2.new(1, 0, 0, 50)
	lockIcon.Position = UDim2.new(0.5, 0, 0.3, 0)
	lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	lockIcon.BackgroundTransparency = 1
	lockIcon.Text = "🔒"
	lockIcon.TextSize = 40
	lockIcon.Font = Enum.Font.SourceSans
	lockIcon.ZIndex = 6
	lockIcon.Parent = lockOverlay

	local lockText = Instance.new("TextLabel")
	lockText.Name = "LockText"
	lockText.Size = UDim2.new(1, -10, 0, 40)
	lockText.Position = UDim2.new(0.5, 0, 0.6, 0)
	lockText.AnchorPoint = Vector2.new(0.5, 0.5)
	lockText.BackgroundTransparency = 1
	lockText.Text = "Rebirth " .. Economy.GetCrateRebirthRequirement(crate.id) .. "\nRequired"
	lockText.TextColor3 = Color3.fromRGB(255, 180, 80)
	lockText.Font = Enum.Font.FredokaOne
	lockText.TextSize = 15
	lockText.TextWrapped = true
	lockText.ZIndex = 6
	lockText.Parent = lockOverlay
	local ltStroke = Instance.new("UIStroke")
	ltStroke.Color = Color3.fromRGB(0, 0, 0)
	ltStroke.Thickness = 1.5
	ltStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ltStroke.Parent = lockText

	buyBtn.MouseButton1Click:Connect(function()
		-- Check rebirth requirement
		local rebirthReq = Economy.GetCrateRebirthRequirement(crate.id)
		local currentRebirth = getRebirthCount()
		if currentRebirth < rebirthReq then
			-- Show error message on the button
			buyBtn.Text = "Rebirth " .. rebirthReq .. " needed!"
			task.delay(1.5, function()
				buyBtn.Text = "🔒 LOCKED"
			end)
			return
		end

		SpinStandController.Close()
		-- Tell SpinController the cost and crate ID for this spin
		local SpinController = require(script.Parent.SpinController)
		SpinController.SetCurrentCost(crate.cost)
		SpinController.SetCurrentCrateId(crate.id)
		SpinController.Show()
		-- Fire crate request via SpinController.RequestSpin (handles queue too)
		SpinController.RequestSpin()
	end)

	-- Store refs for dynamic updates
	cardRefs[crate.id] = {
		card = card,
		buyBtn = buyBtn,
		lockOverlay = lockOverlay,
	}

	return card
end

-------------------------------------------------
-- UPDATE LOCK STATUS on all cards
-------------------------------------------------
local function updateLockStatus()
	local currentRebirth = getRebirthCount()
	for crateId, refs in pairs(cardRefs) do
		local rebirthReq = Economy.GetCrateRebirthRequirement(crateId)
		if currentRebirth >= rebirthReq then
			-- Unlocked
			refs.lockOverlay.Visible = false
			refs.buyBtn.Text = "BUY"
			refs.buyBtn.BackgroundColor3 = Color3.fromRGB(60, 220, 100)
		else
			-- Locked
			refs.lockOverlay.Visible = true
			refs.buyBtn.Text = "🔒 LOCKED"
			refs.buyBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		end
	end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function SpinStandController.Open()
	if isOpen then return end
	isOpen = true
	updateLockStatus() -- Refresh which crates are locked/unlocked
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

	-- Cards container (scrollable for 7 crates)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CardsScroll"
	scroll.Size = UDim2.new(1, -40, 0, 250)
	scroll.Position = UDim2.new(0, 20, 0, 90)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 140)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroll.ZIndex = 2
	scroll.Parent = modalFrame

	local cardsFrame = Instance.new("Frame")
	cardsFrame.Name = "CardsFrame"
	cardsFrame.Size = UDim2.new(0, 0, 1, 0)
	cardsFrame.AutomaticSize = Enum.AutomaticSize.X
	cardsFrame.BackgroundTransparency = 1
	cardsFrame.Parent = scroll

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 20)
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
