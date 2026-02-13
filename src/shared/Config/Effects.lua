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
		color          = Color3.fromRGB(50, 255, 50),    -- bright green
		glowColor      = Color3.fromRGB(30, 200, 30),    -- darker green glow
		cashMultiplier = 2,                                -- 2x base cashPerSecond
		rarityMult     = 2,                                -- twice as hard to get
		rollChance     = 0.15,                             -- 15% base chance (before rarity penalty)
	},
	{
		name           = "Snow",
		prefix         = "Snow",
		color          = Color3.fromRGB(180, 220, 255),  -- icy light blue
		glowColor      = Color3.fromRGB(130, 180, 240),  -- deeper ice blue glow
		cashMultiplier = 3,                                -- 3x base cashPerSecond
		rarityMult     = 3,                                -- three times as hard to get
		rollChance     = 0.12,                             -- 12% base chance (before rarity penalty → 4%)
	},
	{
		name           = "Lava",
		prefix         = "Lava",
		color          = Color3.fromRGB(255, 100, 20),   -- hot orange
		glowColor      = Color3.fromRGB(220, 60, 10),    -- deep red-orange glow
		cashMultiplier = 4,                                -- 4x base cashPerSecond
		rarityMult     = 4,                                -- four times as hard to get
		rollChance     = 0.10,                             -- 10% base chance (before rarity penalty → 2.5%)
	},
	{
		name           = "Lightning",
		prefix         = "Lightning",
		color          = Color3.fromRGB(255, 255, 80),   -- electric yellow
		glowColor      = Color3.fromRGB(200, 200, 40),   -- golden yellow glow
		cashMultiplier = 5,                                -- 5x base cashPerSecond
		rarityMult     = 5,                                -- five times as hard to get
		rollChance     = 0.08,                             -- 8% base chance (before rarity penalty → 1.6%)
	},
	{
		name           = "Shadow",
		prefix         = "Shadow",
		color          = Color3.fromRGB(100, 60, 140),   -- dark purple
		glowColor      = Color3.fromRGB(60, 30, 100),    -- deeper shadow purple
		cashMultiplier = 6,                                -- 6x base cashPerSecond
		rarityMult     = 6,                                -- six times as hard to get
		rollChance     = 0.06,                             -- 6% base (→ 1% after penalty)
	},
	{
		name           = "Glitchy",
		prefix         = "Glitchy",
		color          = Color3.fromRGB(0, 255, 255),    -- cyan
		glowColor      = Color3.fromRGB(255, 0, 255),   -- magenta glow (glitch vibe)
		cashMultiplier = 7,                                -- 7x base cashPerSecond
		rarityMult     = 7,                                -- seven times as hard to get
		rollChance     = 0.05,                             -- 5% base
	},
	{
		name           = "Lunar",
		prefix         = "Lunar",
		color          = Color3.fromRGB(200, 220, 255),  -- pale moon blue
		glowColor      = Color3.fromRGB(160, 180, 220),  -- silver-blue glow
		cashMultiplier = 8,                                -- 8x base cashPerSecond
		rarityMult     = 8,                                -- eight times as hard to get
		rollChance     = 0.04,                             -- 4% base
	},
	{
		name           = "Solar",
		prefix         = "Solar",
		color          = Color3.fromRGB(255, 220, 60),    -- bright gold
		glowColor      = Color3.fromRGB(255, 160, 20),  -- orange-gold glow
		cashMultiplier = 9,                                -- 9x base cashPerSecond
		rarityMult     = 9,                                -- nine times as hard to get
		rollChance     = 0.035,                            -- 3.5% base
	},
	{
		name           = "Void",
		prefix         = "Void",
		color          = Color3.fromRGB(80, 40, 120),    -- deep void purple
		glowColor      = Color3.fromRGB(40, 20, 80),    -- near-black purple
		cashMultiplier = 10,                               -- 10x base cashPerSecond
		rarityMult     = 10,                               -- ten times as hard to get
		rollChance     = 0.03,                             -- 3% base
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
