--[[
	UpgradeStandController.lua
	Upgrade UI at the Upgrade stand (beside Spin). Open with E at the green Upgrades stall.
	Two upgrades:
	  - Luck: +5 luck per purchase (1 luck = +1% drop luck)
	  - Coin Multiplier: +2% cash production per purchase
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
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

-- Luck refs
local luckLabelRef
local luckCostBtnRef

-- Cash refs
local cashLabelRef
local cashCostBtnRef

local BUBBLE_FONT = Enum.Font.FredokaOne

local function refreshModal()
	-- Luck
	if luckLabelRef and luckCostBtnRef then
		local luck = HUDController.Data.luck or 0
		local percent = luck  -- 1 luck = 1%
		local cost = Economy.GetLuckUpgradeCost(luck)
		luckLabelRef.Text = ("Luck: %d  (+%d%% drop luck)"):format(luck, percent)
		luckCostBtnRef.Text = ("Upgrade +5 Luck — $%s"):format(tostring(cost))
		local canAfford = (HUDController.Data.cash or 0) >= cost
		luckCostBtnRef.BackgroundColor3 = canAfford and Color3.fromRGB(50, 200, 80) or Color3.fromRGB(80, 80, 90)
	end

	-- Cash
	if cashLabelRef and cashCostBtnRef then
		local cashUpgrade = HUDController.Data.cashUpgrade or 0
		local percentBoost = cashUpgrade * 2
		local cost = Economy.GetCashUpgradeCost(cashUpgrade)
		cashLabelRef.Text = ("Cash Boost: +%d%%"):format(percentBoost)
		cashCostBtnRef.Text = ("Upgrade +2%% Cash — $%s"):format(tostring(cost))
		local canAfford = (HUDController.Data.cash or 0) >= cost
		cashCostBtnRef.BackgroundColor3 = canAfford and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(80, 80, 90)
	end
end

function UpgradeStandController.Open()
	if isOpen then return end
	isOpen = true
	if modalFrame then
		modalFrame.Visible = true
		refreshModal()
	end
end

function UpgradeStandController.Close()
	if not isOpen then return end
	isOpen = false
	if modalFrame then modalFrame.Visible = false end
end

function UpgradeStandController.Init()
	screenGui = UIHelper.CreateScreenGui("UpgradeStandGui", 5)
	screenGui.Parent = playerGui

	-- Modal (no dark overlay)
	modalFrame = UIHelper.CreateRoundedFrame({
		Name = "UpgradeModal",
		Size = UDim2.new(0, 420, 0, 360),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(25, 28, 40),
		CornerRadius = UDim.new(0, 20),
		StrokeColor = Color3.fromRGB(50, 200, 80),
		StrokeThickness = 3,
		Parent = screenGui,
	})
	modalFrame.ZIndex = 6

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 36)
	title.Position = UDim2.new(0.5, 0, 0, 14)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "UPGRADES"
	title.TextColor3 = Color3.fromRGB(150, 255, 180)
	title.Font = BUBBLE_FONT
	title.TextSize = 28
	title.ZIndex = 7
	title.Parent = modalFrame
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 2
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = title

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -8, 0, 8)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = BUBBLE_FONT
	closeBtn.TextSize = 20
	closeBtn.ZIndex = 8
	closeBtn.Parent = modalFrame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		UpgradeStandController.Close()
	end)

	-------------------------------------------------
	-- LUCK UPGRADE SECTION
	-------------------------------------------------
	local luckSection = Instance.new("Frame")
	luckSection.Name = "LuckSection"
	luckSection.Size = UDim2.new(1, -32, 0, 110)
	luckSection.Position = UDim2.new(0.5, 0, 0, 60)
	luckSection.AnchorPoint = Vector2.new(0.5, 0)
	luckSection.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
	luckSection.BorderSizePixel = 0
	luckSection.ZIndex = 7
	luckSection.Parent = modalFrame
	local lsCorner = Instance.new("UICorner")
	lsCorner.CornerRadius = UDim.new(0, 12)
	lsCorner.Parent = luckSection
	local lsStroke = Instance.new("UIStroke")
	lsStroke.Color = Color3.fromRGB(50, 200, 80)
	lsStroke.Thickness = 2
	lsStroke.Parent = luckSection

	-- Luck icon label
	local luckIcon = Instance.new("TextLabel")
	luckIcon.Size = UDim2.new(1, -16, 0, 22)
	luckIcon.Position = UDim2.new(0.5, 0, 0, 10)
	luckIcon.AnchorPoint = Vector2.new(0.5, 0)
	luckIcon.BackgroundTransparency = 1
	luckIcon.Text = "LUCK UPGRADE"
	luckIcon.TextColor3 = Color3.fromRGB(80, 255, 100)
	luckIcon.Font = BUBBLE_FONT
	luckIcon.TextSize = 16
	luckIcon.ZIndex = 8
	luckIcon.Parent = luckSection
	local liStroke = Instance.new("UIStroke")
	liStroke.Color = Color3.fromRGB(0, 0, 0)
	liStroke.Thickness = 1.5
	liStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	liStroke.Parent = luckIcon

	-- Luck stat label
	luckLabelRef = Instance.new("TextLabel")
	luckLabelRef.Name = "LuckLabel"
	luckLabelRef.Size = UDim2.new(1, -16, 0, 20)
	luckLabelRef.Position = UDim2.new(0.5, 0, 0, 34)
	luckLabelRef.AnchorPoint = Vector2.new(0.5, 0)
	luckLabelRef.BackgroundTransparency = 1
	luckLabelRef.Text = "Luck: 0  (+0% drop luck)"
	luckLabelRef.TextColor3 = Color3.fromRGB(200, 200, 220)
	luckLabelRef.Font = BUBBLE_FONT
	luckLabelRef.TextSize = 14
	luckLabelRef.ZIndex = 8
	luckLabelRef.Parent = luckSection

	-- Luck upgrade button
	luckCostBtnRef = Instance.new("TextButton")
	luckCostBtnRef.Name = "LuckUpgradeBtn"
	luckCostBtnRef.Size = UDim2.new(0.85, 0, 0, 34)
	luckCostBtnRef.Position = UDim2.new(0.5, 0, 1, -10)
	luckCostBtnRef.AnchorPoint = Vector2.new(0.5, 1)
	luckCostBtnRef.BackgroundColor3 = Color3.fromRGB(50, 200, 80)
	luckCostBtnRef.Text = "Upgrade +5 Luck — $1"
	luckCostBtnRef.TextColor3 = Color3.fromRGB(255, 255, 255)
	luckCostBtnRef.Font = BUBBLE_FONT
	luckCostBtnRef.TextSize = 15
	luckCostBtnRef.BorderSizePixel = 0
	luckCostBtnRef.ZIndex = 8
	luckCostBtnRef.Parent = luckSection
	local lbCorner = Instance.new("UICorner")
	lbCorner.CornerRadius = UDim.new(0, 10)
	lbCorner.Parent = luckCostBtnRef

	luckCostBtnRef.MouseButton1Click:Connect(function()
		UpgradeLuckRequest:FireServer()
	end)

	-------------------------------------------------
	-- CASH UPGRADE SECTION
	-------------------------------------------------
	local cashSection = Instance.new("Frame")
	cashSection.Name = "CashSection"
	cashSection.Size = UDim2.new(1, -32, 0, 110)
	cashSection.Position = UDim2.new(0.5, 0, 0, 180)
	cashSection.AnchorPoint = Vector2.new(0.5, 0)
	cashSection.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
	cashSection.BorderSizePixel = 0
	cashSection.ZIndex = 7
	cashSection.Parent = modalFrame
	local csCorner = Instance.new("UICorner")
	csCorner.CornerRadius = UDim.new(0, 12)
	csCorner.Parent = cashSection
	local csStroke = Instance.new("UIStroke")
	csStroke.Color = Color3.fromRGB(255, 200, 50)
	csStroke.Thickness = 2
	csStroke.Parent = cashSection

	-- Cash icon label
	local cashIcon = Instance.new("TextLabel")
	cashIcon.Size = UDim2.new(1, -16, 0, 22)
	cashIcon.Position = UDim2.new(0.5, 0, 0, 10)
	cashIcon.AnchorPoint = Vector2.new(0.5, 0)
	cashIcon.BackgroundTransparency = 1
	cashIcon.Text = "COIN MULTIPLIER UPGRADE"
	cashIcon.TextColor3 = Color3.fromRGB(255, 220, 60)
	cashIcon.Font = BUBBLE_FONT
	cashIcon.TextSize = 16
	cashIcon.ZIndex = 8
	cashIcon.Parent = cashSection
	local ciStroke = Instance.new("UIStroke")
	ciStroke.Color = Color3.fromRGB(0, 0, 0)
	ciStroke.Thickness = 1.5
	ciStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	ciStroke.Parent = cashIcon

	-- Cash stat label
	cashLabelRef = Instance.new("TextLabel")
	cashLabelRef.Name = "CashLabel"
	cashLabelRef.Size = UDim2.new(1, -16, 0, 20)
	cashLabelRef.Position = UDim2.new(0.5, 0, 0, 34)
	cashLabelRef.AnchorPoint = Vector2.new(0.5, 0)
	cashLabelRef.BackgroundTransparency = 1
	cashLabelRef.Text = "Cash Boost: +0%"
	cashLabelRef.TextColor3 = Color3.fromRGB(200, 200, 220)
	cashLabelRef.Font = BUBBLE_FONT
	cashLabelRef.TextSize = 14
	cashLabelRef.ZIndex = 8
	cashLabelRef.Parent = cashSection

	-- Cash upgrade button
	cashCostBtnRef = Instance.new("TextButton")
	cashCostBtnRef.Name = "CashUpgradeBtn"
	cashCostBtnRef.Size = UDim2.new(0.85, 0, 0, 34)
	cashCostBtnRef.Position = UDim2.new(0.5, 0, 1, -10)
	cashCostBtnRef.AnchorPoint = Vector2.new(0.5, 1)
	cashCostBtnRef.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
	cashCostBtnRef.Text = "Upgrade +2% Cash — $1"
	cashCostBtnRef.TextColor3 = Color3.fromRGB(20, 20, 30)
	cashCostBtnRef.Font = BUBBLE_FONT
	cashCostBtnRef.TextSize = 15
	cashCostBtnRef.BorderSizePixel = 0
	cashCostBtnRef.ZIndex = 8
	cashCostBtnRef.Parent = cashSection
	local cbCorner = Instance.new("UICorner")
	cbCorner.CornerRadius = UDim.new(0, 10)
	cbCorner.Parent = cashCostBtnRef

	cashCostBtnRef.MouseButton1Click:Connect(function()
		UpgradeCashRequest:FireServer()
	end)

	-------------------------------------------------
	-- DESCRIPTION
	-------------------------------------------------
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -32, 0, 30)
	descLabel.Position = UDim2.new(0.5, 0, 1, -12)
	descLabel.AnchorPoint = Vector2.new(0.5, 1)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = "Luck = drop luck  |  Cash = streamer income"
	descLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
	descLabel.Font = Enum.Font.GothamBold
	descLabel.TextSize = 11
	descLabel.ZIndex = 7
	descLabel.Parent = modalFrame

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	-- When data updates (e.g. after upgrade), refresh modal if open
	HUDController.OnDataUpdated(function()
		if isOpen then refreshModal() end
	end)

	UpgradeLuckResult.OnClientEvent:Connect(function(result)
		if result.success and isOpen then
			refreshModal()
		end
	end)

	UpgradeCashResult.OnClientEvent:Connect(function(result)
		if result.success and isOpen then
			refreshModal()
		end
	end)

	OpenUpgradeStandGui.OnClientEvent:Connect(function()
		if isOpen then
			UpgradeStandController.Close()
		else
			UpgradeStandController.Open()
		end
	end)

	-- Start hidden; only show when player uses E at the Upgrade stand
	modalFrame.Visible = false
end

return UpgradeStandController
