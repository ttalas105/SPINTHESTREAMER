--[[
	Client Entry Point — Spin the Streamer
	Initializes all controllers, wires up navigation, data updates,
	inventory management, equip/unequip, sell, and remote events.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

-------------------------------------------------
-- LOADING SCREEN (shown immediately)
-------------------------------------------------

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local loadGui = Instance.new("ScreenGui")
loadGui.Name = "LoadingScreen"
loadGui.ResetOnSpawn = false
loadGui.DisplayOrder = 999
loadGui.IgnoreGuiInset = true
loadGui.Parent = playerGui

local bg = Instance.new("Frame")
bg.Name = "BG"
bg.Size = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3 = Color3.fromRGB(12, 10, 22)
bg.BorderSizePixel = 0
bg.ZIndex = 1
bg.Parent = loadGui

local bgGrad = Instance.new("UIGradient")
bgGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 14, 36)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(12, 10, 22)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 16, 40)),
})
bgGrad.Rotation = 135
bgGrad.Parent = bg

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(0, 600, 0, 80)
titleLabel.Position = UDim2.new(0.5, 0, 0.35, 0)
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "SPIN THE STREAMER"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.TextSize = 52
titleLabel.TextScaled = true
titleLabel.ZIndex = 5
titleLabel.Parent = bg
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(80, 40, 200)
titleStroke.Thickness = 3
titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
titleStroke.Parent = titleLabel

local titleGrad = Instance.new("UIGradient")
titleGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 200, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 140, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 180)),
})
titleGrad.Parent = titleLabel

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.Size = UDim2.new(0, 400, 0, 28)
subtitleLabel.Position = UDim2.new(0.5, 0, 0.43, 0)
subtitleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Loading assets..."
subtitleLabel.TextColor3 = Color3.fromRGB(180, 175, 200)
subtitleLabel.Font = Enum.Font.GothamBold
subtitleLabel.TextSize = 18
subtitleLabel.ZIndex = 5
subtitleLabel.Parent = bg

local barBg = Instance.new("Frame")
barBg.Name = "BarBG"
barBg.Size = UDim2.new(0, 400, 0, 12)
barBg.Position = UDim2.new(0.5, 0, 0.50, 0)
barBg.AnchorPoint = Vector2.new(0.5, 0.5)
barBg.BackgroundColor3 = Color3.fromRGB(40, 35, 60)
barBg.BorderSizePixel = 0
barBg.ZIndex = 5
barBg.Parent = bg
Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)
local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(70, 60, 110)
barStroke.Thickness = 1.5
barStroke.Parent = barBg

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(120, 80, 255)
barFill.BorderSizePixel = 0
barFill.ZIndex = 6
barFill.Parent = barBg
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)
local fillGrad = Instance.new("UIGradient")
fillGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 180, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 80, 255)),
})
fillGrad.Parent = barFill

local percentLabel = Instance.new("TextLabel")
percentLabel.Name = "Percent"
percentLabel.Size = UDim2.new(0, 100, 0, 20)
percentLabel.Position = UDim2.new(0.5, 0, 0.55, 0)
percentLabel.AnchorPoint = Vector2.new(0.5, 0.5)
percentLabel.BackgroundTransparency = 1
percentLabel.Text = "0%"
percentLabel.TextColor3 = Color3.fromRGB(160, 150, 190)
percentLabel.Font = Enum.Font.GothamBold
percentLabel.TextSize = 14
percentLabel.ZIndex = 5
percentLabel.Parent = bg

local tipLabel = Instance.new("TextLabel")
tipLabel.Name = "Tip"
tipLabel.Size = UDim2.new(0, 500, 0, 24)
tipLabel.Position = UDim2.new(0.5, 0, 0.92, 0)
tipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
tipLabel.BackgroundTransparency = 1
tipLabel.TextColor3 = Color3.fromRGB(120, 115, 145)
tipLabel.Font = Enum.Font.GothamBold
tipLabel.TextSize = 14
tipLabel.ZIndex = 5
tipLabel.Parent = bg

