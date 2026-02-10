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
	if slotIndex <= SlotsConfig.StartingSlots then
		return 0 -- free from the start
	end
	-- Each rebirth unlocks 1 more slot beyond the starting 4
	return slotIndex - SlotsConfig.StartingSlots
end

return SlotsConfig
