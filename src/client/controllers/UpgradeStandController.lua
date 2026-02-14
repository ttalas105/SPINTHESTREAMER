--[[
	UpgradeStandController.lua
	Kid-friendly upgrade UI at the Upgrade stand (beside Spin).
	Two upgrades: Luck (+5 per purchase) and Coin Multiplier (+2% per purchase).
	Vibrant, bubbly design with gradients, icons, and animations.
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

local screenGui
local modalFrame
local isOpen = false

-- Refs for dynamic update
local luckStatRef
local luckBtnRef
local cashStatRef
local cashBtnRef

local FONT = Enum.Font.FredokaOne

-------------------------------------------------
-- REFRESH
-------------------------------------------------
local function refreshModal()
	-- Luck
	if luckStatRef and luckBtnRef then
		local luck = HUDController.Data.luck or 0
		local cost = Economy.GetLuckUpgradeCost(luck)
		luckStatRef.Text = ("🍀 Luck: %d  (+%d%% drop luck)"):format(luck, luck)
		luckBtnRef.Text = ("BUY +5 LUCK  •  $%s"):format(tostring(cost))
		local canAfford = (HUDController.Data.cash or 0) >= cost
		luckBtnRef.BackgroundColor3 = canAfford and Color3.fromRGB(50, 210, 90) or Color3.fromRGB(80, 80, 90)
	end
	-- Cash
	if cashStatRef and cashBtnRef then
		local cashUpgrade = HUDController.Data.cashUpgrade or 0
		local percentBoost = cashUpgrade * 2
		local cost = Economy.GetCashUpgradeCost(cashUpgrade)
		cashStatRef.Text = ("💰 Cash Boost: +%d%%"):format(percentBoost)
		cashBtnRef.Text = ("BUY +2%% CASH  •  $%s"):format(tostring(cost))
		local canAfford = (HUDController.Data.cash or 0) >= cost
		cashBtnRef.BackgroundColor3 = canAfford and Color3.fromRGB(255, 190, 40) or Color3.fromRGB(80, 80, 90)
	end
end

-------------------------------------------------
-- FLASH ANIMATION on successful upgrade
-------------------------------------------------
local function flashButton(btn, color)
	local orig = btn.BackgroundColor3
	btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TweenService:Create(btn, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
		BackgroundColor3 = color,
	}):Play()
end

-------------------------------------------------
-- BUILD UPGRADE CARD
-------------------------------------------------
local function buildUpgradeCard(parent, config)
	-- Card frame
	local card = Instance.new("Frame")
	card.Name = config.name .. "Card"
	card.Size = UDim2.new(1, -30, 0, 160)
	card.BackgroundColor3 = config.bgColor
	card.BorderSizePixel = 0
	card.Parent = parent
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 18)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = config.strokeColor
	cardStroke.Thickness = 2.5
	cardStroke.Parent = card

	-- Top gradient accent
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(1, 0, 0, 4)
	accent.Position = UDim2.new(0, 0, 0, 0)
	accent.BackgroundColor3 = config.accentColor
	accent.BorderSizePixel = 0
	accent.ZIndex = 3
	accent.Parent = card
	local acCorner = Instance.new("UICorner")
	acCorner.CornerRadius = UDim.new(0, 18)
	acCorner.Parent = accent

	-- Icon (big emoji)
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 60, 0, 60)
	icon.Position = UDim2.new(0, 16, 0, 16)
	icon.BackgroundTransparency = 1
	icon.Text = config.emoji
	icon.TextSize = 44
	icon.Font = Enum.Font.SourceSans
	icon.Parent = card

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -90, 0, 30)
	title.Position = UDim2.new(0, 80, 0, 16)
	title.BackgroundTransparency = 1
	title.Text = config.title
	title.TextColor3 = config.titleColor
	title.Font = FONT
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(0, 0, 0)
	tStroke.Thickness = 2
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tStroke.Parent = title

	-- Subtitle description
	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.Size = UDim2.new(1, -90, 0, 20)
	desc.Position = UDim2.new(0, 80, 0, 46)
	desc.BackgroundTransparency = 1
	desc.Text = config.desc
	desc.TextColor3 = Color3.fromRGB(200, 200, 220)
	desc.Font = FONT
	desc.TextSize = 13
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Parent = card

	-- Stat label (dynamic — shows current level)
	local statLabel = Instance.new("TextLabel")
	statLabel.Name = "StatLabel"
	statLabel.Size = UDim2.new(1, -30, 0, 28)
	statLabel.Position = UDim2.new(0.5, 0, 0, 78)
	statLabel.AnchorPoint = Vector2.new(0.5, 0)
	statLabel.BackgroundTransparency = 1
	statLabel.Text = ""
	statLabel.TextColor3 = config.statColor
	statLabel.Font = FONT
	statLabel.TextSize = 18
	statLabel.Parent = card
	local sStroke = Instance.new("UIStroke")
	sStroke.Color = Color3.fromRGB(0, 0, 0)
	sStroke.Thickness = 1.5
	sStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	sStroke.Parent = statLabel

	-- Buy button (big, bold, gradient)
	local btn = Instance.new("TextButton")
	btn.Name = "BuyBtn"
	btn.Size = UDim2.new(0.85, 0, 0, 42)
	btn.Position = UDim2.new(0.5, 0, 1, -14)
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.BackgroundColor3 = config.btnColor
	btn.Text = "BUY"
	btn.TextColor3 = config.btnTextColor
	btn.Font = FONT
	btn.TextSize = 18
	btn.BorderSizePixel = 0
	btn.Parent = card
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 14)
	btnCorner.Parent = btn
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = config.btnStrokeColor
	btnStroke.Thickness = 2.5
	btnStroke.Parent = btn
	-- Subtle gradient on button (no transparency — prevents blurred look)
	local btnGrad = Instance.new("UIGradient")
	btnGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 210, 210)),
	})
	btnGrad.Rotation = 90
	btnGrad.Parent = btn

	-- Hover effect
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), {
			Size = UDim2.new(0.88, 0, 0, 44),
		}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), {
			Size = UDim2.new(0.85, 0, 0, 42),
		}):Play()
	end)

	return card, statLabel, btn
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function UpgradeStandController.Open()
	if isOpen then return end
	isOpen = true
	if modalFrame then
		modalFrame.Visible = true
		refreshModal()
		UIHelper.ScaleIn(modalFrame, 0.25)
	end