local TIPS = {
	"Place streamers on your base to earn cash!",
	"Rarer streamers earn way more cash per second.",
	"Use potions to multiply your luck and earnings!",
	"Sacrifice duplicate streamers for gems.",
	"Check the Index to see which streamers you're missing.",
	"VIP Pass gives you 1.5x cash forever!",
	"Rebirth to unlock stronger potions and bonuses.",
	"Divine Potions multiply EVERYTHING by 5x!",
}
tipLabel.Text = TIPS[math.random(#TIPS)]

local spinnerDots = {}
for i = 1, 3 do
	local dot = Instance.new("Frame")
	dot.Name = "Dot" .. i
	dot.Size = UDim2.new(0, 8, 0, 8)
	dot.Position = UDim2.new(0.5, (i - 2) * 18, 0.60, 0)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Color3.fromRGB(120, 80, 255)
	dot.BackgroundTransparency = 0.6
	dot.BorderSizePixel = 0
	dot.ZIndex = 5
	dot.Parent = bg
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	spinnerDots[i] = dot
end

task.spawn(function()
	local idx = 0
	while loadGui and loadGui.Parent do
		idx = (idx % 3) + 1
		for i, dot in ipairs(spinnerDots) do
			local target = (i == idx) and 0 or 0.6
			TweenService:Create(dot, TweenInfo.new(0.25), { BackgroundTransparency = target }):Play()
		end
		task.wait(0.35)
	end
end)

local function setLoadProgress(fraction, statusText)
	fraction = math.clamp(fraction, 0, 1)
	TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(fraction, 0, 1, 0),
	}):Play()
	percentLabel.Text = math.floor(fraction * 100) .. "%"
	if statusText then
		subtitleLabel.Text = statusText
	end
end

