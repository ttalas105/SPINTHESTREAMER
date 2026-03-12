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
local cashPopScale
local activeCashTween
local gemsLabel
local luckLabel
local moneyMultLabel
local potionsLabel
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
	sacrificeQueues = {},
	tutorialComplete = nil,
	ownedCrates = {},
	settings = nil,  -- { musicMuted, sacrificeMusicMuted, sfxEnabled } — applied when received
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
	local rounded = math.floor(n + (n >= 0 and 0.5 or -0.5))
	local absN = math.abs(rounded)

	-- Use compact format from millions and above.
	if absN >= 1e6 then
		local suffixes = {
			{ v = 1e15, s = "Q" },
			{ v = 1e12, s = "T" },
			{ v = 1e9, s = "B" },
			{ v = 1e6, s = "M" },
		}
		for _, entry in ipairs(suffixes) do
			if absN >= entry.v then
				local scaled = rounded / entry.v
				local oneDecimal = math.floor(scaled * 10 + (scaled >= 0 and 0.5 or -0.5)) / 10
				local whole = math.floor(oneDecimal)
				if math.abs(oneDecimal - whole) < 1e-9 then
					return tostring(whole) .. entry.s
				end
				return string.format("%.1f%s", oneDecimal, entry.s)
			end
		end
	end

	-- Otherwise, show full number with commas.
	local sign = rounded < 0 and "-" or ""
	local s = tostring(absN)
	local len = #s
	local firstGroup = ((len - 1) % 3) + 1
	local out = s:sub(1, firstGroup)
	local i = firstGroup + 1
	while i <= len do
		out = out .. "," .. s:sub(i, i + 2)
		i += 3
	end
	return sign .. out
end

-------------------------------------------------
-- BUILD UI
-------------------------------------------------