end

function UpgradeStandController.Close()
	if not isOpen then return end
	isOpen = false
	if modalFrame then modalFrame.Visible = false end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function UpgradeStandController.Init()
	screenGui = UIHelper.CreateScreenGui("UpgradeStandGui", 5)
	screenGui.Parent = playerGui

	-- No overlay — clean, no dark background shade

	-- Modal frame
	modalFrame = Instance.new("Frame")
	modalFrame.Name = "UpgradeModal"
	modalFrame.Size = UDim2.new(0, 380, 0, 460)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = Color3.fromRGB(18, 16, 32)
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.Parent = screenGui
	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(0, 22)
	mCorner.Parent = modalFrame
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(100, 80, 200)
	mStroke.Thickness = 3
	mStroke.Parent = modalFrame

	-- Rainbow top bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 5)
	topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	topBar.BorderSizePixel = 0
	topBar.ZIndex = 5
	topBar.Parent = modalFrame
	local tbGrad = Instance.new("UIGradient")
	tbGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 255, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 150, 255)),
	})
	tbGrad.Parent = topBar

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -60, 0, 44)
	title.Position = UDim2.new(0.5, 0, 0, 12)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "⚡ UPGRADES ⚡"
	title.TextColor3 = Color3.fromRGB(255, 220, 80)
	title.Font = FONT
	title.TextSize = 30
	title.Parent = modalFrame
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(120, 60, 200)
	titleStroke.Thickness = 3
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -12, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = FONT
	closeBtn.TextSize = 22
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 8
	closeBtn.Parent = modalFrame
	local ccCorner = Instance.new("UICorner")
	ccCorner.CornerRadius = UDim.new(1, 0)
	ccCorner.Parent = closeBtn
	local ccStroke = Instance.new("UIStroke")
	ccStroke.Color = Color3.fromRGB(120, 30, 30)
	ccStroke.Thickness = 2
	ccStroke.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		UpgradeStandController.Close()
	end)

	-- Cards container
	local cardsContainer = Instance.new("Frame")
	cardsContainer.Name = "CardsContainer"
	cardsContainer.Size = UDim2.new(1, 0, 1, -70)
	cardsContainer.Position = UDim2.new(0, 0, 0, 62)
	cardsContainer.BackgroundTransparency = 1
	cardsContainer.Parent = modalFrame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 14)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = cardsContainer

	-- LUCK CARD
	local _, luckStat, luckBtn = buildUpgradeCard(cardsContainer, {
		name = "Luck",
		emoji = "🍀",
		title = "LUCK UPGRADE",
		desc = "Each +5 luck = +5% better drops!",
		titleColor = Color3.fromRGB(80, 255, 120),
		statColor = Color3.fromRGB(150, 255, 180),
		bgColor = Color3.fromRGB(20, 40, 28),
		strokeColor = Color3.fromRGB(60, 200, 100),
		accentColor = Color3.fromRGB(80, 255, 120),
		btnColor = Color3.fromRGB(50, 210, 90),
		btnTextColor = Color3.fromRGB(255, 255, 255),
		btnStrokeColor = Color3.fromRGB(30, 140, 50),
	})
	luckStatRef = luckStat
	luckBtnRef = luckBtn
	luckBtn.MouseButton1Click:Connect(function()
		UpgradeLuckRequest:FireServer()
	end)

	-- CASH CARD
	local _, cashStat, cashBtn = buildUpgradeCard(cardsContainer, {
		name = "Cash",
		emoji = "💰",
		title = "COIN MULTIPLIER",
		desc = "Each upgrade = +2% streamer income!",
		titleColor = Color3.fromRGB(255, 220, 60),
		statColor = Color3.fromRGB(255, 240, 150),
		bgColor = Color3.fromRGB(40, 35, 18),
		strokeColor = Color3.fromRGB(220, 180, 40),
		accentColor = Color3.fromRGB(255, 200, 50),
		btnColor = Color3.fromRGB(255, 190, 40),
		btnTextColor = Color3.fromRGB(30, 20, 0),
		btnStrokeColor = Color3.fromRGB(180, 120, 20),
	})
	cashStatRef = cashStat
	cashBtnRef = cashBtn
	cashBtn.MouseButton1Click:Connect(function()
		UpgradeCashRequest:FireServer()
	end)

	-- Bottom helper text
	local helpLabel = Instance.new("TextLabel")
	helpLabel.Size = UDim2.new(1, -20, 0, 22)
	helpLabel.Position = UDim2.new(0.5, 0, 1, -10)
	helpLabel.AnchorPoint = Vector2.new(0.5, 1)
	helpLabel.BackgroundTransparency = 1
	helpLabel.Text = "Luck = better drops  •  Cash = more income"
	helpLabel.TextColor3 = Color3.fromRGB(120, 120, 150)
	helpLabel.Font = FONT
	helpLabel.TextSize = 12
	helpLabel.Parent = modalFrame

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	HUDController.OnDataUpdated(function()
		if isOpen then refreshModal() end
	end)

	UpgradeLuckResult.OnClientEvent:Connect(function(result)
		if result.success then
			flashButton(luckBtnRef, Color3.fromRGB(50, 210, 90))
			if isOpen then refreshModal() end
		end
	end)

	UpgradeCashResult.OnClientEvent:Connect(function(result)
		if result.success then
			flashButton(cashBtnRef, Color3.fromRGB(255, 190, 40))
			if isOpen then refreshModal() end
		end
	end)

	OpenUpgradeStandGui.OnClientEvent:Connect(function()
		if isOpen then
			UpgradeStandController.Close()
		else
			UpgradeStandController.Open()
		end
	end)

	modalFrame.Visible = false
end

return UpgradeStandController
