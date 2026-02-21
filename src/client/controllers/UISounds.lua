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

return UISounds
