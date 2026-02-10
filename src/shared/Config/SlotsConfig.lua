--[[
	SlotsConfig.lua
	Defines how many slots unlock per rebirth level.
	Premium Slot = 1 extra slot purchasable with Robux.
]]

local SlotsConfig = {}

-- Number of rebirth-based slots at each rebirth count
-- Key = rebirth count, Value = total rebirth slots unlocked
-- Players always have at least 1 slot (slot 1)
SlotsConfig.SlotsByRebirth = {
	[0] = 1,  -- start with 1 slot
	[1] = 2,
	[2] = 3,
	[3] = 4,
	[5] = 5,
	[8] = 6,
}

-- Maximum possible rebirth-based slots
SlotsConfig.MaxRebirthSlots = 6

-- Premium slot (Robux purchase) adds 1 on top of rebirth slots
SlotsConfig.PremiumSlotBonus = 1

-- Absolute maximum (rebirth max + premium)
SlotsConfig.MaxTotalSlots = SlotsConfig.MaxRebirthSlots + SlotsConfig.PremiumSlotBonus

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

return SlotsConfig