function HUDController.Init()
	-- Hide default Roblox health bar; we show our own HUD instead.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)

	local screenGui = UIHelper.CreateScreenGui("HUDGui", 3, 1.0)
	screenGui.Parent = playerGui

	local hudContainer = Instance.new("Frame")
	hudContainer.Name = "HUDContainer"
	hudContainer.Size = UDim2.new(0, 280, 0, 180)
	hudContainer.Position = UDim2.new(0, 12, 0.5, 210)
	hudContainer.AnchorPoint = Vector2.new(0, 0)
	hudContainer.BackgroundTransparency = 1
	hudContainer.BorderSizePixel = 0
	hudContainer.Parent = screenGui

	cashLabel = Instance.new("TextLabel")
	cashLabel.Name = "CashLabel"
	cashLabel.Size = UDim2.new(1, 0, 0, 34)
	cashLabel.Position = UDim2.new(0, 0, 0, 0)
	cashLabel.BackgroundTransparency = 1
	cashLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	cashLabel.Font = Enum.Font.FredokaOne
	cashLabel.TextSize = 28
	cashLabel.Text = "$0"
	cashLabel.TextXAlignment = Enum.TextXAlignment.Left
	cashLabel.Parent = hudContainer

	cashPopScale = Instance.new("UIScale")
	cashPopScale.Name = "PopScale"
	cashPopScale.Scale = 1
	cashPopScale.Parent = cashLabel

	local cashStroke = Instance.new("UIStroke")
	cashStroke.Color = Color3.fromRGB(0, 0, 0)
	cashStroke.Thickness = 2
	cashStroke.Parent = cashLabel

	gemsLabel = Instance.new("TextLabel")
	gemsLabel.Name = "GemsLabel"
	gemsLabel.Size = UDim2.new(1, 0, 0, 30)
	gemsLabel.Position = UDim2.new(0, 0, 0, 34)
	gemsLabel.BackgroundTransparency = 1
	gemsLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
	gemsLabel.Font = Enum.Font.FredokaOne
	gemsLabel.TextSize = 22
	gemsLabel.Text = "\u{1F48E} 0 Gems"
	gemsLabel.TextXAlignment = Enum.TextXAlignment.Left
	gemsLabel.Parent = hudContainer

	local gemsStroke = Instance.new("UIStroke")
	gemsStroke.Color = Color3.fromRGB(0, 0, 0)
	gemsStroke.Thickness = 2
	gemsStroke.Parent = gemsLabel

	local statsStack = Instance.new("Frame")
	statsStack.Name = "StatsStack"
	statsStack.Size = UDim2.new(1, 0, 0, 90)
	statsStack.Position = UDim2.new(0, 0, 0, 66)
	statsStack.BackgroundTransparency = 1
	statsStack.BorderSizePixel = 0
	statsStack.Parent = hudContainer

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Vertical
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 2)
	statsLayout.Parent = statsStack

	luckLabel = Instance.new("TextLabel")
	luckLabel.Name = "LuckLabel"
	luckLabel.Size = UDim2.new(1, 0, 0, 26)
	luckLabel.BackgroundTransparency = 1
	luckLabel.TextColor3 = Color3.fromRGB(220, 200, 255)
	luckLabel.Font = Enum.Font.FredokaOne
	luckLabel.TextSize = 18
	luckLabel.Text = "Luck: 0 (+0%)"
	luckLabel.TextXAlignment = Enum.TextXAlignment.Left
	luckLabel.LayoutOrder = 1
	luckLabel.Parent = statsStack

	local luckStroke = Instance.new("UIStroke")
	luckStroke.Color = Color3.fromRGB(0, 0, 0)
	luckStroke.Thickness = 2
	luckStroke.Parent = luckLabel

	moneyMultLabel = Instance.new("TextLabel")
	moneyMultLabel.Name = "MoneyMultLabel"
	moneyMultLabel.Size = UDim2.new(1, 0, 0, 26)
	moneyMultLabel.BackgroundTransparency = 1
	moneyMultLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	moneyMultLabel.Font = Enum.Font.FredokaOne
	moneyMultLabel.TextSize = 18
	moneyMultLabel.Text = "Money: x1.0"
	moneyMultLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyMultLabel.LayoutOrder = 2
	moneyMultLabel.Parent = statsStack

	local moneyMultStroke = Instance.new("UIStroke")
	moneyMultStroke.Color = Color3.fromRGB(0, 0, 0)
	moneyMultStroke.Thickness = 2
	moneyMultStroke.Parent = moneyMultLabel

	potionsLabel = Instance.new("TextLabel")
	potionsLabel.Name = "PotionsLabel"
	potionsLabel.Size = UDim2.new(1, 0, 0, 26)
	potionsLabel.BackgroundTransparency = 1
	potionsLabel.TextColor3 = Color3.fromRGB(120, 255, 180)
	potionsLabel.Font = Enum.Font.FredokaOne
	potionsLabel.TextSize = 18
	potionsLabel.Text = ""
	potionsLabel.TextXAlignment = Enum.TextXAlignment.Left
	potionsLabel.Visible = false
	potionsLabel.LayoutOrder = 3
	potionsLabel.Parent = statsStack

	local potionsStroke = Instance.new("UIStroke")
	potionsStroke.Color = Color3.fromRGB(0, 0, 0)
	potionsStroke.Thickness = 2
	potionsStroke.Parent = potionsLabel

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

	-- Apply persisted settings to music/SFX controllers
	if payload.settings and type(payload.settings) == "table" then
		local s = payload.settings
		local ok1, MusicController = pcall(require, script.Parent.MusicController)
		local ok2, UISounds = pcall(require, script.Parent.UISounds)
		if ok1 and MusicController then
			MusicController.SetLobbyMuted(s.musicMuted == true)
			MusicController.SetSacrificeMuted(s.sacrificeMusicMuted == true)
		end
		if ok2 and UISounds then
			UISounds.SetEnabled(s.sfxEnabled ~= false)
		end
	end

	-- Update cash display
	if cashLabel then
		cashLabel.Text = "$" .. formatCompactBalance(HUDController.Data.cash)

		if HUDController.Data.cash ~= previousCash then
			local flashColor = HUDController.Data.cash > previousCash
				and Color3.fromRGB(100, 255, 100)
				or Color3.fromRGB(255, 100, 100)
			cashLabel.TextColor3 = flashColor

			if activeCashTween then
				activeCashTween:Cancel()
				activeCashTween = nil
			end
			cashPopScale.Scale = 1

			local popTween = TweenService:Create(cashPopScale,
				TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1.08 })
			activeCashTween = popTween
			popTween:Play()
			popTween.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					local ret = TweenService:Create(cashPopScale,
						TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Scale = 1 })
					activeCashTween = ret
					ret:Play()
					ret.Completed:Connect(function()
						if activeCashTween == ret then activeCashTween = nil end
					end)
				end
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

	-- Lazy-require PotionController once
	if not PotionController then
		local ok, mod = pcall(function() return require(script.Parent.PotionController) end)
		if ok then PotionController = mod end
	end

	-- Gather potion multipliers (matches server PotionService stacking)
	local luckPotionMult = 1
	local cashPotionMult = 1
	local sacrificeLuckActive = false
	if PotionController and PotionController.ActivePotions then
		local ap = PotionController.ActivePotions
		local divineMult = (ap.Divine and ap.Divine.multiplier) or 0
		local luckMult = (ap.Luck and ap.Luck.multiplier) or 0
		local cashMult = (ap.Cash and ap.Cash.multiplier) or 0

		if ap.SacrificeLuck and ap.SacrificeLuck.multiplier and ap.SacrificeLuck.remaining and ap.SacrificeLuck.remaining > 0 then
			luckPotionMult = ap.SacrificeLuck.multiplier
			sacrificeLuckActive = true
		elseif divineMult > 0 or luckMult > 0 then
			luckPotionMult = divineMult + luckMult
		end

		if divineMult > 0 or cashMult > 0 then
			cashPotionMult = divineMult + cashMult
		end
	end

	-- Update luck display: show total effective luck multiplier (matches SpinService formula)
	if luckLabel then
		local rebirthCount = HUDController.Data.rebirthCount or 0
		local rebirthLuck = 1 + (rebirthCount * 0.02)
		local baseLuck = HUDController.Data.luck or 0
		local playerLuckFactor = 1 + (baseLuck / 100)
		local vipLuck = HUDController.Data.hasVIP and 1.5 or 1
		local x2Luck = HUDController.Data.hasX2Luck and 2 or 1
		local totalLuckMult = rebirthLuck * playerLuckFactor * luckPotionMult * vipLuck * x2Luck

		if totalLuckMult > 1.005 then
			luckLabel.Text = ("Luck: x%.2f"):format(totalLuckMult)
			luckLabel.TextColor3 = sacrificeLuckActive and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(200, 180, 255)
		else
			luckLabel.Text = "Luck: x1.00"
			luckLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
		end
	end

	-- Update money multiplier display: rebirth + cash upgrade + VIP + double cash + potions
	if moneyMultLabel then
		local rebirthCount = HUDController.Data.rebirthCount or 0
		local rebirthBonusPercent = 0
		local REBIRTH_BONUS_PER_LEVEL = { 5, 5, 5, 5, 5, 8, 8, 8, 8, 8, 12, 12, 12, 12, 12, 20, 20, 20, 20 }
		for i = 1, math.min(rebirthCount, 19) do
			rebirthBonusPercent = rebirthBonusPercent + (REBIRTH_BONUS_PER_LEVEL[i] or 5)
		end
		local rebirthMult = 1 + (rebirthBonusPercent / 100)

		local cashUpgrade = HUDController.Data.cashUpgrade or 0
		local cashUpgradeMult = 1 + cashUpgrade * 0.02

		local mult = rebirthMult * cashUpgradeMult
		if HUDController.Data.hasVIP then
			mult = mult * 1.5
		end
		if HUDController.Data.doubleCash then
			mult = mult * 2
		end
		if cashPotionMult > 1 then
			mult = mult * cashPotionMult
		end

		if mult > 1.005 then
			moneyMultLabel.Text = ("Money: x%.2f"):format(mult)
			moneyMultLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		else
			moneyMultLabel.Text = "Money: x1.00"
			moneyMultLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
		end
	end

	-- Potions label: show active potion names/timers as a compact summary
	if potionsLabel then
		local parts = {}
		if PotionController and PotionController.ActivePotions then
			local ap = PotionController.ActivePotions
			if ap.Divine and ap.Divine.remaining and ap.Divine.remaining > 0 then
				table.insert(parts, ("Divine %d:%02d"):format(math.floor(ap.Divine.remaining / 60), ap.Divine.remaining % 60))
			end
			if ap.Luck and ap.Luck.remaining and ap.Luck.remaining > 0 then
				table.insert(parts, ("Luck %d:%02d"):format(math.floor(ap.Luck.remaining / 60), ap.Luck.remaining % 60))
			end
			if ap.Cash and ap.Cash.remaining and ap.Cash.remaining > 0 then
				table.insert(parts, ("Cash %d:%02d"):format(math.floor(ap.Cash.remaining / 60), ap.Cash.remaining % 60))
			end
			if sacrificeLuckActive then
				local rem = ap.SacrificeLuck.remaining or 0
				table.insert(parts, ("Sacrifice %d:%02d"):format(math.floor(rem / 60), rem % 60))
			end
		end
		if #parts > 0 then
			potionsLabel.Text = "Potions: " .. table.concat(parts, " | ")
			potionsLabel.TextColor3 = Color3.fromRGB(120, 255, 180)
			potionsLabel.Visible = true
		else
			potionsLabel.Visible = false
			potionsLabel.Text = ""
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
