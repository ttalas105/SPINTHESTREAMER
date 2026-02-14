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
local skipButton
local isSpinning = false
local animationDone = false -- true after animation finishes and result is shown

-- Current spin cost & crate ID (set by SpinStandController or default)
local currentSpinCost = Economy.SpinCost
local currentCrateId = nil -- nil = regular spin, number = crate spin

-- Skip animation state
local skipRequested = false
local currentAnimConnection = nil -- RenderStepped connection for current animation

-- Queue: if player clicks spin during animation, queue next spin
local queuedSpinResult = nil -- server result data waiting for current anim to finish
local queuedSpinPending = false -- true if we sent a spin request but haven't got result yet

-- Spin generation: incremented each time a new spin starts.
-- Auto-close timers check this to avoid closing a newer spin.
local spinGeneration = 0

-- Callback for when a spin result arrives
local onSpinResult = nil

-- Carousel items
local ITEM_WIDTH = 130
local ITEM_HEIGHT = 155
local ITEM_GAP = 8 -- slightly wider gap for cleaner look
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
	carouselFrame.Size = UDim2.new(0.9, 0, 0, ITEM_HEIGHT + 30) -- slightly taller than items
	carouselFrame.Position = UDim2.new(0.5, 0, 0.44, 0)
	carouselFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	carouselFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 22)
	carouselFrame.BorderSizePixel = 0
	carouselFrame.ClipsDescendants = true
	carouselFrame.Parent = parent

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 12)
	frameCorner.Parent = carouselFrame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Name = "BorderStroke"
	frameStroke.Color = Color3.fromRGB(80, 60, 150)
	frameStroke.Thickness = 3
	frameStroke.Parent = carouselFrame

	-- Bright gradient line across the top (rainbow-ish, eye-catching)
	local topLine = Instance.new("Frame")
	topLine.Name = "TopLine"
	topLine.Size = UDim2.new(1, 0, 0, 4)
	topLine.Position = UDim2.new(0, 0, 0, 0)
	topLine.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
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
		cardCorner.CornerRadius = UDim.new(0, 10)
		cardCorner.Parent = card

		-- Card glow stroke (rarity-colored)
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Name = "CardStroke"
		cardStroke.Color = rarityColor
		cardStroke.Thickness = 2
		cardStroke.Transparency = 0.5
		cardStroke.Parent = card

		-- Gradient overlay for depth (top lighter, bottom darker)
		local cardGrad = Instance.new("UIGradient")
		cardGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 60, 80)),
		})
		cardGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		cardGrad.Rotation = 90
		cardGrad.Parent = card

		-- Thick bottom colour strip (rarity)
		local bottomStrip = Instance.new("Frame")
		bottomStrip.Name = "BottomStrip"
		bottomStrip.Size = UDim2.new(1, 0, 0, 5)
		bottomStrip.Position = UDim2.new(0, 0, 1, -5)
		bottomStrip.BackgroundColor3 = rarityColor
		bottomStrip.BorderSizePixel = 0
		bottomStrip.Parent = card

		-- Effect badge at the very top (cosmetic — creates excitement)
		if eff then
			local badge = Instance.new("TextLabel")
			badge.Name = "EffectTag"
			badge.Size = UDim2.new(1, -6, 0, 18)
			badge.Position = UDim2.new(0.5, 0, 0, 5)
			badge.AnchorPoint = Vector2.new(0.5, 0)
			badge.BackgroundTransparency = 1
			badge.Text = eff.prefix:upper()
			badge.TextColor3 = eff.color
			badge.Font = Enum.Font.FredokaOne
			badge.TextSize = 12
			badge.TextScaled = false
			badge.Parent = card
			local effStroke = Instance.new("UIStroke")
			effStroke.Color = Color3.fromRGB(0, 0, 0)
			effStroke.Thickness = 1
			effStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			effStroke.Parent = badge
		end

		-- Sparkle decoration only on cards that have an effect (Acid, Snow, etc.)
		if eff then
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

		-- Streamer name (center, bigger & bolder)
		local nameY = eff and 0.18 or 0.10
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "StreamerName"
		nameLabel.Size = UDim2.new(1, -10, 0, 50)
		nameLabel.Position = UDim2.new(0.5, 0, nameY, 0)
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = eff and (eff.prefix .. " " .. streamer.displayName) or streamer.displayName
		nameLabel.TextColor3 = eff and eff.color or Color3.new(1, 1, 1)
		nameLabel.Font = Enum.Font.FredokaOne
		nameLabel.TextSize = 16
		nameLabel.TextScaled = false
		nameLabel.TextWrapped = true
		nameLabel.Parent = card
		local nameStroke = Instance.new("UIStroke")
		nameStroke.Color = Color3.fromRGB(0, 0, 0)
		nameStroke.Thickness = 1.5
		nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		nameStroke.Parent = nameLabel

		-- Rarity label (bottom area, bigger)
		local rarLabel = Instance.new("TextLabel")
		rarLabel.Name = "RarityTag"
		rarLabel.Size = UDim2.new(1, -10, 0, 20)
		rarLabel.Position = UDim2.new(0.5, 0, 1, -30)
		rarLabel.AnchorPoint = Vector2.new(0.5, 0)
		rarLabel.BackgroundTransparency = 1
		rarLabel.Text = streamer.rarity:upper()
		rarLabel.TextColor3 = rarityColor
		rarLabel.Font = Enum.Font.FredokaOne
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
			effect = eff,  -- cosmetic effect (may be nil); winning card gets the real one
		}
	end

	-- Size the container to fit all cards
	local totalW = #items * ITEM_STEP
	carouselContainer.Size = UDim2.new(0, totalW, 1, 0)

	-- Center selector — glowing vertical line + big triangles
	local selectorLine = Instance.new("Frame")
	selectorLine.Name = "SelectorLine"
	selectorLine.Size = UDim2.new(0, 3, 1, 10)
	selectorLine.Position = UDim2.new(0.5, 0, 0.5, 0)
	selectorLine.AnchorPoint = Vector2.new(0.5, 0.5)
	selectorLine.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	selectorLine.BorderSizePixel = 0
	selectorLine.ZIndex = 10
	selectorLine.Parent = carouselFrame
	-- Glow around selector
	local selGlow = Instance.new("UIStroke")
	selGlow.Color = Color3.fromRGB(255, 100, 100)
	selGlow.Thickness = 2
	selGlow.Transparency = 0.4
	selGlow.Parent = selectorLine

	-- Top triangle (bigger, bolder)
	local topArrow = Instance.new("TextLabel")
	topArrow.Name = "TopArrow"
	topArrow.Size = UDim2.new(0, 30, 0, 22)
	topArrow.Position = UDim2.new(0.5, 0, 0, 0)
	topArrow.AnchorPoint = Vector2.new(0.5, 0)
	topArrow.BackgroundTransparency = 1
	topArrow.Text = "\u{25BC}"
	topArrow.TextColor3 = Color3.fromRGB(255, 60, 60)
	topArrow.Font = Enum.Font.GothamBold
	topArrow.TextSize = 22
	topArrow.ZIndex = 10
	topArrow.Parent = carouselFrame

	-- Bottom triangle
	local botArrow = Instance.new("TextLabel")
	botArrow.Name = "BotArrow"
	botArrow.Size = UDim2.new(0, 30, 0, 22)
	botArrow.Position = UDim2.new(0.5, 0, 1, 0)
	botArrow.AnchorPoint = Vector2.new(0.5, 1)
	botArrow.BackgroundTransparency = 1
	botArrow.Text = "\u{25B2}"
	botArrow.TextColor3 = Color3.fromRGB(255, 60, 60)
	botArrow.Font = Enum.Font.GothamBold
	botArrow.TextSize = 22
	botArrow.ZIndex = 10
	botArrow.Parent = carouselFrame

	-- Dark gradient edges (wider fade for cinematic depth)
	for _, side in ipairs({"Left", "Right"}) do
		local grad = Instance.new("Frame")
		grad.Name = "Fade" .. side
		grad.Size = UDim2.new(0, 100, 1, 0)
		grad.Position = side == "Left" and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -100, 0, 0)
		grad.BackgroundColor3 = Color3.fromRGB(12, 12, 22)
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
			existingBadge.Size = UDim2.new(1, -6, 0, 18)
			existingBadge.Position = UDim2.new(0.5, 0, 0, 5)
			existingBadge.AnchorPoint = Vector2.new(0.5, 0)
			existingBadge.BackgroundTransparency = 1
			existingBadge.Font = Enum.Font.FredokaOne
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

	-- Sparkle — show on effect cards, hide on non-effect cards
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
			nameLabel.Position = UDim2.new(0.5, 0, 0.10, 0)
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
	local done = false
	skipRequested = false

	-- Show skip button
	if skipButton then
		skipButton.Visible = true
	end

	-- Cleanup previous connection
	if currentAnimConnection then
		pcall(function() currentAnimConnection:Disconnect() end)
		currentAnimConnection = nil
	end

	local function finishAnimation()
		-- Snap to exact final position
		carouselContainer.Position = UDim2.new(0, endX, 0, 0)

		-- Hide skip button
		if skipButton then
			skipButton.Visible = false
		end

		-- Highlight the winning card
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
			if callback then
				callback()
			end
		end)
	end

	currentAnimConnection = RunService.RenderStepped:Connect(function()
		-- Check for skip
		if skipRequested and not done then
			done = true
			currentAnimConnection:Disconnect()
			currentAnimConnection = nil

			-- Quick tween to final position (0.3s fluid skip)
			local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(carouselContainer, tweenInfo, {
				Position = UDim2.new(0, endX, 0, 0),
			})
			tween:Play()
			tween.Completed:Connect(function()
				finishAnimation()
			end)
			return
		end

		local t = (tick() - startTime) / DURATION
		if t >= 1 then t = 1 end

		-- Smooth ease-out: fast at the start, graceful deceleration
		local eased = easeOutQuint(t)
		local currentX = startX - totalDist * eased
		carouselContainer.Position = UDim2.new(0, currentX, 0, 0)

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

	-- Make the message much taller if we have a model to show (big model!)
	local messageHeight = hasModel and 380 or 160
	local receivedMessage = UIHelper.CreateRoundedFrame({
		Name = "ReceivedMessage",
		Size = UDim2.new(0.65, 0, 0, messageHeight),
		Position = UDim2.new(0.5, 0, 0.22, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(18, 18, 30),
		CornerRadius = UDim.new(0, 18),
		StrokeColor = displayColor,
		StrokeThickness = 3,
		Parent = spinContainer,
	})
	receivedMessage.ZIndex = 20

	-- ViewportFrame showing the 3D model (if available) — BIG and prominent
	if hasModel then
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "ModelViewport"
		viewport.Size = UDim2.new(0, 220, 0, 220)
		viewport.Position = UDim2.new(0.5, 0, 0, 12)
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

		-- Position camera to frame the model nicely
		local ok, cf, size = pcall(function()
			return vpModel:GetBoundingBox()
		end)
		if ok and cf and size then
			local maxDim = math.max(size.X, size.Y, size.Z)
			local dist = maxDim * 1.6 -- closer for bigger appearance
			vpCamera.CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y * 0.15, dist), cf.Position)
		else
			vpCamera.CFrame = CFrame.new(Vector3.new(0, 2, 5), Vector3.new(0, 1, 0))
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
	local textYStart = hasModel and 235 or 10
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
	local messageText = Instance.new("TextLabel")
	messageText.Name = "MessageText"
	messageText.Size = UDim2.new(1, -20, 0, messageHeight - textYStart - 10)
	messageText.Position = UDim2.new(0.5, 0, 0, textYStart)
	messageText.AnchorPoint = Vector2.new(0.5, 0)
	messageText.BackgroundTransparency = 1
	messageText.Text = table.concat(messageLines, "\n")
	messageText.TextColor3 = displayColor
	messageText.Font = Enum.Font.FredokaOne
	messageText.TextSize = 20
	messageText.TextWrapped = true
	messageText.ZIndex = 21
	messageText.Parent = receivedMessage
	local msgStroke = Instance.new("UIStroke")
	msgStroke.Color = Color3.fromRGB(0, 0, 0)
	msgStroke.Thickness = 2
	msgStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	msgStroke.Parent = messageText
	
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
	
	-- Auto-close or start queued spin
	-- Capture the current generation so we can bail if a new spin started
	local myGeneration = spinGeneration

	task.spawn(function()
		-- If there's a queued spin result, start it immediately after a brief pause
		if queuedSpinResult then
			task.wait(1.0)
			if spinGeneration ~= myGeneration then return end -- new spin already started
			if receivedMessage and receivedMessage.Parent then
				receivedMessage:Destroy()
			end
			local nextData = queuedSpinResult
			queuedSpinResult = nil
			animationDone = false
			SpinController._startSpin(nextData)
			return
		end

		task.wait(3.5) -- Show result for 3.5 seconds

		-- Bail if a new spin started while we waited
		if spinGeneration ~= myGeneration then return end

		-- Check again if a spin was queued while we were showing result
		if queuedSpinResult then
			if receivedMessage and receivedMessage.Parent then
				receivedMessage:Destroy()
			end
			local nextData = queuedSpinResult
			queuedSpinResult = nil
			animationDone = false
			SpinController._startSpin(nextData)
			return
		end
		
		-- Bail again in case something changed
		if spinGeneration ~= myGeneration then return end

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
			if spinGeneration ~= myGeneration then return end
			if receivedMessage then
				receivedMessage:Destroy()
			end
		end
		
		-- No queued spin — close the window (only if still our generation)
		if spinGeneration ~= myGeneration then return end
		isSpinning = false
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
		Size = UDim2.new(0.55, 0, 0.88, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(15, 15, 25),
		CornerRadius = UDim.new(0, 18),
		StrokeColor = Color3.fromRGB(100, 60, 180),
		StrokeThickness = 3,
		Parent = screenGui,
	})
	spinContainer.Visible = false

	local spinTitle = Instance.new("TextLabel")
	spinTitle.Name = "SpinTitle"
	spinTitle.Size = UDim2.new(1, 0, 0, 48)
	spinTitle.Position = UDim2.new(0.5, 0, 0, 6)
	spinTitle.AnchorPoint = Vector2.new(0.5, 0)
	spinTitle.BackgroundTransparency = 1
	spinTitle.Text = "SPIN THE STREAMER"
	spinTitle.TextColor3 = Color3.fromRGB(255, 200, 80)
	spinTitle.Font = Enum.Font.FredokaOne
	spinTitle.TextSize = 34
	spinTitle.Parent = spinContainer
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(180, 80, 255)
	titleStroke.Thickness = 3
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	titleStroke.Parent = spinTitle

	buildCarousel(spinContainer)
	buildResultDisplay(spinContainer)

	spinButton = Instance.new("TextButton")
	spinButton.Name = "SpinButton"
	spinButton.Size = UDim2.new(0.5, 0, 0, 56)
	spinButton.Position = UDim2.new(0.5, 0, 0.94, 0)
	spinButton.AnchorPoint = Vector2.new(0.5, 0.5)
	spinButton.BackgroundColor3 = Color3.fromRGB(80, 255, 120)
	spinButton.Text = "SPIN  ($" .. currentSpinCost .. ")"
	spinButton.TextColor3 = Color3.fromRGB(10, 30, 15)
	spinButton.Font = Enum.Font.FredokaOne
	spinButton.TextSize = 24
	spinButton.BorderSizePixel = 0
	spinButton.Parent = spinContainer
	local spinBtnCorner = Instance.new("UICorner")
	spinBtnCorner.CornerRadius = UDim.new(0, 14)
	spinBtnCorner.Parent = spinButton
	local spinBtnStroke = Instance.new("UIStroke")
	spinBtnStroke.Color = Color3.fromRGB(0, 200, 80)
	spinBtnStroke.Thickness = 3
	spinBtnStroke.Parent = spinButton
	-- Gradient for the button
	local spinBtnGrad = Instance.new("UIGradient")
	spinBtnGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 255, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 200, 80)),
	})
	spinBtnGrad.Rotation = 90
	spinBtnGrad.Parent = spinButton

	spinButton.MouseButton1Click:Connect(function()
		SpinController.RequestSpin()
	end)

	-- Skip button (appears during spin animation)
	skipButton = Instance.new("TextButton")
	skipButton.Name = "SkipButton"
	skipButton.Size = UDim2.new(0, 100, 0, 36)
	skipButton.Position = UDim2.new(0.5, 0, 0.66, 0)
	skipButton.AnchorPoint = Vector2.new(0.5, 0.5)
	skipButton.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	skipButton.Text = "SKIP"
	skipButton.TextColor3 = Color3.fromRGB(220, 220, 240)
	skipButton.Font = Enum.Font.FredokaOne
	skipButton.TextSize = 18
	skipButton.BorderSizePixel = 0
	skipButton.Visible = false
	skipButton.ZIndex = 15
	skipButton.Parent = spinContainer
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 10)
	skipCorner.Parent = skipButton
	local skipStroke = Instance.new("UIStroke")
	skipStroke.Color = Color3.fromRGB(120, 120, 150)
	skipStroke.Thickness = 2
	skipStroke.Parent = skipButton

	skipButton.MouseButton1Click:Connect(function()
		skipRequested = true
	end)

	-- Listen for spin results
	SpinResult.OnClientEvent:Connect(function(data)
		if data.success then
			if queuedSpinPending then
				-- This result is for a queued spin — store it
				queuedSpinResult = data
				queuedSpinPending = false
			elseif isSpinning then
				-- We're waiting for the primary result — play animation
				SpinController._startSpin(data)
			else
				-- Normal flow: start the spin animation
				SpinController._startSpin(data)
			end
		else
			-- Error handling — if this was for a queued spin, just clear queue
			if queuedSpinPending then
				queuedSpinPending = false
				spinButton.Text = "SPIN AGAIN  ($" .. currentSpinCost .. ")"
			else
				isSpinning = false
				animationDone = false
			end
			spinButton.Text = data.reason or "ERROR"
			task.delay(1.5, function()
				spinButton.Text = "SPIN  ($" .. currentSpinCost .. ")"
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

--- Internal: prepare carousel and play animation for a spin result
function SpinController._startSpin(data)
	isSpinning = true
	animationDone = false
	spinGeneration = spinGeneration + 1
	resultFrame.Visible = false

	-- Clean up any existing received message
	local existingMsg = spinContainer:FindFirstChild("ReceivedMessage")
	if existingMsg then existingMsg:Destroy() end
	
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

	-- Re-randomize cosmetic effects
	local COSMETIC_CHANCE = 0.15
	for idx, item in ipairs(items) do
		local newEff = nil
		if math.random() < COSMETIC_CHANCE then
			newEff = Effects.List[math.random(1, #Effects.List)]
		end
		applyEffectToCard(idx, newEff and newEff.name or nil)
	end

	spinButton.Text = "SPINNING..."

	playSpinAnimation(data, function()
		animationDone = true
		showResult(data)
		-- Don't set isSpinning = false here; showResult's auto-close handles it
		spinButton.Text = "SPIN AGAIN  ($" .. currentSpinCost .. ")"
	end)
end

function SpinController.RequestSpin()
	-- If animation is done (result screen showing), start next spin immediately
	if isSpinning and animationDone then
		-- Clean up result display and start fresh
		local existingMsg = spinContainer:FindFirstChild("ReceivedMessage")
		if existingMsg then existingMsg:Destroy() end

		isSpinning = true
		animationDone = false
		resultFrame.Visible = false
		spinButton.Text = "SPINNING..."

		-- Fire the appropriate spin request
		if currentCrateId then
			local BuyCrateRequest = RemoteEvents:WaitForChild("BuyCrateRequest")
			BuyCrateRequest:FireServer(currentCrateId)
		else
			SpinRequest:FireServer()
		end
		return
	end

	-- If animation is still playing (cards scrolling), queue a next spin
	if isSpinning and not animationDone then
		-- Only allow one queued spin at a time
		if queuedSpinPending then return end
		queuedSpinPending = true
		spinButton.Text = "QUEUED..."

		-- Fire the appropriate spin request
		if currentCrateId then
			local BuyCrateRequest = RemoteEvents:WaitForChild("BuyCrateRequest")
			BuyCrateRequest:FireServer(currentCrateId)
		else
			SpinRequest:FireServer()
		end
		return
	end

	-- Normal first spin (not spinning at all)
	isSpinning = true
	animationDone = false
	resultFrame.Visible = false

	spinButton.Text = "SPINNING..."

	-- Fire the appropriate spin request
	if currentCrateId then
		local BuyCrateRequest = RemoteEvents:WaitForChild("BuyCrateRequest")
		BuyCrateRequest:FireServer(currentCrateId)
	else
		SpinRequest:FireServer()
	end
end

function SpinController.Show()
	spinContainer.Visible = true
	spinButton.Text = "SPIN  ($" .. currentSpinCost .. ")"
	UIHelper.ScaleIn(spinContainer, 0.3)
end

function SpinController.Hide()
	spinContainer.Visible = false
	-- Reset queue state
	queuedSpinResult = nil
	queuedSpinPending = false
	isSpinning = false
	animationDone = false
	if skipButton then skipButton.Visible = false end
	if currentAnimConnection then
		pcall(function() currentAnimConnection:Disconnect() end)
		currentAnimConnection = nil
	end
end

function SpinController.IsVisible(): boolean
	return spinContainer.Visible
end

--- Set the cost displayed on the spin button (called by SpinStandController)
function SpinController.SetCurrentCost(cost: number)
	currentSpinCost = cost
	if spinButton and not isSpinning then
		spinButton.Text = "SPIN  ($" .. currentSpinCost .. ")"
	end
end

--- Set the crate ID for crate spins (nil = regular spin)
function SpinController.SetCurrentCrateId(crateId)
	currentCrateId = crateId
end

--- Set callback for spin result (used by Main to flash inventory)
function SpinController.OnSpinResult(callback)
	onSpinResult = callback
end

return SpinController
