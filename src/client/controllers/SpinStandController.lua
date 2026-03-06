--[[
	SpinStandController.lua
	Case Shop UI inspired by bright mobile "card shop" layouts.
	Each case row includes: case art, name, rarity, huge luck bonus, stock, price, open, buy 1, buy max.
	Global stock resets every 5 minutes with a countdown timer in the header.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local SpinStandController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenSpinStandGui = RemoteEvents:WaitForChild("OpenSpinStandGui")
local BuyCrateStock = RemoteEvents:WaitForChild("BuyCrateStock")
local BuyCrateResult = RemoteEvents:WaitForChild("BuyCrateResult")
local OpenOwnedCrate = RemoteEvents:WaitForChild("OpenOwnedCrate")
local GetCaseStock = RemoteEvents:WaitForChild("GetCaseStock")
local CaseStockUpdate = RemoteEvents:WaitForChild("CaseStockUpdate")

local screenGui
local modalFrame
local overlay
local isOpen = false

-------------------------------------------------
-- STYLE
-------------------------------------------------
local FONT        = Enum.Font.FredokaOne
local FONT_SUB    = Enum.Font.GothamBold
local MODAL_BG    = Color3.fromRGB(127, 194, 255)
local CARD_BG     = Color3.fromRGB(55, 55, 78)
local CARD_HOVER  = Color3.fromRGB(65, 65, 94)
local CARD_LOCKED = Color3.fromRGB(30, 28, 36)

local ROW_H       = 152
local IMAGE_SIZE  = 124
local MODAL_W     = 860
local MODAL_H     = 760

local RARITY_COLORS = {
	Common    = Color3.fromRGB(180, 180, 190),
	Uncommon  = Color3.fromRGB(100, 220, 120),
	Rare      = Color3.fromRGB(80, 170, 255),
	Epic      = Color3.fromRGB(180, 80, 255),
	Legendary = Color3.fromRGB(255, 180, 40),
	Mythic    = Color3.fromRGB(255, 80, 120),
	Godly     = Color3.fromRGB(255, 60, 60),
}

local cardRefs = {}
local stockData = {}
local restockSecondsLeft = 0
local restockTimerLabel = nil
local timerConn = nil
local buyCooldownUntilByCrate = {}
local noCashCooldownUntilByCrate = {}
local errorFlashTokenByCrate = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function getRebirthCount()
	return HUDController.Data.rebirthCount or 0
end

local function getOwnedCount(crateId)
	local owned = HUDController.Data.ownedCrates
	if not owned then return 0 end
	return owned[crateId] or owned[tostring(crateId)] or 0
end

local function formatCash(n)
	if n >= 1e9 then
		return "$" .. string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return "$" .. string.format("%.1fM", n / 1e6)
	end
	local s = tostring(math.floor(n))
	local out, len = "", #s
	for i = 1, len do
		out = out .. s:sub(i, i)
		if (len - i) % 3 == 0 and i < len then out = out .. "," end
	end
	return "$" .. out
end

local function luckString(bonus)
	return "+" .. math.floor(bonus * 100) .. "% Luck"
end

local function formatTime(seconds)
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

local function isTutorialActive()
	local ok, TutorialController = pcall(require, script.Parent.TutorialController)
	return ok and TutorialController.IsActive()
end

local function addStroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(0, 0, 0)
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function getThemeForCase(crateId, rarity)
	if crateId == 1 then
		return {
			base = Color3.fromRGB(137, 76, 213),
			top = Color3.fromRGB(174, 109, 247),
			bottom = Color3.fromRGB(98, 54, 163),
			luckText = Color3.fromRGB(255, 237, 115),
			price = Color3.fromRGB(116, 76, 209),
		}
	elseif crateId == 2 then
		return {
			base = Color3.fromRGB(150, 102, 54),
			top = Color3.fromRGB(212, 162, 94),
			bottom = Color3.fromRGB(114, 74, 43),
			luckText = Color3.fromRGB(255, 236, 116),
			price = Color3.fromRGB(218, 172, 67),
		}
	elseif crateId == 3 then
		return {
			base = Color3.fromRGB(48, 99, 170),
			top = Color3.fromRGB(92, 153, 230),
			bottom = Color3.fromRGB(42, 79, 146),
			luckText = Color3.fromRGB(255, 236, 113),
			price = Color3.fromRGB(56, 105, 196),
		}
	elseif crateId == 4 then
		return {
			base = Color3.fromRGB(52, 42, 112),
			top = Color3.fromRGB(89, 73, 170),
			bottom = Color3.fromRGB(35, 26, 88),
			luckText = Color3.fromRGB(199, 198, 255),
			price = Color3.fromRGB(63, 52, 146),
		}
	end

	if rarity == "Legendary" then
		return {
			base = Color3.fromRGB(92, 78, 44),
			top = Color3.fromRGB(188, 145, 64),
			bottom = Color3.fromRGB(69, 53, 32),
			luckText = Color3.fromRGB(255, 236, 113),
			price = Color3.fromRGB(202, 156, 62),
		}
	elseif rarity == "Epic" then
		return {
			base = Color3.fromRGB(90, 56, 143),
			top = Color3.fromRGB(156, 89, 225),
			bottom = Color3.fromRGB(65, 39, 102),
			luckText = Color3.fromRGB(255, 236, 113),
			price = Color3.fromRGB(130, 78, 194),
		}
	elseif rarity == "Mythic" or rarity == "Godly" then
		return {
			base = Color3.fromRGB(104, 44, 78),
			top = Color3.fromRGB(184, 72, 126),
			bottom = Color3.fromRGB(73, 31, 56),
			luckText = Color3.fromRGB(255, 225, 120),
			price = Color3.fromRGB(171, 66, 112),
		}
	end

	return {
		base = CARD_BG,
		top = Color3.fromRGB(98, 96, 131),
		bottom = Color3.fromRGB(52, 51, 73),
		luckText = Color3.fromRGB(255, 236, 113),
		price = Color3.fromRGB(76, 82, 138),
	}
end

local function getCardBaseColor(crateId)
	local tutorialLock = isTutorialActive() and crateId ~= 1
	if tutorialLock then
		return CARD_LOCKED
	end
	local refs = cardRefs[crateId]
	if refs and refs.baseColor then
		return refs.baseColor
	end
	return CARD_BG
end

local function showErrorToast(message)
	if not screenGui then return end
	local existing = screenGui:FindFirstChild("CaseShopErrorToast")
	if existing then
		existing:Destroy()
	end

	local toast = Instance.new("Frame")
	toast.Name = "CaseShopErrorToast"
	toast.Size = UDim2.new(0, 360, 0, 44)
	toast.Position = UDim2.new(0.5, 0, 1, -24)
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	toast.BorderSizePixel = 0
	toast.ZIndex = 20
	toast.Parent = screenGui
	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 10)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Text = tostring(message or "Could not buy case.")
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = FONT
	label.TextSize = 16
	label.TextWrapped = true
	label.ZIndex = 21
	label.Parent = toast
	addStroke(label, Color3.new(0, 0, 0), 1.2)

	task.delay(2, function()
		if not toast.Parent then return end
		TweenService:Create(toast, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		task.delay(0.28, function()
			if toast.Parent then toast:Destroy() end
		end)
	end)
end

-------------------------------------------------
-- UPDATE ALL CARDS (stock, owned count, button states)
-------------------------------------------------
local function updateAllCards()
	local tutorialLock = isTutorialActive()

	for crateId, refs in pairs(cardRefs) do
		local locked = tutorialLock and crateId ~= 1

		-- Lock overlay (tutorial only)
		if locked then
			refs.lockOverlay.Visible = true
			refs.card.BackgroundColor3 = CARD_LOCKED
			if refs.bgGradient then
				refs.bgGradient.Enabled = false
			end
		else
			refs.lockOverlay.Visible = false
			refs.card.BackgroundColor3 = refs.baseColor or CARD_BG
			if refs.bgGradient then
				refs.bgGradient.Enabled = true
			end
		end

		-- Stock label
		local currentStock = stockData[crateId] or stockData[tostring(crateId)] or 0
		local maxStock = Economy.CrateMaxStock[crateId] or 50
		if refs.stockLabel then
			refs.stockLabel.Text = "Stock: " .. currentStock .. "/" .. maxStock
			if currentStock <= 0 then
				refs.stockLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			elseif currentStock <= math.floor(maxStock * 0.25) then
				refs.stockLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
			else
				refs.stockLabel.TextColor3 = Color3.fromRGB(140, 255, 160)
			end
		end

		-- Owned count on open button
		local owned = getOwnedCount(crateId)
		if refs.openBtn then
			refs.openBtnText.Text = "OPEN (" .. owned .. ")"
			if owned > 0 and not locked then
				refs.openBtnText.TextColor3 = Color3.fromRGB(255, 255, 255)
			else
				refs.openBtnText.TextColor3 = Color3.fromRGB(180, 190, 200)
			end
			if not locked then
				refs.openBtn.BackgroundColor3 = Color3.fromRGB(81, 208, 94)
			else
				refs.openBtn.BackgroundColor3 = Color3.fromRGB(67, 77, 97)
			end
		end

		-- Buy buttons enabled state
		if not locked and currentStock > 0 then
			refs.buy1Btn.BackgroundColor3 = Color3.fromRGB(66, 166, 255)
			refs.buyMaxBtn.BackgroundColor3 = Color3.fromRGB(140, 98, 255)
		elseif not locked then
			refs.buy1Btn.BackgroundColor3 = Color3.fromRGB(67, 77, 97)
			refs.buyMaxBtn.BackgroundColor3 = Color3.fromRGB(67, 77, 97)
		end
	end
end

-------------------------------------------------
-- BUILD SINGLE CASE ROW
-------------------------------------------------
local function buildCaseRow(crateId, parent)
	local cost = Economy.CrateCosts[crateId]
	local luck = Economy.CrateLuckBonuses[crateId]
	local imageId = Economy.CrateImageIds[crateId]
	local name = Economy.CrateNames[crateId]
	local rarity = Economy.CrateRarities[crateId]
	local rarityColor = RARITY_COLORS[rarity] or RARITY_COLORS.Common
	local theme = getThemeForCase(crateId, rarity)

	local row = Instance.new("Frame")
	row.Name = "CaseRow_" .. crateId
	row.Size = UDim2.new(1, -20, 0, ROW_H)
	row.BackgroundColor3 = theme.base
	row.BorderSizePixel = 0
	row.LayoutOrder = crateId
	row.Parent = parent

	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 18)

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = Color3.fromRGB(255, 255, 255)
	rowStroke.Thickness = 3
	rowStroke.Transparency = 0.7
	rowStroke.Parent = row

	local rowGradient = Instance.new("UIGradient")
	rowGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.top),
		ColorSequenceKeypoint.new(1, theme.bottom),
	})
	rowGradient.Rotation = 15
	rowGradient.Parent = row

	-- Case image (left)
	local imgScale = crateId >= 13 and 1.3 or 1.0
	local displaySize = math.floor(IMAGE_SIZE * imgScale)

	local caseImage = Instance.new("ImageLabel")
	caseImage.Size = UDim2.new(0, displaySize, 0, displaySize)
	caseImage.Position = UDim2.new(0, 10 - math.floor((displaySize - IMAGE_SIZE) / 2), 0.5, 0)
	caseImage.AnchorPoint = Vector2.new(0, 0.5)
	caseImage.BackgroundTransparency = 1
	caseImage.Image = imageId or ""
	caseImage.ScaleType = Enum.ScaleType.Fit
	caseImage.ClipsDescendants = false
	caseImage.Parent = row

	local textX = IMAGE_SIZE + 28

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.56, 0, 0, 30)
	nameLabel.Position = UDim2.new(0, textX, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = FONT
	nameLabel.TextSize = 42
	nameLabel.TextScaled = true
	nameLabel.TextWrapped = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Top
	nameLabel.Parent = row
	addStroke(nameLabel, Color3.new(0, 0, 0), 2)

	-- Rarity label
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size = UDim2.new(0.56, 0, 0, 22)
	rarityLabel.Position = UDim2.new(0, textX, 0, 42)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = string.upper(tostring(rarity)) .. "!"
	rarityLabel.TextColor3 = rarityColor
	rarityLabel.Font = FONT
	rarityLabel.TextSize = 24
	rarityLabel.TextScaled = true
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.Parent = row
	addStroke(rarityLabel, Color3.new(0, 0, 0), 1.8)

	-- Huge luck line
	local luckLabel = Instance.new("TextLabel")
	luckLabel.Size = UDim2.new(0.56, 0, 0, 42)
	luckLabel.Position = UDim2.new(0, textX, 0, 62)
	luckLabel.BackgroundTransparency = 1
	luckLabel.Text = "+" .. math.floor(luck * 100) .. "% LUCK!"
	luckLabel.TextColor3 = theme.luckText
	luckLabel.Font = FONT
	luckLabel.TextSize = 42
	luckLabel.TextScaled = true
	luckLabel.TextXAlignment = Enum.TextXAlignment.Left
	luckLabel.Parent = row
	addStroke(luckLabel, Color3.new(0, 0, 0), 2.2)

	-- Stock label
	local stockLbl = Instance.new("TextLabel")
	stockLbl.Name = "StockLabel"
	stockLbl.Size = UDim2.new(0.38, 0, 0, 20)
	stockLbl.Position = UDim2.new(0, textX, 1, -30)
	stockLbl.BackgroundTransparency = 1
	stockLbl.Text = "Stock: --/--"
	stockLbl.TextColor3 = Color3.fromRGB(140, 255, 160)
	stockLbl.Font = FONT
	stockLbl.TextSize = 16
	stockLbl.TextScaled = true
	stockLbl.TextXAlignment = Enum.TextXAlignment.Left
	stockLbl.Parent = row
	addStroke(stockLbl, Color3.new(0, 0, 0), 1.6)

	-- Price capsule
	local pricePill = Instance.new("Frame")
	pricePill.Name = "PricePill"
	pricePill.Size = UDim2.new(0, 132, 0, 42)
	pricePill.Position = UDim2.new(1, -174, 1, -22)
	pricePill.AnchorPoint = Vector2.new(1, 1)
	pricePill.BackgroundColor3 = theme.price
	pricePill.BorderSizePixel = 0
	pricePill.Parent = row
	Instance.new("UICorner", pricePill).CornerRadius = UDim.new(1, 0)
	local priceStroke = Instance.new("UIStroke")
	priceStroke.Color = Color3.fromRGB(255, 255, 255)
	priceStroke.Thickness = 2
	priceStroke.Transparency = 0.35
	priceStroke.Parent = pricePill

	local costLabel = Instance.new("TextLabel")
	costLabel.Size = UDim2.new(1, -10, 1, -2)
	costLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	costLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = formatCash(cost)
	costLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	costLabel.Font = FONT
	costLabel.TextSize = 30
	costLabel.TextScaled = true
	costLabel.TextXAlignment = Enum.TextXAlignment.Center
	costLabel.Parent = pricePill
	addStroke(costLabel, Color3.new(0, 0, 0), 1.8)

	-- Right side: button cluster (matches reference)
	local btnX = -14
	local bounceTI = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local actionPanel = Instance.new("Frame")
	actionPanel.Name = "ActionPanel"
	actionPanel.Size = UDim2.new(0, 158, 0, 126)
	actionPanel.Position = UDim2.new(1, btnX, 0, 8)
	actionPanel.AnchorPoint = Vector2.new(1, 0)
	actionPanel.BackgroundColor3 = Color3.fromRGB(48, 37, 88)
	actionPanel.BorderSizePixel = 0
	actionPanel.Parent = row
	Instance.new("UICorner", actionPanel).CornerRadius = UDim.new(0, 16)
	local actionStroke = Instance.new("UIStroke")
	actionStroke.Color = Color3.fromRGB(255, 255, 255)
	actionStroke.Thickness = 1.5
	actionStroke.Transparency = 0.45
	actionStroke.Parent = actionPanel

	-- OPEN button (top)
	local openBtn = Instance.new("TextButton")
	openBtn.Name = "OpenBtn"
	openBtn.Size = UDim2.new(1, -12, 0, 46)
	openBtn.Position = UDim2.new(0.5, 0, 0, 8)
	openBtn.AnchorPoint = Vector2.new(0.5, 0)
	openBtn.BackgroundColor3 = Color3.fromRGB(81, 208, 94)
	openBtn.Text = ""
	openBtn.BorderSizePixel = 0
	openBtn.AutoButtonColor = false
	openBtn.Parent = actionPanel
	Instance.new("UICorner", openBtn).CornerRadius = UDim.new(1, 0)
	local openStroke = Instance.new("UIStroke")
	openStroke.Color = Color3.fromRGB(49, 144, 66)
	openStroke.Thickness = 2
	openStroke.Parent = openBtn
	local openGradient = Instance.new("UIGradient")
	openGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(104, 234, 118)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(76, 198, 101)),
	})
	openGradient.Rotation = 90
	openGradient.Parent = openBtn

	local openBtnText = Instance.new("TextLabel")
	openBtnText.Size = UDim2.new(1, 0, 1, 0)
	openBtnText.BackgroundTransparency = 1
	openBtnText.Text = "OPEN (0)"
	openBtnText.TextColor3 = Color3.new(1, 1, 1)
	openBtnText.Font = FONT
	openBtnText.TextSize = 15
	openBtnText.TextScaled = false
	openBtnText.TextXAlignment = Enum.TextXAlignment.Center
	openBtnText.TextYAlignment = Enum.TextYAlignment.Center
	openBtnText.Parent = openBtn
	addStroke(openBtnText, Color3.fromRGB(10, 50, 20), 1.5)

	openBtn.MouseEnter:Connect(function()
		TweenService:Create(openBtn, bounceTI, { Size = UDim2.new(1, -8, 0, 49) }):Play()
	end)
	openBtn.MouseLeave:Connect(function()
		TweenService:Create(openBtn, bounceTI, { Size = UDim2.new(1, -12, 0, 46) }):Play()
	end)

	openBtn.MouseButton1Click:Connect(function()
		if isTutorialActive() and crateId ~= 1 then return end
		local SpinController = require(script.Parent.SpinController)
		if SpinController.IsActive() then return end
		local owned = getOwnedCount(crateId)
		if owned <= 0 then
			openBtnText.Text = "NONE!"
			task.delay(1, function() updateAllCards() end)
			return
		end
		SpinController.SetCurrentCost(0)
		SpinController.SetCurrentCrateId(crateId)
		SpinController.SetOwnedCrateMode(true)
		SpinController.Show()
		SpinStandController.Close()
		OpenOwnedCrate:FireServer(crateId)
		SpinController.WaitForResult()
	end)

	-- BUY 1 button (bottom-left)
	local buy1Btn = Instance.new("TextButton")
	buy1Btn.Name = "Buy1Btn"
	buy1Btn.Size = UDim2.new(0, 68, 0, 64)
	buy1Btn.Position = UDim2.new(0, 8, 0, 58)
	buy1Btn.AnchorPoint = Vector2.new(0, 0)
	buy1Btn.BackgroundColor3 = Color3.fromRGB(66, 166, 255)
	buy1Btn.Text = ""
	buy1Btn.BorderSizePixel = 0
	buy1Btn.AutoButtonColor = false
	buy1Btn.Parent = actionPanel
	Instance.new("UICorner", buy1Btn).CornerRadius = UDim.new(0, 16)
	local buy1Stroke = Instance.new("UIStroke")
	buy1Stroke.Color = Color3.fromRGB(38, 118, 204)
	buy1Stroke.Thickness = 2
	buy1Stroke.Parent = buy1Btn

	local buy1Text = Instance.new("TextLabel")
	buy1Text.Size = UDim2.new(1, 0, 0, 24)
	buy1Text.Position = UDim2.new(0, 0, 0, 4)
	buy1Text.BackgroundTransparency = 1
	buy1Text.Text = "BUY 1"
	buy1Text.TextColor3 = Color3.new(1, 1, 1)
	buy1Text.Font = FONT
	buy1Text.TextSize = 14
	buy1Text.Parent = buy1Btn
	addStroke(buy1Text, Color3.new(0, 0, 0), 1)

	local buy1Icon = Instance.new("ImageLabel")
	buy1Icon.Size = UDim2.new(1, 0, 0, 30)
	buy1Icon.Position = UDim2.new(0.5, 0, 1, -32)
	buy1Icon.AnchorPoint = Vector2.new(0.5, 0)
	buy1Icon.BackgroundTransparency = 1
	buy1Icon.Image = "rbxthumb://type=Asset&id=18209599079&w=420&h=420"
	buy1Icon.ScaleType = Enum.ScaleType.Fit
	buy1Icon.ZIndex = 3
	buy1Icon.Parent = buy1Btn

	buy1Btn.MouseEnter:Connect(function()
		TweenService:Create(buy1Btn, bounceTI, { Size = UDim2.new(0, 72, 0, 68) }):Play()
	end)
	buy1Btn.MouseLeave:Connect(function()
		TweenService:Create(buy1Btn, bounceTI, { Size = UDim2.new(0, 68, 0, 64) }):Play()
	end)

	buy1Btn.MouseButton1Click:Connect(function()
		if isTutorialActive() and crateId ~= 1 then return end
		local now = os.clock()
		if now < (buyCooldownUntilByCrate[crateId] or 0) then return end
		if now < (noCashCooldownUntilByCrate[crateId] or 0) then return end
		buyCooldownUntilByCrate[crateId] = now + 0.25
		BuyCrateStock:FireServer(crateId, 1)
	end)

	-- BUY MAX button (bottom-right)
	local buyMaxBtn = Instance.new("TextButton")
	buyMaxBtn.Name = "BuyMaxBtn"
	buyMaxBtn.Size = UDim2.new(0, 68, 0, 64)
	buyMaxBtn.Position = UDim2.new(1, -8, 0, 58)
	buyMaxBtn.AnchorPoint = Vector2.new(1, 0)
	buyMaxBtn.BackgroundColor3 = Color3.fromRGB(140, 98, 255)
	buyMaxBtn.Text = ""
	buyMaxBtn.BorderSizePixel = 0
	buyMaxBtn.AutoButtonColor = false
	buyMaxBtn.Parent = actionPanel
	Instance.new("UICorner", buyMaxBtn).CornerRadius = UDim.new(0, 16)
	local buyMaxStroke = Instance.new("UIStroke")
	buyMaxStroke.Color = Color3.fromRGB(98, 62, 188)
	buyMaxStroke.Thickness = 2
	buyMaxStroke.Parent = buyMaxBtn

	local buyMaxText = Instance.new("TextLabel")
	buyMaxText.Size = UDim2.new(1, 0, 0, 24)
	buyMaxText.Position = UDim2.new(0, 0, 0, 4)
	buyMaxText.BackgroundTransparency = 1
	buyMaxText.Text = "MAX"
	buyMaxText.TextColor3 = Color3.new(1, 1, 1)
	buyMaxText.Font = FONT
	buyMaxText.TextSize = 14
	buyMaxText.Parent = buyMaxBtn
	addStroke(buyMaxText, Color3.new(0, 0, 0), 1)

	local buyMaxIcon = Instance.new("ImageLabel")
	buyMaxIcon.Size = UDim2.new(1, 0, 0, 30)
	buyMaxIcon.Position = UDim2.new(0.5, 0, 1, -32)
	buyMaxIcon.AnchorPoint = Vector2.new(0.5, 0)
	buyMaxIcon.BackgroundTransparency = 1
	buyMaxIcon.Image = "rbxthumb://type=Asset&id=89118380394851&w=420&h=420"
	buyMaxIcon.ScaleType = Enum.ScaleType.Fit
	buyMaxIcon.ZIndex = 3
	buyMaxIcon.Parent = buyMaxBtn

	buyMaxBtn.MouseEnter:Connect(function()
		TweenService:Create(buyMaxBtn, bounceTI, { Size = UDim2.new(0, 72, 0, 68) }):Play()
	end)
	buyMaxBtn.MouseLeave:Connect(function()
		TweenService:Create(buyMaxBtn, bounceTI, { Size = UDim2.new(0, 68, 0, 64) }):Play()
	end)

	buyMaxBtn.MouseButton1Click:Connect(function()
		if isTutorialActive() and crateId ~= 1 then return end
		local now = os.clock()
		if now < (buyCooldownUntilByCrate[crateId] or 0) then return end
		if now < (noCashCooldownUntilByCrate[crateId] or 0) then return end
		buyCooldownUntilByCrate[crateId] = now + 0.25
		local currentStock = stockData[crateId] or stockData[tostring(crateId)] or 0
		local costPer = Economy.CrateCosts[crateId] or 1
		local playerCash = HUDController.Data.cash or 0
		local maxAfford = math.floor(playerCash / costPer)
		local toBuy = math.min(currentStock, maxAfford)
		if toBuy <= 0 then toBuy = 1 end
		BuyCrateStock:FireServer(crateId, toBuy)
	end)

	-- Owned count label (below buttons)
	local ownedLabel = Instance.new("TextLabel")
	ownedLabel.Name = "OwnedLabel"
	ownedLabel.Size = UDim2.new(0, 148, 0, 16)
	ownedLabel.Position = UDim2.new(1, btnX, 1, -18)
	ownedLabel.AnchorPoint = Vector2.new(1, 0)
	ownedLabel.BackgroundTransparency = 1
	ownedLabel.Text = ""
	ownedLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	ownedLabel.Font = FONT_SUB
	ownedLabel.TextSize = 11
	ownedLabel.Parent = row

	-- Lock overlay
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.new(1, 0, 1, 0)
	lockOverlay.BackgroundColor3 = Color3.fromRGB(15, 12, 25)
	lockOverlay.BackgroundTransparency = 0.3
	lockOverlay.BorderSizePixel = 0
	lockOverlay.ZIndex = 5
	lockOverlay.Visible = false
	lockOverlay.Parent = row
	Instance.new("UICorner", lockOverlay).CornerRadius = UDim.new(0, 14)

	local lockIcon = Instance.new("TextLabel")
	lockIcon.Size = UDim2.new(0, 50, 0, 50)
	lockIcon.Position = UDim2.new(0.5, -30, 0.5, 0)
	lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	lockIcon.BackgroundTransparency = 1
	lockIcon.Text = "\u{1F512}"
	lockIcon.TextSize = 40
	lockIcon.Font = Enum.Font.SourceSans
	lockIcon.ZIndex = 6
	lockIcon.Parent = lockOverlay

	local lockText = Instance.new("TextLabel")
	lockText.Size = UDim2.new(0, 220, 0, 30)
	lockText.Position = UDim2.new(0.5, 30, 0.5, 0)
	lockText.AnchorPoint = Vector2.new(0.5, 0.5)
	lockText.BackgroundTransparency = 1
	lockText.Text = "Complete Tutorial First"
	lockText.TextColor3 = Color3.fromRGB(255, 180, 80)
	lockText.Font = FONT
	lockText.TextSize = 20
	lockText.ZIndex = 6
	lockText.Parent = lockOverlay
	addStroke(lockText, Color3.new(0, 0, 0), 1.5)

	cardRefs[crateId] = {
		card = row,
		baseColor = theme.base,
		bgGradient = rowGradient,
		buy1Btn = buy1Btn,
		buyMaxBtn = buyMaxBtn,
		openBtn = openBtn,
		openBtnText = openBtnText,
		stockLabel = stockLbl,
		lockOverlay = lockOverlay,
	}

	return row
