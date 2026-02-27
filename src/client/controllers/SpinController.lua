--[[
	SpinController.lua
	CS:GO-style horizontal scrolling case opening animation.
	Vibrant, bubbly, kid-friendly UI with clean result display.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local GemCases = require(ReplicatedStorage.Shared.Config.GemCases)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)
local UISounds = require(script.Parent.UISounds)

local SpinController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SpinRequest = RemoteEvents:WaitForChild("SpinRequest")
local SpinResult = RemoteEvents:WaitForChild("SpinResult")
local MythicAlert = RemoteEvents:WaitForChild("MythicAlert")

-------------------------------------------------
-- STYLE CONSTANTS
-------------------------------------------------
local FONT        = Enum.Font.FredokaOne
local FONT_SUB    = Enum.Font.GothamBold
local CONTAINER_BG_TOP = Color3.fromRGB(30, 18, 60)
local CONTAINER_BG_BOT = Color3.fromRGB(12, 8, 28)
local CONTAINER_STROKE = Color3.fromRGB(140, 80, 255)
local CAROUSEL_BG      = Color3.fromRGB(10, 10, 20)
local CAROUSEL_STROKE  = Color3.fromRGB(100, 70, 180)
local SELECTOR_COLOR   = Color3.fromRGB(255, 60, 80)
local BTN_GREEN_TOP    = Color3.fromRGB(100, 255, 150)
local BTN_GREEN_BOT    = Color3.fromRGB(40, 200, 80)

-- UI references
local screenGui
local spinContainer
local carouselFrame
local carouselContainer
local resultFrame
local spinButton
local skipButton
local isSpinning = false
local animationDone = false

local currentSpinCost = Economy.SpinCost
local currentCrateId = nil

local skipRequested = false
local currentAnimConnection = nil
local preSpinConnection = nil

local autoSpinEnabled = false
local autoSpinButton = nil

local spinGeneration = 0
local onSpinResult = nil
local isOwnedCrateOpen = false
local currentGemCaseId = nil

-- Carousel items
local ITEM_WIDTH = 130
local ITEM_HEIGHT = 155
local ITEM_GAP = 8
local ITEM_STEP = ITEM_WIDTH + ITEM_GAP
local items = {}
local currentTargetIndex = 1

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function formatCash(n)
	local s = tostring(math.floor(n))
	local out, len = "", #s
	for i = 1, len do
		out = out .. s:sub(i, i)
		if (len - i) % 3 == 0 and i < len then out = out .. "," end
	end
	return "$" .. out
end

local function formatOdds(odds)
	if not odds or odds < 1 then return "" end
	local s = tostring(math.floor(odds))
	local formatted, len = "", #s
	for i = 1, len do
		formatted = formatted .. string.sub(s, i, i)
		if (len - i) % 3 == 0 and i < len then formatted = formatted .. "," end
	end
	return "1 in " .. formatted
end

local function addOutlinedText(parent, props)
	local label = Instance.new("TextLabel")
	label.Name = props.Name or "Label"
	label.Size = props.Size or UDim2.new(1, 0, 0, 24)
	label.Position = props.Position or UDim2.new(0, 0, 0, 0)
	label.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	label.BackgroundTransparency = 1
	label.Text = props.Text or ""
	label.TextColor3 = props.Color or Color3.new(1, 1, 1)
	label.Font = props.Font or FONT
	label.TextSize = props.TextSize or 20
	label.TextScaled = props.TextScaled or false
	label.TextWrapped = true
	label.RichText = props.RichText or false
	label.ZIndex = props.ZIndex or 1
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = props.StrokeColor or Color3.fromRGB(0, 0, 0)
	stroke.Thickness = props.StrokeThickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return label
end

-------------------------------------------------
-- BUILD CAROUSEL
-------------------------------------------------

local function buildCarousel(parent)
	carouselFrame = Instance.new("Frame")
	carouselFrame.Name = "CarouselFrame"
	carouselFrame.Size = UDim2.new(0.92, 0, 0, ITEM_HEIGHT + 30)
	carouselFrame.Position = UDim2.new(0.5, 0, 0.44, 0)
	carouselFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	carouselFrame.BackgroundColor3 = CAROUSEL_BG
	carouselFrame.BorderSizePixel = 0
	carouselFrame.ClipsDescendants = true
	carouselFrame.Parent = parent

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 16)
	frameCorner.Parent = carouselFrame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Name = "BorderStroke"
	frameStroke.Color = CAROUSEL_STROKE
	frameStroke.Thickness = 1.5
	frameStroke.Transparency = 0.25
	frameStroke.Parent = carouselFrame

	-- Rainbow accent line across the top
	local topLine = Instance.new("Frame")
	topLine.Name = "TopLine"
	topLine.Size = UDim2.new(1, 0, 0, 4)
	topLine.Position = UDim2.new(0, 0, 0, 0)
	topLine.BackgroundColor3 = Color3.new(1, 1, 1)
	topLine.BorderSizePixel = 0
	topLine.ZIndex = 6
	topLine.Parent = carouselFrame
	local topGrad = Instance.new("UIGradient")
	topGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 120)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 150)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 150, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 80, 255)),
	})
	topGrad.Parent = topLine

	-- Inner container (wide strip that slides)
	carouselContainer = Instance.new("Frame")
	carouselContainer.Name = "CarouselContainer"
	carouselContainer.BackgroundTransparency = 1
	carouselContainer.BorderSizePixel = 0
	carouselContainer.Position = UDim2.new(0, 0, 0, 0)
	carouselContainer.AnchorPoint = Vector2.new(0, 0)
	carouselContainer.Parent = carouselFrame

	-- Build shuffled item strip
	local allStreamers = {}
	for _ = 1, 12 do
		for _, streamer in ipairs(Streamers.List) do
			table.insert(allStreamers, streamer)
		end
	end
	for i = #allStreamers, 2, -1 do
		local j = math.random(1, i)
		allStreamers[i], allStreamers[j] = allStreamers[j], allStreamers[i]
	end

	local COSMETIC_EFFECT_CHANCE = 0.15
	local allCosmetics = {}
	for ci = 1, #allStreamers do
		allCosmetics[ci] = math.random() < COSMETIC_EFFECT_CHANCE
			and Effects.List[math.random(1, #Effects.List)] or nil
	end

	items = {}
	for i, streamer in ipairs(allStreamers) do
		local eff = allCosmetics[i]
		local rarityColor = Rarities.ByName[streamer.rarity] and Rarities.ByName[streamer.rarity].color or Color3.fromRGB(100, 100, 100)
		local bgColor = rarityColor
		if eff then
			bgColor = Color3.fromRGB(
				math.floor(bgColor.R * 255 * 0.5 + eff.color.R * 255 * 0.5),
				math.floor(bgColor.G * 255 * 0.5 + eff.color.G * 255 * 0.5),
				math.floor(bgColor.B * 255 * 0.5 + eff.color.B * 255 * 0.5)
			)
		end

		local card = Instance.new("Frame")
		card.Name = "Card_" .. i
		card.Size = UDim2.new(0, ITEM_WIDTH, 0, ITEM_HEIGHT)
		card.Position = UDim2.new(0, (i - 1) * ITEM_STEP, 0.5, 0)
		card.AnchorPoint = Vector2.new(0, 0.5)
		card.BackgroundColor3 = bgColor
		card.BorderSizePixel = 0
		card.Parent = carouselContainer

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 12)
		cardCorner.Parent = card

		local cardStroke = Instance.new("UIStroke")
		cardStroke.Name = "CardStroke"
		cardStroke.Color = rarityColor
		cardStroke.Thickness = 2
		cardStroke.Transparency = 0.4
		cardStroke.Parent = card

		-- Depth gradient
		local cardGrad = Instance.new("UIGradient")
		cardGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 50, 70)),
		})
		cardGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.65),
			NumberSequenceKeypoint.new(1, 0),
		})
		cardGrad.Rotation = 90
		cardGrad.Parent = card

		-- Effect badge
		if eff then
			local badge = Instance.new("TextLabel")
			badge.Name = "EffectTag"
			badge.Size = UDim2.new(1, -6, 0, 18)
			badge.Position = UDim2.new(0.5, 0, 0, 5)
			badge.AnchorPoint = Vector2.new(0.5, 0)
			badge.BackgroundTransparency = 1
			badge.Text = eff.prefix:upper()
			badge.TextColor3 = eff.color
			badge.Font = FONT
			badge.TextSize = 12
			badge.TextScaled = false
			badge.Parent = card
			local effStroke = Instance.new("UIStroke")
			effStroke.Color = Color3.fromRGB(0, 0, 0)
			effStroke.Thickness = 1
			effStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			effStroke.Parent = badge

			local star = Instance.new("TextLabel")
			star.Name = "Star"
			star.Size = UDim2.new(0, 20, 0, 20)
			star.Position = UDim2.new(1, -6, 0, 4)
			star.AnchorPoint = Vector2.new(1, 0)
			star.BackgroundTransparency = 1
			star.Text = "\u{2728}"
			star.TextSize = 14
			star.Font = Enum.Font.SourceSans
			star.Parent = card
		end

		-- Streamer name
		local nameY = eff and 0.18 or 0.10
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "StreamerName"
		nameLabel.Size = UDim2.new(1, -10, 0, 50)
		nameLabel.Position = UDim2.new(0.5, 0, nameY, 0)
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = eff and (eff.prefix .. " " .. streamer.displayName) or streamer.displayName
		nameLabel.TextColor3 = eff and eff.color or Color3.new(1, 1, 1)
		nameLabel.Font = FONT
		nameLabel.TextSize = 16
		nameLabel.TextScaled = false
		nameLabel.TextWrapped = true
		nameLabel.Parent = card
		local nameStroke = Instance.new("UIStroke")
		nameStroke.Color = Color3.fromRGB(0, 0, 0)
		nameStroke.Thickness = 1.5
		nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		nameStroke.Parent = nameLabel

		-- Rarity label
		local rarLabel = Instance.new("TextLabel")
		rarLabel.Name = "RarityTag"
		rarLabel.Size = UDim2.new(1, -10, 0, 20)
		rarLabel.Position = UDim2.new(0.5, 0, 1, -30)
		rarLabel.AnchorPoint = Vector2.new(0.5, 0)
		rarLabel.BackgroundTransparency = 1
		rarLabel.Text = streamer.rarity:upper()
		rarLabel.TextColor3 = rarityColor
		rarLabel.Font = FONT
		rarLabel.TextSize = 13
		rarLabel.TextScaled = false
		rarLabel.Parent = card
		local rarStroke = Instance.new("UIStroke")
		rarStroke.Color = Color3.fromRGB(0, 0, 0)
		rarStroke.Thickness = 1
		rarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		rarStroke.Parent = rarLabel

		items[i] = {
			frame = card,
			streamer = streamer,
			effect = eff,
		}
	end

	carouselContainer.Size = UDim2.new(0, #items * ITEM_STEP, 1, 0)

	-- Center selector line
	local selectorLine = Instance.new("Frame")
	selectorLine.Name = "SelectorLine"
	selectorLine.Size = UDim2.new(0, 3, 1, 10)
	selectorLine.Position = UDim2.new(0.5, 0, 0.5, 0)
	selectorLine.AnchorPoint = Vector2.new(0.5, 0.5)
	selectorLine.BackgroundColor3 = SELECTOR_COLOR
	selectorLine.BorderSizePixel = 0
	selectorLine.ZIndex = 10
	selectorLine.Parent = carouselFrame
	local selGlow = Instance.new("UIStroke")
	selGlow.Color = Color3.fromRGB(255, 120, 120)
	selGlow.Thickness = 2
	selGlow.Transparency = 0.3
	selGlow.Parent = selectorLine

	-- Triangles
	for _, info in ipairs({
		{ name = "TopArrow", text = "\u{25BC}", pos = UDim2.new(0.5, 0, 0, -2), anchor = Vector2.new(0.5, 0) },
		{ name = "BotArrow", text = "\u{25B2}", pos = UDim2.new(0.5, 0, 1, 2),  anchor = Vector2.new(0.5, 1) },
	}) do
		local arrow = Instance.new("TextLabel")
		arrow.Name = info.name
		arrow.Size = UDim2.new(0, 30, 0, 22)
		arrow.Position = info.pos
		arrow.AnchorPoint = info.anchor
		arrow.BackgroundTransparency = 1
		arrow.Text = info.text
		arrow.TextColor3 = SELECTOR_COLOR
		arrow.Font = Enum.Font.GothamBold
		arrow.TextSize = 22
		arrow.ZIndex = 10
		arrow.Parent = carouselFrame
	end

	-- Dark gradient edges
	for _, side in ipairs({"Left", "Right"}) do
		local grad = Instance.new("Frame")
		grad.Name = "Fade" .. side
		grad.Size = UDim2.new(0, 100, 1, 0)
		grad.Position = side == "Left" and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -100, 0, 0)
		grad.BackgroundColor3 = CAROUSEL_BG
		grad.BorderSizePixel = 0
		grad.ZIndex = 8
		grad.Parent = carouselFrame
		local uiGrad = Instance.new("UIGradient")
		uiGrad.Transparency = side == "Left"
			and NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
			or  NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)})
		uiGrad.Parent = grad
	end

	return carouselFrame
