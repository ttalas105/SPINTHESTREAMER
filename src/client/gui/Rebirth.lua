--[[
	gui/Rebirth.lua
	Rebirth GUI — modal for next rebirth info and confirm.
	Used by RebirthController; build the modal frame and label/button refs here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIHelper = require(script.Parent.Parent.controllers.UIHelper)

local FONT = Enum.Font.FredokaOne
local FONT2 = Enum.Font.GothamBold
local BG = Color3.fromRGB(22, 18, 42)

local RebirthGui = {}

function RebirthGui.Build(parent)
	local modal = Instance.new("Frame")
	modal.Name = "RebirthModal"
	modal.Size = UDim2.new(0, 400, 0, 380)
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.BackgroundColor3 = BG
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.Parent = parent

	Instance.new("UICorner", modal).CornerRadius = UDim.new(0, 20)
	local stroke = Instance.new("UIStroke", modal)
	stroke.Color = Color3.fromRGB(255, 200, 80)
	stroke.Thickness = 2

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -32, 0, 44)
	titleLabel.Position = UDim2.new(0, 16, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "⭐ Rebirth 1 ⭐"
	titleLabel.Font = FONT
	titleLabel.TextSize = 24
	titleLabel.TextColor3 = Color3.fromRGB(255, 220, 140)
	titleLabel.Parent = modal

	-- Coin bonus
	local coinBonusLabel = Instance.new("TextLabel")
	coinBonusLabel.Name = "CoinBonus"
	coinBonusLabel.Size = UDim2.new(1, -32, 0, 28)
	coinBonusLabel.Position = UDim2.new(0, 16, 0, 72)
	coinBonusLabel.BackgroundTransparency = 1
	coinBonusLabel.Text = "💰  +5% Coin Bonus"
	coinBonusLabel.Font = FONT2
	coinBonusLabel.TextSize = 18
	coinBonusLabel.TextColor3 = Color3.fromRGB(200, 255, 180)
	coinBonusLabel.Parent = modal

	-- Case unlock
	local caseUnlockLabel = Instance.new("TextLabel")
	caseUnlockLabel.Name = "CaseUnlock"
	caseUnlockLabel.Size = UDim2.new(1, -32, 0, 28)
	caseUnlockLabel.Position = UDim2.new(0, 16, 0, 104)
	caseUnlockLabel.BackgroundTransparency = 1
	caseUnlockLabel.Text = "📦 Unlock: Case 2"
	caseUnlockLabel.Font = FONT2
	caseUnlockLabel.TextSize = 16
	caseUnlockLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
	caseUnlockLabel.Parent = modal

	-- Cost
	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "Cost"
	costLabel.Size = UDim2.new(1, -32, 0, 24)
	costLabel.Position = UDim2.new(0, 16, 0, 140)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = "Cost: 1,000,000 coins"
	costLabel.Font = FONT2
	costLabel.TextSize = 16
	costLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	costLabel.Parent = modal

	-- Warning
	local warningLabel = Instance.new("TextLabel")
	warningLabel.Name = "Warning"
	warningLabel.Size = UDim2.new(1, -32, 0, 48)
	warningLabel.Position = UDim2.new(0, 16, 0, 172)
	warningLabel.BackgroundTransparency = 1
	warningLabel.Text = "Rebirth will reset your money and potions!"
	warningLabel.Font = FONT2
	warningLabel.TextSize = 14
	warningLabel.TextColor3 = Color3.fromRGB(255, 180, 120)
	warningLabel.TextWrapped = true
	warningLabel.Parent = modal

	-- Maxed message (hidden by default)
	local maxedLabel = Instance.new("TextLabel")
	maxedLabel.Name = "Maxed"
	maxedLabel.Size = UDim2.new(1, -32, 0, 60)
	maxedLabel.Position = UDim2.new(0, 16, 0, 172)
	maxedLabel.BackgroundTransparency = 1
	maxedLabel.Text = "You've reached the highest rebirth!"
	maxedLabel.Font = FONT2
	maxedLabel.TextSize = 16
	maxedLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
	maxedLabel.TextWrapped = true
	maxedLabel.Visible = false
	maxedLabel.Parent = modal

	-- Confirm button
	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name = "Confirm"
	confirmBtn.Size = UDim2.new(1, -32, 0, 48)
	confirmBtn.Position = UDim2.new(0, 16, 1, -64)
	confirmBtn.AnchorPoint = Vector2.new(0, 1)
	confirmBtn.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
	confirmBtn.BorderSizePixel = 0
	confirmBtn.Text = "REBIRTH"
	confirmBtn.Font = FONT
	confirmBtn.TextSize = 20
	confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 12)
	confirmBtn.Parent = modal

	UIHelper.MakeResponsiveModal(modal, 400, 380)

	local refs = {
		modal = modal,
		titleLabel = titleLabel,
		coinBonusLabel = coinBonusLabel,
		caseUnlockLabel = caseUnlockLabel,
		costLabel = costLabel,
		warningLabel = warningLabel,
		maxedLabel = maxedLabel,
		confirmBtn = confirmBtn,
	}
	return modal, refs
end

return RebirthGui