end

-------------------------------------------------
-- RESTOCK TIMER
-------------------------------------------------
local function startTimerLoop()
	if timerConn then return end
	timerConn = RunService.Heartbeat:Connect(function(dt)
		restockSecondsLeft = math.max(0, restockSecondsLeft - dt)
		if restockTimerLabel then
			restockTimerLabel.Text = "\u{23F0} Restock: " .. formatTime(restockSecondsLeft)
		end
	end)
end

local function stopTimerLoop()
	if timerConn then timerConn:Disconnect(); timerConn = nil end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function SpinStandController.Open()
	local SpinController = require(script.Parent.SpinController)
	if isOpen or SpinController.IsVisible() or SpinController.IsActive() then return end
	isOpen = true
	GetCaseStock:FireServer()
	updateAllCards()
	startTimerLoop()
	overlay.Visible = true
	modalFrame.Visible = true
	UIHelper.ScaleIn(modalFrame, 0.35)
end

function SpinStandController.Close()
	if not isOpen then return end
	isOpen = false
	stopTimerLoop()
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

	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.3
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "CaseShopModal"
	modalFrame.Size = UDim2.new(0, MODAL_W, 0, MODAL_H)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = MODAL_BG
	modalFrame.BorderSizePixel = 0
	modalFrame.ZIndex = 2
	modalFrame.Visible = false
	modalFrame.Parent = screenGui

	Instance.new("UICorner", modalFrame).CornerRadius = UDim.new(0, 24)

	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = Color3.fromRGB(255, 255, 255)
	modalStroke.Thickness = 3
	modalStroke.Transparency = 0.35
	modalStroke.Parent = modalFrame

	local modalGradient = Instance.new("UIGradient")
	modalGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(157, 215, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(115, 175, 255)),
	})
	modalGradient.Rotation = 90
	modalGradient.Parent = modalFrame

	UIHelper.CreateShadow(modalFrame)
	UIHelper.MakeResponsiveModal(modalFrame, MODAL_W, MODAL_H)

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = modalFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0, 300, 0, 44)
	title.Position = UDim2.new(0, 26, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "CASE SHOP!"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = FONT
	title.TextSize = 40
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = header
	addStroke(title, Color3.new(0, 0, 0), 1.5)

	-- Restock timer (center of header)
	restockTimerLabel = Instance.new("TextLabel")
	restockTimerLabel.Size = UDim2.new(0, 230, 0, 34)
	restockTimerLabel.Position = UDim2.new(0.5, 0, 0, 14)
	restockTimerLabel.AnchorPoint = Vector2.new(0.5, 0)
	restockTimerLabel.BackgroundColor3 = Color3.fromRGB(54, 68, 125)
	restockTimerLabel.BackgroundTransparency = 0
	restockTimerLabel.Text = "\u{23F0} Restock: --:--"
	restockTimerLabel.TextColor3 = Color3.fromRGB(245, 233, 160)
	restockTimerLabel.Font = FONT
	restockTimerLabel.TextSize = 23
	restockTimerLabel.ZIndex = 3
	restockTimerLabel.Parent = header
	Instance.new("UICorner", restockTimerLabel).CornerRadius = UDim.new(1, 0)
	addStroke(restockTimerLabel, Color3.fromRGB(26, 35, 75), 1.8)

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 42, 0, 42)
	closeBtn.Position = UDim2.new(1, -14, 0, 8)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(248, 87, 87)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT
	closeBtn.TextSize = 24
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 5
	closeBtn.Parent = modalFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(255, 255, 255)
	closeStroke.Thickness = 2
	closeStroke.Parent = closeBtn
	addStroke(closeBtn, Color3.fromRGB(130, 35, 35), 1.8)

	local closeBounce = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 48, 0, 48), BackgroundColor3 = Color3.fromRGB(255, 107, 107) }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, closeBounce, { Size = UDim2.new(0, 42, 0, 42), BackgroundColor3 = Color3.fromRGB(248, 87, 87) }):Play()
	end)
	closeBtn.MouseButton1Click:Connect(function()
		SpinStandController.Close()
	end)

	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -30, 0, 1)
	divider.Position = UDim2.new(0.5, 0, 0, 64)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.BackgroundColor3 = Color3.fromRGB(65, 60, 80)
	divider.BackgroundTransparency = 0.2
	divider.BorderSizePixel = 0
	divider.ZIndex = 3
	divider.Parent = modalFrame

	-- Scrollable case list
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CaseScroll"
	scroll.Size = UDim2.new(1, -24, 1, -90)
	scroll.Position = UDim2.new(0.5, 0, 0, 78)
	scroll.AnchorPoint = Vector2.new(0.5, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 10
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scroll.ScrollBarImageColor3 = Color3.fromRGB(87, 120, 213)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 2
	scroll.Parent = modalFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 12)
	listLayout.Parent = scroll

	local topPad = Instance.new("UIPadding")
	topPad.PaddingTop = UDim.new(0, 4)
	topPad.PaddingBottom = UDim.new(0, 10)
	topPad.Parent = scroll

	for i = 1, Economy.TotalCases do
		buildCaseRow(i, scroll)
	end

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	-- Stock updates from server
	CaseStockUpdate.OnClientEvent:Connect(function(payload)
		if payload.stock then
			stockData = payload.stock
		end
		if payload.restockIn then
			restockSecondsLeft = payload.restockIn
		end
		updateAllCards()
	end)

	-- Also use GetCaseStock response (same remote, bidirectional)
	GetCaseStock.OnClientEvent:Connect(function(payload)
		if payload.stock then
			stockData = payload.stock
		end
		if payload.restockIn then
			restockSecondsLeft = payload.restockIn
		end
		updateAllCards()
	end)

	-- Buy result feedback
	BuyCrateResult.OnClientEvent:Connect(function(result)
		if result.success then
			if result.crateId then
				buyCooldownUntilByCrate[result.crateId] = 0
				noCashCooldownUntilByCrate[result.crateId] = 0
			end
			updateAllCards()
		else
			-- Flash error on the relevant card
			local crateId = result.crateId
			if crateId and cardRefs[crateId] then
				local refs = cardRefs[crateId]
				local flashToken = (errorFlashTokenByCrate[crateId] or 0) + 1
				errorFlashTokenByCrate[crateId] = flashToken
				refs.card.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
				task.delay(0.8, function()
					if errorFlashTokenByCrate[crateId] ~= flashToken then return end
					if refs.card then refs.card.BackgroundColor3 = getCardBaseColor(crateId) end
				end)
				local reason = string.lower(tostring(result.reason or ""))
				if string.find(reason, "not enough cash", 1, true) then
					noCashCooldownUntilByCrate[crateId] = os.clock() + 1.0
				end
			end
			showErrorToast(result.reason or "Could not buy case.")
		end
	end)

	-- Data updates (owned crates change)
	HUDController.OnDataUpdated(function()
		if isOpen then
			updateAllCards()
		end
	end)

	-- Server event to open shop (block re-entry while shop or spin animation is active)
	OpenSpinStandGui.OnClientEvent:Connect(function()
		local SpinController = require(script.Parent.SpinController)
		if isOpen or SpinController.IsVisible() or SpinController.IsActive() then return end
		SpinStandController.Open()
	end)
end

return SpinStandController
