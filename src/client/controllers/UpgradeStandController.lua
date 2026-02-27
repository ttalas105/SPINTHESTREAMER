--[[
	UpgradeStandController.lua
	Upgrade UI — dark-themed panel matching Case Shop / Potion Shop style.
	Two upgrades: Luck (+5 per purchase) and Coin Multiplier (+2% per purchase).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local UpgradeStandController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenUpgradeStandGui = RemoteEvents:WaitForChild("OpenUpgradeStandGui")
local UpgradeLuckRequest = RemoteEvents:WaitForChild("UpgradeLuckRequest")
local UpgradeLuckResult = RemoteEvents:WaitForChild("UpgradeLuckResult")
local UpgradeCashRequest = RemoteEvents:WaitForChild("UpgradeCashRequest")
local UpgradeCashResult = RemoteEvents:WaitForChild("UpgradeCashResult")

local screenGui, overlay, modalFrame
local isOpen = false

local luckValueRef, luckCostRef, luckBtnRef
local cashValueRef, cashCostRef, cashBtnRef

local FONT = Enum.Font.FredokaOne
local FONT_SUB = Enum.Font.GothamBold
local MODAL_BG = Color3.fromRGB(30, 25, 45)
local RED = Color3.fromRGB(220, 55, 55)
local RED_DARK = Color3.fromRGB(160, 30, 30)
local CARD_BG = Color3.fromRGB(40, 35, 60)
local MODAL_W, MODAL_H = 400, 420

local bounceTween = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function addStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function fmtNum(n)
	local s = tostring(math.floor(n))
	local formatted = ""
	local len = #s
	for i = 1, len do
		formatted = formatted .. string.sub(s, i, i)
		if (len - i) % 3 == 0 and i < len then formatted = formatted .. "," end
	end
	return formatted
end

-------------------------------------------------
-- REFRESH
-------------------------------------------------

local function refreshModal()
	if luckValueRef and luckCostRef and luckBtnRef then
		local luck = HUDController.Data.luck or 0
		local cost = Economy.GetLuckUpgradeCost(luck)
		luckValueRef.Text = "+" .. luck .. "% drop luck"
		luckCostRef.Text = "$" .. fmtNum(cost)
		local canAfford = (HUDController.Data.cash or 0) >= cost
		luckBtnRef.BackgroundColor3 = canAfford and Color3.fromRGB(50, 200, 90) or Color3.fromRGB(60, 55, 75)
	end
	if cashValueRef and cashCostRef and cashBtnRef then
		local cashUpgrade = HUDController.Data.cashUpgrade or 0
		local pct = cashUpgrade * 2
		local cost = Economy.GetCashUpgradeCost(cashUpgrade)
		cashValueRef.Text = "+" .. pct .. "% income"
		cashCostRef.Text = "$" .. fmtNum(cost)
		local canAfford = (HUDController.Data.cash or 0) >= cost
		cashBtnRef.BackgroundColor3 = canAfford and Color3.fromRGB(240, 180, 40) or Color3.fromRGB(60, 55, 75)
	end
end

local function flashButton(btn, color)
	btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TweenService:Create(btn, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
		BackgroundColor3 = color,
	}):Play()
end

-------------------------------------------------
-- BUILD UPGRADE CARD
-------------------------------------------------

local function buildUpgradeCard(parent, cfg)
	local card = Instance.new("Frame")
	card.Name = cfg.name .. "Card"
	card.Size = UDim2.new(1, 0, 0, 130)
	card.BackgroundColor3 = CARD_BG
	card.BorderSizePixel = 0
	card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.6, 0, 0, 24)
	title.Position = UDim2.new(0, 22, 0, 14)
	title.BackgroundTransparency = 1
	title.Text = cfg.title
	title.TextColor3 = cfg.accent
	title.Font = FONT
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card
	addStroke(title, Color3.new(0, 0, 0), 1)

	-- Description
	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(0.65, 0, 0, 16)
	desc.Position = UDim2.new(0, 22, 0, 38)
	desc.BackgroundTransparency = 1
	desc.Text = cfg.desc
	desc.TextColor3 = Color3.fromRGB(140, 135, 160)
	desc.Font = FONT_SUB
	desc.TextSize = 11
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Parent = card

	-- Current value (right side, top)
	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0, 120, 0, 22)
	valueLabel.Position = UDim2.new(1, -14, 0, 16)
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = "+0%"
	valueLabel.TextColor3 = cfg.valueColor
	valueLabel.Font = FONT
	valueLabel.TextSize = 16
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = card
	addStroke(valueLabel, Color3.new(0, 0, 0), 1)

	-- Cost label
	local costLabel = Instance.new("TextLabel")
	costLabel.Size = UDim2.new(0, 120, 0, 18)
	costLabel.Position = UDim2.new(1, -14, 0, 38)
	costLabel.AnchorPoint = Vector2.new(1, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = "$0"
	costLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	costLabel.Font = FONT_SUB
	costLabel.TextSize = 12
	costLabel.TextXAlignment = Enum.TextXAlignment.Right
	costLabel.Parent = card

	-- Buy button (bottom of card, full width)
	local btn = Instance.new("TextButton")
	btn.Name = "BuyBtn"
	btn.Size = UDim2.new(1, -24, 0, 40)
	btn.Position = UDim2.new(0.5, 0, 1, -12)
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.BackgroundColor3 = cfg.btnColor
	btn.Text = ""
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Parent = card
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = cfg.btnStroke
	btnStroke.Thickness = 1.5
	btnStroke.Parent = btn

	local btnText = Instance.new("TextLabel")
	btnText.Size = UDim2.new(1, 0, 1, 0)
	btnText.BackgroundTransparency = 1
	btnText.Text = cfg.btnLabel
	btnText.TextColor3 = Color3.new(1, 1, 1)
	btnText.Font = FONT
	btnText.TextSize = 16
	btnText.Parent = btn
	addStroke(btnText, Color3.new(0, 0, 0), 1)

	local idleSize = UDim2.new(1, -24, 0, 40)
	local hoverSize = UDim2.new(1, -18, 0, 44)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, bounceTween, { Size = hoverSize }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, bounceTween, { Size = idleSize }):Play()
	end)

	return card, valueLabel, costLabel, btn
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function UpgradeStandController.Open()
	if isOpen then return end
	isOpen = true
	if modalFrame then
		overlay.Visible = true
		modalFrame.Visible = true
		refreshModal()
		UIHelper.ScaleIn(modalFrame, 0.25)
	end
