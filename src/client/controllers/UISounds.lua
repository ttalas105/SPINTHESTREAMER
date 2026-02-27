--[[
	UISounds.lua
	Satisfying hover and click sounds for main nav UI only
	(not for stand UIs like spin, upgrades, etc.).
	Uses SoundService "UIClick" / "UIHover" if present, else fallback asset.
]]

local SoundService = game:GetService("SoundService")

local UISounds = {}

-- Fallback asset: UI click sound (verified Roblox catalog)
local FALLBACK_CLICK_ID = "rbxassetid://7212399604"

local cachedClickSound = nil
local cachedHoverSound = nil
local sfxEnabled = true

local function getClickSound(): Sound?
	if cachedClickSound and cachedClickSound.Parent then
		return cachedClickSound
	end
	local byName = SoundService:FindFirstChild("UIClick")
	if byName and byName:IsA("Sound") then
		cachedClickSound = byName
		return byName
	end
	local sound = Instance.new("Sound")
	sound.Name = "UIClick"
	sound.SoundId = FALLBACK_CLICK_ID
	sound.Volume = 1
	sound.Parent = SoundService
	cachedClickSound = sound
	return sound
end

local function getHoverSound(): Sound?
	if cachedHoverSound and cachedHoverSound.Parent then
		return cachedHoverSound
	end
	local byName = SoundService:FindFirstChild("UIHover")
	if byName and byName:IsA("Sound") then
		cachedHoverSound = byName
		return byName
	end
	-- Reuse click sound for hover at lower volume
	return getClickSound()
end

local function cleanupClone(clone)
	task.defer(function()
		if clone and clone.Parent then
			clone:Destroy()
		end
	end)
end

--- Play a satisfying click (use when opening a panel or selecting a nav button).
function UISounds.PlayClick()
	if not sfxEnabled then return end
	local s = getClickSound()
	if not s then return end
	local clone = s:Clone()
	clone.Volume = 1
	clone.Parent = SoundService
	SoundService:PlayLocalSound(clone)
	clone.Ended:Connect(function()
		cleanupClone(clone)
	end)
	task.delay(2, function()
		if clone and clone.Parent then
			cleanupClone(clone)
		end
	end)
end

--- Play a subtle hover sound (use on MouseEnter for nav buttons).
function UISounds.PlayHover()
	if not sfxEnabled then return end
	local s = getHoverSound()
	if not s then return end
	local clone = s:Clone()
	clone.Volume = 0.45
	clone.Parent = SoundService
	SoundService:PlayLocalSound(clone)
	clone.Ended:Connect(function()
		cleanupClone(clone)
	end)
	task.delay(2, function()
		if clone and clone.Parent then
			cleanupClone(clone)
		end
	end)
end

-------------------------------------------------
-- SPIN SOUNDS
-------------------------------------------------

local SPIN_TICK_ID = "rbxassetid://421058925"
local SPIN_WIN_ID  = "rbxassetid://140728595235867"

local cachedSpinTick = nil
local cachedSpinWin = nil

local function getSpinTick(): Sound?
	if cachedSpinTick and cachedSpinTick.Parent then
		return cachedSpinTick
	end
	local byName = SoundService:FindFirstChild("SpinTick")
	if byName and byName:IsA("Sound") then
		cachedSpinTick = byName
		return byName
	end
	local sound = Instance.new("Sound")
	sound.Name = "SpinTick"
	sound.SoundId = SPIN_TICK_ID
	sound.Volume = 0.5
	sound.Parent = SoundService
	cachedSpinTick = sound
	return sound
end

local function getSpinWin(): Sound?
	if cachedSpinWin and cachedSpinWin.Parent then
		return cachedSpinWin
	end
	local byName = SoundService:FindFirstChild("SpinWin")
	if byName and byName:IsA("Sound") then
		cachedSpinWin = byName
		return byName
	end
	local sound = Instance.new("Sound")
	sound.Name = "SpinWin"
	sound.SoundId = SPIN_WIN_ID
	sound.Volume = 0.7
	sound.Parent = SoundService
	cachedSpinWin = sound
	return sound
end

--- Short tick played each time a card crosses the selector line during spin.
--- `pitch` (0.8–1.5) lets the tick rise in pitch as the reel slows down.
function UISounds.PlaySpinTick(pitch: number?)
	if not sfxEnabled then return end
	local s = getSpinTick()
	if not s then return end
	local clone = s:Clone()
	clone.Volume = 0.35
	clone.PlaybackSpeed = pitch or 1.2
	clone.Parent = SoundService
	SoundService:PlayLocalSound(clone)
	clone.Ended:Connect(function() cleanupClone(clone) end)
	task.delay(0.5, function()
		if clone and clone.Parent then cleanupClone(clone) end
	end)
end

--- Celebratory sound when the spin lands on the winning card.
function UISounds.PlaySpinWin()
	if not sfxEnabled then return end
	local s = getSpinWin()
	if not s then return end
	local clone = s:Clone()
	clone.Volume = 0.25
	clone.Parent = SoundService
	SoundService:PlayLocalSound(clone)
	clone.Ended:Connect(function() cleanupClone(clone) end)
	task.delay(4, function()
		if clone and clone.Parent then cleanupClone(clone) end
	end)
end

function UISounds.SetEnabled(enabled: boolean)
	sfxEnabled = enabled ~= false
end

function UISounds.IsEnabled(): boolean
	return sfxEnabled
end

return UISounds
