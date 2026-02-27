--[[
	IndexController.lua
	Collection / Index UI — "Pokédex" for streamers.
	Sidebar tabs for Default + each effect. Locked = fully black silhouette + "???".
	Unlocked = spinning 3D model + name. Gem claiming (one-time per combo).
	Optimized: only visible cards get Heartbeat connections, snapshot prevents rebuilds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Streamers = require(ReplicatedStorage.Shared.Config.Streamers)
local Effects = require(ReplicatedStorage.Shared.Config.Effects)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local UIHelper = require(script.Parent.UIHelper)
local HUDController = require(script.Parent.HUDController)

local IndexController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ClaimIndexGems = RemoteEvents:WaitForChild("ClaimIndexGems")
local ClaimIndexResult = RemoteEvents:WaitForChild("ClaimIndexResult")

local screenGui
local modalFrame
local isOpen = false
local contentGrid
local sidebarBtns = {}
local activeTab = nil
local counterLabel
local claimAllBtn
local lastSnapshot = ""
local isClaimAllRunning = false
local needsGridRefreshAfterClaimAll = false
local skipNextDataRebuild = false
local currentBuildToken = 0

-- Single shared Heartbeat for ALL viewport rotations (performance)
local viewportData = {} -- { {camera, target, dist, camY, angle} }
local heartbeatConn = nil

local FONT = Enum.Font.FredokaOne

-- Book image for Index header. Upload your image in Roblox (Create > Decals & Images), then set to "rbxassetid://YOUR_ID"
local INDEX_BOOK_ASSET_ID = "rbxassetid://0"

local LeftSideNavController = require(script.Parent.LeftSideNavController)

local TABS = { { name = "Default", effect = nil, color = Color3.fromRGB(200, 200, 220) } }
for _, eff in ipairs(Effects.List) do
	table.insert(TABS, { name = eff.name, effect = eff.name, color = eff.color })
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function getIndexKey(streamerId, effect)
	if effect then return effect .. ":" .. streamerId end
	return streamerId
end

-- Count unclaimed streamers for a specific tab (nil = Default)
local function countUnclaimedForTab(tabEffect)
	local indexCol = HUDController.Data.indexCollection or {}
	local count = 0
	for _, info in ipairs(Streamers.List) do
		local key = getIndexKey(info.id, tabEffect)
		local val = indexCol[key]
		if val ~= nil and val ~= "claimed" then
			count = count + 1
		end
	end
	return count
end

local function getTabNameByEffect(tabEffect)
	for _, tab in ipairs(TABS) do
		if tab.effect == tabEffect then
			return tab.name
		end
	end
	return "Default"
end

local function getClaimableEntriesForTab(tabEffect)
	local indexCol = HUDController.Data.indexCollection or {}
	local entries = {}
	for _, info in ipairs(Streamers.List) do
		local key = getIndexKey(info.id, tabEffect)
		local value = indexCol[key]
		if value ~= nil and value ~= "claimed" then
			table.insert(entries, info)
		end
	end
	return entries
end

local function getClaimableEntriesAllTabs()
	local all = {}
	for _, tab in ipairs(TABS) do
		local tabEntries = getClaimableEntriesForTab(tab.effect)
		for _, info in ipairs(tabEntries) do
			table.insert(all, {
				id = info.id,
				effect = tab.effect,
			})
		end
	end
	return all
end

-- Count total unclaimed across ALL tabs
local function countTotalUnclaimed()
	local total = 0
	for _, tab in ipairs(TABS) do
		total = total + countUnclaimedForTab(tab.effect)
	end
	return total
end

-- Update the Index nav button badge
local function updateNavBadge()
	local count = countTotalUnclaimed()
	LeftSideNavController.SetBadge("Index", count)
end

local function updateClaimAllButton()
	if not claimAllBtn then return end

	local unclaimed = countTotalUnclaimed()
	local enabled = (unclaimed > 0) and (not isClaimAllRunning)

	claimAllBtn.AutoButtonColor = enabled
	claimAllBtn.Active = enabled
	claimAllBtn.BackgroundColor3 = enabled and Color3.fromRGB(90, 170, 255) or Color3.fromRGB(75, 75, 90)
	claimAllBtn.TextTransparency = enabled and 0 or 0.2

	if isClaimAllRunning then
		claimAllBtn.Text = "Claiming..."
	elseif unclaimed > 0 then
		claimAllBtn.Text = "Claim All (" .. unclaimed .. ")"
	else
		claimAllBtn.Text = "No Claims Available"
	end
end

local function setCardClaimedVisual(card)
	if not card then return end

	local claimBtn = card:FindFirstChild("ClaimBtn")
	if claimBtn then claimBtn:Destroy() end

	local exclBadge = card:FindFirstChild("ExclBadge")
	if exclBadge then exclBadge:Destroy() end

	local existing = card:FindFirstChild("ClaimedLabel")
	if existing then return end

	local cl = Instance.new("TextLabel")
	cl.Name = "ClaimedLabel"
	cl.Size = UDim2.new(1, -16, 0, 28)
	cl.Position = UDim2.new(0.5, 0, 1, -8)
	cl.AnchorPoint = Vector2.new(0.5, 1)
	cl.BackgroundTransparency = 1
	cl.Text = "\u{2705} Claimed"
	cl.TextColor3 = Color3.fromRGB(120, 230, 120)
	cl.Font = FONT
	cl.TextSize = 16
	cl.Parent = card
	local clStroke = Instance.new("UIStroke")
	clStroke.Color = Color3.fromRGB(0, 0, 0)
	clStroke.Thickness = 1
	clStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	clStroke.Parent = cl
end

local function buildSnapshot()
	local indexCol = HUDController.Data.indexCollection or {}
	local parts = {}
	local tabEffect = activeTab
	for i, info in ipairs(Streamers.List) do
		local key = getIndexKey(info.id, tabEffect)
		local val = indexCol[key]
		parts[i] = key .. ":" .. tostring(val or "nil")
	end
	return table.concat(parts, "|")
end

-- Stop all viewport rotations
local function stopRotations()
	viewportData = {}
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

-- Start the single shared Heartbeat for all viewports
local function startRotationLoop()
	if heartbeatConn then return end
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		for i = #viewportData, 1, -1 do
			local d = viewportData[i]
			if not d.camera or not d.camera.Parent then
				table.remove(viewportData, i)
			else
				d.angle = d.angle + dt * d.speed
				d.camera.CFrame = CFrame.new(
					d.target + Vector3.new(math.sin(d.angle) * d.dist, d.camY, math.cos(d.angle) * d.dist),
					d.target
				)
			end
		end
		if #viewportData == 0 and heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
	end)
end

-------------------------------------------------
-- BUILD SINGLE CARD
-------------------------------------------------
local function buildStreamerCard(info, effect, parent, cardIndex)
	local indexCol = HUDController.Data.indexCollection or {}
	local key = getIndexKey(info.id, effect)
	local isUnlocked = indexCol[key] ~= nil
	local isClaimed = indexCol[key] == "claimed"

	local effectInfo = effect and Effects.ByName[effect] or nil
	local rarityInfo = Rarities.ByName[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(170, 170, 170)
	local displayColor = effectInfo and effectInfo.color or rarityColor
	local gemReward = Economy.GetIndexGemReward(info.rarity, effect)

	local card = Instance.new("Frame")
	card.Name = "IndexCard_" .. cardIndex
	card.Size = UDim2.new(0, 180, 0, 240)
	card.BackgroundColor3 = isUnlocked and Color3.fromRGB(50, 40, 80) or Color3.fromRGB(35, 28, 58)
	card.BorderSizePixel = 0
	card.LayoutOrder = cardIndex
	card:SetAttribute("IndexKey", key)
	card.Parent = parent

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 18)
	cCorner.Parent = card

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = isUnlocked and displayColor or Color3.fromRGB(80, 65, 120)
	cStroke.Thickness = isUnlocked and 2.5 or 2
	cStroke.Transparency = isUnlocked and 0.1 or 0.4
	cStroke.Parent = card

	local cardGrad = Instance.new("UIGradient")
	cardGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 220)),
	})
	cardGrad.Rotation = 90
	cardGrad.Parent = card

	-- Viewport
	local vpSize = 140
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ModelVP"
	viewport.Size = UDim2.new(1, -16, 0, vpSize)
	viewport.Position = UDim2.new(0.5, 0, 0, 10)
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.BackgroundColor3 = isUnlocked and Color3.fromRGB(25, 20, 45) or Color3.fromRGB(18, 14, 32)
	viewport.BackgroundTransparency = 0
	viewport.BorderSizePixel = 0
	viewport.Parent = card
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 14)
	vpCorner.Parent = viewport
	local vpStroke = Instance.new("UIStroke")
	vpStroke.Color = isUnlocked and displayColor or Color3.fromRGB(60, 50, 90)
	vpStroke.Thickness = 1.5
	vpStroke.Transparency = 0.5
	vpStroke.Parent = viewport

	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	local modelTemplate = modelsFolder and modelsFolder:FindFirstChild(info.id)

	if modelTemplate then
		local vpModel = modelTemplate:Clone()

		if not isUnlocked then
			for _, desc in ipairs(vpModel:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Color = Color3.fromRGB(15, 12, 25)
					desc.Material = Enum.Material.SmoothPlastic
					desc.Transparency = 0
					desc.Reflectance = 0
				elseif desc:IsA("Decal") or desc:IsA("Texture") or desc:IsA("SurfaceAppearance") then
					desc:Destroy()
				elseif desc:IsA("Shirt") or desc:IsA("Pants") or desc:IsA("ShirtGraphic") or desc:IsA("CharacterMesh") then
					desc:Destroy()
				elseif desc:IsA("Accessory") or desc:IsA("Hat") then
					desc:Destroy()
				elseif desc:IsA("SpecialMesh") then
					desc.TextureId = ""
				end
			end
		end

		vpModel.Parent = viewport

		local vpCamera = Instance.new("Camera")
		vpCamera.Parent = viewport
		viewport.CurrentCamera = vpCamera

		local ok, cf, size = pcall(function() return vpModel:GetBoundingBox() end)
		if ok and cf and size then
			local maxDim = math.max(size.X, size.Y, size.Z)
			local dist = maxDim * 1.8
			local target = cf.Position
			local camYOffset = size.Y * 0.15
			local speed = isUnlocked and 0.8 or 0.3

			vpCamera.CFrame = CFrame.new(
				target + Vector3.new(0, camYOffset, dist), target
			)

			table.insert(viewportData, {
				camera = vpCamera,
				target = target,
				dist = dist,
				camY = camYOffset,
				angle = math.random() * math.pi * 2,
				speed = speed,
			})
			startRotationLoop()
		end
	else
		local ph = Instance.new("TextLabel")
		ph.Size = UDim2.new(1, 0, 1, 0)
		ph.BackgroundTransparency = 1
		ph.Text = isUnlocked and "\u{1F3AD}" or "\u{2753}"
		ph.TextSize = isUnlocked and 42 or 36
		ph.TextColor3 = isUnlocked and Color3.new(1, 1, 1) or Color3.fromRGB(70, 55, 100)
		ph.Font = Enum.Font.SourceSans
		ph.Parent = viewport
	end

	-- Name
	local nameText = isUnlocked and info.displayName or "???"
	if isUnlocked and effectInfo then
		nameText = effectInfo.prefix .. " " .. nameText
	end
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -10, 0, 24)
	nameLabel.Position = UDim2.new(0.5, 0, 0, vpSize + 14)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = nameText
	nameLabel.TextColor3 = isUnlocked and displayColor or Color3.fromRGB(100, 85, 140)
	nameLabel.Font = FONT
	nameLabel.TextSize = 17
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card
	local nStroke = Instance.new("UIStroke")
	nStroke.Color = Color3.fromRGB(0, 0, 0)
	nStroke.Thickness = 1.5
	nStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	nStroke.Parent = nameLabel

	-- Rarity
	local rarLabel = Instance.new("TextLabel")
	rarLabel.Size = UDim2.new(1, -10, 0, 18)
	rarLabel.Position = UDim2.new(0.5, 0, 0, vpSize + 38)
	rarLabel.AnchorPoint = Vector2.new(0.5, 0)
	rarLabel.BackgroundTransparency = 1
	rarLabel.Text = isUnlocked and info.rarity:upper() or "???"
	rarLabel.TextColor3 = isUnlocked and rarityColor or Color3.fromRGB(80, 65, 110)
	rarLabel.Font = FONT
	rarLabel.TextSize = 14
	rarLabel.Parent = card
	local rStroke = Instance.new("UIStroke")
	rStroke.Color = Color3.fromRGB(0, 0, 0)
	rStroke.Thickness = 1
	rStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	rStroke.Parent = rarLabel

	-- Bottom: claim / claimed / locked
	if isUnlocked and not isClaimed then
		local exclBadge = Instance.new("Frame")
		exclBadge.Name = "ExclBadge"
		exclBadge.Size = UDim2.new(0, 28, 0, 28)
		exclBadge.Position = UDim2.new(1, -4, 0, -4)
		exclBadge.AnchorPoint = Vector2.new(1, 0)
		exclBadge.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
		exclBadge.BorderSizePixel = 0
		exclBadge.ZIndex = 8
		exclBadge.Parent = card
		Instance.new("UICorner", exclBadge).CornerRadius = UDim.new(1, 0)
		local exclText = Instance.new("TextLabel")
		exclText.Size = UDim2.new(1, 0, 1, 0)
		exclText.BackgroundTransparency = 1
		exclText.Text = "!"
		exclText.TextColor3 = Color3.new(1, 1, 1)
		exclText.Font = FONT
		exclText.TextSize = 18
		exclText.ZIndex = 9
		exclText.Parent = exclBadge

		local claimBtn = Instance.new("TextButton")
		claimBtn.Name = "ClaimBtn"
		claimBtn.Size = UDim2.new(1, -16, 0, 34)
		claimBtn.Position = UDim2.new(0.5, 0, 1, -8)
		claimBtn.AnchorPoint = Vector2.new(0.5, 1)
		claimBtn.BackgroundColor3 = Color3.fromRGB(80, 210, 120)
		claimBtn.Text = "\u{1F48E} +" .. gemReward .. " Gems"
		claimBtn.TextColor3 = Color3.new(1, 1, 1)
		claimBtn.Font = FONT
		claimBtn.TextSize = 15
		claimBtn.BorderSizePixel = 0
		claimBtn.Parent = card
		local cbCorner = Instance.new("UICorner")
		cbCorner.CornerRadius = UDim.new(0, 12)
		cbCorner.Parent = claimBtn
		local cbStroke = Instance.new("UIStroke")
		cbStroke.Color = Color3.fromRGB(50, 160, 80)
		cbStroke.Thickness = 1.5
		cbStroke.Parent = claimBtn
		local cbGrad = Instance.new("UIGradient")
		cbGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 255, 220)),
		})
		cbGrad.Rotation = 90
		cbGrad.Parent = claimBtn

		claimBtn.MouseEnter:Connect(function()
			TweenService:Create(claimBtn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(100, 235, 145) }):Play()
		end)
		claimBtn.MouseLeave:Connect(function()
			TweenService:Create(claimBtn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(80, 210, 120) }):Play()
		end)
		claimBtn.MouseButton1Click:Connect(function()
			ClaimIndexGems:FireServer(info.id, effect)
		end)
	elseif isUnlocked and isClaimed then
		local cl = Instance.new("TextLabel")
		cl.Size = UDim2.new(1, -16, 0, 28)
		cl.Position = UDim2.new(0.5, 0, 1, -8)
		cl.AnchorPoint = Vector2.new(0.5, 1)
		cl.BackgroundTransparency = 1
		cl.Text = "\u{2705} Claimed"
		cl.TextColor3 = Color3.fromRGB(120, 230, 120)
		cl.Font = FONT
		cl.TextSize = 16
		cl.Parent = card
		local clStroke = Instance.new("UIStroke")
		clStroke.Color = Color3.fromRGB(0, 0, 0)
		clStroke.Thickness = 1
		clStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		clStroke.Parent = cl
	else
		local lk = Instance.new("TextLabel")
		lk.Size = UDim2.new(1, -16, 0, 28)
		lk.Position = UDim2.new(0.5, 0, 1, -8)
		lk.AnchorPoint = Vector2.new(0.5, 1)
		lk.BackgroundTransparency = 1
		lk.Text = "\u{1F512} Locked"
		lk.TextColor3 = Color3.fromRGB(110, 90, 155)
		lk.Font = FONT
		lk.TextSize = 16
		lk.Parent = card
		local lkStroke = Instance.new("UIStroke")
		lkStroke.Color = Color3.fromRGB(0, 0, 0)
		lkStroke.Thickness = 1
		lkStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		lkStroke.Parent = lk
	end

	return card
