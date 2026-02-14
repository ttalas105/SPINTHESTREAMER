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
local lastSnapshot = ""

-- Single shared Heartbeat for ALL viewport rotations (performance)
local viewportData = {} -- { {camera, target, dist, camY, angle} }
local heartbeatConn = nil

local FONT = Enum.Font.FredokaOne

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
	local gemReward = Economy.IndexGemRewards[info.rarity] or 2

	local card = Instance.new("Frame")
	card.Name = "IndexCard_" .. cardIndex
	card.Size = UDim2.new(0, 130, 0, 175)
	card.BackgroundColor3 = isUnlocked and Color3.fromRGB(22, 22, 38) or Color3.fromRGB(12, 12, 18)
	card.BorderSizePixel = 0
	card.LayoutOrder = cardIndex
	card.Parent = parent

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 12)
	cCorner.Parent = card

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = isUnlocked and displayColor or Color3.fromRGB(40, 40, 50)
	cStroke.Thickness = 2
	cStroke.Transparency = isUnlocked and 0.3 or 0.7
	cStroke.Parent = card

	-- Viewport
	local vpSize = 100
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ModelVP"
	viewport.Size = UDim2.new(1, -16, 0, vpSize)
	viewport.Position = UDim2.new(0.5, 0, 0, 8)
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.BackgroundColor3 = isUnlocked and Color3.fromRGB(10, 10, 20) or Color3.fromRGB(5, 5, 10)
	viewport.BackgroundTransparency = 0.2
	viewport.BorderSizePixel = 0
	viewport.Parent = card
	local vpCorner = Instance.new("UICorner")
	vpCorner.CornerRadius = UDim.new(0, 8)
	vpCorner.Parent = viewport

	local modelsFolder = ReplicatedStorage:FindFirstChild("StreamerModels")
	local modelTemplate = modelsFolder and modelsFolder:FindFirstChild(info.id)

	if modelTemplate then
		local vpModel = modelTemplate:Clone()

		if not isUnlocked then
			-- Fully black silhouette: destroy EVERYTHING visual, make all parts pure black
			for _, desc in ipairs(vpModel:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Color = Color3.fromRGB(5, 5, 5)
					desc.Material = Enum.Material.SmoothPlastic
					desc.Transparency = 0
					desc.Reflectance = 0
				elseif desc:IsA("Decal") or desc:IsA("Texture") or desc:IsA("SurfaceAppearance") then
					desc:Destroy()
				elseif desc:IsA("Shirt") or desc:IsA("Pants") or desc:IsA("ShirtGraphic") or desc:IsA("CharacterMesh") then
					desc:Destroy()
				elseif desc:IsA("Accessory") or desc:IsA("Hat") then
					-- Remove accessories (hair, hats) to prevent color clipping
					desc:Destroy()
				elseif desc:IsA("SpecialMesh") then
					-- Keep mesh shape but remove texture
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

			-- Add to shared rotation data instead of individual connections
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
		ph.TextSize = isUnlocked and 36 or 30
		ph.TextColor3 = isUnlocked and Color3.new(1, 1, 1) or Color3.fromRGB(40, 40, 50)
		ph.Font = Enum.Font.SourceSans
		ph.Parent = viewport
	end

	-- Name
	local nameText = isUnlocked and info.displayName or "???"
	if isUnlocked and effectInfo then
		nameText = effectInfo.prefix .. " " .. nameText
	end
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -8, 0, 18)
	nameLabel.Position = UDim2.new(0.5, 0, 0, vpSize + 12)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = nameText
	nameLabel.TextColor3 = isUnlocked and displayColor or Color3.fromRGB(60, 60, 70)
	nameLabel.Font = FONT
	nameLabel.TextSize = 12
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card
	if isUnlocked then
		local nStroke = Instance.new("UIStroke")
		nStroke.Color = Color3.fromRGB(0, 0, 0)
		nStroke.Thickness = 1.2
		nStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		nStroke.Parent = nameLabel
	end

	-- Rarity
	local rarLabel = Instance.new("TextLabel")
	rarLabel.Size = UDim2.new(1, -8, 0, 14)
	rarLabel.Position = UDim2.new(0.5, 0, 0, vpSize + 30)
	rarLabel.AnchorPoint = Vector2.new(0.5, 0)
	rarLabel.BackgroundTransparency = 1
	rarLabel.Text = isUnlocked and info.rarity:upper() or "???"
	rarLabel.TextColor3 = isUnlocked and rarityColor or Color3.fromRGB(50, 50, 60)
	rarLabel.Font = FONT
	rarLabel.TextSize = 10
	rarLabel.Parent = card

	-- Bottom: claim / claimed / locked
	if isUnlocked and not isClaimed then
		local claimBtn = Instance.new("TextButton")
		claimBtn.Name = "ClaimBtn"
		claimBtn.Size = UDim2.new(1, -16, 0, 24)
		claimBtn.Position = UDim2.new(0.5, 0, 1, -6)
		claimBtn.AnchorPoint = Vector2.new(0.5, 1)
		claimBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
		claimBtn.Text = "\u{1F48E} +" .. gemReward .. " Gems"
		claimBtn.TextColor3 = Color3.new(1, 1, 1)
		claimBtn.Font = FONT
		claimBtn.TextSize = 11
		claimBtn.BorderSizePixel = 0
		claimBtn.Parent = card
		local cbCorner = Instance.new("UICorner")
		cbCorner.CornerRadius = UDim.new(0, 8)
		cbCorner.Parent = claimBtn

		claimBtn.MouseEnter:Connect(function()
			TweenService:Create(claimBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(110, 210, 255) }):Play()
		end)
		claimBtn.MouseLeave:Connect(function()
			TweenService:Create(claimBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(80, 180, 255) }):Play()
		end)
		claimBtn.MouseButton1Click:Connect(function()
			ClaimIndexGems:FireServer(info.id, effect)
		end)
	elseif isUnlocked and isClaimed then
		local cl = Instance.new("TextLabel")
		cl.Size = UDim2.new(1, -16, 0, 22)
		cl.Position = UDim2.new(0.5, 0, 1, -6)
		cl.AnchorPoint = Vector2.new(0.5, 1)
		cl.BackgroundTransparency = 1
		cl.Text = "\u{2705} Claimed"
		cl.TextColor3 = Color3.fromRGB(100, 200, 100)
		cl.Font = FONT
		cl.TextSize = 11
		cl.Parent = card
	else
		local lk = Instance.new("TextLabel")
		lk.Size = UDim2.new(1, -16, 0, 22)
		lk.Position = UDim2.new(0.5, 0, 1, -6)
		lk.AnchorPoint = Vector2.new(0.5, 1)
		lk.BackgroundTransparency = 1
		lk.Text = "\u{1F512} Locked"
		lk.TextColor3 = Color3.fromRGB(60, 60, 70)
		lk.Font = FONT
		lk.TextSize = 11
		lk.Parent = card
	end

	return card
