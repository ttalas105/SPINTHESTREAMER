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
bg.BackgroundColor3 = Color3.fromRGB(20, 10, 50)
bg.BorderSizePixel = 0
bg.ZIndex = 1
bg.Parent = loadGui

local bgGrad = Instance.new("UIGradient")
bgGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 15, 80)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(80, 30, 140)),
	ColorSequenceKeypoint.new(0.65, Color3.fromRGB(30, 60, 160)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 20, 120)),
})
bgGrad.Rotation = 135
bgGrad.Parent = bg

-- Animated background gradient rotation
task.spawn(function()
	local rot = 135
	while loadGui and loadGui.Parent do
		rot = (rot + 0.3) % 360
		bgGrad.Rotation = rot
		RunService.Heartbeat:Wait()
	end
end)

-- Floating sparkle particles
local particleContainer = Instance.new("Frame")
particleContainer.Name = "Particles"
particleContainer.Size = UDim2.new(1, 0, 1, 0)
particleContainer.BackgroundTransparency = 1
particleContainer.ZIndex = 2
particleContainer.ClipsDescendants = true
particleContainer.Parent = bg

local PARTICLE_COLORS = {
	Color3.fromRGB(255, 200, 80),
	Color3.fromRGB(120, 220, 255),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(180, 100, 255),
	Color3.fromRGB(100, 255, 180),
	Color3.fromRGB(255, 150, 100),
}

local particleFrames = {}
task.spawn(function()
	for i = 1, 30 do
		if not (loadGui and loadGui.Parent) then break end
		local p = Instance.new("Frame")
		local sz = math.random(3, 8)
		p.Size = UDim2.new(0, sz, 0, sz)
		p.Position = UDim2.new(math.random() * 1.2 - 0.1, 0, 1.05, 0)
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.BackgroundColor3 = PARTICLE_COLORS[math.random(#PARTICLE_COLORS)]
		p.BackgroundTransparency = math.random() * 0.3 + 0.2
		p.BorderSizePixel = 0
		p.ZIndex = 2
		p.Rotation = math.random(0, 360)
		p.Parent = particleContainer
		Instance.new("UICorner", p).CornerRadius = UDim.new(1, 0)
		table.insert(particleFrames, p)

		local dur = math.random(40, 80) / 10
		local xDrift = math.random(-60, 60)
		TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {
			Position = UDim2.new(p.Position.X.Scale, xDrift, -0.1, 0),
			Rotation = p.Rotation + math.random(-180, 180),
		}):Play()
		TweenService:Create(p, TweenInfo.new(dur * 0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			BackgroundTransparency = math.random() * 0.4 + 0.5,
		}):Play()

		if i % 5 == 0 then task.wait(0.05) end
	end
end)

-- Floating fun emoji icons
local EMOJIS = { "🎰", "💎", "🔥", "⭐", "🎮", "🎬", "🏆", "💰", "✨", "🎲" }
local emojiLabels = {}
task.spawn(function()
	for i = 1, 12 do
		if not (loadGui and loadGui.Parent) then break end
		local em = Instance.new("TextLabel")
		em.Size = UDim2.new(0, 40, 0, 40)
		em.Position = UDim2.new(math.random() * 0.9 + 0.05, 0, math.random() * 0.8 + 0.1, 0)
		em.AnchorPoint = Vector2.new(0.5, 0.5)
		em.BackgroundTransparency = 1
		em.Text = EMOJIS[math.random(#EMOJIS)]
		em.TextSize = math.random(24, 42)
		em.TextTransparency = 0.5
		em.Font = Enum.Font.GothamBold
		em.ZIndex = 3
		em.Rotation = math.random(-20, 20)
		em.Parent = bg
		table.insert(emojiLabels, em)

		local floatDur = math.random(25, 50) / 10
		local startY = em.Position.Y.Scale
		TweenService:Create(em, TweenInfo.new(floatDur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Position = UDim2.new(em.Position.X.Scale, 0, startY - 0.03, 0),
			Rotation = em.Rotation + math.random(-10, 10),
			TextTransparency = 0.7,
		}):Play()
	end
end)

-- Glowing ring behind the title
local glowRing = Instance.new("Frame")
glowRing.Name = "GlowRing"
glowRing.Size = UDim2.new(0, 500, 0, 500)
glowRing.Position = UDim2.new(0.5, 0, 0.35, 0)
glowRing.AnchorPoint = Vector2.new(0.5, 0.5)
glowRing.BackgroundColor3 = Color3.fromRGB(140, 80, 255)
glowRing.BackgroundTransparency = 0.85
glowRing.BorderSizePixel = 0
glowRing.ZIndex = 3
glowRing.Parent = bg
Instance.new("UICorner", glowRing).CornerRadius = UDim.new(1, 0)

task.spawn(function()
	while loadGui and loadGui.Parent do
		TweenService:Create(glowRing, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Size = UDim2.new(0, 560, 0, 560),
			BackgroundTransparency = 0.92,
		}):Play()
		task.wait(1.8)
		if not (loadGui and loadGui.Parent) then break end
		TweenService:Create(glowRing, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Size = UDim2.new(0, 500, 0, 500),
			BackgroundTransparency = 0.85,
		}):Play()
		task.wait(1.8)
	end
end)

-- Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(0, 800, 0, 120)
titleLabel.Position = UDim2.new(0.5, 0, 0.32, 0)
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "SPIN THE STREAMER"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.TextSize = 72
titleLabel.TextScaled = true
titleLabel.ZIndex = 10
titleLabel.Parent = bg

local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(255, 180, 50)
titleStroke.Thickness = 4
titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
titleStroke.Parent = titleLabel

local titleGrad = Instance.new("UIGradient")
titleGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 80)),
	ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 140, 200)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(120, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
})
titleGrad.Parent = titleLabel