end

-------------------------------------------------
-- SIDEBAR
-------------------------------------------------

local function highlightTab(tabName)
	for _, btn in ipairs(sidebarBtns) do
		local isActive = btn.Name == "Tab_" .. tabName
		btn.BackgroundColor3 = isActive and Color3.fromRGB(80, 65, 130) or Color3.fromRGB(45, 36, 75)
		btn.BackgroundTransparency = isActive and 0 or 0.15
		local lbl = btn:FindFirstChild("TabLabel")
		if lbl then lbl.TextSize = isActive and 18 or 15 end
	end
end

local function updateSidebarBadges()
	for _, btn in ipairs(sidebarBtns) do
		local tabName = btn.Name:sub(5)
		local tabEffect = nil
		for _, tab in ipairs(TABS) do
			if tab.name == tabName then tabEffect = tab.effect; break end
		end
		local unclaimed = countUnclaimedForTab(tabEffect)
		local badge = btn:FindFirstChild("TabBadge")
		if unclaimed > 0 then
			if not badge then
				badge = Instance.new("Frame")
				badge.Name = "TabBadge"
				badge.Size = UDim2.new(0, 24, 0, 24)
				badge.Position = UDim2.new(1, -6, 0.5, 0)
				badge.AnchorPoint = Vector2.new(1, 0.5)
				badge.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
				badge.BorderSizePixel = 0
				badge.ZIndex = 6
				badge.Parent = btn
				Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
				local bl = Instance.new("TextLabel")
				bl.Name = "BadgeText"
				bl.Size = UDim2.new(1, 0, 1, 0)
				bl.BackgroundTransparency = 1
				bl.Text = "!"
				bl.TextColor3 = Color3.new(1, 1, 1)
				bl.Font = FONT
				bl.TextSize = 15
				bl.ZIndex = 7
				bl.Parent = badge
			end
			badge.Visible = true
		else
			if badge then badge.Visible = false end
		end
	end