end

-------------------------------------------------
-- BUILD GRID
-------------------------------------------------

local function buildGrid(force)
	if not contentGrid then return end

	local snap = buildSnapshot()
	if not force and snap == lastSnapshot then return end
	lastSnapshot = snap

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
		buildStreamerCard(info, tabEffect, contentGrid, i)
	end

	if counterLabel then
		local tabName = tabEffect or "Default"
		counterLabel.Text = tabName .. ": " .. unlockedCount .. "/" .. totalCount .. " discovered"
	end

	task.defer(function()
		local gl = contentGrid:FindFirstChildOfClass("UIGridLayout")
		if gl then
			contentGrid.CanvasSize = UDim2.new(0, 0, 0, gl.AbsoluteContentSize.Y + 16)
		end
	end)
end

-------------------------------------------------
-- SIDEBAR
-------------------------------------------------

local function highlightTab(tabName)
	for _, btn in ipairs(sidebarBtns) do
		local isActive = btn.Name == "Tab_" .. tabName
		btn.BackgroundColor3 = isActive and Color3.fromRGB(60, 60, 90) or Color3.fromRGB(25, 25, 40)
		local lbl = btn:FindFirstChild("TabLabel")
		if lbl then lbl.TextSize = isActive and 13 or 11 end
	end
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
	stopRotations()
	if modalFrame then modalFrame.Visible = false end
end

-------------------------------------------------
-- INIT
-------------------------------------------------

