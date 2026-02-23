--[[
	Effects.lua
	Streamer effects / subclasses. An effect can be applied to any streamer pull.
	Each effect has:
	  name          – display name
	  color         – UI color (glow, text tint)
	  cashMultiplier – multiplier applied to the streamer's cashPerSecond
	  rarityMult    – how much harder it is to roll (2 = twice as hard)
	  rollChance    – base chance to roll this effect (0-1, before rarity penalty)
	  prefix        – shown before the streamer name (e.g. "Acid Rakai")
]]

local Effects = {}

Effects.List = {
	{
		name           = "Acid",
		prefix         = "Acid",
		color          = Color3.fromRGB(50, 255, 50),
		glowColor      = Color3.fromRGB(30, 200, 30),
		cashMultiplier = 2,
		rarityMult     = 2,
		rollChance     = 0.15,
	},
	{
		name           = "Snow",
		prefix         = "Snow",
		color          = Color3.fromRGB(180, 220, 255),
		glowColor      = Color3.fromRGB(130, 180, 240),
		cashMultiplier = 3,
		rarityMult     = 3,
		rollChance     = 0.12,
	},
	{
		name           = "Lava",
		prefix         = "Lava",
		color          = Color3.fromRGB(255, 100, 20),
		glowColor      = Color3.fromRGB(220, 60, 10),
		cashMultiplier = 5,
		rarityMult     = 5,
		rollChance     = 0.10,
	},
	{
		name           = "Lightning",
		prefix         = "Lightning",
		color          = Color3.fromRGB(255, 255, 80),
		glowColor      = Color3.fromRGB(200, 200, 40),
		cashMultiplier = 8,
		rarityMult     = 8,
		rollChance     = 0.08,
	},
	{
		name           = "Shadow",
		prefix         = "Shadow",
		color          = Color3.fromRGB(100, 60, 140),
		glowColor      = Color3.fromRGB(60, 30, 100),
		cashMultiplier = 12,
		rarityMult     = 12,
		rollChance     = 0.06,
	},
	{
		name           = "Glitchy",
		prefix         = "Glitchy",
		color          = Color3.fromRGB(0, 255, 255),
		glowColor      = Color3.fromRGB(255, 0, 255),
		cashMultiplier = 18,
		rarityMult     = 18,
		rollChance     = 0.05,
	},
	{
		name           = "Lunar",
		prefix         = "Lunar",
		color          = Color3.fromRGB(200, 220, 255),
		glowColor      = Color3.fromRGB(160, 180, 220),
		cashMultiplier = 25,
		rarityMult     = 25,
		rollChance     = 0.04,
	},
	{
		name           = "Solar",
		prefix         = "Solar",
		color          = Color3.fromRGB(255, 220, 60),
		glowColor      = Color3.fromRGB(255, 160, 20),
		cashMultiplier = 35,
		rarityMult     = 35,
		rollChance     = 0.035,
	},
	{
		name           = "Void",
		prefix         = "Void",
		color          = Color3.fromRGB(140, 15, 50),
		glowColor      = Color3.fromRGB(70, 5, 25),
		cashMultiplier = 50,
		rarityMult     = 50,
		rollChance     = 0.03,
	},
}

-- Lookup by name
Effects.ByName = {}
for _, e in ipairs(Effects.List) do
	Effects.ByName[e.name] = e
end

-- No effect (normal pull)
Effects.None = nil  -- effect field will be nil for normal pulls

return Effects