end

-------------------------------------------------
-- BUILD GRID
-------------------------------------------------

local function buildGrid(force)
	if not contentGrid then return end

	local snap = buildSnapshot()
	if not force and snap == lastSnapshot then return end
	lastSnapshot = snap
	currentBuildToken = currentBuildToken + 1
	local buildToken = currentBuildToken

	stopRotations()
	for _, child in ipairs(contentGrid:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local tabEffect = activeTab
	local indexCol = HUDController.Data.indexCollection or {}
	local totalCount, unlockedCount = 0, 0

	for i, info in ipairs(Streamers.List) do
		totalCount = totalCount + 1
		local key = getIndexKey(info.id, tabEffect)
		if indexCol[key] then unlockedCount = unlockedCount + 1 end
	end

	if counterLabel then
		local tabName = tabEffect or "Default"
		counterLabel.Text = tabName .. " - " .. unlockedCount .. " / " .. totalCount .. " Discovered!"
	end

	updateSidebarBadges()
	updateNavBadge()
	updateClaimAllButton()

	task.spawn(function()
		for i, info in ipairs(Streamers.List) do
			if buildToken ~= currentBuildToken then
				return
			end
			buildStreamerCard(info, tabEffect, contentGrid, i)
			if i % 4 == 0 then
				task.wait()
			end
		end
	end)
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------

function IndexController.Open()
	if isOpen then IndexController.Close() return end
	isOpen = true
	activeTab = nil
	lastSnapshot = ""
	if modalFrame then
		modalFrame.Visible = true
		highlightTab("Default")
		buildGrid(true)
		UIHelper.ScaleIn(modalFrame, 0.25)
	end
end

function IndexController.Close()
	if not isOpen then return end
	isOpen = false
	lastSnapshot = ""
	currentBuildToken = currentBuildToken + 1
	stopRotations()
	if modalFrame then UIHelper.ScaleOut(modalFrame, 0.2) end
end

function IndexController.IsOpen()
	return isOpen
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function IndexController.Init()
	screenGui = UIHelper.CreateScreenGui("IndexGui", 12)
	screenGui.Parent = playerGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "IndexModal"
	modalFrame.Size = UDim2.new(0, 940, 0, 670)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = Color3.fromRGB(45, 35, 75)
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui
	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(0, 28)
	mCorner.Parent = modalFrame
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(180, 130, 255)
	mStroke.Thickness = 2.5
	mStroke.Transparency = 0.1
	UIHelper.MakeResponsiveModal(modalFrame, 940, 670)
	mStroke.Parent = modalFrame
	UIHelper.CreateShadow(modalFrame)

	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 190, 220)),
	})
	bgGrad.Rotation = 90
	bgGrad.Parent = modalFrame

	-- Header
	local headerFrame = Instance.new("Frame")
	headerFrame.Name = "HeaderFrame"
	headerFrame.Size = UDim2.new(1, 0, 0, 70)
	headerFrame.Position = UDim2.new(0, 0, 0, 0)
	headerFrame.BackgroundTransparency = 1
	headerFrame.ZIndex = 2
	headerFrame.Parent = modalFrame

	local bookIcon = Instance.new("ImageLabel")
	bookIcon.Name = "IndexBookIcon"
	bookIcon.Size = UDim2.new(0, 56, 0, 56)
	bookIcon.Position = UDim2.new(0, 20, 0, 6)
	bookIcon.AnchorPoint = Vector2.new(0, 0)
	bookIcon.BackgroundTransparency = 1
	bookIcon.ScaleType = Enum.ScaleType.Fit
	bookIcon.ZIndex = 2
	bookIcon.Parent = headerFrame
	if INDEX_BOOK_ASSET_ID and INDEX_BOOK_ASSET_ID ~= "" and INDEX_BOOK_ASSET_ID ~= "rbxassetid://0" then
		bookIcon.Image = INDEX_BOOK_ASSET_ID
		bookIcon.Visible = true
	else
		bookIcon.Visible = false
	end

	-- Title (always centered)
	local title = Instance.new("TextLabel")
	title.Name = "TitleLabel"
	title.Size = UDim2.new(1, -120, 0, 50)
	title.Position = UDim2.new(0.5, 0, 0, 6)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "\u{2B50} STREAMER INDEX \u{2B50}"
	title.TextColor3 = Color3.fromRGB(255, 220, 80)
	title.Font = FONT
	title.TextSize = 38
	title.ZIndex = 2
	title.Parent = headerFrame
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(120, 60, 0)
	tStroke.Thickness = 2
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tStroke.Parent = title

	-- Close
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 50, 0, 50)
	closeBtn.Position = UDim2.new(1, -14, 0, 16)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT
	closeBtn.TextSize = 26
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 10
	closeBtn.Parent = modalFrame
	local ccCorner = Instance.new("UICorner")
	ccCorner.CornerRadius = UDim.new(1, 0)
	ccCorner.Parent = closeBtn
	local ccStroke = Instance.new("UIStroke")
	ccStroke.Color = Color3.fromRGB(180, 50, 50)
	ccStroke.Thickness = 2
	ccStroke.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function() IndexController.Close() end)

	-- Counter
	counterLabel = Instance.new("TextLabel")
	counterLabel.Size = UDim2.new(1, -180, 0, 26)
	counterLabel.Position = UDim2.new(0.5, 0, 0, 62)
	counterLabel.AnchorPoint = Vector2.new(0.5, 0)
	counterLabel.BackgroundTransparency = 1
	counterLabel.Text = "Default: 0/0 discovered"
	counterLabel.TextColor3 = Color3.fromRGB(200, 180, 255)
	counterLabel.Font = FONT
	counterLabel.TextSize = 20
	counterLabel.Parent = modalFrame
	local cntStroke = Instance.new("UIStroke")
	cntStroke.Color = Color3.fromRGB(20, 15, 40)
	cntStroke.Thickness = 1
	cntStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	cntStroke.Parent = counterLabel

	claimAllBtn = Instance.new("TextButton")
	claimAllBtn.Name = "ClaimAllBtn"
	claimAllBtn.Size = UDim2.new(0, 170, 0, 30)
	claimAllBtn.Position = UDim2.new(0, 88, 0, 58)
	claimAllBtn.AnchorPoint = Vector2.new(0.5, 0)
	claimAllBtn.BackgroundColor3 = Color3.fromRGB(90, 170, 255)
	claimAllBtn.BorderSizePixel = 0
	claimAllBtn.TextColor3 = Color3.new(1, 1, 1)
	claimAllBtn.Font = FONT
	claimAllBtn.TextSize = 13
	claimAllBtn.Text = "Claim All"
	claimAllBtn.ZIndex = 3
	claimAllBtn.Parent = modalFrame
	local caCorner = Instance.new("UICorner")
	caCorner.CornerRadius = UDim.new(0, 10)
	caCorner.Parent = claimAllBtn
	local caStroke = Instance.new("UIStroke")
	caStroke.Color = Color3.fromRGB(65, 120, 200)
	caStroke.Thickness = 1.5
	caStroke.Parent = claimAllBtn

	claimAllBtn.MouseButton1Click:Connect(function()
		if isClaimAllRunning then return end

		local toClaim = getClaimableEntriesAllTabs()
		if #toClaim <= 0 then
			updateClaimAllButton()
			return
		end

		isClaimAllRunning = true
		needsGridRefreshAfterClaimAll = false
		updateClaimAllButton()

		task.spawn(function()
			for _, entry in ipairs(toClaim) do
				ClaimIndexGems:FireServer(entry.id, entry.effect)
				task.wait(0.06)
			end

			task.wait(0.15)
			isClaimAllRunning = false
			if isOpen and needsGridRefreshAfterClaimAll then
				lastSnapshot = ""
				buildGrid(true)
			end
			needsGridRefreshAfterClaimAll = false
			updateClaimAllButton()
		end)
	end)

	-------------------------------------------------
	-- SIDEBAR
	-------------------------------------------------
	local sidebarWidth = 165
	local sidebar = Instance.new("ScrollingFrame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, sidebarWidth, 1, -95)
	sidebar.Position = UDim2.new(0, 6, 0, 92)
	sidebar.BackgroundColor3 = Color3.fromRGB(35, 28, 60)
	sidebar.BackgroundTransparency = 0.4
	sidebar.BorderSizePixel = 0
	sidebar.ScrollBarThickness = 4
	sidebar.ScrollBarImageColor3 = Color3.fromRGB(180, 130, 255)
	sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
	sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sidebar.Parent = modalFrame
	local sbCorner = Instance.new("UICorner")
	sbCorner.CornerRadius = UDim.new(0, 16)
	sbCorner.Parent = sidebar

	local sbLayout = Instance.new("UIListLayout")
	sbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sbLayout.Padding = UDim.new(0, 5)
	sbLayout.Parent = sidebar

	local sbPadding = Instance.new("UIPadding")
	sbPadding.PaddingTop = UDim.new(0, 6)
	sbPadding.PaddingLeft = UDim.new(0, 6)
	sbPadding.PaddingRight = UDim.new(0, 6)
	sbPadding.PaddingBottom = UDim.new(0, 6)
	sbPadding.Parent = sidebar

	for i, tab in ipairs(TABS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. tab.name
		btn.Size = UDim2.new(1, 0, 0, 46)
		btn.BackgroundColor3 = Color3.fromRGB(45, 36, 75)
		btn.BackgroundTransparency = 0.15
		btn.BorderSizePixel = 0
		btn.LayoutOrder = i
		btn.Text = ""
		btn.Parent = sidebar
		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 12)
		btnCorner.Parent = btn

		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, 6, 0.65, 0)
		strip.Position = UDim2.new(0, 4, 0.175, 0)
		strip.BackgroundColor3 = tab.color
		strip.BorderSizePixel = 0
		strip.Parent = btn
		local stCorner = Instance.new("UICorner")
		stCorner.CornerRadius = UDim.new(0, 3)
		stCorner.Parent = strip

		local lbl = Instance.new("TextLabel")
		lbl.Name = "TabLabel"
		lbl.Size = UDim2.new(1, -20, 1, 0)
		lbl.Position = UDim2.new(0, 16, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = tab.name
		lbl.TextColor3 = tab.color
		lbl.Font = FONT
		lbl.TextSize = 15
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Parent = btn
		local tabStroke = Instance.new("UIStroke")
		tabStroke.Color = Color3.fromRGB(0, 0, 0)
		tabStroke.Thickness = 1
		tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		tabStroke.Parent = lbl

		btn.MouseButton1Click:Connect(function()
			activeTab = tab.effect
			lastSnapshot = ""
			highlightTab(tab.name)
			buildGrid(true)
		end)

		table.insert(sidebarBtns, btn)
	end

	-------------------------------------------------
	-- CONTENT
	-------------------------------------------------
	contentGrid = Instance.new("ScrollingFrame")
	contentGrid.Name = "ContentGrid"
	contentGrid.Size = UDim2.new(1, -sidebarWidth - 18, 1, -95)
	contentGrid.Position = UDim2.new(0, sidebarWidth + 12, 0, 92)
	contentGrid.BackgroundTransparency = 1
	contentGrid.BorderSizePixel = 0
	contentGrid.ScrollBarThickness = 6
	contentGrid.ScrollBarImageColor3 = Color3.fromRGB(180, 130, 255)
	contentGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	contentGrid.Parent = modalFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 180, 0, 240)
	gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = contentGrid

	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 6)
	gridPadding.PaddingLeft = UDim.new(0, 6)
	gridPadding.PaddingRight = UDim.new(0, 6)
	gridPadding.Parent = contentGrid

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	HUDController.OnDataUpdated(function()
		updateNavBadge()
		if isOpen then
			if isClaimAllRunning then
				needsGridRefreshAfterClaimAll = true
				updateSidebarBadges()
			elseif skipNextDataRebuild then
				skipNextDataRebuild = false
				updateSidebarBadges()
			else
				buildGrid(false)
				updateSidebarBadges()
			end
		end
		updateClaimAllButton()
	end)

	ClaimIndexResult.OnClientEvent:Connect(function(result)
		if result.success then
			updateNavBadge()
			if isOpen then
				if isClaimAllRunning then
					needsGridRefreshAfterClaimAll = true
				else
					local key = getIndexKey(result.streamerId, result.effect)
					local indexCol = HUDController.Data.indexCollection
					if indexCol then
						indexCol[key] = "claimed"
					end

					local appliedToVisibleCard = false
					for _, child in ipairs(contentGrid:GetChildren()) do
						if child:IsA("Frame") and child:GetAttribute("IndexKey") == key then
							setCardClaimedVisual(child)
							appliedToVisibleCard = true
							break
						end
					end

					if appliedToVisibleCard then
						skipNextDataRebuild = true
						updateSidebarBadges()
						updateClaimAllButton()
					else
						task.wait(0.1)
						lastSnapshot = ""
						buildGrid(true)
					end
				end
			end
		end
		updateClaimAllButton()
	end)

	-- Set initial badge count
	updateNavBadge()
	updateClaimAllButton()

	modalFrame.Visible = false
end

return IndexController