end

-------------------------------------------------
-- RESULT DISPLAY
-------------------------------------------------

local function buildResultDisplay(parent)
	resultFrame = UIHelper.CreateRoundedFrame({
		Name = "ResultFrame",
		Size = UDim2.new(0.7, 0, 0, 125),
		Position = UDim2.new(0.5, 0, 0.78, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = DesignConfig.Colors.BackgroundLight,
		CornerRadius = DesignConfig.Layout.PanelCorner,
		StrokeColor = Color3.fromRGB(100, 100, 140),
		Parent = parent,
	})
	resultFrame.Visible = false

	UIHelper.CreateLabel({
		Name = "ResultLabel",
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "YOU GOT:",
		TextColor = DesignConfig.Colors.TextSecondary,
		Font = DesignConfig.Fonts.Secondary,
		TextSize = DesignConfig.FontSizes.Caption,
		Parent = resultFrame,
	})

	UIHelper.CreateLabel({
		Name = "StreamerName",
		Size = UDim2.new(1, -20, 0, 35),
		Position = UDim2.new(0.5, 0, 0, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		TextColor = DesignConfig.Colors.White,
		Font = DesignConfig.Fonts.Accent,
		TextSize = DesignConfig.FontSizes.Header,
		Parent = resultFrame,
	})

	UIHelper.CreateLabel({
		Name = "RarityLabel",
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.new(0.5, 0, 0, 58),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		TextColor = Color3.fromRGB(170, 170, 170),
		Font = DesignConfig.Fonts.Primary,
		TextSize = DesignConfig.FontSizes.Caption,
		Parent = resultFrame,
	})

	UIHelper.CreateLabel({
		Name = "OddsLabel",
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.new(0.5, 0, 0, 76),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "",
		TextColor = DesignConfig.Colors.Accent,
		Font = DesignConfig.Fonts.Secondary,
		TextSize = DesignConfig.FontSizes.Caption,
		Parent = resultFrame,
	})

	UIHelper.CreateLabel({
		Name = "InventoryNotice",
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.new(0.5, 0, 0, 96),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Added to inventory!",
		TextColor = DesignConfig.Colors.Accent,
		Font = DesignConfig.Fonts.Secondary,
		TextSize = DesignConfig.FontSizes.Small,
		Parent = resultFrame,
	})

	return resultFrame
end

-------------------------------------------------
-- SPIN ANIMATION
-------------------------------------------------

local function easeOutQuint(t)
	local t1 = 1 - t
	return 1 - t1 * t1 * t1 * t1 * t1
end

local function stopPreSpinVisual()
	if preSpinConnection then
		pcall(function() preSpinConnection:Disconnect() end)
		preSpinConnection = nil
	end
end

local function startPreSpinVisual()
	if not carouselFrame or not carouselContainer or #items <= 0 then return end
	stopPreSpinVisual()

	carouselFrame.Visible = true

	local frameWidthScreen = carouselFrame.AbsoluteSize.X
	if frameWidthScreen == 0 then frameWidthScreen = 700 end
	local uiScale = UIHelper.GetScale()
	if uiScale <= 0 then uiScale = 1 end
	local frameWidth = frameWidthScreen / uiScale
	local halfFrame = frameWidth / 2

	local centerIndex = math.max(1, math.floor(#items * 0.35))
	local centerX = (centerIndex - 1) * ITEM_STEP + ITEM_WIDTH / 2
	local baseX = halfFrame - centerX
	local stripLength = math.max(1, #items * ITEM_STEP)
	local offset = 0
	local PRESPIN_SPEED = 560

	carouselContainer.Position = UDim2.new(0, baseX, 0, 0)

	preSpinConnection = RunService.RenderStepped:Connect(function(dt)
		offset = (offset + PRESPIN_SPEED * dt) % stripLength
		carouselContainer.Position = UDim2.new(0, baseX - offset, 0, 0)
	end)
end

local function applyEffectToCard(cardIndex, effectName)
	local entry = items[cardIndex]
	if not entry then return end
	local card = entry.frame
	local streamer = entry.streamer
	if not card or not streamer then return end

	local effectInfo = effectName and Effects.ByName[effectName] or nil
	local rarityColor = Rarities.ByName[streamer.rarity] and Rarities.ByName[streamer.rarity].color or Color3.fromRGB(100, 100, 100)

	entry.effect = effectInfo

	if effectInfo then
		card.BackgroundColor3 = Color3.fromRGB(
			math.floor(rarityColor.R * 255 * 0.5 + effectInfo.color.R * 255 * 0.5),
			math.floor(rarityColor.G * 255 * 0.5 + effectInfo.color.G * 255 * 0.5),
			math.floor(rarityColor.B * 255 * 0.5 + effectInfo.color.B * 255 * 0.5)
		)
	else
		card.BackgroundColor3 = rarityColor
	end

	local existingBadge = card:FindFirstChild("EffectTag")
	if effectInfo then
		if not existingBadge then
			existingBadge = Instance.new("TextLabel")
			existingBadge.Name = "EffectTag"
			existingBadge.Size = UDim2.new(1, -6, 0, 18)
			existingBadge.Position = UDim2.new(0.5, 0, 0, 5)
			existingBadge.AnchorPoint = Vector2.new(0.5, 0)
			existingBadge.BackgroundTransparency = 1
			existingBadge.Font = FONT
			existingBadge.TextSize = 12
			existingBadge.TextScaled = false
			existingBadge.Parent = card
			local effS = Instance.new("UIStroke")
			effS.Color = Color3.fromRGB(0, 0, 0)
			effS.Thickness = 1
			effS.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			effS.Parent = existingBadge
		end
		existingBadge.Text = effectInfo.prefix:upper()
		existingBadge.TextColor3 = effectInfo.color
		existingBadge.Visible = true
	elseif existingBadge then
		existingBadge.Visible = false
	end

	local existingStar = card:FindFirstChild("Star")
	if effectInfo then
		if not existingStar then
			existingStar = Instance.new("TextLabel")
			existingStar.Name = "Star"
			existingStar.Size = UDim2.new(0, 20, 0, 20)
			existingStar.Position = UDim2.new(1, -6, 0, 4)
			existingStar.AnchorPoint = Vector2.new(1, 0)
			existingStar.BackgroundTransparency = 1
			existingStar.Text = "\u{2728}"
			existingStar.TextSize = 14
			existingStar.Font = Enum.Font.SourceSans
			existingStar.Parent = card
		end
		existingStar.Visible = true
	elseif existingStar then
		existingStar.Visible = false
	end

	local nameLabel = card:FindFirstChild("StreamerName")
	if nameLabel then
		if effectInfo then
			nameLabel.Text = effectInfo.prefix .. " " .. streamer.displayName
			nameLabel.TextColor3 = effectInfo.color
			nameLabel.Position = UDim2.new(0.5, 0, 0.18, 0)
		else
			nameLabel.Text = streamer.displayName
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
			nameLabel.Position = UDim2.new(0.5, 0, 0.10, 0)
		end
	end
end

local function getForcedGemCaseEffect()
	if not currentGemCaseId then return nil end
	local caseData = GemCases.ById[currentGemCaseId]
	return caseData and caseData.effect or nil
end

local function playSpinAnimation(resultData, callback)
	if not carouselContainer or not carouselFrame then return end
	stopPreSpinVisual()

	local targetStreamerId = resultData.streamerId or resultData.id
	local occurrences = {}
	for i, item in ipairs(items) do
		if item.streamer.id == targetStreamerId then
			table.insert(occurrences, i)
		end
	end
	if #occurrences == 0 then
		for i, item in ipairs(items) do
			if item.streamer.displayName == resultData.displayName then
				table.insert(occurrences, i)
			end
		end
	end

	local targetIndex
	if #occurrences >= 1 then
		-- Keep enough cards to the right of the winner so the reel never
		-- reaches end-of-strip black space during the stop.
		local rightSafetyCards = 10
		local maxSafeIndex = math.max(1, #items - rightSafetyCards)
		for i = #occurrences, 1, -1 do
			if occurrences[i] <= maxSafeIndex then
				targetIndex = occurrences[i]
				break
			end
		end
		targetIndex = targetIndex or occurrences[1]
	else
		targetIndex = 1
	end
	currentTargetIndex = targetIndex

	applyEffectToCard(targetIndex, resultData.effect)

	local nearMissOffsets = { -2, -1, 1, 2 }
	for _, offset in ipairs(nearMissOffsets) do
		local adjIdx = targetIndex + offset
		if adjIdx >= 1 and adjIdx <= #items and adjIdx ~= targetIndex then
			if math.random() < 0.40 then
				local randEff = Effects.List[math.random(1, #Effects.List)]
				applyEffectToCard(adjIdx, randEff.name)
			end
		end
	end

	RunService.RenderStepped:Wait()
	local frameWidthScreen = carouselFrame.AbsoluteSize.X
	if frameWidthScreen == 0 then frameWidthScreen = 700 end
	local uiScale = UIHelper.GetScale()
	if uiScale <= 0 then uiScale = 1 end
	local frameWidth = frameWidthScreen / uiScale

	local halfFrame = frameWidth / 2
	local targetCenterX = (targetIndex - 1) * ITEM_STEP + ITEM_WIDTH / 2
	local endX = halfFrame - targetCenterX

	local setWidth = #Streamers.List * ITEM_STEP
	if setWidth <= 0 then setWidth = ITEM_STEP end

	-- Start from the currently visible offset, but never outside the
	-- container's valid on-screen range (prevents black sections at start).
	local containerWidth = math.max(1, #items * ITEM_STEP)
	local minVisibleX = frameWidth - containerWidth
	local maxVisibleX = 0
	local startX = maxVisibleX

	-- Keep enough travel distance for a satisfying spin while staying visible.
	local minTravel = setWidth * 2.8
	while (startX - endX) < minTravel and (startX + setWidth) <= maxVisibleX do
		startX = startX + setWidth
	end

	local totalDist = startX - endX
	local DURATION = 5.5
	local startTime = tick()

	carouselContainer.Position = UDim2.new(0, startX, 0, 0)

	local done = false
	skipRequested = false
	local lastTickIndex = -1

	if skipButton then skipButton.Visible = true end

	if currentAnimConnection then
		pcall(function() currentAnimConnection:Disconnect() end)
		currentAnimConnection = nil
	end

	local function getCardUnderSelector(containerX)
		local selectorWorldX = halfFrame - containerX
		local idx = math.floor(selectorWorldX / ITEM_STEP) + 1
		return math.clamp(idx, 1, #items)
	end

	local function finishAnimation()
		carouselContainer.Position = UDim2.new(0, endX, 0, 0)
		if skipButton then skipButton.Visible = false end

		UISounds.PlaySpinWin()

		local winCard = items[targetIndex] and items[targetIndex].frame
		if winCard then
			local glow = winCard:FindFirstChild("WinGlow")
			if not glow then
				glow = Instance.new("UIStroke")
				glow.Name = "WinGlow"
				glow.Parent = winCard
			end
			local rarCol = Rarities.ByName[items[targetIndex].streamer.rarity]
			local glowColor = rarCol and rarCol.color or Color3.fromRGB(255, 255, 255)
			glow.Color = glowColor
			glow.Thickness = 0
			glow.Transparency = 0
			TweenService:Create(glow, TweenInfo.new(0.35, Enum.EasingStyle.Back), {
				Thickness = 5,
			}):Play()
		end

		task.spawn(function()
			task.wait(0.6)
			if callback then callback() end
		end)
	end

	currentAnimConnection = RunService.RenderStepped:Connect(function()
		if skipRequested and not done then
			done = true
			currentAnimConnection:Disconnect()
			currentAnimConnection = nil
			local settleTween = TweenService:Create(carouselContainer, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, endX, 0, 0),
			})
			settleTween:Play()
			settleTween.Completed:Connect(function()
				finishAnimation()
			end)
			return
		end

		local t = (tick() - startTime) / DURATION
		if t >= 1 then t = 1 end
		local eased = easeOutQuint(t)
		local currentX = startX - totalDist * eased
		carouselContainer.Position = UDim2.new(0, currentX, 0, 0)

		local cardIdx = getCardUnderSelector(currentX)
		if cardIdx ~= lastTickIndex then
			lastTickIndex = cardIdx
			local pitch = 0.85 + 0.35 * t
			UISounds.PlaySpinTick(pitch)
		end

		if t >= 1 and not done then
			done = true
			currentAnimConnection:Disconnect()
			currentAnimConnection = nil
			finishAnimation()
		end
	end)
end

local function showResult(data)
	local rarityInfo = Rarities.ByName[data.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(170, 170, 170)
	local effectInfo = data.effect and Effects.ByName[data.effect] or nil
	local displayColor = effectInfo and effectInfo.color or rarityColor

	local nameLabel = resultFrame:FindFirstChild("StreamerName")
	local rarityLabel = resultFrame:FindFirstChild("RarityLabel")
	local resultLabel = resultFrame:FindFirstChild("ResultLabel")

	if resultLabel then
		resultLabel.Text = "YOU RECEIVED:"
		resultLabel.TextColor3 = displayColor
	end
	if nameLabel then
		local fullName = data.displayName or "Unknown"
		if effectInfo and not string.find(fullName, effectInfo.prefix, 1, true) then
			fullName = effectInfo.prefix .. " " .. fullName
		end
		nameLabel.Text = fullName
		nameLabel.TextColor3 = displayColor
	end
	if rarityLabel then
		local rarityText = (data.rarity or "Common"):upper()
		if effectInfo then rarityText = effectInfo.prefix:upper() .. " " .. rarityText end
		rarityLabel.Text = rarityText
		rarityLabel.TextColor3 = displayColor
	end

	local oddsText = data.odds and formatOdds(data.odds) or ""
	local oddsLabel = resultFrame:FindFirstChild("OddsLabel")
	if oddsLabel and oddsText ~= "" then
		oddsLabel.Text = oddsText
		oddsLabel.TextColor3 = displayColor
		oddsLabel.Visible = true
	elseif oddsLabel then
		oddsLabel.Visible = false
	end

	resultFrame.Visible = true
	UIHelper.ScaleIn(resultFrame, 0.3)

	spinContainer.Visible = false

	-- 3D model popup
	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	local modelTemplate = modelsFolder and modelsFolder:FindFirstChild(data.streamerId or "")
	local hasModel = modelTemplate ~= nil

	local messageHeight = hasModel and 400 or 180
	local receivedMessage = Instance.new("Frame")
	receivedMessage.Name = "ReceivedMessage"
	receivedMessage.Size = UDim2.new(0, 450, 0, messageHeight)
	receivedMessage.Position = UDim2.new(0.5, 0, 0.45, 0)
	receivedMessage.AnchorPoint = Vector2.new(0.5, 0.5)
	receivedMessage.BackgroundColor3 = Color3.fromRGB(25, 15, 50)
	receivedMessage.BorderSizePixel = 0
	receivedMessage.ZIndex = 20
	receivedMessage.Parent = screenGui

	UIHelper.MakeResponsiveModal(receivedMessage, 450, messageHeight)

	local rmCorner = Instance.new("UICorner")
	rmCorner.CornerRadius = UDim.new(0, 20)
	rmCorner.Parent = receivedMessage

	local rmStroke = Instance.new("UIStroke")
	rmStroke.Color = displayColor
	rmStroke.Thickness = 1.5
	rmStroke.Transparency = 0.25
	rmStroke.Parent = receivedMessage

	-- Background gradient
	local rmGrad = Instance.new("UIGradient")
	rmGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 20, 65)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 8, 25)),
	})
	rmGrad.Rotation = 90
	rmGrad.Parent = receivedMessage

	if hasModel then
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "ModelViewport"
		viewport.Size = UDim2.new(0.55, 0, 0.55, 0)
		viewport.Position = UDim2.new(0.5, 0, 0, 12)
		viewport.AnchorPoint = Vector2.new(0.5, 0)
		viewport.BackgroundTransparency = 1
		viewport.ZIndex = 21
		viewport.Parent = receivedMessage

		local vpModel = modelTemplate:Clone()
		vpModel.Parent = viewport

		local vpCamera = Instance.new("Camera")
		vpCamera.Parent = viewport
		viewport.CurrentCamera = vpCamera

		local ok, cf, size = pcall(function() return vpModel:GetBoundingBox() end)
		if ok and cf and size then
			local maxDim = math.max(size.X, size.Y, size.Z)
			local dist = maxDim * 1.6
			vpCamera.CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y * 0.15, dist), cf.Position)
		else
			vpCamera.CFrame = CFrame.new(Vector3.new(0, 2, 5), Vector3.new(0, 1, 0))
		end

		local rotConn
		rotConn = RunService.RenderStepped:Connect(function(dt)
			if not viewport or not viewport.Parent then
				rotConn:Disconnect()
				return
			end
			if vpCamera and vpCamera.Parent then
				local target = ok and cf and cf.Position or Vector3.new(0, 1, 0)
				local currentCF = vpCamera.CFrame
				local rotated = CFrame.Angles(0, dt * 0.8, 0) * (currentCF - target) + target
				vpCamera.CFrame = CFrame.new(rotated.Position, target)
			end
		end)
	end

	-- Text section
	local textYStart = hasModel and 250 or 14
	local resultFullName = data.displayName or "Unknown"
	if effectInfo and not string.find(resultFullName, effectInfo.prefix, 1, true) then
		resultFullName = effectInfo.prefix .. " " .. resultFullName
	end

	-- Title "YOU RECEIVED:"
	addOutlinedText(receivedMessage, {
		Name = "RecTitle",
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0.5, 0, 0, textYStart),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "YOU RECEIVED:",
		Color = Color3.fromRGB(200, 190, 255),
		Font = FONT_SUB,
		TextSize = 16,
		StrokeThickness = 1.5,
		ZIndex = 21,
	})

	-- Streamer name (big, colorful)
	addOutlinedText(receivedMessage, {
		Name = "RecName",
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.new(0.5, 0, 0, textYStart + 24),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = resultFullName,
		Color = displayColor,
		Font = FONT,
		TextSize = 26,
		StrokeThickness = 1.5,
		ZIndex = 21,
	})

	-- Rarity
	local rarityText = (data.rarity or "Common"):upper()
	if effectInfo then rarityText = effectInfo.prefix:upper() .. " " .. rarityText end
	addOutlinedText(receivedMessage, {
		Name = "RecRarity",
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0.5, 0, 0, textYStart + 60),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = rarityText,
		Color = displayColor,
		Font = FONT,
		TextSize = 16,
		StrokeThickness = 2,
		ZIndex = 21,
	})

	-- Cash per second
	local streamerCfg = Streamers.ById[data.streamerId or ""]
	local cashLine = ""
	if streamerCfg then
		local cashPerSec = streamerCfg.cashPerSecond or 0
		if effectInfo and effectInfo.cashMultiplier then
			cashPerSec = cashPerSec * effectInfo.cashMultiplier
		end
		if cashPerSec > 0 then
			cashLine = formatCash(cashPerSec):sub(1) .. "/sec"
		end
	end
	if cashLine ~= "" then
		addOutlinedText(receivedMessage, {
			Name = "RecCash",
			Size = UDim2.new(1, -20, 0, 26),
			Position = UDim2.new(0.5, 0, 0, textYStart + 84),
			AnchorPoint = Vector2.new(0.5, 0),
			Text = cashLine,
			Color = Color3.fromRGB(80, 255, 130),
			Font = FONT,
			TextSize = 22,
			StrokeThickness = 2.5,
			ZIndex = 21,
		})
	end

	-- Odds
	if oddsText ~= "" then
		addOutlinedText(receivedMessage, {
			Name = "RecOdds",
			Size = UDim2.new(1, -20, 0, 20),
			Position = UDim2.new(0.5, 0, 0, textYStart + (cashLine ~= "" and 112 or 86)),
			AnchorPoint = Vector2.new(0.5, 0),
			Text = oddsText,
			Color = Color3.fromRGB(255, 220, 80),
			Font = FONT_SUB,
			TextSize = 14,
			StrokeThickness = 1.5,
			ZIndex = 21,
		})
	end

	UIHelper.ScaleIn(receivedMessage, 0.3)

	-- Glow carousel border
	local stroke = carouselFrame:FindFirstChild("BorderStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.3), { Color = displayColor, Thickness = 3 }):Play()
		task.delay(2, function()
			if stroke and stroke.Parent then
				TweenService:Create(stroke, TweenInfo.new(0.5), { Color = CAROUSEL_STROKE, Thickness = 3 }):Play()
			end
		end)
	end

	if items[currentTargetIndex] and items[currentTargetIndex].frame then
		local winGlow = items[currentTargetIndex].frame:FindFirstChild("WinGlow")
		if winGlow then
			TweenService:Create(winGlow, TweenInfo.new(0.3), { Color = displayColor, Thickness = 6 }):Play()
		end
	end

	local shakeIntensity = rarityInfo and rarityInfo.shakeIntensity or 0
	if shakeIntensity > 0 then UIHelper.CameraShake(shakeIntensity * 0.1, 0.4) end

	if data.rarity == "Legendary" or data.rarity == "Mythic" or effectInfo then
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.Size = UDim2.new(1, 0, 1, 0)
		flash.BackgroundColor3 = displayColor
		flash.BackgroundTransparency = 0.5
		flash.ZIndex = 100
		flash.Parent = screenGui
		TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		task.delay(0.5, function() flash:Destroy() end)
	end

	if onSpinResult then task.spawn(onSpinResult, data) end

	local myGeneration = spinGeneration
	task.spawn(function()
		local waitTime = autoSpinEnabled and 1.5 or 3.5
		task.wait(waitTime)
		if spinGeneration ~= myGeneration then return end

		if receivedMessage and receivedMessage.Parent then
			TweenService:Create(receivedMessage, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			local ms = receivedMessage:FindFirstChildOfClass("UIStroke")
			if ms then TweenService:Create(ms, TweenInfo.new(0.3), { Transparency = 1 }):Play() end
			task.wait(0.3)
			if spinGeneration ~= myGeneration then return end
			if receivedMessage then receivedMessage:Destroy() end
		end
		if spinGeneration ~= myGeneration then return end

		isSpinning = false
		animationDone = false

		if autoSpinEnabled then
			resultFrame.Visible = false
			spinContainer.Visible = true
			if carouselFrame then carouselFrame.Visible = true end
			if isOwnedCrateOpen and currentCrateId then
				local HUD = require(script.Parent.HUDController)
				local owned = HUD.Data.ownedCrates
				local count = owned and (owned[currentCrateId] or owned[tostring(currentCrateId)] or 0) or 0
				if count > 0 then
					local OpenOwnedCrate = RemoteEvents:WaitForChild("OpenOwnedCrate")
					OpenOwnedCrate:FireServer(currentCrateId)
					SpinController.WaitForResult()
				else
					autoSpinEnabled = false
					if autoSpinButton then
						autoSpinButton.BackgroundColor3 = Color3.fromRGB(55, 50, 80)
						autoSpinButton.Text = "AUTO"
						autoSpinButton.TextColor3 = Color3.fromRGB(180, 180, 210)
					end
					SpinController.Hide()
				end
			else
				SpinController.RequestSpin()
			end
			return
		end
		task.wait(0.2)
		SpinController.Hide()
	end)
end

-------------------------------------------------
-- MYTHIC ALERT
-------------------------------------------------

local function showMythicAlert(data)
	local alert = UIHelper.CreateRoundedFrame({
		Name = "MythicAlert",
		Size = UDim2.new(0, 640, 0, 60),
		Position = UDim2.new(0.5, 0, 0.15, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(40, 10, 10),
		CornerRadius = DesignConfig.Layout.PanelCorner,
		StrokeColor = Rarities.ByName["Mythic"].color,
		Parent = screenGui,
	})

	UIHelper.MakeResponsiveModal(alert, 640, 60)

	UIHelper.CreateLabel({
		Name = "AlertText",
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = data.playerName .. " pulled MYTHIC " .. data.displayName .. "!",
		TextColor = Rarities.ByName["Mythic"].color,
		Font = DesignConfig.Fonts.Accent,
		TextSize = DesignConfig.FontSizes.Body,
		Parent = alert,
	})

	UIHelper.ScaleIn(alert, 0.4)
	task.delay(4, function()
		local tween = TweenService:Create(alert, TweenInfo.new(0.5), {
			Position = UDim2.new(0.5, 0, -0.1, 0),
		})
		tween:Play()
		tween.Completed:Connect(function() alert:Destroy() end)
	end)
end

-------------------------------------------------
-- HELPER: styled pill button for spin/auto/skip
-------------------------------------------------

local function createPillButton(parent, props)
	local btn = Instance.new("TextButton")
	btn.Name = props.Name or "PillBtn"
	btn.Size = props.Size or UDim2.new(0, 120, 0, 48)
	btn.Position = props.Position or UDim2.new(0.5, 0, 0.5, 0)
	btn.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	btn.BackgroundColor3 = props.Color or Color3.fromRGB(80, 80, 120)
	btn.Text = props.Text or "BUTTON"
	btn.TextColor3 = props.TextColor or Color3.new(1, 1, 1)
	btn.Font = props.Font or FONT
	btn.TextSize = props.TextSize or 20
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = props.ZIndex or 1
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, props.CornerRadius or 18)
	corner.Parent = btn

	if props.StrokeColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = props.StrokeColor
		stroke.Thickness = props.StrokeThickness or 2.5
		stroke.Transparency = 0.1
		stroke.Parent = btn
	end

	if props.GradientTop and props.GradientBot then
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, props.GradientTop),
			ColorSequenceKeypoint.new(1, props.GradientBot),
		})
		grad.Rotation = 90
		grad.Parent = btn
	end

	-- Text stroke
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = props.TextStrokeColor or Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = props.TextStrokeThickness or 2
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = btn

	-- Bounce interactions
	local idleSize = btn.Size
	local hoverSize = UDim2.new(
		idleSize.X.Scale * 1.08, math.floor(idleSize.X.Offset * 1.08),
		idleSize.Y.Scale * 1.08, math.floor(idleSize.Y.Offset * 1.08)
	)
	local clickSize = UDim2.new(
		idleSize.X.Scale * 0.93, math.floor(idleSize.X.Offset * 0.93),
		idleSize.Y.Scale * 0.93, math.floor(idleSize.Y.Offset * 0.93)
	)
	local bounceTI = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local clickTI  = TweenInfo.new(0.08, Enum.EasingStyle.Quad)

	local hoverColor = props.HoverColor or props.Color or Color3.fromRGB(100, 100, 140)
	local idleColor = props.Color or Color3.fromRGB(80, 80, 120)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, bounceTI, { Size = hoverSize, BackgroundColor3 = hoverColor }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, bounceTI, { Size = idleSize, BackgroundColor3 = idleColor }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, clickTI, { Size = clickSize }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, bounceTI, { Size = idleSize }):Play()
	end)

	return btn