-- Animated title gradient shimmer
task.spawn(function()
	local offset = 0
	while loadGui and loadGui.Parent do
		offset = (offset + 0.005) % 1
		titleGrad.Offset = Vector2.new(offset, 0)
		RunService.Heartbeat:Wait()
	end
end)

-- Title bounce animation
task.spawn(function()
	while loadGui and loadGui.Parent do
		TweenService:Create(titleLabel, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Position = UDim2.new(0.5, 0, 0.31, 0),
		}):Play()
		task.wait(0.8)
		if not (loadGui and loadGui.Parent) then break end
		TweenService:Create(titleLabel, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Position = UDim2.new(0.5, 0, 0.33, 0),
		}):Play()
		task.wait(0.8)
	end
end)

-- Subtitle
local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.Size = UDim2.new(0, 500, 0, 36)
subtitleLabel.Position = UDim2.new(0.5, 0, 0.43, 0)
subtitleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Loading assets..."
subtitleLabel.TextColor3 = Color3.fromRGB(220, 210, 255)
subtitleLabel.Font = Enum.Font.GothamBold
subtitleLabel.TextSize = 22
subtitleLabel.ZIndex = 10
subtitleLabel.Parent = bg

local subtitleStroke = Instance.new("UIStroke")
subtitleStroke.Color = Color3.fromRGB(60, 30, 120)
subtitleStroke.Thickness = 1.5
subtitleStroke.Parent = subtitleLabel

-- Progress bar (wider and chunkier)
local barBg = Instance.new("Frame")
barBg.Name = "BarBG"
barBg.Size = UDim2.new(0, 500, 0, 20)
barBg.Position = UDim2.new(0.5, 0, 0.50, 0)
barBg.AnchorPoint = Vector2.new(0.5, 0.5)
barBg.BackgroundColor3 = Color3.fromRGB(30, 20, 60)
barBg.BorderSizePixel = 0
barBg.ZIndex = 10
barBg.Parent = bg
Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(120, 80, 200)
barStroke.Thickness = 2
barStroke.Parent = barBg

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(255, 180, 50)
barFill.BorderSizePixel = 0
barFill.ZIndex = 11
barFill.Parent = barBg
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

local fillGrad = Instance.new("UIGradient")
fillGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 180)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 100, 255)),
})
fillGrad.Parent = barFill

-- Animated bar glow
local barGlow = Instance.new("Frame")
barGlow.Name = "BarGlow"
barGlow.Size = UDim2.new(1, 10, 1, 10)
barGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
barGlow.AnchorPoint = Vector2.new(0.5, 0.5)
barGlow.BackgroundColor3 = Color3.fromRGB(140, 80, 255)
barGlow.BackgroundTransparency = 0.7
barGlow.BorderSizePixel = 0
barGlow.ZIndex = 9
barGlow.Parent = barBg
Instance.new("UICorner", barGlow).CornerRadius = UDim.new(1, 0)

