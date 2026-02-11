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
local ITEM_WIDTH = 180 -- Larger items for better visibility
local ITEM_SPACING = 40 -- More spacing so items are clearly separated
local items = {}
local currentTargetIndex = 1

-------------------------------------------------
-- BUILD CAROUSEL (CS:GO Style)
-------------------------------------------------

local function buildCarousel(parent)
	-- Main carousel frame with circular viewport - larger for better visibility
	carouselFrame = UIHelper.CreateRoundedFrame({
		Name = "CarouselFrame",
		Size = UDim2.new(0, 600, 0, 320),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(20, 20, 30),
		CornerRadius = UDim.new(0, 0),
		StrokeColor = Color3.fromRGB(60, 60, 80),
		Parent = parent,
	})

	-- Circular mask/viewport overlay (dark translucent circle) - larger for better visibility
	local viewportMask = UIHelper.CreateRoundedFrame({
		Name = "ViewportMask",
		Size = UDim2.new(0, 500, 0, 500),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(0, 0, 0),
		CornerRadius = UDim.new(1, 0),
		Transparency = 0.6, -- Less transparent so items are more visible
		Parent = carouselFrame,
	})
	viewportMask.ZIndex = 5

	-- Inner container that will scroll horizontally
	-- Make it wide enough to hold all items (will be calculated after we know how many items)
	carouselContainer = Instance.new("Frame")
	carouselContainer.Name = "CarouselContainer"
	carouselContainer.Size = UDim2.new(1, 0, 1, 0) -- Will be resized after items are created
	carouselContainer.Position = UDim2.new(0, 0, 0, 0)
	carouselContainer.AnchorPoint = Vector2.new(0, 0)
	carouselContainer.BackgroundTransparency = 1
	carouselContainer.ClipsDescendants = true
	carouselContainer.Parent = carouselFrame

	-- Create items from streamers list - include ALL streamers, repeat 3 times for smooth scrolling
	-- Some items randomly get an effect (like Acid) for visual variety during the spin
	local allStreamers = {}
	local allEffects = {} -- parallel array: effect name or nil per item
	local repeatCount = 3
	for repeatNum = 1, repeatCount do
		for _, streamer in ipairs(Streamers.List) do
			table.insert(allStreamers, streamer)
			-- Random ~15% of carousel items show the Acid effect label (cosmetic during spin)
			local eff = nil
			for _, e in ipairs(Effects.List) do
				if math.random() < (e.rollChance or 0) then
					eff = e
					break
				end
			end
			table.insert(allEffects, eff)
		end
	end

	-- Create item frames
	for i, streamer in ipairs(allStreamers) do
		local eff = allEffects[i]
		local bgColor = Rarities.ByName[streamer.rarity] and Rarities.ByName[streamer.rarity].color or Color3.fromRGB(100, 100, 100)
		-- If item has effect, tint the background slightly with effect color
		if eff then
			bgColor = Color3.fromRGB(
				math.floor(bgColor.R * 255 * 0.5 + eff.color.R * 255 * 0.5),
				math.floor(bgColor.G * 255 * 0.5 + eff.color.G * 255 * 0.5),
				math.floor(bgColor.B * 255 * 0.5 + eff.color.B * 255 * 0.5)
			)
		end

		local itemFrame = UIHelper.CreateRoundedFrame({
			Name = "Item_" .. i .. "_" .. streamer.id,
			Size = UDim2.new(0, ITEM_WIDTH, 0, ITEM_WIDTH),
			Position = UDim2.new(0, (i - 1) * (ITEM_WIDTH + ITEM_SPACING), 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Color = bgColor,
			CornerRadius = DesignConfig.Layout.ButtonCorner,
			Parent = carouselContainer,
		})

		-- Glow effect (will be animated)
		local glowStroke = Instance.new("UIStroke")
		glowStroke.Color = eff and eff.glowColor or (Rarities.ByName[streamer.rarity] and Rarities.ByName[streamer.rarity].color or Color3.fromRGB(100, 100, 100))
		glowStroke.Thickness = 0
		glowStroke.Transparency = 0.5
		glowStroke.Parent = itemFrame

		-- Effect tag (e.g. "ACID") — bright green label at the top
		if eff then
			UIHelper.CreateLabel({
				Name = "EffectTag",
				Size = UDim2.new(1, -8, 0, 18),
				Position = UDim2.new(0.5, 0, 0, 3),
				AnchorPoint = Vector2.new(0.5, 0),
				Text = eff.prefix:upper(),
				TextColor = eff.color,
				Font = DesignConfig.Fonts.Accent,
				TextSize = 14,
				TextScaled = false,
				Parent = itemFrame,
			})
		end

		-- Streamer name (full name for clarity) - larger and more visible
		local nameYPos = eff and 0.16 or 0.12
		local nameLabel = UIHelper.CreateLabel({
			Name = "StreamerName",
			Size = UDim2.new(1, -12, 0, 50),
			Position = UDim2.new(0.5, 0, nameYPos, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			Text = eff and (eff.prefix .. " " .. streamer.displayName) or streamer.displayName,
			TextColor = eff and eff.color or DesignConfig.Colors.White,
			Font = DesignConfig.Fonts.Primary,
			TextSize = 18,
			TextScaled = false,
			Parent = itemFrame,
		})
		nameLabel.TextWrapped = true

		-- Rarity tag (larger and more visible) - bold and clear
		local rarityColor = Rarities.ByName[streamer.rarity] and Rarities.ByName[streamer.rarity].color or Color3.fromRGB(170, 170, 170)
		UIHelper.CreateLabel({
			Name = "RarityTag",
			Size = UDim2.new(1, -12, 0, 35),
			Position = UDim2.new(0.5, 0, 0.75, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			Text = streamer.rarity:upper(),
			TextColor = rarityColor,
			Font = DesignConfig.Fonts.Accent,
			TextSize = 18,
			TextScaled = false,
			Parent = itemFrame,
		})

		items[i] = {
			frame = itemFrame,
			streamer = streamer,
			effect = eff,
			glowStroke = glowStroke,
			baseX = (i - 1) * (ITEM_WIDTH + ITEM_SPACING),
		}
	end
	
	-- Resize container to fit all items
	local totalWidth = #items * (ITEM_WIDTH + ITEM_SPACING) + ITEM_SPACING
	carouselContainer.Size = UDim2.new(0, totalWidth, 1, 0)

	-- Pointer indicator (inverted triangle at top center)
	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.Size = UDim2.new(0, 30, 0, 20)
	pointer.Position = UDim2.new(0.5, 0, 0, -8)
	pointer.AnchorPoint = Vector2.new(0.5, 0)
	pointer.BackgroundTransparency = 1
	pointer.ZIndex = 10
	pointer.Parent = carouselFrame

	-- Create triangle shape
	local triangleLabel = Instance.new("TextLabel")
	triangleLabel.Size = UDim2.new(1, 0, 1, 0)
	triangleLabel.BackgroundTransparency = 1
	triangleLabel.Text = "▼"
	triangleLabel.TextColor3 = DesignConfig.Colors.Danger
	triangleLabel.Font = Enum.Font.GothamBold
	triangleLabel.TextSize = 24
	triangleLabel.TextScaled = false
	triangleLabel.Parent = pointer

	-- Center highlight glow (blue glow beneath center items) - larger and more visible
	local centerGlow = UIHelper.CreateRoundedFrame({
		Name = "CenterGlow",
		Size = UDim2.new(0, ITEM_WIDTH + 40, 0, ITEM_WIDTH + 40),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Color3.fromRGB(60, 130, 255),
		CornerRadius = DesignConfig.Layout.ButtonCorner,
		Transparency = 0.7, -- More visible
		Parent = carouselFrame,
	})
	centerGlow.ZIndex = 1

	local glowStroke = Instance.new("UIStroke")
	glowStroke.Color = Color3.fromRGB(60, 130, 255)
	glowStroke.Thickness = 4 -- Thicker for better visibility
	glowStroke.Transparency = 0.2
	glowStroke.Parent = centerGlow

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
-- SPIN ANIMATION (Horizontal CS:GO Style)
-------------------------------------------------

local function updateItemVisuals()
	if not carouselContainer or not carouselFrame then return end
	local ok, err = pcall(function()
	-- Calculate center position relative to carousel container
	local containerWidth = carouselFrame.AbsoluteSize.X
	if containerWidth == 0 then return end -- UI not rendered yet
	
	local centerX = containerWidth / 2
	
	for i, item in ipairs(items) do
		if not item.frame or not item.frame.Parent then continue end
		
		-- Calculate item's center position
		local itemAbsSize = item.frame.AbsoluteSize.X
		if itemAbsSize == 0 then continue end -- Item not rendered yet
		
		local itemX = item.frame.AbsolutePosition.X + itemAbsSize / 2
		local distanceFromCenter = math.abs(itemX - centerX)
		local maxDistance = containerWidth / 2 + ITEM_WIDTH
		local normalizedDistance = math.min(distanceFromCenter / maxDistance, 1)
		
		-- Scale: smaller when further from center (CS:GO style) - but keep center items large
		local scale = 1 - (normalizedDistance * 0.4) -- Less scaling so items stay more visible
		scale = math.max(scale, 0.5) -- Minimum scale of 50% so items are always readable
		item.frame.Size = UDim2.new(0, ITEM_WIDTH * scale, 0, ITEM_WIDTH * scale)
		
		-- Transparency: more transparent when further from center (blur effect) - but keep readable
		local transparency = normalizedDistance * 0.5 -- Less transparency so items stay visible
		item.frame.BackgroundTransparency = transparency
		
		-- Glow: brighter when closer to center - make it more visible
		if item.glowStroke then
			local glowIntensity = 1 - normalizedDistance
			if normalizedDistance < 0.3 then
				-- Strong glow for center items - more visible
				local rarityColor = Rarities.ByName[item.streamer.rarity] and Rarities.ByName[item.streamer.rarity].color or Color3.fromRGB(100, 100, 100)
				item.glowStroke.Color = rarityColor
				item.glowStroke.Thickness = 6 * glowIntensity -- Thicker glow
				item.glowStroke.Transparency = 0.2 - (glowIntensity * 0.15) -- More visible
			else
				item.glowStroke.Thickness = 0
			end
		end
		
		-- Text transparency - keep text readable
		local nameLabel = item.frame:FindFirstChild("StreamerName")
		local rarityLabel = item.frame:FindFirstChild("RarityTag")
		local effectTag = item.frame:FindFirstChild("EffectTag")
		if nameLabel then
			nameLabel.TextTransparency = transparency * 0.3 -- Keep text very visible
		end
		if rarityLabel then
			rarityLabel.TextTransparency = transparency * 0.3 -- Keep rarity visible
		end
		if effectTag then
			effectTag.TextTransparency = transparency * 0.3
		end
	end
	end)
	if not ok and err then
		-- Don't spam; visuals will retry next frame
	end
end

local function playSpinAnimation(resultData, callback)
	if not carouselContainer then return end
	
	-- Find target streamer index in items array using streamerId from server
	-- Prefer the second occurrence (middle of the 3 repeats) for better animation feel
	local targetIndex = nil
	local occurrences = {}
	local targetStreamerId = resultData.streamerId or resultData.id -- Support both formats
	
	for i, item in ipairs(items) do
		if item.streamer.id == targetStreamerId then
			table.insert(occurrences, i)
		end
	end
	
	-- Use the second occurrence if available, otherwise first, otherwise fallback
	if #occurrences >= 2 then
		targetIndex = occurrences[2] -- Use second occurrence (middle set)
	elseif #occurrences >= 1 then
		targetIndex = occurrences[1] -- Use first occurrence
	else
		-- Fallback: try to find by displayName if id doesn't match
		for i, item in ipairs(items) do
			if item.streamer.displayName == resultData.displayName then
				table.insert(occurrences, i)
			end
		end
		if #occurrences >= 1 then
			targetIndex = occurrences[1]
		else
			targetIndex = 1 -- Final fallback
		end
	end
	
	currentTargetIndex = targetIndex
	
	-- Calculate target position (center the target item properly)
	local carouselWidth = carouselFrame.AbsoluteSize.X
	if carouselWidth == 0 then
		-- Fallback to known size from buildCarousel
		carouselWidth = 600
	end
	
	local carouselCenter = carouselWidth / 2
	-- Item position relative to container: (targetIndex - 1) * (ITEM_WIDTH + ITEM_SPACING)
	-- Item center relative to container: (targetIndex - 1) * (ITEM_WIDTH + ITEM_SPACING) + ITEM_WIDTH/2
	-- To center the item: containerX = carouselCenter - itemCenterX
	local itemCenterX = (targetIndex - 1) * (ITEM_WIDTH + ITEM_SPACING) + (ITEM_WIDTH / 2)
	local finalTargetX = carouselCenter - itemCenterX
	
	-- Add extra distance for multiple spins (make it feel like multiple rotations)
	-- Use one full set of streamers as the rotation distance
	local extraSpins = 2.5 -- Number of full rotations
	local fullRotationDistance = #Streamers.List * (ITEM_WIDTH + ITEM_SPACING) -- One full set of all streamers
	
	-- Store the final target position for use at the end
	local finalPosition = finalTargetX
	
	-- CS:GO style duration - fast start, slow end
	local duration = 5.0 -- Total duration
	local startTime = tick()
	local startX = carouselContainer.Position.X.Offset
	
	-- Calculate where we need to start from to end up at finalPosition after extraSpins
	-- We want to start further back so that after spinning extraSpins times, we land at finalPosition
	local startPosition = finalPosition - (extraSpins * fullRotationDistance)
	
	-- Calculate the total distance to travel
	local totalDistance = finalPosition - startPosition
	
	-- Set the starting position immediately so animation is smooth
	carouselContainer.Position = UDim2.new(0, startPosition, 0, 0)
	local actualStartX = startPosition
	
	-- Animation loop with smooth easing
	local connection
	local hasCompleted = false
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		if elapsed >= duration then
			if not hasCompleted then
				hasCompleted = true
				connection:Disconnect()
				-- Snap to final position - use the pre-calculated finalPosition
				carouselContainer.Position = UDim2.new(0, finalPosition, 0, 0)
				updateItemVisuals()
				
				-- Ensure the winning item is clearly visible immediately
				task.spawn(function()
					task.wait(0.1) -- Brief wait for UI to update
					updateItemVisuals()
					
					-- Ensure the winning item is clearly visible
					if items[targetIndex] and items[targetIndex].frame then
						local winningItem = items[targetIndex].frame
						if winningItem then
							winningItem.Size = UDim2.new(0, ITEM_WIDTH, 0, ITEM_WIDTH)
							winningItem.BackgroundTransparency = 0
							local winningGlow = winningItem:FindFirstChildOfClass("UIStroke")
							if winningGlow then
								local rarityColor = Rarities.ByName[items[targetIndex].streamer.rarity] and Rarities.ByName[items[targetIndex].streamer.rarity].color or Color3.fromRGB(100, 100, 100)
								winningGlow.Color = rarityColor
								winningGlow.Thickness = 8
								winningGlow.Transparency = 0
							end
							
							-- Make sure text is visible
							local nameLabel = winningItem:FindFirstChild("StreamerName")
							local rarityLabel = winningItem:FindFirstChild("RarityTag")
							if nameLabel then
								nameLabel.TextTransparency = 0
								nameLabel.TextColor3 = DesignConfig.Colors.White
							end
							if rarityLabel then
								rarityLabel.TextTransparency = 0
								local rarityColor = Rarities.ByName[items[targetIndex].streamer.rarity] and Rarities.ByName[items[targetIndex].streamer.rarity].color or Color3.fromRGB(170, 170, 170)
								rarityLabel.TextColor3 = rarityColor
							end
						end
					end
					
					-- Brief pause to show the result clearly before callback
					task.wait(1.0) -- Give time to see the result
					if callback then
						callback()
					end
				end)
			end
			return
		end
		
		local progress = elapsed / duration
		
		-- CS:GO style easing: VERY fast start, dramatic slowdown at end
		-- First 75% of time covers 90% of distance (very fast)
		-- Last 25% of time covers 10% of distance (very slow, visible)
		local eased
		if progress < 0.75 then
			-- Fast phase - very quick scrolling (first 75% of time covers 90% of distance)
			local fastProgress = progress / 0.75
			-- Ease in cubic for accelerating start
			local fastEased = fastProgress ^ 3
			eased = fastEased * 0.9
		else
			-- Slow phase - dramatic slowdown for visibility (last 25% of time covers 10% of distance)
			local slowProgress = (progress - 0.75) / 0.25
			-- Ease out exponential for very smooth, dramatic deceleration
			local slowEased = 1 - (2 ^ (-10 * slowProgress)) -- Exponential ease out
			eased = 0.9 + (slowEased * 0.1) -- Final 10% of distance in last 25% of time
		end
		
		-- Calculate current position using eased progress
		-- Use actualStartX instead of startX to ensure consistency
		local currentX = actualStartX + totalDistance * eased
		carouselContainer.Position = UDim2.new(0, currentX, 0, 0)
		
		-- Update visual effects in real-time to keep items visible
		updateItemVisuals()
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
	
	-- Show a prominent "You received..." message with odds
	local receivedMessage = UIHelper.CreateRoundedFrame({
		Name = "ReceivedMessage",
		Size = UDim2.new(0.6, 0, 0, 140),
		Position = UDim2.new(0.5, 0, 0.25, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = DesignConfig.Colors.BackgroundLight,
		CornerRadius = DesignConfig.Layout.PanelCorner,
		StrokeColor = displayColor,
		Parent = spinContainer,
	})
	receivedMessage.ZIndex = 20
	
	local messageLines = { "YOU RECEIVED:", data.displayName or "Unknown", (data.rarity or "Common"):upper() }
	if effectInfo then
		table.insert(messageLines, effectInfo.prefix:upper() .. " EFFECT (x" .. effectInfo.cashMultiplier .. " CASH)")
	end
	if oddsText ~= "" then
		table.insert(messageLines, oddsText)
	end
	local messageText = UIHelper.CreateLabel({
		Name = "MessageText",
		Size = UDim2.new(1, -20, 1, -20),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = table.concat(messageLines, "\n"),
		TextColor = displayColor,
		Font = DesignConfig.Fonts.Accent,
		TextSize = 22,
		Parent = receivedMessage,
	})
	messageText.TextScaled = false
	
	UIHelper.ScaleIn(receivedMessage, 0.3)

	-- Glow carousel border
	local stroke = carouselFrame:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.3), {
			Color = displayColor,
			Thickness = 4,
		}):Play()
		task.delay(2, function()
			TweenService:Create(stroke, TweenInfo.new(0.5), {
				Color = Color3.fromRGB(60, 60, 80),
				Thickness = 2,
			}):Play()
		end)
	end
	
	-- Highlight the winning item
	if items[currentTargetIndex] and items[currentTargetIndex].frame then
		local winningItem = items[currentTargetIndex].frame
		local winningGlow = winningItem:FindFirstChildOfClass("UIStroke")
		if winningGlow then
			TweenService:Create(winningGlow, TweenInfo.new(0.3), {
				Color = displayColor,
				Thickness = 6,
				Transparency = 0,
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
	
	-- Reset carousel position for new spin (no blocking wait)
	if carouselContainer then
		carouselContainer.Position = UDim2.new(0, 0, 0, 0)
		updateItemVisuals()
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
