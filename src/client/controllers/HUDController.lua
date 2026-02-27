--[[
	HUDController.lua
	Bottom-left currency display showing: cash, rebirth count, spin credits.
	Matches reference: hearts (rebirth) + cash in bottom-left corner.
	Updates in real time when PlayerDataUpdate fires from server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

local DesignConfig = require(ReplicatedStorage.Shared.Config.DesignConfig)
local UIHelper = require(script.Parent.UIHelper)
local PotionController -- lazy require to avoid circular deps

local HUDController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Cached references
local cashLabel
local gemsLabel
local luckLabel
local moneyMultLabel
local GEM_GAIN_SOUND_ID = "rbxassetid://2650039396"
local cachedGemGainSound = nil
local hasSeenInitialGemValue = false

-- Local data mirror
HUDController.Data = {
	cash = 0,
	gems = 0,
	inventory = {},
	storage = {},
	equippedPads = {},
	collection = {},
	indexCollection = {},
	rebirthCount = 0,
	luck = 0,
	cashUpgrade = 0,
	totalSlots = 1,
	premiumSlotUnlocked = false,
	doubleCash = false,
	hasVIP = false,
	hasX2Luck = false,
	spinCredits = 0,
	sacrificeOneTime = {},
	sacrificeChargeState = { FiftyFifty = { count = 0, nextAt = nil }, FeelingLucky = { count = 0, nextAt = nil } },
	tutorialComplete = nil,
	ownedCrates = {},
}

local onDataUpdated = {}

local function playGemGainSound()
	if not cachedGemGainSound or not cachedGemGainSound.Parent then
		cachedGemGainSound = Instance.new("Sound")
		cachedGemGainSound.Name = "GemGainSFX"
		cachedGemGainSound.SoundId = GEM_GAIN_SOUND_ID
		cachedGemGainSound.Volume = 0.9
		cachedGemGainSound.Parent = SoundService
	end

	local clone = cachedGemGainSound:Clone()
	clone.Parent = SoundService
	SoundService:PlayLocalSound(clone)
	clone.Ended:Connect(function()
		if clone and clone.Parent then clone:Destroy() end
	end)
	task.delay(3, function()
		if clone and clone.Parent then clone:Destroy() end
	end)
end

local function formatCompactBalance(value)
	local n = tonumber(value) or 0
	local absN = math.abs(n)
	if absN < 1e6 then
		return tostring(math.floor(n + 0.5))
	end

	local suffixes = {
		{ v = 1e15, s = "q" },
		{ v = 1e12, s = "t" },
		{ v = 1e9,  s = "b" },
		{ v = 1e6,  s = "m" },
	}

	for _, entry in ipairs(suffixes) do
		if absN >= entry.v then
			local scaled = n / entry.v
			local rounded = math.floor(scaled * 10 + (scaled >= 0 and 0.5 or -0.5)) / 10
			local whole = math.floor(rounded)
			if math.abs(rounded - whole) < 1e-9 then
				return tostring(whole) .. entry.s
			end
			return string.format("%.1f%s", rounded, entry.s)
		end
	end

	return tostring(math.floor(n + 0.5))
end

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function HUDController.Init()
	-- Hide default Roblox health bar; we show our own HUD instead.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	local screenGui = UIHelper.CreateScreenGui("HUDGui", 3)
	screenGui.Parent = playerGui

	local hudContainer = Instance.new("Frame")
	hudContainer.Name = "HUDContainer"
	hudContainer.Size = UDim2.new(0, 300, 0, 148)
	hudContainer.Position = UDim2.new(0.5, -250, 0, 8)
	hudContainer.AnchorPoint = Vector2.new(1, 0)
	hudContainer.BackgroundTransparency = 1
	hudContainer.BorderSizePixel = 0
	hudContainer.Parent = screenGui

	cashLabel = Instance.new("TextLabel")
	cashLabel.Name = "CashLabel"
	cashLabel.Size = UDim2.new(1, 0, 0, 38)
	cashLabel.Position = UDim2.new(0, 0, 0, 0)
	cashLabel.BackgroundTransparency = 1
	cashLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	cashLabel.Font = Enum.Font.FredokaOne
	cashLabel.TextSize = 34
	cashLabel.Text = "$0"
	cashLabel.TextXAlignment = Enum.TextXAlignment.Left
	cashLabel.Parent = hudContainer

	local cashStroke = Instance.new("UIStroke")
	cashStroke.Color = Color3.fromRGB(0, 0, 0)
	cashStroke.Thickness = 2
	cashStroke.Parent = cashLabel

	gemsLabel = Instance.new("TextLabel")
	gemsLabel.Name = "GemsLabel"
	gemsLabel.Size = UDim2.new(1, 0, 0, 30)
	gemsLabel.Position = UDim2.new(0, 0, 0, 40)
	gemsLabel.BackgroundTransparency = 1
	gemsLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
	gemsLabel.Font = Enum.Font.FredokaOne
	gemsLabel.TextSize = 26
	gemsLabel.Text = "\u{1F48E} 0 Gems"
	gemsLabel.TextXAlignment = Enum.TextXAlignment.Left
	gemsLabel.Parent = hudContainer

	local gemsStroke = Instance.new("UIStroke")
	gemsStroke.Color = Color3.fromRGB(0, 0, 0)
	gemsStroke.Thickness = 2
	gemsStroke.Parent = gemsLabel

	luckLabel = Instance.new("TextLabel")
	luckLabel.Name = "LuckLabel"
	luckLabel.Size = UDim2.new(1, 0, 0, 28)
	luckLabel.Position = UDim2.new(0, 0, 0, 72)
	luckLabel.BackgroundTransparency = 1
	luckLabel.TextColor3 = Color3.fromRGB(220, 200, 255)
	luckLabel.Font = Enum.Font.FredokaOne
	luckLabel.TextSize = 24
	luckLabel.Text = "Luck: 0 (+0%)"
	luckLabel.TextXAlignment = Enum.TextXAlignment.Left
	luckLabel.Parent = hudContainer

	local luckStroke = Instance.new("UIStroke")
	luckStroke.Color = Color3.fromRGB(0, 0, 0)
	luckStroke.Thickness = 2
	luckStroke.Parent = luckLabel

	moneyMultLabel = Instance.new("TextLabel")
	moneyMultLabel.Name = "MoneyMultLabel"
	moneyMultLabel.Size = UDim2.new(1, 0, 0, 26)
	moneyMultLabel.Position = UDim2.new(0, 0, 0, 100)
	moneyMultLabel.BackgroundTransparency = 1
	moneyMultLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	moneyMultLabel.Font = Enum.Font.FredokaOne
	moneyMultLabel.TextSize = 22
	moneyMultLabel.Text = "Money: x1.0"
	moneyMultLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyMultLabel.Parent = hudContainer

	local moneyMultStroke = Instance.new("UIStroke")
	moneyMultStroke.Color = Color3.fromRGB(0, 0, 0)
	moneyMultStroke.Thickness = 2
	moneyMultStroke.Parent = moneyMultLabel

	-- Listen for data updates from server
	local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
	local PlayerDataUpdate = RemoteEvents:WaitForChild("PlayerDataUpdate")

	PlayerDataUpdate.OnClientEvent:Connect(function(payload)
		HUDController.UpdateData(payload)
	end)

	-- Also refresh luck display when potions change
	local PotionUpdate = RemoteEvents:WaitForChild("PotionUpdate")
	PotionUpdate.OnClientEvent:Connect(function()
		-- Re-run the luck label update with current data
		if luckLabel then
			HUDController.UpdateData({}) -- triggers the luck display refresh with 0 changes
		end
	end)
end

-------------------------------------------------
-- DATA UPDATE
-------------------------------------------------

function HUDController.UpdateData(payload)
	local previousCash = HUDController.Data.cash
	local previousGems = HUDController.Data.gems or 0
	local payloadIncludesGems = payload and payload.gems ~= nil

	for key, value in pairs(payload) do
		HUDController.Data[key] = value
	end

	-- Update cash display
	if cashLabel then
		cashLabel.Text = "$" .. formatCompactBalance(HUDController.Data.cash)

		if HUDController.Data.cash ~= previousCash then
			local flashColor = HUDController.Data.cash > previousCash
				and Color3.fromRGB(100, 255, 100)
				or Color3.fromRGB(255, 100, 100)
			cashLabel.TextColor3 = flashColor

			local origSize = cashLabel.Size
			local popSize = UDim2.new(
				origSize.X.Scale * 1.06, origSize.X.Offset * 1.06,
				origSize.Y.Scale * 1.06, origSize.Y.Offset * 1.06
			)
			local popInfo = TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local returnInfo = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In)

			local popTween = TweenService:Create(cashLabel, popInfo, { Size = popSize })
			popTween:Play()
			popTween.Completed:Connect(function()
				TweenService:Create(cashLabel, returnInfo, { Size = origSize }):Play()
			end)

			task.delay(0.2, function()
				TweenService:Create(cashLabel, TweenInfo.new(0.3), {
					TextColor3 = DesignConfig.Colors.Accent,
				}):Play()
			end)
		end
	end

	-- Update gems display
	if gemsLabel then
		gemsLabel.Text = "\u{1F48E} " .. formatCompactBalance(HUDController.Data.gems or 0) .. " Gems"
	end
	if payloadIncludesGems then
		local currentGems = HUDController.Data.gems or 0
		if hasSeenInitialGemValue and currentGems > previousGems then
			playGemGainSound()
		end
		hasSeenInitialGemValue = true
	end

	-- Update luck display (1 luck = +1%) with potion boost shown
	if luckLabel then
		local luck = HUDController.Data.luck or 0
		local percent = luck  -- 1 luck = 1%
		-- Check for active luck potion
		if not PotionController then
			local ok, mod = pcall(function() return require(script.Parent.PotionController) end)
			if ok then PotionController = mod end
		end
		local potionMult = 1
		local potionSource = ""
		if PotionController and PotionController.ActivePotions then
			local divineMult = (PotionController.ActivePotions.Divine and PotionController.ActivePotions.Divine.multiplier) or 0
			local luckMult = (PotionController.ActivePotions.Luck and PotionController.ActivePotions.Luck.multiplier) or 0
			if divineMult > 0 or luckMult > 0 then
				potionMult = divineMult + luckMult
				if divineMult > 0 and luckMult > 0 then
					potionSource = "Divine+Luck"
				elseif divineMult > 0 then
					potionSource = "Divine"
				else
					potionSource = "Luck"
				end
			end
		end
		if potionMult > 1 then
			local potionLabel = (potionSource == "Divine+Luck") and "Potions" or potionSource
			luckLabel.Text = ("Luck: %d (+%d%%)  |  %s: x%.1f"):format(luck, percent, potionLabel, potionMult)
			luckLabel.TextColor3 = (potionSource == "Divine" or potionSource == "Divine+Luck")
				and Color3.fromRGB(255, 150, 255) or Color3.fromRGB(80, 255, 100)
		else
			luckLabel.Text = ("Luck: %d (+%d%%)"):format(luck, percent)
			luckLabel.TextColor3 = Color3.fromRGB(200, 180, 255) -- default purple
		end
	end

	-- Update money multiplier display
	if moneyMultLabel then
		local mult = 1
		local cashUpgrade = HUDController.Data.cashUpgrade or 0
		mult = mult * (1 + cashUpgrade * 0.02)
		if HUDController.Data.hasVIP then
			mult = mult * 1.5
		end
		if HUDController.Data.doubleCash then
			mult = mult * 2
		end
		if not PotionController then
			local ok, mod = pcall(function() return require(script.Parent.PotionController) end)
			if ok then PotionController = mod end
		end
		if PotionController and PotionController.ActivePotions then
			local divineMult = (PotionController.ActivePotions.Divine and PotionController.ActivePotions.Divine.multiplier) or 0
			local cashPotMult = (PotionController.ActivePotions.Cash and PotionController.ActivePotions.Cash.multiplier) or 0
			local potionTotal = divineMult + cashPotMult
			if potionTotal > 0 then
				mult = mult * potionTotal
			end
		end

		if mult > 1 then
			moneyMultLabel.Text = ("Money: x%.1f"):format(mult)
			moneyMultLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		else
			moneyMultLabel.Text = "Money: x1.0"
			moneyMultLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
		end
	end

	-- Fire data update callbacks
	for _, callback in ipairs(onDataUpdated) do
		task.spawn(callback, HUDController.Data)
	end
end

function HUDController.OnDataUpdated(callback)
	table.insert(onDataUpdated, callback)
end

return HUDController