task.spawn(function()
	while loadGui and loadGui.Parent do
		TweenService:Create(barGlow, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			BackgroundTransparency = 0.85,
			Size = UDim2.new(1, 16, 1, 16),
		}):Play()
		task.wait(1)
		if not (loadGui and loadGui.Parent) then break end
		TweenService:Create(barGlow, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			BackgroundTransparency = 0.7,
			Size = UDim2.new(1, 10, 1, 10),
		}):Play()
		task.wait(1)
	end
end)

-- Percent label
local percentLabel = Instance.new("TextLabel")
percentLabel.Name = "Percent"
percentLabel.Size = UDim2.new(0, 120, 0, 28)
percentLabel.Position = UDim2.new(0.5, 0, 0.555, 0)
percentLabel.AnchorPoint = Vector2.new(0.5, 0.5)
percentLabel.BackgroundTransparency = 1
percentLabel.Text = "0%"
percentLabel.TextColor3 = Color3.fromRGB(255, 220, 140)
percentLabel.Font = Enum.Font.FredokaOne
percentLabel.TextSize = 20
percentLabel.ZIndex = 10
percentLabel.Parent = bg

-- Tip label (bigger, with icon prefix)
local tipLabel = Instance.new("TextLabel")
tipLabel.Name = "Tip"
tipLabel.Size = UDim2.new(0, 600, 0, 36)
tipLabel.Position = UDim2.new(0.5, 0, 0.90, 0)
tipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
tipLabel.BackgroundTransparency = 1
tipLabel.TextColor3 = Color3.fromRGB(200, 190, 255)
tipLabel.Font = Enum.Font.GothamBold
tipLabel.TextSize = 18
tipLabel.ZIndex = 10
tipLabel.Parent = bg

local tipStroke = Instance.new("UIStroke")
tipStroke.Color = Color3.fromRGB(40, 20, 80)
tipStroke.Thickness = 1
tipStroke.Parent = tipLabel

