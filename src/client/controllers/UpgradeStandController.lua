--[[
	UpgradeStandController.lua
	Luck upgrade UI at the Upgrade stand (beside Spin). Open with E at the green Upgrades stall.
	First upgrade $1,000, second $5,000.
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

local screenGui
local modalFrame
local overlay
local isOpen = false
local luckLabelRef
local costLabelRef
local upgradeBtnRef

local CARTOON_FONT = Enum.Font.Cartoon

local function refreshModal()
	if not luckLabelRef or not costLabelRef or not upgradeBtnRef then return end
	local luck = HUDController.Data.luck or 0
	local percent = math.floor(luck / 10)
	local cost = Economy.GetLuckUpgradeCost(luck)
	luckLabelRef.Text = ("Luck: %d  (+%d%% drop luck)"):format(luck, percent)
	costLabelRef.Text = ("$%s"):format(tostring(cost))
	upgradeBtnRef.Text = ("Upgrade +1 Luck — $%s"):format(tostring(cost))
	-- Disable if can't afford
	local canAfford = (HUDController.Data.cash or 0) >= cost
	upgradeBtnRef.BackgroundColor3 = canAfford and Color3.fromRGB(50, 180, 80) or Color3.fromRGB(80, 80, 90)
end

function UpgradeStandController.Open()
	if isOpen then return end
	isOpen = true
	if overlay then overlay.Visible = true end
	if modalFrame then
		modalFrame.Visible = true
		refreshModal()
	end
end

function UpgradeStandController.Close()
	if not isOpen then return end
	isOpen = false
	if overlay then overlay.Visible = false end
	if modalFrame then modalFrame.Visible = false end
end

function UpgradeStandController.Init()
	screenGui = UIHelper.CreateScreenGui("UpgradeStandGui", 5)
	screenGui.Parent = playerGui

	-- Full-screen overlay (click to close optional)
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 5
	overlay.Parent = screenGui

	-- Modal
	modalFrame = UIHelper.CreateRoundedFrame({
		Name = "UpgradeModal",
		Size = UDim2.new(0, 380, 0, 260),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = DesignConfig.Colors.BackgroundLight,
		CornerRadius = UDim.new(0, 24),
		StrokeColor = Color3.fromRGB(50, 180, 80),
		StrokeThickness = 3,
		ZIndex = 6,
		Parent = screenGui,
	})

	-- Title
	UIHelper.CreateLabel({
		Name = "Title",
		Size = UDim2.new(1, -40, 0, 36),
		Position = UDim2.new(0.5, 0, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "⬆ Upgrades",
		TextColor = Color3.fromRGB(255, 255, 255),
		Font = CARTOON_FONT,
		TextSize = 28,
		Parent = modalFrame,
	})

	-- Current luck
	luckLabelRef = UIHelper.CreateLabel({
		Name = "LuckLabel",
		Size = UDim2.new(1, -40, 0, 28),
		Position = UDim2.new(0.5, 0, 0, 68),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Luck: 0  (+0% drop luck)",
		TextColor = Color3.fromRGB(200, 180, 255),
		Font = CARTOON_FONT,
		TextSize = 20,
		Parent = modalFrame,
	})

	-- Cost for next upgrade
	costLabelRef = UIHelper.CreateLabel({
		Name = "CostLabel",
		Size = UDim2.new(1, -40, 0, 24),
		Position = UDim2.new(0.5, 0, 0, 100),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "$1,000",
		TextColor = DesignConfig.Colors.TextSecondary,
		Font = CARTOON_FONT,
		TextSize = 18,
		Parent = modalFrame,
	})

	-- Upgrade button
	upgradeBtnRef = Instance.new("TextButton")
	upgradeBtnRef.Name = "UpgradeBtn"
	upgradeBtnRef.Size = UDim2.new(1, -48, 0, 48)
	upgradeBtnRef.Position = UDim2.new(0.5, 0, 0, 138)
	upgradeBtnRef.AnchorPoint = Vector2.new(0.5, 0)
	upgradeBtnRef.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
	upgradeBtnRef.Text = "Upgrade +1 Luck — $1,000"
	upgradeBtnRef.TextColor3 = Color3.fromRGB(255, 255, 255)
	upgradeBtnRef.Font = CARTOON_FONT
	upgradeBtnRef.TextSize = 20
	upgradeBtnRef.BorderSizePixel = 0
	upgradeBtnRef.ZIndex = 7
	upgradeBtnRef.Parent = modalFrame
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 12)
	btnCorner.Parent = upgradeBtnRef
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(30, 120, 50)
	btnStroke.Thickness = 2
	btnStroke.Parent = upgradeBtnRef

	upgradeBtnRef.MouseButton1Click:Connect(function()
		UpgradeLuckRequest:FireServer()
	end)

	-- Close button
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
	closeBtn.ZIndex = 7
	closeBtn.Parent = modalFrame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function()
		UpgradeStandController.Close()
	end)

	-- When data updates (e.g. after upgrade), refresh modal if open
	HUDController.OnDataUpdated(function()
		if isOpen then refreshModal() end
	end)

	UpgradeLuckResult.OnClientEvent:Connect(function(result)
		if result.success and isOpen then
			refreshModal()
		end
	end)

	OpenUpgradeStandGui.OnClientEvent:Connect(function()
		UpgradeStandController.Open()
	end)

	-- Start hidden; only show when player uses E at the Upgrade stand
	modalFrame.Visible = false
	overlay.Visible = false
end

return UpgradeStandController
