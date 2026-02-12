--[[
	SpinController.lua
	CS:GO-style horizontal scrolling case opening animation.
	Items scroll horizontally with blur effects and smooth easing.
	Spin results now go to INVENTORY — shown with "Added to inventory!" text.
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
local UIHelper = require(script.Parent.UIHelper)

local SpinController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SpinRequest = RemoteEvents:WaitForChild("SpinRequest")
local SpinResult = RemoteEvents:WaitForChild("SpinResult")
local MythicAlert = RemoteEvents:WaitForChild("MythicAlert")

-- UI references
local screenGui
local spinContainer
local carouselFrame
local carouselContainer
local resultFrame
local spinButton
local isSpinning = false

-- Callback for when a spin result arrives
local onSpinResult = nil

-- Carousel items
local ITEM_WIDTH = 120
local ITEM_HEIGHT = 140
local ITEM_GAP = 6 -- thin gap between items (CS:GO style)
local ITEM_STEP = ITEM_WIDTH + ITEM_GAP
local items = {}
local currentTargetIndex = 1

-------------------------------------------------
-- BUILD CAROUSEL (CS:GO Style — flat horizontal strip)
-------------------------------------------------

local function buildCarousel(parent)
	-- Outer frame — the visible window, clips the strip
	carouselFrame = Instance.new("Frame")
	carouselFrame.Name = "CarouselFrame"
	carouselFrame.Size = UDim2.new(0.85, 0, 0, ITEM_HEIGHT + 24) -- slightly taller than items
	carouselFrame.Position = UDim2.new(0.5, 0, 0.44, 0)
	carouselFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	carouselFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
	carouselFrame.BorderSizePixel = 0
	carouselFrame.ClipsDescendants = true
	carouselFrame.Parent = parent

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 8)
	frameCorner.Parent = carouselFrame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Name = "BorderStroke"
	frameStroke.Color = Color3.fromRGB(55, 55, 75)
	frameStroke.Thickness = 2
	frameStroke.Parent = carouselFrame

	-- Thin coloured line across the top (CS:GO gold line)
	local topLine = Instance.new("Frame")
	topLine.Name = "TopLine"
	topLine.Size = UDim2.new(1, 0, 0, 3)
	topLine.Position = UDim2.new(0, 0, 0, 0)
	topLine.BackgroundColor3 = Color3.fromRGB(220, 180, 50)
	topLine.BorderSizePixel = 0
	topLine.ZIndex = 6
	topLine.Parent = carouselFrame

	-- Inner container (very wide strip that slides left/right)
	carouselContainer = Instance.new("Frame")
	carouselContainer.Name = "CarouselContainer"
	carouselContainer.BackgroundTransparency = 1
	carouselContainer.BorderSizePixel = 0
	carouselContainer.Position = UDim2.new(0, 0, 0, 0)
	carouselContainer.AnchorPoint = Vector2.new(0, 0)
	carouselContainer.Parent = carouselFrame

	-- Build item strip: 5 full sets, SHUFFLED so rarities are scattered
	-- like real CS:GO cases.  Some cards get random cosmetic effects so
	-- players see "Acid Speed" or "Lightning Kai Cenat" fly past — creates
	-- the near-miss / excitement feeling.  The WINNING card is always
	-- overwritten in playSpinAnimation with the real server result.
	local allStreamers = {}
	local repeatCount = 5
	for _ = 1, repeatCount do
		for _, streamer in ipairs(Streamers.List) do
			table.insert(allStreamers, streamer)
		end
	end

	-- Fisher-Yates shuffle so cards are in a random order
	for i = #allStreamers, 2, -1 do
		local j = math.random(1, i)
		allStreamers[i], allStreamers[j] = allStreamers[j], allStreamers[i]
	end

	-- Decide random cosmetic effects (~15% of cards)
	local COSMETIC_EFFECT_CHANCE = 0.15
	local allCosmetics = {} -- parallel array: effectInfo or nil per card
	for ci = 1, #allStreamers do
		local eff = nil
		if math.random() < COSMETIC_EFFECT_CHANCE then
			-- Pick a random effect from the list
			eff = Effects.List[math.random(1, #Effects.List)]
		end
		allCosmetics[ci] = eff
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
		cardCorner.CornerRadius = UDim.new(0, 6)
		cardCorner.Parent = card

		-- Thin bottom colour strip (rarity)
		local bottomStrip = Instance.new("Frame")
		bottomStrip.Name = "BottomStrip"
		bottomStrip.Size = UDim2.new(1, 0, 0, 4)
		bottomStrip.Position = UDim2.new(0, 0, 1, -4)
		bottomStrip.BackgroundColor3 = rarityColor
		bottomStrip.BorderSizePixel = 0
		bottomStrip.Parent = card

		-- Effect badge at the very top (cosmetic — creates excitement)
		if eff then
			local badge = Instance.new("TextLabel")
			badge.Name = "EffectTag"
			badge.Size = UDim2.new(1, -6, 0, 16)
			badge.Position = UDim2.new(0.5, 0, 0, 4)
			badge.AnchorPoint = Vector2.new(0.5, 0)
			badge.BackgroundTransparency = 1
			badge.Text = eff.prefix:upper()
			badge.TextColor3 = eff.color
			badge.Font = Enum.Font.GothamBold
			badge.TextSize = 11
			badge.TextScaled = false
			badge.Parent = card
		end

		-- Streamer name (center)
		local nameY = eff and 0.18 or 0.08
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "StreamerName"
		nameLabel.Size = UDim2.new(1, -10, 0, 44)
		nameLabel.Position = UDim2.new(0.5, 0, nameY, 0)
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = eff and (eff.prefix .. " " .. streamer.displayName) or streamer.displayName
		nameLabel.TextColor3 = eff and eff.color or Color3.new(1, 1, 1)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 15
		nameLabel.TextScaled = false
		nameLabel.TextWrapped = true
		nameLabel.Parent = card

		-- Rarity label (bottom area)
		local rarLabel = Instance.new("TextLabel")
		rarLabel.Name = "RarityTag"
		rarLabel.Size = UDim2.new(1, -10, 0, 18)
		rarLabel.Position = UDim2.new(0.5, 0, 1, -26)
		rarLabel.AnchorPoint = Vector2.new(0.5, 0)
		rarLabel.BackgroundTransparency = 1
		rarLabel.Text = streamer.rarity:upper()
		rarLabel.TextColor3 = rarityColor
		rarLabel.Font = Enum.Font.GothamBold
		rarLabel.TextSize = 12
		rarLabel.TextScaled = false
		rarLabel.Parent = card

		items[i] = {
			frame = card,
			streamer = streamer,
			effect = eff,  -- cosmetic effect (may be nil); winning card gets the real one
		}
	end

	-- Size the container to fit all cards
	local totalW = #items * ITEM_STEP
	carouselContainer.Size = UDim2.new(0, totalW, 1, 0)

	-- Center selector — vertical line + triangles (CS:GO style)
	local selectorLine = Instance.new("Frame")
	selectorLine.Name = "SelectorLine"
	selectorLine.Size = UDim2.new(0, 2, 1, 6)
	selectorLine.Position = UDim2.new(0.5, 0, 0.5, 0)
	selectorLine.AnchorPoint = Vector2.new(0.5, 0.5)
	selectorLine.BackgroundColor3 = Color3.fromRGB(230, 50, 50)
	selectorLine.BorderSizePixel = 0
	selectorLine.ZIndex = 10
	selectorLine.Parent = carouselFrame

	-- Top triangle
	local topArrow = Instance.new("TextLabel")
	topArrow.Name = "TopArrow"
	topArrow.Size = UDim2.new(0, 24, 0, 18)
	topArrow.Position = UDim2.new(0.5, 0, 0, 2)
	topArrow.AnchorPoint = Vector2.new(0.5, 0)
	topArrow.BackgroundTransparency = 1
	topArrow.Text = "\u{25BC}"
	topArrow.TextColor3 = Color3.fromRGB(230, 50, 50)
	topArrow.Font = Enum.Font.GothamBold
	topArrow.TextSize = 18
	topArrow.ZIndex = 10
	topArrow.Parent = carouselFrame

	-- Bottom triangle
	local botArrow = Instance.new("TextLabel")
	botArrow.Name = "BotArrow"
	botArrow.Size = UDim2.new(0, 24, 0, 18)
	botArrow.Position = UDim2.new(0.5, 0, 1, -2)
	botArrow.AnchorPoint = Vector2.new(0.5, 1)
	botArrow.BackgroundTransparency = 1
	botArrow.Text = "\u{25B2}"
	botArrow.TextColor3 = Color3.fromRGB(230, 50, 50)
	botArrow.Font = Enum.Font.GothamBold
	botArrow.TextSize = 18
	botArrow.ZIndex = 10
	botArrow.Parent = carouselFrame

	-- Dark gradient edges (fade to black on left/right for depth)
	for _, side in ipairs({"Left", "Right"}) do
		local grad = Instance.new("Frame")
		grad.Name = "Fade" .. side
		grad.Size = UDim2.new(0, 80, 1, 0)
		grad.Position = side == "Left" and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -80, 0, 0)
		grad.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
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

-- Format odds for display: 1000000 -> "1 in 1,000,000"
local function formatOdds(odds)
	if not odds or odds < 1 then return "" end
	local s = tostring(math.floor(odds))
	local formatted = ""
	local len = #s
	for i = 1, len do
		formatted = formatted .. string.sub(s, i, i)
		if (len - i) % 3 == 0 and i < len then
			formatted = formatted .. ","
		end
	end
	return "1 in " .. formatted
end

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

	-- "Added to inventory!" text
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
-- SPIN ANIMATION (CS:GO style — smooth ease-out)
-------------------------------------------------

-- Ease-out quint: starts fast, decelerates smoothly to a stop
local function easeOutQuint(t)
	local t1 = 1 - t
	return 1 - t1 * t1 * t1 * t1 * t1
end

-- Update an existing carousel card to reflect an effect (or no effect).
-- Called on the winning card so the strip shows EXACTLY what the player received.
local function applyEffectToCard(cardIndex, effectName)
	local entry = items[cardIndex]
	if not entry then return end
	local card = entry.frame
	local streamer = entry.streamer
	if not card or not streamer then return end

	local effectInfo = effectName and Effects.ByName[effectName] or nil
	local rarityColor = Rarities.ByName[streamer.rarity] and Rarities.ByName[streamer.rarity].color or Color3.fromRGB(100, 100, 100)

	-- Update stored effect so showResult glow colours match
	entry.effect = effectInfo

	-- Background colour: blend rarity with effect colour
	if effectInfo then
		card.BackgroundColor3 = Color3.fromRGB(
			math.floor(rarityColor.R * 255 * 0.5 + effectInfo.color.R * 255 * 0.5),
			math.floor(rarityColor.G * 255 * 0.5 + effectInfo.color.G * 255 * 0.5),
			math.floor(rarityColor.B * 255 * 0.5 + effectInfo.color.B * 255 * 0.5)
		)
	else
		card.BackgroundColor3 = rarityColor
	end

	-- Effect badge
	local existingBadge = card:FindFirstChild("EffectTag")
	if effectInfo then
		if not existingBadge then
			existingBadge = Instance.new("TextLabel")
			existingBadge.Name = "EffectTag"
			existingBadge.Size = UDim2.new(1, -6, 0, 16)
			existingBadge.Position = UDim2.new(0.5, 0, 0, 4)
			existingBadge.AnchorPoint = Vector2.new(0.5, 0)
			existingBadge.BackgroundTransparency = 1
			existingBadge.Font = Enum.Font.GothamBold
			existingBadge.TextSize = 11
			existingBadge.TextScaled = false
			existingBadge.Parent = card
		end
		existingBadge.Text = effectInfo.prefix:upper()
		existingBadge.TextColor3 = effectInfo.color
		existingBadge.Visible = true
	elseif existingBadge then
		existingBadge.Visible = false
	end

	-- Streamer name
	local nameLabel = card:FindFirstChild("StreamerName")
	if nameLabel then
		if effectInfo then
			nameLabel.Text = effectInfo.prefix .. " " .. streamer.displayName
			nameLabel.TextColor3 = effectInfo.color
			nameLabel.Position = UDim2.new(0.5, 0, 0.18, 0)
		else
			nameLabel.Text = streamer.displayName
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
			nameLabel.Position = UDim2.new(0.5, 0, 0.08, 0)
		end
	end
end

local function playSpinAnimation(resultData, callback)
	if not carouselContainer or not carouselFrame then return end

	-- Find target item — prefer the 3rd occurrence (middle of 5 repeats)
	local targetStreamerId = resultData.streamerId or resultData.id
	local occurrences = {}
	for i, item in ipairs(items) do
		if item.streamer.id == targetStreamerId then
			table.insert(occurrences, i)
		end
	end
	-- Fallback by displayName
	if #occurrences == 0 then
		for i, item in ipairs(items) do
			if item.streamer.displayName == resultData.displayName then
				table.insert(occurrences, i)
			end
		end
	end

	local targetIndex
	if #occurrences >= 3 then
		targetIndex = occurrences[3]
	elseif #occurrences >= 2 then
		targetIndex = occurrences[2]
	elseif #occurrences >= 1 then
		targetIndex = occurrences[1]
	else
		targetIndex = 1
	end
	currentTargetIndex = targetIndex

	-- Update the WINNING card to show the actual effect from the server
	-- so whatever the player sees the strip land on is exactly what they get
	applyEffectToCard(targetIndex, resultData.effect)

	-- Near-miss excitement: place a couple flashy items near the winning card
	-- so the player sees rare / effect items right next to where they landed.
	-- This creates the "I was SO CLOSE to a Mythic!" feeling.
	local nearMissOffsets = { -2, -1, 1, 2 } -- cards adjacent to winner
	for _, offset in ipairs(nearMissOffsets) do
		local adjIdx = targetIndex + offset
		if adjIdx >= 1 and adjIdx <= #items and adjIdx ~= targetIndex then
			-- 40% chance to give adjacent cards a flashy effect
			if math.random() < 0.40 then
				local randEff = Effects.List[math.random(1, #Effects.List)]
				applyEffectToCard(adjIdx, randEff.name)
			end
			-- 25% chance to make an adjacent card a rarer streamer (visual swap)
			-- We only swap the displayed name/rarity — the DATA doesn't matter
			-- because only the winning card's result is real.
			if math.random() < 0.25 then
				local rareStreamers = {}
				for _, s in ipairs(Streamers.List) do
					if s.rarity == "Legendary" or s.rarity == "Mythic" or s.rarity == "Epic" then
						table.insert(rareStreamers, s)
					end
				end
				if #rareStreamers > 0 then
					local swapTo = rareStreamers[math.random(1, #rareStreamers)]
					local adjCard = items[adjIdx].frame
					local adjName = adjCard and adjCard:FindFirstChild("StreamerName")
					local adjRar = adjCard and adjCard:FindFirstChild("RarityTag")
					local adjStrip = adjCard and adjCard:FindFirstChild("BottomStrip")
					local swapColor = Rarities.ByName[swapTo.rarity] and Rarities.ByName[swapTo.rarity].color or Color3.new(1,1,1)
					if adjName then
						-- Keep any effect prefix already applied
						local existEff = items[adjIdx].effect
						if existEff then
							adjName.Text = existEff.prefix .. " " .. swapTo.displayName
						else
							adjName.Text = swapTo.displayName
						end
					end
					if adjRar then
						adjRar.Text = swapTo.rarity:upper()
						adjRar.TextColor3 = swapColor
					end
					if adjStrip then
						adjStrip.BackgroundColor3 = swapColor
					end
					-- Update stored streamer for consistency
					items[adjIdx].streamer = swapTo
				end
			end
		end
	end

	-- Calculate positions
	local frameWidth = carouselFrame.AbsoluteSize.X
	if frameWidth == 0 then frameWidth = 700 end
	local halfFrame = frameWidth / 2

	-- Where the target card's center sits inside the container
	local targetCenterX = (targetIndex - 1) * ITEM_STEP + ITEM_WIDTH / 2
	-- Container X that puts the target under the selector line
	local endX = halfFrame - targetCenterX
	-- Add a small random offset (-20..+20 px) so it doesn't always land dead center
	endX = endX + math.random(-20, 20)

	-- Starting position: at least 3 full streamer-sets to the right of the end
	local setWidth = #Streamers.List * ITEM_STEP
	local startX = endX + setWidth * 3

	-- Duration & timing
	local DURATION = 5.5 -- seconds — feels like CS:GO
	local startTime = tick()

	-- Reset container to start position instantly
	carouselContainer.Position = UDim2.new(0, startX, 0, 0)

	local totalDist = startX - endX -- positive (moving left)
	local connection
	local done = false

	connection = RunService.RenderStepped:Connect(function()
		local t = (tick() - startTime) / DURATION
		if t >= 1 then t = 1 end

		-- Smooth ease-out: fast at the start, graceful deceleration
		local eased = easeOutQuint(t)
		local currentX = startX - totalDist * eased
		carouselContainer.Position = UDim2.new(0, currentX, 0, 0)

		if t >= 1 and not done then
			done = true
			connection:Disconnect()

			-- Snap to exact final position
			carouselContainer.Position = UDim2.new(0, endX, 0, 0)

			-- Highlight the winning card
			task.spawn(function()
				task.wait(0.05)
				local winCard = items[targetIndex] and items[targetIndex].frame
				if winCard then
					-- Add a bright glow stroke
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
					-- Animate glow in
					TweenService:Create(glow, TweenInfo.new(0.35, Enum.EasingStyle.Back), {
						Thickness = 5,
					}):Play()
				end

				task.wait(1.0) -- pause to admire the result
				if callback then
					callback()
				end
			end)
		end
	end)
end

local function showResult(data)
	local rarityInfo = Rarities.ByName[data.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(170, 170, 170)

	-- If the streamer has an effect, use the effect color for glow
	local effectInfo = data.effect and Effects.ByName[data.effect] or nil
	local displayColor = effectInfo and effectInfo.color or rarityColor

	-- Update result display
	local nameLabel = resultFrame:FindFirstChild("StreamerName")
	local rarityLabel = resultFrame:FindFirstChild("RarityLabel")
	local resultLabel = resultFrame:FindFirstChild("ResultLabel")

	if resultLabel then
		resultLabel.Text = "YOU RECEIVED:"
		resultLabel.TextColor3 = displayColor
	end
	if nameLabel then
		nameLabel.Text = data.displayName or "Unknown"
		nameLabel.TextColor3 = displayColor
	end
	if rarityLabel then
		local rarityText = (data.rarity or "Common"):upper()
		if effectInfo then
			rarityText = effectInfo.prefix:upper() .. " " .. rarityText
		end
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
	
	-- Show a prominent "You received..." message with model viewport + odds
	-- Check if we have a 3D model for this streamer
	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	local modelTemplate = modelsFolder and modelsFolder:FindFirstChild(data.streamerId or "")
	local hasModel = modelTemplate ~= nil

	-- Make the message taller if we have a model to show
	local messageHeight = hasModel and 260 or 140
	local receivedMessage = UIHelper.CreateRoundedFrame({
		Name = "ReceivedMessage",
		Size = UDim2.new(0.6, 0, 0, messageHeight),
		Position = UDim2.new(0.5, 0, 0.25, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = DesignConfig.Colors.BackgroundLight,
		CornerRadius = DesignConfig.Layout.PanelCorner,
		StrokeColor = displayColor,
		Parent = spinContainer,
	})
	receivedMessage.ZIndex = 20

	-- ViewportFrame showing the 3D model (if available)
	if hasModel then
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "ModelViewport"
		viewport.Size = UDim2.new(0, 120, 0, 120)
		viewport.Position = UDim2.new(0.5, 0, 0, 10)
		viewport.AnchorPoint = Vector2.new(0.5, 0)
		viewport.BackgroundTransparency = 1
		viewport.ZIndex = 21
		viewport.Parent = receivedMessage

		-- Clone model into viewport
		local vpModel = modelTemplate:Clone()
		vpModel.Parent = viewport

		-- Camera for viewport
		local vpCamera = Instance.new("Camera")
		vpCamera.Parent = viewport
		viewport.CurrentCamera = vpCamera

		-- Position camera to frame the model
		local ok, cf, size = pcall(function()
			return vpModel:GetBoundingBox()
		end)
		if ok and cf and size then
			local maxDim = math.max(size.X, size.Y, size.Z)
			local dist = maxDim * 1.8
			vpCamera.CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y * 0.2, dist), cf.Position)
		else
			vpCamera.CFrame = CFrame.new(Vector3.new(0, 2, 6), Vector3.new(0, 1, 0))
		end

		-- Slow rotation animation
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

	-- Text section (below model or centered)
	local textYStart = hasModel and 132 or 10
	local messageLines = { "YOU RECEIVED:", data.displayName or "Unknown", (data.rarity or "Common"):upper() }
	if effectInfo then
		table.insert(messageLines, effectInfo.prefix:upper() .. " EFFECT (x" .. effectInfo.cashMultiplier .. " CASH)")
	end

	-- Add cashPerSecond info
	local streamerCfg = Streamers.ById[data.streamerId or ""]
	if streamerCfg then
		local cashPerSec = streamerCfg.cashPerSecond or 0
		if effectInfo and effectInfo.cashMultiplier then
			cashPerSec = cashPerSec * effectInfo.cashMultiplier
		end
		if cashPerSec > 0 then
			local formatted = tostring(math.floor(cashPerSec))
			local len = #formatted
			local fmtCash = ""
			for ci = 1, len do
				fmtCash = fmtCash .. string.sub(formatted, ci, ci)
				if (len - ci) % 3 == 0 and ci < len then
					fmtCash = fmtCash .. ","
				end
			end
			table.insert(messageLines, "$" .. fmtCash .. "/sec")
		end
	end

	if oddsText ~= "" then
		table.insert(messageLines, oddsText)
	end
	local messageText = UIHelper.CreateLabel({
		Name = "MessageText",
		Size = UDim2.new(1, -20, 0, messageHeight - textYStart - 10),
		Position = UDim2.new(0.5, 0, 0, textYStart),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = table.concat(messageLines, "\n"),
		TextColor = displayColor,
		Font = DesignConfig.Fonts.Accent,
		TextSize = 18,
		Parent = receivedMessage,
	})
	messageText.TextScaled = false
	
	UIHelper.ScaleIn(receivedMessage, 0.3)

	-- Glow carousel border
	local stroke = carouselFrame:FindFirstChild("BorderStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.3), {
			Color = displayColor,
			Thickness = 3,
		}):Play()
		task.delay(2, function()
			if stroke and stroke.Parent then
				TweenService:Create(stroke, TweenInfo.new(0.5), {
					Color = Color3.fromRGB(55, 55, 75),
					Thickness = 2,
				}):Play()
			end
		end)
	end
	
	-- Highlight the winning item with a glow tween
	if items[currentTargetIndex] and items[currentTargetIndex].frame then
		local winCard = items[currentTargetIndex].frame
		local winGlow = winCard:FindFirstChild("WinGlow")
		if winGlow then
			TweenService:Create(winGlow, TweenInfo.new(0.3), {
				Color = displayColor,
				Thickness = 6,
			}):Play()
		end
	end

	-- Camera shake for high rarities
	local shakeIntensity = rarityInfo and rarityInfo.shakeIntensity or 0
	if shakeIntensity > 0 then
		UIHelper.CameraShake(shakeIntensity * 0.1, 0.4)
	end

	-- Flash for legendary/mythic or effect items
	if data.rarity == "Legendary" or data.rarity == "Mythic" or effectInfo then
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.Size = UDim2.new(1, 0, 1, 0)
		flash.BackgroundColor3 = displayColor
		flash.BackgroundTransparency = 0.5
		flash.ZIndex = 100
		flash.Parent = screenGui

		TweenService:Create(flash, TweenInfo.new(0.5), {
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.5, function()
			flash:Destroy()
		end)
	end

	-- Notify callback (for inventory flash)
	if onSpinResult then
		task.spawn(onSpinResult, data)
	end
	
	-- Auto-close the window after showing the result
	task.spawn(function()
		task.wait(3.5) -- Show result for 3.5 seconds
		
		-- Fade out the received message
		if receivedMessage and receivedMessage.Parent then
			TweenService:Create(receivedMessage, TweenInfo.new(0.3), {
				BackgroundTransparency = 1,
			}):Play()
			local messageStroke = receivedMessage:FindFirstChildOfClass("UIStroke")
			if messageStroke then
				TweenService:Create(messageStroke, TweenInfo.new(0.3), {
					Transparency = 1,
				}):Play()
			end
			task.wait(0.3)
			if receivedMessage then
				receivedMessage:Destroy()
			end
		end
		
		-- Close the spin window
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
		Size = UDim2.new(0.5, 0, 0, 60),
		Position = UDim2.new(0.5, 0, 0.15, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(40, 10, 10),
		CornerRadius = DesignConfig.Layout.PanelCorner,
		StrokeColor = Rarities.ByName["Mythic"].color,
		Parent = screenGui,
	})

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
		tween.Completed:Connect(function()
			alert:Destroy()
		end)
	end)
end

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function SpinController.Init()
	screenGui = UIHelper.CreateScreenGui("SpinGui", 10)
	screenGui.Parent = playerGui

	spinContainer = UIHelper.CreateRoundedFrame({
		Name = "SpinContainer",
		Size = UDim2.new(0.45, 0, 0.85, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = DesignConfig.Colors.Background,
		CornerRadius = DesignConfig.Layout.ModalCorner,
		StrokeColor = Color3.fromRGB(80, 80, 120),
		Parent = screenGui,
	})
	spinContainer.Visible = false

	UIHelper.CreateLabel({
		Name = "SpinTitle",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "SPIN THE STREAMER",
		TextColor = Color3.fromRGB(200, 120, 255),
		Font = DesignConfig.Fonts.Accent,
		TextSize = DesignConfig.FontSizes.Title,
		Parent = spinContainer,
	})

	buildCarousel(spinContainer)
	buildResultDisplay(spinContainer)

	spinButton = UIHelper.CreateButton({
		Name = "SpinButton",
		Size = UDim2.new(0.4, 0, 0, 50),
		Position = UDim2.new(0.5, 0, 0.95, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = DesignConfig.Colors.Accent,
		HoverColor = Color3.fromRGB(0, 230, 120),
		Text = "SPIN  ($" .. Economy.SpinCost .. ")",
		TextColor = DesignConfig.Colors.White,
		Font = DesignConfig.Fonts.Primary,
		TextSize = DesignConfig.FontSizes.Header,
		CornerRadius = DesignConfig.Layout.ButtonCorner,
		StrokeColor = Color3.fromRGB(0, 255, 130),
		Parent = spinContainer,
	})

	spinButton.MouseButton1Click:Connect(function()
		SpinController.RequestSpin()
	end)

	-- Listen for spin results
	SpinResult.OnClientEvent:Connect(function(data)
		if data.success then
			playSpinAnimation(data, function()
				showResult(data)
				isSpinning = false
				spinButton.Text = "SPIN  ($" .. Economy.SpinCost .. ")"
			end)
		else
			isSpinning = false
			spinButton.Text = data.reason or "ERROR"
			task.delay(1.5, function()
				spinButton.Text = "SPIN  ($" .. Economy.SpinCost .. ")"
			end)
		end
	end)

	-- Listen for mythic alerts
	MythicAlert.OnClientEvent:Connect(function(data)
		showMythicAlert(data)
	end)
end

-------------------------------------------------
-- PUBLIC
-------------------------------------------------

function SpinController.RequestSpin()
	if isSpinning then return end
	isSpinning = true
	resultFrame.Visible = false
	
	-- Reset carousel position for new spin
	if carouselContainer then
		carouselContainer.Position = UDim2.new(0, 0, 0, 0)
	end
	-- Remove any lingering win glow from previous spin
	for _, item in ipairs(items) do
		if item.frame then
			local glow = item.frame:FindFirstChild("WinGlow")
			if glow then glow:Destroy() end
		end
	end

	-- Re-randomize cosmetic effects on every spin so the strip always
	-- looks fresh and exciting.  ~15% of cards get a random effect.
	local COSMETIC_CHANCE = 0.15
	for idx, item in ipairs(items) do
		local newEff = nil
		if math.random() < COSMETIC_CHANCE then
			newEff = Effects.List[math.random(1, #Effects.List)]
		end
		applyEffectToCard(idx, newEff and newEff.name or nil)
	end
	
	spinButton.Text = "SPINNING..."
	SpinRequest:FireServer()
end

function SpinController.Show()
	spinContainer.Visible = true
	UIHelper.ScaleIn(spinContainer, 0.3)
end

function SpinController.Hide()
	spinContainer.Visible = false
end

function SpinController.IsVisible(): boolean
	return spinContainer.Visible
end

--- Set callback for spin result (used by Main to flash inventory)
function SpinController.OnSpinResult(callback)
	onSpinResult = callback
end

return SpinController