local TIPS = {
	"💰 Place streamers on your base to earn cash!",
	"✨ Rarer streamers earn way more cash per second.",
	"🧪 Use potions to multiply your luck and earnings!",
	"💎 Sacrifice duplicate streamers for gems.",
	"📖 Check the Index to see which streamers you're missing.",
	"👑 VIP Pass gives you 1.5x cash forever!",
	"🔄 Rebirth to unlock stronger potions and bonuses.",
	"🌟 Divine Potions multiply EVERYTHING by 5x!",
	"🎰 Spin the wheel for a chance at legendary streamers!",
	"🏆 Compete on the leaderboard for bragging rights!",
	"🔥 Stack potions for insane multiplier combos!",
	"🎮 More streamers = more cash per second!",
}
tipLabel.Text = TIPS[math.random(#TIPS)]

-- Rotating tips with fade animation
task.spawn(function()
	while loadGui and loadGui.Parent do
		task.wait(3.5)
		if not (loadGui and loadGui.Parent) then break end
		TweenService:Create(tipLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		task.wait(0.3)
		if not (loadGui and loadGui.Parent) then break end
		tipLabel.Text = TIPS[math.random(#TIPS)]
		TweenService:Create(tipLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	end
end)

-- Spinner dots (bigger, more colorful)
local spinnerDots = {}
local DOT_COLORS = {
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(255, 120, 180),
	Color3.fromRGB(120, 200, 255),
}
for i = 1, 3 do
	local dot = Instance.new("Frame")
	dot.Name = "Dot" .. i
	dot.Size = UDim2.new(0, 12, 0, 12)
	dot.Position = UDim2.new(0.5, (i - 2) * 24, 0.62, 0)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = DOT_COLORS[i]
	dot.BackgroundTransparency = 0.5
	dot.BorderSizePixel = 0
	dot.ZIndex = 10
	dot.Parent = bg
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	spinnerDots[i] = dot
end

task.spawn(function()
	local idx = 0
	while loadGui and loadGui.Parent do
		idx = (idx % 3) + 1
		for i, dot in ipairs(spinnerDots) do
			if i == idx then
				TweenService:Create(dot, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					BackgroundTransparency = 0,
					Size = UDim2.new(0, 16, 0, 16),
				}):Play()
			else
				TweenService:Create(dot, TweenInfo.new(0.2), {
					BackgroundTransparency = 0.5,
					Size = UDim2.new(0, 12, 0, 12),
				}):Play()
			end
		end
		task.wait(0.3)
	end
end)

-- "Get ready to spin!" label under the dots
local readyLabel = Instance.new("TextLabel")
readyLabel.Name = "ReadyLabel"
readyLabel.Size = UDim2.new(0, 400, 0, 30)
readyLabel.Position = UDim2.new(0.5, 0, 0.67, 0)
readyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
readyLabel.BackgroundTransparency = 1
readyLabel.Text = "Get ready to spin!"
readyLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
readyLabel.Font = Enum.Font.FredokaOne
readyLabel.TextSize = 20
readyLabel.TextTransparency = 0.3
readyLabel.ZIndex = 10
readyLabel.Parent = bg

task.spawn(function()
	while loadGui and loadGui.Parent do
		TweenService:Create(readyLabel, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			TextTransparency = 0.6,
		}):Play()
		task.wait(1)
		if not (loadGui and loadGui.Parent) then break end
		TweenService:Create(readyLabel, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			TextTransparency = 0.2,
		}):Play()
		task.wait(1)
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
	setLoadProgress(1, "Let's go!")
	task.wait(0.5)

	local fadeInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bg, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(titleLabel, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(titleStroke, fadeInfo, { Transparency = 1 }):Play()
	TweenService:Create(subtitleLabel, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitleStroke, fadeInfo, { Transparency = 1 }):Play()
	TweenService:Create(percentLabel, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(tipLabel, fadeInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(tipStroke, fadeInfo, { Transparency = 1 }):Play()
	TweenService:Create(barBg, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(barStroke, fadeInfo, { Transparency = 1 }):Play()
	TweenService:Create(barFill, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(barGlow, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(glowRing, fadeInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(readyLabel, fadeInfo, { TextTransparency = 1 }):Play()
	for _, dot in ipairs(spinnerDots) do
		TweenService:Create(dot, fadeInfo, { BackgroundTransparency = 1 }):Play()
	end
	for _, em in ipairs(emojiLabels) do
		TweenService:Create(em, fadeInfo, { TextTransparency = 1 }):Play()
	end
	for _, p in ipairs(particleFrames) do
		TweenService:Create(p, fadeInfo, { BackgroundTransparency = 1 }):Play()
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
local cachedRestockSound = nil
local lastUnifiedRestockToastAt = 0
local RESTOCK_TOAST_COOLDOWN = 1.25

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

local function showCenterToast(messageText)
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
		centerToastLabel.Size = UDim2.new(0, 760, 0, 122)
		centerToastLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		centerToastLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		centerToastLabel.BackgroundColor3 = Color3.fromRGB(20, 45, 120)
		centerToastLabel.BackgroundTransparency = 0.06
		centerToastLabel.BorderSizePixel = 0
		centerToastLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		centerToastLabel.Font = Enum.Font.FredokaOne
		centerToastLabel.TextSize = 52
		centerToastLabel.TextWrapped = true
		centerToastLabel.TextStrokeColor3 = Color3.fromRGB(50, 200, 255)
		centerToastLabel.TextStrokeTransparency = 0.12
		centerToastLabel.Visible = false
		centerToastLabel.Parent = centerToastGui
		Instance.new("UICorner", centerToastLabel).CornerRadius = UDim.new(0, 18)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(120, 220, 255)
		stroke.Thickness = 3
		stroke.Transparency = 0
		stroke.Parent = centerToastLabel
		centerToastStroke = stroke
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(65, 115, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 210, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 70, 255)),
		})
		gradient.Rotation = 25
		gradient.Parent = centerToastLabel
	end

	centerToastToken += 1
	local token = centerToastToken
	centerToastLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	centerToastLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	centerToastLabel.Text = messageText or ""
	centerToastLabel.BackgroundTransparency = 0.06
	centerToastLabel.TextTransparency = 0
	centerToastLabel.Size = UDim2.new(0, 760, 0, 122)
	if centerToastStroke then
		centerToastStroke.Transparency = 0
	end
	centerToastLabel.Visible = true
	local pop = TweenService:Create(centerToastLabel, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 800, 0, 134),
	})
	pop:Play()

	task.delay(2.7, function()
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

local function announceUnifiedRestock()
	local now = os.clock()
	if now - lastUnifiedRestockToastAt < RESTOCK_TOAST_COOLDOWN then
		return
	end
	lastUnifiedRestockToastAt = now
	playRestockSound()
	showCenterToast("POTIONS + CASES HAVE RESTOCKED!")
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
		announceUnifiedRestock()
	end
end

local function handlePotionStockPayload(payload)
	if type(payload) ~= "table" then return end
	local restockIn = payload.restockIn
	if type(restockIn) ~= "number" then return end
	if payload.restocked == true then
		announceUnifiedRestock()
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
