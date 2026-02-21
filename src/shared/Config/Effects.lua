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
		cashMultiplier = 3,                                -- 3x base cashPerSecond
		rarityMult     = 3,                                -- 3x harder to get
		rollChance     = 0.15,
	},
	{
		name           = "Snow",
		prefix         = "Snow",
		color          = Color3.fromRGB(180, 220, 255),  -- icy light blue
		glowColor      = Color3.fromRGB(130, 180, 240),  -- deeper ice blue glow
		cashMultiplier = 5,                                -- 5x base cashPerSecond
		rarityMult     = 5,                                -- 5x harder to get
		rollChance     = 0.12,
	},
	{
		name           = "Lava",
		prefix         = "Lava",
		color          = Color3.fromRGB(255, 100, 20),   -- hot orange
		glowColor      = Color3.fromRGB(220, 60, 10),    -- deep red-orange glow
		cashMultiplier = 10,                               -- 10x base cashPerSecond
		rarityMult     = 10,                               -- 10x harder to get
		rollChance     = 0.10,
	},
	{
		name           = "Lightning",
		prefix         = "Lightning",
		color          = Color3.fromRGB(255, 255, 80),   -- electric yellow
		glowColor      = Color3.fromRGB(200, 200, 40),   -- golden yellow glow
		cashMultiplier = 15,                               -- 15x base cashPerSecond
		rarityMult     = 15,                               -- 15x harder to get
		rollChance     = 0.08,
	},
	{
		name           = "Shadow",
		prefix         = "Shadow",
		color          = Color3.fromRGB(100, 60, 140),   -- dark purple
		glowColor      = Color3.fromRGB(60, 30, 100),    -- deeper shadow purple
		cashMultiplier = 20,                               -- 20x base cashPerSecond
		rarityMult     = 20,                               -- 20x harder to get
		rollChance     = 0.06,
	},
	{
		name           = "Glitchy",
		prefix         = "Glitchy",
		color          = Color3.fromRGB(0, 255, 255),    -- cyan
		glowColor      = Color3.fromRGB(255, 0, 255),   -- magenta glow (glitch vibe)
		cashMultiplier = 30,                               -- 30x base cashPerSecond
		rarityMult     = 30,                               -- 30x harder to get
		rollChance     = 0.05,
	},
	{
		name           = "Lunar",
		prefix         = "Lunar",
		color          = Color3.fromRGB(200, 220, 255),  -- pale moon blue
		glowColor      = Color3.fromRGB(160, 180, 220),  -- silver-blue glow
		cashMultiplier = 40,                               -- 40x base cashPerSecond
		rarityMult     = 40,                               -- 40x harder to get
		rollChance     = 0.04,
	},
	{
		name           = "Solar",
		prefix         = "Solar",
		color          = Color3.fromRGB(255, 220, 60),    -- bright gold
		glowColor      = Color3.fromRGB(255, 160, 20),  -- orange-gold glow
		cashMultiplier = 50,                               -- 50x base cashPerSecond
		rarityMult     = 50,                               -- 50x harder to get
		rollChance     = 0.035,
	},
	{
		name           = "Void",
		prefix         = "Void",
		color          = Color3.fromRGB(140, 15, 50),    -- deep crimson / wine red
		glowColor      = Color3.fromRGB(70, 5, 25),     -- near-black blood red
		cashMultiplier = 70,                               -- 70x base cashPerSecond
		rarityMult     = 70,                               -- 70x harder to get
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
