--[[
	SlotsConfig.lua
	Defines how many pad slots unlock per rebirth level.
	Layout: 4 rows x 5 columns = 20 total possible pads.
	Players start with 4 open slots; each rebirth adds 1 more.
	Premium Slot = 1 extra slot purchasable with Robux (slot 20).
]]

local SlotsConfig = {}

-- Starting slots (no rebirths needed)
SlotsConfig.StartingSlots = 4

-- Maximum possible rebirth-based slots (slots 1-19)
SlotsConfig.MaxRebirthSlots = 19

-- Premium slot adds 1 on top
SlotsConfig.PremiumSlotBonus = 1

-- Premium slot index (always the last one, slot 20)
SlotsConfig.PremiumSlotIndex = 20

-- Absolute maximum (rebirth max + premium)
SlotsConfig.MaxTotalSlots = SlotsConfig.MaxRebirthSlots + SlotsConfig.PremiumSlotBonus

-- Grid layout (must match DesignConfig.Base)
SlotsConfig.GridRows = 4
SlotsConfig.GridCols = 5

local _unlockOrderCache = nil

local function getDefaultColumnOrder(cols: number)
	if cols == 5 then
		-- two left, two right, then center
		return { 1, 2, 4, 5, 3 }
	end
	local order = {}
	for c = 1, cols do
		table.insert(order, c)
	end
	return order
end

--- Non-premium unlock order for base pads (slot indices 1..19).
--- Row-first from entrance to back, with column priority:
--- left pair, right pair, then center (for 5 columns).
function SlotsConfig.GetUnlockOrder(): { number }
	if _unlockOrderCache then
		return _unlockOrderCache
	end

	local order = {}
	local cols = SlotsConfig.GridCols
	local rows = SlotsConfig.GridRows
	local colOrder = getDefaultColumnOrder(cols)

	for row = 1, rows do
		for _, col in ipairs(colOrder) do
			local slotIndex = (row - 1) * cols + col
			if slotIndex ~= SlotsConfig.PremiumSlotIndex then
				table.insert(order, slotIndex)
			end
		end
	end

	_unlockOrderCache = order
	return order
end

--- Get number of rebirth-based slots for a given rebirth count.
--- Start with 4 slots, each rebirth adds 1.
function SlotsConfig.GetSlotsForRebirth(rebirthCount: number): number
	local slots = SlotsConfig.StartingSlots + rebirthCount
	return math.min(slots, SlotsConfig.MaxRebirthSlots)
end

--- Get total slots (rebirth + premium)
function SlotsConfig.GetTotalSlots(rebirthCount: number, hasPremiumSlot: boolean): number
	local base = SlotsConfig.GetSlotsForRebirth(rebirthCount)
	if hasPremiumSlot then
		base = base + SlotsConfig.PremiumSlotBonus
	end
	return math.min(base, SlotsConfig.MaxTotalSlots)
end

--- Get the rebirth level needed to unlock a specific slot index.
--- Slots 1-4 are free (rebirth 0). Slot 5 = rebirth 1, slot 6 = rebirth 2, etc.
function SlotsConfig.GetRebirthForSlot(slotIndex: number): number
	if slotIndex == SlotsConfig.PremiumSlotIndex then
		return -1 -- premium, not rebirth-based
	end
	local unlockOrder = SlotsConfig.GetUnlockOrder()
	local unlockPos = nil
	for i, idx in ipairs(unlockOrder) do
		if idx == slotIndex then
			unlockPos = i
			break
		end
	end
	if not unlockPos then
		return SlotsConfig.MaxRebirthSlots
	end
	if unlockPos <= SlotsConfig.StartingSlots then
		return 0
	end
	return unlockPos - SlotsConfig.StartingSlots
end

--- True if this specific slot index is unlocked for the player.
--- Rebirth unlocks slots 1..19 progressively; premium only unlocks slot 20.
function SlotsConfig.IsSlotUnlocked(rebirthCount: number, hasPremiumSlot: boolean, slotIndex: number): boolean
	if slotIndex < 1 or slotIndex > SlotsConfig.MaxTotalSlots then
		return false
	end
	if slotIndex == SlotsConfig.PremiumSlotIndex then
		return hasPremiumSlot == true
	end
	local unlockedCount = SlotsConfig.GetSlotsForRebirth(rebirthCount)
	local unlockOrder = SlotsConfig.GetUnlockOrder()
	for i = 1, math.min(unlockedCount, #unlockOrder) do
		if unlockOrder[i] == slotIndex then
			return true
		end
	end
	return false
end

return SlotsConfig