end

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function SpinController.Init()
	screenGui = UIHelper.CreateScreenGui("SpinGui", 10)
	screenGui.Parent = playerGui

	-- Main container
	spinContainer = Instance.new("Frame")
	spinContainer.Name = "SpinContainer"
	spinContainer.Size = UDim2.new(0.58, 0, 0.88, 0)
	spinContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
	spinContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	spinContainer.BackgroundColor3 = CONTAINER_BG_TOP
	spinContainer.BorderSizePixel = 0
	spinContainer.Visible = false
	spinContainer.Parent = screenGui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 22)
	containerCorner.Parent = spinContainer

	local containerGrad = Instance.new("UIGradient")
	containerGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CONTAINER_BG_TOP),
		ColorSequenceKeypoint.new(1, CONTAINER_BG_BOT),
	})
	containerGrad.Rotation = 90
	containerGrad.Parent = spinContainer

	local containerStroke = Instance.new("UIStroke")
	containerStroke.Color = CONTAINER_STROKE
	containerStroke.Thickness = 1.5
	containerStroke.Transparency = 0.25
	containerStroke.Parent = spinContainer

	UIHelper.CreateShadow(spinContainer)

	-- Top rainbow accent
	local topAccent = Instance.new("Frame")
	topAccent.Name = "TopAccent"
	topAccent.Size = UDim2.new(0.8, 0, 0, 4)
	topAccent.Position = UDim2.new(0.5, 0, 0, 8)
	topAccent.AnchorPoint = Vector2.new(0.5, 0)
	topAccent.BackgroundColor3 = Color3.new(1, 1, 1)
	topAccent.BorderSizePixel = 0
	topAccent.ZIndex = 3
	topAccent.Parent = spinContainer
	local taCorner = Instance.new("UICorner")
	taCorner.CornerRadius = UDim.new(0, 2)
	taCorner.Parent = topAccent
	local taGrad = Instance.new("UIGradient")
	taGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 120)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 150)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 150, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 80, 255)),
	})
	taGrad.Parent = topAccent

	-- Title
	local spinTitle = addOutlinedText(spinContainer, {
		Name = "SpinTitle",
		Size = UDim2.new(1, 0, 0, 46),
		Position = UDim2.new(0.5, 0, 0, 16),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "🎰  SPIN THE STREAMER  🎰",
		Color = Color3.fromRGB(255, 220, 80),
		Font = FONT,
		TextSize = 32,
		StrokeColor = Color3.fromRGB(180, 80, 0),
		StrokeThickness = 1.5,
	})
	spinTitle.ZIndex = 2

	buildCarousel(spinContainer)
	buildResultDisplay(spinContainer)

	-- SPIN button (vibrant green pill)
	spinButton = createPillButton(spinContainer, {
		Name = "SpinButton",
		Size = UDim2.new(0.45, 0, 0, 56),
		Position = UDim2.new(0.5, 0, 0.94, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(60, 220, 100),
		HoverColor = Color3.fromRGB(90, 255, 140),
		Text = "SPIN  (" .. formatCash(currentSpinCost) .. ")",
		TextColor = Color3.new(1, 1, 1),
		TextSize = 24,
		StrokeColor = Color3.fromRGB(30, 160, 70),
		GradientTop = BTN_GREEN_TOP,
		GradientBot = BTN_GREEN_BOT,
		TextStrokeColor = Color3.fromRGB(10, 60, 20),
		TextStrokeThickness = 2.5,
	})

	spinButton.MouseButton1Click:Connect(function()
		SpinController.RequestSpin()
	end)

	-- AUTO button
	autoSpinButton = createPillButton(spinContainer, {
		Name = "AutoSpinBtn",
		Size = UDim2.new(0, 110, 0, 42),
		Position = UDim2.new(0.04, 0, 0.94, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = Color3.fromRGB(55, 50, 80),
		HoverColor = Color3.fromRGB(70, 65, 100),
		Text = "AUTO",
		TextColor = Color3.fromRGB(180, 180, 210),
		TextSize = 18,
		StrokeColor = Color3.fromRGB(80, 70, 120),
		StrokeThickness = 2,
		TextStrokeColor = Color3.fromRGB(20, 15, 40),
		TextStrokeThickness = 1.5,
		ZIndex = 5,
	})

	local function updateAutoSpinVisual()
		if autoSpinEnabled then
			autoSpinButton.BackgroundColor3 = Color3.fromRGB(50, 200, 80)
			autoSpinButton.Text = "AUTO: ON"
			autoSpinButton.TextColor3 = Color3.new(1, 1, 1)
			local s = autoSpinButton:FindFirstChildOfClass("UIStroke")
			if s then s.Color = Color3.fromRGB(30, 160, 60) end
		else
			autoSpinButton.BackgroundColor3 = Color3.fromRGB(55, 50, 80)
			autoSpinButton.Text = "AUTO"
			autoSpinButton.TextColor3 = Color3.fromRGB(180, 180, 210)
			local s = autoSpinButton:FindFirstChildOfClass("UIStroke")
			if s then s.Color = Color3.fromRGB(80, 70, 120) end
		end
	end

	autoSpinButton.MouseButton1Click:Connect(function()
		autoSpinEnabled = not autoSpinEnabled
		updateAutoSpinVisual()
	end)

	-- SKIP button
	skipButton = createPillButton(spinContainer, {
		Name = "SkipButton",
		Size = UDim2.new(0, 110, 0, 38),
		Position = UDim2.new(0.5, 0, 0.66, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(70, 60, 100),
		HoverColor = Color3.fromRGB(90, 80, 130),
		Text = "SKIP ▶▶",
		TextColor = Color3.fromRGB(230, 230, 255),
		TextSize = 16,
		StrokeColor = Color3.fromRGB(120, 100, 180),
		StrokeThickness = 2,
		TextStrokeColor = Color3.fromRGB(20, 15, 40),
		TextStrokeThickness = 1.5,
		ZIndex = 15,
	})
	skipButton.Visible = false

	skipButton.MouseButton1Click:Connect(function()
		skipRequested = true
	end)

	-- Listen for spin results
	SpinResult.OnClientEvent:Connect(function(data)
		if data.success then
			SpinController._startSpin(data)
		else
			if autoSpinEnabled then
				autoSpinEnabled = false
				updateAutoSpinVisual()
			end
			stopPreSpinVisual()
			isSpinning = false
			animationDone = false
			spinButton.Text = data.reason or "ERROR"
			task.delay(1.5, function()
				if currentSpinCost <= 0 then
					spinButton.Text = "OPEN"
				else
					spinButton.Text = "SPIN  (" .. formatCash(currentSpinCost) .. ")"
				end
				SpinController.Hide()
			end)
		end
	end)

	MythicAlert.OnClientEvent:Connect(function(data)
		showMythicAlert(data)
	end)
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function SpinController._startSpin(data)
	isSpinning = true
	animationDone = false
	spinGeneration = spinGeneration + 1
	resultFrame.Visible = false
	stopPreSpinVisual()

	local existingMsg = screenGui:FindFirstChild("ReceivedMessage")
	if existingMsg then existingMsg:Destroy() end

	spinContainer.Visible = true
	if carouselFrame then
		carouselFrame.Visible = true
		carouselFrame.Size = UDim2.new(0.92, 0, 0, ITEM_HEIGHT + 30)
	end
	for _, item in ipairs(items) do
		if item.frame then
			local glow = item.frame:FindFirstChild("WinGlow")
			if glow then glow:Destroy() end
		end
	end

	local forcedEffect = getForcedGemCaseEffect()
	if not forcedEffect and data and data.caseId then
		local caseData = GemCases.ById[data.caseId]
		forcedEffect = caseData and caseData.effect or nil
	end

	local COSMETIC_CHANCE = 0.15
	for idx, _item in ipairs(items) do
		if forcedEffect then
			applyEffectToCard(idx, forcedEffect)
		else
			local newEff = nil
			if math.random() < COSMETIC_CHANCE then
				newEff = Effects.List[math.random(1, #Effects.List)]
			end
			applyEffectToCard(idx, newEff and newEff.name or nil)
		end
	end

	spinButton.Text = "SPINNING..."

	playSpinAnimation(data, function()
		animationDone = true
		showResult(data)
		if currentSpinCost <= 0 then
			spinButton.Text = "OPEN AGAIN"
		else
			spinButton.Text = "SPIN AGAIN  (" .. formatCash(currentSpinCost) .. ")"
		end
	end)
end

function SpinController.RequestSpin()
	if isSpinning and not animationDone then return end

	if isSpinning and animationDone then
		local existingMsg = screenGui:FindFirstChild("ReceivedMessage")
		if existingMsg then existingMsg:Destroy() end
	end

	isSpinning = true
	animationDone = false
	spinGeneration = spinGeneration + 1
	resultFrame.Visible = false
	spinContainer.Visible = true
	if carouselFrame then
		carouselFrame.Visible = true
		carouselFrame.Size = UDim2.new(0.92, 0, 0, ITEM_HEIGHT + 30)
	end
	startPreSpinVisual()

	spinButton.Text = "SPINNING..."

	if isOwnedCrateOpen and currentCrateId then
		local OpenOwnedCrate = RemoteEvents:WaitForChild("OpenOwnedCrate")
		OpenOwnedCrate:FireServer(currentCrateId)
	elseif currentCrateId then
		local BuyCrateRequest = RemoteEvents:WaitForChild("BuyCrateRequest")
		BuyCrateRequest:FireServer(currentCrateId)
	else
		SpinRequest:FireServer()
	end
end

function SpinController.Show()
	spinContainer.Visible = true
	if currentSpinCost <= 0 then
		spinButton.Text = "OPEN"
	else
		spinButton.Text = "SPIN  (" .. formatCash(currentSpinCost) .. ")"
	end
	UIHelper.ScaleIn(spinContainer, 0.3)
end

function SpinController.Hide()
	stopPreSpinVisual()
	UIHelper.ScaleOut(spinContainer, 0.2)
	isSpinning = false
	animationDone = false
	autoSpinEnabled = false
	isOwnedCrateOpen = false
	currentGemCaseId = nil
	if autoSpinButton then
		autoSpinButton.BackgroundColor3 = Color3.fromRGB(55, 50, 80)
		autoSpinButton.Text = "AUTO"
		autoSpinButton.TextColor3 = Color3.fromRGB(180, 180, 210)
		local s = autoSpinButton:FindFirstChildOfClass("UIStroke")
		if s then s.Color = Color3.fromRGB(80, 70, 120) end
	end
	if skipButton then skipButton.Visible = false end
	if currentAnimConnection then
		pcall(function() currentAnimConnection:Disconnect() end)
		currentAnimConnection = nil
	end
end

function SpinController.IsVisible(): boolean
	return spinContainer.Visible
end

function SpinController.SetCurrentCost(cost: number)
	currentSpinCost = cost
	if spinButton and not isSpinning then
		if cost <= 0 then
			spinButton.Text = "OPEN"
		else
			spinButton.Text = "SPIN  (" .. formatCash(currentSpinCost) .. ")"
		end
	end
end

function SpinController.SetCurrentCrateId(crateId)
	currentCrateId = crateId
	if crateId ~= nil then
		currentGemCaseId = nil
	end
end

function SpinController.SetOwnedCrateMode(enabled)
	isOwnedCrateOpen = enabled
end

function SpinController.SetGemCaseVisual(caseId)
	currentGemCaseId = caseId
end

function SpinController.WaitForResult()
	isSpinning = true
	animationDone = false
	spinGeneration = spinGeneration + 1
	resultFrame.Visible = false
	spinContainer.Visible = true
	if carouselFrame then
		carouselFrame.Visible = true
		carouselFrame.Size = UDim2.new(0.92, 0, 0, ITEM_HEIGHT + 30)
	end
	local forcedEffect = getForcedGemCaseEffect()
	if forcedEffect then
		for idx, _item in ipairs(items) do
			applyEffectToCard(idx, forcedEffect)
		end
	end
	startPreSpinVisual()
	spinButton.Text = "SPINNING..."
end

function SpinController.OnSpinResult(callback)
	onSpinResult = callback
end

function SpinController.IsAnimating()
	return isSpinning and not animationDone
end

return SpinController