local function dismissLoadingScreen()
	setLoadProgress(1, "Ready!")
	task.wait(0.4)

	local fadeInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bg, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(titleLabel, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(titleStroke, fadeInfo, { Transparency = 1 }):Play()
	TweenService:Create(subtitleLabel, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(percentLabel, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(tipLabel, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(barBg, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(barStroke, fadeInfo, { Transparency = 1 }):Play()
	TweenService:Create(barFill, fadeInfo, { BackgroundTransparency = 1 }):Play()
	for _, dot in ipairs(spinnerDots) do
		TweenService:Create(dot, fadeInfo, { BackgroundTransparency = 1 }):Play()
	end

	task.wait(0.65)
	loadGui:Destroy()
end

-- Wait for shared modules
ReplicatedStorage:WaitForChild("Shared")

setLoadProgress(0.05, "Loading modules...")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local controllers = script.Parent.controllers

-- Controllers
local TopNavController       = require(controllers.TopNavController)
local LeftSideNavController  = require(controllers.LeftSideNavController)
local RightSideNavController = require(controllers.RightSideNavController)
local HUDController          = require(controllers.HUDController)
local StoreController        = require(controllers.StoreController)
local SpinController         = require(controllers.SpinController)
local SpinStandController    = require(controllers.SpinStandController)
local UpgradeStandController = require(controllers.UpgradeStandController)
local SellStandController    = require(controllers.SellStandController)
local PotionController       = require(controllers.PotionController)
local RebirthController      = require(controllers.RebirthController)
local HoldController         = require(controllers.HoldController)
local SlotPadController      = require(controllers.SlotPadController)
local InventoryController    = require(controllers.InventoryController)
local IndexController        = require(controllers.IndexController)
local GemShopController      = require(controllers.GemShopController)
local SacrificeController    = require(controllers.SacrificeController)
local StorageController      = require(controllers.StorageController)
local MusicController        = require(controllers.MusicController)
local SettingsController     = require(controllers.SettingsController)
local TutorialController     = require(controllers.TutorialController)
local QuestController        = require(controllers.QuestController)
local UIHelper               = require(controllers.UIHelper)

setLoadProgress(0.15, "Connecting to server...")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local CaseStockUpdate = RemoteEvents:WaitForChild("CaseStockUpdate")
local GetCaseStock = RemoteEvents:WaitForChild("GetCaseStock")
local PotionStockUpdate = RemoteEvents:WaitForChild("PotionStockUpdate")
local GetPotionStock = RemoteEvents:WaitForChild("GetPotionStock")
local RESTOCK_SOUND_ID = "rbxassetid://137402801272072"
local centerToastGui = nil
local centerToastLabel = nil
local centerToastStroke = nil
local centerToastToken = 0
local hasSeenCaseStockSnapshot = false
local lastCaseRestockIn = nil
local cachedRestockSound = nil

local function playRestockSound()
	if not cachedRestockSound or not cachedRestockSound.Parent then
		cachedRestockSound = Instance.new("Sound")
		cachedRestockSound.Name = "CaseRestockSFX"
		cachedRestockSound.SoundId = RESTOCK_SOUND_ID
		cachedRestockSound.Volume = 0.9
		cachedRestockSound.Parent = SoundService
	end

	local clone = cachedRestockSound:Clone()
	clone.Parent = SoundService
	SoundService:PlayLocalSound(clone)
	clone.Ended:Connect(function()
		if clone and clone.Parent then clone:Destroy() end
	end)
	task.delay(4, function()
		if clone and clone.Parent then clone:Destroy() end
	end)
end

local function showSystemToast(titleText, bodyText)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = titleText or "Spin the Streamer",
			Text = bodyText or "",
			Duration = 3,
		})
	end)
end

local function showCenterToast(messageText, options)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	if not centerToastGui or not centerToastGui.Parent then
		centerToastGui = Instance.new("ScreenGui")
		centerToastGui.Name = "CenterToastGui"
		centerToastGui.ResetOnSpawn = false
		centerToastGui.DisplayOrder = 60
		centerToastGui.IgnoreGuiInset = true
		centerToastGui.Parent = playerGui
	end
	if not centerToastLabel or not centerToastLabel.Parent then
		centerToastLabel = Instance.new("TextLabel")
		centerToastLabel.Name = "CenterToastLabel"
		centerToastLabel.Size = UDim2.new(0, 560, 0, 82)
		-- Default placement near top nav.
		centerToastLabel.Position = UDim2.new(0.5, 0, 0, 24)
		centerToastLabel.AnchorPoint = Vector2.new(0.5, 0)
		centerToastLabel.BackgroundColor3 = Color3.fromRGB(6, 22, 56)
		centerToastLabel.BackgroundTransparency = 0.12
		centerToastLabel.BorderSizePixel = 0
		centerToastLabel.TextColor3 = Color3.fromRGB(235, 250, 255)
		centerToastLabel.Font = Enum.Font.FredokaOne
		centerToastLabel.TextSize = 40
		centerToastLabel.TextWrapped = true
		centerToastLabel.TextStrokeColor3 = Color3.fromRGB(0, 145, 255)
		centerToastLabel.TextStrokeTransparency = 0.35
		centerToastLabel.Visible = false
		centerToastLabel.Parent = centerToastGui
		Instance.new("UICorner", centerToastLabel).CornerRadius = UDim.new(0, 12)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(35, 180, 255)
		stroke.Thickness = 2
		stroke.Transparency = 0.05
		stroke.Parent = centerToastLabel
		centerToastStroke = stroke
	end

	centerToastToken += 1
	local token = centerToastToken
	local isCentered = type(options) == "table" and options.centered == true
	if isCentered then
		centerToastLabel.Position = UDim2.new(0.5, 0, 0, 24)
		centerToastLabel.AnchorPoint = Vector2.new(0.5, 0)
	else
		-- Place near the top nav, left of the SHOP area.
		centerToastLabel.Position = UDim2.new(0.5, -380, 0, 24)
		centerToastLabel.AnchorPoint = Vector2.new(0, 0)
	end
	centerToastLabel.Text = messageText or ""
	centerToastLabel.BackgroundTransparency = 0.12
	centerToastLabel.TextTransparency = 0
	if centerToastStroke then
		centerToastStroke.Transparency = 0
	end
	centerToastLabel.Visible = true

	task.delay(3.6, function()
		if token ~= centerToastToken or not centerToastLabel then return end
		TweenService:Create(centerToastLabel, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		}):Play()
		if centerToastStroke then
			TweenService:Create(centerToastStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
		end
		task.delay(0.5, function()
			if token ~= centerToastToken or not centerToastLabel then return end
			centerToastLabel.Visible = false
		end)
	end)
end

local function shouldShowBaseSlotErrorToast(reasonText)
	if type(reasonText) ~= "string" then return false end
	local r = string.lower(reasonText)
	if string.find(r, "select a streamer first", 1, true) then return false end
	if string.find(r, "too fast", 1, true) then return false end
	return true
end

local function handleCaseStockPayload(payload)
	if type(payload) ~= "table" then return end
	local restockIn = payload.restockIn
	if type(restockIn) ~= "number" then return end

	if payload.restocked == true then
		playRestockSound()
		showCenterToast("Cases have been restocked")
	end

	local previousRestockIn = lastCaseRestockIn
	lastCaseRestockIn = restockIn

	hasSeenCaseStockSnapshot = true
end

local function handlePotionStockPayload(payload)
	if type(payload) ~= "table" then return end
	local restockIn = payload.restockIn
	if type(restockIn) ~= "number" then return end
	if payload.restocked == true then
		playRestockSound()
		showCenterToast("Potion stock has been restocked!")
	end
end

-------------------------------------------------
-- PRELOAD ASSETS
-------------------------------------------------

setLoadProgress(0.20, "Loading assets...")

do
	local assetsToPreload = {}

	local streamerModels = ReplicatedStorage:FindFirstChild("StreamerModels")
	if streamerModels then
		for _, model in ipairs(streamerModels:GetChildren()) do
			table.insert(assetsToPreload, model)
		end
	end

	local Potions = require(ReplicatedStorage.Shared.Config.Potions)
	if Potions.Types then
		for _, list in pairs(Potions.Types) do
			for _, p in ipairs(list) do
				if p.imageId and p.imageId ~= "" then
					local img = Instance.new("ImageLabel")
					img.Image = p.imageId
					table.insert(assetsToPreload, img)
				end
			end
		end
	end

	local soundIds = {
		"rbxassetid://7212399604",
		"rbxassetid://421058925",
		"rbxassetid://140728595235867",
		"rbxassetid://137402801272072",
		"rbxassetid://2650039396",
	}
	for _, sid in ipairs(soundIds) do
		local s = Instance.new("Sound")
		s.SoundId = sid
		table.insert(assetsToPreload, s)
	end

	local totalAssets = math.max(#assetsToPreload, 1)
	local loaded = 0

	if totalAssets > 0 then
		ContentProvider:PreloadAsync(assetsToPreload, function()
			loaded += 1
			local frac = 0.20 + (loaded / totalAssets) * 0.50
			setLoadProgress(frac, "Loading assets...")
		end)
	end

	for _, obj in ipairs(assetsToPreload) do
		if obj:IsA("ImageLabel") or obj:IsA("Sound") then
			if not obj.Parent then
				obj:Destroy()
			end
		end
	end
end

setLoadProgress(0.75, "Building UI...")

-------------------------------------------------
-- INITIALIZE ALL CONTROLLERS
-------------------------------------------------

HUDController.Init()
TopNavController.Init()
LeftSideNavController.Init()
RightSideNavController.Init()
setLoadProgress(0.80, "Building UI...")
StoreController.Init()
SpinController.Init()
SpinStandController.Init()
UpgradeStandController.Init()
SellStandController.Init()
PotionController.Init()
setLoadProgress(0.85, "Building UI...")
RebirthController.Init()
HoldController.Init()
InventoryController.Init()
IndexController.Init()
GemShopController.Init()
SacrificeController.Init()
setLoadProgress(0.90, "Almost there...")
StorageController.Init()
MusicController.Init()
SettingsController.Init()
TutorialController.Init()
QuestController.Init()
SlotPadController.Init(HoldController, InventoryController)
setLoadProgress(0.95, "Finishing up...")

-------------------------------------------------
-- DEBUG: Give all streamers + Skip tutorial (Studio only)
-- Buttons in bottom-right corner to avoid overlapping other UI
-------------------------------------------------
if RunService:IsStudio() then
	task.defer(function()
		local debugGiveAll = RemoteEvents:FindFirstChild("DebugGiveAll")
		local debugSkipTutorial = RemoteEvents:FindFirstChild("DebugSkipTutorial")
		local debugMaxRebirth = RemoteEvents:FindFirstChild("DebugMaxRebirth")
		if not debugGiveAll then debugGiveAll = RemoteEvents:WaitForChild("DebugGiveAll", 5) end
		if not debugSkipTutorial then debugSkipTutorial = RemoteEvents:WaitForChild("DebugSkipTutorial", 5) end
		if not debugMaxRebirth then debugMaxRebirth = RemoteEvents:WaitForChild("DebugMaxRebirth", 5) end
		if debugGiveAll and debugSkipTutorial and debugMaxRebirth then
			local sg = Instance.new("ScreenGui")
			sg.Name = "DebugGui"
			sg.ResetOnSpawn = false
			sg.DisplayOrder = 100
			sg.Parent = playerGui

			local container = Instance.new("Frame")
			container.Name = "DebugPanel"
			container.Size = UDim2.new(0, 170, 0, 122)
			container.Position = UDim2.new(1, -180, 1, -132)
			container.AnchorPoint = Vector2.new(1, 1)
			container.BackgroundColor3 = Color3.fromRGB(30, 25, 45)
			container.BackgroundTransparency = 0.3
			container.BorderSizePixel = 0
			container.Parent = sg
			Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

			local list = Instance.new("UIListLayout")
			list.Padding = UDim.new(0, 6)
			list.VerticalAlignment = Enum.VerticalAlignment.Center
			list.HorizontalAlignment = Enum.HorizontalAlignment.Center
			list.Parent = container

			local function makeBtn(text)
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(0, 160, 0, 34)
				btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
				btn.Text = text
				btn.TextColor3 = Color3.new(1, 1, 1)
				btn.Font = Enum.Font.FredokaOne
				btn.TextSize = 14
				btn.BorderSizePixel = 0
				Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
				btn.Parent = container
				return btn
			end

			local giveAllBtn = makeBtn("DEBUG: Give All")
			giveAllBtn.MouseButton1Click:Connect(function()
				giveAllBtn.Text = "Giving..."
				debugGiveAll:FireServer()
				task.delay(1.5, function()
					if giveAllBtn and giveAllBtn.Parent then
						giveAllBtn.Text = "DEBUG: Give All"
					end
				end)
			end)

			local skipBtn = makeBtn("DEBUG: Skip Tutorial")
			skipBtn.MouseButton1Click:Connect(function()
				TutorialController.ForceComplete()
				debugSkipTutorial:FireServer()
				skipBtn.Text = "Done!"
				task.delay(1, function()
					if skipBtn and skipBtn.Parent then skipBtn.Text = "DEBUG: Skip Tutorial" end
				end)
			end)

			local maxRebirthBtn = makeBtn("DEBUG: Max Rebirth")
			maxRebirthBtn.MouseButton1Click:Connect(function()
				maxRebirthBtn.Text = "Applying..."
				debugMaxRebirth:FireServer()
				task.delay(1, function()
					if maxRebirthBtn and maxRebirthBtn.Parent then
						maxRebirthBtn.Text = "DEBUG: Max Rebirth"
					end
				end)
			end)
		end
	end)
end

-------------------------------------------------
-- HIDE PLAYER HEALTH BARS + MOVEMENT SPEED
-------------------------------------------------

local DEFAULT_WALKSPEED = 16
local WALKSPEED_MULTIPLIER = 1.30  -- 30% faster
local MIN_CAMERA_ZOOM_DISTANCE = 8

local function setupCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.WalkSpeed = math.floor(DEFAULT_WALKSPEED * WALKSPEED_MULTIPLIER + 0.5)  -- 20
	end
end

local function enforceThirdPersonZoom(player)
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = MIN_CAMERA_ZOOM_DISTANCE
	if player.CameraMaxZoomDistance < MIN_CAMERA_ZOOM_DISTANCE then
		player.CameraMaxZoomDistance = MIN_CAMERA_ZOOM_DISTANCE
	end
end

local localPlayer = Players.LocalPlayer
enforceThirdPersonZoom(localPlayer)
if localPlayer.Character then
	setupCharacter(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(function(char)
	enforceThirdPersonZoom(localPlayer)
	setupCharacter(char)
end)

-------------------------------------------------
-- TELEPORT + BASE TRACKING
-------------------------------------------------

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local myBasePosition = nil

local BaseReady = RemoteEvents:WaitForChild("BaseReady")
BaseReady.OnClientEvent:Connect(function(data)
	if data.position then
		myBasePosition = data.position
		SlotPadController.SetBasePosition(data.position)
		TutorialController.OnBaseReady(data)
		print("[Client] Base assigned at position: " .. tostring(data.position))
	end
end)

-------------------------------------------------
-- CLOSE ALL MODALS (prevents stacking)
-------------------------------------------------

local function closeAllModals(except)
	if except ~= "Index"       and IndexController.IsOpen()          then IndexController.Close() end
	if except ~= "Storage"     and StorageController.IsOpen()        then StorageController.Close() end
	if except ~= "Store"       and StoreController.IsOpen()          then StoreController.Close() end
	if except ~= "SpinStand"   and SpinStandController.IsOpen()      then SpinStandController.Close() end
	if except ~= "Sell"        and SellStandController.IsOpen()      then SellStandController.Close() end
	if except ~= "Upgrade"     and UpgradeStandController.IsOpen()   then UpgradeStandController.Close() end
	if except ~= "Rebirth"     and RebirthController.IsOpen()        then RebirthController.Close() end
	if except ~= "Settings"    and SettingsController.IsOpen()       then SettingsController.Close() end
	if except ~= "Quests"      and QuestController.IsOpen()          then QuestController.Close() end
	if except ~= "Potion"      and PotionController.IsShopOpen()     then PotionController.CloseShop() end
	if except ~= "GemShop"     and GemShopController.IsOpen()        then GemShopController.Close() end
	if except ~= "Sacrifice"   and SacrificeController.IsOpen()      then SacrificeController.Close() end
	if except ~= "EnhancedCase" and not SpinController.IsActive() then
		SpinController.Hide()
	end
end

local function isTutorialInputBlocked()
	if not TutorialController.IsActive() then
		return false
	end
	TutorialController.OnBlockedMainInput()
	return true
end

-------------------------------------------------
-- WIRE TOP NAV TABS (BASE / SHOP) — TELEPORT
-------------------------------------------------

TopNavController.OnTabChanged(function(tabName)
	closeAllModals()

	if TutorialController.IsActive() then
		TutorialController.OnTabChanged(tabName)
	end

	local character = Players.LocalPlayer.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	if tabName == "BASE" then
		if myBasePosition then
			rootPart.CFrame = CFrame.new(myBasePosition + Vector3.new(0, 5, 0))
		end
	elseif tabName == "SHOP" then
		-- Shop area = gamepasses (Store button opens the Store modal)
		local shopPos = DesignConfig.HubCenter + Vector3.new(0, 5, 15)
		rootPart.CFrame = CFrame.new(shopPos)
	end
end)

-------------------------------------------------
-- WIRE LEFT SIDE NAV (Index, Pets, Store)
-------------------------------------------------

LeftSideNavController.OnClick("Index", function()
	if isTutorialInputBlocked() then return end
	if IndexController.IsOpen() then
		IndexController.Close()
	else
		closeAllModals("Index")
		IndexController.Open()
	end
end)

LeftSideNavController.OnClick("Storage", function()
	if isTutorialInputBlocked() then return end
	if StorageController.IsOpen() then
		StorageController.Close()
	else
		closeAllModals("Storage")
		StorageController.Open()
	end
end)

LeftSideNavController.OnClick("Store", function()
	if isTutorialInputBlocked() then return end
	if StoreController.IsOpen() then
		StoreController.Close()
	else
		closeAllModals("Store")
		StoreController.Open()
	end
end)

-------------------------------------------------
-- WIRE RIGHT SIDE NAV (Rebirth, Settings)
-------------------------------------------------

RightSideNavController.OnClick("Rebirth", function()
	if isTutorialInputBlocked() then return end
	if RebirthController.IsOpen() then
		RebirthController.Close()
	else
		closeAllModals("Rebirth")
		RebirthController.Open()
	end
end)

RightSideNavController.OnClick("Settings", function()
	if isTutorialInputBlocked() then return end
	if SettingsController.IsOpen() then
		SettingsController.Close()
	else
		closeAllModals("Settings")
		SettingsController.Open()
	end
end)

RightSideNavController.OnClick("Quests", function()
	if isTutorialInputBlocked() then return end
	if QuestController.IsOpen() then
		QuestController.Close()
	else
		closeAllModals("Quests")
		QuestController.Open()
	end
end)

-------------------------------------------------
-- DATA UPDATES -> INVENTORY + PADS
-------------------------------------------------

local tutorialStarted = false
local pendingInventoryData = nil

HUDController.OnDataUpdated(function(data)
	if SpinController.IsAnimating() then
		pendingInventoryData = data
	else
		InventoryController.UpdateInventory(data.inventory, data.storage)
		StorageController.Refresh()
	end
	SlotPadController.Refresh(data)

	if not tutorialStarted and data.tutorialComplete ~= nil then
		tutorialStarted = true
		if TutorialController.ShouldStart(data) then
			task.delay(1.5, function()
				TutorialController.Start()
			end)
		end
	end
end)

-- Safety fallback: if the initial data arrived before the callback was registered,
-- check now so the tutorial still triggers for new players.
task.defer(function()
	local data = HUDController.Data
	if not tutorialStarted and data.tutorialComplete ~= nil then
		tutorialStarted = true
		if TutorialController.ShouldStart(data) then
			task.delay(1.5, function()
				TutorialController.Start()
			end)
		end
	end
end)

-- When sacrifice queues change, refresh inventory/storage/sell visuals
SacrificeController.OnQueueChanged(function()
	InventoryController.RefreshVisuals()
	StorageController.Refresh()
	SellStandController.RefreshList()
end)

-- Music: pause lobby / start sacrifice music on open, reverse on close
SacrificeController.OnOpen(function()
	MusicController.OnSacrificeOpen()
end)
SacrificeController.OnClose(function()
	MusicController.OnSacrificeClose()
end)

-------------------------------------------------
-- INVENTORY SELECTION -> HOLD MODEL
-------------------------------------------------

InventoryController.OnSelectionChanged(function(slotIndex, item)
	if slotIndex and item then
		-- Player selected an inventory item — hold it in hand
		HoldController.Hold(item)
	else
		-- Player deselected — drop the held model
		HoldController.Drop()
	end
end)

-------------------------------------------------
-- SPIN RESULT -> INVENTORY FLASH
-------------------------------------------------

SpinController.OnSpinResult(function(data)
	-- Flush deferred inventory update now that animation is done
	if pendingInventoryData then
		InventoryController.UpdateInventory(pendingInventoryData.inventory, pendingInventoryData.storage)
		StorageController.Refresh()
		pendingInventoryData = nil
	end
	if data.streamerId and data.destination ~= "storage" then
		InventoryController.FlashNewItem(data.streamerId, data.effect)
	end
	if TutorialController.IsActive() then
		TutorialController.OnSpinResult(data)
	end
end)

-- Base single-slot place/remove result handling
local EquipResult = RemoteEvents:WaitForChild("EquipResult")
EquipResult.OnClientEvent:Connect(function(data)
	if data and data.success then
		InventoryController.ClearSelection()
		HoldController.Drop()
	elseif data and data.reason then
		warn("[Client] Place failed: " .. tostring(data.reason))
		if shouldShowBaseSlotErrorToast(data.reason) then
			showSystemToast("Base Slot", tostring(data.reason))
		end
	end
	if TutorialController.IsActive() then
		TutorialController.OnEquipResult(data)
	end
end)

local UnequipResult = RemoteEvents:WaitForChild("UnequipResult")
UnequipResult.OnClientEvent:Connect(function(data)
	if data and data.success and data.streamerId then
		-- Remove action: return streamer to inventory only.
		-- Do not auto-select/swap hand item, so the currently held streamer
		-- stays ready to place on another slot.
	end
end)

-- Rebirth result is handled by RebirthController

-------------------------------------------------
-- SELL RESULT
-------------------------------------------------

local SellResult = RemoteEvents:WaitForChild("SellResult")
SellResult.OnClientEvent:Connect(function(data)
	if data.success then
		print("[Client] Sold! +$" .. data.cashEarned)
	else
		print("[Client] Sell failed: " .. (data.reason or "unknown"))
	end
end)

CaseStockUpdate.OnClientEvent:Connect(handleCaseStockPayload)
GetCaseStock.OnClientEvent:Connect(handleCaseStockPayload)
PotionStockUpdate.OnClientEvent:Connect(handlePotionStockPayload)
GetPotionStock.OnClientEvent:Connect(handlePotionStockPayload)
task.defer(function()
	GetCaseStock:FireServer()
	GetPotionStock:FireServer()
end)

-------------------------------------------------
-- ENHANCED CASE RESULT (uses same spin animation)
-------------------------------------------------

local EnhancedCaseResult = RemoteEvents:WaitForChild("EnhancedCaseResult")
EnhancedCaseResult.OnClientEvent:Connect(function(data)
	if data.success then
		StoreController.Close()
		closeAllModals("EnhancedCase")

		SpinController.SetOnHideCallback(function()
			StoreController.Open()
		end)

		SpinController._startSpin({
			success = true,
			streamerId = data.streamerId,
			displayName = data.displayName,
			rarity = data.rarity,
			effect = data.effect,
		})
	end
end)

-------------------------------------------------
-- CLOSE OTHER MODALS WHEN STANDS OPEN
-------------------------------------------------

RemoteEvents:WaitForChild("OpenSpinStandGui").OnClientEvent:Connect(function()
	if SpinController.IsActive() then return end
	closeAllModals("SpinStand")
end)
RemoteEvents:WaitForChild("OpenSellStandGui").OnClientEvent:Connect(function()
	if isTutorialInputBlocked() then return end
	closeAllModals("Sell")
end)
RemoteEvents:WaitForChild("OpenUpgradeStandGui").OnClientEvent:Connect(function()
	if isTutorialInputBlocked() then return end
	closeAllModals("Upgrade")
end)
RemoteEvents:WaitForChild("OpenPotionStandGui").OnClientEvent:Connect(function()
	if isTutorialInputBlocked() then return end
	closeAllModals("Potion")
end)

-------------------------------------------------
-- TUTORIAL HOOKS
-------------------------------------------------

local OpenSpinStandGuiTutorial = RemoteEvents:WaitForChild("OpenSpinStandGui")
OpenSpinStandGuiTutorial.OnClientEvent:Connect(function()
	if TutorialController.IsActive() then
		TutorialController.OnSpinStandOpened()
	end
end)

-------------------------------------------------
-- AUTO-CLOSE STALL UIs WHEN PLAYER WALKS AWAY
-------------------------------------------------

local STALL_CLOSE_DISTANCE = 40

local stallUIMap = {
	{ stallName = "Stall_Spin",      isOpen = function() return SpinStandController.IsOpen() end, close = function() SpinStandController.Close(); if not SpinController.IsActive() then SpinController.Hide() end end },
	{ stallName = "Stall_Sell",      isOpen = function() return SellStandController.IsOpen() end, close = function() SellStandController.Close() end },
	{ stallName = "Stall_Upgrades",  isOpen = function() return UpgradeStandController.IsOpen() end, close = function() UpgradeStandController.Close() end },
	{ stallName = "Stall_Potions",   isOpen = function() return PotionController.IsShopOpen() end, close = function() PotionController.CloseShop() end },
	{ stallName = "Stall_Gems",      isOpen = function() return GemShopController.IsOpen() end, close = function() GemShopController.Close() end },
	{ stallName = "Stall_Sacrifice", isOpen = function() return SacrificeController.IsOpen() end, close = function() SacrificeController.Close() end },
}

local distCheckTimer = 0
RunService.Heartbeat:Connect(function(dt)
	distCheckTimer = distCheckTimer + dt
	if distCheckTimer < 0.5 then return end
	distCheckTimer = 0

	local character = Players.LocalPlayer.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local playerPos = rootPart.Position

	local hub = workspace:FindFirstChild("Hub")
	if not hub then return end

	for _, entry in ipairs(stallUIMap) do
		if entry.isOpen() then
			local stall = hub:FindFirstChild(entry.stallName)
			if stall then
				local stallPos
				if stall:IsA("Model") then
					local cf = stall:GetBoundingBox()
					stallPos = cf.Position
				elseif stall:IsA("BasePart") then
					stallPos = stall.Position
				end
				if stallPos and (playerPos - stallPos).Magnitude > STALL_CLOSE_DISTANCE then
					entry.close()
				end
			end
		end
	end
end)

-------------------------------------------------
-- DISMISS LOADING SCREEN
-------------------------------------------------

dismissLoadingScreen()

print("[Client] Spin the Streamer initialized!")