function IndexController.Init()
	screenGui = UIHelper.CreateScreenGui("IndexGui", 12)
	screenGui.Parent = playerGui

	modalFrame = Instance.new("Frame")
	modalFrame.Name = "IndexModal"
	modalFrame.Size = UDim2.new(0, 680, 0, 500)
	modalFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	modalFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	modalFrame.BackgroundColor3 = Color3.fromRGB(14, 12, 28)
	modalFrame.BorderSizePixel = 0
	modalFrame.Visible = false
	modalFrame.ClipsDescendants = true
	modalFrame.Parent = screenGui
	local mCorner = Instance.new("UICorner")
	mCorner.CornerRadius = UDim.new(0, 20)
	mCorner.Parent = modalFrame
	local mStroke = Instance.new("UIStroke")
	mStroke.Color = Color3.fromRGB(100, 180, 255)
	mStroke.Thickness = 3
	mStroke.Parent = modalFrame

	-- Rainbow top bar
	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 5)
	topBar.BackgroundColor3 = Color3.new(1, 1, 1)
	topBar.BorderSizePixel = 0
	topBar.ZIndex = 5
	topBar.Parent = modalFrame
	local tbGrad = Instance.new("UIGradient")
	tbGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 60)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 100)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 200, 255)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(160, 100, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 200)),
	})
	tbGrad.Parent = topBar

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -100, 0, 40)
	title.Position = UDim2.new(0.5, 0, 0, 8)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = "\u{1F4D6} STREAMER INDEX \u{1F4D6}"
	title.TextColor3 = Color3.fromRGB(100, 200, 255)
	title.Font = FONT
	title.TextSize = 26
	title.Parent = modalFrame
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = Color3.fromRGB(0, 0, 80)
	tStroke.Thickness = 2.5
	tStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	tStroke.Parent = title

	-- Close
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -12, 0, 10)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
	closeBtn.Text = "\u{2715}"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = FONT
	closeBtn.TextSize = 20
	closeBtn.BorderSizePixel = 0
	closeBtn.ZIndex = 10
	closeBtn.Parent = modalFrame
	local ccCorner = Instance.new("UICorner")
	ccCorner.CornerRadius = UDim.new(1, 0)
	ccCorner.Parent = closeBtn
	closeBtn.MouseButton1Click:Connect(function() IndexController.Close() end)

	-- Counter
	counterLabel = Instance.new("TextLabel")
	counterLabel.Size = UDim2.new(1, -140, 0, 18)
	counterLabel.Position = UDim2.new(0.5, 40, 0, 46)
	counterLabel.AnchorPoint = Vector2.new(0.5, 0)
	counterLabel.BackgroundTransparency = 1
	counterLabel.Text = "Default: 0/0 discovered"
	counterLabel.TextColor3 = Color3.fromRGB(160, 180, 220)
	counterLabel.Font = FONT
	counterLabel.TextSize = 13
	counterLabel.Parent = modalFrame

	-------------------------------------------------
	-- SIDEBAR
	-------------------------------------------------
	local sidebarWidth = 110
	local sidebar = Instance.new("ScrollingFrame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, sidebarWidth, 1, -68)
	sidebar.Position = UDim2.new(0, 0, 0, 68)
	sidebar.BackgroundColor3 = Color3.fromRGB(18, 16, 32)
	sidebar.BackgroundTransparency = 0.3
	sidebar.BorderSizePixel = 0
	sidebar.ScrollBarThickness = 3
	sidebar.ScrollBarImageColor3 = Color3.fromRGB(100, 150, 255)
	sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
	sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sidebar.Parent = modalFrame

	local sbLayout = Instance.new("UIListLayout")
	sbLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sbLayout.Padding = UDim.new(0, 3)
	sbLayout.Parent = sidebar

	local sbPadding = Instance.new("UIPadding")
	sbPadding.PaddingTop = UDim.new(0, 4)
	sbPadding.PaddingLeft = UDim.new(0, 4)
	sbPadding.PaddingRight = UDim.new(0, 4)
	sbPadding.Parent = sidebar

	for i, tab in ipairs(TABS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. tab.name
		btn.Size = UDim2.new(1, 0, 0, 32)
		btn.BackgroundColor3 = Color3.fromRGB(25, 25, 40)
		btn.BorderSizePixel = 0
		btn.LayoutOrder = i
		btn.Text = "" -- remove default "Button" text
		btn.Parent = sidebar
		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 8)
		btnCorner.Parent = btn

		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, 4, 0.7, 0)
		strip.Position = UDim2.new(0, 3, 0.15, 0)
		strip.BackgroundColor3 = tab.color
		strip.BorderSizePixel = 0
		strip.Parent = btn
		local stCorner = Instance.new("UICorner")
		stCorner.CornerRadius = UDim.new(0, 2)
		stCorner.Parent = strip

		local lbl = Instance.new("TextLabel")
		lbl.Name = "TabLabel"
		lbl.Size = UDim2.new(1, -14, 1, 0)
		lbl.Position = UDim2.new(0, 12, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = tab.name
		lbl.TextColor3 = tab.color
		lbl.Font = FONT
		lbl.TextSize = 11
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextTruncate = Enum.TextTruncate.AtEnd
		lbl.Parent = btn

		btn.MouseButton1Click:Connect(function()
			activeTab = tab.effect
			lastSnapshot = "" -- force rebuild
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
	contentGrid.Size = UDim2.new(1, -sidebarWidth - 10, 1, -68)
	contentGrid.Position = UDim2.new(0, sidebarWidth + 6, 0, 68)
	contentGrid.BackgroundTransparency = 1
	contentGrid.BorderSizePixel = 0
	contentGrid.ScrollBarThickness = 5
	contentGrid.ScrollBarImageColor3 = Color3.fromRGB(100, 180, 255)
	contentGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentGrid.Parent = modalFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 130, 0, 175)
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gridLayout.Parent = contentGrid

	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 4)
	gridPadding.PaddingLeft = UDim.new(0, 4)
	gridPadding.Parent = contentGrid

	-------------------------------------------------
	-- EVENTS
	-------------------------------------------------

	HUDController.OnDataUpdated(function()
		if isOpen then buildGrid(false) end
	end)

	ClaimIndexResult.OnClientEvent:Connect(function(result)
		if result.success and isOpen then
			task.wait(0.1)
			lastSnapshot = ""
			buildGrid(true)
		end
	end)

	modalFrame.Visible = false
end

return IndexController
