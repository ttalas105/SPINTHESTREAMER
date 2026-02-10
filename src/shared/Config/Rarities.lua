--[[
	Rarities.lua
	Rarity tiers with RNG weights, colors, and visual/audio intensity.
	Weight = relative chance in the weighted roll.
]]

local Rarities = {}

Rarities.Tiers = {
	{
		name   = "Common",
		weight = 60,
		color  = Color3.fromRGB(170, 170, 170),
		glowIntensity = 0,
		shakeIntensity = 0,
		soundId = "", -- placeholder: drop in asset id later
	},
	{
		name   = "Rare",
		weight = 25,
		color  = Color3.fromRGB(60, 130, 255),
		glowIntensity = 0.3,
		shakeIntensity = 0,
		soundId = "",
	},
	{
		name   = "Epic",
		weight = 10,
		color  = Color3.fromRGB(170, 60, 255),
		glowIntensity = 0.6,
		shakeIntensity = 3,
		soundId = "",
	},
	{
		name   = "Legendary",
		weight = 4,
		color  = Color3.fromRGB(255, 200, 40),
		glowIntensity = 0.8,
		shakeIntensity = 6,
		soundId = "",
	},
	{
		name   = "Mythic",
		weight = 1,
		color  = Color3.fromRGB(255, 50, 50),
		glowIntensity = 1.0,
		shakeIntensity = 12,
		soundId = "", -- unique server-wide sound
	},
}

-- Build lookup by name
Rarities.ByName = {}
for _, tier in ipairs(Rarities.Tiers) do
	Rarities.ByName[tier.name] = tier
end

-- Ordered names for UI
Rarities.Order = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

-- Total weight (for RNG)
Rarities.TotalWeight = 0
for _, tier in ipairs(Rarities.Tiers) do
	Rarities.TotalWeight = Rarities.TotalWeight + tier.weight
end

return Rarities