end

function UpgradeStandController.IsOpen()
	return isOpen
end

function UpgradeStandController.Close()
	if not isOpen then return end
	isOpen = false
	if overlay then overlay.Visible = false end
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function UpgradeStandController.Init()
	screenGui = UIHelper.CreateScreenGui("UpgradeStandGui", 5)
	screenGui.Parent = playerGui

	-- Overlay
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	-- Modal
	modalFrame = Instance.new("Frame")
	modalFrame.Name = "UpgradeModal"
	modalFrame.Size = UDim2.new(0, MODAL_W, 0, MODAL_H)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = MODAL_BG
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.ZIndex = 2
	modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui

	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 20)
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(70, 60, 100)
	mStroke.Thickness = 1.5
	mStroke.Transparency = 0.3
	mStroke.Parent = modalFrame
	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	-- ===== HEADER =====
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = modalFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.6, 0, 0, 32)
	title.Position = UDim2.new(0, 20, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "Upgrades"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = FONT
	title.TextSize = 28
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = header
	addStroke(title, Color3.new(0, 0, 0), 1.5)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -14, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = RED
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT
	closeBtn.TextSize = 20
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 5
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	local cStroke = Instance.new("UIStroke")
	cStroke.Color = RED_DARK
	cStroke.Thickness = 1.5
	cStroke.Parent = closeBtn
	addStroke(closeBtn, Color3.fromRGB(80, 0, 0), 1)

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, bounceTween, { Size = UDim2.new(0, 46, 0, 46), BackgroundColor3 = Color3.fromRGB(255, 75, 75) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, bounceTween, { Size = UDim2.new(0, 40, 0, 40), BackgroundColor3 = RED }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function() UpgradeStandController.Close() end)

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -30, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 62)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
	divider.BorderSizePixel = 0
	divider.ZIndex = 3
	divider.Parent = modalFrame

	-- ===== CARDS AREA =====
	local cardsContainer = Instance.new("Frame")
	cardsContainer.Name = "Cards"
	cardsContainer.Size = UDim2.new(1, -30, 1, -90)
	cardsContainer.Position = UDim2.new(0.5, 0, 0, 72)
	cardsContainer.AnchorPoint = Vector2.new(0.5, 0)
	cardsContainer.BackgroundTransparency = 1
	cardsContainer.ZIndex = 3
	cardsContainer.Parent = modalFrame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = cardsContainer

	-- LUCK CARD
	local _, luckVal, luckCost, luckBtn = buildUpgradeCard(cardsContainer, {
		name = "Luck",
		title = "Luck Upgrade",
		desc = "Each +5 luck = +5% better drops",
		accent = Color3.fromRGB(80, 220, 120),
		valueColor = Color3.fromRGB(120, 255, 160),
		btnColor = Color3.fromRGB(50, 200, 90),
		btnStroke = Color3.fromRGB(30, 140, 50),
		btnLabel = "BUY +5 LUCK",
	})
	luckValueRef = luckVal
	luckCostRef = luckCost
	luckBtnRef = luckBtn
	luckBtn.MouseButton1Click:Connect(function()
		UpgradeLuckRequest:FireServer()
	end)

	-- CASH CARD
	local _, cashVal, cashCost, cashBtn = buildUpgradeCard(cardsContainer, {
		name = "Cash",
		title = "Coin Multiplier",
		desc = "Each upgrade = +2% streamer income",
		accent = Color3.fromRGB(240, 200, 50),
		valueColor = Color3.fromRGB(255, 230, 120),
		btnColor = Color3.fromRGB(240, 180, 40),
		btnStroke = Color3.fromRGB(180, 120, 20),
		btnLabel = "BUY +2% COINS",
	})
	cashValueRef = cashVal
	cashCostRef = cashCost
	cashBtnRef = cashBtn
	cashBtn.MouseButton1Click:Connect(function()
		UpgradeCashRequest:FireServer()
	end)

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	HUDController.OnDataUpdated(function()
		if isOpen then refreshModal() end
	end)

	UpgradeLuckResult.OnClientEvent:Connect(function(result)
		if result.success then
			flashButton(luckBtnRef, Color3.fromRGB(50, 200, 90))
			if isOpen then refreshModal() end
		end
	end)

	UpgradeCashResult.OnClientEvent:Connect(function(result)
		if result.success then
			flashButton(cashBtnRef, Color3.fromRGB(240, 180, 40))
			if isOpen then refreshModal() end
		end
	end)

	OpenUpgradeStandGui.OnClientEvent:Connect(function()
		local TutorialController = require(script.Parent.TutorialController)
		if TutorialController.IsActive() then return end
		if isOpen then
			UpgradeStandController.Close()
		else
			UpgradeStandController.Open()
		end
	end)

	modalFrame.Visible = false
end

return UpgradeStandController
