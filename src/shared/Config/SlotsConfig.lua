--[[
	SlotsConfig.lua
	Defines how many pad slots unlock per rebirth level.
	Layout: 4 rows x 5 columns = 20 total possible pads.
	18 rebirth-based + 1 premium + 1 reserved = 20.
	Premium Slot = 1 extra slot purchasable with Robux.
]]

local SlotsConfig = {}

-- Rebirth-based slots: Key = rebirth count, Value = total rebirth slots
-- Players always have at least 1 slot (slot 1)
SlotsConfig.SlotsByRebirth = {
	[0]  = 1,   -- start with 1 slot
	[1]  = 3,
	[2]  = 5,
	[3]  = 7,
	[4]  = 9,
	[5]  = 12,
	[8]  = 15,
	[10] = 18,
}

-- Maximum possible rebirth-based slots
SlotsConfig.MaxRebirthSlots = 18

-- Premium slot adds 1 on top
SlotsConfig.PremiumSlotBonus = 1

-- Premium slot index (always the last one)
SlotsConfig.PremiumSlotIndex = 19

-- Absolute maximum (rebirth max + premium)
SlotsConfig.MaxTotalSlots = SlotsConfig.MaxRebirthSlots + SlotsConfig.PremiumSlotBonus

-- Grid layout (must match DesignConfig.Base)
SlotsConfig.GridRows = 4
SlotsConfig.GridCols = 5

--- Get number of rebirth-based slots for a given rebirth count
function SlotsConfig.GetSlotsForRebirth(rebirthCount: number): number
	local slots = 1
	for reqRebirth, slotCount in pairs(SlotsConfig.SlotsByRebirth) do
		if rebirthCount >= reqRebirth and slotCount > slots then
			slots = slotCount
		end
	end
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

--- Get the rebirth level needed to unlock a specific slot index
function SlotsConfig.GetRebirthForSlot(slotIndex: number): number
	if slotIndex == SlotsConfig.PremiumSlotIndex then
		return -1 -- premium, not rebirth-based
	end

	local needed = 999
	for reqRebirth, slotCount in pairs(SlotsConfig.SlotsByRebirth) do
		if slotCount >= slotIndex and reqRebirth < needed then
			needed = reqRebirth
		end
	end
	return needed ~= 999 and needed or -1
end

return SlotsConfig
